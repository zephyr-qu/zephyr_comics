//! 压缩包句柄缓存模块 (P0 性能优化)
//!
//! 缓存已打开的 ZIP 文件句柄，避免重复打开同一个文件。
//!
//! # 性能提升
//! - 减少文件打开/关闭开销
//! - 特别适用于预加载多页场景
//! - 默认缓存 5 个句柄

use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;
use zip::ZipArchive;

use crate::error::{ComicError, Result};

/// 默认最大缓存句柄数
const DEFAULT_MAX_HANDLES: usize = 5;

/// The largest single archive entry we will load into memory. A malformed CBZ
/// can declare an arbitrary uncompressed size, so an allocation must never be
/// sized from the ZIP header alone.
const MAX_ENTRY_BYTES: usize = 64 * 1024 * 1024;

/// 缓存统计信息
#[derive(Debug, Clone)]
pub struct ArchiveCacheStats {
    /// 缓存的句柄数量
    pub cached_handles: usize,
    /// 最大句柄数量
    pub max_handles: usize,
    /// 总访问次数
    pub total_accesses: u64,
}

/// 压缩包句柄缓存
pub struct ArchiveCache {
    max_handles: usize,
    access_count: u64,
    archives: HashMap<String, CachedArchive>,
    access_order: Vec<String>,
}

struct CachedArchive {
    archive: ZipArchive<File>,
    file_names: Option<Vec<String>>,
    fingerprint: ArchiveFingerprint,
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct ArchiveFingerprint {
    size: u64,
    modified: Option<SystemTime>,
}

impl ArchiveCache {
    /// 创建新的缓存
    pub fn new(_max_handles: usize) -> Self {
        Self {
            max_handles: _max_handles.max(1),
            access_count: 0,
            archives: HashMap::new(),
            access_order: Vec::new(),
        }
    }

    /// 创建默认配置的缓存
    pub fn with_default_config() -> Self {
        Self::new(DEFAULT_MAX_HANDLES)
    }

    /// 从缓存的 ZIP 句柄读取文件内容。
    ///
    /// 归档源文件由应用层视为只读，因此可以安全地复用打开的句柄；
    /// 句柄数量受 LRU 风格的上限控制。
    pub fn extract_file(&mut self, path: &str, file_name: &str) -> Result<Vec<u8>> {
        self.access_count += 1;

        let cached = self.cached_archive(path)?;
        let archive = &mut cached.archive;

        // 查找并读取文件
        let entry = archive
            .by_name(file_name)
            .map_err(|e| ComicError::FileNotFound(format!("文件不存在：{}", e)))?;

        // Never trust `entry.size()`: it is attacker-controlled for a malformed
        // archive. Cap both the pre-allocation and the bytes actually read, and
        // treat an over-sized entry as a corrupt page rather than truncating it.
        let declared = usize::try_from(entry.size()).unwrap_or(0);
        let mut buffer = Vec::with_capacity(declared.min(MAX_ENTRY_BYTES));
        let read = entry
            .take(MAX_ENTRY_BYTES as u64 + 1)
            .read_to_end(&mut buffer)?;
        if read > MAX_ENTRY_BYTES {
            return Err(ComicError::ArchiveError(format!(
                "压缩包条目过大：{}",
                file_name
            )));
        }

        Ok(buffer)
    }

    /// Reads only the leading bytes needed for lightweight image metadata.
    pub fn extract_file_prefix(
        &mut self,
        path: &str,
        file_name: &str,
        max_bytes: usize,
    ) -> Result<Vec<u8>> {
        self.access_count += 1;

        let cached = self.cached_archive(path)?;
        let archive = &mut cached.archive;
        let entry = archive
            .by_name(file_name)
            .map_err(|e| ComicError::FileNotFound(format!("文件不存在：{}", e)))?;
        let capacity = usize::try_from(entry.size())
            .unwrap_or(max_bytes)
            .min(max_bytes);
        let mut buffer = Vec::with_capacity(capacity);
        entry.take(max_bytes as u64).read_to_end(&mut buffer)?;
        Ok(buffer)
    }

    /// 列出 ZIP 中的所有文件名。
    pub fn list_files(&mut self, path: &str) -> Result<Vec<String>> {
        self.access_count += 1;
        let cached = self.cached_archive(path)?;
        if let Some(file_names) = &cached.file_names {
            return Ok(file_names.clone());
        }

        let archive = &mut cached.archive;
        let mut files = Vec::with_capacity(archive.len());
        for index in 0..archive.len() {
            let entry = archive.by_index(index)?;
            if entry.is_file() {
                files.push(entry.name().to_string());
            }
        }
        cached.file_names = Some(files.clone());
        Ok(files)
    }

    fn ensure_open(&mut self, path: &str) -> Result<()> {
        let fingerprint = Self::fingerprint(path)?;
        if self
            .archives
            .get(path)
            .is_some_and(|cached| cached.fingerprint == fingerprint)
        {
            return Ok(());
        }

        self.archives.remove(path);
        self.access_order.retain(|entry| entry != path);

        let file = File::open(path)
            .map_err(|e| ComicError::FileNotFound(format!("无法打开文件：{}", e)))?;
        let archive = ZipArchive::new(file)
            .map_err(|e| ComicError::ArchiveError(format!("ZIP 解析失败：{}", e)))?;
        self.archives.insert(
            path.to_string(),
            CachedArchive {
                archive,
                file_names: None,
                fingerprint,
            },
        );
        self.access_order.push(path.to_string());
        self.evict_if_needed();
        Ok(())
    }

    fn fingerprint(path: &str) -> Result<ArchiveFingerprint> {
        let metadata = std::fs::metadata(path)
            .map_err(|e| ComicError::FileNotFound(format!("无法打开文件：{}", e)))?;
        Ok(ArchiveFingerprint {
            size: metadata.len(),
            modified: metadata.modified().ok(),
        })
    }

    fn cached_archive(&mut self, path: &str) -> Result<&mut CachedArchive> {
        self.ensure_open(path)?;
        self.touch(path);
        self.archives
            .get_mut(path)
            .ok_or_else(|| ComicError::Internal("压缩包缓存未能打开归档".to_string()))
    }

    fn touch(&mut self, path: &str) {
        self.access_order.retain(|entry| entry != path);
        self.access_order.push(path.to_string());
    }

    fn evict_if_needed(&mut self) {
        while self.archives.len() > self.max_handles {
            let Some(oldest) = self.access_order.first().cloned() else {
                break;
            };
            self.access_order.remove(0);
            self.archives.remove(&oldest);
        }
    }

    /// 清空已打开的归档句柄。
    pub fn clear(&mut self) {
        self.archives.clear();
        self.access_order.clear();
    }

    /// 获取缓存统计
    pub fn get_stats(&self) -> ArchiveCacheStats {
        ArchiveCacheStats {
            cached_handles: self.archives.len(),
            max_handles: self.max_handles,
            total_accesses: self.access_count,
        }
    }

    /// 设置最大缓存句柄数
    pub fn set_max_handles(&mut self, max: usize) {
        self.max_handles = max.max(1);
        self.evict_if_needed();
    }
}

// ============ 全局缓存实例 ============

use once_cell::sync::Lazy;

static GLOBAL_ARCHIVE_CACHE: Lazy<Arc<Mutex<ArchiveCache>>> =
    Lazy::new(|| Arc::new(Mutex::new(ArchiveCache::with_default_config())));

/// 获取全局缓存实例
pub fn get_global_archive_cache() -> Arc<Mutex<ArchiveCache>> {
    GLOBAL_ARCHIVE_CACHE.clone()
}

/// 从全局缓存提取文件
pub fn extract_file_from_cache(path: &str, file_name: &str) -> Result<Vec<u8>> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.extract_file(path, file_name)
}

/// Reads a bounded prefix from a file in the global archive cache.
pub fn extract_file_prefix_from_cache(
    path: &str,
    file_name: &str,
    max_bytes: usize,
) -> Result<Vec<u8>> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.extract_file_prefix(path, file_name, max_bytes)
}

/// 从全局归档缓存列出文件名。
pub fn list_files_from_cache(path: &str) -> Result<Vec<String>> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.list_files(path)
}

/// 设置全局缓存大小
pub fn set_global_cache_size(max_handles: usize) {
    if let Ok(mut cache) = GLOBAL_ARCHIVE_CACHE.lock() {
        cache.set_max_handles(max_handles);
    } else {
        log::error!("压缩包缓存锁中毒，无法设置缓存大小");
    }
}

/// 获取全局缓存统计
pub fn get_global_cache_stats() -> ArchiveCacheStats {
    GLOBAL_ARCHIVE_CACHE
        .lock()
        .map(|cache| cache.get_stats())
        .unwrap_or_else(|e| {
            log::error!("压缩包缓存锁中毒：{}", e);
            ArchiveCacheStats {
                cached_handles: 0,
                max_handles: DEFAULT_MAX_HANDLES,
                total_accesses: 0,
            }
        })
}

/// 清空全局缓存
pub fn clear_global_cache() {
    if let Ok(mut cache) = GLOBAL_ARCHIVE_CACHE.lock() {
        cache.clear();
    }
    log::info!("压缩包缓存已清空");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_creation() {
        let cache = ArchiveCache::new(10);
        let stats = cache.get_stats();
        assert_eq!(stats.cached_handles, 0);
        assert_eq!(stats.max_handles, 10);
    }

    #[test]
    fn test_cache_reuses_open_archive_and_evicts_oldest() {
        let dir = std::env::temp_dir().join(format!("zephyr_archive_cache_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let first = dir.join("first.cbz");
        let second = dir.join("second.cbz");
        write_test_archive(&first, "001.png", b"first");
        write_test_archive(&second, "001.png", b"second");

        let mut cache = ArchiveCache::new(1);
        assert_eq!(
            cache
                .extract_file(first.to_str().unwrap(), "001.png")
                .unwrap(),
            b"first"
        );
        assert_eq!(cache.get_stats().cached_handles, 1);
        assert_eq!(
            cache
                .extract_file(first.to_str().unwrap(), "001.png")
                .unwrap(),
            b"first"
        );
        assert_eq!(cache.get_stats().cached_handles, 1);

        write_test_archive(&first, "001.png", b"updated-content");
        assert_eq!(
            cache
                .extract_file(first.to_str().unwrap(), "001.png")
                .unwrap(),
            b"updated-content"
        );

        cache
            .extract_file(second.to_str().unwrap(), "001.png")
            .unwrap();
        assert_eq!(cache.get_stats().cached_handles, 1);

        let _ = std::fs::remove_dir_all(dir);
    }

    fn write_test_archive(path: &std::path::Path, name: &str, bytes: &[u8]) {
        use std::io::Write;
        let file = File::create(path).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        archive
            .start_file(name, zip::write::FileOptions::default())
            .unwrap();
        archive.write_all(bytes).unwrap();
        archive.finish().unwrap();
    }

    #[test]
    fn test_cache_stats() {
        let mut cache = ArchiveCache::new(5);
        cache.access_count = 100;
        let stats = cache.get_stats();
        assert_eq!(stats.total_accesses, 100);
    }

    #[test]
    fn test_global_cache() {
        let cache1 = get_global_archive_cache();
        let cache2 = get_global_archive_cache();

        // 应该是同一个实例
        assert!(Arc::ptr_eq(&cache1, &cache2));
    }
}

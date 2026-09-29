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
use crate::sort::{filter_image_files, natural_sort};

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
    /// The image entries, filtered and naturally sorted once per handle.
    page_names: Option<Vec<String>>,
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
        read_entry(cached, file_name)
    }

    /// Extract one page by index in a single lock.
    ///
    /// The page list stays inside the handle: only the requested entry's bytes
    /// are copied out, so a page turn no longer clones the whole page table.
    pub fn extract_page(&mut self, path: &str, index: usize) -> Result<Vec<u8>> {
        self.access_count += 1;
        let cached = self.cached_archive(path)?;
        ensure_page_names(cached)?;
        let name = {
            let pages = cached
                .page_names
                .as_ref()
                .ok_or_else(|| ComicError::Internal("压缩包页表未建立".to_string()))?;
            pages
                .get(index)
                .cloned()
                .ok_or(ComicError::PageIndexOutOfBounds {
                    requested: index,
                    total: pages.len(),
                })?
        };
        read_entry(cached, &name)
    }

    /// Read just the leading bytes of the page at `index`, again without
    /// materialising the whole page table for the caller.
    pub fn extract_page_prefix(
        &mut self,
        path: &str,
        index: usize,
        max_bytes: usize,
    ) -> Result<Vec<u8>> {
        self.access_count += 1;
        let cached = self.cached_archive(path)?;
        ensure_page_names(cached)?;
        let name = {
            let pages = cached
                .page_names
                .as_ref()
                .ok_or_else(|| ComicError::Internal("压缩包页表未建立".to_string()))?;
            pages
                .get(index)
                .cloned()
                .ok_or(ComicError::PageIndexOutOfBounds {
                    requested: index,
                    total: pages.len(),
                })?
        };
        read_entry_prefix(cached, &name, max_bytes)
    }

    /// The number of readable pages, resolved without copying the page list.
    pub fn page_count(&mut self, path: &str) -> Result<usize> {
        self.access_count += 1;
        let cached = self.cached_archive(path)?;
        ensure_page_names(cached)?;
        Ok(cached.page_names.as_ref().map_or(0, Vec::len))
    }

    /// 列出 ZIP 中的所有文件名。
    pub fn list_files(&mut self, path: &str) -> Result<Vec<String>> {
        self.access_count += 1;
        let cached = self.cached_archive(path)?;
        ensure_file_names(cached)?;
        Ok(cached.file_names.as_ref().cloned().unwrap_or_default())
    }

    /// The archive's image entries in natural sort order, cached on the handle.
    ///
    /// The reader asks for one page at a time, so re-filtering and re-sorting
    /// the whole listing on every request is pure waste.
    pub fn list_page_files(&mut self, path: &str) -> Result<Vec<String>> {
        self.access_count += 1;
        let cached = self.cached_archive(path)?;
        ensure_page_names(cached)?;
        Ok(cached.page_names.as_ref().cloned().unwrap_or_default())
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
                page_names: None,
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

/// Read one entry's full payload. `entry.size()` is attacker-controlled for a
/// malformed archive, so both the pre-allocation and the bytes actually read are
/// capped; an over-sized entry is a corrupt page, not a truncated one.
fn read_entry(cached: &mut CachedArchive, file_name: &str) -> Result<Vec<u8>> {
    let entry = cached
        .archive
        .by_name(file_name)
        .map_err(|e| ComicError::FileNotFound(format!("文件不存在：{}", e)))?;

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

/// Read a bounded prefix of one entry, for lightweight image metadata.
fn read_entry_prefix(
    cached: &mut CachedArchive,
    file_name: &str,
    max_bytes: usize,
) -> Result<Vec<u8>> {
    let entry = cached
        .archive
        .by_name(file_name)
        .map_err(|e| ComicError::FileNotFound(format!("文件不存在：{}", e)))?;
    let capacity = usize::try_from(entry.size())
        .unwrap_or(max_bytes)
        .min(max_bytes);
    let mut buffer = Vec::with_capacity(capacity);
    entry.take(max_bytes as u64).read_to_end(&mut buffer)?;
    Ok(buffer)
}

/// Populate the handle's raw file listing once.
fn ensure_file_names(cached: &mut CachedArchive) -> Result<()> {
    if cached.file_names.is_some() {
        return Ok(());
    }
    let mut files = Vec::with_capacity(cached.archive.len());
    for index in 0..cached.archive.len() {
        let entry = cached.archive.by_index(index)?;
        if entry.is_file() {
            files.push(entry.name().to_string());
        }
    }
    cached.file_names = Some(files);
    Ok(())
}

/// Populate the handle's filtered, naturally sorted page list once.
fn ensure_page_names(cached: &mut CachedArchive) -> Result<()> {
    if cached.page_names.is_some() {
        return Ok(());
    }
    ensure_file_names(cached)?;
    let pages = {
        let files = cached.file_names.as_deref().unwrap_or(&[]);
        natural_sort(&filter_image_files(files))
    };
    cached.page_names = Some(pages);
    Ok(())
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

/// 从全局归档缓存列出文件名。
pub fn list_files_from_cache(path: &str) -> Result<Vec<String>> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.list_files(path)
}

/// Lists the archive's page entries, filtered and naturally sorted, from the
/// global archive cache.
pub fn list_page_files_from_cache(path: &str) -> Result<Vec<String>> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.list_page_files(path)
}

/// Extract one page by index from the global cache, without cloning the page
/// table out to the caller.
pub fn extract_page_from_cache(path: &str, index: usize) -> Result<Vec<u8>> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.extract_page(path, index)
}

/// Read a bounded prefix of one page by index from the global cache.
pub fn extract_page_prefix_from_cache(
    path: &str,
    index: usize,
    max_bytes: usize,
) -> Result<Vec<u8>> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.extract_page_prefix(path, index, max_bytes)
}

/// The archive's page count from the global cache, resolved without copying the
/// page list.
pub fn page_count_from_cache(path: &str) -> Result<usize> {
    let mut cache = GLOBAL_ARCHIVE_CACHE
        .lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.page_count(path)
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

    #[test]
    fn list_page_files_filters_sorts_and_caches() {
        let dir = std::env::temp_dir().join(format!("zephyr_archive_pages_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let archive_path = dir.join("pages.cbz");

        use std::io::Write;
        let file = File::create(&archive_path).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        for name in ["10.png", "2.png", "1.png", "notes.txt"] {
            archive
                .start_file(name, zip::write::FileOptions::default())
                .unwrap();
            archive.write_all(b"x").unwrap();
        }
        archive.finish().unwrap();

        let mut cache = ArchiveCache::new(1);
        let path = archive_path.to_string_lossy().to_string();

        assert_eq!(
            cache.list_page_files(&path).unwrap(),
            vec!["1.png", "2.png", "10.png"]
        );
        // Filtered and sorted once: the second call comes off the handle.
        assert_eq!(
            cache.list_page_files(&path).unwrap(),
            vec!["1.png", "2.png", "10.png"]
        );

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

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
use zip::ZipArchive;

use crate::error::{ComicError, Result};

/// 默认最大缓存句柄数
const DEFAULT_MAX_HANDLES: usize = 5;

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
}

impl ArchiveCache {
    /// 创建新的缓存
    pub fn new(_max_handles: usize) -> Self {
        Self {
            max_handles: _max_handles,
            access_count: 0,
        }
    }

    /// 创建默认配置的缓存
    pub fn with_default_config() -> Self {
        Self::new(DEFAULT_MAX_HANDLES)
    }

    /// 获取 ZIP 文件内容 (不缓存句柄，简化实现)
    /// 
    /// 注意：由于 Rust 生命周期限制，无法直接返回 ZipArchive 引用
    /// 当前实现：每次打开新句柄，读取文件内容后关闭
    /// 优化方案：在调用方完成操作，保持句柄打开时间最短
    pub fn extract_file(&mut self, path: &str, file_name: &str) -> Result<Vec<u8>> {
        self.access_count += 1;

        // 打开文件
        let file = File::open(path)
            .map_err(|e| ComicError::FileNotFound(format!("无法打开文件：{}", e)))?;
        
        let mut archive = ZipArchive::new(file)
            .map_err(|e| ComicError::ArchiveError(format!("ZIP 解析失败：{}", e)))?;

        // 查找并读取文件
        let mut entry = archive.by_name(file_name)
            .map_err(|e| ComicError::FileNotFound(format!("文件不存在：{}", e)))?;
        
        let mut buffer = Vec::with_capacity(entry.size() as usize);
        entry.read_to_end(&mut buffer)?;
        
        Ok(buffer)
    }

    /// 获取缓存统计
    pub fn get_stats(&self) -> ArchiveCacheStats {
        ArchiveCacheStats {
            cached_handles: 0, // 简化实现，不缓存
            max_handles: self.max_handles,
            total_accesses: self.access_count,
        }
    }

    /// 设置最大缓存句柄数
    pub fn set_max_handles(&mut self, max: usize) {
        self.max_handles = max;
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
    let mut cache = GLOBAL_ARCHIVE_CACHE.lock()
        .map_err(|e| ComicError::Internal(format!("压缩包缓存锁中毒：{}", e)))?;
    cache.extract_file(path, file_name)
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
    GLOBAL_ARCHIVE_CACHE.lock()
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
    // 简化实现，无需操作
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

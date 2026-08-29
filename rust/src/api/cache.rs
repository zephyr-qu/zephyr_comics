//! 内存/磁盘/压缩包缓存的统计、限值与清理接口。



use flutter_rust_bridge::frb;
use crate::archive_cache::{clear_global_cache, get_global_cache_stats, set_global_cache_size, ArchiveCacheStats};
use crate::disk_cache::DiskCacheStats;
use crate::error::{ComicError, Result};
use crate::api::init::{IMAGE_CACHE, DISK_CACHE, DEFAULT_CACHE_SIZE_MB};

/// 获取缓存统计信息
#[frb(sync)]
pub fn get_cache_stats() -> crate::cache::CacheStats {
    if let Some(cache) = IMAGE_CACHE.get() {
        cache.get_stats()
    } else {
        crate::cache::CacheStats {
            cached_images: 0,
            current_memory: 0,
            max_memory: DEFAULT_CACHE_SIZE_MB * 1024 * 1024,
            memory_usage_percent: 0,
        }
    }
}

/// 清除缓存
///
/// 释放所有缓存的图片数据。
#[frb(sync)]
pub fn clear_cache() {
    log::info!("清除缓存");
    if let Some(cache) = IMAGE_CACHE.get() {
        cache.clear();
    }
}

/// 设置缓存大小限制
///
/// # 参数
/// * `max_memory_mb` - 最大内存占用 (MB)
#[frb(sync)]
pub fn set_cache_limit(max_memory_mb: i32) {
    if max_memory_mb > 0 {
        log::info!("设置缓存限制：{}MB", max_memory_mb);
        // 注意：OnceLock 只能设置一次，运行时修改需要重新初始化引擎
        log::warn!("缓存限制需要在初始化时设置，运行时修改需要重新初始化引擎");
    }
}

/// 获取磁盘缓存统计信息
#[frb(sync)]
pub fn get_disk_cache_stats() -> DiskCacheStats {
    if let Some(cache) = DISK_CACHE.get() {
        cache.get_stats()
    } else {
        DiskCacheStats {
            cached_images: 0,
            current_size: 0,
            max_size: 500 * 1024 * 1024,
            cache_dir: String::new(),
        }
    }
}

/// 清除磁盘缓存
#[frb(sync)]
pub fn clear_disk_cache() -> Result<()> {
    log::info!("清除磁盘缓存");
    if let Some(cache) = DISK_CACHE.get() {
        cache.clear()
    } else {
        Err(ComicError::CacheError("磁盘缓存未初始化".to_string()))
    }
}

/// 设置磁盘缓存大小限制
///
/// # 注意
/// 此设置需要在初始化时生效，运行时修改需要重新初始化
#[frb(sync)]
pub fn set_disk_cache_limit(max_size_mb: i32) {
    if max_size_mb > 0 {
        log::info!("设置磁盘缓存限制：{}MB", max_size_mb);
        log::warn!("磁盘缓存限制需要在初始化时设置");
    }
}

/// 设置压缩包缓存大小
///
/// # 参数
/// * `max_handles` - 最大缓存句柄数 (推荐 5-10)
#[frb(sync)]
pub fn set_archive_cache_size(max_handles: i32) {
    if max_handles > 0 {
        log::info!("设置压缩包缓存大小：{}", max_handles);
        set_global_cache_size(max_handles as usize);
    }
}

/// 获取压缩包缓存统计
#[frb(sync)]
pub fn get_archive_cache_stats() -> ArchiveCacheStats {
    get_global_cache_stats()
}

/// 清空压缩包缓存
#[frb(sync)]
pub fn clear_archive_cache() {
    log::info!("清空压缩包缓存");
    clear_global_cache();
}

#[cfg(test)]
mod tests {
    use crate::api::init::init_app;
    use super::*;

    #[test]
    fn test_cache_stats() {
        init_app();
        let stats = get_cache_stats();
        assert!(stats.max_memory > 0);
    }

    #[test]
    fn test_disk_cache_stats() {
        init_app();
        let stats = get_disk_cache_stats();
        assert!(stats.max_size > 0);
    }

    #[test]
    fn test_archive_cache() {
        init_app();
        let stats = get_archive_cache_stats();
        assert!(stats.max_handles >= 5);
        set_archive_cache_size(10);
        let stats = get_archive_cache_stats();
        assert_eq!(stats.max_handles, 10);
    }
}


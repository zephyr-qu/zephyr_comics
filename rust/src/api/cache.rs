//! 派生缓存（封面/缩略图）的统计与清理接口。
//!
//! 页面解码结果不再进 Rust 缓存：阅读器传原始编码字节、由 Flutter 侧按显示
//! 尺寸解码并缓存。这里统计的是真正落盘的派生数据 —— 库表里的封面。

use crate::error::{ComicError, Result};
use crate::library_db::{get_global_db, DerivedCacheStats};
use flutter_rust_bridge::frb;

const EMPTY: DerivedCacheStats = DerivedCacheStats {
    bytes: 0,
    entries: 0,
};

/// 获取派生缓存统计信息
#[frb(sync)]
pub fn get_derived_cache_stats() -> DerivedCacheStats {
    let Some(db) = get_global_db() else {
        return EMPTY;
    };
    db.derived_cache_stats().unwrap_or_else(|error| {
        log::warn!("读取派生缓存统计失败：{}", error);
        EMPTY
    })
}

/// 清除派生缓存
///
/// 只删除封面数据（下次扫描重建）；源漫画文件与阅读进度都不受影响。
#[frb(sync)]
pub fn clear_derived_cache() -> Result<()> {
    log::info!("清除派生缓存");
    let Some(db) = get_global_db() else {
        return Err(ComicError::Internal("数据库未初始化".to_string()));
    };
    db.clear_derived_covers()
}

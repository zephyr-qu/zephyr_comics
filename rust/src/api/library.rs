//! 图书馆扫描、查询与管理接口。

use crate::error::{ComicError, Result};
use crate::library_db::{get_global_db, LibraryEntry};
use flutter_rust_bridge::frb;

/// 扫描目录添加到图书馆
///
/// # 参数
/// * `path` - 目录路径
#[frb(dart_async)]
pub async fn scan_directory_to_library(path: String) -> Result<Vec<LibraryEntry>> {
    let db = get_global_db().ok_or_else(|| ComicError::Internal("数据库未初始化".to_string()))?;

    // The database is shared (its connection locks per statement), so the scan
    // does not hold a lock across the file IO and image decoding it performs.
    tokio::task::spawn_blocking(move || {
        crate::library_scanner::scan_directory_to_library(&db, &path)
    })
    .await
    .map_err(|error| ComicError::Internal(format!("扫描任务失败：{}", error)))?
}

/// 获取图书馆所有漫画
#[frb(sync)]
pub fn get_library_entries() -> Vec<LibraryEntry> {
    if let Some(db) = get_global_db() {
        db.get_library_entries().unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 搜索图书馆
///
/// # 参数
/// * `query` - 搜索关键词
#[frb(sync)]
pub fn search_library(query: String) -> Vec<LibraryEntry> {
    if let Some(db) = get_global_db() {
        db.search_library(&query).unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取最近添加的漫画
///
/// # 参数
/// * `limit` - 返回数量限制
#[frb(sync)]
pub fn get_recently_added(limit: i32) -> Vec<LibraryEntry> {
    if let Some(db) = get_global_db() {
        db.get_recently_added(limit as usize).unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 从图书馆移除
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn remove_from_library(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        db.remove_from_library(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 更新最后打开时间
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn update_last_opened(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        db.update_last_opened(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::init::init_app;

    #[test]
    fn test_library_operations() {
        init_app();

        let entries = get_library_entries();
        assert!(entries.is_empty());

        let results = search_library("test".to_string());
        assert!(results.is_empty());
    }
}

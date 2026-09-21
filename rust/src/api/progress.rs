//! 阅读进度、书签、历史与阅读统计接口。

use crate::error::{ComicError, Result};
use crate::library_db::get_global_db;
use crate::reading_progress::{current_timestamp, Bookmark, ReadingProgress, ReadingStats};
use flutter_rust_bridge::frb;
use std::sync::{Arc, Mutex};

/// 保存阅读进度，Rust 侧统一计算完成度与时间戳
///
/// # 参数
/// * `file_path` - 漫画文件完整路径
/// * `page_index` - 当前页面索引 (从 0 开始)
/// * `total_pages` - 漫画总页数
#[frb(sync)]
pub fn save_reading_progress(
    file_path: String,
    page_index: usize,
    total_pages: usize,
) -> Result<()> {
    let page = page_index.min(total_pages.saturating_sub(1));
    let progress = ReadingProgress {
        file_path,
        chapter_index: 0,
        page_index: page,
        last_read_timestamp: current_timestamp(),
        completion_percent: ReadingProgress::completion_percent(page, total_pages),
    };
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.save_reading_progress(&progress)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 获取阅读进度
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn get_reading_progress(file_path: String) -> Option<ReadingProgress> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()?
            .get_reading_progress(&file_path)
            .ok()
            .flatten()
    } else {
        None
    }
}

/// 获取阅读历史
///
/// # 参数
/// * `limit` - 返回数量限制
async fn read_reading_history(
    db: Arc<Mutex<crate::library_db::LibraryDatabase>>,
    limit: usize,
) -> Result<Vec<ReadingProgress>> {
    tokio::task::spawn_blocking(move || {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.get_reading_history(limit)
    })
    .await
    .map_err(|error| ComicError::Internal(format!("读取阅读历史任务失败：{}", error)))?
}

#[frb(dart_async)]
pub async fn get_reading_history(limit: i32) -> Result<Vec<ReadingProgress>> {
    let db = get_global_db().ok_or_else(|| ComicError::Internal("数据库未初始化".to_string()))?;
    read_reading_history(db, limit.max(0) as usize).await
}

/// Hide one history entry without deleting its progress or bookmarks.
#[frb(sync)]
pub fn hide_reading_history(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.hide_reading_history(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 删除阅读进度
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn remove_reading_progress(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.remove_reading_progress(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 添加书签
///
/// # 参数
/// * `file_path` - 文件路径
/// * `page_index` - 页面索引
/// * `note` - 备注 (可选)
#[frb(sync)]
pub fn add_bookmark(file_path: String, page_index: i32, note: Option<String>) -> Result<Bookmark> {
    let bookmark = Bookmark::new(file_path, page_index as usize, note);

    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.add_bookmark(&bookmark)?;
        Ok(bookmark)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 移除书签
///
/// # 参数
/// * `file_path` - 文件路径
/// * `page_index` - 页面索引
#[frb(sync)]
pub fn remove_bookmark(file_path: String, page_index: i32) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.remove_bookmark(&file_path, page_index as usize)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 获取书签列表
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn get_bookmarks(file_path: String) -> Vec<Bookmark> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_bookmarks(&file_path).ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取所有书签
#[frb(sync)]
pub fn get_all_bookmarks() -> Vec<Bookmark> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_all_bookmarks().ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取阅读统计
#[frb(sync)]
pub fn get_reading_stats() -> ReadingStats {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_reading_stats().ok())
            .unwrap_or_default()
    } else {
        ReadingStats::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::init::init_app;

    #[tokio::test]
    async fn reading_history_propagates_database_lock_failure() {
        let path = std::env::temp_dir().join(format!(
            "zephyr-reading-history-poison-{}.db",
            std::process::id()
        ));
        let db = crate::library_db::LibraryDatabase::new(Some(path.clone())).unwrap();
        let db = Arc::new(Mutex::new(db));
        let poisoned = Arc::clone(&db);

        let _ = std::thread::spawn(move || {
            let _guard = poisoned.lock().unwrap();
            panic!("poison the database lock for the regression test");
        })
        .join();

        let result = read_reading_history(db, 100).await;
        assert!(matches!(
            result,
            Err(ComicError::Internal(message)) if message.contains("数据库锁中毒")
        ));
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn test_reading_progress() {
        init_app();

        assert!(save_reading_progress("test.cbz".to_string(), 0, 50).is_ok());
        let first = get_reading_progress("test.cbz".to_string()).unwrap();
        assert_eq!(first.page_index, 0);
        assert_eq!(first.completion_percent, 0.0);

        assert!(save_reading_progress("test.cbz".to_string(), 25, 50).is_ok());
        let mid = get_reading_progress("test.cbz".to_string()).unwrap();
        assert_eq!(mid.page_index, 25);
        assert!((mid.completion_percent - 50.0).abs() < 0.1);

        assert!(save_reading_progress("test.cbz".to_string(), 49, 50).is_ok());
        let last = get_reading_progress("test.cbz".to_string()).unwrap();
        assert_eq!(last.completion_percent, 100.0);

        assert!(save_reading_progress("test.cbz".to_string(), 500, 50).is_ok());
        let clamped = get_reading_progress("test.cbz".to_string()).unwrap();
        assert_eq!(clamped.page_index, 49);
        assert_eq!(clamped.completion_percent, 100.0);
    }

    #[test]
    fn test_bookmark() {
        init_app();

        let result = add_bookmark("test.cbz".to_string(), 10, Some("test".to_string()));
        assert!(result.is_ok());

        let bookmarks = get_bookmarks("test.cbz".to_string());
        assert_eq!(bookmarks.len(), 1);

        remove_bookmark("test.cbz".to_string(), 10).unwrap();
        let bookmarks = get_bookmarks("test.cbz".to_string());
        assert!(bookmarks.is_empty());
    }
}

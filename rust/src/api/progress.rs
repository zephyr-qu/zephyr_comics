//! 阅读进度、书签、历史与阅读统计接口。

use crate::error::{ComicError, Result};
use crate::library_db::{get_global_db, LibraryDatabase};
use crate::reading_progress::{current_timestamp, Bookmark, ReadingProgress, ReadingStats};
use flutter_rust_bridge::frb;
use std::sync::Arc;

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
        db.save_reading_progress(&progress)
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
        db.get_reading_progress(&file_path).ok().flatten()
    } else {
        None
    }
}

/// 获取阅读历史
///
/// # 参数
/// * `limit` - 返回数量限制
async fn read_reading_history(
    db: Arc<LibraryDatabase>,
    limit: usize,
) -> Result<Vec<ReadingProgress>> {
    tokio::task::spawn_blocking(move || db.get_reading_history(limit))
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
        db.hide_reading_history(&file_path)
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
        db.remove_reading_progress(&file_path)
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
        db.add_bookmark(&bookmark)?;
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
        db.remove_bookmark(&file_path, page_index as usize)
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
        db.get_bookmarks(&file_path).unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取所有书签
#[frb(sync)]
pub fn get_all_bookmarks() -> Vec<Bookmark> {
    if let Some(db) = get_global_db() {
        db.get_all_bookmarks().unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取阅读统计
#[frb(sync)]
pub fn get_reading_stats() -> ReadingStats {
    if let Some(db) = get_global_db() {
        db.get_reading_stats().unwrap_or_default()
    } else {
        ReadingStats::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::init::init_app;

    #[tokio::test]
    async fn reading_history_reads_through_the_shared_database() {
        let path =
            std::env::temp_dir().join(format!("zephyr-reading-history-{}.db", std::process::id()));
        let db = Arc::new(LibraryDatabase::new(Some(path.clone())).unwrap());
        db.save_reading_progress(&ReadingProgress::new("history.cbz".to_string(), 0, 7))
            .unwrap();

        let history = read_reading_history(Arc::clone(&db), 100).await.unwrap();
        assert_eq!(history.len(), 1);
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

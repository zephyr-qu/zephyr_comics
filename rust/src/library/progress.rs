//! 阅读进度和书签模块
//!
//! 管理用户的阅读进度和书签。

/// 阅读进度
///
/// 记录用户在漫画中的阅读位置。
#[derive(Debug, Clone)]
pub struct ReadingProgress {
    /// 文件完整路径
    pub file_path: String,
    /// 章节索引 (从 0 开始)
    pub chapter_index: usize,
    /// 页面索引 (从 0 开始)
    pub page_index: usize,
    /// 最后阅读时间戳 (毫秒)
    pub last_read_timestamp: u64,
    /// 完成度百分比 (0.0 - 100.0)
    pub completion_percent: f32,
}

impl ReadingProgress {
    /// 创建新的阅读进度
    pub fn new(file_path: String, chapter_index: usize, page_index: usize) -> Self {
        Self {
            file_path,
            chapter_index,
            page_index,
            last_read_timestamp: current_timestamp(),
            completion_percent: 0.0,
        }
    }

    /// 页面进入完成度：末页记 100%，否则按占比。index 内部 clamp 到 [0, total-1]。
    pub fn completion_percent(page_index: usize, total_pages: usize) -> f32 {
        if total_pages == 0 {
            return 0.0;
        }
        let page = page_index.min(total_pages - 1);
        if page + 1 >= total_pages {
            100.0
        } else {
            (page as f32 / total_pages as f32) * 100.0
        }
    }
}

/// 书签
///
/// 用户可以在任意页面添加书签。
#[derive(Debug, Clone)]
pub struct Bookmark {
    /// 文件完整路径
    pub file_path: String,
    /// 页面索引 (从 0 开始)
    pub page_index: usize,
    /// 备注 (可选)
    pub note: Option<String>,
    /// 创建时间戳 (毫秒)
    pub created_at: u64,
}

impl Bookmark {
    /// 创建新的书签
    pub fn new(file_path: String, page_index: usize, note: Option<String>) -> Self {
        Self {
            file_path,
            page_index,
            note,
            created_at: current_timestamp(),
        }
    }
}

/// 阅读统计
///
/// 用户的阅读行为统计信息。
#[derive(Debug, Clone, Default)]
pub struct ReadingStats {
    /// 已读完的漫画数量
    pub total_comics_read: usize,
    /// 已阅读的总页数
    pub total_pages_read: usize,
    /// 总阅读时间 (分钟)
    pub reading_time_minutes: u64,
    /// 本周每天阅读页数 (7 天)
    pub weekly_activity: Vec<u32>,
}

/// 获取当前时间戳 (毫秒)
pub fn current_timestamp() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reading_progress_creation() {
        let progress = ReadingProgress::new("test.cbz".to_string(), 0, 5);
        assert_eq!(progress.file_path, "test.cbz");
        assert_eq!(progress.chapter_index, 0);
        assert_eq!(progress.page_index, 5);
        assert!(progress.last_read_timestamp > 0);
    }

    #[test]
    fn completion_percent_last_page_is_100() {
        assert_eq!(ReadingProgress::completion_percent(0, 50), 0.0);
        assert!((ReadingProgress::completion_percent(24, 50) - 48.0).abs() < 0.1);
        assert_eq!(ReadingProgress::completion_percent(49, 50), 100.0);
    }

    #[test]
    fn completion_percent_clamps_out_of_range_index() {
        assert_eq!(ReadingProgress::completion_percent(500, 50), 100.0);
        assert_eq!(ReadingProgress::completion_percent(0, 0), 0.0);
    }

    #[test]
    fn test_bookmark_creation() {
        let bookmark = Bookmark::new("test.cbz".to_string(), 10, Some("重要页面".to_string()));
        assert_eq!(bookmark.page_index, 10);
        assert_eq!(bookmark.note, Some("重要页面".to_string()));
        assert!(bookmark.created_at > 0);
    }

    #[test]
    fn test_bookmark_without_note() {
        let bookmark = Bookmark::new("test.cbz".to_string(), 10, None);
        assert!(bookmark.note.is_none());
    }
}

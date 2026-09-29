//! 图书馆数据库模块
//!
//! 使用 SQLite 存储阅读进度、书签和漫画库信息。

use rusqlite::{params, Connection, OptionalExtension};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use crate::error::{ComicError, Result};
use crate::reading_progress::{current_timestamp, Bookmark, ReadingProgress, ReadingStats};

/// 数据库包装器
pub struct LibraryDatabase {
    conn: Arc<Mutex<Connection>>,
}

fn db_err<T: std::fmt::Display>(msg: &str, e: T) -> ComicError {
    ComicError::Internal(format!("{}: {}", msg, e))
}

impl LibraryDatabase {
    /// 创建或打开数据库
    pub fn new(db_path: Option<PathBuf>) -> Result<Self> {
        let path = db_path.unwrap_or_else(|| {
            let mut path = std::env::temp_dir();
            path.push("zephyr_comics");
            path.push("library.db");
            path
        });

        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        let conn = Connection::open(&path).map_err(|e| db_err("无法打开数据库", e))?;

        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
        };

        db.init_tables()?;

        Ok(db)
    }

    /// Lock the connection, recovering from a poisoned mutex instead of
    /// panicking. A panic in one query must not make every later call panic:
    /// SQLite's connection stays usable, so the guard is recovered in place.
    fn conn(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.conn.lock().unwrap_or_else(|error| {
            log::error!("数据库连接锁中毒，继续使用连接：{}", error);
            error.into_inner()
        })
    }

    /// 初始化数据库表
    fn init_tables(&self) -> Result<()> {
        let conn = self.conn();

        conn.execute(
            "CREATE TABLE IF NOT EXISTS reading_progress (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT NOT NULL UNIQUE,
                chapter_index INTEGER NOT NULL DEFAULT 0,
                page_index INTEGER NOT NULL DEFAULT 0,
                last_read_timestamp INTEGER NOT NULL,
                completion_percent REAL NOT NULL DEFAULT 0.0,
                history_visible INTEGER NOT NULL DEFAULT 1
            )",
            [],
        )
        .map_err(|e| db_err("创建表失败", e))?;

        // Forward migration for databases created before history visibility
        // was separated from progress. Never delete or recreate user data.
        let _ = conn.execute(
            "ALTER TABLE reading_progress ADD COLUMN history_visible INTEGER NOT NULL DEFAULT 1",
            [],
        );

        conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, version INTEGER NOT NULL)",
            [],
        )
        .map_err(|e| db_err("创建 schema 版本表失败", e))?;
        conn.execute(
            "INSERT INTO schema_meta(key, version) VALUES ('library', 2)
             ON CONFLICT(key) DO UPDATE SET version = MAX(version, excluded.version)",
            [],
        )
        .map_err(|e| db_err("写入 schema 版本失败", e))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS bookmarks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                note TEXT,
                created_at INTEGER NOT NULL,
                UNIQUE(file_path, page_index)
            )",
            [],
        )
        .map_err(|e| db_err("创建表失败", e))?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS library (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT NOT NULL UNIQUE,
                title TEXT,
                author TEXT,
                publisher TEXT,
                description TEXT,
                genres TEXT,
                year INTEGER,
                format TEXT,
                file_size INTEGER,
                total_pages INTEGER,
                cover_data BLOB,
                added_at INTEGER NOT NULL,
                last_opened_at INTEGER,
                modified_at INTEGER NOT NULL DEFAULT 0
            )",
            [],
        )
        .map_err(|e| db_err("创建表失败", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_library_title ON library(title)",
            [],
        )
        .map_err(|e| db_err("创建索引失败", e))?;

        // Existing MVP databases predate the scanner fingerprint. Keep them
        // readable and let the next successful scan populate the value.
        let _ = conn.execute(
            "ALTER TABLE library ADD COLUMN modified_at INTEGER NOT NULL DEFAULT 0",
            [],
        );

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_library_added ON library(added_at)",
            [],
        )
        .map_err(|e| db_err("创建索引失败", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_bookmarks_file ON bookmarks(file_path)",
            [],
        )
        .map_err(|e| db_err("创建索引失败", e))?;

        Ok(())
    }

    /// 保存阅读进度
    pub fn save_reading_progress(&self, progress: &ReadingProgress) -> Result<()> {
        let conn = self.conn();

        conn.execute(
            "INSERT OR REPLACE INTO reading_progress 
             (file_path, chapter_index, page_index, last_read_timestamp, completion_percent)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                progress.file_path,
                progress.chapter_index,
                progress.page_index,
                progress.last_read_timestamp,
                progress.completion_percent,
            ],
        )
        .map_err(|e| db_err("保存进度失败", e))?;

        Ok(())
    }

    /// 获取阅读进度
    pub fn get_reading_progress(&self, file_path: &str) -> Result<Option<ReadingProgress>> {
        let conn = self.conn();

        let mut stmt = conn.prepare(
            "SELECT file_path, chapter_index, page_index, last_read_timestamp, completion_percent
             FROM reading_progress WHERE file_path = ?1",
        ).map_err(|e| db_err("准备语句失败", e))?;

        let progress = stmt
            .query_row(params![file_path], |row| {
                Ok(ReadingProgress {
                    file_path: row.get(0)?,
                    chapter_index: row.get(1)?,
                    page_index: row.get(2)?,
                    last_read_timestamp: row.get(3)?,
                    completion_percent: row.get(4)?,
                })
            })
            .optional()
            .map_err(|e| db_err("查询失败", e))?;

        Ok(progress)
    }

    /// 获取阅读历史
    pub fn get_reading_history(&self, limit: usize) -> Result<Vec<ReadingProgress>> {
        let conn = self.conn();

        let mut stmt = conn.prepare(
            "SELECT file_path, chapter_index, page_index, last_read_timestamp, completion_percent
             FROM reading_progress
             WHERE history_visible = 1
             ORDER BY last_read_timestamp DESC LIMIT ?1",
        ).map_err(|e| db_err("准备语句失败", e))?;

        let progress_iter = stmt
            .query_map(params![limit], |row| {
                Ok(ReadingProgress {
                    file_path: row.get(0)?,
                    chapter_index: row.get(1)?,
                    page_index: row.get(2)?,
                    last_read_timestamp: row.get(3)?,
                    completion_percent: row.get(4)?,
                })
            })
            .map_err(|e| db_err("查询失败", e))?;

        let mut progress_list = Vec::new();
        for progress in progress_iter {
            progress_list.push(progress.map_err(|e| db_err("读取行失败", e))?);
        }

        Ok(progress_list)
    }

    /// Hide a history entry while preserving progress and bookmarks.
    pub fn hide_reading_history(&self, file_path: &str) -> Result<()> {
        let conn = self.conn();
        conn.execute(
            "UPDATE reading_progress SET history_visible = 0 WHERE file_path = ?1",
            params![file_path],
        )
        .map_err(|e| db_err("删除历史失败", e))?;
        Ok(())
    }

    /// 删除阅读进度
    pub fn remove_reading_progress(&self, file_path: &str) -> Result<()> {
        let conn = self.conn();

        conn.execute(
            "DELETE FROM reading_progress WHERE file_path = ?1",
            params![file_path],
        )
        .map_err(|e| db_err("删除失败", e))?;

        Ok(())
    }

    /// 添加书签
    pub fn add_bookmark(&self, bookmark: &Bookmark) -> Result<()> {
        let conn = self.conn();

        conn.execute(
            "INSERT OR REPLACE INTO bookmarks (file_path, page_index, note, created_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![
                bookmark.file_path,
                bookmark.page_index,
                bookmark.note,
                bookmark.created_at,
            ],
        )
        .map_err(|e| db_err("添加书签失败", e))?;

        Ok(())
    }

    /// 移除书签
    pub fn remove_bookmark(&self, file_path: &str, page_index: usize) -> Result<()> {
        let conn = self.conn();

        conn.execute(
            "DELETE FROM bookmarks WHERE file_path = ?1 AND page_index = ?2",
            params![file_path, page_index],
        )
        .map_err(|e| db_err("删除书签失败", e))?;

        Ok(())
    }

    /// 获取书签列表
    pub fn get_bookmarks(&self, file_path: &str) -> Result<Vec<Bookmark>> {
        let conn = self.conn();

        let mut stmt = conn
            .prepare(
                "SELECT file_path, page_index, note, created_at
             FROM bookmarks WHERE file_path = ?1 ORDER BY page_index ASC",
            )
            .map_err(|e| db_err("准备语句失败", e))?;

        let bookmark_iter = stmt
            .query_map(params![file_path], |row| {
                Ok(Bookmark {
                    file_path: row.get(0)?,
                    page_index: row.get(1)?,
                    note: row.get(2)?,
                    created_at: row.get(3)?,
                })
            })
            .map_err(|e| db_err("查询失败", e))?;

        let mut bookmarks = Vec::new();
        for bookmark in bookmark_iter {
            bookmarks.push(bookmark.map_err(|e| db_err("读取行失败", e))?);
        }

        Ok(bookmarks)
    }

    /// 获取所有书签
    pub fn get_all_bookmarks(&self) -> Result<Vec<Bookmark>> {
        let conn = self.conn();

        let mut stmt = conn
            .prepare(
                "SELECT file_path, page_index, note, created_at
             FROM bookmarks ORDER BY created_at DESC",
            )
            .map_err(|e| db_err("准备语句失败", e))?;

        let bookmark_iter = stmt
            .query_map([], |row| {
                Ok(Bookmark {
                    file_path: row.get(0)?,
                    page_index: row.get(1)?,
                    note: row.get(2)?,
                    created_at: row.get(3)?,
                })
            })
            .map_err(|e| db_err("查询失败", e))?;

        let mut bookmarks = Vec::new();
        for bookmark in bookmark_iter {
            bookmarks.push(bookmark.map_err(|e| db_err("读取行失败", e))?);
        }

        Ok(bookmarks)
    }

    /// 获取阅读统计
    pub fn get_reading_stats(&self) -> Result<ReadingStats> {
        let conn = self.conn();

        let total_comics: usize = conn
            .query_row(
                "SELECT COUNT(*) FROM reading_progress WHERE completion_percent >= 99.0",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let total_pages: usize = conn
            .query_row(
                "SELECT COALESCE(SUM(page_index), 0) FROM reading_progress",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        Ok(ReadingStats {
            total_comics_read: total_comics,
            total_pages_read: total_pages,
            reading_time_minutes: 0,
            weekly_activity: vec![0; 7],
        })
    }

    /// 添加漫画到库
    pub fn add_to_library(&self, entry: &LibraryEntry) -> Result<()> {
        let conn = self.conn();
        let modified_at = std::fs::metadata(&entry.file_path)
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|duration| duration.as_nanos() as u64)
            .unwrap_or_default();

        conn.execute(
            "INSERT INTO library
             (file_path, title, author, publisher, description, genres, year, 
              format, file_size, total_pages, cover_data, added_at, last_opened_at, modified_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
             ON CONFLICT(file_path) DO UPDATE SET
               title = excluded.title,
               author = excluded.author,
               publisher = excluded.publisher,
               description = excluded.description,
               genres = excluded.genres,
               year = excluded.year,
               format = excluded.format,
               file_size = excluded.file_size,
               total_pages = excluded.total_pages,
               cover_data = excluded.cover_data,
               modified_at = excluded.modified_at",
            params![
                entry.file_path,
                entry.title,
                entry.author,
                entry.publisher,
                entry.description,
                entry.genres.join(","),
                entry.year,
                entry.format,
                entry.file_size,
                entry.total_pages,
                entry.cover_data,
                entry.added_at,
                entry.last_opened_at,
                modified_at,
            ],
        )
        .map_err(|e| db_err("添加到图书馆失败", e))?;

        Ok(())
    }

    /// Return the persisted size/mtime fingerprint used by incremental scans.
    /// This remains an implementation seam and is intentionally not exposed
    /// through the generated Flutter `LibraryEntry` shape.
    pub fn get_file_fingerprint(&self, file_path: &str) -> Result<Option<(u64, u64)>> {
        let conn = self.conn();
        conn.query_row(
            "SELECT file_size, modified_at FROM library WHERE file_path = ?1",
            params![file_path],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|e| db_err("查询文件指纹失败", e))
    }

    /// 从库中移除
    pub fn remove_from_library(&self, file_path: &str) -> Result<()> {
        let conn = self.conn();

        conn.execute(
            "DELETE FROM library WHERE file_path = ?1",
            params![file_path],
        )
        .map_err(|e| db_err("删除失败", e))?;

        Ok(())
    }

    /// 获取库中所有漫画
    pub fn get_library_entries(&self) -> Result<Vec<LibraryEntry>> {
        let conn = self.conn();

        let mut stmt = conn
            .prepare(
                "SELECT file_path, title, author, publisher, description, genres, year,
                    format, file_size, total_pages, cover_data, added_at, last_opened_at
             FROM library ORDER BY added_at DESC",
            )
            .map_err(|e| db_err("准备语句失败", e))?;

        let iter = stmt
            .query_map([], |row| {
                Ok(LibraryEntry {
                    file_path: row.get(0)?,
                    title: row.get(1)?,
                    author: row.get(2)?,
                    publisher: row.get(3)?,
                    description: row.get(4)?,
                    genres: row
                        .get::<_, String>(5)?
                        .split(',')
                        .map(|s| s.to_string())
                        .collect(),
                    year: row.get(6)?,
                    format: row.get(7)?,
                    file_size: row.get(8)?,
                    total_pages: row.get(9)?,
                    cover_data: row.get(10)?,
                    added_at: row.get(11)?,
                    last_opened_at: row.get(12)?,
                })
            })
            .map_err(|e| db_err("查询失败", e))?;

        let mut entries = Vec::new();
        for entry in iter {
            entries.push(entry.map_err(|e| db_err("读取行失败", e))?);
        }

        Ok(entries)
    }

    /// 搜索漫画
    pub fn search_library(&self, query: &str) -> Result<Vec<LibraryEntry>> {
        let conn = self.conn();
        let search_pattern = format!("%{}%", query);

        let mut stmt = conn
            .prepare(
                "SELECT file_path, title, author, publisher, description, genres, year,
                    format, file_size, total_pages, cover_data, added_at, last_opened_at
             FROM library
             WHERE title LIKE ?1 OR author LIKE ?1 OR description LIKE ?1
             ORDER BY title ASC",
            )
            .map_err(|e| db_err("准备语句失败", e))?;

        let iter = stmt
            .query_map(params![search_pattern], |row| {
                Ok(LibraryEntry {
                    file_path: row.get(0)?,
                    title: row.get(1)?,
                    author: row.get(2)?,
                    publisher: row.get(3)?,
                    description: row.get(4)?,
                    genres: row
                        .get::<_, String>(5)?
                        .split(',')
                        .map(|s| s.to_string())
                        .collect(),
                    year: row.get(6)?,
                    format: row.get(7)?,
                    file_size: row.get(8)?,
                    total_pages: row.get(9)?,
                    cover_data: row.get(10)?,
                    added_at: row.get(11)?,
                    last_opened_at: row.get(12)?,
                })
            })
            .map_err(|e| db_err("查询失败", e))?;

        let mut entries = Vec::new();
        for entry in iter {
            entries.push(entry.map_err(|e| db_err("读取行失败", e))?);
        }

        Ok(entries)
    }

    /// 获取最近添加的漫画
    pub fn get_recently_added(&self, limit: usize) -> Result<Vec<LibraryEntry>> {
        let conn = self.conn();

        let mut stmt = conn
            .prepare(
                "SELECT file_path, title, author, publisher, description, genres, year,
                    format, file_size, total_pages, cover_data, added_at, last_opened_at
             FROM library ORDER BY added_at DESC LIMIT ?1",
            )
            .map_err(|e| db_err("准备语句失败", e))?;

        let iter = stmt
            .query_map(params![limit], |row| {
                Ok(LibraryEntry {
                    file_path: row.get(0)?,
                    title: row.get(1)?,
                    author: row.get(2)?,
                    publisher: row.get(3)?,
                    description: row.get(4)?,
                    genres: row
                        .get::<_, String>(5)?
                        .split(',')
                        .map(|s| s.to_string())
                        .collect(),
                    year: row.get(6)?,
                    format: row.get(7)?,
                    file_size: row.get(8)?,
                    total_pages: row.get(9)?,
                    cover_data: row.get(10)?,
                    added_at: row.get(11)?,
                    last_opened_at: row.get(12)?,
                })
            })
            .map_err(|e| db_err("查询失败", e))?;

        let mut entries = Vec::new();
        for entry in iter {
            entries.push(entry.map_err(|e| db_err("读取行失败", e))?);
        }

        Ok(entries)
    }

    /// 更新最后打开时间
    pub fn update_last_opened(&self, file_path: &str) -> Result<()> {
        let conn = self.conn();
        let now = current_timestamp();

        conn.execute(
            "UPDATE library SET last_opened_at = ?1 WHERE file_path = ?2",
            params![now, file_path],
        )
        .map_err(|e| db_err("更新失败", e))?;

        Ok(())
    }

    /// Bytes and count of the derived covers held in the library table.
    pub fn derived_cache_stats(&self) -> Result<DerivedCacheStats> {
        let conn = self.conn();
        conn.query_row(
            "SELECT COALESCE(SUM(LENGTH(cover_data)), 0), COUNT(cover_data) FROM library",
            [],
            |row| {
                Ok(DerivedCacheStats {
                    bytes: u64::try_from(row.get::<_, i64>(0)?).unwrap_or(0),
                    entries: usize::try_from(row.get::<_, i64>(1)?).unwrap_or(0),
                })
            },
        )
        .map_err(|e| db_err("统计派生缓存失败", e))
    }

    /// Drops every derived cover. The source comics and the reading records are
    /// untouched; the next scan rebuilds the covers.
    pub fn clear_derived_covers(&self) -> Result<()> {
        let conn = self.conn();
        conn.execute("UPDATE library SET cover_data = NULL", [])
            .map_err(|e| db_err("清除派生缓存失败", e))?;
        Ok(())
    }
}

/// 派生缓存（库表内的封面数据）的统计。
#[derive(Debug, Clone)]
pub struct DerivedCacheStats {
    pub bytes: u64,
    pub entries: usize,
}

/// 图书馆条目
#[derive(Debug, Clone)]
pub struct LibraryEntry {
    pub file_path: String,
    pub title: Option<String>,
    pub author: Option<String>,
    pub publisher: Option<String>,
    pub description: Option<String>,
    pub genres: Vec<String>,
    pub year: Option<i32>,
    pub format: String,
    pub file_size: u64,
    pub total_pages: usize,
    pub cover_data: Option<Vec<u8>>,
    pub added_at: u64,
    pub last_opened_at: Option<u64>,
}

// ============ 全局数据库实例 ============

use std::sync::OnceLock;

static GLOBAL_DB: OnceLock<Arc<LibraryDatabase>> = OnceLock::new();

/// 初始化全局数据库
pub fn init_global_db(db_path: Option<PathBuf>) -> Result<()> {
    let db = LibraryDatabase::new(db_path)?;
    GLOBAL_DB.get_or_init(|| Arc::new(db));
    Ok(())
}

/// 获取全局数据库实例
///
/// The connection is already guarded inside [`LibraryDatabase`], so callers must
/// not wrap it in a second lock: holding one across a scan's file IO would block
/// every progress save, bookmark and history read while the shelf rebuilds.
pub fn get_global_db() -> Option<Arc<LibraryDatabase>> {
    GLOBAL_DB.get().cloned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn create_test_db() -> LibraryDatabase {
        let mut path = std::env::temp_dir();
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis();
        path.push(format!("zephyr_test_{}.db", ts));
        LibraryDatabase::new(Some(path)).unwrap()
    }

    #[test]
    fn test_reading_progress() {
        let db = create_test_db();
        let progress = ReadingProgress::new("test.cbz".to_string(), 0, 10);
        db.save_reading_progress(&progress).unwrap();
        let retrieved = db.get_reading_progress("test.cbz").unwrap();
        assert!(retrieved.is_some());
    }

    #[test]
    fn test_bookmark() {
        let db = create_test_db();
        let bookmark = Bookmark::new("test.cbz".to_string(), 5, Some("test".to_string()));
        db.add_bookmark(&bookmark).unwrap();
        let bookmarks = db.get_bookmarks("test.cbz").unwrap();
        assert_eq!(bookmarks.len(), 1);
        db.remove_bookmark("test.cbz", 5).unwrap();
        let bookmarks = db.get_bookmarks("test.cbz").unwrap();
        assert!(bookmarks.is_empty());
    }

    #[test]
    fn derived_cache_stats_follow_the_stored_covers() {
        let db = create_test_db();
        assert_eq!(db.derived_cache_stats().unwrap().entries, 0);

        db.add_to_library(&LibraryEntry {
            file_path: "covered.cbz".to_string(),
            title: Some("Covered".to_string()),
            author: None,
            publisher: None,
            description: None,
            genres: vec![],
            year: None,
            format: "cbz".to_string(),
            file_size: 10,
            total_pages: 1,
            cover_data: Some(vec![7u8; 32]),
            added_at: 100,
            last_opened_at: None,
        })
        .unwrap();

        let stats = db.derived_cache_stats().unwrap();
        assert_eq!(stats.entries, 1);
        assert_eq!(stats.bytes, 32);

        db.clear_derived_covers().unwrap();
        let cleared = db.derived_cache_stats().unwrap();
        assert_eq!(cleared.entries, 0);
        assert_eq!(cleared.bytes, 0);
    }

    #[test]
    fn library_upsert_preserves_existing_timestamps() {
        let db = create_test_db();
        let original = LibraryEntry {
            file_path: "stable.cbz".to_string(),
            title: Some("Old title".to_string()),
            author: None,
            publisher: None,
            description: None,
            genres: vec![],
            year: None,
            format: "cbz".to_string(),
            file_size: 10,
            total_pages: 1,
            cover_data: None,
            added_at: 100,
            last_opened_at: Some(200),
        };
        db.add_to_library(&original).unwrap();

        let refreshed = LibraryEntry {
            title: Some("New title".to_string()),
            file_size: 20,
            total_pages: 2,
            added_at: 300,
            last_opened_at: None,
            ..original
        };
        db.add_to_library(&refreshed).unwrap();

        let stored = db.get_library_entries().unwrap().remove(0);
        assert_eq!(stored.title.as_deref(), Some("New title"));
        assert_eq!(stored.file_size, 20);
        assert_eq!(stored.added_at, 100);
        assert_eq!(stored.last_opened_at, Some(200));
    }
}

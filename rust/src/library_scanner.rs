//! 图书馆扫描器模块
//!
//! 扫描目录中的漫画文件，建立图书馆索引。

use std::path::{Path, PathBuf};
use std::fs;

use crate::error::{ComicError, Result};
use crate::library_db::{LibraryDatabase, LibraryEntry};
use crate::metadata::extract_metadata;
use crate::archive::get_comic_info;

/// 图书馆扫描器
pub struct LibraryScanner {
    /// 扫描路径列表
    scan_paths: Vec<PathBuf>,
    /// 支持的扩展名
    supported_extensions: Vec<String>,
}

impl LibraryScanner {
    /// 创建新的扫描器
    pub fn new() -> Self {
        Self {
            scan_paths: Vec::new(),
            supported_extensions: vec![
                "cbz".to_string(),
                "cbr".to_string(),
                "zip".to_string(),
                "rar".to_string(),
                "pdf".to_string(),
                "epub".to_string(),
            ],
        }
    }

    /// 添加扫描路径
    pub fn add_scan_path(&mut self, path: &str) {
        let path_buf = PathBuf::from(path);
        if !self.scan_paths.contains(&path_buf) {
            self.scan_paths.push(path_buf);
        }
    }

    /// 移除扫描路径
    pub fn remove_scan_path(&mut self, path: &str) {
        self.scan_paths.retain(|p| p != path);
    }

    /// 获取扫描路径列表
    pub fn get_scan_paths(&self) -> Vec<String> {
        self.scan_paths.iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect()
    }

    /// 扫描单个目录
    pub fn scan_directory(&self, path: &str) -> Result<Vec<LibraryEntry>> {
        let scan_path = Path::new(path);

        if !scan_path.exists() {
            return Err(ComicError::FileNotFound(path.to_string()));
        }

        let mut entries = Vec::new();
        self.scan_directory_recursive(scan_path, &mut entries)?;

        Ok(entries)
    }

    /// 递归扫描目录
    fn scan_directory_recursive(&self, dir: &Path, entries: &mut Vec<LibraryEntry>) -> Result<()> {
        let Ok(read_dir) = fs::read_dir(dir) else {
            return Ok(());
        };

        for entry_result in read_dir {
            let Ok(entry) = entry_result else {
                continue;
            };

            let path = entry.path();

            if path.is_dir() {
                // 递归扫描子目录
                self.scan_directory_recursive(&path, entries)?;
            } else if path.is_file() {
                // 检查是否为支持的漫画格式
                if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
                    if self.supported_extensions.contains(&ext.to_lowercase()) {
                        match self.create_library_entry(&path) {
                            Ok(entry) => entries.push(entry),
                            Err(e) => {
                                log::warn!("扫描文件失败 {:?}: {}", path, e);
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// 创建图书馆条目
    fn create_library_entry(&self, path: &Path) -> Result<LibraryEntry> {
        let file_path = path.to_string_lossy().to_string();

        // 获取文件基本信息
        let metadata = fs::metadata(path)?;
        let file_size = metadata.len();

        // 提取元数据
        let comic_metadata = extract_metadata(&file_path).unwrap_or_default();

        // 尝试获取总页数
        let total_pages = get_comic_info(&file_path)
            .ok()
            .map(|info| info.total_images)
            .unwrap_or(0);

        // 获取格式
        let format = path
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .to_lowercase();

        let now = crate::reading_progress::current_timestamp();

        Ok(LibraryEntry {
            file_path,
            title: comic_metadata.title,
            author: comic_metadata.author,
            publisher: comic_metadata.publisher,
            description: comic_metadata.description,
            genres: comic_metadata.genres,
            year: comic_metadata.year,
            format,
            file_size,
            total_pages,
            cover_data: None, // TODO: 生成封面缩略图
            added_at: now,
            last_opened_at: None,
        })
    }

    /// 扫描所有已配置的路径
    pub fn scan_all(&self) -> Result<Vec<LibraryEntry>> {
        let mut all_entries = Vec::new();

        for scan_path in &self.scan_paths {
            match self.scan_directory(&scan_path.to_string_lossy()) {
                Ok(entries) => all_entries.extend(entries),
                Err(e) => {
                    log::warn!("扫描路径 {:?} 失败：{}", scan_path, e);
                }
            }
        }

        Ok(all_entries)
    }

    /// 增量扫描 (只扫描新文件)
    pub fn scan_incremental(&self, db: &LibraryDatabase) -> Result<Vec<LibraryEntry>> {
        let existing_entries = db.get_library_entries()?;
        let existing_paths: std::collections::HashSet<_> =
            existing_entries.iter().map(|e| &e.file_path).collect();

        let mut new_entries = Vec::new();

        for entry in self.scan_all()? {
            if !existing_paths.contains(&entry.file_path) {
                new_entries.push(entry);
            }
        }

        Ok(new_entries)
    }

    /// 清理不存在的文件
    pub fn cleanup_missing_files(&self, db: &LibraryDatabase) -> Result<Vec<String>> {
        let entries = db.get_library_entries()?;
        let mut removed_paths = Vec::new();

        for entry in entries {
            if !Path::new(&entry.file_path).exists() {
                db.remove_from_library(&entry.file_path)?;
                removed_paths.push(entry.file_path);
            }
        }

        Ok(removed_paths)
    }

    /// 获取支持的扩展名列表
    pub fn get_supported_extensions() -> Vec<&'static str> {
        vec!["cbz", "cbr", "zip", "rar", "pdf", "epub"]
    }
}

impl Default for LibraryScanner {
    fn default() -> Self {
        Self::new()
    }
}

/// 便捷函数：扫描目录并添加到数据库
pub fn scan_directory_to_library(
    db: &LibraryDatabase,
    path: &str,
) -> Result<Vec<LibraryEntry>> {
    let scanner = LibraryScanner::new();
    let entries = scanner.scan_directory(path)?;

    for entry in &entries {
        db.add_to_library(entry)?;
    }

    Ok(entries)
}

/// 便捷函数：扫描所有路径并更新数据库
pub fn scan_and_update_library(
    db: &LibraryDatabase,
    scan_paths: &[String],
) -> Result<usize> {
    let mut scanner = LibraryScanner::new();
    for path in scan_paths {
        scanner.add_scan_path(path);
    }

    // 清理不存在的文件
    let removed = scanner.cleanup_missing_files(db)?;
    log::info!("清理了 {} 个不存在的文件", removed.len());

    // 增量扫描新文件
    let new_entries = scanner.scan_incremental(db)?;
    let new_count = new_entries.len();

    for entry in &new_entries {
        db.add_to_library(entry)?;
    }

    log::info!("添加了 {} 个新漫画", new_count);

    Ok(new_count)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn test_scanner_creation() {
        let scanner = LibraryScanner::new();
        assert!(scanner.scan_paths.is_empty());
        assert_eq!(scanner.supported_extensions.len(), 6);
    }

    #[test]
    fn test_add_scan_path() {
        let mut scanner = LibraryScanner::new();
        scanner.add_scan_path("/test/path");
        scanner.add_scan_path("/test/path"); // 重复添加

        assert_eq!(scanner.get_scan_paths().len(), 1);
    }

    #[test]
    fn test_remove_scan_path() {
        let mut scanner = LibraryScanner::new();
        scanner.add_scan_path("/test/path1");
        scanner.add_scan_path("/test/path2");
        scanner.remove_scan_path("/test/path1");

        assert_eq!(scanner.get_scan_paths().len(), 1);
        assert_eq!(scanner.get_scan_paths()[0], "/test/path2");
    }

    #[test]
    fn test_get_supported_extensions() {
        let extensions = LibraryScanner::get_supported_extensions();
        assert!(extensions.contains(&"cbz"));
        assert!(extensions.contains(&"cbr"));
        assert!(extensions.contains(&"pdf"));
    }

    #[test]
    fn test_scan_nonexistent_directory() {
        let scanner = LibraryScanner::new();
        let result = scanner.scan_directory("/nonexistent/path/that/does/not/exist");
        assert!(result.is_err());
    }

    #[test]
    fn test_scan_empty_directory() {
        // 创建临时空目录
        let mut temp_path = std::env::temp_dir();
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis();
        temp_path.push(format!("zephyr_test_{}", ts));
        let _ = fs::create_dir_all(&temp_path);

        let scanner = LibraryScanner::new();
        let result = scanner.scan_directory(&temp_path.to_string_lossy());

        // 清理
        let _ = fs::remove_dir_all(&temp_path);

        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }
}

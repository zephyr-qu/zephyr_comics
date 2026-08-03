//! 图书馆扫描器模块
//!
//! 扫描目录中的漫画文件，建立图书馆索引。

use std::fs;
use std::path::{Path, PathBuf};

use crate::archive::{extract_file_from_archive, get_comic_info};
use crate::error::{ComicError, Result};
use crate::library_db::{LibraryDatabase, LibraryEntry};
use crate::metadata::{extract_front_cover, extract_metadata, generate_cover_thumbnail};

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
            supported_extensions: vec!["cbz".to_string(), "zip".to_string()],
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
        self.scan_paths
            .iter()
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
        let read_dir = fs::read_dir(dir)
            .map_err(|error| ComicError::Internal(format!("无法读取目录 {:?}: {}", dir, error)))?;
        for entry_result in read_dir {
            let entry = entry_result.map_err(|error| {
                ComicError::Internal(format!("无法读取目录项 {:?}: {}", dir, error))
            })?;

            let path = entry.path();

            if path.is_dir() {
                // 递归扫描子目录
                self.scan_directory_recursive(&path, entries)?;
            } else if path.is_file() {
                // 检查是否为支持的漫画格式
                if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
                    if self
                        .supported_extensions
                        .contains(&ext.to_ascii_lowercase())
                    {
                        match self.create_library_entry(&path) {
                            Ok(entry) => entries.push(entry),
                            Err(e) => log::warn!("扫描文件失败 {:?}: {}", path, e),
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// 创建图书馆条目
    fn create_library_entry(&self, path: &Path) -> Result<LibraryEntry> {
        let file_path = normalize_path(path);

        // 获取文件基本信息
        let metadata = fs::metadata(path)?;
        let file_size = metadata.len();

        // 提取元数据
        let comic_metadata = extract_metadata(&file_path).unwrap_or_default();

        // The same sorted page list drives both the page count and the cover.
        let comic_info = get_comic_info(&file_path).ok();
        let total_pages = comic_info
            .as_ref()
            .map(|info| info.total_images)
            .unwrap_or(0);
        let cover_data = comic_info.as_ref().and_then(|info| {
            let pages = info.chapters.first()?.image_files.as_slice();
            let preferred = extract_front_cover(&file_path)
                .ok()
                .flatten()
                .and_then(|front| {
                    pages
                        .iter()
                        .find(|page| page.eq_ignore_ascii_case(&front))
                        .cloned()
                });
            let page = preferred
                .as_deref()
                .or_else(|| pages.first().map(String::as_str))?;
            extract_file_from_archive(&file_path, page)
                .ok()
                .and_then(|bytes| generate_cover_thumbnail(&bytes, 512).ok())
        });

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
            cover_data,
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
        let mut changed_entries = Vec::new();
        for scan_path in &self.scan_paths {
            let mut paths = Vec::new();
            self.discover_files(scan_path, &mut paths)?;
            for path in paths {
                let normalized = normalize_path(&path);
                let metadata = fs::metadata(&path)?;
                let modified_at = file_modified_at(&metadata);
                let unchanged =
                    db.get_file_fingerprint(&normalized)?
                        .is_some_and(|(size, modified)| {
                            size == metadata.len() && modified == modified_at
                        });
                if !unchanged {
                    changed_entries.push(self.create_library_entry(&path)?);
                }
            }
        }
        Ok(changed_entries)
    }

    fn discover_files(&self, dir: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
        for entry_result in fs::read_dir(dir)
            .map_err(|error| ComicError::Internal(format!("无法读取目录 {:?}: {}", dir, error)))?
        {
            let entry = entry_result.map_err(|error| {
                ComicError::Internal(format!("无法读取目录项 {:?}: {}", dir, error))
            })?;
            let path = entry.path();
            if path.is_dir() {
                self.discover_files(&path, files)?;
            } else if path.is_file()
                && path
                    .extension()
                    .and_then(|ext| ext.to_str())
                    .is_some_and(|ext| {
                        self.supported_extensions
                            .contains(&ext.to_ascii_lowercase())
                    })
            {
                files.push(path);
            }
        }
        Ok(())
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
        vec!["cbz", "zip"]
    }
}

fn normalize_path(path: &Path) -> String {
    let absolute = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    absolute.to_string_lossy().replace('\\', "/")
}

fn file_modified_at(metadata: &fs::Metadata) -> u64 {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_nanos() as u64)
        .unwrap_or_default()
}

impl Default for LibraryScanner {
    fn default() -> Self {
        Self::new()
    }
}

/// 便捷函数：扫描目录并添加到数据库
pub fn scan_directory_to_library(db: &LibraryDatabase, path: &str) -> Result<Vec<LibraryEntry>> {
    let scanner = LibraryScanner::new();
    let entries = scanner.scan_directory(path)?;

    for entry in &entries {
        db.add_to_library(entry)?;
    }

    Ok(entries)
}

/// 便捷函数：扫描所有路径并更新数据库
pub fn scan_and_update_library(db: &LibraryDatabase, scan_paths: &[String]) -> Result<usize> {
    let mut scanner = LibraryScanner::new();
    for path in scan_paths {
        scanner.add_scan_path(path);
    }

    // Validate every configured root before touching the database. A revoked
    // all-files grant or missing directory must preserve the previous shelf;
    // reconciliation is only safe after all roots were read successfully.
    for path in scan_paths {
        let root = Path::new(path);
        if !root.is_dir() {
            return Err(ComicError::FileNotFound(path.clone()));
        }
        let mut discovered = Vec::new();
        scanner.discover_files(root, &mut discovered)?;
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
    use std::fs::File;
    use std::io::Write;
    use std::time::{SystemTime, UNIX_EPOCH};
    use zip::write::FileOptions;

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        path.push(format!("zephyr_scanner_{prefix}_{nonce}"));
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn write_cbz(path: &Path, entries: &[(&str, &[u8])]) {
        let file = File::create(path).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        for (entry_name, bytes) in entries {
            archive
                .start_file(*entry_name, FileOptions::default())
                .unwrap();
            archive.write_all(bytes).unwrap();
        }
        archive.finish().unwrap();
    }

    #[test]
    fn test_scanner_creation() {
        let scanner = LibraryScanner::new();
        assert!(scanner.scan_paths.is_empty());
        assert_eq!(scanner.supported_extensions, vec!["cbz", "zip"]);
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
        assert!(extensions.contains(&"zip"));
        assert!(!extensions.contains(&"cbr"));
        assert!(!extensions.contains(&"pdf"));
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

    #[test]
    fn scan_uses_filename_title_and_first_sorted_page_as_cover() {
        let dir = unique_temp_dir("cover");
        let path = dir.join("Original Name.cbz");
        let image = image::DynamicImage::new_rgb8(800, 400);
        let mut page = Vec::new();
        image
            .write_to(
                &mut std::io::Cursor::new(&mut page),
                image::ImageFormat::Png,
            )
            .unwrap();
        write_cbz(&path, &[("002.png", &page), ("001.png", &page)]);

        let entry = LibraryScanner::new().create_library_entry(&path).unwrap();

        assert_eq!(entry.title.as_deref(), Some("Original Name"));
        assert_eq!(entry.total_pages, 2);
        let cover = image::load_from_memory(entry.cover_data.as_ref().unwrap()).unwrap();
        assert_eq!((cover.width(), cover.height()), (512, 256));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn scan_keeps_entry_when_cover_is_missing() {
        let dir = unique_temp_dir("no_cover");
        let path = dir.join("No Cover.cbz");
        let xml = br#"<ComicInfo><Title>Metadata Title</Title></ComicInfo>"#;
        write_cbz(&path, &[("nested/comicinfo.xml", xml)]);

        let entry = LibraryScanner::new().create_library_entry(&path).unwrap();

        assert_eq!(entry.title.as_deref(), Some("Metadata Title"));
        assert_eq!(entry.total_pages, 0);
        assert!(entry.cover_data.is_none());
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn scan_prefers_comic_info_front_cover_over_natural_first_page() {
        let dir = unique_temp_dir("front_cover");
        let path = dir.join("Front Cover.cbz");
        let first = image::DynamicImage::new_rgb8(800, 400);
        let second = image::DynamicImage::new_rgb8(400, 800);
        let mut first_bytes = Vec::new();
        first
            .write_to(
                &mut std::io::Cursor::new(&mut first_bytes),
                image::ImageFormat::Png,
            )
            .unwrap();
        let mut second_bytes = Vec::new();
        second
            .write_to(
                &mut std::io::Cursor::new(&mut second_bytes),
                image::ImageFormat::Png,
            )
            .unwrap();
        let xml = br#"<ComicInfo><Title>Metadata title</Title><FrontCover>002.png</FrontCover></ComicInfo>"#;
        write_cbz(
            &path,
            &[
                ("001.png", &first_bytes),
                ("002.png", &second_bytes),
                ("ComicInfo.xml", xml),
            ],
        );

        let entry = LibraryScanner::new().create_library_entry(&path).unwrap();
        let cover = image::load_from_memory(entry.cover_data.as_ref().unwrap()).unwrap();
        assert_eq!(entry.title.as_deref(), Some("Metadata title"));
        assert_eq!((cover.width(), cover.height()), (256, 512));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn scan_incremental_reuses_unchanged_fingerprint() {
        let dir = unique_temp_dir("incremental");
        let path = dir.join("one.cbz");
        write_cbz(&path, &[("001.png", b"not an image")]);
        let db_path = dir.join("library.db");
        let db = LibraryDatabase::new(Some(db_path)).unwrap();
        let mut scanner = LibraryScanner::new();
        scanner.add_scan_path(dir.to_str().unwrap());
        let first = scanner.scan_incremental(&db).unwrap();
        assert_eq!(first.len(), 1);
        db.add_to_library(&first[0]).unwrap();
        assert!(scanner.scan_incremental(&db).unwrap().is_empty());
        let _ = fs::remove_dir_all(dir);
    }
}

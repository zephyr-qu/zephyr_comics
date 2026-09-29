//! 压缩包解压模块
//!
//! 支持 CBZ (ZIP) 格式的解压和文件列表提取。
//!
//! # 功能
//! - ZIP (CBZ) 文件解压
//! - 文件列表智能排序

use std::path::Path;

use crate::error::{ComicError, Result};
use crate::types::{ChapterInfo, ComicFormat, ComicInfo};

/// 获取漫画文件信息
///
/// 分析漫画文件，返回文件信息和章节/页面列表。
pub fn get_comic_info(file_path: &str) -> Result<ComicInfo> {
    let path = Path::new(file_path);

    if !path.exists() {
        return Err(ComicError::FileNotFound(file_path.to_string()));
    }

    let file_name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("unknown")
        .to_string();
    let file_size = path.metadata()?.len();
    let extension = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string();

    let format = ComicFormat::from_extension(&extension);
    if format == ComicFormat::Unknown {
        return Err(ComicError::UnsupportedFormat(extension));
    }

    let chapters = match format {
        ComicFormat::Cbz => extract_zip_contents(file_path)?,
        ComicFormat::Unknown => return Err(ComicError::UnsupportedFormat(extension)),
    };

    let total_images: usize = chapters.iter().map(|c| c.image_count).sum();

    Ok(ComicInfo {
        file_path: file_path.to_string(),
        file_name,
        format: format.as_str().to_string(),
        file_size,
        chapters,
        total_images,
    })
}

/// 从 ZIP 文件提取内容列表
fn extract_zip_contents(file_path: &str) -> Result<Vec<ChapterInfo>> {
    // Filtered and naturally sorted once per open archive handle. The page
    // sequence is the full archive path in natural order; cover preference is
    // resolved separately from ComicInfo.xml by the library scanner and must
    // not silently reorder pages for the reader.
    let sorted_files = crate::archive_cache::list_page_files_from_cache(file_path)?;

    // 单章节漫画
    let image_count = sorted_files.len();
    let chapter = ChapterInfo {
        name: "全部".to_string(),
        image_files: sorted_files,
        image_count,
    };

    Ok(vec![chapter])
}

/// 从压缩包中提取单页图像数据
///
/// # 参数
/// * `file_path` - 压缩包路径
/// * `file_name` - 压缩包内的文件名
///
/// # 返回
/// 返回原始图像数据 (未解码)
pub fn extract_file_from_archive(file_path: &str, file_name: &str) -> Result<Vec<u8>> {
    // ponytail: only CBZ supported, use archive cache
    crate::archive_cache::extract_file_from_cache(file_path, file_name)
}

#[cfg(test)]
mod tests {
    use crate::sort::filter_image_files;

    #[test]
    fn test_filter_image_files() {
        let files = vec![
            "001.png".to_string(),
            "002.jpg".to_string(),
            "readme.txt".to_string(),
            "cover.jpeg".to_string(),
        ];
        let filtered = filter_image_files(&files);
        assert_eq!(filtered.len(), 3);
        assert!(!filtered.iter().any(|f| f.ends_with(".txt")));
    }
}

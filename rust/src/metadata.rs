//! 漫画元数据提取模块
//!
//! 从漫画文件中提取元数据信息，支持 ComicInfo.xml 标准。

use flutter_rust_bridge::frb;
use std::path::Path;
use quick_xml::{events::Event, Reader};

use crate::error::{ComicError, Result};

/// 漫画元数据
///
/// 包含漫画的详细信息。
#[derive(Debug, Clone, Default)]
pub struct ComicMetadata {
    /// 标题
    pub title: Option<String>,
    /// 作者
    pub author: Option<String>,
    /// 出版社
    pub publisher: Option<String>,
    /// 描述/简介
    pub description: Option<String>,
    /// 类型标签
    pub genres: Vec<String>,
    /// 出版年份
    pub year: Option<i32>,
    /// 卷号
    pub volume: Option<i32>,
    /// 期号
    pub issue: Option<String>,
    /// 评分 (0-10)
    pub rating: Option<f32>,
    /// Web 链接
    pub web_url: Option<String>,
    /// ISBN
    pub isbn: Option<String>,
    /// 封面图像数据 (PNG 格式)
    pub cover_image: Option<Vec<u8>>,
}

impl ComicMetadata {
    /// 创建空的元数据
    pub fn new() -> Self {
        Self::default()
    }

    /// 从文件路径提取元数据
    pub fn from_file(file_path: &str) -> Result<Self> {
        extract_metadata(file_path)
    }

    /// 是否包含有效信息
    pub fn is_empty(&self) -> bool {
        self.title.is_none() && self.author.is_none()
    }

    /// 获取显示用的标题
    pub fn display_title(&self) -> String {
        self.title.clone().unwrap_or_else(|| "未知标题".to_string())
    }

    /// 获取显示用的作者
    pub fn display_author(&self) -> String {
        self.author.clone().unwrap_or_else(|| "未知作者".to_string())
    }
}

/// 从漫画文件提取元数据
pub fn extract_metadata(file_path: &str) -> Result<ComicMetadata> {
    let path = Path::new(file_path);

    if !path.exists() {
        return Err(ComicError::FileNotFound(file_path.to_string()));
    }

    // 尝试从 ComicInfo.xml 提取
    match extract_from_comic_info(file_path) {
        Ok(metadata) if !metadata.is_empty() => return Ok(metadata),
        _ => {}
    }

    // 从文件名推断
    Ok(infer_from_filename(file_path))
}

/// 从 ComicInfo.xml 提取元数据
pub fn extract_from_comic_info(file_path: &str) -> Result<ComicMetadata> {
    use zip::ZipArchive;
    use std::fs::File;

    let file = File::open(file_path)?;
    let mut archive = ZipArchive::new(file)?;

    // 查找 ComicInfo.xml
    let xml_data = match archive.by_name("ComicInfo.xml") {
        Ok(mut entry) => {
            let mut contents = String::new();
            std::io::Read::read_to_string(&mut entry, &mut contents)?;
            contents
        }
        Err(_) => return Err(ComicError::FileNotFound("ComicInfo.xml not found".to_string())),
    };

    parse_comic_info_xml(&xml_data)
}

/// 解析 ComicInfo.xml 内容
pub fn parse_comic_info_xml(xml_data: &str) -> Result<ComicMetadata> {
    let mut reader = Reader::from_str(xml_data);
    reader.trim_text(true);

    let mut metadata = ComicMetadata::new();
    let mut current_tag = String::new();
    let mut current_text = String::new();

    loop {
        match reader.read_event() {
            Ok(Event::Start(ref e)) | Ok(Event::Empty(ref e)) => {
                let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                current_tag = tag_name;
                current_text.clear();
            }
            Ok(Event::Text(ref e)) => {
                current_text = String::from_utf8_lossy(e.as_ref()).to_string();
            }
            Ok(Event::End(ref e)) => {
                let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                
                if tag_name == current_tag && !current_text.is_empty() {
                    match tag_name.as_str() {
                        "Title" => metadata.title = Some(current_text.clone()),
                        "Author" | "Writer" | "Penciller" | "Inker" => {
                            if metadata.author.is_none() {
                                metadata.author = Some(current_text.clone());
                            } else if let Some(ref mut author) = metadata.author {
                                if !author.contains(&current_text) {
                                    author.push_str(&format!(", {}", current_text));
                                }
                            }
                        }
                        "Publisher" => metadata.publisher = Some(current_text.clone()),
                        "Summary" | "Description" => metadata.description = Some(current_text.clone()),
                        "Genre" => {
                            for genre in current_text.split(',').map(|s| s.trim()) {
                                if !genre.is_empty() {
                                    metadata.genres.push(genre.to_string());
                                }
                            }
                        }
                        "Year" => {
                            if let Ok(year) = current_text.parse() {
                                metadata.year = Some(year);
                            }
                        }
                        "Volume" => {
                            if let Ok(vol) = current_text.parse() {
                                metadata.volume = Some(vol);
                            }
                        }
                        "Number" | "Issue" => metadata.issue = Some(current_text.clone()),
                        "Web" => metadata.web_url = Some(current_text.clone()),
                        "ISBN" => metadata.isbn = Some(current_text.clone()),
                        _ => {}
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => {
                return Err(ComicError::Internal(format!("XML 解析错误：{}", e)));
            }
            _ => {}
        }
    }

    Ok(metadata)
}

/// 从文件名推断元数据
fn infer_from_filename(file_path: &str) -> ComicMetadata {
    let path = Path::new(file_path);
    let filename = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or_default()
        .to_string();

    // 简单的推断逻辑
    let mut metadata = ComicMetadata::new();
    metadata.title = Some(filename.clone());

    // 尝试从路径推断作者
    if let Some(parent) = path.parent() {
        if let Some(author) = parent.file_name().and_then(|s| s.to_str()) {
            if !author.is_empty() && author != "comics" && author != "manga" {
                metadata.author = Some(author.to_string());
            }
        }
    }

    metadata
}

/// 从图像数据生成缩略图
pub fn generate_cover_thumbnail(image_data: &[u8], size: u32) -> Result<Vec<u8>> {
    use image::load_from_memory;
    use std::io::Cursor;

    let img = load_from_memory(image_data)?;

    let thumb = img.resize_exact(size, size, image::imageops::FilterType::Lanczos3);

    let mut png_data = Vec::new();
    thumb.write_to(&mut Cursor::new(&mut png_data), image::ImageFormat::Png)?;

    Ok(png_data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metadata_creation() {
        let metadata = ComicMetadata::new();
        assert!(metadata.is_empty());
        assert_eq!(metadata.display_title(), "未知标题");
    }

    #[test]
    fn test_metadata_from_fields() {
        let metadata = ComicMetadata {
            title: Some("Test".to_string()),
            author: Some("Author".to_string()),
            ..Default::default()
        };

        assert!(!metadata.is_empty());
        assert_eq!(metadata.display_title(), "Test");
        assert_eq!(metadata.display_author(), "Author");
    }

    #[test]
    fn test_parse_simple_xml() {
        let xml = r#"<?xml version="1.0"?>
<ComicInfo>
    <Title>Test Comic</Title>
    <Author>Test Author</Author>
    <Year>2024</Year>
</ComicInfo>"#;

        let metadata = parse_comic_info_xml(xml).unwrap();
        assert_eq!(metadata.title, Some("Test Comic".to_string()));
        assert_eq!(metadata.author, Some("Test Author".to_string()));
        assert_eq!(metadata.year, Some(2024));
    }

    #[test]
    fn test_parse_genres() {
        let xml = r#"<?xml version="1.0"?>
<ComicInfo>
    <Genre>Action, Adventure, Superhero</Genre>
</ComicInfo>"#;

        let metadata = parse_comic_info_xml(xml).unwrap();
        assert_eq!(metadata.genres.len(), 3);
        assert!(metadata.genres.contains(&"Action".to_string()));
    }

    #[test]
    fn test_infer_from_filename() {
        let metadata = infer_from_filename("/comics/batman/batman_01.cbz");
        assert_eq!(metadata.title, Some("batman_01".to_string()));
        assert_eq!(metadata.author, Some("batman".to_string()));
    }
}

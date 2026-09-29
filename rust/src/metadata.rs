//! 漫画元数据提取模块
//!
//! 从漫画文件中提取元数据信息，支持 ComicInfo.xml 标准。

use quick_xml::{events::Event, Reader};
use std::path::Path;

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
        self.author
            .clone()
            .unwrap_or_else(|| "未知作者".to_string())
    }
}

/// 从漫画文件提取元数据
pub fn extract_metadata(file_path: &str) -> Result<ComicMetadata> {
    let path = Path::new(file_path);

    if !path.exists() {
        return Err(ComicError::FileNotFound(file_path.to_string()));
    }

    // ComicInfo.xml may contain useful fields without a title. Preserve those
    // fields and fill only the missing title from the original file name.
    if let Ok(mut metadata) = extract_from_comic_info(file_path) {
        let inferred = infer_from_filename(file_path);
        if metadata.title.as_deref().is_none_or(str::is_empty) {
            metadata.title = inferred.title;
        }
        return Ok(metadata);
    }

    // 从文件名推断
    Ok(infer_from_filename(file_path))
}

/// 从 ComicInfo.xml 提取元数据
pub fn extract_from_comic_info(file_path: &str) -> Result<ComicMetadata> {
    parse_comic_info_xml(&read_comic_info_xml(file_path)?)
}

/// Read the optional ComicInfo.xml FrontCover value without making it part of
/// the public metadata/FRB shape. The value is an archive entry path and is
/// resolved by the library scanner against the naturally sorted image list.
pub fn extract_front_cover(file_path: &str) -> Result<Option<String>> {
    let contents = match read_comic_info_xml(file_path) {
        Ok(contents) => contents,
        Err(ComicError::FileNotFound(_)) => return Ok(None),
        Err(error) => return Err(error),
    };
    let lower = contents.to_ascii_lowercase();
    let Some(open_start) = lower.find("<frontcover") else {
        return Ok(None);
    };
    let Some(open_end_rel) = lower[open_start..].find('>') else {
        return Ok(None);
    };
    let value_start = open_start + open_end_rel + 1;
    let Some(close_rel) = lower[value_start..].find("</frontcover>") else {
        return Ok(None);
    };
    let value = contents[value_start..value_start + close_rel].trim();
    Ok((!value.is_empty()).then(|| value.to_string()))
}

fn read_comic_info_xml(file_path: &str) -> Result<String> {
    for entry_name in crate::archive_cache::list_files_from_cache(file_path)? {
        let file_name = entry_name.rsplit('/').next().unwrap_or(&entry_name);
        if file_name.eq_ignore_ascii_case("ComicInfo.xml") {
            let bytes = crate::archive_cache::extract_file_from_cache(file_path, &entry_name)?;
            return String::from_utf8(bytes).map_err(|error| {
                ComicError::Internal(format!("ComicInfo.xml 编码错误：{}", error))
            });
        }
    }
    Err(ComicError::FileNotFound(
        "ComicInfo.xml not found".to_string(),
    ))
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
                current_text = e
                    .unescape()
                    .map_err(|error| ComicError::Internal(format!("XML 文本解析错误：{}", error)))?
                    .into_owned();
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
                        "Summary" | "Description" => {
                            metadata.description = Some(current_text.clone())
                        }
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

    let longest_edge = img.width().max(img.height());
    let target = size.min(longest_edge);
    let thumb = img.resize(target, target, image::imageops::FilterType::Lanczos3);

    let mut png_data = Vec::new();
    thumb.write_to(&mut Cursor::new(&mut png_data), image::ImageFormat::Png)?;

    Ok(png_data)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;
    use std::time::{SystemTime, UNIX_EPOCH};
    use zip::write::FileOptions;

    fn temp_cbz(name: &str, entries: &[(&str, &[u8])]) -> std::path::PathBuf {
        let mut path = std::env::temp_dir();
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        path.push(format!("zephyr_metadata_{nonce}_{name}.cbz"));
        let file = File::create(&path).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        for (entry_name, bytes) in entries {
            archive
                .start_file(*entry_name, FileOptions::default())
                .unwrap();
            archive.write_all(bytes).unwrap();
        }
        archive.finish().unwrap();
        path
    }

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

    #[test]
    fn finds_nested_comic_info_case_insensitively() {
        let xml = br#"<ComicInfo><Title>Nested Title</Title></ComicInfo>"#;
        let path = temp_cbz("nested", &[("metadata/COMICINFO.XML", xml)]);

        let metadata = extract_metadata(path.to_str().unwrap()).unwrap();

        assert_eq!(metadata.title.as_deref(), Some("Nested Title"));
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn preserves_partial_comic_info_and_fills_missing_title() {
        let xml = br#"<ComicInfo><Summary>Tom &amp; Jerry</Summary></ComicInfo>"#;
        let path = temp_cbz("Fallback Title", &[("ComicInfo.xml", xml)]);
        let expected_title = path.file_stem().unwrap().to_string_lossy().to_string();

        let metadata = extract_metadata(path.to_str().unwrap()).unwrap();

        assert_eq!(metadata.title.as_deref(), Some(expected_title.as_str()));
        assert_eq!(metadata.description.as_deref(), Some("Tom & Jerry"));
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn cover_thumbnail_preserves_aspect_ratio() {
        let image = image::DynamicImage::new_rgb8(400, 200);
        let mut source = Vec::new();
        image
            .write_to(
                &mut std::io::Cursor::new(&mut source),
                image::ImageFormat::Png,
            )
            .unwrap();

        let thumbnail = generate_cover_thumbnail(&source, 100).unwrap();
        let decoded = image::load_from_memory(&thumbnail).unwrap();

        assert_eq!((decoded.width(), decoded.height()), (100, 50));
    }
}

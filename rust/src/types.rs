//! 数据类型模块
//!
//! 定义漫画引擎的核心数据结构，包括：
//! - 漫画文件信息 (ComicInfo)
//! - 章节信息 (ChapterInfo)
//! - 图像数据 (ImageData)
//! - 缓存键 (PageKey)

/// 漫画文件信息
///
/// 描述一个漫画文件 (CBZ) 的基本信息和章节列表。
#[derive(Debug, Clone)]
pub struct ComicInfo {
    /// 文件完整路径
    pub file_path: String,
    /// 文件名 (不含路径)
    pub file_name: String,
    /// 文件格式 (cbz)
    pub format: String,
    /// 文件大小 (字节)
    pub file_size: u64,
    /// 章节列表
    pub chapters: Vec<ChapterInfo>,
    /// 总图片数量
    pub total_images: usize,
}

/// 章节信息
///
/// 描述漫画中的一个章节 (或单文件漫画的页面列表)。
#[derive(Debug, Clone)]
pub struct ChapterInfo {
    /// 章节名称
    pub name: String,
    /// 章节内图片文件列表 (已排序)
    pub image_files: Vec<String>,
    /// 图片数量
    pub image_count: usize,
}

/// 图像数据
///
/// 解码后的图像像素数据，使用 RGBA8888 格式。
/// Flutter 侧可直接使用 `Image.memory()` 显示。
#[derive(Debug, Clone)]
pub struct ImageData {
    /// 图像宽度 (像素)
    pub width: i32,
    /// 图像高度 (像素)
    pub height: i32,
    /// RGBA 原始像素数据 (R,G,B,A,R,G,B,A,...)
    pub data: Vec<u8>,
    /// 像素格式标识
    pub format: String,
}

/// A page encoded as PNG for direct consumption by Flutter image widgets.
#[derive(Debug, Clone)]
pub struct EncodedPage {
    pub width: i32,
    pub height: i32,
    pub png_data: Vec<u8>,
}

impl ImageData {
    /// 创建新的 ImageData
    pub fn new(width: i32, height: i32, data: Vec<u8>) -> Self {
        Self {
            width,
            height,
            data,
            format: "RGBA8888".to_string(),
        }
    }

    /// 计算内存占用 (字节)
    pub fn memory_size(&self) -> usize {
        self.data.len()
    }

    /// 创建占位图 (用于错误情况)
    pub fn placeholder() -> Self {
        // 创建一个 64x64 的灰色占位图
        let size = 64;
        let mut data = Vec::with_capacity((size * size * 4) as usize);
        for _ in 0..(size * size) {
            data.extend_from_slice(&[128, 128, 128, 255]); // 灰色
        }
        Self::new(size, size, data)
    }
}

/// 页面缓存键
///
/// 用于 LRU 缓存的唯一标识符。
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct PageKey {
    /// 文件路径
    pub file_path: String,
    /// 页面索引
    pub page_index: usize,
}

impl PageKey {
    pub fn new(file_path: impl Into<String>, page_index: usize) -> Self {
        Self {
            file_path: file_path.into(),
            page_index,
        }
    }
}

/// 缩略图数据
///
/// 用于书架展示的缩略图。
#[derive(Debug, Clone)]
pub struct ThumbnailData {
    /// 缩略图宽度
    pub width: i32,
    /// 缩略图高度
    pub height: i32,
    /// PNG 编码的缩略图数据
    pub png_data: Vec<u8>,
}

/// 阅读进度
///
/// 记录用户的阅读位置。
#[derive(Debug, Clone)]
pub struct ReadProgress {
    /// 章节索引
    pub chapter_index: usize,
    /// 页面索引
    pub page_index: usize,
    /// 最后阅读时间戳 (毫秒)
    pub last_read_timestamp: u64,
}

/// 文件格式枚举
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ComicFormat {
    Cbz,
    Unknown,
}

impl ComicFormat {
    /// 从文件扩展名识别格式
    pub fn from_extension(ext: &str) -> Self {
        match ext.to_lowercase().as_str() {
            "cbz" | "zip" => ComicFormat::Cbz,
            _ => ComicFormat::Unknown,
        }
    }

    /// 获取格式字符串
    pub fn as_str(&self) -> &'static str {
        match self {
            ComicFormat::Cbz => "cbz",
            ComicFormat::Unknown => "unknown",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_image_data_memory_size() {
        let data = vec![0u8; 1024];
        let img = ImageData::new(16, 16, data);
        assert_eq!(img.memory_size(), 1024);
    }

    #[test]
    fn test_image_data_placeholder() {
        let placeholder = ImageData::placeholder();
        assert_eq!(placeholder.width, 64);
        assert_eq!(placeholder.height, 64);
        assert_eq!(placeholder.format, "RGBA8888");
    }

    #[test]
    fn test_comic_format_from_extension() {
        assert_eq!(ComicFormat::from_extension("cbz"), ComicFormat::Cbz);
        assert_eq!(ComicFormat::from_extension("CBZ"), ComicFormat::Cbz);
        assert_eq!(ComicFormat::from_extension("zip"), ComicFormat::Cbz);
        assert_eq!(ComicFormat::from_extension("unknown"), ComicFormat::Unknown);
    }

    #[test]
    fn test_page_key_equality() {
        let key1 = PageKey::new("/path/to/file.cbz", 5);
        let key2 = PageKey::new("/path/to/file.cbz", 5);
        let key3 = PageKey::new("/path/to/file.cbz", 6);

        assert_eq!(key1, key2);
        assert_ne!(key1, key3);
    }
}

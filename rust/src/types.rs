//! 数据类型模块
//!
//! 定义漫画引擎的核心数据结构：
//! - 漫画文件信息 (ComicInfo)
//! - 章节信息 (ChapterInfo)
//! - 页面尺寸 (PageDimensions)
//! - 文件格式 (ComicFormat)

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

/// Immutable page geometry used to lay out continuous reading before decode.
#[derive(Debug, Clone, Copy)]
pub struct PageDimensions {
    pub width: i32,
    pub height: i32,
}

impl PageDimensions {
    pub fn fallback() -> Self {
        Self {
            width: 10,
            height: 14,
        }
    }
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
    fn test_comic_format_from_extension() {
        assert_eq!(ComicFormat::from_extension("cbz"), ComicFormat::Cbz);
        assert_eq!(ComicFormat::from_extension("CBZ"), ComicFormat::Cbz);
        assert_eq!(ComicFormat::from_extension("zip"), ComicFormat::Cbz);
        assert_eq!(ComicFormat::from_extension("unknown"), ComicFormat::Unknown);
    }
}

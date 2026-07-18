//! 错误处理模块
//! 
//! 提供统一的错误类型定义，用于漫画引擎的所有错误处理。
//! 所有错误都实现 `std::fmt::Display` 和 `thiserror::Error`，
//! 便于 FFI 层向 Flutter 传递友好的错误信息。

use thiserror::Error;

/// 漫画引擎统一错误类型
/// 
/// 所有可能的错误场景都归类到此枚举，便于 Flutter 侧统一处理。
#[derive(Error, Debug, Clone, PartialEq)]
pub enum ComicError {
    /// 文件不存在
    #[error("文件不存在：{0}")]
    FileNotFound(String),
    
    /// 文件无法访问 (权限问题)
    #[error("无法访问文件：{0}")]
    FileAccessDenied(String),
    
    /// 不支持的文件格式
    #[error("不支持的格式：{0}")]
    UnsupportedFormat(String),
    
    /// 解压错误 (ZIP/RAR)
    #[error("解压失败：{0}")]
    ArchiveError(String),
    
    /// 图像解码错误
    #[error("图像解码失败：{0}")]
    DecodeError(String),
    
    
    /// 页面索引越界
    #[error("页面索引越界：请求 {requested}, 总数 {total}")]
    PageIndexOutOfBounds {
        requested: usize,
        total: usize,
    },
    
    /// 内存不足
    #[error("内存不足：需要 {needed}MB, 可用 {available}MB")]
    OutOfMemory {
        needed: usize,
        available: usize,
    },
    
    /// 缓存错误
    #[error("缓存操作失败：{0}")]
    CacheError(String),
    
    /// 排序错误
    #[error("文件排序失败：{0}")]
    SortError(String),
    
    /// 内部错误 (不应暴露给用户)
    #[error("内部错误：{0}")]
    Internal(String),
}

/// 结果类型别名
pub type Result<T> = std::result::Result<T, ComicError>;

// ============ From 转换实现 ============

impl From<zip::result::ZipError> for ComicError {
    fn from(err: zip::result::ZipError) -> Self {
        ComicError::ArchiveError(err.to_string())
    }
}


impl From<image::ImageError> for ComicError {
    fn from(err: image::ImageError) -> Self {
        ComicError::DecodeError(err.to_string())
    }
}


impl From<rusqlite::Error> for ComicError {
    fn from(err: rusqlite::Error) -> Self {
        ComicError::Internal(format!("数据库错误：{}", err))
    }
}

impl From<std::io::Error> for ComicError {
    fn from(err: std::io::Error) -> Self {
        match err.kind() {
            std::io::ErrorKind::NotFound => {
                ComicError::FileNotFound(err.to_string())
            }
            std::io::ErrorKind::PermissionDenied => {
                ComicError::FileAccessDenied(err.to_string())
            }
            _ => ComicError::Internal(err.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = ComicError::FileNotFound("test.cbz".to_string());
        assert_eq!(format!("{}", err), "文件不存在：test.cbz");
        
        let err = ComicError::PageIndexOutOfBounds { requested: 10, total: 5 };
        assert_eq!(format!("{}", err), "页面索引越界：请求 10, 总数 5");
    }

    #[test]
    fn test_result_alias() {
        let result: Result<String> = Ok("success".to_string());
        assert_eq!(result.unwrap(), "success");
        
        let result: Result<String> = Err(ComicError::FileNotFound("x".to_string()));
        assert!(result.is_err());
    }
}

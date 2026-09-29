//! 漫画阅读器的 Rust 后端：ZIP 读取、元数据与存储
//!
//! 图像解码不在这里。阅读器拿到的是压缩包里的**原始编码字节**，由 Flutter 的
//! 图片管线按显示尺寸解码并缓存 —— 只有一份解码缓存，也避免了「全分辨率解码
//! 再缩放」的内存峰值。
//!
//! # 架构
//! ```text
//! lib.rs (入口)
//! ├── api/              # FFI 接口 (flutter_rust_bridge)
//! ├── archive.rs        # 压缩包解压 (CBZ)
//! ├── cache/archive.rs  # 已打开的 ZIP 句柄 + 页表缓存
//! ├── library/          # 图书馆、数据库和阅读进度
//! ├── metadata.rs       # ComicInfo.xml 与封面缩略图
//! ├── sort.rs           # 自然排序
//! ├── types.rs          # 数据类型定义
//! └── error.rs          # 错误处理
//! ```
//!
//! # 快速开始
//! ```rust,no_run
//! use rust_lib_zephyr_comics::api::{init::init_app, reader::get_comic_info};
//!
//! init_app();
//! let info = get_comic_info("path/to/comic.cbz".to_string()).unwrap();
//! ```

pub mod api;
mod frb_generated;

// 核心模块
mod archive;
mod cache;
mod error;
mod library;
mod metadata;
mod sort;
mod types;

// 生成绑定使用的兼容模块名，保持可解析
mod archive_cache {
    pub use crate::cache::archive::*;
}
mod library_db {
    pub use crate::library::db::*;
}
mod library_scanner {
    pub use crate::library::scanner::*;
}
mod reading_progress {
    pub use crate::library::progress::*;
}

// 重新导出常用类型，方便外部使用
pub use archive_cache::{
    clear_global_cache, get_global_archive_cache, get_global_cache_stats, set_global_cache_size,
    ArchiveCache, ArchiveCacheStats,
};
pub use error::{ComicError, Result};
pub use library_db::{DerivedCacheStats, LibraryDatabase, LibraryEntry};
pub use library_scanner::LibraryScanner;
pub use metadata::ComicMetadata;
pub use reading_progress::{Bookmark, ReadingProgress, ReadingStats};
pub use types::{ChapterInfo, ComicFormat, ComicInfo, PageDimensions};

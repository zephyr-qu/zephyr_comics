//! 纯净漫画阅读器 Rust 图像引擎
//!
//! 高性能漫画图像解码引擎，支持：
//! - CBZ (ZIP) 格式解压
//! - 并行图像解码
//! - LRU 内存缓存 + 磁盘缓存
//! - 智能文件名排序
//!
//! # 架构
//! ```text
//! lib.rs (入口)
//! ├── api/       # FFI 接口 (flutter_rust_bridge)
//! ├── archive.rs       # 压缩包解压 (CBZ)
//! ├── decoder.rs       # 图像解码 (并行处理)
//! ├── cache/           # 内存、磁盘和压缩包缓存
//! ├── library/         # 图书馆、数据库和阅读进度
//! ├── preload/         # 预加载策略
//! ├── sort.rs          # 智能排序
//! ├── types.rs         # 数据类型定义
//! └── error.rs         # 错误处理
//! ```
//!
//! # 快速开始
//! ```rust,no_run
//! use rust_lib_zephyr_comics::api::{init::init_app, reader::{get_comic_info, get_page_image}};
//!
//! // 1. 初始化引擎
//! init_app();
//!
//! // 2. 获取漫画信息
//! let info = get_comic_info("path/to/comic.cbz".to_string()).unwrap();
//!
//! // 3. 解码页面 (异步)
//! // let image = get_page_image("path/to/comic.cbz".to_string(), 0, 2048, 4096).await;
//! ```

pub mod api;
mod frb_generated;

// 核心模块
mod archive;
mod cache;
mod decoder;
mod error;
mod library;
mod preload;
mod sort;
mod types;

// 扩展模块
mod metadata;
mod archive_cache {
    pub use crate::cache::archive::*;
}
mod disk_cache {
    pub use crate::cache::disk::*;
}
mod library_db {
    pub use crate::library::db::*;
}
mod library_scanner {
    pub use crate::library::scanner::*;
}
mod preload_strategy {
    pub use crate::preload::strategy::*;
}
mod reading_progress {
    pub use crate::library::progress::*;
}

// 重新导出常用类型，方便外部使用
pub use archive_cache::{
    clear_global_cache, get_global_archive_cache, get_global_cache_stats, set_global_cache_size,
    ArchiveCache, ArchiveCacheStats,
};
pub use cache::{CacheStats, ImageCache, SharedImageCache};
pub use decoder::{DecoderConfig, ImageDecoder};
pub use disk_cache::{DiskCache, DiskCacheConfig, DiskCacheStats, SharedDiskCache};
pub use error::{ComicError, Result};
pub use library_db::{LibraryDatabase, LibraryEntry};
pub use library_scanner::LibraryScanner;
pub use metadata::ComicMetadata;
pub use preload_strategy::{PreloadStrategy, ReadingDirection};
pub use reading_progress::{Bookmark, ReadingProgress, ReadingStats};
pub use types::{
    ChapterInfo, ComicFormat, ComicInfo, ImageData, PageKey, ReadProgress, ThumbnailData,
};

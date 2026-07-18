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
//! ├── archive/   # 压缩包解压 (CBZ)
//! ├── decoder/   # 图像解码 (并行处理)
//! ├── cache/     # LRU 缓存管理 (内存 + 磁盘)
//! ├── sort/      # 智能排序
//! ├── types/     # 数据类型定义
//! └── error/     # 错误处理
//! ```
//!
//! # 快速开始
//! ```rust,no_run
//! use rust_lib_zephyr_comics::api::comic::{init_app, get_comic_info, get_page_image};
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
mod error;
mod types;
mod sort;
mod cache;
mod archive;
mod decoder;

// 扩展模块
mod disk_cache;
mod preload_strategy;
mod reading_progress;
mod library_db;
mod metadata;
mod library_scanner;
mod archive_cache;

// 重新导出常用类型，方便外部使用
pub use error::{ComicError, Result};
pub use types::{
    ChapterInfo, ComicFormat, ComicInfo, ImageData, PageKey, ReadProgress,
    ThumbnailData,
};
pub use cache::{CacheStats, ImageCache, SharedImageCache};
pub use decoder::{DecoderConfig, ImageDecoder};
pub use disk_cache::{DiskCache, DiskCacheConfig, DiskCacheStats, SharedDiskCache};
pub use preload_strategy::{PreloadStrategy, ReadingDirection};
pub use reading_progress::{ReadingProgress, Bookmark, ReadingStats};
pub use library_db::{LibraryDatabase, LibraryEntry};
pub use metadata::ComicMetadata;
pub use library_scanner::LibraryScanner;
pub use archive_cache::{ArchiveCache, ArchiveCacheStats, get_global_archive_cache, set_global_cache_size, get_global_cache_stats, clear_global_cache};

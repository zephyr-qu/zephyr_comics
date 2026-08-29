//! 引擎全局初始化：缓存、解码器、预加载管理器与数据库引导。



use flutter_rust_bridge::frb;
use std::sync::{Arc, Mutex, OnceLock};
use crate::cache::SharedImageCache;
use crate::decoder::{DecoderConfig, ImageDecoder};
use crate::disk_cache::{DiskCacheConfig, SharedDiskCache};
use crate::library_db::init_global_db;
use crate::preload_strategy::{PreloadManager, PreloadStrategy};

/// 全局缓存实例 (懒初始化)
pub(crate) static IMAGE_CACHE: OnceLock<SharedImageCache> = OnceLock::new();

/// 全局磁盘缓存实例 (懒初始化)
pub(crate) static DISK_CACHE: OnceLock<SharedDiskCache> = OnceLock::new();

/// 全局预加载管理器 (懒初始化)
pub(crate) static PRELOAD_MANAGER: OnceLock<Arc<Mutex<PreloadManager>>> = OnceLock::new();

/// 全局解码器实例 (懒初始化)
pub(crate) static DECODER: OnceLock<ImageDecoder> = OnceLock::new();

/// 默认缓存大小 (MB)
pub(crate) const DEFAULT_CACHE_SIZE_MB: usize = 100;

/// 默认最大图片宽度
pub(crate) const DEFAULT_MAX_WIDTH: u32 = 2048;

/// 默认最大图片高度
pub(crate) const DEFAULT_MAX_HEIGHT: u32 = 4096;

/// 初始化漫画引擎
///
/// 必须在调用其他接口前调用此函数。
#[frb(init)]
pub fn init_app() {
    // 初始化日志
    #[cfg(target_os = "android")]
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Info)
            .with_tag("ZephyrComics"),
    );

    #[cfg(not(target_os = "android"))]
    let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .try_init();

    // 初始化内存缓存
    let cache = SharedImageCache::new(DEFAULT_CACHE_SIZE_MB);
    IMAGE_CACHE.get_or_init(|| cache);

    // 初始化磁盘缓存
    let disk_cache_config = DiskCacheConfig::new(500); // 500MB
    if let Ok(disk_cache) = SharedDiskCache::new(disk_cache_config) {
        DISK_CACHE.get_or_init(|| disk_cache);
        log::info!("磁盘缓存初始化完成");
    } else {
        log::warn!("磁盘缓存初始化失败");
    }

    // 初始化预加载管理器
    let preload_strategy = PreloadStrategy::default();
    let preload_manager = PreloadManager::new(preload_strategy);
    PRELOAD_MANAGER.get_or_init(|| Arc::new(Mutex::new(preload_manager)));

    // 初始化解码器 (使用内存缓存)
    let config = DecoderConfig::new(DEFAULT_MAX_WIDTH, DEFAULT_MAX_HEIGHT);
    let decoder = ImageDecoder::new(config)
        .with_cache(IMAGE_CACHE.get().expect("内存缓存应该已初始化").clone());
    DECODER.get_or_init(|| decoder);

    // 初始化数据库 (阅读进度/书签/书架)
    if let Err(e) = init_global_db(None) {
        log::warn!("数据库初始化失败：{} (阅读进度等功能将不可用)", e);
    } else {
        log::info!("数据库初始化完成");
    }

    log::info!("漫画引擎初始化完成 (内存缓存 + 磁盘缓存 + 智能预加载 + 数据库)");
}

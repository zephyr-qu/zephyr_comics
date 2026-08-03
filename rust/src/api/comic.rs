//! 漫画引擎 FFI 接口
//!
//! 提供 Flutter 可调用的漫画引擎接口，使用 flutter_rust_bridge。
//!
//! # 核心接口
//! - `init_app()` - 初始化引擎
//! - `get_comic_info()` - 获取漫画文件信息
//! - `get_page_image()` - 获取指定页图片数据
//! - `generate_thumbnail()` - 生成缩略图
//! - `preload_pages()` - 预加载多页

use flutter_rust_bridge::frb;
use std::sync::{Arc, Mutex, OnceLock};

use crate::archive::{
    extract_file_from_archive, get_comic_info as archive_get_info, is_valid_comic_file,
};
use crate::archive_cache::{
    clear_global_cache, get_global_cache_stats, set_global_cache_size, ArchiveCacheStats,
};
use crate::cache::SharedImageCache;
use crate::decoder::{DecoderConfig, ImageDecoder};
use crate::disk_cache::{DiskCacheConfig, DiskCacheStats, SharedDiskCache};
use crate::error::{ComicError, Result};
use crate::library_db::{get_global_db, init_global_db, LibraryEntry};
use crate::metadata::{extract_metadata, ComicMetadata};
use crate::preload_strategy::{PreloadManager, PreloadStrategy, ReadingDirection};
use crate::reading_progress::{Bookmark, ReadingProgress, ReadingStats};
use crate::types::{ComicInfo, EncodedPage, ImageData, ThumbnailData};

/// 全局缓存实例 (懒初始化)
static IMAGE_CACHE: OnceLock<SharedImageCache> = OnceLock::new();

/// 全局磁盘缓存实例 (懒初始化)
static DISK_CACHE: OnceLock<SharedDiskCache> = OnceLock::new();

/// 全局预加载管理器 (懒初始化)
static PRELOAD_MANAGER: OnceLock<Arc<Mutex<PreloadManager>>> = OnceLock::new();

/// 全局解码器实例 (懒初始化)
static DECODER: OnceLock<ImageDecoder> = OnceLock::new();

/// 默认缓存大小 (MB)
const DEFAULT_CACHE_SIZE_MB: usize = 100;

/// 默认最大图片宽度
const DEFAULT_MAX_WIDTH: u32 = 2048;

/// 默认最大图片高度
const DEFAULT_MAX_HEIGHT: u32 = 4096;

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

/// 获取缓存统计信息
#[frb(sync)]
pub fn get_cache_stats() -> crate::cache::CacheStats {
    if let Some(cache) = IMAGE_CACHE.get() {
        cache.get_stats()
    } else {
        crate::cache::CacheStats {
            cached_images: 0,
            current_memory: 0,
            max_memory: DEFAULT_CACHE_SIZE_MB * 1024 * 1024,
            memory_usage_percent: 0,
        }
    }
}

/// 获取漫画文件信息
///
/// 分析漫画文件，返回章节列表和图片数量。
///
/// # 参数
/// * `file_path` - 漫画文件路径 (CBZ/CBR/PDF)
#[frb(sync)]
pub fn get_comic_info(file_path: String) -> Result<ComicInfo> {
    log::debug!("获取漫画信息：{}", file_path);
    archive_get_info(&file_path)
}

/// 获取指定页的图片数据
///
/// 核心接口：从压缩包中解码指定页面的图片。
///
/// # 参数
/// * `file_path` - 漫画文件路径
/// * `page_index` - 页面索引 (从 0 开始)
/// * `max_width` - 最大宽度 (用于降采样，节省内存)
/// * `max_height` - 最大高度
///
/// # 返回
/// 解码后的图像数据 (RGBA8888 格式)
#[frb(dart_async)]
pub async fn get_page_image(
    file_path: String,
    page_index: i32,
    max_width: i32,
    max_height: i32,
) -> Result<ImageData> {
    log::debug!(
        "解码页面：{} #{} ({}x{})",
        file_path,
        page_index,
        max_width,
        max_height
    );

    // 获取漫画信息以获取文件列表
    let info = archive_get_info(&file_path)?;

    if info.chapters.is_empty() {
        return Err(ComicError::ArchiveError("漫画文件为空".to_string()));
    }

    // 获取第一章节 (单章节漫画)
    let chapter = &info.chapters[0];

    if page_index < 0 || page_index as usize >= chapter.image_files.len() {
        return Err(ComicError::PageIndexOutOfBounds {
            requested: page_index as usize,
            total: chapter.image_files.len(),
        });
    }

    let file_name = &chapter.image_files[page_index as usize];
    let max_w = if max_width > 0 {
        max_width
    } else {
        DEFAULT_MAX_WIDTH as i32
    } as u32;
    let max_h = if max_height > 0 {
        max_height
    } else {
        DEFAULT_MAX_HEIGHT as i32
    } as u32;

    // 使用解码器解码
    if let Some(decoder) = DECODER.get() {
        decoder.decode_from_archive(&file_path, file_name, max_w, max_h)
    } else {
        // 解码器未初始化，使用便捷函数
        crate::decoder::decode_page(&file_path, file_name, max_w, max_h)
    }
}

/// Decode a page and return an explicitly PNG-encoded payload.
#[frb(dart_async)]
pub async fn get_page_image_png(
    file_path: String,
    page_index: i32,
    max_width: i32,
    max_height: i32,
) -> Result<EncodedPage> {
    let image = get_page_image(file_path, page_index, max_width, max_height).await?;
    encode_page_png(image)
}

/// Extract a page in its original encoded image format.
///
/// Unlike [`get_page_image_png`], this path does not decode the archive entry
/// into RGBA pixels or encode it again. The returned bytes are the original
/// encoded image payload stored in the comic archive.
#[frb(dart_async)]
pub async fn get_page_image_encoded(file_path: String, page_index: i32) -> Result<Vec<u8>> {
    extract_page_image_encoded(&file_path, page_index)
}

fn extract_page_image_encoded(file_path: &str, page_index: i32) -> Result<Vec<u8>> {
    let info = archive_get_info(file_path)?;
    let chapter = info
        .chapters
        .first()
        .ok_or_else(|| ComicError::ArchiveError("漫画文件为空".to_string()))?;

    if page_index < 0 || page_index as usize >= chapter.image_files.len() {
        return Err(ComicError::PageIndexOutOfBounds {
            requested: usize::try_from(page_index).unwrap_or(usize::MAX),
            total: chapter.image_files.len(),
        });
    }

    extract_file_from_archive(file_path, &chapter.image_files[page_index as usize])
}

fn encode_page_png(image: ImageData) -> Result<EncodedPage> {
    use image::{DynamicImage, ImageOutputFormat, RgbaImage};
    use std::io::Cursor;

    let width = u32::try_from(image.width)
        .map_err(|_| ComicError::DecodeError("图片宽度无效".to_string()))?;
    let height = u32::try_from(image.height)
        .map_err(|_| ComicError::DecodeError("图片高度无效".to_string()))?;
    let rgba = RgbaImage::from_raw(width, height, image.data)
        .ok_or_else(|| ComicError::DecodeError("RGBA 像素长度与图片尺寸不匹配".to_string()))?;
    let mut png_data = Vec::new();
    DynamicImage::ImageRgba8(rgba)
        .write_to(&mut Cursor::new(&mut png_data), ImageOutputFormat::Png)
        .map_err(|error| ComicError::DecodeError(format!("PNG 编码失败：{error}")))?;
    Ok(EncodedPage {
        width: image.width,
        height: image.height,
        png_data,
    })
}

#[cfg(test)]
mod encoded_page_tests {
    use super::*;

    #[test]
    fn encodes_rgba_as_decodable_png() {
        let encoded =
            encode_page_png(ImageData::new(2, 1, vec![255, 0, 0, 255, 0, 255, 0, 128])).unwrap();

        assert_eq!((encoded.width, encoded.height), (2, 1));
        assert_eq!(&encoded.png_data[..8], b"\x89PNG\r\n\x1a\n");
        let decoded = image::load_from_memory(&encoded.png_data)
            .unwrap()
            .to_rgba8();
        assert_eq!(decoded.dimensions(), (2, 1));
        assert_eq!(decoded.into_raw(), vec![255, 0, 0, 255, 0, 255, 0, 128]);
    }

    #[test]
    fn rejects_invalid_rgba_length() {
        let result = encode_page_png(ImageData::new(2, 2, vec![0; 4]));
        assert!(result.is_err());
    }
}

#[cfg(test)]
mod raw_encoded_page_tests {
    use super::*;
    use image::{DynamicImage, ImageOutputFormat, RgbaImage};
    use std::fs::File;
    use std::io::{Cursor, Write};
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};
    use zip::write::FileOptions;

    struct TempCbz(PathBuf);

    impl TempCbz {
        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempCbz {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
        }
    }

    fn encode(format: ImageOutputFormat) -> Vec<u8> {
        let pixels = RgbaImage::from_raw(2, 1, vec![255, 0, 0, 255, 0, 255, 0, 255])
            .expect("valid RGBA fixture");
        let mut bytes = Vec::new();
        DynamicImage::ImageRgba8(pixels)
            .write_to(&mut Cursor::new(&mut bytes), format)
            .expect("encode fixture");
        bytes
    }

    fn create_cbz(entries: &[(&str, &[u8])]) -> TempCbz {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock after epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "zephyr-raw-page-{}-{nonce}.cbz",
            std::process::id()
        ));
        let file = File::create(&path).expect("create CBZ fixture");
        let mut archive = zip::ZipWriter::new(file);
        let options = FileOptions::default().compression_method(zip::CompressionMethod::Stored);
        for (name, bytes) in entries {
            archive.start_file(*name, options).expect("start ZIP entry");
            archive.write_all(bytes).expect("write ZIP entry");
        }
        archive.finish().expect("finish CBZ fixture");
        TempCbz(path)
    }

    #[test]
    fn returns_original_jpeg_and_png_entry_bytes() {
        let jpeg = encode(ImageOutputFormat::Jpeg(90));
        let png = encode(ImageOutputFormat::Png);
        let comic = create_cbz(&[("002.png", &png), ("001.jpg", &jpeg)]);
        let path = comic.path().to_string_lossy();

        assert_eq!(extract_page_image_encoded(&path, 0).unwrap(), jpeg);
        assert_eq!(extract_page_image_encoded(&path, 1).unwrap(), png);
    }

    #[test]
    fn rejects_out_of_range_page_without_decoding() {
        let jpeg = encode(ImageOutputFormat::Jpeg(90));
        let comic = create_cbz(&[("001.jpg", &jpeg)]);
        let error = extract_page_image_encoded(&comic.path().to_string_lossy(), 1).unwrap_err();

        assert!(matches!(
            error,
            ComicError::PageIndexOutOfBounds {
                requested: 1,
                total: 1
            }
        ));
    }
}

/// 获取指定页的图片数据 (使用 ZeroCopyBuffer 优化)
///
/// 与 `get_page_image` 类似，但返回类型适合零拷贝传输。
///
/// # 注意
/// 此接口用于对性能要求极高的场景。
#[frb(dart_async)]
pub async fn get_page_image_zero_copy(
    file_path: String,
    page_index: i32,
    max_width: i32,
    max_height: i32,
) -> Result<ZeroCopyImageData> {
    let result = get_page_image(file_path, page_index, max_width, max_height).await?;
    Ok(ZeroCopyImageData {
        width: result.width,
        height: result.height,
        data: result.data,
    })
}

/// 零拷贝图像数据
///
/// 用于 FFI 零拷贝传输的图像数据结构。
#[derive(Debug, Clone)]
pub struct ZeroCopyImageData {
    /// 图像宽度
    pub width: i32,
    /// 图像高度
    pub height: i32,
    /// RGBA 像素数据
    pub data: Vec<u8>,
}

/// 生成漫画封面缩略图
///
/// 从漫画文件的第一页生成缩略图。
///
/// # 参数
/// * `file_path` - 漫画文件路径
/// * `size` - 缩略图边长 (像素)
#[frb(dart_async)]
pub async fn generate_thumbnail(file_path: String, size: i32) -> Result<ThumbnailData> {
    log::debug!("生成缩略图：{} ({}x{})", file_path, size, size);

    // 获取第一页
    let info = archive_get_info(&file_path)?;

    if info.chapters.is_empty() || info.chapters[0].image_files.is_empty() {
        return Err(ComicError::ArchiveError("漫画文件无图片".to_string()));
    }

    let first_file = &info.chapters[0].image_files[0];
    let size = size as u32;

    // 提取文件数据
    let data = crate::archive::extract_file_from_archive(&file_path, first_file)?;

    // 生成缩略图
    let png_data = crate::decoder::generate_thumbnail(&data, size)?;

    Ok(ThumbnailData {
        width: size as i32,
        height: size as i32,
        png_data,
    })
}

/// 预加载多页图片到缓存
///
/// 用于阅读器预加载功能，提前解码相邻页面。
///
/// # 参数
/// * `file_path` - 漫画文件路径
/// * `page_indices` - 要预加载的页面索引列表
/// * `max_width` - 最大宽度
/// * `max_height` - 最大高度
#[frb(dart_async)]
pub async fn preload_pages(
    file_path: String,
    page_indices: Vec<i32>,
    max_width: i32,
    max_height: i32,
) -> Result<Vec<ImageData>> {
    log::debug!("预加载页面：{:?}", page_indices);

    // 获取漫画信息
    let info = archive_get_info(&file_path)?;

    if info.chapters.is_empty() {
        return Err(ComicError::ArchiveError("漫画文件为空".to_string()));
    }

    let chapter = &info.chapters[0];
    let max_w = if max_width > 0 {
        max_width
    } else {
        DEFAULT_MAX_WIDTH as i32
    } as u32;
    let max_h = if max_height > 0 {
        max_height
    } else {
        DEFAULT_MAX_HEIGHT as i32
    } as u32;

    // 收集要加载的文件名
    let file_names: Vec<String> = page_indices
        .iter()
        .filter_map(|&idx| {
            if idx >= 0 && (idx as usize) < chapter.image_files.len() {
                Some(chapter.image_files[idx as usize].clone())
            } else {
                None
            }
        })
        .collect();

    // 并行解码
    if let Some(decoder) = DECODER.get() {
        let results = decoder.decode_multiple_from_archive(&file_path, &file_names, max_w, max_h);

        // 收集成功结果
        let mut images = Vec::with_capacity(results.len());
        for result in results {
            match result {
                Ok(img) => images.push(img),
                Err(e) => {
                    log::warn!("预加载页面失败：{}", e);
                    // 失败时返回占位图
                    images.push(ImageData::placeholder());
                }
            }
        }
        Ok(images)
    } else {
        Err(ComicError::Internal("解码器未初始化".to_string()))
    }
}

/// 清除缓存
///
/// 释放所有缓存的图片数据。
#[frb(sync)]
pub fn clear_cache() {
    log::info!("清除缓存");
    if let Some(cache) = IMAGE_CACHE.get() {
        cache.clear();
    }
}

/// 检查文件是否为有效的漫画格式
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn is_valid_comic(file_path: String) -> bool {
    is_valid_comic_file(&file_path)
}

/// 获取支持的漫画格式列表
#[frb(sync)]
pub fn get_supported_formats() -> Vec<String> {
    crate::archive::get_supported_formats()
        .into_iter()
        .map(|s| s.to_string())
        .collect()
}

/// 设置缓存大小限制
///
/// # 参数
/// * `max_memory_mb` - 最大内存占用 (MB)
#[frb(sync)]
pub fn set_cache_limit(max_memory_mb: i32) {
    if max_memory_mb > 0 {
        log::info!("设置缓存限制：{}MB", max_memory_mb);
        // 注意：OnceLock 只能设置一次，运行时修改需要重新初始化引擎
        log::warn!("缓存限制需要在初始化时设置，运行时修改需要重新初始化引擎");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_stats() {
        init_app();
        let stats = get_cache_stats();
        assert!(stats.max_memory > 0);
    }

    #[test]
    fn test_supported_formats() {
        let formats = get_supported_formats();
        assert!(formats.contains(&"cbz".to_string()));
    }

    #[test]
    fn test_is_valid_comic() {
        let fixture =
            std::env::temp_dir().join(format!("zephyr-api-valid-comic-{}", std::process::id()));
        let cbz = fixture.with_extension("cbz");
        let cbr = fixture.with_extension("cbr");
        let txt = fixture.with_extension("txt");
        for path in [&cbz, &cbr, &txt] {
            std::fs::write(path, []).expect("create comic path fixture");
        }

        assert!(is_valid_comic(cbz.to_string_lossy().into_owned()));
        assert!(!is_valid_comic(cbr.to_string_lossy().into_owned()));
        assert!(!is_valid_comic(txt.to_string_lossy().into_owned()));

        for path in [cbz, cbr, txt] {
            let _ = std::fs::remove_file(path);
        }
    }

    #[test]
    fn test_disk_cache_stats() {
        init_app();
        let stats = get_disk_cache_stats();
        assert!(stats.max_size > 0);
    }

    #[test]
    fn test_preload_strategy() {
        let pages = calculate_preload_pages(10, 50, ReadingDirection::LeftToRight);
        assert!(!pages.is_empty());
    }
}

// ============ 磁盘缓存 API ============

/// 获取磁盘缓存统计信息
#[frb(sync)]
pub fn get_disk_cache_stats() -> DiskCacheStats {
    if let Some(cache) = DISK_CACHE.get() {
        cache.get_stats()
    } else {
        DiskCacheStats {
            cached_images: 0,
            current_size: 0,
            max_size: 500 * 1024 * 1024,
            cache_dir: String::new(),
        }
    }
}

/// 清除磁盘缓存
#[frb(sync)]
pub fn clear_disk_cache() -> Result<()> {
    log::info!("清除磁盘缓存");
    if let Some(cache) = DISK_CACHE.get() {
        cache.clear()
    } else {
        Err(ComicError::CacheError("磁盘缓存未初始化".to_string()))
    }
}

/// 设置磁盘缓存大小限制
///
/// # 注意
/// 此设置需要在初始化时生效，运行时修改需要重新初始化
#[frb(sync)]
pub fn set_disk_cache_limit(max_size_mb: i32) {
    if max_size_mb > 0 {
        log::info!("设置磁盘缓存限制：{}MB", max_size_mb);
        log::warn!("磁盘缓存限制需要在初始化时设置");
    }
}

// ============ 智能预加载 API ============

/// 设置阅读方向
///
/// # 参数
/// * `direction` - 阅读方向
#[frb(sync)]
pub fn set_reading_direction(direction: ReadingDirection) {
    log::info!("设置阅读方向：{:?}", direction);
    if let Some(manager) = PRELOAD_MANAGER.get() {
        let mut mgr = manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒");
        let mut strategy = mgr.strategy().clone();
        strategy.direction = direction;
        mgr.set_strategy(strategy);
    }
}

/// 获取当前阅读方向
#[frb(sync)]
pub fn get_reading_direction() -> ReadingDirection {
    if let Some(manager) = PRELOAD_MANAGER.get() {
        manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒")
            .strategy()
            .direction
    } else {
        ReadingDirection::LeftToRight
    }
}

/// 计算需要预加载的页面
///
/// # 参数
/// * `current_page` - 当前页面索引
/// * `total_pages` - 总页数
/// * `direction` - 阅读方向
#[frb(sync)]
pub fn calculate_preload_pages(
    current_page: usize,
    total_pages: usize,
    direction: ReadingDirection,
) -> Vec<usize> {
    let strategy = PreloadStrategy::new(direction);
    strategy.calculate_pages_to_preload(current_page, total_pages)
}

/// 智能计算预加载页面
///
/// # 参数
/// * `current_page` - 当前页面索引
/// * `total_pages` - 总页数
/// * `reading_speed_ms` - 阅读速度 (毫秒/页)
#[frb(sync)]
pub fn calculate_smart_preload_pages(
    current_page: usize,
    total_pages: usize,
    reading_speed_ms: u64,
) -> Vec<usize> {
    if let Some(manager) = PRELOAD_MANAGER.get() {
        let mgr = manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒");
        mgr.strategy()
            .calculate_smart_pages(current_page, total_pages, reading_speed_ms)
    } else {
        let strategy = PreloadStrategy::default();
        strategy.calculate_smart_pages(current_page, total_pages, reading_speed_ms)
    }
}

/// 设置预加载策略
///
/// # 参数
/// * `base_count` - 基础预加载数量
/// * `max_count` - 最大预加载数量
/// * `enable_smart` - 是否启用智能预取
#[frb(sync)]
pub fn set_preload_strategy(base_count: i32, max_count: i32, enable_smart: bool) {
    if let Some(manager) = PRELOAD_MANAGER.get() {
        let mut mgr = manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒");
        let mut strategy = mgr.strategy().clone();
        strategy.base_preload_count = base_count as usize;
        strategy.max_preload_count = max_count as usize;
        strategy.enable_smart_preload = enable_smart;
        mgr.set_strategy(strategy);
        log::info!(
            "设置预加载策略：base={}, max={}, smart={}",
            base_count,
            max_count,
            enable_smart
        );
    }
}

/// 获取下一个页面索引
///
/// # 参数
/// * `current_page` - 当前页面索引
/// * `total_pages` - 总页数
#[frb(sync)]
pub fn get_next_page(current_page: usize, total_pages: usize) -> Option<usize> {
    if let Some(manager) = PRELOAD_MANAGER.get() {
        let mgr = manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒");
        mgr.strategy().next_page(current_page, total_pages)
    } else {
        let strategy = PreloadStrategy::default();
        strategy.next_page(current_page, total_pages)
    }
}

/// 获取上一个页面索引
///
/// # 参数
/// * `current_page` - 当前页面索引
/// * `total_pages` - 总页数
#[frb(sync)]
pub fn get_prev_page(current_page: usize, total_pages: usize) -> Option<usize> {
    if let Some(manager) = PRELOAD_MANAGER.get() {
        let mgr = manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒");
        mgr.strategy().prev_page(current_page, total_pages)
    } else {
        let strategy = PreloadStrategy::default();
        strategy.prev_page(current_page, total_pages)
    }
}

/// 取消所有预加载任务
#[frb(sync)]
pub fn cancel_all_preload_tasks() {
    log::info!("取消所有预加载任务");
    if let Some(manager) = PRELOAD_MANAGER.get() {
        let mut mgr = manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒");
        mgr.cancel_all();
    }
}

/// 取消指定文件的预加载任务
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn cancel_preload_tasks_for_file(file_path: String) {
    log::info!("取消文件预加载任务：{}", file_path);
    if let Some(manager) = PRELOAD_MANAGER.get() {
        let mut mgr = manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒");
        mgr.cancel_for_file(&file_path);
    }
}

/// 获取待处理预加载任务数量
#[frb(sync)]
pub fn get_pending_preload_tasks() -> usize {
    if let Some(manager) = PRELOAD_MANAGER.get() {
        manager
            .lock()
            .map_err(|e| ComicError::Internal(format!("预加载管理器锁中毒：{}", e)))
            .expect("预加载管理器锁不应该中毒")
            .pending_count()
    } else {
        0
    }
}

// ============ 阅读进度 API ============

/// 保存阅读进度
///
/// # 参数
/// * `progress` - 阅读进度信息
#[frb(sync)]
pub fn save_reading_progress(progress: ReadingProgress) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.save_reading_progress(&progress)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 获取阅读进度
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn get_reading_progress(file_path: String) -> Option<ReadingProgress> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()?
            .get_reading_progress(&file_path)
            .ok()
            .flatten()
    } else {
        None
    }
}

/// 获取阅读历史
///
/// # 参数
/// * `limit` - 返回数量限制
#[frb(sync)]
pub fn get_reading_history(limit: i32) -> Vec<ReadingProgress> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_reading_history(limit as usize).ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// Hide one history entry without deleting its progress or bookmarks.
#[frb(sync)]
pub fn hide_reading_history(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.hide_reading_history(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 删除阅读进度
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn remove_reading_progress(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.remove_reading_progress(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

// ============ 书签 API ============

/// 添加书签
///
/// # 参数
/// * `file_path` - 文件路径
/// * `page_index` - 页面索引
/// * `note` - 备注 (可选)
#[frb(sync)]
pub fn add_bookmark(file_path: String, page_index: i32, note: Option<String>) -> Result<Bookmark> {
    let bookmark = Bookmark::new(file_path, page_index as usize, note);

    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.add_bookmark(&bookmark)?;
        Ok(bookmark)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 移除书签
///
/// # 参数
/// * `file_path` - 文件路径
/// * `page_index` - 页面索引
#[frb(sync)]
pub fn remove_bookmark(file_path: String, page_index: i32) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.remove_bookmark(&file_path, page_index as usize)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 获取书签列表
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn get_bookmarks(file_path: String) -> Vec<Bookmark> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_bookmarks(&file_path).ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取所有书签
#[frb(sync)]
pub fn get_all_bookmarks() -> Vec<Bookmark> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_all_bookmarks().ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取阅读统计
#[frb(sync)]
pub fn get_reading_stats() -> ReadingStats {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_reading_stats().ok())
            .unwrap_or_default()
    } else {
        ReadingStats::default()
    }
}

// ============ 图书馆管理 API ============

/// 提取漫画元数据
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn extract_comic_metadata(file_path: String) -> Result<ComicMetadata> {
    extract_metadata(&file_path)
}

/// 扫描目录添加到图书馆
///
/// # 参数
/// * `path` - 目录路径
#[frb(sync)]
pub fn scan_directory_to_library(path: String) -> Result<Vec<LibraryEntry>> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        crate::library_scanner::scan_directory_to_library(&db_guard, &path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 获取图书馆所有漫画
#[frb(sync)]
pub fn get_library_entries() -> Vec<LibraryEntry> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_library_entries().ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 搜索图书馆
///
/// # 参数
/// * `query` - 搜索关键词
#[frb(sync)]
pub fn search_library(query: String) -> Vec<LibraryEntry> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.search_library(&query).ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 获取最近添加的漫画
///
/// # 参数
/// * `limit` - 返回数量限制
#[frb(sync)]
pub fn get_recently_added(limit: i32) -> Vec<LibraryEntry> {
    if let Some(db) = get_global_db() {
        db.lock()
            .map_err(|e| {
                log::error!("数据库锁中毒：{}", e);
                ComicError::Internal(format!("数据库锁中毒：{}", e))
            })
            .ok()
            .and_then(|db_guard| db_guard.get_recently_added(limit as usize).ok())
            .unwrap_or_default()
    } else {
        Vec::new()
    }
}

/// 从图书馆移除
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn remove_from_library(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.remove_from_library(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

/// 更新最后打开时间
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn update_last_opened(file_path: String) -> Result<()> {
    if let Some(db) = get_global_db() {
        let db_guard = db
            .lock()
            .map_err(|e| ComicError::Internal(format!("数据库锁中毒：{}", e)))?;
        db_guard.update_last_opened(&file_path)
    } else {
        Err(ComicError::Internal("数据库未初始化".to_string()))
    }
}

#[cfg(test)]
mod testsaa {
    use super::*;

    // #[test]
    // fn test_cache_stats() {
    //     init_app();
    //     let stats = get_cache_stats();
    //     assert!(stats.max_memory_kb > 0);
    // }

    #[test]
    fn test_supported_formats() {
        let formats = get_supported_formats();
        assert!(formats.contains(&"cbz".to_string()));
    }

    #[test]
    fn test_is_valid_comic() {
        let fixture = std::env::temp_dir().join(format!(
            "zephyr-api-legacy-valid-comic-{}",
            std::process::id()
        ));
        let cbz = fixture.with_extension("cbz");
        let cbr = fixture.with_extension("cbr");
        let txt = fixture.with_extension("txt");
        for path in [&cbz, &cbr, &txt] {
            std::fs::write(path, []).expect("create comic path fixture");
        }

        assert!(is_valid_comic(cbz.to_string_lossy().into_owned()));
        assert!(!is_valid_comic(cbr.to_string_lossy().into_owned()));
        assert!(!is_valid_comic(txt.to_string_lossy().into_owned()));

        for path in [cbz, cbr, txt] {
            let _ = std::fs::remove_file(path);
        }
    }

    #[test]
    fn test_disk_cache_stats() {
        init_app();
        let stats = get_disk_cache_stats();
        assert!(stats.max_size > 0);
    }

    #[test]
    fn test_preload_strategy() {
        let pages = calculate_preload_pages(10, 50, ReadingDirection::LeftToRight);
        assert!(!pages.is_empty());
    }

    #[test]
    fn test_reading_progress() {
        init_app();

        let progress = ReadingProgress::new("test.cbz".to_string(), 0, 5);
        let result = save_reading_progress(progress);
        assert!(result.is_ok());

        let retrieved = get_reading_progress("test.cbz".to_string());
        assert!(retrieved.is_some());
    }

    #[test]
    fn test_bookmark() {
        init_app();

        let result = add_bookmark("test.cbz".to_string(), 10, Some("test".to_string()));
        assert!(result.is_ok());

        let bookmarks = get_bookmarks("test.cbz".to_string());
        assert_eq!(bookmarks.len(), 1);

        remove_bookmark("test.cbz".to_string(), 10).unwrap();
        let bookmarks = get_bookmarks("test.cbz".to_string());
        assert!(bookmarks.is_empty());
    }

    #[test]
    fn test_library_operations() {
        init_app();

        // 获取图书馆列表 (应该为空)
        let entries = get_library_entries();
        assert!(entries.is_empty());

        // 搜索 (应该为空)
        let results = search_library("test".to_string());
        assert!(results.is_empty());
    }

    #[test]
    fn test_archive_cache() {
        init_app();

        let stats = get_archive_cache_stats();
        assert!(stats.max_handles >= 5);

        set_archive_cache_size(10);
        let stats = get_archive_cache_stats();
        assert_eq!(stats.max_handles, 10);
    }
}

// ============ 压缩包缓存 API (P0 性能优化) ============

/// 设置压缩包缓存大小
///
/// # 参数
/// * `max_handles` - 最大缓存句柄数 (推荐 5-10)
#[frb(sync)]
pub fn set_archive_cache_size(max_handles: i32) {
    if max_handles > 0 {
        log::info!("设置压缩包缓存大小：{}", max_handles);
        set_global_cache_size(max_handles as usize);
    }
}

/// 获取压缩包缓存统计
#[frb(sync)]
pub fn get_archive_cache_stats() -> ArchiveCacheStats {
    get_global_cache_stats()
}

/// 清空压缩包缓存
#[frb(sync)]
pub fn clear_archive_cache() {
    log::info!("清空压缩包缓存");
    clear_global_cache();
}

//! 漫画页面解码、预加载、缩略图与格式校验接口。

use crate::api::init::{DECODER, DEFAULT_MAX_HEIGHT, DEFAULT_MAX_WIDTH, PRELOAD_MANAGER};
use crate::archive::{
    extract_file_from_archive, extract_file_prefix_from_archive,
    get_comic_info as archive_get_info, is_valid_comic_file,
};
use crate::error::{ComicError, Result};
use crate::metadata::{extract_metadata, ComicMetadata};
use crate::preload_strategy::{PreloadManager, PreloadStrategy, ReadingDirection};
use crate::types::{ComicInfo, EncodedPage, ImageData, PageDimensions, ThumbnailData};
use flutter_rust_bridge::frb;

/// Run a blocking archive/decode operation on the blocking pool instead of an
/// async worker thread. `zip`, `image`, and `rusqlite` are synchronous, so
/// calling them from an async fn would stall the runtime for every other task.
async fn blocking<T, F>(work: F) -> Result<T>
where
    F: FnOnce() -> Result<T> + Send + 'static,
    T: Send + 'static,
{
    tokio::task::spawn_blocking(work)
        .await
        .map_err(|error| ComicError::Internal(format!("后台任务失败：{}", error)))?
}

/// Lock the preload manager, recovering from a poisoned mutex rather than
/// panicking across the FFI boundary.
fn preload_manager() -> Option<std::sync::MutexGuard<'static, PreloadManager>> {
    PRELOAD_MANAGER.get().map(|manager| {
        manager.lock().unwrap_or_else(|error| {
            log::error!("预加载管理器锁中毒，继续使用：{}", error);
            error.into_inner()
        })
    })
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

/// Read every page's geometry before Flutter builds a continuous scroll list.
///
/// Only an encoded-image prefix is inspected in the common case; pixels are
/// never decoded and the original page payload remains the reader fast path.
#[frb(dart_async)]
pub async fn get_comic_page_dimensions(file_path: String) -> Result<Vec<PageDimensions>> {
    blocking(move || extract_comic_page_dimensions(&file_path)).await
}

const DIMENSION_PREFIX_BYTES: usize = 256 * 1024;

fn extract_comic_page_dimensions(file_path: &str) -> Result<Vec<PageDimensions>> {
    let info = archive_get_info(file_path)?;
    let chapter = info
        .chapters
        .first()
        .ok_or_else(|| ComicError::ArchiveError("漫画文件为空".to_string()))?;

    Ok(chapter
        .image_files
        .iter()
        .enumerate()
        .map(|(index, file_name)| {
            let dimensions =
                extract_file_prefix_from_archive(file_path, file_name, DIMENSION_PREFIX_BYTES)
                    .and_then(|prefix| read_encoded_dimensions(&prefix))
                    .or_else(|_| {
                        extract_file_from_archive(file_path, file_name)
                            .and_then(|encoded| read_encoded_dimensions(&encoded))
                    });
            dimensions.unwrap_or_else(|error| {
                log::warn!(
                    "读取页面尺寸失败，使用稳定回退比例：{} #{} ({})",
                    file_path,
                    index,
                    error
                );
                PageDimensions::fallback()
            })
        })
        .collect())
}

fn read_encoded_dimensions(encoded: &[u8]) -> Result<PageDimensions> {
    let reader = image::io::Reader::new(std::io::Cursor::new(encoded))
        .with_guessed_format()
        .map_err(|error| ComicError::DecodeError(format!("无法识别图片格式：{error}")))?;
    let (width, height) = reader
        .into_dimensions()
        .map_err(|error| ComicError::DecodeError(format!("无法读取图片尺寸：{error}")))?;
    Ok(PageDimensions {
        width: i32::try_from(width)
            .map_err(|_| ComicError::DecodeError("图片宽度超出支持范围".to_string()))?,
        height: i32::try_from(height)
            .map_err(|_| ComicError::DecodeError("图片高度超出支持范围".to_string()))?,
    })
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

    blocking(move || decode_page_image(&file_path, page_index, max_width, max_height)).await
}

/// Synchronous core of [`get_page_image`]; runs on the blocking pool.
fn decode_page_image(
    file_path: &str,
    page_index: i32,
    max_width: i32,
    max_height: i32,
) -> Result<ImageData> {
    // 获取漫画信息以获取文件列表
    let info = archive_get_info(file_path)?;

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
        decoder.decode_from_archive(file_path, file_name, max_w, max_h)
    } else {
        // 解码器未初始化，使用便捷函数
        crate::decoder::decode_page(file_path, file_name, max_w, max_h)
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
    blocking(move || encode_page_png(image)).await
}

/// Extract a page in its original encoded image format.
///
/// Unlike [`get_page_image_png`], this path does not decode the archive entry
/// into RGBA pixels or encode it again. The returned bytes are the original
/// encoded image payload stored in the comic archive.
#[frb(dart_async)]
pub async fn get_page_image_encoded(file_path: String, page_index: i32) -> Result<Vec<u8>> {
    blocking(move || extract_page_image_encoded(&file_path, page_index)).await
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

    blocking(move || build_thumbnail(&file_path, size)).await
}

/// Synchronous core of [`generate_thumbnail`]; runs on the blocking pool.
fn build_thumbnail(file_path: &str, size: i32) -> Result<ThumbnailData> {
    // 获取第一页
    let info = archive_get_info(file_path)?;

    if info.chapters.is_empty() || info.chapters[0].image_files.is_empty() {
        return Err(ComicError::ArchiveError("漫画文件无图片".to_string()));
    }

    let first_file = &info.chapters[0].image_files[0];
    let size = size as u32;

    // 提取文件数据
    let data = crate::archive::extract_file_from_archive(file_path, first_file)?;

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

    blocking(move || preload_page_images(&file_path, page_indices, max_width, max_height)).await
}

/// Synchronous core of [`preload_pages`]; runs on the blocking pool.
fn preload_page_images(
    file_path: &str,
    page_indices: Vec<i32>,
    max_width: i32,
    max_height: i32,
) -> Result<Vec<ImageData>> {
    // 获取漫画信息
    let info = archive_get_info(file_path)?;

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
        let results = decoder.decode_multiple_from_archive(file_path, &file_names, max_w, max_h);

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

/// 设置阅读方向
///
/// # 参数
/// * `direction` - 阅读方向
#[frb(sync)]
pub fn set_reading_direction(direction: ReadingDirection) {
    log::info!("设置阅读方向：{:?}", direction);
    if let Some(mut mgr) = preload_manager() {
        let mut strategy = mgr.strategy().clone();
        strategy.direction = direction;
        mgr.set_strategy(strategy);
    }
}

/// 获取当前阅读方向
#[frb(sync)]
pub fn get_reading_direction() -> ReadingDirection {
    preload_manager()
        .map(|mgr| mgr.strategy().direction)
        .unwrap_or(ReadingDirection::LeftToRight)
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
    if let Some(mgr) = preload_manager() {
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
    if let Some(mut mgr) = preload_manager() {
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
    if let Some(mgr) = preload_manager() {
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
    if let Some(mgr) = preload_manager() {
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
    if let Some(mut mgr) = preload_manager() {
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
    if let Some(mut mgr) = preload_manager() {
        mgr.cancel_for_file(&file_path);
    }
}

/// 获取待处理预加载任务数量
#[frb(sync)]
pub fn get_pending_preload_tasks() -> usize {
    preload_manager()
        .map(|mgr| mgr.pending_count())
        .unwrap_or(0)
}

/// 提取漫画元数据
///
/// # 参数
/// * `file_path` - 文件路径
#[frb(sync)]
pub fn extract_comic_metadata(file_path: String) -> Result<ComicMetadata> {
    extract_metadata(&file_path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{DynamicImage, ImageOutputFormat, RgbaImage};
    use std::fs::File;
    use std::io::{Cursor, Write};
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};
    use zip::write::FileOptions;

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
    fn reads_stable_page_geometry_without_pixel_decode() {
        let jpeg = encode(ImageOutputFormat::Jpeg(90));
        let png = encode(ImageOutputFormat::Png);
        let comic = create_cbz(&[("002.png", &png), ("001.jpg", &jpeg)]);

        let dimensions = extract_comic_page_dimensions(&comic.path().to_string_lossy()).unwrap();

        assert_eq!(dimensions.len(), 2);
        assert_eq!((dimensions[0].width, dimensions[0].height), (2, 1));
        assert_eq!((dimensions[1].width, dimensions[1].height), (2, 1));
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
    fn test_preload_strategy() {
        let pages = calculate_preload_pages(10, 50, ReadingDirection::LeftToRight);
        assert!(!pages.is_empty());
    }
}

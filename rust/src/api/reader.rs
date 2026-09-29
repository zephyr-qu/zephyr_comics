//! 漫画读取接口：文件信息、页面尺寸与原始页面字节。
//!
//! 这里不做像素解码 —— 页面以压缩包里的原始编码格式交给 Flutter，
//! 由 Flutter 的图片管线按显示尺寸解码并缓存。

use crate::archive::get_comic_info as archive_get_info;
use crate::error::{ComicError, Result};
use crate::types::{ComicInfo, PageDimensions};
use flutter_rust_bridge::frb;

/// Run a blocking archive operation on the blocking pool instead of an async
/// worker thread. `zip` is synchronous, so calling it from an async fn would
/// stall the runtime for every other task.
async fn blocking<T, F>(work: F) -> Result<T>
where
    F: FnOnce() -> Result<T> + Send + 'static,
    T: Send + 'static,
{
    tokio::task::spawn_blocking(work)
        .await
        .map_err(|error| ComicError::Internal(format!("后台任务失败：{}", error)))?
}

/// 获取漫画文件信息
///
/// 分析漫画文件，返回章节列表和图片数量。
///
/// # 参数
/// * `file_path` - 漫画文件路径 (CBZ/ZIP)
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

/// How much of a page to read when only its dimensions are needed. Image
/// headers live in the first few KB; oversized EXIF/ICC segments can push the
/// JPEG SOF marker further, and `extract_comic_page_dimensions` falls back to a
/// full entry read when the prefix is not enough — so this stays generous
/// rather than forcing a whole-page read on an album of profiled scans.
const DIMENSION_PREFIX_BYTES: usize = 64 * 1024;

fn extract_comic_page_dimensions(file_path: &str) -> Result<Vec<PageDimensions>> {
    // Resolve the page count once, then read each page *by index*: the page table
    // stays in the archive cache instead of being cloned out per page.
    let page_count = crate::archive_cache::page_count_from_cache(file_path)?;

    Ok((0..page_count)
        .map(|index| {
            let dimensions = crate::archive_cache::extract_page_prefix_from_cache(
                file_path,
                index,
                DIMENSION_PREFIX_BYTES,
            )
            .and_then(|prefix| read_encoded_dimensions(&prefix))
            .or_else(|_| {
                crate::archive_cache::extract_page_from_cache(file_path, index)
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

/// Extract a page in its original encoded image format.
///
/// The returned bytes are the original encoded image payload stored in the
/// comic archive: no RGBA decode and no re-encode.
#[frb(dart_async)]
pub async fn get_page_image_encoded(file_path: String, page_index: i32) -> Result<Vec<u8>> {
    blocking(move || extract_page_image_encoded(&file_path, page_index)).await
}

fn extract_page_image_encoded(file_path: &str, page_index: i32) -> Result<Vec<u8>> {
    // A negative index maps to `usize::MAX`, so the cache's bounds check reports
    // the same out-of-range error it did before, with the real page count.
    let index = usize::try_from(page_index).unwrap_or(usize::MAX);
    crate::archive_cache::extract_page_from_cache(file_path, index)
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
}

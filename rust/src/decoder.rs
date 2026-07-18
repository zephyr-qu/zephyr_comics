//! 图像解码模块
//!
//! 使用 `image` crate 和 `rayon` 并行处理实现高性能图像解码。
//!
//! # 特性
//! - 支持 JPEG, PNG, WebP, GIF, BMP 等格式
//! - 并行解码多张图片
//! - 限制最大解码尺寸，防止内存爆炸
//! - 降采样解码 (根据目标尺寸)
//! - 两级缓存 (内存 + 磁盘)
//! - 图像后处理 (滤镜)

use std::io::Cursor;
use image::{GenericImageView, ImageFormat};
use rayon::prelude::*;

use crate::archive::extract_file_from_archive;
use crate::cache::{clamp_image_dimensions, SharedImageCache};
use crate::disk_cache::SharedDiskCache;
use crate::error::Result;
use crate::types::{ImageData, PageKey};

/// 默认最大解码宽度
const DEFAULT_MAX_WIDTH: u32 = 2048;

/// 默认最大解码高度
const DEFAULT_MAX_HEIGHT: u32 = 4096;

/// 图像解码器配置
#[derive(Debug, Clone)]
pub struct DecoderConfig {
    /// 最大解码宽度
    pub max_width: u32,
    /// 最大解码高度
    pub max_height: u32,
    /// 是否使用并行解码
    pub parallel: bool,
}

impl Default for DecoderConfig {
    fn default() -> Self {
        Self {
            max_width: DEFAULT_MAX_WIDTH,
            max_height: DEFAULT_MAX_HEIGHT,
            parallel: true,
        }
    }
}

impl DecoderConfig {
    /// 创建新的解码器配置
    pub fn new(max_width: u32, max_height: u32) -> Self {
        Self {
            max_width,
            max_height,
            parallel: true,
        }
    }
}

/// 图像解码器
pub struct ImageDecoder {
    config: DecoderConfig,
    cache: Option<SharedImageCache>,
    disk_cache: Option<SharedDiskCache>,
}

impl ImageDecoder {
    /// 创建新的图像解码器
    pub fn new(config: DecoderConfig) -> Self {
        Self {
            config,
            cache: None,
            disk_cache: None,
        }
    }

    /// 设置内存缓存
    pub fn with_cache(mut self, cache: SharedImageCache) -> Self {
        self.cache = Some(cache);
        self
    }

    /// 设置磁盘缓存
    pub fn with_disk_cache(mut self, disk_cache: SharedDiskCache) -> Self {
        self.disk_cache = Some(disk_cache);
        self
    }


    /// 解码单张图片
    ///
    /// # 参数
    /// * `data` - 原始图像数据
    /// * `max_width` - 最大宽度 (超过则降采样)
    /// * `max_height` - 最大高度 (超过则降采样)
    pub fn decode_image(&self, data: &[u8], max_width: u32, max_height: u32) -> Result<ImageData> {
        // 使用 image crate 解码
        let img = image::load_from_memory(data)?;

        // 获取原始尺寸
        let (orig_width, orig_height) = img.dimensions();

        // 计算缩放比例
        let (target_width, target_height) =
            calculate_target_dimensions(orig_width, orig_height, max_width, max_height);

        // 如果需要缩放
        let decoded = if target_width < orig_width || target_height < orig_height {
            img.resize_exact(
                target_width,
                target_height,
                image::imageops::FilterType::Lanczos3,
            )
        } else {
            img
        };

        // 转换为 RGBA8888 格式
        let rgba = decoded.to_rgba8();
        let (width, height) = rgba.dimensions();

        // 获取原始像素数据 (零拷贝)
        let data = rgba.into_raw();

        Ok(ImageData::new(width as i32, height as i32, data))
    }

    /// 从压缩包解码指定页面的图片
    ///
    /// # 参数
    /// * `archive_path` - 压缩包路径
    /// * `file_name` - 压缩包内的文件名
    /// * `max_width` - 最大宽度
    /// * `max_height` - 最大高度
    pub fn decode_from_archive(
        &self,
        archive_path: &str,
        file_name: &str,
        max_width: u32,
        max_height: u32,
    ) -> Result<ImageData> {
        // 生成缓存键
        let cache_key = PageKey::new(archive_path, hash_file_name(file_name));

        // 1. 检查内存缓存
        if let Some(cache) = &self.cache {
            if let Some(cached) = cache.get(&cache_key) {
                return Ok((*cached).clone());
            }
        }

        // 2. 检查磁盘缓存
        if let Some(disk_cache) = &self.disk_cache {
            if let Some(cached) = disk_cache.get(&cache_key) {
                // 磁盘缓存命中，同时写入内存缓存
                if let Some(cache) = &self.cache {
                    cache.insert(cache_key.clone(), cached.clone());
                }
                return Ok(cached);
            }
        }

        // 3. 从压缩包提取文件
        let data = extract_file_from_archive(archive_path, file_name)?;

        // 4. 解码图像
        let image_data = self.decode_image(&data, max_width, max_height)?;


        // 5. 存入缓存
        if let Some(cache) = &self.cache {
            cache.insert(cache_key.clone(), image_data.clone());
        }
        if let Some(disk_cache) = &self.disk_cache {
            let _ = disk_cache.insert(cache_key.clone(), &image_data);
        }

        Ok(image_data)
    }

    /// 并行解码多张图片
    ///
    /// # 参数
    /// * `archive_path` - 压缩包路径
    /// * `file_names` - 文件名列表
    /// * `max_width` - 最大宽度
    /// * `max_height` - 最大高度
    ///
    /// # 返回
    /// 返回解码结果列表 (按输入顺序)
    pub fn decode_multiple_from_archive(
        &self,
        archive_path: &str,
        file_names: &[String],
        max_width: u32,
        max_height: u32,
    ) -> Vec<Result<ImageData>> {
        if !self.config.parallel {
            // 串行解码
            file_names
                .iter()
                .map(|name| self.decode_from_archive(archive_path, name, max_width, max_height))
                .collect()
        } else {
            // 并行解码 (使用 rayon)
            file_names
                .par_iter()
                .map(|name| self.decode_from_archive(archive_path, name, max_width, max_height))
                .collect()
        }
    }

    /// 生成缩略图
    ///
    /// # 参数
    /// * `data` - 原始图像数据
    /// * `size` - 缩略图边长 (正方形)
    pub fn generate_thumbnail(&self, data: &[u8], size: u32) -> Result<Vec<u8>> {
        let img = image::load_from_memory(data)?;

        // 缩放到指定尺寸
        let thumb = img.resize_exact(size, size, image::imageops::FilterType::Lanczos3);

        // 编码为 PNG
        let mut png_data = Vec::new();
        thumb
            .write_to(&mut Cursor::new(&mut png_data), ImageFormat::Png)?;

        Ok(png_data)
    }

    /// 从压缩包生成缩略图
    pub fn generate_thumbnail_from_archive(
        &self,
        archive_path: &str,
        file_name: &str,
        size: u32,
    ) -> Result<Vec<u8>> {
        let data = extract_file_from_archive(archive_path, file_name)?;
        self.generate_thumbnail(&data, size)
    }
}

/// 计算目标尺寸
fn calculate_target_dimensions(
    orig_width: u32,
    orig_height: u32,
    max_width: u32,
    max_height: u32,
) -> (u32, u32) {
    // 应用最大尺寸限制
    let (clamped_w, clamped_h) = clamp_image_dimensions(orig_width, orig_height);

    // 进一步限制到目标尺寸
    let scale = if clamped_w > max_width || clamped_h > max_height {
        let scale_w = max_width as f32 / clamped_w as f32;
        let scale_h = max_height as f32 / clamped_h as f32;
        scale_w.min(scale_h)
    } else {
        1.0
    };

    if scale < 1.0 {
        (
            ((clamped_w as f32) * scale) as u32,
            ((clamped_h as f32) * scale) as u32,
        )
    } else {
        (clamped_w, clamped_h)
    }
}

/// 文件名的简单哈希 (用于缓存键)
fn hash_file_name(name: &str) -> usize {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    name.hash(&mut hasher);
    hasher.finish() as usize
}

/// 便捷函数：解码单张图片
pub fn decode_image(data: &[u8], max_width: u32, max_height: u32) -> Result<ImageData> {
    let decoder = ImageDecoder::new(DecoderConfig::default());
    decoder.decode_image(data, max_width, max_height)
}

/// 便捷函数：从压缩包解码图片
pub fn decode_page(
    archive_path: &str,
    file_name: &str,
    max_width: u32,
    max_height: u32,
) -> Result<ImageData> {
    let decoder = ImageDecoder::new(DecoderConfig::default());
    decoder.decode_from_archive(archive_path, file_name, max_width, max_height)
}

/// 便捷函数：并行解码多页
pub fn decode_pages_parallel(
    archive_path: &str,
    file_names: &[String],
    max_width: u32,
    max_height: u32,
) -> Vec<Result<ImageData>> {
    let decoder = ImageDecoder::new(DecoderConfig::default());
    decoder.decode_multiple_from_archive(archive_path, file_names, max_width, max_height)
}

/// 便捷函数：生成缩略图
pub fn generate_thumbnail(data: &[u8], size: u32) -> Result<Vec<u8>> {
    let decoder = ImageDecoder::new(DecoderConfig::default());
    decoder.generate_thumbnail(data, size)
}

#[cfg(test)]
mod tests {
    use image::DynamicImage;

    use super::*;

    // 创建一个简单的测试图像 (红色 100x100 PNG)
    fn create_test_png() -> Vec<u8> {
        let img = DynamicImage::new_rgb8(100, 100);
        let mut data = Vec::new();
        img.write_to(&mut Cursor::new(&mut data), ImageFormat::Png)
            .unwrap();
        data
    }

    #[test]
    fn test_decode_image_basic() {
        let data = create_test_png();
        let result = decode_image(&data, 200, 200);
        assert!(result.is_ok());
        let img = result.unwrap();
        assert_eq!(img.width, 100);
        assert_eq!(img.height, 100);
        assert_eq!(img.format, "RGBA8888");
    }

    #[test]
    fn test_decode_image_downscale() {
        let data = create_test_png();
        // 要求缩小到 50x50
        let result = decode_image(&data, 50, 50);
        assert!(result.is_ok());
        let img = result.unwrap();
        assert_eq!(img.width, 50);
        assert_eq!(img.height, 50);
    }

    #[test]
    fn test_calculate_target_dimensions() {
        // 小尺寸不变
        let (w, h) = calculate_target_dimensions(100, 100, 200, 200);
        assert_eq!((w, h), (100, 100));

        // 大尺寸缩小
        let (w, h) = calculate_target_dimensions(1000, 500, 200, 200);
        assert!(w <= 200 && h <= 200);

        // 保持宽高比
        let ratio_orig = 1000.0 / 500.0;
        let ratio_scaled = w as f64 / h as f64;
        assert!((ratio_orig - ratio_scaled).abs() < 0.01);
    }

    #[test]
    fn test_decoder_config() {
        let config = DecoderConfig::new(4096, 4096);
        assert_eq!(config.max_width, 4096);
        assert_eq!(config.max_height, 4096);
        assert!(config.parallel);
    }

    #[test]
    fn test_hash_file_name_consistency() {
        let hash1 = hash_file_name("test.png");
        let hash2 = hash_file_name("test.png");
        assert_eq!(hash1, hash2);

        let hash3 = hash_file_name("other.png");
        assert_ne!(hash1, hash3);
    }

    #[test]
    fn test_generate_thumbnail() {
        let data = create_test_png();
        let thumb = generate_thumbnail(&data, 64);
        assert!(thumb.is_ok());
        // PNG 数据应该非空
        assert!(!thumb.unwrap().is_empty());
    }
}

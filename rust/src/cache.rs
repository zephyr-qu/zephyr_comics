//! LRU 内存缓存模块
//! 
//! 实现基于 LRU (Least Recently Used) 策略的图像缓存，
//! 严格限制最大内存占用，超出时自动淘汰最久未使用的图片。
//! 
//! # 设计原则
//! - 内存安全：严格限制最大内存占用 (默认 100MB)
//! - 线程安全：使用 Mutex 支持多线程访问
//! - 自动淘汰：超出限制时自动移除最旧数据

use lru::LruCache;
use std::num::NonZeroUsize;
use std::sync::{Arc, Mutex};

use crate::types::{ImageData, PageKey};

/// 默认最大内存占用 (100MB)
const DEFAULT_MAX_MEMORY_MB: usize = 100;

/// 单个图片的最大尺寸限制 (防止 4K 图片撑爆内存)
const MAX_IMAGE_DIMENSION: u32 = 4096;

/// 图像缓存
/// 
/// 线程安全的 LRU 缓存，用于存储解码后的图像数据。
pub struct ImageCache {
    /// LRU 缓存核心
    cache: LruCache<PageKey, Arc<ImageData>>,
    /// 当前内存占用 (字节)
    current_memory: usize,
    /// 最大内存占用 (字节)
    max_memory: usize,
}

impl ImageCache {
    /// 创建新的图像缓存
    /// 
    /// # 参数
    /// * `max_memory_mb` - 最大内存占用 (MB)
    pub fn new(max_memory_mb: usize) -> Self {
        // 估算：平均每张图片 0.5MB，初始容量设为 max_memory_mb * 2
        let initial_capacity = NonZeroUsize::new(max_memory_mb * 2).unwrap();
        
        Self {
            cache: LruCache::new(initial_capacity),
            current_memory: 0,
            max_memory: max_memory_mb * 1024 * 1024,
        }
    }
    
    /// 创建默认配置的缓存 (100MB)
    pub fn with_default_config() -> Self {
        Self::new(DEFAULT_MAX_MEMORY_MB)
    }
    
    /// 获取缓存中的图片
    pub fn get(&mut self, key: &PageKey) -> Option<Arc<ImageData>> {
        self.cache.get(key).cloned()
    }
    
    /// 插入图片到缓存
    /// 
    /// 如果超出内存限制，会自动淘汰最旧的数据。
    pub fn insert(&mut self, key: PageKey, data: ImageData) {
        let data_size = data.memory_size();
        
        // 如果单张图片就超出最大内存的 50%，拒绝缓存
        if data_size > self.max_memory / 2 {
            log::warn!(
                "图片过大跳过缓存：{} bytes (max: {})",
                data_size,
                self.max_memory / 2
            );
            return;
        }
        
        // 淘汰旧数据直到有足够空间
        while self.current_memory + data_size > self.max_memory {
            if let Some((_, old_data)) = self.cache.pop_lru() {
                self.current_memory = self.current_memory.saturating_sub(old_data.memory_size());
            } else {
                // 缓存已空，无法继续淘汰
                break;
            }
        }
        
        // 插入新数据
        self.current_memory += data_size;
        self.cache.push(key, Arc::new(data));
    }
    
    /// 检查缓存是否包含指定 key
    pub fn contains(&self, key: &PageKey) -> bool {
        self.cache.contains(key)
    }
    
    /// 移除指定 key 的缓存
    pub fn remove(&mut self, key: &PageKey) -> Option<Arc<ImageData>> {
        if let Some(data) = self.cache.pop(key) {
            self.current_memory = self.current_memory.saturating_sub(data.memory_size());
            Some(data)
        } else {
            None
        }
    }
    
    /// 清空缓存
    pub fn clear(&mut self) {
        self.cache.clear();
        self.current_memory = 0;
    }
    
    /// 获取当前内存占用 (字节)
    pub fn current_memory(&self) -> usize {
        self.current_memory
    }
    
    /// 获取最大内存占用 (字节)
    pub fn max_memory(&self) -> usize {
        self.max_memory
    }
    
    /// 获取缓存中的图片数量
    pub fn len(&self) -> usize {
        self.cache.len()
    }
    
    /// 检查缓存是否为空
    pub fn is_empty(&self) -> bool {
        self.cache.is_empty()
    }
    
    /// 获取缓存命中率统计
    pub fn get_stats(&self) -> CacheStats {
        CacheStats {
            cached_images: self.cache.len(),
            current_memory: self.current_memory,
            max_memory: self.max_memory,
            memory_usage_percent: if self.max_memory > 0 {
                (self.current_memory as f64 / self.max_memory as f64 * 100.0) as u8
            } else {
                0
            },
        }
    }
}

/// 缓存统计信息
#[derive(Debug, Clone)]
pub struct CacheStats {
    /// 缓存的图片数量
    pub cached_images: usize,
    /// 当前内存占用 (字节)
    pub current_memory: usize,
    /// 最大内存占用 (字节)
    pub max_memory: usize,
    /// 内存使用率百分比
    pub memory_usage_percent: u8,
}

/// 线程安全的缓存包装器
///
/// 用于在多线程环境中安全地共享缓存。
#[derive(Clone)]
pub struct SharedImageCache {
    inner: Arc<Mutex<ImageCache>>,
}

impl SharedImageCache {
    /// 创建新的共享缓存
    pub fn new(max_memory_mb: usize) -> Self {
        Self {
            inner: Arc::new(Mutex::new(ImageCache::new(max_memory_mb))),
        }
    }

    /// 获取图片
    pub fn get(&self, key: &PageKey) -> Option<Arc<ImageData>> {
        self.inner.lock()
            .unwrap_or_else(|e| {
                log::error!("缓存锁中毒：{}", e);
                e.into_inner()
            })
            .get(key)
    }

    /// 插入图片
    pub fn insert(&self, key: PageKey, data: ImageData) {
        self.inner.lock()
            .unwrap_or_else(|e| {
                log::error!("缓存锁中毒：{}", e);
                e.into_inner()
            })
            .insert(key, data);
    }

    /// 清空缓存
    pub fn clear(&self) {
        self.inner.lock()
            .unwrap_or_else(|e| {
                log::error!("缓存锁中毒：{}", e);
                e.into_inner()
            })
            .clear();
    }

    /// 获取统计信息
    pub fn get_stats(&self) -> CacheStats {
        self.inner.lock()
            .unwrap_or_else(|e| {
                log::error!("缓存锁中毒：{}", e);
                e.into_inner()
            })
            .get_stats()
    }

    /// 获取当前内存占用
    pub fn current_memory(&self) -> usize {
        self.inner.lock()
            .unwrap_or_else(|e| {
                log::error!("缓存锁中毒：{}", e);
                e.into_inner()
            })
            .current_memory()
    }
}

/// 限制图像最大尺寸
/// 
/// 如果图像超过最大尺寸，返回缩小后的尺寸。
pub fn clamp_image_dimensions(width: u32, height: u32) -> (u32, u32) {
    let scale = if width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION {
        let scale_w = MAX_IMAGE_DIMENSION as f32 / width as f32;
        let scale_h = MAX_IMAGE_DIMENSION as f32 / height as f32;
        scale_w.min(scale_h)
    } else {
        1.0
    };
    
    if scale < 1.0 {
        (
            (width as f32 * scale) as u32,
            (height as f32 * scale) as u32,
        )
    } else {
        (width, height)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_image(width: i32, height: i32) -> ImageData {
        let data = vec![0u8; (width * height * 4) as usize];
        ImageData::new(width, height, data)
    }

    #[test]
    fn test_cache_insert_and_get() {
        let mut cache = ImageCache::new(10); // 10MB
        let key = PageKey::new("test.cbz", 0);
        let data = create_test_image(100, 100);
        
        cache.insert(key.clone(), data);
        assert!(cache.get(&key).is_some());
        assert_eq!(cache.len(), 1);
    }

    #[test]
    fn test_cache_lru_eviction() {
        let mut cache = ImageCache::new(1); // 1MB 限制
        
        // 插入多张图片，应该触发淘汰
        for i in 0..10 {
            let key = PageKey::new("test.cbz", i);
            let data = create_test_image(200, 200); // 约 0.16MB 每张
            cache.insert(key, data);
        }
        
        // 内存占用不应超过限制
        assert!(cache.current_memory() <= 1024 * 1024);
    }

    #[test]
    fn test_cache_clear() {
        let mut cache = ImageCache::new(10);
        let key = PageKey::new("test.cbz", 0);
        cache.insert(key.clone(), create_test_image(100, 100));
        
        cache.clear();
        assert!(cache.is_empty());
        assert_eq!(cache.current_memory(), 0);
    }

    #[test]
    fn test_cache_stats() {
        let mut cache = ImageCache::new(10);
        let key = PageKey::new("test.cbz", 0);
        cache.insert(key.clone(), create_test_image(100, 100));
        
        let stats = cache.get_stats();
        assert_eq!(stats.cached_images, 1);
        assert!(stats.current_memory > 0);
        assert_eq!(stats.max_memory, 10 * 1024 * 1024);
    }

    #[test]
    fn test_shared_cache() {
        let cache = SharedImageCache::new(10);
        let key = PageKey::new("test.cbz", 0);
        
        cache.insert(key.clone(), create_test_image(100, 100));
        assert!(cache.get(&key).is_some());
        
        // 多线程安全测试
        let cache_clone = cache.clone();
        std::thread::spawn(move || {
            cache_clone.insert(PageKey::new("test2.cbz", 0), create_test_image(50, 50));
        })
        .join()
        .unwrap();
    }

    #[test]
    fn test_clamp_dimensions() {
        // 小尺寸不变
        let (w, h) = clamp_image_dimensions(100, 100);
        assert_eq!((w, h), (100, 100));
        
        // 大尺寸缩小
        let (w, h) = clamp_image_dimensions(8000, 6000);
        assert!(w <= MAX_IMAGE_DIMENSION && h <= MAX_IMAGE_DIMENSION);
        
        // 保持宽高比
        let ratio_original = 8000.0 / 6000.0;
        let ratio_clamped = w as f64 / h as f64;
        assert!((ratio_original - ratio_clamped).abs() < 0.01);
    }

    #[test]
    fn test_large_image_rejected() {
        let mut cache = ImageCache::new(1); // 1MB 限制
        
        // 创建一张超过 50% 限制的大图
        let key = PageKey::new("test.cbz", 0);
        let data = create_test_image(1000, 1000); // 约 4MB
        
        cache.insert(key.clone(), data);
        
        // 大图应该被拒绝缓存
        assert!(cache.get(&key).is_none());
    }
}

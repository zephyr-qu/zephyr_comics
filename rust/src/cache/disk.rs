//! 磁盘缓存模块
//!
//! 实现基于文件的磁盘缓存，用于持久化存储解码后的图像。
//!
//! # 特性
//! - LRU 淘汰策略
//! - 最大磁盘空间限制
//! - 自动清理过期数据
//! - 跨平台路径处理

use std::collections::HashMap;
use std::fs::{self, File};
use std::hash::{Hash, Hasher};
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::error::{ComicError, Result};
use crate::types::{ImageData, PageKey};

/// 默认磁盘缓存大小 (500MB)
const DEFAULT_DISK_CACHE_MB: usize = 500;

/// 缓存文件版本 (用于格式变更时清理旧缓存)
const CACHE_VERSION: u32 = 1;

/// 缓存条目元数据
#[derive(Debug, Clone)]
struct CacheEntry {
    /// 最后访问时间戳
    last_access: u64,
    /// 数据大小 (字节)
    size: usize,
    /// 图像宽度
    width: i32,
    /// 图像高度
    height: i32,
}

/// 磁盘缓存
///
/// 使用文件系统存储解码后的图像，支持 LRU 淘汰。
pub struct DiskCache {
    /// 缓存目录路径
    cache_dir: PathBuf,
    /// 当前磁盘占用 (字节)
    current_size: usize,
    /// 最大磁盘占用 (字节)
    max_size: usize,
    /// 缓存条目元数据 (内存中)
    entries: HashMap<String, CacheEntry>,
    /// 访问顺序 (用于 LRU)
    access_order: Vec<String>,
}

/// 磁盘缓存配置
#[derive(Debug, Clone)]
pub struct DiskCacheConfig {
    /// 最大磁盘占用 (MB)
    pub max_size_mb: usize,
    /// 缓存目录 (可选，使用默认如果为 None)
    pub cache_dir: Option<PathBuf>,
}

impl Default for DiskCacheConfig {
    fn default() -> Self {
        Self {
            max_size_mb: DEFAULT_DISK_CACHE_MB,
            cache_dir: None,
        }
    }
}

impl DiskCacheConfig {
    pub fn new(max_size_mb: usize) -> Self {
        Self {
            max_size_mb,
            cache_dir: None,
        }
    }

    pub fn with_cache_dir(mut self, cache_dir: PathBuf) -> Self {
        self.cache_dir = Some(cache_dir);
        self
    }
}

impl DiskCache {
    /// 创建新的磁盘缓存
    pub fn new(config: DiskCacheConfig) -> Result<Self> {
        // 确定缓存目录
        let cache_dir = config.cache_dir.clone().unwrap_or_else(|| {
            // 使用平台特定的缓存目录
            let base = std::env::temp_dir();
            base.join("zephyr_comics").join("image_cache")
        });

        // 创建缓存目录
        fs::create_dir_all(&cache_dir)
            .map_err(|e| ComicError::CacheError(format!("无法创建缓存目录：{}", e)))?;

        let max_size = config.max_size_mb * 1024 * 1024;

        let mut cache = Self {
            cache_dir,
            current_size: 0,
            max_size,
            entries: HashMap::new(),
            access_order: Vec::new(),
        };

        // 加载现有缓存元数据。A truncated or stale metadata file must not make
        // the cache unusable — the payload files are rebuildable, so keep
        // whatever parsed cleanly instead of failing construction.
        if let Err(error) = cache.load_metadata() {
            log::warn!("磁盘缓存元数据加载失败，跳过：{}", error);
        }

        Ok(cache)
    }

    /// 生成缓存文件的键
    fn make_cache_key(page_key: &PageKey) -> String {
        format!(
            "v{}_{}_{}",
            CACHE_VERSION,
            hash_string(&page_key.file_path),
            page_key.page_index
        )
    }

    /// 获取缓存文件的完整路径
    fn get_cache_path(&self, page_key: &PageKey) -> PathBuf {
        let key = Self::make_cache_key(page_key);
        self.cache_dir.join(format!("{}.cache", key))
    }

    /// 获取元数据文件的完整路径
    fn get_metadata_path(&self) -> PathBuf {
        self.cache_dir.join("metadata.bin")
    }

    /// 检查缓存是否存在
    pub fn contains(&self, page_key: &PageKey) -> bool {
        let key = Self::make_cache_key(page_key);
        self.entries.contains_key(&key)
    }

    /// 从缓存获取图像
    pub fn get(&mut self, page_key: &PageKey) -> Option<ImageData> {
        let key = Self::make_cache_key(page_key);

        // 检查元数据
        if !self.entries.contains_key(&key) {
            return None;
        }

        // 读取文件
        let path = self.get_cache_path(page_key);
        if !path.exists() {
            // 文件不存在，清理元数据
            self.entries.remove(&key);
            return None;
        }

        // 读取并解码图像数据
        match self.read_cache_file(&path) {
            Ok(data) => {
                // 更新访问顺序 (LRU)
                self.update_access_order(&key);
                Some(data)
            }
            Err(e) => {
                log::warn!("读取缓存失败：{} - {}", key, e);
                None
            }
        }
    }

    /// 插入图像到缓存
    pub fn insert(&mut self, page_key: PageKey, data: &ImageData) -> Result<()> {
        let key = Self::make_cache_key(&page_key);
        let path = self.get_cache_path(&page_key);

        // 检查空间
        let data_size = self.estimate_data_size(data);
        while self.current_size + data_size > self.max_size {
            if !self.evict_lru() {
                // 无法淘汰更多数据
                log::warn!("磁盘缓存已满，跳过插入");
                return Ok(());
            }
        }

        // 写入文件
        self.write_cache_file(&path, data)?;

        // 更新元数据
        let entry = CacheEntry {
            last_access: current_timestamp(),
            size: data_size,
            width: data.width,
            height: data.height,
        };

        self.entries.insert(key.clone(), entry);
        self.current_size += data_size;
        self.update_access_order(&key);

        // 定期保存元数据
        if self.entries.len().is_multiple_of(10) {
            self.save_metadata()?;
        }

        Ok(())
    }

    /// 移除指定缓存
    pub fn remove(&mut self, page_key: &PageKey) -> Result<()> {
        let key = Self::make_cache_key(page_key);
        let path = self.get_cache_path(page_key);

        // 删除文件
        if path.exists() {
            if let Some(entry) = self.entries.remove(&key) {
                self.current_size = self.current_size.saturating_sub(entry.size);
                fs::remove_file(&path).ok();
            }
        }

        // 从访问顺序中移除
        self.access_order.retain(|k| k != &key);

        Ok(())
    }

    /// 清空缓存
    pub fn clear(&mut self) -> Result<()> {
        // 删除所有缓存文件
        for entry in fs::read_dir(&self.cache_dir)
            .ok()
            .into_iter()
            .flatten()
            .flatten()
        {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("cache") {
                fs::remove_file(&path).ok();
            }
        }

        self.entries.clear();
        self.access_order.clear();
        self.current_size = 0;

        // 删除元数据文件
        let _ = fs::remove_file(self.get_metadata_path());

        Ok(())
    }

    /// 获取统计信息
    pub fn get_stats(&self) -> DiskCacheStats {
        DiskCacheStats {
            cached_images: self.entries.len(),
            current_size: self.current_size,
            max_size: self.max_size,
            cache_dir: self.cache_dir.to_string_lossy().to_string(),
        }
    }

    /// 获取当前磁盘占用
    pub fn current_size(&self) -> usize {
        self.current_size
    }

    /// 获取最大磁盘占用
    pub fn max_size(&self) -> usize {
        self.max_size
    }

    // ============ 内部方法 ============

    /// 写入缓存文件
    fn write_cache_file(&self, path: &Path, data: &ImageData) -> Result<()> {
        let file = File::create(path)
            .map_err(|e| ComicError::CacheError(format!("无法创建缓存文件：{}", e)))?;
        let mut writer = BufWriter::new(file);

        // 写入头部：magic + version + width + height
        writer.write_all(b"ZCCH")?; // Magic
        writer.write_all(&CACHE_VERSION.to_le_bytes())?;
        writer.write_all(&(data.width as u32).to_le_bytes())?;
        writer.write_all(&(data.height as u32).to_le_bytes())?;

        // 写入图像数据 (RGBA)
        writer.write_all(&data.data)?;

        writer.flush()?;
        Ok(())
    }

    /// 读取缓存文件
    fn read_cache_file(&self, path: &Path) -> Result<ImageData> {
        let file = File::open(path)
            .map_err(|e| ComicError::CacheError(format!("无法打开缓存文件：{}", e)))?;
        let mut reader = BufReader::new(file);

        // 读取头部
        let mut magic = [0u8; 4];
        reader.read_exact(&mut magic)?;
        if &magic != b"ZCCH" {
            return Err(ComicError::CacheError("缓存文件格式错误".to_string()));
        }

        let mut version = [0u8; 4];
        reader.read_exact(&mut version)?;
        let version = u32::from_le_bytes(version);
        if version != CACHE_VERSION {
            return Err(ComicError::CacheError(format!(
                "缓存版本不匹配：期望 {}, 实际 {}",
                CACHE_VERSION, version
            )));
        }

        let mut width = [0u8; 4];
        reader.read_exact(&mut width)?;
        let width = i32::from_le_bytes(width);

        let mut height = [0u8; 4];
        reader.read_exact(&mut height)?;
        let height = i32::from_le_bytes(height);

        // 读取图像数据
        let data_size = (width * height * 4) as usize;
        let mut data = vec![0u8; data_size];
        reader.read_exact(&mut data)?;

        Ok(ImageData::new(width, height, data))
    }

    /// 估算数据大小
    fn estimate_data_size(&self, data: &ImageData) -> usize {
        // 头部 16 字节 + 图像数据
        16 + data.data.len()
    }

    /// 淘汰 LRU 条目
    fn evict_lru(&mut self) -> bool {
        // 找到最久未访问的条目
        if let Some(oldest_key) = self.access_order.first().cloned() {
            if let Some(entry) = self.entries.remove(&oldest_key) {
                self.current_size = self.current_size.saturating_sub(entry.size);

                // 删除文件
                // 需要从 key 重建 PageKey (简化处理：直接删除所有匹配的文件)
                for entry in fs::read_dir(&self.cache_dir)
                    .ok()
                    .into_iter()
                    .flatten()
                    .flatten()
                {
                    let path = entry.path();
                    if path
                        .file_name()
                        .and_then(|s| s.to_str())
                        .map(|s| {
                            s.starts_with(&format!(
                                "v{}_{}",
                                CACHE_VERSION,
                                oldest_key.split('_').nth(1).unwrap_or("")
                            ))
                        })
                        .unwrap_or(false)
                    {
                        fs::remove_file(&path).ok();
                        break;
                    }
                }

                self.access_order.remove(0);
                return true;
            }
        }
        false
    }

    /// 更新访问顺序
    fn update_access_order(&mut self, key: &str) {
        // 移除旧位置
        self.access_order.retain(|k| k != key);
        // 添加到末尾 (最新访问)
        self.access_order.push(key.to_string());
    }

    /// 保存元数据
    fn save_metadata(&self) -> Result<()> {
        let path = self.get_metadata_path();
        let file = File::create(&path)
            .map_err(|e| ComicError::CacheError(format!("无法保存元数据：{}", e)))?;
        let mut writer = BufWriter::new(file);

        // 写入条目数量
        writer.write_all(&(self.entries.len() as u32).to_le_bytes())?;

        // 写入每个条目
        for (key, entry) in &self.entries {
            // key
            writer.write_all(&(key.len() as u16).to_le_bytes())?;
            writer.write_all(key.as_bytes())?;

            // entry
            writer.write_all(&entry.last_access.to_le_bytes())?;
            writer.write_all(&(entry.size as u32).to_le_bytes())?;
            writer.write_all(&(entry.width as u32).to_le_bytes())?;
            writer.write_all(&(entry.height as u32).to_le_bytes())?;
        }

        writer.flush()?;
        Ok(())
    }

    /// 加载元数据
    fn load_metadata(&mut self) -> Result<()> {
        let path = self.get_metadata_path();
        if !path.exists() {
            return Ok(());
        }

        let file = File::open(&path)
            .map_err(|e| ComicError::CacheError(format!("无法加载元数据：{}", e)))?;
        let mut reader = BufReader::new(file);

        // 读取条目数量
        let mut count = [0u8; 4];
        reader.read_exact(&mut count)?;
        let count = u32::from_le_bytes(count) as usize;

        // 读取每个条目
        for _ in 0..count {
            // key
            let mut key_len = [0u8; 2];
            reader.read_exact(&mut key_len)?;
            let key_len = u16::from_le_bytes(key_len) as usize;

            let mut key_bytes = vec![0u8; key_len];
            reader.read_exact(&mut key_bytes)?;
            let key = String::from_utf8_lossy(&key_bytes).to_string();

            // entry
            let mut last_access = [0u8; 8];
            reader.read_exact(&mut last_access)?;
            let last_access = u64::from_le_bytes(last_access);

            // Must match `save_metadata`, which writes the size as a u32.
            let mut size = [0u8; 4];
            reader.read_exact(&mut size)?;
            let size = u32::from_le_bytes(size) as usize;

            let mut width = [0u8; 4];
            reader.read_exact(&mut width)?;
            let width = i32::from_le_bytes(width);

            let mut height = [0u8; 4];
            reader.read_exact(&mut height)?;
            let height = i32::from_le_bytes(height);

            // 检查文件是否存在
            let file_key = key.clone();
            let file_exists = fs::read_dir(&self.cache_dir)
                .ok()
                .into_iter()
                .flatten()
                .any(|e| {
                    e.ok()
                        .map(|e| e.file_name().to_string_lossy().starts_with(&file_key))
                        .unwrap_or(false)
                });

            if file_exists {
                self.entries.insert(
                    key.clone(),
                    CacheEntry {
                        last_access,
                        size,
                        width,
                        height,
                    },
                );
                self.current_size += size;
                self.access_order.push(key);
            }
        }

        Ok(())
    }
}

/// 磁盘缓存统计信息
#[derive(Debug, Clone)]
pub struct DiskCacheStats {
    /// 缓存的图片数量
    pub cached_images: usize,
    /// 当前磁盘占用 (字节)
    pub current_size: usize,
    /// 最大磁盘占用 (字节)
    pub max_size: usize,
    /// 缓存目录路径
    pub cache_dir: String,
}

/// 线程安全的磁盘缓存包装器
#[derive(Clone)]
pub struct SharedDiskCache {
    inner: Arc<Mutex<DiskCache>>,
}

impl SharedDiskCache {
    /// 创建新的共享磁盘缓存
    pub fn new(config: DiskCacheConfig) -> Result<Self> {
        let cache = DiskCache::new(config)?;
        Ok(Self {
            inner: Arc::new(Mutex::new(cache)),
        })
    }

    /// 检查缓存是否存在
    pub fn contains(&self, page_key: &PageKey) -> bool {
        self.inner
            .lock()
            .unwrap_or_else(|e| {
                log::error!("磁盘缓存锁中毒：{}", e);
                e.into_inner()
            })
            .contains(page_key)
    }

    /// 从缓存获取图像
    pub fn get(&self, page_key: &PageKey) -> Option<ImageData> {
        self.inner
            .lock()
            .unwrap_or_else(|e| {
                log::error!("磁盘缓存锁中毒：{}", e);
                e.into_inner()
            })
            .get(page_key)
    }

    /// 插入图像到缓存
    pub fn insert(&self, page_key: PageKey, data: &ImageData) -> Result<()> {
        self.inner
            .lock()
            .unwrap_or_else(|e| {
                log::error!("磁盘缓存锁中毒：{}", e);
                e.into_inner()
            })
            .insert(page_key, data)
    }

    /// 清空缓存
    pub fn clear(&self) -> Result<()> {
        self.inner
            .lock()
            .unwrap_or_else(|e| {
                log::error!("磁盘缓存锁中毒：{}", e);
                e.into_inner()
            })
            .clear()
    }

    /// 获取统计信息
    pub fn get_stats(&self) -> DiskCacheStats {
        self.inner
            .lock()
            .unwrap_or_else(|e| {
                log::error!("磁盘缓存锁中毒：{}", e);
                e.into_inner()
            })
            .get_stats()
    }
}

// ============ 工具函数 ============

/// 字符串哈希
fn hash_string(s: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    let mut hasher = DefaultHasher::new();
    s.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

/// 获取当前时间戳 (毫秒)
fn current_timestamp() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_TEMP_DIR: AtomicU64 = AtomicU64::new(0);

    struct TestCacheDir(PathBuf);

    impl TestCacheDir {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("clock after epoch")
                .as_nanos();
            let sequence = NEXT_TEMP_DIR.fetch_add(1, Ordering::Relaxed);
            Self(std::env::temp_dir().join(format!(
                "zephyr-disk-cache-test-{}-{nonce}-{sequence}",
                std::process::id()
            )))
        }

        fn config(&self, max_size_mb: usize) -> DiskCacheConfig {
            DiskCacheConfig::new(max_size_mb).with_cache_dir(self.0.clone())
        }
    }

    impl Drop for TestCacheDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn create_test_image() -> ImageData {
        let data = vec![0u8; 100 * 100 * 4];
        ImageData::new(100, 100, data)
    }

    #[test]
    fn test_disk_cache_insert_and_get() {
        let cache_dir = TestCacheDir::new();
        let mut cache = DiskCache::new(cache_dir.config(10)).unwrap();

        let key = PageKey::new("test.cbz", 0);
        let data = create_test_image();

        cache.insert(key.clone(), &data).unwrap();
        let retrieved = cache.get(&key);

        assert!(retrieved.is_some());
        let retrieved = retrieved.unwrap();
        assert_eq!(retrieved.width, 100);
        assert_eq!(retrieved.height, 100);
    }

    #[test]
    fn test_disk_cache_contains() {
        let cache_dir = TestCacheDir::new();
        let mut cache = DiskCache::new(cache_dir.config(10)).unwrap();

        let key = PageKey::new("test.cbz", 0);
        assert!(!cache.contains(&key));

        cache.insert(key.clone(), &create_test_image()).unwrap();
        assert!(cache.contains(&key));
    }

    #[test]
    fn test_disk_cache_clear() {
        let cache_dir = TestCacheDir::new();
        let mut cache = DiskCache::new(cache_dir.config(10)).unwrap();

        let key = PageKey::new("test.cbz", 0);
        cache.insert(key.clone(), &create_test_image()).unwrap();

        cache.clear().unwrap();
        assert!(!cache.contains(&key));
        assert_eq!(cache.current_size, 0);
    }

    #[test]
    fn test_disk_cache_stats() {
        let cache_dir = TestCacheDir::new();
        let mut cache = DiskCache::new(cache_dir.config(10)).unwrap();

        cache
            .insert(PageKey::new("test1.cbz", 0), &create_test_image())
            .unwrap();
        cache
            .insert(PageKey::new("test2.cbz", 0), &create_test_image())
            .unwrap();

        let stats = cache.get_stats();
        assert_eq!(stats.cached_images, 2);
        assert!(stats.current_size > 0);
        assert_eq!(stats.max_size, 10 * 1024 * 1024);
    }

    #[test]
    fn test_shared_disk_cache() {
        let cache_dir = TestCacheDir::new();
        let cache = SharedDiskCache::new(cache_dir.config(10)).unwrap();

        let key = PageKey::new("test.cbz", 0);
        cache.insert(key.clone(), &create_test_image()).unwrap();

        assert!(cache.contains(&key));
        assert!(cache.get(&key).is_some());
    }

    #[test]
    fn metadata_survives_reload() {
        let cache_dir = TestCacheDir::new();
        let key = PageKey::new("test.cbz", 0);
        let data = create_test_image();

        {
            let mut cache = DiskCache::new(cache_dir.config(10)).unwrap();
            cache.insert(key.clone(), &data).unwrap();
            cache.save_metadata().unwrap();
        }

        // A fresh instance must parse the file the writer produced; a field
        // width mismatch here used to drop every entry on the next launch.
        let reloaded = DiskCache::new(cache_dir.config(10)).unwrap();

        assert!(reloaded.contains(&key));
        assert_eq!(reloaded.current_size(), 16 + data.data.len());
    }

    #[test]
    fn test_hash_string_consistency() {
        let hash1 = hash_string("test.cbz");
        let hash2 = hash_string("test.cbz");
        assert_eq!(hash1, hash2);

        let hash3 = hash_string("other.cbz");
        assert_ne!(hash1, hash3);
    }
}

//! 智能预加载策略模块
//!
//! 根据阅读方向和用户行为智能计算需要预加载的页面。
//!
//! # 预加载策略
//! - 左→右阅读：预加载当前页之后的页面
//! - 右→左阅读 (日漫)：预加载当前页之前的页面
//! - 上→下阅读 (条漫)：预加载当前页之后的多页
//! - 智能预取：根据阅读速度动态调整预加载数量

/// 阅读方向
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(Default)]
pub enum ReadingDirection {
    /// 左到右 (美漫/国漫)
    #[default]
    LeftToRight,
    /// 右到左 (日漫)
    RightToLeft,
    /// 上到下 (条漫/Webtoon)
    TopToBottom,
    /// 自动 (根据内容判断)
    Auto,
}


/// 预加载策略配置
#[derive(Debug, Clone)]
pub struct PreloadStrategy {
    /// 阅读方向
    pub direction: ReadingDirection,
    /// 基础预加载数量 (相邻页面)
    pub base_preload_count: usize,
    /// 最大预加载数量
    pub max_preload_count: usize,
    /// 是否启用智能预取 (根据阅读速度调整)
    pub enable_smart_preload: bool,
    /// 快速阅读时的额外预加载数量
    pub fast_reading_bonus: usize,
}

impl Default for PreloadStrategy {
    fn default() -> Self {
        Self {
            direction: ReadingDirection::LeftToRight,
            base_preload_count: 3,
            max_preload_count: 10,
            enable_smart_preload: true,
            fast_reading_bonus: 2,
        }
    }
}

impl PreloadStrategy {
    /// 创建新的预加载策略
    pub fn new(direction: ReadingDirection) -> Self {
        Self {
            direction,
            ..Default::default()
        }
    }

    /// 设置预加载数量
    pub fn with_preload_count(mut self, base: usize, max: usize) -> Self {
        self.base_preload_count = base;
        self.max_preload_count = max;
        self
    }

    /// 启用/禁用智能预取
    pub fn with_smart_preload(mut self, enable: bool) -> Self {
        self.enable_smart_preload = enable;
        self
    }

    /// 计算需要预加载的页面索引
    ///
    /// # 参数
    /// * `current_page` - 当前页面索引
    /// * `total_pages` - 总页数
    ///
    /// # 返回
    /// 需要预加载的页面索引列表
    pub fn calculate_pages_to_preload(
        &self,
        current_page: usize,
        total_pages: usize,
    ) -> Vec<usize> {
        if total_pages == 0 {
            return Vec::new();
        }

        let preload_count = self.base_preload_count.min(self.max_preload_count);
        let mut pages = Vec::with_capacity(preload_count);

        match self.direction {
            ReadingDirection::LeftToRight => {
                // 预加载当前页之后的页面
                for i in 1..=preload_count {
                    let next_page = current_page + i;
                    if next_page < total_pages {
                        pages.push(next_page);
                    }
                }
            }

            ReadingDirection::RightToLeft => {
                // 预加载当前页之前的页面 (日漫从右往左翻)
                if current_page >= 1 {
                    for i in 1..=preload_count {
                        if current_page >= i {
                            pages.push(current_page - i);
                        }
                    }
                }
            }

            ReadingDirection::TopToBottom => {
                // 条漫：预加载更多下方页面
                for i in 1..=preload_count + self.fast_reading_bonus {
                    let next_page = current_page + i;
                    if next_page < total_pages {
                        pages.push(next_page);
                    }
                }
            }

            ReadingDirection::Auto => {
                // 自动模式：默认使用左到右
                for i in 1..=preload_count {
                    let next_page = current_page + i;
                    if next_page < total_pages {
                        pages.push(next_page);
                    }
                }
            }
        }

        pages
    }

    /// 智能计算预加载页面 (考虑阅读速度)
    ///
    /// # 参数
    /// * `current_page` - 当前页面索引
    /// * `total_pages` - 总页数
    /// * `reading_speed_ms_per_page` - 阅读速度 (毫秒/页)
    pub fn calculate_smart_pages(
        &self,
        current_page: usize,
        total_pages: usize,
        reading_speed_ms_per_page: u64,
    ) -> Vec<usize> {
        if !self.enable_smart_preload {
            return self.calculate_pages_to_preload(current_page, total_pages);
        }

        // 根据阅读速度调整预加载数量
        // 快速阅读 (< 2 秒/页)：增加预加载
        // 慢速阅读 (> 10 秒/页)：减少预加载
        let adjusted_count = if reading_speed_ms_per_page < 2000 {
            self.base_preload_count + self.fast_reading_bonus
        } else if reading_speed_ms_per_page > 10000 {
            self.base_preload_count / 2
        } else {
            self.base_preload_count
        }
        .max(1)
        .min(self.max_preload_count);

        // 使用调整后的数量重新计算
        let mut strategy = self.clone();
        strategy.base_preload_count = adjusted_count;
        strategy.calculate_pages_to_preload(current_page, total_pages)
    }

    /// 获取下一个应该显示的页面索引
    ///
    /// # 参数
    /// * `current_page` - 当前页面索引
    /// * `total_pages` - 总页数
    pub fn next_page(&self, current_page: usize, total_pages: usize) -> Option<usize> {
        if total_pages == 0 {
            return None;
        }

        match self.direction {
            ReadingDirection::LeftToRight | ReadingDirection::TopToBottom => {
                if current_page + 1 < total_pages {
                    Some(current_page + 1)
                } else {
                    None
                }
            }

            ReadingDirection::RightToLeft => {
                if current_page > 0 {
                    Some(current_page - 1)
                } else {
                    None
                }
            }

            ReadingDirection::Auto => {
                if current_page + 1 < total_pages {
                    Some(current_page + 1)
                } else {
                    None
                }
            }
        }
    }

    /// 获取上一个应该显示的页面索引
    ///
    /// # 参数
    /// * `current_page` - 当前页面索引
    /// * `total_pages` - 总页数
    pub fn prev_page(&self, current_page: usize, total_pages: usize) -> Option<usize> {
        if total_pages == 0 {
            return None;
        }

        match self.direction {
            ReadingDirection::LeftToRight | ReadingDirection::TopToBottom => {
                if current_page > 0 {
                    Some(current_page - 1)
                } else {
                    None
                }
            }

            ReadingDirection::RightToLeft => {
                if current_page + 1 < total_pages {
                    Some(current_page + 1)
                } else {
                    None
                }
            }

            ReadingDirection::Auto => {
                if current_page > 0 {
                    Some(current_page - 1)
                } else {
                    None
                }
            }
        }
    }
}

/// 预加载任务
#[derive(Debug, Clone)]
pub struct PreloadTask {
    /// 文件路径
    pub file_path: String,
    /// 要预加载的页面索引
    pub page_indices: Vec<usize>,
    /// 优先级 (越小越高)
    pub priority: u8,
}

impl PreloadTask {
    pub fn new(file_path: String, page_indices: Vec<usize>) -> Self {
        Self {
            file_path,
            page_indices,
            priority: 0,
        }
    }

    pub fn with_priority(mut self, priority: u8) -> Self {
        self.priority = priority;
        self
    }
}

/// 预加载管理器
///
/// 管理预加载任务的队列和执行。
pub struct PreloadManager {
    /// 预加载策略
    strategy: PreloadStrategy,
    /// 待处理的任务队列
    task_queue: Vec<PreloadTask>,
    /// 当前正在加载的任务
    current_task: Option<PreloadTask>,
}

impl PreloadManager {
    /// 创建新的预加载管理器
    pub fn new(strategy: PreloadStrategy) -> Self {
        Self {
            strategy,
            task_queue: Vec::new(),
            current_task: None,
        }
    }

    /// 添加预加载任务
    pub fn add_task(&mut self, task: PreloadTask) {
        self.task_queue.push(task);
        // 按优先级排序
        self.task_queue.sort_by_key(|t| t.priority);
    }

    /// 取消所有待处理的预加载任务
    pub fn cancel_all(&mut self) {
        self.task_queue.clear();
        self.current_task = None;
    }

    /// 取消指定文件的预加载任务
    pub fn cancel_for_file(&mut self, file_path: &str) {
        self.task_queue.retain(|t| t.file_path != file_path);
        if let Some(ref current) = self.current_task {
            if current.file_path == file_path {
                self.current_task = None;
            }
        }
    }

    /// 获取下一个要执行的任务
    pub fn next_task(&mut self) -> Option<PreloadTask> {
        if self.task_queue.is_empty() {
            return None;
        }
        Some(self.task_queue.remove(0))
    }

    /// 设置当前正在执行的任务
    pub fn set_current_task(&mut self, task: Option<PreloadTask>) {
        self.current_task = task;
    }

    /// 获取当前任务
    pub fn get_current_task(&self) -> Option<&PreloadTask> {
        self.current_task.as_ref()
    }

    /// 获取待处理任务数量
    pub fn pending_count(&self) -> usize {
        self.task_queue.len()
    }

    /// 获取预加载策略
    pub fn strategy(&self) -> &PreloadStrategy {
        &self.strategy
    }

    /// 设置预加载策略
    pub fn set_strategy(&mut self, strategy: PreloadStrategy) {
        self.strategy = strategy;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preload_strategy_left_to_right() {
        let strategy = PreloadStrategy::new(ReadingDirection::LeftToRight);
        let pages = strategy.calculate_pages_to_preload(5, 20);

        assert_eq!(pages, vec![6, 7, 8]); // 默认 preload 3 页
    }

    #[test]
    fn test_preload_strategy_right_to_left() {
        let strategy = PreloadStrategy::new(ReadingDirection::RightToLeft);
        let pages = strategy.calculate_pages_to_preload(5, 20);

        assert_eq!(pages, vec![4, 3, 2]); // 向前预加载
    }

    #[test]
    fn test_preload_strategy_top_to_bottom() {
        let strategy = PreloadStrategy::new(ReadingDirection::TopToBottom);
        let pages = strategy.calculate_pages_to_preload(5, 20);

        // 条漫预加载更多
        assert_eq!(pages.len(), 5); // 3 + 2 bonus
    }

    #[test]
    fn test_preload_boundary() {
        let strategy = PreloadStrategy::new(ReadingDirection::LeftToRight);

        // 接近末尾
        let pages = strategy.calculate_pages_to_preload(18, 20);
        assert_eq!(pages, vec![19]); // 只剩一页

        // 最后一页
        let pages = strategy.calculate_pages_to_preload(19, 20);
        assert!(pages.is_empty());
    }

    #[test]
    fn test_next_prev_page() {
        let strategy = PreloadStrategy::new(ReadingDirection::LeftToRight);

        assert_eq!(strategy.next_page(5, 20), Some(6));
        assert_eq!(strategy.prev_page(5, 20), Some(4));

        assert_eq!(strategy.next_page(19, 20), None);
        assert_eq!(strategy.prev_page(0, 20), None);
    }

    #[test]
    fn test_smart_preload() {
        let strategy = PreloadStrategy::default();

        // 快速阅读
        let pages = strategy.calculate_smart_pages(5, 20, 1000); // 1 秒/页
        assert!(pages.len() >= 3);

        // 慢速阅读
        let pages = strategy.calculate_smart_pages(5, 20, 15000); // 15 秒/页
        assert!(pages.len() <= 2);
    }

    #[test]
    fn test_preload_manager() {
        let strategy = PreloadStrategy::default();
        let mut manager = PreloadManager::new(strategy);

        manager.add_task(PreloadTask::new("comic.cbz".to_string(), vec![1, 2, 3]));
        assert_eq!(manager.pending_count(), 1);

        manager.cancel_all();
        assert_eq!(manager.pending_count(), 0);
    }
}

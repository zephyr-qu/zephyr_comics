//! 智能排序模块
//!
//! 实现漫画图片文件的智能排序算法，解决：
//! - `1.png, 2.png, 10.png` 排序为 `1, 2, 10` 而非 `1, 10, 2`
//! - 特殊文件名处理 (封面、目录等)
//! - 支持多章节文件的分组排序

use std::cmp::Ordering;

/// 对文件名列表进行智能自然排序
///
/// 使用自然排序算法，将数字部分按数值大小排序。
/// 例如：["1.png", "2.png", "10.png"] 而非 ["1.png", "10.png", "2.png"]
///
/// # 示例
/// ```
/// let files = vec!["10.png".to_string(), "2.png".to_string(), "1.png".to_string()];
/// let sorted = natural_sort(&files);
/// assert_eq!(sorted, vec!["1.png", "2.png", "10.png"]);
/// ```
pub fn natural_sort(files: &[String]) -> Vec<String> {
    let mut sorted = files.to_vec();
    sorted.sort_by(|a, b| natural_cmp(a, b));
    sorted
}

/// 自然排序比较函数
///
/// 比较两个字符串，将连续数字作为数值比较。
fn natural_cmp(a: &str, b: &str) -> Ordering {
    let mut a_chars = a.chars().peekable();
    let mut b_chars = b.chars().peekable();

    loop {
        match (a_chars.peek(), b_chars.peek()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            _ => {}
        }

        let a_digit = a_chars.peek().map(|c| c.is_ascii_digit()).unwrap_or(false);
        let b_digit = b_chars.peek().map(|c| c.is_ascii_digit()).unwrap_or(false);

        if a_digit && b_digit {
            // 都是数字，解析完整数字进行比较
            let mut a_num = String::new();
            while let Some(&c) = a_chars.peek() {
                if c.is_ascii_digit() {
                    a_num.push(c);
                    a_chars.next();
                } else {
                    break;
                }
            }

            let mut b_num = String::new();
            while let Some(&c) = b_chars.peek() {
                if c.is_ascii_digit() {
                    b_num.push(c);
                    b_chars.next();
                } else {
                    break;
                }
            }

            // 比较数值 (先比较长度，再比较字典序)
            let a_val = a_num.parse::<u64>().unwrap_or(0);
            let b_val = b_num.parse::<u64>().unwrap_or(0);

            match a_val.cmp(&b_val) {
                Ordering::Equal => continue,
                other => return other,
            }
        } else if a_digit {
            // 数字 < 非数字
            return Ordering::Less;
        } else if b_digit {
            return Ordering::Greater;
        } else {
            // 都不是数字，按字符比较
            match a_chars.next().unwrap().cmp(&b_chars.next().unwrap()) {
                Ordering::Equal => continue,
                other => return other,
            }
        }
    }
}

/// 过滤出图像文件
///
/// 从文件列表中筛选出支持的图像格式。
pub fn filter_image_files(files: &[String]) -> Vec<String> {
    let image_extensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp"];

    files
        .iter()
        .filter(|f| {
            f.rsplit('.')
                .next()
                .map(|ext| {
                    image_extensions
                        .iter()
                        .any(|&ie| ie.eq_ignore_ascii_case(ext))
                })
                .unwrap_or(false)
        })
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_natural_sort_basic() {
        let files = vec![
            "10.png".to_string(),
            "2.png".to_string(),
            "1.png".to_string(),
            "20.png".to_string(),
        ];
        let sorted = natural_sort(&files);
        assert_eq!(sorted, vec!["1.png", "2.png", "10.png", "20.png"]);
    }

    #[test]
    fn test_natural_sort_with_prefix() {
        let files = vec![
            "page_10.png".to_string(),
            "page_2.png".to_string(),
            "page_1.png".to_string(),
        ];
        let sorted = natural_sort(&files);
        assert_eq!(sorted, vec!["page_1.png", "page_2.png", "page_10.png"]);
    }

    #[test]
    fn test_filter_image_files() {
        let files = vec![
            "001.png".to_string(),
            "002.jpg".to_string(),
            "readme.txt".to_string(),
            "003.jpeg".to_string(),
            "notes.md".to_string(),
        ];
        let filtered = filter_image_files(&files);
        assert_eq!(filtered.len(), 3);
        assert!(filtered.contains(&"001.png".to_string()));
        assert!(filtered.contains(&"002.jpg".to_string()));
        assert!(filtered.contains(&"003.jpeg".to_string()));
    }
}

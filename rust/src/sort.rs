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

/// 对文件名进行智能排序 (原地排序)
pub fn natural_sort_in_place(files: &mut [String]) {
    files.sort_by(|a, b| natural_cmp(a, b));
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

/// 特殊文件名权重
/// 
/// 给特殊文件 (如封面) 更高的优先级，使其排在前面。
fn special_file_priority(filename: &str) -> u8 {
    let lower = filename.to_lowercase();
    
    // 封面类文件优先级最高
    if lower.contains("cover") || lower.contains("封面") {
        return 100;
    }
    
    // 目录/介绍类文件
    if lower.contains("index") || lower.contains("目录") || lower.contains("intro") {
        return 90;
    }
    
    // 彩页/插页
    if lower.contains("color") || lower.contains("彩页") {
        return 80;
    }
    
    // 默认优先级
    50
}

/// 带特殊文件处理的智能排序
/// 
/// 将特殊文件 (封面、目录等) 排在前面，其余文件按自然排序。
pub fn smart_sort(files: &[String]) -> Vec<String> {
    let mut special_files: Vec<(u8, String)> = Vec::new();
    let mut normal_files: Vec<String> = Vec::new();
    
    for file in files {
        let priority = special_file_priority(file);
        if priority >= 80 {
            special_files.push((priority, file.clone()));
        } else {
            normal_files.push(file.clone());
        }
    }
    
    // 特殊文件按优先级降序排序
    special_files.sort_by(|a, b| b.0.cmp(&a.0));
    let special_sorted: Vec<String> = special_files.into_iter().map(|(_, f)| f).collect();
    
    // 普通文件自然排序
    let mut normal_sorted = natural_sort(&normal_files);
    
    // 合并结果
    let mut result = special_sorted;
    result.append(&mut normal_sorted);
    result
}

/// 从文件路径中提取章节信息
///
/// 支持格式：
/// - `chapter_01/001.png` -> ("chapter_01", "001.png")
/// - `01 - Title/002.jpg` -> ("01 - Title", "002.jpg")
/// - `single.cbz` -> ("", "single.cbz")
pub fn extract_chapter_and_file(path: &str) -> (String, String) {
    use std::path::Path;

    let path = Path::new(path);

    // 如果有父目录，认为是章节名
    if let Some(parent) = path.parent() {
        let chapter = parent
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or_default()
            .to_string();
        let file = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or_default()
            .to_string();
        (chapter, file)
    } else {
        // 单文件漫画
        (
            "".to_string(),
            path.file_name()
                .and_then(|s| s.to_str())
                .unwrap_or_default()
                .to_string(),
        )
    }
}

/// 对章节进行排序
/// 
/// 使用自然排序对章节名进行排序。
pub fn sort_chapters(chapters: &mut [String]) {
    natural_sort_in_place(chapters);
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
                    image_extensions.iter().any(|&ie| ie.eq_ignore_ascii_case(ext))
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
        assert_eq!(
            sorted,
            vec!["1.png", "2.png", "10.png", "20.png"]
        );
    }

    #[test]
    fn test_natural_sort_with_prefix() {
        let files = vec![
            "page_10.png".to_string(),
            "page_2.png".to_string(),
            "page_1.png".to_string(),
        ];
        let sorted = natural_sort(&files);
        assert_eq!(
            sorted,
            vec!["page_1.png", "page_2.png", "page_10.png"]
        );
    }

    #[test]
    fn test_smart_sort_cover_first() {
        let files = vec![
            "003.png".to_string(),
            "cover.jpg".to_string(),
            "001.png".to_string(),
            "002.png".to_string(),
        ];
        let sorted = smart_sort(&files);
        // 封面应该在最前面
        assert_eq!(sorted[0], "cover.jpg");
        // 其余按自然排序
        assert_eq!(sorted[1], "001.png");
        assert_eq!(sorted[2], "002.png");
        assert_eq!(sorted[3], "003.png");
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

    #[test]
    fn test_extract_chapter_and_file() {
        let (chapter, file) = extract_chapter_and_file("chapter_01/001.png");
        assert_eq!(chapter, "chapter_01");
        assert_eq!(file, "001.png");

        let (chapter, file) = extract_chapter_and_file("single.cbz");
        assert_eq!(chapter, "");
        assert_eq!(file, "single.cbz");
    }

    #[test]
    fn test_special_file_priority() {
        assert_eq!(special_file_priority("cover.jpg"), 100);
        assert_eq!(special_file_priority("封面.png"), 100);
        assert_eq!(special_file_priority("index.txt"), 90);
        assert_eq!(special_file_priority("目录.jpg"), 90);
        assert_eq!(special_file_priority("color_page.png"), 80);
        assert_eq!(special_file_priority("001.png"), 50);
    }
}

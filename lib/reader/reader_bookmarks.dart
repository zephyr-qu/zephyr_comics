import 'package:signals_flutter/signals_flutter.dart';

import '../reading/reading_records.dart';

/// 书签查看/切换的有限结果。文案留给视图，模块不产出版本相关的字符串。
enum BookmarkToggleResult { added, removed, failed }

/// 阅读器书签特性状态：集合归属、加载与切换都在这一个模块里，
/// 屏幕只订阅 `pages` 信号并渲染。
final class ReaderBookmarks {
  ReaderBookmarks({required this.filePath, required this.records});

  final String filePath;
  final ReadingRecords records;

  final Signal<Set<int>> pages = signal<Set<int>>(const {});

  /// 加载已有书签；失败保持空集，不打断阅读（书签是增强功能）。
  Future<void> load() async {
    try {
      final bookmarks = await records.bookmarksFor(filePath);
      pages.value = Set.unmodifiable(
        bookmarks.map((bookmark) => bookmark.pageIndex),
      );
    } catch (_) {
      // 书签加载失败不影响阅读。
    }
  }

  /// 切换一页的书签状态。写失败时集合保持不变并返回 failed。
  Future<BookmarkToggleResult> toggle(int pageIndex) async {
    try {
      if (pages.value.contains(pageIndex)) {
        await records.removeBookmark(filePath, pageIndex);
        final next = Set<int>.of(pages.value)..remove(pageIndex);
        pages.value = Set.unmodifiable(next);
        return BookmarkToggleResult.removed;
      }
      await records.addBookmark(filePath, pageIndex);
      final next = Set<int>.of(pages.value)..add(pageIndex);
      pages.value = Set.unmodifiable(next);
      return BookmarkToggleResult.added;
    } catch (_) {
      return BookmarkToggleResult.failed;
    }
  }
}

import '../src/rust/api/progress.dart' as rust;
import '../src/rust/library/progress.dart' as rust_progress;

/// Product-facing progress; FRB/SQLite types never cross this boundary.
final class ReadingProgressRecord {
  const ReadingProgressRecord({
    required this.filePath,
    required this.pageIndex,
    required this.lastReadAt,
    required this.completionPercent,
  });

  final String filePath;
  final int pageIndex;
  final DateTime lastReadAt;
  final double completionPercent;

  bool get isFinished => completionPercent >= 99.0;
}

final class ReadingHistoryEntry {
  const ReadingHistoryEntry({
    required this.filePath,
    required this.pageIndex,
    required this.lastReadAt,
    required this.completionPercent,
  });

  final String filePath;
  final int pageIndex;
  final DateTime lastReadAt;
  final double completionPercent;

  bool get isFinished => completionPercent >= 99.0;
}

final class BookmarkRecord {
  const BookmarkRecord({
    required this.filePath,
    required this.pageIndex,
    required this.createdAt,
    this.note,
  });

  final String filePath;
  final int pageIndex;
  final DateTime createdAt;
  final String? note;
}

abstract interface class ReadingRecordsAdapter {
  Future<ReadingProgressRecord?> readProgress(String filePath);

  Future<void> saveProgress({
    required String filePath,
    required int pageIndex,
    required int totalPages,
  });

  Future<List<ReadingHistoryEntry>> readHistory({required int limit});

  Future<void> removeHistory(String filePath);

  Future<void> resetProgress(String filePath);

  Future<List<BookmarkRecord>> readBookmarks(String filePath);

  Future<BookmarkRecord> addBookmark(
    String filePath,
    int pageIndex, {
    String? note,
  });

  Future<void> removeBookmark(String filePath, int pageIndex);
}

/// Product seam shared by detail, history and reader surfaces.
final class ReadingRecords {
  ReadingRecords({required this.adapter});

  final ReadingRecordsAdapter adapter;

  Future<ReadingProgressRecord?> progressFor(String filePath) =>
      adapter.readProgress(filePath);

  Future<void> recordProgress({
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) {
    final safeTotal = totalPages < 1 ? 1 : totalPages;
    final safePage = pageIndex.clamp(0, safeTotal - 1).toInt();
    // 完成度由 Rust 侧统一计算；这里只负责夹取页面索引。
    return adapter.saveProgress(
      filePath: filePath,
      pageIndex: safePage,
      totalPages: safeTotal,
    );
  }

  Future<List<ReadingHistoryEntry>> history({int limit = 100}) =>
      adapter.readHistory(limit: limit.clamp(1, 1000).toInt());

  Future<void> removeHistory(String filePath) =>
      adapter.removeHistory(filePath);

  Future<void> resetProgress(String filePath) =>
      adapter.resetProgress(filePath);

  Future<List<BookmarkRecord>> bookmarksFor(String filePath) =>
      adapter.readBookmarks(filePath);

  Future<BookmarkRecord> addBookmark(
    String filePath,
    int pageIndex, {
    String? note,
  }) => adapter.addBookmark(filePath, pageIndex, note: note);

  Future<void> removeBookmark(String filePath, int pageIndex) =>
      adapter.removeBookmark(filePath, pageIndex);
}

/// Production adapter for the existing Rust SQLite API.
final class FrbReadingRecordsAdapter implements ReadingRecordsAdapter {
  @override
  Future<ReadingProgressRecord?> readProgress(String filePath) async {
    final value = rust.getReadingProgress(filePath: filePath);
    return value == null ? null : _progress(value);
  }

  @override
  Future<void> saveProgress({
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) async {
    rust.saveReadingProgress(
      filePath: filePath,
      pageIndex: BigInt.from(pageIndex),
      totalPages: BigInt.from(totalPages),
    );
  }

  @override
  Future<List<ReadingHistoryEntry>> readHistory({required int limit}) async =>
      (await rust.getReadingHistory(limit: limit))
          .map(
            (value) => ReadingHistoryEntry(
              filePath: value.filePath,
              pageIndex: value.pageIndex.toInt(),
              lastReadAt: DateTime.fromMillisecondsSinceEpoch(
                value.lastReadTimestamp.toInt(),
              ),
              completionPercent: value.completionPercent,
            ),
          )
          .toList(growable: false);

  @override
  Future<void> removeHistory(String filePath) async {
    rust.hideReadingHistory(filePath: filePath);
  }

  @override
  Future<void> resetProgress(String filePath) async {
    rust.removeReadingProgress(filePath: filePath);
  }

  @override
  Future<List<BookmarkRecord>> readBookmarks(String filePath) async => rust
      .getBookmarks(filePath: filePath)
      .map(_bookmark)
      .toList(growable: false);

  @override
  Future<BookmarkRecord> addBookmark(
    String filePath,
    int pageIndex, {
    String? note,
  }) async => _bookmark(
    rust.addBookmark(filePath: filePath, pageIndex: pageIndex, note: note),
  );

  @override
  Future<void> removeBookmark(String filePath, int pageIndex) async {
    rust.removeBookmark(filePath: filePath, pageIndex: pageIndex);
  }

  ReadingProgressRecord _progress(rust_progress.ReadingProgress value) =>
      ReadingProgressRecord(
        filePath: value.filePath,
        pageIndex: value.pageIndex.toInt(),
        lastReadAt: DateTime.fromMillisecondsSinceEpoch(
          value.lastReadTimestamp.toInt(),
        ),
        completionPercent: value.completionPercent,
      );

  BookmarkRecord _bookmark(rust_progress.Bookmark value) => BookmarkRecord(
    filePath: value.filePath,
    pageIndex: value.pageIndex.toInt(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(value.createdAt.toInt()),
    note: value.note,
  );
}

/// Deterministic adapter used by module and widget tests.
final class InMemoryReadingRecordsAdapter implements ReadingRecordsAdapter {
  final Map<String, ReadingProgressRecord> _progress = {};
  final Map<String, bool> _historyVisible = {};
  final Map<String, Map<int, BookmarkRecord>> _bookmarks = {};

  @override
  Future<ReadingProgressRecord?> readProgress(String filePath) async =>
      _progress[filePath];

  @override
  Future<void> saveProgress({
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) async {
    // 镜像 Rust 完成度语义：夹取索引，末页记 100%，否则按占比。
    final safeTotal = totalPages < 1 ? 1 : totalPages;
    final safePage = pageIndex.clamp(0, safeTotal - 1).toInt();
    final completion = safePage == safeTotal - 1
        ? 100.0
        : (safePage / safeTotal) * 100.0;
    final previous = _progress[filePath];
    final finished = previous?.isFinished == true || completion >= 99.0;
    _progress[filePath] = ReadingProgressRecord(
      filePath: filePath,
      pageIndex: safePage,
      lastReadAt: DateTime.now(),
      completionPercent: finished ? 100.0 : completion,
    );
    _historyVisible[filePath] = true;
  }

  @override
  Future<List<ReadingHistoryEntry>> readHistory({required int limit}) async {
    final values = <ReadingHistoryEntry>[];
    for (final value in _progress.values) {
      if (_historyVisible[value.filePath] == false) continue;
      values.add(
        ReadingHistoryEntry(
          filePath: value.filePath,
          pageIndex: value.pageIndex,
          lastReadAt: value.lastReadAt,
          completionPercent: value.completionPercent,
        ),
      );
    }
    values.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    return values.take(limit).toList(growable: false);
  }

  @override
  Future<void> removeHistory(String filePath) async {
    if (_progress.containsKey(filePath)) _historyVisible[filePath] = false;
  }

  @override
  Future<void> resetProgress(String filePath) async {
    _progress.remove(filePath);
    _historyVisible.remove(filePath);
  }

  @override
  Future<List<BookmarkRecord>> readBookmarks(String filePath) async =>
      (_bookmarks[filePath]?.values.toList(growable: false) ?? const [])
        ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

  @override
  Future<BookmarkRecord> addBookmark(
    String filePath,
    int pageIndex, {
    String? note,
  }) async {
    final bookmark = BookmarkRecord(
      filePath: filePath,
      pageIndex: pageIndex,
      note: note,
      createdAt: DateTime.now(),
    );
    (_bookmarks[filePath] ??= {})[pageIndex] = bookmark;
    return bookmark;
  }

  @override
  Future<void> removeBookmark(String filePath, int pageIndex) async {
    _bookmarks[filePath]?.remove(pageIndex);
  }
}

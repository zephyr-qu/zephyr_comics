import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/reading/reading_records.dart';
import 'package:zephyr_comics/reader/reader_bookmarks.dart';

final class _FailingRecordsAdapter implements ReadingRecordsAdapter {
  final InMemoryReadingRecordsAdapter _inner = InMemoryReadingRecordsAdapter();

  @override
  Future<ReadingProgressRecord?> readProgress(String filePath) =>
      _inner.readProgress(filePath);

  @override
  Future<void> saveProgress({
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) => _inner.saveProgress(
    filePath: filePath,
    pageIndex: pageIndex,
    totalPages: totalPages,
  );

  @override
  Future<List<ReadingHistoryEntry>> readHistory({required int limit}) =>
      _inner.readHistory(limit: limit);

  @override
  Future<void> removeHistory(String filePath) => _inner.removeHistory(filePath);

  @override
  Future<void> resetProgress(String filePath) => _inner.resetProgress(filePath);

  @override
  Future<List<BookmarkRecord>> readBookmarks(String filePath) =>
      _inner.readBookmarks(filePath);

  @override
  Future<BookmarkRecord> addBookmark(
    String filePath,
    int pageIndex, {
    String? note,
  }) {
    throw StateError('bookmark write failed');
  }

  @override
  Future<void> removeBookmark(String filePath, int pageIndex) async {}
}

void main() {
  test('load restores saved bookmark pages', () async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());
    await records.addBookmark('/comics/a.cbz', 7);
    final bookmarks = ReaderBookmarks(
      filePath: '/comics/a.cbz',
      records: records,
    );

    await bookmarks.load();

    expect(bookmarks.pages.value, {7});
  });

  test('toggle adds then removes while the signal follows', () async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());
    final bookmarks = ReaderBookmarks(
      filePath: '/comics/a.cbz',
      records: records,
    );

    expect(await bookmarks.toggle(3), BookmarkToggleResult.added);
    expect(bookmarks.pages.value, {3});
    expect((await records.bookmarksFor('/comics/a.cbz')).single.pageIndex, 3);

    expect(await bookmarks.toggle(3), BookmarkToggleResult.removed);
    expect(bookmarks.pages.value, isEmpty);
    expect(await records.bookmarksFor('/comics/a.cbz'), isEmpty);
  });

  test('failed toggle leaves the set unchanged and reports failed', () async {
    final records = ReadingRecords(adapter: _FailingRecordsAdapter());
    final bookmarks = ReaderBookmarks(
      filePath: '/comics/a.cbz',
      records: records,
    );

    expect(await bookmarks.toggle(3), BookmarkToggleResult.failed);
    expect(bookmarks.pages.value, isEmpty);
  });

  test('load failure keeps the set empty without throwing', () async {
    final records = ReadingRecords(adapter: _FailingRecordsAdapter());
    final bookmarks = ReaderBookmarks(
      filePath: '/comics/a.cbz',
      records: records,
    );

    await bookmarks.load();

    expect(bookmarks.pages.value, isEmpty);
  });
}

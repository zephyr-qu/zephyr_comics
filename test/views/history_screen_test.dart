import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/reading/reading_records.dart';
import 'package:zephyr_comics/library/comic_library.dart';
import 'package:zephyr_comics/views/history/history_screen.dart';

void main() {
  testWidgets('top refresh reloads history and waits for completion', (
    tester,
  ) async {
    final adapter = _FakeReadingRecordsAdapter([
      ReadingHistoryEntry(
        filePath: '/comics/one.cbz',
        pageIndex: 1,
        lastReadAt: _fixedTime,
        completionPercent: 50,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(records: ReadingRecords(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.historyCalls, 1);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(adapter.historyCalls, 2);
    expect(find.text('one.cbz'), findsOneWidget);
  });

  testWidgets('injected library entries resolve title and cover source', (
    tester,
  ) async {
    final adapter = _FakeReadingRecordsAdapter([
      ReadingHistoryEntry(
        filePath: '/comics/one.cbz',
        pageIndex: 1,
        lastReadAt: _fixedTime,
        completionPercent: 50,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          records: ReadingRecords(adapter: adapter),
          libraryEntries: const [
            ComicLibraryEntry(
              path: '/comics/one.cbz',
              title: 'One',
              format: 'cbz',
              fileSize: 1,
              totalPages: 10,
              addedAt: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('One'), findsOneWidget);
    expect(find.textContaining('第 2 / 10 页'), findsOneWidget);
  });

  testWidgets('history errors remain visible instead of becoming empty state', (
    tester,
  ) async {
    final adapter = _FakeReadingRecordsAdapter(
      const [],
      error: StateError('db failed'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(records: ReadingRecords(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史暂时不可用'), findsOneWidget);
    expect(find.textContaining('db failed'), findsOneWidget);
    expect(find.text('暂无阅读记录'), findsNothing);
  });
}

final _fixedTime = DateTime(2026, 1, 1);

class _FakeReadingRecordsAdapter implements ReadingRecordsAdapter {
  _FakeReadingRecordsAdapter(this.entries, {this.error});

  final List<ReadingHistoryEntry> entries;
  final Object? error;
  int historyCalls = 0;

  @override
  Future<List<ReadingHistoryEntry>> readHistory({required int limit}) async {
    historyCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return entries;
  }

  @override
  Future<ReadingProgressRecord?> readProgress(String filePath) async => null;

  @override
  Future<void> saveProgress({
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) async {}

  @override
  Future<void> removeHistory(String filePath) async {}

  @override
  Future<void> resetProgress(String filePath) async {}

  @override
  Future<List<BookmarkRecord>> readBookmarks(String filePath) async => const [];

  @override
  Future<BookmarkRecord> addBookmark(
    String filePath,
    int pageIndex, {
    String? note,
  }) async => BookmarkRecord(
    filePath: filePath,
    pageIndex: pageIndex,
    createdAt: _fixedTime,
    note: note,
  );

  @override
  Future<void> removeBookmark(String filePath, int pageIndex) async {}
}

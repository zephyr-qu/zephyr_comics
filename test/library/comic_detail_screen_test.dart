import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/library/comic_library.dart';
import 'package:zephyr_comics/reading/reading_records.dart';
import 'package:zephyr_comics/views/library/comic_detail_screen.dart';

/// The detail page is taller than the default 800x600 test viewport, and a
/// ListView does not build off-screen children. Sizing the viewport explicitly
/// keeps the reset-row taps independent of scroll geometry — which is what the
/// old `scrollUntilVisible` approach was fragile about.
Future<void> _pumpDetail(
  WidgetTester tester, {
  required ComicLibraryEntry entry,
  required ReadingRecords records,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: ComicDetailScreen(entry: entry, records: records),
    ),
  );
  await tester.pumpAndSettle();
}

const _entry = ComicLibraryEntry(
  path: '/comics/blue.cbz',
  title: 'Blue Sky',
  format: 'cbz',
  fileSize: 100,
  totalPages: 20,
  addedAt: 1,
);

void main() {
  testWidgets('detail shows progress and bookmarks with injected records', (
    tester,
  ) async {
    const path = '/comics/blue.cbz';
    final adapter = InMemoryReadingRecordsAdapter();
    final records = ReadingRecords(adapter: adapter);
    await adapter.saveProgress(filePath: path, pageIndex: 4, totalPages: 16);
    await records.addBookmark(path, 4);

    await _pumpDetail(tester, entry: _entry, records: records);

    expect(find.text('Blue Sky'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
    // The prototype's progress readout names the page, not a bare percentage.
    expect(find.text('读至第 5 页'), findsOneWidget);
    expect(find.text('第 5 页'), findsOneWidget);
  });

  testWidgets('reset takes two taps and is not armed without progress', (
    tester,
  ) async {
    const path = '/comics/blue.cbz';
    final adapter = InMemoryReadingRecordsAdapter();
    final records = ReadingRecords(adapter: adapter);
    await adapter.saveProgress(filePath: path, pageIndex: 4, totalPages: 16);

    await _pumpDetail(tester, entry: _entry, records: records);

    // First tap only arms the action.
    await tester.tap(find.byKey(const Key('detail-reset')));
    await tester.pumpAndSettle();
    expect(find.text('再点一次确认重置'), findsOneWidget);
    expect(await records.progressFor(path), isNotNull);

    // Second tap commits it.
    await tester.tap(find.byKey(const Key('detail-reset')));
    await tester.pumpAndSettle();
    expect(await records.progressFor(path), isNull);

    // The control returns to its idle label once the progress is gone.
    expect(find.text('重置阅读进度'), findsOneWidget);
    expect(find.text('尚未开始'), findsOneWidget);
  });

  testWidgets('a comic with no progress has nothing to reset', (tester) async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());

    await _pumpDetail(
      tester,
      entry: const ComicLibraryEntry(
        path: '/comics/fresh.cbz',
        title: 'Fresh',
        format: 'cbz',
        fileSize: 100,
        totalPages: 20,
        addedAt: 1,
      ),
      records: records,
    );

    expect(find.text('尚未开始'), findsOneWidget);
    expect(find.text('还没有书签。阅读时点按页面中央，即可记下当前页。'), findsOneWidget);
    // Nothing to reset, so the control never arms.
    await tester.tap(find.byKey(const Key('detail-reset')));
    await tester.pumpAndSettle();
    expect(find.text('再点一次确认重置'), findsNothing);
  });

  testWidgets('deleting a bookmark keeps reading progress', (tester) async {
    const path = '/comics/blue.cbz';
    final adapter = InMemoryReadingRecordsAdapter();
    final records = ReadingRecords(adapter: adapter);
    await adapter.saveProgress(filePath: path, pageIndex: 4, totalPages: 16);
    await records.addBookmark(path, 4);

    await _pumpDetail(tester, entry: _entry, records: records);
    expect(find.text('第 5 页'), findsOneWidget);

    await tester.tap(find.byTooltip('删除书签'));
    await tester.pumpAndSettle();

    expect(find.text('第 5 页'), findsNothing);
    expect(find.text('还没有书签。阅读时点按页面中央，即可记下当前页。'), findsOneWidget);
    // The bookmark is its own record: removing it leaves progress untouched.
    expect(await records.bookmarksFor(path), isEmpty);
    expect(await records.progressFor(path), isNotNull);
  });
}

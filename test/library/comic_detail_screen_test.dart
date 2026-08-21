import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/library/comic_library.dart';
import 'package:zephyr_comics/reading/reading_records.dart';
import 'package:zephyr_comics/views/library/comic_detail_screen.dart';

void main() {
  testWidgets('detail shows progress and bookmarks with injected records', (
    tester,
  ) async {
    const path = '/comics/blue.cbz';
    final adapter = InMemoryReadingRecordsAdapter();
    final records = ReadingRecords(adapter: adapter);
    await adapter.saveProgress(
      filePath: path,
      pageIndex: 4,
      completionPercent: 25,
    );
    await records.addBookmark(path, 4);

    await tester.pumpWidget(
      MaterialApp(
        home: ComicDetailScreen(
          entry: const ComicLibraryEntry(
            path: path,
            title: 'Blue Sky',
            format: 'cbz',
            fileSize: 100,
            totalPages: 20,
            addedAt: 1,
          ),
          records: records,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blue Sky'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('已读 25%'), findsOneWidget);
    expect(find.text('第 5 页'), findsOneWidget);
  });
}

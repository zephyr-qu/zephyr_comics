import 'package:flutter_test/flutter_test.dart';

import 'package:zephyr_comics/reading/reading_records.dart';

void main() {
  test('progress is clamped and completion is only set on last page', () async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());

    await records.recordProgress(
      filePath: '/comics/a.cbz',
      pageIndex: 99,
      totalPages: 10,
    );

    final progress = await records.progressFor('/comics/a.cbz');
    expect(progress?.pageIndex, 9);
    expect(progress?.isFinished, isTrue);

    await records.recordProgress(
      filePath: '/comics/a.cbz',
      pageIndex: -2,
      totalPages: 10,
    );
    expect((await records.progressFor('/comics/a.cbz'))?.pageIndex, 0);
    expect((await records.progressFor('/comics/a.cbz'))?.isFinished, isTrue);
  });

  test('history can be removed without losing progress or bookmarks', () async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());
    await records.recordProgress(
      filePath: '/comics/a.cbz',
      pageIndex: 2,
      totalPages: 10,
    );
    await records.addBookmark('/comics/a.cbz', 2);

    await records.removeHistory('/comics/a.cbz');

    expect(await records.history(), isEmpty);
    expect((await records.progressFor('/comics/a.cbz'))?.pageIndex, 2);
    expect((await records.bookmarksFor('/comics/a.cbz')).single.pageIndex, 2);
  });

  test('bookmarks are unique by comic and page and can be deleted', () async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());
    final first = await records.addBookmark('/comics/a.cbz', 3);
    final second = await records.addBookmark(
      '/comics/a.cbz',
      3,
      note: 'updated',
    );

    expect(second.pageIndex, 3);
    expect(second.note, 'updated');
    expect((await records.bookmarksFor('/comics/a.cbz')), hasLength(1));
    expect(first.filePath, second.filePath);

    await records.removeBookmark('/comics/a.cbz', 3);
    expect(await records.bookmarksFor('/comics/a.cbz'), isEmpty);
  });

  test('reset progress clears only progress and history visibility', () async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());
    await records.recordProgress(
      filePath: '/comics/a.cbz',
      pageIndex: 2,
      totalPages: 3,
    );
    await records.addBookmark('/comics/a.cbz', 1);

    await records.resetProgress('/comics/a.cbz');

    expect(await records.progressFor('/comics/a.cbz'), isNull);
    expect(await records.history(), isEmpty);
    expect((await records.bookmarksFor('/comics/a.cbz')), hasLength(1));
  });
}

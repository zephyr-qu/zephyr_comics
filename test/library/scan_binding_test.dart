import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/src/rust/api/library.dart';
import 'package:zephyr_comics/src/rust/api/progress.dart';
import 'package:zephyr_comics/src/rust/library/db.dart';
import 'package:zephyr_comics/src/rust/library/progress.dart';

void main() {
  test('library scan binding stays asynchronous', () {
    final Future<List<LibraryEntry>> Function({required String path}) scan =
        scanDirectoryToLibrary;

    expect(scan, isA<Function>());
  });

  test('reading history binding stays asynchronous', () {
    final Future<List<ReadingProgress>> Function({required int limit}) history =
        getReadingHistory;

    expect(history, isA<Function>());
  });
}

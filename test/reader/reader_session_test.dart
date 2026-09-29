import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/reading/reading_records.dart';
import 'package:zephyr_comics/reader/reader_engine.dart';
import 'package:zephyr_comics/reader/reader_session.dart';

class FakeReaderEngine implements ReaderEngine {
  FakeReaderEngine({
    this.totalPages = 5,
    this.openCompleter,
    Set<int>? failOncePages,
  }) : failOncePages = failOncePages ?? <int>{};
  final int totalPages;
  final Completer<void>? openCompleter;
  final Set<int> failOncePages;
  final List<int> loads = [];

  @override
  Future<ReaderBook> open(String filePath) async {
    await openCompleter?.future;
    return ReaderBook(totalPages: totalPages);
  }

  @override
  Future<Uint8List> loadPageEncoded(
    String filePath,
    int pageIndex, {
    required int maxWidth,
    required int maxHeight,
  }) async {
    loads.add(pageIndex);
    if (failOncePages.remove(pageIndex)) {
      throw const ReaderFailure(ReaderFailureKind.pageDecode, '页面加载失败');
    }
    return Uint8List.fromList([pageIndex]);
  }
}

final class GatedPageReaderEngine extends FakeReaderEngine {
  GatedPageReaderEngine({super.totalPages});

  final Map<int, Completer<void>> gates = {};
  int activeLoads = 0;
  int maxActiveLoads = 0;

  @override
  Future<Uint8List> loadPageEncoded(
    String filePath,
    int pageIndex, {
    required int maxWidth,
    required int maxHeight,
  }) async {
    loads.add(pageIndex);
    activeLoads++;
    maxActiveLoads = activeLoads > maxActiveLoads
        ? activeLoads
        : maxActiveLoads;
    try {
      await gates.putIfAbsent(pageIndex, Completer<void>.new).future;
      return Uint8List.fromList([pageIndex]);
    } finally {
      activeLoads--;
    }
  }
}

Future<void> releaseRequestedPages(GatedPageReaderEngine engine) async {
  while (true) {
    final pending = engine.gates.values.where((gate) => !gate.isCompleted);
    if (pending.isEmpty) {
      await Future<void>.delayed(Duration.zero);
      if (engine.gates.values.every((gate) => gate.isCompleted)) return;
      continue;
    }
    for (final gate in pending.toList()) {
      gate.complete();
    }
    await Future<void>.delayed(Duration.zero);
  }
}

/// Gated/failing progress adapter so persist behavior stays observable
/// without touching the FRB channel.
final class _GatedRecordsAdapter implements ReadingRecordsAdapter {
  _GatedRecordsAdapter({this.writeGate, this.failSaves = false});
  final Completer<void>? writeGate;
  final bool failSaves;
  final InMemoryReadingRecordsAdapter _inner = InMemoryReadingRecordsAdapter();
  int writes = 0;

  @override
  Future<ReadingProgressRecord?> readProgress(String filePath) =>
      _inner.readProgress(filePath);

  @override
  Future<void> saveProgress({
    required String filePath,
    required int pageIndex,
    required int totalPages,
  }) {
    if (failSaves) {
      throw const ReaderFailure(ReaderFailureKind.persistence, '阅读进度保存失败');
    }
    writes++;
    return () async {
      await writeGate?.future;
      await _inner.saveProgress(
        filePath: filePath,
        pageIndex: pageIndex,
        totalPages: totalPages,
      );
    }();
  }

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
  }) => _inner.addBookmark(filePath, pageIndex, note: note);

  @override
  Future<void> removeBookmark(String filePath, int pageIndex) =>
      _inner.removeBookmark(filePath, pageIndex);
}

Future<ReadingRecords> recordsWith({
  int? savedPage,
  int totalPages = 5,
  Completer<void>? writeGate,
  bool failSaves = false,
}) async {
  final adapter = _GatedRecordsAdapter(
    writeGate: writeGate,
    failSaves: failSaves,
  );
  if (savedPage != null) {
    await adapter.saveProgress(
      filePath: 'book.cbz',
      pageIndex: savedPage,
      totalPages: totalPages,
    );
  }
  return ReadingRecords(adapter: adapter);
}

void main() {
  test('open restores and clamps saved progress', () async {
    final records = await recordsWith(savedPage: 99, totalPages: 5);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: FakeReaderEngine(totalPages: 3),
      records: records,
    );
    await session.open();
    final ready = session.snapshot.value as ReaderReady;
    expect(ready.totalPages, 3);
    expect(ready.currentPage, 2);
    await session.close();
  });

  test('open prepares the restored page and the next page', () async {
    final engine = FakeReaderEngine(totalPages: 10);
    final records = await recordsWith(savedPage: 3, totalPages: 10);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );

    await session.open();
    await Future<void>.delayed(Duration.zero);

    expect(engine.loads, isNotEmpty);
    expect(engine.loads.first, 3);
    expect(engine.loads, contains(4));
    await session.close();
  });

  test(
    'prefetches a bounded forward window with limited concurrency',
    () async {
      final engine = GatedPageReaderEngine()
        ..gates.addAll({
          for (var index = 0; index < 12; index++) index: Completer<void>(),
        });
      final records = await recordsWith();
      final session = ReaderSession(
        filePath: 'book.cbz',
        engine: engine,
        records: records,
      );

      await session.open();
      expect(engine.loads, [0, 1]);
      await releaseRequestedPages(engine);

      expect(engine.loads.toSet(), {0, 1, 2, 3});
      expect(engine.maxActiveLoads, 2);
      expect(session.cachedPageIndexes.length, lessThanOrEqualTo(4));
      await session.close();
    },
  );

  test('page requests are cached and retry reloads', () async {
    final engine = FakeReaderEngine();
    final records = await recordsWith();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    await session.loadPage(1);
    await session.loadPage(1);
    expect(engine.loads.where((index) => index == 1), hasLength(1));
    await session.retryPage(1);
    expect(engine.loads.where((index) => index == 1), hasLength(2));
    await session.close();
  });

  test('moving backward reverses the bounded prefetch window', () async {
    final engine = FakeReaderEngine(totalPages: 12);
    final records = await recordsWith(savedPage: 5, totalPages: 12);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    await Future<void>.delayed(Duration.zero);

    session.moveTo(4);
    await Future<void>.delayed(Duration.zero);

    expect(session.cachedPageIndexes, {1, 2, 3, 4, 5, 6});
    expect(engine.loads.where((index) => index == 3), hasLength(1));
    expect(engine.loads.where((index) => index == 4), hasLength(1));
    await session.close();
  });

  test(
    'repeating the current page does not publish duplicate snapshots',
    () async {
      final engine = FakeReaderEngine(totalPages: 12);
      final records = await recordsWith(savedPage: 5, totalPages: 12);
      final session = ReaderSession(
        filePath: 'book.cbz',
        engine: engine,
        records: records,
      );
      await session.open();

      var notifications = 0;
      session.snapshot.addListener(() => notifications++);

      session.moveTo(5);
      session.moveTo(5);

      expect(notifications, 0);
      await session.close();
    },
  );

  test(
    'canceled page requests are distinguishable from decode failures',
    () async {
      final engine = GatedPageReaderEngine(totalPages: 20);
      final records = await recordsWith(totalPages: 20);
      final session = ReaderSession(
        filePath: 'book.cbz',
        engine: engine,
        records: records,
      );
      await session.open();
      await Future<void>.delayed(Duration.zero);

      final stalePage = session.loadPage(2);
      session.moveTo(15);

      await expectLater(stalePage, throwsA(isA<ReaderPageRequestCancelled>()));
      await releaseRequestedPages(engine);
      await session.close();
    },
  );

  test('returning to an active page retains the shared result', () async {
    final engine = GatedPageReaderEngine(totalPages: 12);
    final records = await recordsWith(savedPage: 5, totalPages: 12);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    expect(engine.loads, [5, 6]);

    session.moveTo(10);
    session.moveTo(6);
    engine.gates[6]!.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final revisitedPage = session.loadPage(6);
    await releaseRequestedPages(engine);
    await revisitedPage;

    expect(engine.loads.where((index) => index == 6), hasLength(1));
    await session.close();
  });

  test('foreground page requests jump ahead of queued prefetches', () async {
    final engine = GatedPageReaderEngine(totalPages: 10);
    final records = await recordsWith();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    expect(engine.loads, [0, 1]);

    final visiblePage = session.loadPage(4);
    engine.gates[0]!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(engine.loads, [0, 1, 4]);
    engine.gates[4]!.complete();
    await visiblePage;
    await session.close();
    for (final gate in engine.gates.values.where((gate) => !gate.isCompleted)) {
      gate.complete();
    }
    await Future<void>.delayed(Duration.zero);
  });

  test('foreground page requests bypass stale active prefetches', () async {
    final engine = GatedPageReaderEngine(totalPages: 20);
    final records = await recordsWith(totalPages: 20);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    expect(engine.loads, [0, 1]);

    session.moveTo(10);
    final visiblePage = session.loadPage(10);
    await Future<void>.delayed(Duration.zero);

    expect(engine.loads, contains(10));
    await releaseRequestedPages(engine);
    await visiblePage;
    await session.close();
  });

  test(
    'deferred moves keep prefetch window stable until scrolling settles',
    () async {
      final engine = GatedPageReaderEngine(totalPages: 20);
      final records = await recordsWith(totalPages: 20);
      final session = ReaderSession(
        filePath: 'book.cbz',
        engine: engine,
        records: records,
      );
      await session.open();
      expect(engine.loads, [0, 1]);

      session.moveTo(10, deferPrefetch: true);
      final visiblePage = session.loadPage(10);
      await Future<void>.delayed(Duration.zero);

      expect(engine.loads, contains(10));
      expect(session.cachedPageIndexes, contains(0));

      session.prefetchCurrentWindow();
      await releaseRequestedPages(engine);
      await visiblePage;

      expect(session.cachedPageIndexes, contains(10));
      expect(session.cachedPageIndexes, isNot(contains(0)));
      await session.close();
    },
  );

  test('the latest current page replaces obsolete queued work', () async {
    final engine = GatedPageReaderEngine(totalPages: 15);
    final records = await recordsWith();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    expect(engine.loads, [0, 1]);

    session.moveTo(5);
    session.moveTo(10);
    engine.gates[0]!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(engine.loads, [0, 1, 5, 10]);
    await releaseRequestedPages(engine);
    await session.close();
  });

  test(
    'rapid page requests keep pending work and concurrency bounded',
    () async {
      final engine = GatedPageReaderEngine(totalPages: 20);
      final records = await recordsWith();
      final session = ReaderSession(
        filePath: 'book.cbz',
        engine: engine,
        records: records,
      );
      await session.open();

      final requests = <Future<void>>[
        for (var index = 0; index < 20; index++)
          session.loadPage(index).then<void>((_) {}, onError: (_) {}),
      ];
      await releaseRequestedPages(engine);
      await Future.wait(requests);

      expect(engine.loads.length, lessThanOrEqualTo(11));
      expect(engine.maxActiveLoads, lessThanOrEqualTo(3));
      expect(session.cachedPageIndexes.length, lessThanOrEqualTo(11));
      await session.close();
    },
  );

  test('prefetch failure is page-local and retry remains available', () async {
    final engine = FakeReaderEngine(failOncePages: {1});
    final records = await recordsWith();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    await Future<void>.delayed(Duration.zero);

    expect(session.snapshot.value, isA<ReaderReady>());
    await expectLater(session.loadPage(1), throwsA(isA<ReaderFailure>()));
    await session.retryPage(1);

    expect(session.snapshot.value, isA<ReaderReady>());
    expect(engine.loads.where((index) => index == 1), hasLength(2));
    await session.close();
  });

  test(
    'concurrent page completions cannot grow or recenter the cache',
    () async {
      final engine = GatedPageReaderEngine()
        ..gates.addAll({
          for (var index = 0; index < 5; index++) index: Completer<void>(),
        });
      final records = await recordsWith();
      final session = ReaderSession(
        filePath: 'book.cbz',
        engine: engine,
        records: records,
      );
      await session.open();
      session.moveTo(4);
      final requests = [
        for (var index = 0; index < 5; index++) session.loadPage(index),
      ];

      expect(session.cachedPageIndexes, {2, 3, 4});
      engine.gates[4]!.complete();
      engine.gates[0]!.complete();
      engine.gates[1]!.complete();
      engine.gates[2]!.complete();
      engine.gates[3]!.complete();
      await Future.wait(requests);

      expect(session.cachedPageIndexes, {2, 3, 4});
      await session.close();
    },
  );

  test('rapid moves debounce and close flushes final progress', () async {
    final engine = FakeReaderEngine();
    final records = await recordsWith();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
      saveDelay: const Duration(hours: 1),
    );
    await session.open();
    session.moveTo(1);
    session.moveTo(4);
    final progressBeforeClose = await records.progressFor('book.cbz');
    expect(progressBeforeClose?.pageIndex, isNot(4));
    await session.close();
    final progress = await records.progressFor('book.cbz');
    expect(progress?.pageIndex, 4);
  });

  test('close is safe while open is still in flight', () async {
    final gate = Completer<void>();
    final records = await recordsWith();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: FakeReaderEngine(openCompleter: gate),
      records: records,
    );
    final opening = session.open();
    await session.close();
    gate.complete();
    await opening;
  });

  test('active loads finishing after close do not start queued work', () async {
    final engine = GatedPageReaderEngine(totalPages: 10);
    final records = await recordsWith();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      records: records,
    );
    await session.open();
    expect(engine.loads, [0, 1]);

    await session.close();
    engine.gates[0]!.complete();
    engine.gates[1]!.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(engine.loads, [0, 1]);
    expect(engine.activeLoads, 0);
  });

  test('close waits for an in-flight progress write', () async {
    final gate = Completer<void>();
    final records = await recordsWith(writeGate: gate);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: FakeReaderEngine(),
      records: records,
      saveDelay: Duration.zero,
    );
    await session.open();
    session.moveTo(2);
    await Future<void>.delayed(Duration.zero);
    var closed = false;
    final closing = session.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await closing;
    final progress = await records.progressFor('book.cbz');
    expect(progress?.pageIndex, 2);
  });

  test('persistence failure becomes a non-blocking warning', () async {
    final records = await recordsWith(failSaves: true);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: FakeReaderEngine(),
      records: records,
      saveDelay: Duration.zero,
    );
    await session.open();
    session.moveTo(2);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final ready = session.snapshot.value as ReaderReady;
    expect(ready.currentPage, 2);
    expect(ready.warning?.kind, ReaderFailureKind.persistence);
    await session.close();
  });
}

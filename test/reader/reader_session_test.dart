import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/reader/reader_engine.dart';
import 'package:zephyr_comics/reader/reader_session.dart';

class FakeReaderEngine implements ReaderEngine {
  FakeReaderEngine({
    this.totalPages = 5,
    this.savedPage,
    this.openCompleter,
    this.writeCompleter,
    this.failWrites = false,
    Set<int>? failOncePages,
  }) : failOncePages = failOncePages ?? <int>{};
  final int totalPages;
  final int? savedPage;
  final Completer<void>? openCompleter;
  final Completer<void>? writeCompleter;
  final bool failWrites;
  final Set<int> failOncePages;
  final List<int> loads = [];
  final List<int> writes = [];

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

  @override
  Future<ReaderProgress?> readProgress(String filePath) async =>
      savedPage == null
      ? null
      : ReaderProgress(filePath: filePath, pageIndex: savedPage!);

  @override
  Future<void> writeProgress(ReaderProgress progress) async {
    writes.add(progress.pageIndex);
    if (failWrites) {
      throw const ReaderFailure(ReaderFailureKind.persistence, '阅读进度保存失败');
    }
    await writeCompleter?.future;
  }
}

final class GatedPageReaderEngine extends FakeReaderEngine {
  GatedPageReaderEngine({super.totalPages, super.savedPage});

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

void main() {
  test('open restores and clamps saved progress', () async {
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: FakeReaderEngine(totalPages: 3, savedPage: 99),
    );
    await session.open();
    final ready = session.snapshot.value as ReaderReady;
    expect(ready.totalPages, 3);
    expect(ready.currentPage, 2);
    await session.close();
  });

  test('open prepares the restored page and the next page', () async {
    final engine = FakeReaderEngine(totalPages: 10, savedPage: 3);
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);

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
      final session = ReaderSession(filePath: 'book.cbz', engine: engine);

      await session.open();
      expect(engine.loads, [0, 1]);
      await releaseRequestedPages(engine);

      expect(engine.loads.toSet(), {0, 1, 2, 3, 4});
      expect(engine.maxActiveLoads, 2);
      expect(session.cachedPageIndexes.length, lessThanOrEqualTo(7));
      await session.close();
    },
  );

  test('page requests are cached and retry reloads', () async {
    final engine = FakeReaderEngine();
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);
    await session.open();
    await session.loadPage(1);
    await session.loadPage(1);
    expect(engine.loads.where((index) => index == 1), hasLength(1));
    await session.retryPage(1);
    expect(engine.loads.where((index) => index == 1), hasLength(2));
    await session.close();
  });

  test('moving backward reverses the bounded prefetch window', () async {
    final engine = FakeReaderEngine(totalPages: 12, savedPage: 5);
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);
    await session.open();
    await Future<void>.delayed(Duration.zero);

    session.moveTo(4);
    await Future<void>.delayed(Duration.zero);

    expect(session.cachedPageIndexes, {0, 1, 2, 3, 4, 5, 6});
    expect(engine.loads.where((index) => index == 3), hasLength(1));
    expect(engine.loads.where((index) => index == 4), hasLength(1));
    await session.close();
  });

  test('returning to an active page retains the shared result', () async {
    final engine = GatedPageReaderEngine(totalPages: 12, savedPage: 5);
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);
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
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);
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

  test('the latest current page replaces obsolete queued work', () async {
    final engine = GatedPageReaderEngine(totalPages: 15);
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);
    await session.open();
    expect(engine.loads, [0, 1]);

    session.moveTo(5);
    session.moveTo(10);
    engine.gates[0]!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(engine.loads, [0, 1, 10]);
    await releaseRequestedPages(engine);
    await session.close();
  });

  test(
    'rapid page requests keep pending work and concurrency bounded',
    () async {
      final engine = GatedPageReaderEngine(totalPages: 20);
      final session = ReaderSession(filePath: 'book.cbz', engine: engine);
      await session.open();

      final requests = <Future<void>>[
        for (var index = 0; index < 20; index++)
          session.loadPage(index).then<void>((_) {}, onError: (_) {}),
      ];
      await releaseRequestedPages(engine);
      await Future.wait(requests);

      expect(engine.loads.length, lessThanOrEqualTo(7));
      expect(engine.maxActiveLoads, 2);
      expect(session.cachedPageIndexes.length, lessThanOrEqualTo(7));
      await session.close();
    },
  );

  test('prefetch failure is page-local and retry remains available', () async {
    final engine = FakeReaderEngine(failOncePages: {1});
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);
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
      final session = ReaderSession(filePath: 'book.cbz', engine: engine);
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
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
      saveDelay: const Duration(hours: 1),
    );
    await session.open();
    session.moveTo(1);
    session.moveTo(4);
    expect(engine.writes, isEmpty);
    await session.close();
    expect(engine.writes, [4]);
  });

  test('close is safe while open is still in flight', () async {
    final gate = Completer<void>();
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: FakeReaderEngine(openCompleter: gate),
    );
    final opening = session.open();
    await session.close();
    gate.complete();
    await opening;
  });

  test('active loads finishing after close do not start queued work', () async {
    final engine = GatedPageReaderEngine(totalPages: 10);
    final session = ReaderSession(filePath: 'book.cbz', engine: engine);
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
    final engine = FakeReaderEngine(writeCompleter: gate);
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: engine,
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
    expect(engine.writes, [2]);
  });

  test('persistence failure becomes a non-blocking warning', () async {
    final session = ReaderSession(
      filePath: 'book.cbz',
      engine: FakeReaderEngine(failWrites: true),
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

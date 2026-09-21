import 'dart:async';
import 'package:flutter/foundation.dart';
import '../reading/reading_records.dart';
import 'reader_engine.dart';

sealed class ReaderSnapshot {
  const ReaderSnapshot();
}

final class ReaderOpening extends ReaderSnapshot {
  const ReaderOpening();
}

final class ReaderReady extends ReaderSnapshot {
  const ReaderReady({
    required this.currentPage,
    required this.totalPages,
    this.pageLayouts = const [],
    this.warning,
  });
  final int currentPage;
  final int totalPages;
  final List<ReaderPageLayout> pageLayouts;
  final ReaderFailure? warning;

  ReaderPageLayout layoutFor(int pageIndex) =>
      pageIndex >= 0 && pageIndex < pageLayouts.length
      ? pageLayouts[pageIndex]
      : ReaderPageLayout.fallback;
}

final class ReaderFailed extends ReaderSnapshot {
  const ReaderFailed(this.failure);
  final ReaderFailure failure;
}

/// A queued page request was superseded by a newer viewport target.
final class ReaderPageRequestCancelled implements Exception {
  const ReaderPageRequestCancelled();
}

final class ReaderSession {
  ReaderSession({
    required this.filePath,
    required this.engine,
    required this.records,
    this.initialPage,
    this.saveDelay = const Duration(milliseconds: 400),
  });

  final String filePath;
  final ReaderEngine engine;
  final ReadingRecords records;
  final int? initialPage;
  final Duration saveDelay;
  final snapshot = ValueNotifier<ReaderSnapshot>(const ReaderOpening());
  static const int _prefetchAhead = 8;
  static const int _prefetchBehind = 2;
  static const int _maxConcurrentPageLoads = 2;
  static const int _maxPendingPageLoads = _prefetchAhead + _prefetchBehind + 1;
  static const int _maxPriorityPageLoads = _maxConcurrentPageLoads + 1;
  static const Duration _deferredWindowDelay = Duration(milliseconds: 160);

  final Map<int, _PageRequest> _pages = {};
  final Map<int, _PageRequest> _queuedPages = {};
  final Map<int, _PageRequest> _activePages = {};
  final List<_PageRequest> _foregroundQueue = [];
  final List<_PageRequest> _prefetchQueue = [];
  Set<int> _desiredPages = const {};
  int _readingDirection = 1;
  Timer? _saveTimer;
  Timer? _deferredWindowTimer;
  bool _closed = false;
  Future<void> _saveQueue = Future<void>.value();

  Future<void> open() async {
    snapshot.value = const ReaderOpening();
    try {
      final results = await Future.wait<Object?>([
        engine.open(filePath),
        records.progressFor(filePath),
      ]);
      final book = results[0] as ReaderBook;
      final progress = results[1] as ReadingProgressRecord?;
      if (_closed) return;
      if (book.totalPages <= 0) {
        throw StateError('漫画文件中没有页面');
      }
      final page = (initialPage ?? progress?.pageIndex ?? 0)
          .clamp(0, book.totalPages - 1)
          .toInt();
      snapshot.value = ReaderReady(
        currentPage: page,
        totalPages: book.totalPages,
        pageLayouts: book.pageLayouts,
      );
      _schedulePageWindow(page, book.totalPages);
    } catch (error) {
      if (_closed) return;
      snapshot.value = ReaderFailed(_failure(error));
    }
  }

  Future<ReaderPage> loadPage(int pageIndex, {bool foreground = true}) {
    if (_closed) {
      return Future.error(StateError('阅读会话已关闭'));
    }
    final ready = snapshot.value;
    if (ready is! ReaderReady) {
      return Future.error(StateError('阅读会话尚未就绪'));
    }
    final index = pageIndex.clamp(0, ready.totalPages - 1).toInt();
    return _requestPage(index, foreground: foreground);
  }

  Future<void> retryPage(int pageIndex) async {
    final ready = snapshot.value;
    if (ready is! ReaderReady) {
      throw StateError('阅读会话尚未就绪');
    }
    final index = pageIndex.clamp(0, ready.totalPages - 1).toInt();
    _pages.remove(index);
    final queued = _queuedPages.remove(index);
    if (queued != null) {
      _foregroundQueue.remove(queued);
      _prefetchQueue.remove(queued);
    }
    await _requestPage(index, foreground: true);
  }

  void moveTo(int pageIndex, {bool deferPrefetch = false}) {
    final ready = snapshot.value;
    if (ready is! ReaderReady || _closed) return;
    final index = pageIndex.clamp(0, ready.totalPages - 1).toInt();
    if (index == ready.currentPage) {
      if (!deferPrefetch) _schedulePageWindow(index, ready.totalPages);
      return;
    }
    final delta = index - ready.currentPage;
    _readingDirection = delta.sign;
    snapshot.value = ReaderReady(
      currentPage: index,
      totalPages: ready.totalPages,
      pageLayouts: ready.pageLayouts,
      warning: ready.warning,
    );
    if (deferPrefetch) {
      _prioritizePage(index);
      _deferredWindowTimer?.cancel();
      _deferredWindowTimer = Timer(_deferredWindowDelay, () {
        if (_closed) return;
        final current = snapshot.value;
        if (current is ReaderReady && current.currentPage == index) {
          _schedulePageWindow(index, current.totalPages);
        }
      });
    } else {
      _schedulePageWindow(index, ready.totalPages);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => _enqueuePersist(index));
  }

  /// Rebuilds the normal prefetch window after a continuous scroll settles.
  void prefetchCurrentWindow() {
    if (_closed) return;
    _deferredWindowTimer?.cancel();
    final ready = snapshot.value;
    if (ready is ReaderReady) {
      _schedulePageWindow(ready.currentPage, ready.totalPages);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final hadPendingSave = _saveTimer?.isActive ?? false;
    _saveTimer?.cancel();
    _deferredWindowTimer?.cancel();
    _cancelQueuedPages();
    _pages.clear();
    final ready = snapshot.value;
    if (hadPendingSave && ready is ReaderReady) {
      _enqueuePersist(ready.currentPage);
    }
    await _saveQueue;
    snapshot.dispose();
  }

  void _enqueuePersist(int pageIndex) {
    _saveQueue = _saveQueue.then((_) async {
      try {
        final ready = snapshot.value;
        if (ready is! ReaderReady) return;
        await records.recordProgress(
          filePath: filePath,
          pageIndex: pageIndex,
          totalPages: ready.totalPages,
        );
      } catch (error) {
        if (_closed) return;
        final ready = snapshot.value;
        if (ready is ReaderReady) {
          snapshot.value = ReaderReady(
            currentPage: ready.currentPage,
            totalPages: ready.totalPages,
            pageLayouts: ready.pageLayouts,
            warning: _failure(error, ReaderFailureKind.persistence),
          );
        }
      }
    });
  }

  Future<ReaderPage> _requestPage(
    int pageIndex, {
    required bool foreground,
    bool highestPriority = false,
  }) {
    final retained = _pages[pageIndex];
    if (retained != null) {
      if (foreground) {
        _promote(retained, highestPriority: highestPriority);
      }
      return retained.future;
    }
    final active = _activePages[pageIndex];
    if (active != null) {
      _retainIfDesired(active);
      return active.future;
    }
    final queued = _queuedPages[pageIndex];
    if (queued != null) {
      _retainIfDesired(queued);
      if (foreground) _promote(queued, highestPriority: highestPriority);
      return queued.future;
    }

    final request = _PageRequest(pageIndex, foreground: foreground);
    if (!_makeRoomFor(request)) return request.future;
    if (_desiredPages.contains(pageIndex)) _pages[pageIndex] = request;
    _queuedPages[pageIndex] = request;
    if (foreground && highestPriority) {
      _foregroundQueue.insert(0, request);
    } else {
      (foreground ? _foregroundQueue : _prefetchQueue).add(request);
    }
    _pumpPageQueue();
    return request.future;
  }

  void _retainIfDesired(_PageRequest request) {
    if (_desiredPages.contains(request.pageIndex)) {
      _pages[request.pageIndex] = request;
    }
  }

  bool _makeRoomFor(_PageRequest incoming) {
    while (_activePages.length + _queuedPages.length >= _maxPendingPageLoads) {
      final prefetch = _prefetchQueue.lastOrNull;
      if (prefetch != null) {
        _cancelQueuedRequest(prefetch, '页面预取已取消');
        continue;
      }
      if (!incoming.foreground) {
        incoming.completeError(StateError('页面预取队列已满'));
        return false;
      }
      final foreground = _foregroundQueue.lastOrNull;
      if (foreground == null) break;
      _cancelQueuedRequest(foreground, '页面请求已被较新的可见页替代');
    }
    return true;
  }

  void _promote(_PageRequest request, {bool highestPriority = false}) {
    if (!_queuedPages.containsKey(request.pageIndex)) {
      return;
    }
    if (request.foreground) {
      if (highestPriority) {
        _foregroundQueue.remove(request);
        _foregroundQueue.insert(0, request);
      }
      return;
    }
    request.foreground = true;
    _prefetchQueue.remove(request);
    if (highestPriority) {
      _foregroundQueue.insert(0, request);
    } else {
      _foregroundQueue.add(request);
    }
  }

  void _pumpPageQueue() {
    if (_closed) return;
    while (_canStartNextPageLoad()) {
      final request = _takeNextRequest();
      if (request == null) return;
      _queuedPages.remove(request.pageIndex);
      _activePages[request.pageIndex] = request;
      unawaited(_performPageLoad(request));
    }
  }

  void _prioritizePage(int pageIndex) {
    for (final request in _activePages.values) {
      request.foreground = request.pageIndex == pageIndex;
    }

    final current = _queuedPages[pageIndex];
    for (final request in List<_PageRequest>.of(_foregroundQueue)) {
      if (request == current) continue;
      _foregroundQueue.remove(request);
      request.foreground = false;
      _prefetchQueue.add(request);
    }
    if (current != null) {
      _prefetchQueue.remove(current);
      current.foreground = true;
      _foregroundQueue.insert(0, current);
    }
    _pumpPageQueue();
  }

  bool _canStartNextPageLoad() {
    if (_activePages.length < _maxConcurrentPageLoads) return true;
    if (_foregroundQueue.isEmpty ||
        _activePages.length >= _maxPriorityPageLoads) {
      return false;
    }
    return _activePages.values.every((request) => !request.foreground);
  }

  _PageRequest? _takeNextRequest() {
    if (_foregroundQueue.isNotEmpty) {
      return _foregroundQueue.removeAt(0);
    }
    if (_prefetchQueue.isNotEmpty) return _prefetchQueue.removeAt(0);
    return null;
  }

  Future<void> _performPageLoad(_PageRequest request) async {
    try {
      final bytes = await engine.loadPageEncoded(
        filePath,
        request.pageIndex,
        maxWidth: 2048,
        maxHeight: 4096,
      );
      request.complete(
        ReaderPage(index: request.pageIndex, encodedBytes: bytes),
      );
      if (request.foreground) {
        _pages[request.pageIndex] = request;
      }
    } catch (error, stackTrace) {
      request.completeError(
        _failure(error, ReaderFailureKind.pageDecode),
        stackTrace,
      );
    } finally {
      _activePages.remove(request.pageIndex);
      if (!_desiredPages.contains(request.pageIndex)) {
        _pages.remove(request.pageIndex);
      }
      _pumpPageQueue();
    }
  }

  void _schedulePageWindow(int center, int totalPages) {
    final desired = <int>{center};
    for (var distance = 1; distance <= _prefetchAhead; distance++) {
      final index = center + (_readingDirection * distance);
      if (index >= 0 && index < totalPages) desired.add(index);
    }
    for (var distance = 1; distance <= _prefetchBehind; distance++) {
      final index = center - (_readingDirection * distance);
      if (index >= 0 && index < totalPages) desired.add(index);
    }
    _desiredPages = desired;
    for (final request in _activePages.values) {
      if (!_desiredPages.contains(request.pageIndex)) {
        request.foreground = false;
      }
    }
    _pages.removeWhere((index, _) => !desired.contains(index));
    _cancelObsoleteQueuedRequests();

    _prefetchPage(center, foreground: true, highestPriority: true);
    for (var distance = 1; distance <= _prefetchAhead; distance++) {
      _prefetchIfInRange(center + (_readingDirection * distance), totalPages);
    }
    for (var distance = 1; distance <= _prefetchBehind; distance++) {
      _prefetchIfInRange(center - (_readingDirection * distance), totalPages);
    }
  }

  void _prefetchIfInRange(int pageIndex, int totalPages) {
    if (pageIndex < 0 || pageIndex >= totalPages) return;
    _prefetchPage(pageIndex);
  }

  void _prefetchPage(
    int pageIndex, {
    bool foreground = false,
    bool highestPriority = false,
  }) {
    unawaited(
      _requestPage(
        pageIndex,
        foreground: foreground,
        highestPriority: highestPriority,
      ).then<void>((_) {}, onError: (_) {}),
    );
  }

  void _cancelObsoleteQueuedRequests() {
    for (final request in List<_PageRequest>.of(_queuedPages.values)) {
      if (_desiredPages.contains(request.pageIndex)) continue;
      _cancelQueuedRequest(request, '页面预取已取消');
    }
  }

  void _cancelQueuedRequest(_PageRequest request, String reason) {
    _foregroundQueue.remove(request);
    _prefetchQueue.remove(request);
    _queuedPages.remove(request.pageIndex);
    _pages.remove(request.pageIndex);
    request.completeError(const ReaderPageRequestCancelled());
  }

  void _cancelQueuedPages() {
    final queued = List<_PageRequest>.of(_queuedPages.values);
    _queuedPages.clear();
    _foregroundQueue.clear();
    _prefetchQueue.clear();
    for (final request in queued) {
      request.completeError(StateError('阅读会话已关闭'));
    }
  }

  @visibleForTesting
  Set<int> get cachedPageIndexes => Set<int>.unmodifiable(_pages.keys);

  ReaderFailure _failure(
    Object error, [
    ReaderFailureKind fallback = ReaderFailureKind.unexpected,
  ]) {
    if (error is ReaderFailure) return error;
    return ReaderFailure(
      fallback,
      fallback == ReaderFailureKind.persistence ? '阅读进度保存失败' : '阅读器发生未知错误',
      error,
    );
  }
}

final class _PageRequest {
  _PageRequest(this.pageIndex, {required this.foreground});

  final int pageIndex;
  bool foreground;
  final Completer<ReaderPage> _completer = Completer<ReaderPage>();

  Future<ReaderPage> get future => _completer.future;

  void complete(ReaderPage page) {
    if (!_completer.isCompleted) _completer.complete(page);
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) _completer.completeError(error, stackTrace);
  }
}

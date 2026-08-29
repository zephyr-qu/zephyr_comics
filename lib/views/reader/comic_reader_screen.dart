import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../models/reader_mode.dart';
import '../../models/settings_options.dart';
import '../../reading/reading_records.dart';
import '../../reader/frb_reader_engine.dart';
import '../../reader/reader_engine.dart';
import '../../reader/reader_session.dart';
import '../../reader/reader_bookmarks.dart';
import '../../signals/app_signals.dart';

class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.filePath,
    this.initialPage,
    this.preserveProgressOnStart = false,
    this.readerEngine,
    this.records,
  });
  final String filePath;
  final int? initialPage;
  final bool preserveProgressOnStart;
  final ReaderEngine? readerEngine;
  final ReadingRecords? records;

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late final ReaderSession _session;
  late final ItemScrollController _itemScrollController;
  late final ItemPositionsListener _positionsListener;
  ExtendedPageController? _pageController;
  ReaderMode _readerMode = ReaderMode.vertical;
  bool _toolbarVisible = false;
  final Set<int> _failedPages = <int>{};
  late final ReaderBookmarks _bookmarks;

  @override
  void initState() {
    super.initState();
    _session = ReaderSession(
      filePath: widget.filePath,
      engine: widget.readerEngine ?? FrbReaderEngine(),
      records: widget.records ?? readingRecords,
      initialPage: widget.initialPage,
      preserveProgressOnStart: widget.preserveProgressOnStart,
    );
    _itemScrollController = ItemScrollController();
    _positionsListener = ItemPositionsListener.create()
      ..itemPositions.addListener(_onContinuousPosition);
    _readerMode = readerMode.value;
    _enterFullscreen();
    _session.open();
    _bookmarks = ReaderBookmarks(
      filePath: widget.filePath,
      records: widget.records ?? readingRecords,
    );
    unawaited(_bookmarks.load());
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onContinuousPosition);
    _pageController?.dispose();
    _session.close();
    _exitFullscreen();
    super.dispose();
  }

  bool get _continuous =>
      _readerMode == ReaderMode.verticalContinuous ||
      _readerMode == ReaderMode.webtoon;

  void _onContinuousPosition() {
    if (!_continuous) return;
    final visible =
        _positionsListener.itemPositions.value
            .where(
              (item) => item.itemTrailingEdge > 0 && item.itemLeadingEdge < 1,
            )
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (visible.isNotEmpty) _session.moveTo(visible.first.index);
  }

  void _enterFullscreen() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  void _exitFullscreen() => SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderSnapshot>(
      valueListenable: _session.snapshot,
      builder: (context, snapshot, _) {
        return Scaffold(
          backgroundColor: _backgroundColor(context),
          body: switch (snapshot) {
            ReaderOpening() => const Center(child: CircularProgressIndicator()),
            ReaderFailed(:final failure) => _fatal(failure),
            ReaderReady() => _ready(snapshot),
          },
        );
      },
    );
  }

  Widget _fatal(ReaderFailure failure) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 56),
        const SizedBox(height: 12),
        Text(failure.message, style: const TextStyle(color: Colors.white)),
        FilledButton(
          key: const Key('reader-fatal-retry'),
          onPressed: _session.open,
          child: const Text('重试'),
        ),
      ],
    ),
  );

  Widget _ready(ReaderReady ready) {
    _pageController ??= ExtendedPageController(
      initialPage: ready.currentPage,
      shouldIgnorePointerWhenScrolling: false,
    );
    return Stack(
      children: [
        if (_continuous)
          ScrollablePositionedList.separated(
            initialScrollIndex: ready.currentPage,
            itemCount: ready.totalPages,
            minCacheExtent: MediaQuery.sizeOf(context).height * 3,
            itemScrollController: _itemScrollController,
            itemPositionsListener: _positionsListener,
            itemBuilder: (_, index) => _page(index, gesture: false),
            separatorBuilder: (_, _) =>
                SizedBox(height: _readerMode == ReaderMode.webtoon ? 0 : 6),
          )
        else
          ExtendedImageGesturePageView.builder(
            controller: _pageController,
            scrollDirection: _readerMode == ReaderMode.vertical
                ? Axis.vertical
                : Axis.horizontal,
            reverse: _readerMode == ReaderMode.rtl,
            itemCount: ready.totalPages,
            itemBuilder: (_, index) => _page(index, gesture: true),
            onPageChanged: _session.moveTo,
          ),
        _gestureOverlay(ready),
        _toolbar(ready),
        if (ready.warning case final warning?)
          Positioned(
            top: 96,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.amber.shade800,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  warning.message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        if (!_toolbarVisible && showPageNumber.value)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Text(
              '${ready.currentPage + 1} / ${ready.totalPages}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _page(int index, {required bool gesture}) {
    final mediaQuery = MediaQuery.of(context);
    final cacheWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio)
        .ceil()
        .clamp(1, 1 << 30)
        .toInt();
    final cacheHeight = (mediaQuery.size.height * mediaQuery.devicePixelRatio)
        .ceil()
        .clamp(1, 1 << 30)
        .toInt();
    return FutureBuilder<ReaderPage>(
      future: _session.loadPage(index),
      builder: (context, result) {
        if (result.hasError) {
          _markPageFailure(index, failed: true);
          return _pageRetry(index);
        }
        final page = result.data;
        if (page == null) {
          return SizedBox(
            height: MediaQuery.sizeOf(context).height,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final imageProvider = ExtendedResizeImage(
          ExtendedMemoryImageProvider(page.encodedBytes),
          width: cacheWidth,
          height: cacheHeight,
          policy: ResizeImagePolicy.fit,
        );
        return ExtendedImage(
          image: imageProvider,
          fit: BoxFit.contain,
          mode: gesture ? ExtendedImageMode.gesture : ExtendedImageMode.none,
          enableLoadState: true,
          loadStateChanged: (state) {
            if (state.extendedImageLoadState == LoadState.completed) {
              _markPageFailure(index, failed: false);
              return null;
            }
            if (state.extendedImageLoadState != LoadState.failed) return null;
            _markPageFailure(index, failed: true);
            return _pageRetry(
              index,
              beforeRetry: () => state.imageProvider.evict(),
            );
          },
        );
      },
    );
  }

  Widget _pageRetry(int index, {Future<bool> Function()? beforeRetry}) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      child: Center(
        child: FilledButton.icon(
          key: Key('reader-page-retry-$index'),
          onPressed: () async {
            try {
              final eviction = beforeRetry?.call();
              if (eviction != null) {
                unawaited(eviction.catchError((_) => false));
              }
            } catch (_) {
              // Cache eviction is best-effort. A provider failure must not
              // suppress the actual page reload.
            }
            try {
              await _session.retryPage(index);
            } catch (_) {}
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.refresh),
          label: const Text('页面加载失败，重试'),
        ),
      ),
    );
  }

  void _markPageFailure(int index, {required bool failed}) {
    final alreadyMarked = _failedPages.contains(index);
    if (alreadyMarked == failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (failed) {
          _failedPages.add(index);
        } else {
          _failedPages.remove(index);
        }
      });
    });
  }

  Widget _gestureOverlay(ReaderReady ready) => IgnorePointer(
    ignoring: _toolbarVisible || _failedPages.contains(ready.currentPage),
    child: Column(
      children: [
        Expanded(
          flex: 2,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _goTo(ready.currentPage - 1, ready),
          ),
        ),
        Expanded(
          flex: 5,
          child: GestureDetector(
            key: const Key('reader-toolbar-toggle'),
            behavior: HitTestBehavior.translucent,
            onTap: () {
              setState(() => _toolbarVisible = true);
              _exitFullscreen();
            },
          ),
        ),
        Expanded(
          flex: 2,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _goTo(ready.currentPage + 1, ready),
          ),
        ),
      ],
    ),
  );

  void _goTo(int page, ReaderReady ready) {
    final target = page.clamp(0, ready.totalPages - 1).toInt();
    if (_continuous) {
      _itemScrollController.scrollTo(
        index: target,
        duration: const Duration(milliseconds: 150),
      );
    } else {
      _pageController?.animateToPage(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.ease,
      );
    }
    _session.moveTo(target);
  }

  Widget _toolbar(ReaderReady ready) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: SafeArea(
      bottom: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _toolbarVisible ? 132 : 0,
        color: Colors.black87,
        child: !_toolbarVisible
            ? null
            : Column(
                children: [
                  SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '返回',
                          onPressed: context.pop,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            '${widget.filePath.split(RegExp(r'[/\\]')).last}  '
                            '${ready.currentPage + 1}/${ready.totalPages}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<ReaderMode>(
                          key: const Key('reader-mode-menu'),
                          tooltip: '阅读模式',
                          initialValue: _readerMode,
                          onSelected: (mode) {
                            setReaderMode(mode);
                            final currentPage =
                                (_session.snapshot.value as ReaderReady)
                                    .currentPage;
                            final previousController = _pageController;
                            _pageController = ExtendedPageController(
                              initialPage: currentPage,
                              shouldIgnorePointerWhenScrolling: false,
                            );
                            setState(() => _readerMode = mode);
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => previousController?.dispose(),
                            );
                          },
                          itemBuilder: (_) => [
                            for (final mode in ReaderMode.values)
                              PopupMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              ),
                          ],
                        ),
                        SignalBuilder(
                          builder: (context) {
                            final bookmarked = _bookmarks.pages.value.contains(
                              ready.currentPage,
                            );
                            return IconButton(
                              key: const Key('reader-bookmark'),
                              tooltip: bookmarked ? '取消书签' : '添加书签',
                              onPressed: () =>
                                  _toggleBookmark(ready.currentPage),
                              icon: Icon(
                                bookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_add_outlined,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: '退出全屏',
                          onPressed: () {
                            setState(() => _toolbarVisible = false);
                            _enterFullscreen();
                          },
                          icon: const Icon(Icons.fullscreen),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: ready.currentPage.toDouble(),
                      min: 0,
                      max: (ready.totalPages - 1).toDouble(),
                      divisions: ready.totalPages > 1
                          ? ready.totalPages - 1
                          : null,
                      label: '第 ${ready.currentPage + 1} 页',
                      onChanged: (value) => _goTo(value.round(), ready),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );

  Future<void> _toggleBookmark(int page) async {
    final result = await _bookmarks.toggle(page);
    if (!mounted) return;
    final message = switch (result) {
      BookmarkToggleResult.added => '已添加书签',
      BookmarkToggleResult.removed => '已取消书签',
      BookmarkToggleResult.failed => '书签操作失败，请重试',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Color _backgroundColor(BuildContext context) =>
      switch (readerBackground.value) {
        ReaderBackground.black => Colors.black,
        ReaderBackground.dark => const Color(0xff151515),
        ReaderBackground.paper => const Color(0xfff2ecdf),
        ReaderBackground.system =>
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff151515)
              : const Color(0xfff2ecdf),
      };
}

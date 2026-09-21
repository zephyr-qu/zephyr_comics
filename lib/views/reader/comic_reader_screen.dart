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
import '../../reader/reader_volume_keys.dart';
import '../../signals/app_signals.dart';
import '../../theme/zephyr_theme.dart';
import '../../utils/format.dart';
import '../widgets/progress_hairline.dart';

class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.filePath,
    this.initialPage,
    this.readerEngine,
    this.records,
    this.volumeKeys,
  });
  final String filePath;
  final int? initialPage;
  final ReaderEngine? readerEngine;
  final ReadingRecords? records;
  final ReaderVolumeKeys? volumeKeys;

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late final ReaderSession _session;
  late final ItemScrollController _itemScrollController;
  late final ItemPositionsListener _positionsListener;
  late final FocusNode _readerFocusNode;
  ExtendedPageController? _pageController;
  ReaderMode _readerMode = ReaderMode.vertical;

  /// Whether the reader chrome (top bar + bottom drawer) is showing. The
  /// collapsed state is the immersive one: a page-number handle and a progress
  /// hairline remain, mirroring the prototype's `{toolbar && …}` form.
  bool _chromeVisible = false;
  bool _continuousScrollActive = false;
  int? _lastContinuousPage;
  final Set<int> _cancelledContinuousPages = <int>{};
  Timer? _cancelledPageRetryTimer;
  final Set<int> _failedPages = <int>{};
  late final ReaderBookmarks _bookmarks;
  late final ReaderVolumeKeys _volumeKeys;

  /// The ready snapshot, or null while the session is opening or has failed.
  ReaderReady? get _readySnapshot {
    final snapshot = _session.snapshot.value;
    return snapshot is ReaderReady ? snapshot : null;
  }

  @override
  void initState() {
    super.initState();
    _readerFocusNode = FocusNode(debugLabel: 'comic-reader');
    _volumeKeys = widget.volumeKeys ?? const AndroidReaderVolumeKeys();
    _volumeKeys.start(_onVolumeKeyPressed);
    _session = ReaderSession(
      filePath: widget.filePath,
      engine: widget.readerEngine ?? FrbReaderEngine(),
      records: widget.records ?? readingRecords,
      initialPage: widget.initialPage,
    );
    _itemScrollController = ItemScrollController();
    _positionsListener = ItemPositionsListener.create()
      ..itemPositions.addListener(_onContinuousPosition);
    _readerMode = settingsSnapshot.value.readerMode;
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
    _cancelledPageRetryTimer?.cancel();
    _readerFocusNode.dispose();
    _volumeKeys.stop();
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
    if (visible.isEmpty) return;
    final pageIndex = visible.first.index;
    if (_lastContinuousPage == pageIndex) return;
    _lastContinuousPage = pageIndex;
    _session.moveTo(pageIndex, deferPrefetch: _continuousScrollActive);
  }

  bool _onContinuousScrollNotification(ScrollNotification notification) {
    if (!_continuous || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification) {
      case ScrollStartNotification():
      case ScrollUpdateNotification():
      case OverscrollNotification():
        _continuousScrollActive = true;
      case ScrollEndNotification():
        _continuousScrollActive = false;
        _session.prefetchCurrentWindow();
        _retryCancelledVisiblePages();
      case _:
        break;
    }
    return false;
  }

  void _enterFullscreen() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  void _exitFullscreen() => SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final settings = settingsSnapshot.value;
        return ValueListenableBuilder<ReaderSnapshot>(
          valueListenable: _session.snapshot,
          builder: (context, snapshot, _) {
            return PopScope(
              // PRD §7: the back action closes an open toolbar before it
              // leaves the route.
              canPop: !_chromeVisible,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && _chromeVisible) {
                  setState(() => _chromeVisible = false);
                  _enterFullscreen();
                }
              },
              child: Focus(
                focusNode: _readerFocusNode,
                autofocus: true,
                onKeyEvent: _onKeyEvent,
                child: Scaffold(
                  backgroundColor: _backgroundColor(
                    context,
                    settings.readerBackground,
                  ),
                  body: switch (snapshot) {
                    ReaderOpening() => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    ReaderFailed(:final failure) => _fatal(failure),
                    ReaderReady() => _ready(
                      snapshot,
                      showPageNumber: settings.showPageNumber,
                    ),
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !settingsSnapshot.value.volumeKeyPaging) {
      return KeyEventResult.ignored;
    }
    final ready = _readySnapshot;
    if (ready == null) return KeyEventResult.ignored;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.audioVolumeUp => 1,
      LogicalKeyboardKey.audioVolumeDown => -1,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    _onVolumeKeyPressed(delta == 1);
    return KeyEventResult.handled;
  }

  void _onVolumeKeyPressed(bool next) {
    if (!mounted || !settingsSnapshot.value.volumeKeyPaging) return;
    final ready = _readySnapshot;
    if (ready == null) return;
    _goTo(ready.currentPage + (next ? 1 : -1), ready);
  }

  Widget _fatal(ReaderFailure failure) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: scheme.onSurface, size: 56),
          const SizedBox(height: ZephyrSpacing.md),
          Text(failure.message, style: TextStyle(color: scheme.onSurface)),
          FilledButton(
            key: const Key('reader-fatal-retry'),
            onPressed: _session.open,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _ready(ReaderReady ready, {required bool showPageNumber}) {
    final scheme = Theme.of(context).colorScheme;
    _pageController ??= ExtendedPageController(
      initialPage: ready.currentPage,
      shouldIgnorePointerWhenScrolling: false,
    );
    // The prototype's `done`: the last page replaces the drawer with a closing
    // card and retires the page-number handle.
    final finished = ready.currentPage + 1 >= ready.totalPages;
    return Stack(
      children: [
        if (_continuous)
          NotificationListener<ScrollNotification>(
            onNotification: _onContinuousScrollNotification,
            child: ScrollablePositionedList.separated(
              initialScrollIndex: ready.currentPage,
              itemCount: ready.totalPages,
              minCacheExtent: MediaQuery.sizeOf(context).height * 1.5,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _positionsListener,
              itemBuilder: (_, index) => _page(
                index,
                gesture: false,
                layout: ready.layoutFor(index),
                foreground: ready.currentPage == index || _isPageVisible(index),
              ),
              separatorBuilder: (_, _) => const SizedBox.shrink(),
            ),
          )
        else
          // A swipeable page view, deliberately NOT the prototype's in-place
          // dissolve (`saPgNext` / `saPgPrev`): a finger-following drag and a
          // cross-fade are mutually exclusive, and swiping to turn a page counts
          // for more than the animation does. `extended_image`'s page view is
          // what lets the drag coexist with pinch-zoom on the page itself.
          ExtendedImageGesturePageView.builder(
            controller: _pageController,
            scrollDirection: _readerMode == ReaderMode.vertical
                ? Axis.vertical
                : Axis.horizontal,
            reverse: _readerMode == ReaderMode.rtl,
            itemCount: ready.totalPages,
            itemBuilder: (_, index) =>
                _page(index, gesture: true, layout: ready.layoutFor(index)),
            onPageChanged: _session.moveTo,
          ),
        _gestureOverlay(ready),
        if (_chromeVisible) ...[
          _topBar(ready),
          if (finished) _endCard(ready) else _drawer(ready),
        ] else ...[
          if (showPageNumber && !finished) _handle(ready),
          _hairline(ready),
        ],
        if (ready.warning case final warning?)
          Positioned(
            top: _chromeVisible ? 96 : 24,
            left: 16,
            right: 16,
            child: Material(
              color: scheme.error,
              borderRadius: BorderRadius.circular(ZephyrRadius.small),
              child: Padding(
                padding: const EdgeInsets.all(ZephyrSpacing.sm),
                child: Text(
                  warning.message,
                  style: TextStyle(color: scheme.onError),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isPageVisible(int index) => _positionsListener.itemPositions.value.any(
    (item) =>
        item.index == index &&
        item.itemTrailingEdge > 0 &&
        item.itemLeadingEdge < 1,
  );

  void _scheduleCancelledPageRetry(int index) {
    if (!_continuous || !_isPageVisible(index)) return;
    _cancelledContinuousPages.add(index);
    if (_continuousScrollActive || _cancelledPageRetryTimer != null) return;
    _cancelledPageRetryTimer = Timer(const Duration(milliseconds: 160), () {
      _cancelledPageRetryTimer = null;
      _retryCancelledVisiblePages();
    });
  }

  void _retryCancelledVisiblePages() {
    final visible = _cancelledContinuousPages
        .where(_isPageVisible)
        .toList(growable: false);
    if (visible.isEmpty) return;
    _cancelledContinuousPages.removeAll(visible);
    if (mounted) setState(() {});
  }

  Widget _page(
    int index, {
    required bool gesture,
    required ReaderPageLayout layout,
    bool foreground = true,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final stableHeight = _continuous
        ? layout.displayHeight(mediaQuery.size.width)
        : null;
    final cacheWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio)
        .ceil()
        .clamp(1, 1 << 30)
        .toInt();
    final cacheHeight =
        ((stableHeight ?? mediaQuery.size.height) * mediaQuery.devicePixelRatio)
            .ceil()
            .clamp(1, 4096)
            .toInt();
    final pageContent = FutureBuilder<ReaderPage>(
      future: _session.loadPage(index, foreground: foreground),
      builder: (context, result) {
        if (result.hasError) {
          if (result.error is ReaderPageRequestCancelled) {
            _scheduleCancelledPageRetry(index);
            return _pageLoading(showProgress: false);
          }
          _markPageFailure(index, failed: true);
          return _pageRetry(index);
        }
        final page = result.data;
        if (page == null) {
          return _pageLoading(
            showProgress: foreground && !_continuousScrollActive,
          );
        }
        final imageProvider = ExtendedResizeImage(
          ExtendedMemoryImageProvider(page.encodedBytes),
          width: cacheWidth,
          height: cacheHeight,
          policy: ResizeImagePolicy.fit,
        );
        final image = ExtendedImage(
          image: imageProvider,
          width: _continuous ? double.infinity : null,
          height: _continuous ? double.infinity : null,
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
        return image;
      },
    );
    if (!_continuous) {
      return KeyedSubtree(key: Key('reader-page-$index'), child: pageContent);
    }
    return SizedBox(
      key: Key('reader-page-$index'),
      width: double.infinity,
      height: stableHeight,
      child: pageContent,
    );
  }

  Widget _pageLoading({bool showProgress = true}) => SizedBox(
    width: double.infinity,
    height: _continuous ? double.infinity : MediaQuery.sizeOf(context).height,
    child: showProgress
        ? const Center(child: CircularProgressIndicator())
        : const SizedBox.shrink(),
  );

  Widget _pageRetry(int index, {Future<bool> Function()? beforeRetry}) {
    return SizedBox(
      width: double.infinity,
      height: _continuous ? double.infinity : MediaQuery.sizeOf(context).height,
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

  /// Page-turn and chrome-toggle zones. They stay live while the chrome is
  /// showing, so a tap outside the drawer collapses it again; the chrome's own
  /// surfaces absorb the taps that land on them.
  Widget _gestureOverlay(ReaderReady ready) => IgnorePointer(
    ignoring: _failedPages.contains(ready.currentPage),
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
            onTap: _toggleChrome,
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

  /// Centre tap: reveal the chrome, or collapse it into the immersive state.
  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
  }

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

  /// `N / M`, one-based and spaced. The top bar zero-pads to three digits
  /// (`.sa-read-count`); the drawer and the handle do not.
  String _pageCounter(ReaderReady ready, {bool padded = false}) {
    final current = '${ready.currentPage + 1}';
    return '${padded ? current.padLeft(3, '0') : current} / ${ready.totalPages}';
  }

  /// Top bar: back, file name, page counter, over a scrim that fades into the
  /// page (the prototype's `.sa-read-top`).
  Widget _topBar(ReaderReady ready) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _Entrance(
        dy: -8,
        duration: const Duration(milliseconds: 280),
        child: GestureDetector(
          // Opaque so taps land here instead of the page-turn zones underneath.
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface.withValues(alpha: ZephyrSurfaces.scrimAlpha),
                  scheme.surface.withValues(alpha: 0.6),
                  scheme.surface.withValues(alpha: 0),
                ],
                stops: const [0, 0.68, 1],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(ZephyrSpacing.md),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: context.pop,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        baseName(widget.filePath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      _pageCounter(ready, padded: true),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 11,
                        letterSpacing: 0.66,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bottom drawer: grip, oversized page number, slider, the five reader modes
  /// as a segmented control, and the tool row (the prototype's `.sa-drawer`).
  Widget _drawer(ReaderReady ready) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Positioned(
      left: 14,
      right: 14,
      bottom: 14,
      child: _Entrance(
        dy: 14,
        duration: const Duration(milliseconds: 320),
        child: GestureDetector(
          // Opaque so slider and tool taps never reach the page-turn zones.
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Container(
            key: const Key('reader-toolbar'),
            padding: const EdgeInsets.fromLTRB(
              ZephyrSpacing.lg,
              ZephyrSpacing.sm,
              ZephyrSpacing.lg,
              ZephyrSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(
                alpha: ZephyrSurfaces.paneAlpha,
              ),
              borderRadius: BorderRadius.circular(ZephyrRadius.panel),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.62),
                  blurRadius: 50,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 2,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(ZephyrRadius.hairline),
                  ),
                ),
                // Drawer rhythm: the drawer is one control composed of four parts
                // (page number, slider, segmented track, tool row), so these gaps
                // are tuned by visual weight and stay off the spacing ladder.
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${ready.currentPage + 1}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    // Drawer rhythm — off the ladder.
                    const SizedBox(width: 9),
                    Text(
                      '/ ${ready.totalPages}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        letterSpacing: 0.77,
                      ),
                    ),
                  ],
                ),
                // Drawer rhythm — off the ladder.
                const SizedBox(height: 9),
                Slider(
                  value: ready.currentPage.toDouble(),
                  min: 0,
                  max: (ready.totalPages - 1).toDouble(),
                  divisions: ready.totalPages > 1 ? ready.totalPages - 1 : null,
                  label: '第 ${ready.currentPage + 1} 页',
                  onChanged: (value) => _goTo(value.round(), ready),
                ),
                // Drawer rhythm — off the ladder.
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(ZephyrSpacing.xs),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(ZephyrRadius.segment),
                  ),
                  child: Row(
                    children: [
                      for (final mode in ReaderMode.values)
                        Expanded(child: _modeSegment(mode, theme, scheme)),
                    ],
                  ),
                ),
                // Drawer rhythm — off the ladder.
                const SizedBox(height: 6),
                SignalBuilder(
                  builder: (context) {
                    final bookmarked = _bookmarks.pages.value.contains(
                      ready.currentPage,
                    );
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _drawerTool(
                          key: const Key('reader-bookmark'),
                          label: bookmarked ? '已书签' : '书签',
                          icon: bookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_add_outlined,
                          active: bookmarked,
                          onTap: () => _toggleBookmark(ready.currentPage),
                        ),
                        _drawerTool(
                          key: const Key('reader-first-page'),
                          label: '回到第一页',
                          icon: Icons.restart_alt,
                          onTap: () => _goTo(0, ready),
                        ),
                        _drawerTool(
                          key: const Key('reader-collapse'),
                          label: '收起',
                          icon: Icons.keyboard_arrow_down,
                          onTap: _toggleChrome,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeSegment(ReaderMode mode, ThemeData theme, ColorScheme scheme) {
    final selected = _readerMode == mode;
    return GestureDetector(
      key: Key('reader-mode-${mode.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _applyMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: ZephyrSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : null,
          borderRadius: BorderRadius.circular(ZephyrRadius.segment - 2),
        ),
        child: Text(
          mode.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _drawerTool({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      key: key,
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: active ? scheme.primary : scheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(
          horizontal: ZephyrSpacing.md,
          vertical: ZephyrSpacing.sm,
        ),
      ),
    );
  }

  /// Collapsed state: a floating page-number pill, plus the progress hairline
  /// pinned to the screen's bottom edge.
  Widget _handle(ReaderReady ready) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Positioned(
      bottom: 22,
      left: 0,
      right: 0,
      child: _Entrance(
        dy: 10,
        duration: const Duration(milliseconds: 300),
        child: Center(
          child: GestureDetector(
            key: const Key('reader-page-handle'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggleChrome,
            child: Container(
              height: 34,
              padding: const EdgeInsets.fromLTRB(
                ZephyrSpacing.md,
                0,
                ZephyrSpacing.lg,
                0,
              ),
              decoration: ShapeDecoration(
                color: scheme.surfaceContainerHighest.withValues(
                  alpha: ZephyrSurfaces.paneAlpha,
                ),
                // A pill: the radius is the half-height, so no literal here.
                shape: StadiumBorder(
                  side: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.34),
                  ),
                ),
                shadows: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.6),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: ZephyrSpacing.sm),
                  Text(
                    '${ready.currentPage + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 11.5,
                      letterSpacing: 0.69,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: ZephyrSpacing.sm),
                  Text(
                    '/ ${ready.totalPages}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      letterSpacing: 0.53,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `.sa-end`: on the last page the drawer gives way to a closing card, so the
  /// book finishes in place instead of dumping the reader back to the shelf.
  Widget _endCard(ReaderReady ready) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            ZephyrSpacing.xl,
            ZephyrSpacing.xxl,
            ZephyrSpacing.xl,
            ZephyrSpacing.xl,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                scheme.surface.withValues(alpha: ZephyrSurfaces.scrimAlpha),
                scheme.surface.withValues(alpha: 0.2),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '读完了',
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: 21),
              ),
              const SizedBox(height: ZephyrSpacing.md),
              Text(
                '「${baseName(widget.filePath)}」共 '
                '${ready.totalPages} 页。Zephyr 不会自动打开下一本，'
                '阅读进度与书签都留在原处。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12.5,
                  height: 1.85,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ZephyrSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: context.pop,
                      child: const Text('返回书架'),
                    ),
                  ),
                  const SizedBox(width: ZephyrSpacing.md),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _goTo(0, ready),
                      child: const Text('从头阅读'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hairline(ReaderReady ready) {
    final progress = ((ready.currentPage + 1) / ready.totalPages).clamp(
      0.0,
      1.0,
    );
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ProgressHairline(
        key: const Key('reader-progress-hairline'),
        value: progress,
      ),
    );
  }

  /// Switching mode rebuilds the page controller so the new layout starts on
  /// the current page; the ReaderSession is deliberately preserved.
  ///
  /// The change is scoped to this reading session. Persisting it here would
  /// silently rewrite the global default, so a one-off "read this webtoon as a
  /// webtoon" would change how *every* comic opens. The default is edited in
  /// Settings; this control only affects what is on screen now.
  void _applyMode(ReaderMode mode) {
    if (mode == _readerMode) return;
    final currentPage = (_session.snapshot.value as ReaderReady).currentPage;
    final previousController = _pageController;
    _pageController = ExtendedPageController(
      initialPage: currentPage,
      shouldIgnorePointerWhenScrolling: false,
    );
    setState(() {
      _readerMode = mode;
      _continuousScrollActive = false;
      _lastContinuousPage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => previousController?.dispose(),
    );
  }

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

  Color _backgroundColor(BuildContext context, ReaderBackground background) =>
      switch (background) {
        ReaderBackground.black => ZephyrReaderBackground.black,
        ReaderBackground.dark => ZephyrReaderBackground.dark,
        ReaderBackground.paper => ZephyrReaderBackground.paper,
        ReaderBackground.system => Theme.of(context).scaffoldBackgroundColor,
      };
}

/// The prototype's chrome entrances: `.sa-read-top` drops in, the drawer and the
/// handle rise. Each one replays on its own because the widget leaves the tree
/// when the chrome collapses.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.child,
    required this.dy,
    required this.duration,
  });

  final Widget child;
  final double dy;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: duration,
    curve: Curves.easeOut,
    builder: (context, t, child) => Opacity(
      opacity: 0.6 + 0.4 * t,
      child: Transform.translate(offset: Offset(0, dy * (1 - t)), child: child),
    ),
    child: child,
  );
}

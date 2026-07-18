import 'dart:io';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../models/reader_mode.dart';
import '../../signals/app_signals.dart';
import 'image_view_horizontal.dart';
import 'image_view_vertical.dart';

class ComicReaderScreen extends StatefulWidget {
  final String filePath;
  const ComicReaderScreen({super.key, required this.filePath});

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen>
    with TickerProviderStateMixin {
  // ponytail: demo data - real data comes from Rust FRB
  final int _totalPages = 30;
  int _currentPage = 0;
  ReaderMode _readerMode = ReaderMode.vertical;
  bool _isToolbarVisible = false;
  final bool _showPageNumbers = true;

  late final ItemScrollController _itemScrollController;
  late final ExtendedPageController _extPageController;

  @override
  void initState() {
    super.initState();
    _itemScrollController = ItemScrollController();
    _extPageController = ExtendedPageController(
      initialPage: _currentPage,
      shouldIgnorePointerWhenScrolling: false,
    );
    _readerMode = readerMode.value;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  @override
  void dispose() {
    _extPageController.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  bool get _isContinuous =>
      _readerMode == ReaderMode.verticalContinuous ||
      _readerMode == ReaderMode.webtoon;

  Axis get _scrollAxis =>
      _readerMode == ReaderMode.vertical ? Axis.vertical : Axis.horizontal;

  bool get _isReversed => _readerMode == ReaderMode.rtl;

  String _cachePath(int page) {
    final dir = Directory('${Directory.systemTemp.path}/zephyr_cache');
    dir.createSync(recursive: true);
    return '${dir.path}/page_$page.jpg';
  }

  void _goToPage(int page) {
    final clamped = page.clamp(0, _totalPages - 1);
    if (_isContinuous) {
      _itemScrollController.scrollTo(
        index: clamped,
        duration: const Duration(milliseconds: 150),
        curve: Curves.ease,
      );
    } else {
      _extPageController.animateToPage(
        clamped,
        duration: const Duration(milliseconds: 150),
        curve: Curves.ease,
      );
    }
    _currentPage = clamped;
  }

  void _toggleToolbar() {
    setState(() => _isToolbarVisible = !_isToolbarVisible);
    if (_isToolbarVisible) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildContent(),
            _buildGestureOverlay(),
            _buildToolbar(),
            _buildPageNumber(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isContinuous) {
      return ScrollablePositionedList.separated(
        physics: const ClampingScrollPhysics(),
        minCacheExtent: 8 * MediaQuery.of(context).size.height,
        initialScrollIndex: _currentPage,
        itemCount: _totalPages,
        itemScrollController: _itemScrollController,
        itemBuilder: (context, index) {
          return GestureDetector(
            onDoubleTapDown: (details) {},
            child: ImageViewVertical(
              cachePath: _cachePath(index),
              chapter: '',
              index: index,
              length: _totalPages,
            ),
          );
        },
        separatorBuilder: (_, _) => Divider(
          color: Colors.black,
          height: _readerMode == ReaderMode.webtoon ? 0 : 6,
        ),
      );
    }

    return ExtendedImageGesturePageView.builder(
      controller: _extPageController,
      scrollDirection: _scrollAxis,
      reverse: _isReversed,
      physics: const ClampingScrollPhysics(),
      canScrollPage: (details) {
        return details == null || !(details.totalScale! > 1.0);
      },
      itemBuilder: (context, index) {
        return ImageViewHorizontal(
          cachePath: _cachePath(index),
          chapter: '',
          index: index,
          length: _totalPages,
          loadStateChanged: (state) => _buildLoadState(state),
          onDoubleTap: (state) {
            final begin = state.gestureDetails?.totalScale ?? 1.0;
            state.handleDoubleTap(
              scale: begin == 1.0 ? 2.0 : 1.0,
              doubleTapPosition: state.pointerDownPosition,
            );
          },
          initGestureConfigHandler: (state) {
            return GestureConfig(
              inertialSpeed: 200,
              inPageView: true,
              initialScale: 1.0,
              maxScale: 8,
              animationMaxScale: 8,
              initialAlignment: InitialAlignment.center,
              cacheGesture: false,
              hitTestBehavior: HitTestBehavior.translucent,
            );
          },
        );
      },
      itemCount: _totalPages,
      onPageChanged: (index) {
        _currentPage = index;
        if (mounted) setState(() {});
      },
    );
  }

  Widget? _buildLoadState(ExtendedImageState state) {
    if (state.extendedImageLoadState == LoadState.loading) {
      return Container(
        color: Colors.black,
        height: MediaQuery.of(context).size.height * 0.8,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (state.extendedImageLoadState == LoadState.failed) {
      return Container(
        color: Colors.black,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, color: Colors.grey, size: 64),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => state.reLoadImage(),
              child: const Icon(Icons.replay_outlined, size: 30),
            ),
          ],
        ),
      );
    }
    return null;
  }

  Widget _buildGestureOverlay() {
    return IgnorePointer(
      ignoring: _isToolbarVisible,
      child: Column(
        children: [
          // Top region (prev page)
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _goToPage(_currentPage - 1),
            ),
          ),
          // Center region (toggle toolbar)
          Expanded(
            flex: 5,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleToolbar,
            ),
          ),
          // Bottom region (next page)
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _goToPage(_currentPage + 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.ease,
        height: _isToolbarVisible ? 90 : 0,
        color: Colors.black.withValues(alpha: 0.9),
        child: _isToolbarVisible
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.filePath.split('/').last,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '第 ${_currentPage + 1} 页 / 共 $_totalPages 页',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                actions: [
                  PopupMenuButton<ReaderMode>(
                    color: Colors.black,
                    icon: const Icon(Icons.view_carousel_outlined,
                        color: Colors.white),
                    onSelected: (mode) {
                      _readerMode = mode;
                      setReaderMode(mode);
                      setState(() {});
                    },
                    itemBuilder: (_) => [
                      for (final mode in ReaderMode.values)
                        PopupMenuItem(
                          value: mode,
                          child: Row(
                            children: [
                              Icon(
                                Icons.check,
                                color: _readerMode == mode
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                mode.label,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildPageNumber() {
    if (_showPageNumbers && !_isToolbarVisible) {
      return Positioned(
        bottom: 24,
        left: 0,
        right: 0,
        child: Text(
          '${_currentPage + 1} / $_totalPages',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            shadows: [
              Shadow(offset: Offset(0, 0), blurRadius: 10),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

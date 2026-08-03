import 'dart:io';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

class ImageViewHorizontal extends StatefulWidget {
  final int length;
  final String cachePath;
  final int index;
  final String chapter;
  final Widget? Function(ExtendedImageState state) loadStateChanged;
  final Function(ExtendedImageGestureState state) onDoubleTap;
  final GestureConfig Function(ExtendedImageState state)
  initGestureConfigHandler;

  const ImageViewHorizontal({
    super.key,
    required this.cachePath,
    required this.chapter,
    required this.index,
    required this.length,
    required this.loadStateChanged,
    required this.onDoubleTap,
    required this.initGestureConfigHandler,
  });

  @override
  State<ImageViewHorizontal> createState() => _ImageViewHorizontalState();
}

class _ImageViewHorizontalState extends State<ImageViewHorizontal>
    with AutomaticKeepAliveClientMixin<ImageViewHorizontal> {
  bool _isLoading = true;
  bool _hasCache = false;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  void _checkCache() {
    final file = File(widget.cachePath);
    _hasCache = file.existsSync();
    _isLoading = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasCache) {
      return Container(
        color: Colors.black,
        height: MediaQuery.of(context).size.height * 0.8,
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.grey, size: 64),
        ),
      );
    }

    // Use loadStateChanged from parent to handle loading/error states
    return ExtendedImage.file(
      File(widget.cachePath),
      mode: ExtendedImageMode.gesture,
      fit: BoxFit.contain,
      clearMemoryCacheWhenDispose: true,
      loadStateChanged: widget.loadStateChanged,
      initGestureConfigHandler: widget.initGestureConfigHandler,
      onDoubleTap: widget.onDoubleTap,
    );
  }

  @override
  bool get wantKeepAlive => true;
}

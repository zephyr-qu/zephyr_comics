import 'dart:io';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

class ImageViewVertical extends StatefulWidget {
  final int length;
  final String cachePath;
  final int index;
  final String chapter;

  const ImageViewVertical({
    super.key,
    required this.cachePath,
    required this.chapter,
    required this.index,
    required this.length,
  });

  @override
  State<ImageViewVertical> createState() => _ImageViewVerticalState();
}

class _ImageViewVerticalState extends State<ImageViewVertical>
    with AutomaticKeepAliveClientMixin<ImageViewVertical> {
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
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.index == 0)
            SizedBox(height: MediaQuery.of(context).padding.top),
          if (_isLoading)
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasCache)
            ExtendedImage.file(
              File(widget.cachePath),
              fit: BoxFit.contain,
              clearMemoryCacheWhenDispose: true,
            )
          else
            const SizedBox(
              height: 200,
              child: Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          if (widget.index + 1 == widget.length)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    '${widget.chapter} 已看完',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Icon(Icons.check_circle_outline, color: Colors.white),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

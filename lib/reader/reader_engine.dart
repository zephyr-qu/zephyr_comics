import 'dart:typed_data';

enum ReaderFailureKind {
  fileMissing,
  permissionDenied,
  unsupportedFormat,
  emptyComic,
  pageOutOfRange,
  pageDecode,
  persistence,
  unexpected,
}

final class ReaderFailure implements Exception {
  const ReaderFailure(this.kind, this.message, [this.cause]);

  final ReaderFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class ReaderBook {
  const ReaderBook({required this.totalPages, this.pageLayouts = const []});
  final int totalPages;
  final List<ReaderPageLayout> pageLayouts;
}

final class ReaderPageLayout {
  const ReaderPageLayout({required this.width, required this.height});

  static const fallback = ReaderPageLayout(width: 10, height: 14);

  final int width;
  final int height;

  double displayHeight(double displayWidth) {
    if (width <= 0 || height <= 0) {
      return displayWidth * fallback.height / fallback.width;
    }
    return displayWidth * height / width;
  }
}

final class ReaderPage {
  const ReaderPage({required this.index, required this.encodedBytes});
  final int index;
  final Uint8List encodedBytes;
}

abstract interface class ReaderEngine {
  Future<ReaderBook> open(String filePath);

  /// Returns the archive entry's original encoded image bytes.
  ///
  /// [maxWidth] and [maxHeight] describe the intended display bound. Native
  /// adapters may use them when the source format requires transcoding; the
  /// normal CBZ path leaves JPEG, PNG, and WebP bytes untouched.
  Future<Uint8List> loadPageEncoded(
    String filePath,
    int pageIndex, {
    required int maxWidth,
    required int maxHeight,
  });
}

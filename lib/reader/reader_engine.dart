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
  const ReaderBook({required this.totalPages});
  final int totalPages;
}

final class ReaderPage {
  const ReaderPage({required this.index, required this.encodedBytes});
  final int index;
  final Uint8List encodedBytes;
}

final class ReaderProgress {
  const ReaderProgress({required this.filePath, required this.pageIndex});
  final String filePath;
  final int pageIndex;
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
  Future<ReaderProgress?> readProgress(String filePath);
  Future<void> writeProgress(ReaderProgress progress);
}

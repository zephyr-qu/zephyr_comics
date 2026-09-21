import 'dart:typed_data';

import '../src/rust/api/reader.dart' as rust;
import 'reader_engine.dart';

final class FrbReaderEngine implements ReaderEngine {
  @override
  Future<ReaderBook> open(String filePath) async {
    try {
      final info = rust.getComicInfo(filePath: filePath);
      if (info.totalImages == BigInt.zero) {
        throw const ReaderFailure(ReaderFailureKind.emptyComic, '漫画文件中没有页面');
      }
      final totalPages = info.totalImages.toInt();
      final nativeLayouts = await rust.getComicPageDimensions(
        filePath: filePath,
      );
      return ReaderBook(
        totalPages: totalPages,
        pageLayouts: [
          for (var index = 0; index < totalPages; index++)
            if (index < nativeLayouts.length &&
                nativeLayouts[index].width > 0 &&
                nativeLayouts[index].height > 0)
              ReaderPageLayout(
                width: nativeLayouts[index].width,
                height: nativeLayouts[index].height,
              )
            else
              ReaderPageLayout.fallback,
        ],
      );
    } on ReaderFailure {
      rethrow;
    } catch (error) {
      throw _mapFailure(error, ReaderFailureKind.unsupportedFormat);
    }
  }

  @override
  Future<Uint8List> loadPageEncoded(
    String filePath,
    int pageIndex, {
    required int maxWidth,
    required int maxHeight,
  }) async {
    try {
      return await rust.getPageImageEncoded(
        filePath: filePath,
        pageIndex: pageIndex,
      );
    } catch (error) {
      throw _mapFailure(error, ReaderFailureKind.pageDecode);
    }
  }

  ReaderFailure _mapFailure(Object error, ReaderFailureKind fallback) {
    if (error is ReaderFailure) return error;
    // FRB currently exposes a single exception boundary. Keep classification
    // here and use operation context rather than making Widgets parse messages.
    return ReaderFailure(fallback, switch (fallback) {
      ReaderFailureKind.unsupportedFormat => '无法打开漫画文件',
      ReaderFailureKind.pageDecode => '页面解码失败',
      _ => '阅读器发生未知错误',
    }, error);
  }
}

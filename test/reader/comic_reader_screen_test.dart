import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:zephyr_comics/models/reader_mode.dart';
import 'package:zephyr_comics/reading/reading_records.dart';
import 'package:zephyr_comics/reader/reader_engine.dart';
import 'package:zephyr_comics/signals/app_signals.dart';
import 'package:zephyr_comics/views/reader/comic_reader_screen.dart';

final class WidgetReaderEngine implements ReaderEngine {
  WidgetReaderEngine({
    this.openGate,
    this.failFirstOpen = false,
    this.failFirstDecode = false,
  });

  final Completer<void>? openGate;
  final bool failFirstOpen;
  final bool failFirstDecode;
  int openCalls = 0;
  int pageLoads = 0;
  final List<int> loads = [];

  static final Uint8List png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mNk+M/wHwAF/gL+X2NDWQAAAABJRU5ErkJggg==',
  );

  @override
  Future<ReaderBook> open(String filePath) async {
    openCalls++;
    await openGate?.future;
    if (failFirstOpen && openCalls == 1) {
      throw const ReaderFailure(
        ReaderFailureKind.unsupportedFormat,
        '无法打开漫画文件',
      );
    }
    return const ReaderBook(totalPages: 3);
  }

  @override
  Future<Uint8List> loadPageEncoded(
    String filePath,
    int pageIndex, {
    required int maxWidth,
    required int maxHeight,
  }) async {
    pageLoads++;
    loads.add(pageIndex);
    if (failFirstDecode && pageLoads == 1) return Uint8List.fromList([0]);
    return png;
  }
}

Widget _app(ReaderEngine engine, {ReadingRecords? records}) => MaterialApp(
  home: ComicReaderScreen(
    filePath: 'test.cbz',
    readerEngine: engine,
    records:
        records ?? ReadingRecords(adapter: InMemoryReadingRecordsAdapter()),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    readerMode.value = ReaderMode.vertical;
  });

  testWidgets('continuous mode builds three viewports ahead', (tester) async {
    readerMode.value = ReaderMode.verticalContinuous;
    await tester.pumpWidget(_app(WidgetReaderEngine()));
    await tester.pump();

    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(
      list.minCacheExtent,
      3 * tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
  });

  testWidgets('shows opening then the restored first page', (tester) async {
    final gate = Completer<void>();
    final engine = WidgetReaderEngine(openGate: gate);
    await tester.pumpWidget(_app(engine));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    final image = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    final provider = image.image as ExtendedResizeImage;
    expect(provider.width, tester.view.physicalSize.width.ceil());
    expect(provider.height, tester.view.physicalSize.height.ceil());
    expect(provider.policy, ResizeImagePolicy.fit);
  });

  testWidgets(
    'fatal error exposes retry without parsing infrastructure errors',
    (tester) async {
      final engine = WidgetReaderEngine(failFirstOpen: true);
      await tester.pumpWidget(_app(engine));
      await tester.pump();
      expect(find.text('无法打开漫画文件'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader-fatal-retry')));
      await tester.pump();
      await tester.pump();
      expect(find.text('1 / 3'), findsOneWidget);
      expect(engine.openCalls, 2);
    },
  );

  testWidgets('Flutter decode failure reloads the page bytes', (tester) async {
    final engine = WidgetReaderEngine(failFirstDecode: true);
    await tester.pumpWidget(_app(engine));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader-page-retry-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(engine.loads.where((index) => index == 0), hasLength(2));
    expect(find.byType(ExtendedImage), findsOneWidget);
  });

  testWidgets('mode switch preserves session and restored current page', (
    tester,
  ) async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());
    await records.recordProgress(
      filePath: 'test.cbz',
      pageIndex: 1,
      totalPages: 3,
    );
    final engine = WidgetReaderEngine();
    await tester.pumpWidget(_app(engine, records: records));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('reader-mode-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(ReaderMode.rtl.label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(engine.openCalls, 1);
    expect(find.textContaining('2/3'), findsOneWidget);
  });
}

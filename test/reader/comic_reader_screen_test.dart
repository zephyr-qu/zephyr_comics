import 'dart:async';
import 'dart:convert';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:zephyr_comics/models/reader_mode.dart';
import 'package:zephyr_comics/models/settings_options.dart';
import 'package:zephyr_comics/reading/reading_records.dart';
import 'package:zephyr_comics/reader/reader_engine.dart';
import 'package:zephyr_comics/reader/reader_volume_keys.dart';
import 'package:zephyr_comics/signals/app_signals.dart';
import 'package:zephyr_comics/theme/zephyr_theme.dart';
import 'package:zephyr_comics/views/reader/comic_reader_screen.dart';

final class WidgetReaderEngine implements ReaderEngine {
  WidgetReaderEngine({
    this.openGate,
    this.pageGates = const {},
    this.totalPages = 3,
    this.pageLayouts,
    this.failFirstOpen = false,
    this.failFirstDecode = false,
  });

  final Completer<void>? openGate;
  final Map<int, Completer<void>> pageGates;
  final int totalPages;
  final List<ReaderPageLayout>? pageLayouts;
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
    return ReaderBook(
      totalPages: totalPages,
      pageLayouts:
          pageLayouts ??
          List<ReaderPageLayout>.filled(
            totalPages,
            const ReaderPageLayout(width: 1, height: 1),
          ),
    );
  }

  @override
  Future<Uint8List> loadPageEncoded(
    String filePath,
    int pageIndex, {
    required int maxWidth,
    required int maxHeight,
  }) async {
    pageLoads++;
    final loadNumber = pageLoads;
    loads.add(pageIndex);
    await pageGates[pageIndex]?.future;
    if (failFirstDecode && loadNumber == 1) return Uint8List.fromList([0]);
    return png;
  }
}

Widget _app(
  ReaderEngine engine, {
  ReadingRecords? records,
  ReaderVolumeKeys? volumeKeys,
}) => MaterialApp(
  home: ComicReaderScreen(
    filePath: 'test.cbz',
    readerEngine: engine,
    records:
        records ?? ReadingRecords(adapter: InMemoryReadingRecordsAdapter()),
    volumeKeys: volumeKeys,
  ),
);

Widget _themedApp(
  ReaderEngine engine, {
  ReadingRecords? records,
  ReaderVolumeKeys? volumeKeys,
}) => SignalBuilder(
  builder: (context) {
    final preference = settingsSnapshot.value.themePreference;
    return MaterialApp(
      theme: zephyrLightTheme(),
      darkTheme: zephyrDarkTheme(),
      themeMode: switch (preference) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      },
      home: ComicReaderScreen(
        filePath: 'test.cbz',
        readerEngine: engine,
        records:
            records ?? ReadingRecords(adapter: InMemoryReadingRecordsAdapter()),
        volumeKeys: volumeKeys,
      ),
    );
  },
);

void main() {
  const volumeKeysChannel = MethodChannel('com.zephyr.comics/volume_keys');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeKeysChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeKeysChannel, null);
  });

  testWidgets('continuous mode keeps a focused cache window', (tester) async {
    await setReaderMode(ReaderMode.verticalContinuous);
    await tester.pumpWidget(_app(WidgetReaderEngine()));
    await tester.pump();

    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(
      list.minCacheExtent,
      1.5 * tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
  });

  testWidgets(
    'continuous page height stays stable when image finishes loading',
    (tester) async {
      await setReaderMode(ReaderMode.verticalContinuous);
      final gate = Completer<void>();
      final engine = WidgetReaderEngine(pageGates: {0: gate}, totalPages: 1);
      await tester.pumpWidget(_app(engine));
      await tester.pump();

      final page = find.byKey(const Key('reader-page-0'));
      final loadingHeight = tester.getSize(page).height;
      expect(
        loadingHeight,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.getSize(page).height, loadingHeight);
    },
  );

  testWidgets('shows opening then the restored first page', (tester) async {
    final gate = Completer<void>();
    final engine = WidgetReaderEngine(openGate: gate);
    await tester.pumpWidget(_app(engine));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump();
    // `.sa-handle-n` + `.sa-handle-s`: the counter is one pill but two weights.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('/ 3'), findsOneWidget);
    final image = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    final provider = image.image as ExtendedResizeImage;
    expect(provider.width, tester.view.physicalSize.width.ceil());
    expect(provider.height, tester.view.physicalSize.height.ceil());
    expect(provider.policy, ResizeImagePolicy.fit);
  });

  testWidgets('reader theme and system background update while open', (
    tester,
  ) async {
    await setReaderBackground(ReaderBackground.system);
    await setThemePreference(ThemePreference.light);
    // Two pages, so the first one is not also the last: the drawer only exists
    // while there is somewhere left to read.
    await tester.pumpWidget(_themedApp(WidgetReaderEngine(totalPages: 2)));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump(const Duration(milliseconds: 300));

    final lightTheme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      lightTheme.scaffoldBackgroundColor,
    );
    // The drawer's pane colour must be derived from the active ThemeData, not
    // hard-coded — this is the property the reader-theme task guards.
    expect(
      (tester
                  .widget<Container>(find.byKey(const Key('reader-toolbar')))
                  .decoration
              as BoxDecoration)
          .color,
      lightTheme.colorScheme.surfaceContainerHighest.withValues(
        alpha: ZephyrSurfaces.paneAlpha,
      ),
    );

    await setThemePreference(ThemePreference.dark);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final darkTheme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      darkTheme.scaffoldBackgroundColor,
    );
    expect(
      (tester
                  .widget<Container>(find.byKey(const Key('reader-toolbar')))
                  .decoration
              as BoxDecoration)
          .color,
      darkTheme.colorScheme.surfaceContainerHighest.withValues(
        alpha: ZephyrSurfaces.paneAlpha,
      ),
    );
  });

  testWidgets('reader background changes are applied while open', (
    tester,
  ) async {
    await setReaderBackground(ReaderBackground.black);
    await tester.pumpWidget(_app(WidgetReaderEngine(totalPages: 1)));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.black,
    );

    await setReaderBackground(ReaderBackground.paper);
    await tester.pump();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      ZephyrReaderBackground.paper,
    );
  });

  testWidgets('volume key events page while the reader is open', (
    tester,
  ) async {
    final volumeKeys = FakeReaderVolumeKeys();
    await setVolumeKeyPaging(true);
    await tester.pumpWidget(_app(WidgetReaderEngine(), volumeKeys: volumeKeys));
    await tester.pump();
    await tester.pump();

    volumeKeys.press(next: true);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('2'), findsOneWidget);
    expect(find.text('/ 3'), findsOneWidget);
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
      expect(find.text('1'), findsOneWidget);
      expect(find.text('/ 3'), findsOneWidget);
      expect(engine.openCalls, 2);
    },
  );

  testWidgets('Flutter decode failure reloads the page bytes', (tester) async {
    final engine = WidgetReaderEngine(failFirstDecode: true);
    await tester.pumpWidget(_app(engine));
    await tester.pump();
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('reader-page-retry-0')), findsOneWidget);

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
    // Collapsed: the handle splits the counter into the page and `/ total`.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('/ 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Reader modes are a segmented control now: every mode is directly tappable
    // instead of living behind a popup menu.
    await tester.tap(find.byKey(const Key('reader-mode-rtl')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(engine.openCalls, 1);
    // With the chrome open the top bar carries the zero-padded counter.
    expect(find.text('002 / 3'), findsOneWidget);
  });

  testWidgets('switching mode in the reader does not rewrite the default', (
    tester,
  ) async {
    final engine = WidgetReaderEngine(
      totalPages: 3,
      pageGates: {0: Completer<void>()},
    );
    await tester.pumpWidget(_app(engine));
    await tester.pump();
    await tester.pump();

    final before = settingsSnapshot.value.readerMode;

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reader-mode-rtl')));
    await tester.pump();

    // The mode control is session-scoped. Persisting it would turn a per-comic
    // choice into a permanent change to how every comic opens.
    expect(settingsSnapshot.value.readerMode, before);
    expect(find.byType(ComicReaderScreen), findsOneWidget);
  });

  testWidgets('centre tap collapses the chrome and the handle restores it', (
    tester,
  ) async {
    // A page that never finishes loading keeps the gesture zones live: they are
    // deliberately stood down while the current page shows a decode failure, so
    // a failing page would otherwise mask the toggle.
    final engine = WidgetReaderEngine(
      totalPages: 3,
      pageGates: {0: Completer<void>()},
    );
    await tester.pumpWidget(_app(engine));
    await tester.pump();
    await tester.pump();

    // Collapsed is the immersive state: handle + progress hairline only.
    expect(find.byKey(const Key('reader-page-handle')), findsOneWidget);
    expect(find.byKey(const Key('reader-progress-hairline')), findsOneWidget);
    expect(find.byKey(const Key('reader-toolbar')), findsNothing);

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('reader-toolbar')), findsOneWidget);
    expect(find.byKey(const Key('reader-page-handle')), findsNothing);
    expect(find.byKey(const Key('reader-progress-hairline')), findsNothing);

    // Tapping the page centre again collapses it.
    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('reader-toolbar')), findsNothing);
    expect(find.byKey(const Key('reader-page-handle')), findsOneWidget);

    // The page-number handle brings it back.
    await tester.tap(find.byKey(const Key('reader-page-handle')));
    await tester.pump();
    expect(find.byKey(const Key('reader-toolbar')), findsOneWidget);
  });

  testWidgets('the drawer 收起 tool collapses the chrome', (tester) async {
    final engine = WidgetReaderEngine(
      totalPages: 3,
      pageGates: {0: Completer<void>()},
    );
    await tester.pumpWidget(_app(engine));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('reader-toolbar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-collapse')));
    await tester.pump();
    expect(find.byKey(const Key('reader-toolbar')), findsNothing);
    expect(find.byKey(const Key('reader-page-handle')), findsOneWidget);
  });

  testWidgets('back closes the open chrome instead of leaving the route', (
    tester,
  ) async {
    final engine = WidgetReaderEngine(
      totalPages: 3,
      pageGates: {0: Completer<void>()},
    );
    await tester.pumpWidget(_app(engine));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('reader-toolbar')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // PRD §7: the first back closes the toolbar; the route stays.
    expect(find.byKey(const Key('reader-toolbar')), findsNothing);
    expect(find.byType(ComicReaderScreen), findsOneWidget);
  });

  testWidgets('the last page closes the book in place', (tester) async {
    final records = ReadingRecords(adapter: InMemoryReadingRecordsAdapter());
    await records.recordProgress(
      filePath: 'test.cbz',
      pageIndex: 2,
      totalPages: 3,
    );
    await tester.pumpWidget(
      _app(WidgetReaderEngine(totalPages: 3), records: records),
    );
    await tester.pump();
    await tester.pump();

    // Collapsed on the last page: the handle retires, the hairline stays.
    expect(find.byKey(const Key('reader-page-handle')), findsNothing);
    expect(find.byKey(const Key('reader-progress-hairline')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // `.sa-end`: the drawer gives way to the closing card.
    expect(find.byKey(const Key('reader-toolbar')), findsNothing);
    expect(find.text('读完了'), findsOneWidget);
    expect(find.text('返回书架'), findsOneWidget);
    expect(find.text('从头阅读'), findsOneWidget);
  });

  testWidgets('the drawer clears the navigation bar when the chrome opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    // Opening the chrome restores the system bars, so the drawer has to sit
    // above the navigation inset instead of under the gesture pill.
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(WidgetReaderEngine()));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-toolbar-toggle')));
    await tester.pump();
    // Let the 320ms entrance settle so the translate is back to zero.
    await tester.pump(const Duration(milliseconds: 400));

    final drawerBottom = tester
        .getBottomLeft(find.byKey(const Key('reader-toolbar')))
        .dy;

    // 600 tall, less the drawer's 14px inset and the 48px navigation inset.
    expect(drawerBottom, closeTo(600 - 14 - 48, 0.5));
  });
}

final class FakeReaderVolumeKeys implements ReaderVolumeKeys {
  void Function(bool next)? _onPressed;

  @override
  void start(void Function(bool next) onPressed) => _onPressed = onPressed;

  @override
  void stop() => _onPressed = null;

  void press({required bool next}) => _onPressed?.call(next);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/cache/derived_cache.dart';
import 'package:zephyr_comics/models/settings_options.dart';
import 'package:zephyr_comics/signals/app_signals.dart';
import 'package:zephyr_comics/theme/zephyr_theme.dart';
import 'package:zephyr_comics/views/settings/settings_screen.dart';

void main() {
  const storageChannel = MethodChannel('com.zephyr.comics/storage');

  setUp(() {
    settings.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
          if (call.method == 'isAllFilesAccessGranted') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  testWidgets('settings explains all-files access before choosing a root', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.tap(find.text('漫画目录'));
    await tester.pumpAndSettle();

    expect(find.text('需要访问漫画文件'), findsOneWidget);
    expect(find.text('去授权'), findsOneWidget);
    expect(find.text('暂不授权'), findsOneWidget);
  });

  testWidgets('settings exposes reader behavior controls', (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('阅读时保持屏幕常亮'), findsOneWidget);
    expect(find.text('使用音量键翻页'), findsOneWidget);
  });

  testWidgets('the page carries the prototype sections in order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    // No app bar: the page names itself, then runs the prototype's six sections.
    expect(find.text('设置'), findsOneWidget);
    for (final section in ['书库', '阅读', '外观', '设备', '存储', '关于']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    // The app identity and the version sit together in 关于 — `findsOneWidget`
    // is the point: they must not also be repeated under the page title.
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('ZEPHYR COMICS · 0.1.0'), findsOneWidget);
    // Switches are hand-drawn, not Material's SwitchListTile.
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('the switch knob is painted and tracks the value', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final scheme = zephyrDarkTheme().colorScheme;
    await tester.pumpWidget(
      MaterialApp(theme: zephyrDarkTheme(), home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();

    const switchKey = Key('settings-switch-显示页码');
    finder() => find.descendant(
      of: find.byKey(switchKey),
      matching: find.byKey(const Key('switch-knob')),
    );
    BoxDecoration knob() =>
        tester.widget<DecoratedBox>(finder()).decoration as BoxDecoration;

    // A hand-drawn track with no knob reads as a bare capsule, so the knob's own
    // paint and size are part of the contract.
    expect(knob().shape, BoxShape.circle);
    expect(tester.getSize(finder()), const Size(16, 16));
    // Starts on: the page colour on a brass track.
    expect(knob().color, scheme.surface);

    await tester.tap(find.byKey(switchKey));
    await tester.pumpAndSettle();

    expect(settingsSnapshot.value.showPageNumber, isFalse);
    // Off: the `--tx3` grey on a transparent track.
    expect(knob().color, scheme.outline);
  });

  // The settings list is taller than the default 800x600 test viewport, and a
  // ListView does not build off-screen children. These tests size the viewport
  // to fit the whole page instead of scrolling, so the taps do not depend on
  // scroll geometry.
  testWidgets('enum choices are inline segments that persist on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('默认阅读模式'), findsOneWidget);

    // Every option is on screen at once — no dropdown to open.
    expect(find.text('阅读页背景'), findsOneWidget);
    expect(find.text('纸张'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-reader-background-paper')));
    await tester.pumpAndSettle();
    expect(settingsSnapshot.value.readerBackground, ReaderBackground.paper);

    expect(find.text('应用主题'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-theme-dark')));
    await tester.pumpAndSettle();
    expect(settingsSnapshot.value.themePreference, ThemePreference.dark);
  });

  testWidgets('the storage section reports and clears the derived cache', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final adapter = InMemoryDerivedCacheAdapter(
      bytes: 129 * 1024 * 1024,
      entries: 42,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(cache: DerivedCache(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('派生缓存'), findsOneWidget);
    expect(find.text('封面与缩略图 · 可随时重建'), findsOneWidget);
    expect(find.text('129.0 MB'), findsOneWidget);

    await tester.tap(find.text('清除缓存'));
    await tester.pumpAndSettle();

    // The confirmation names the cost in bytes.
    expect(find.text('清除派生缓存？'), findsOneWidget);
    expect(find.text('将释放'), findsOneWidget);
    // The paragraph above already says what is deleted, so listing what survives
    // on top of that was redundant.
    expect(find.text('保留'), findsNothing);
    expect(find.text('源文件 · 进度 · 历史 · 书签'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pumpAndSettle();

    expect(adapter.clearCalls, 1);
    expect(find.text('0 B'), findsOneWidget);
    expect(find.text('再次清除缓存'), findsOneWidget);
  });

  testWidgets('an unreadable cache size disables the clear action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final adapter = InMemoryDerivedCacheAdapter(
      failure: StateError('cache unavailable'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(cache: DerivedCache(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂时无法读取'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '清除缓存'))
          .onPressed,
      isNull,
    );
  });
}

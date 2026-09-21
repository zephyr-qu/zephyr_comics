import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zephyr_comics/theme/zephyr_theme.dart';
import 'package:zephyr_comics/views/app_shell.dart';

/// The shell is the only surface that owns the bottom navigation bar, and it
/// was changed without coverage when the theme landed. These tests pin the
/// destinations, the navigation, and the reader exception.
Widget _app(String initialLocation) => MaterialApp.router(
  theme: zephyrDarkTheme(),
  routerConfig: GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/library', builder: (_, _) => const Text('shelf')),
          GoRoute(path: '/history', builder: (_, _) => const Text('history')),
          GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
        ],
      ),
      // The reader lives outside the shell on purpose: no navigation bar while
      // reading.
      GoRoute(path: '/reader', builder: (_, _) => const Text('reader')),
    ],
  ),
);

/// The bar is hand-drawn, so selection is asserted through the label's colour:
/// brass when lit, `--tx3` when not.
Color _navColour(WidgetTester tester, String slug) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(Key('nav-$slug')),
        matching: find.byType(Text),
      ),
    )
    .style!
    .color!;

void main() {
  final scheme = zephyrDarkTheme().colorScheme;

  testWidgets('the shell exposes all three destinations', (tester) async {
    await tester.pumpWidget(_app('/library'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav-library')), findsOneWidget);
    expect(find.byKey(const Key('nav-history')), findsOneWidget);
    expect(find.byKey(const Key('nav-settings')), findsOneWidget);
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // The prototype's bar has no indicator pill, so Material's NavigationBar —
    // and with it the pill — must be gone.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('tapping a destination navigates and moves the selection', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/library'));
    await tester.pumpAndSettle();
    expect(_navColour(tester, 'library'), scheme.primary);
    expect(_navColour(tester, 'history'), scheme.outline);

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('history'), findsOneWidget);
    expect(_navColour(tester, 'history'), scheme.primary);
    expect(_navColour(tester, 'library'), scheme.outline);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
    expect(_navColour(tester, 'settings'), scheme.primary);
  });

  testWidgets('the reader route is outside the shell', (tester) async {
    await tester.pumpWidget(_app('/reader'));
    await tester.pumpAndSettle();

    expect(find.text('reader'), findsOneWidget);
    expect(find.byKey(const Key('nav-library')), findsNothing);
  });
}

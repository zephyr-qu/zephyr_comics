import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr_comics/library/comic_library.dart';
import 'package:zephyr_comics/signals/app_signals.dart';
import 'package:zephyr_comics/views/library/library_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings.reset();
    librarySnapshot.value = const LibrarySnapshot(
      status: LibraryStatus.initial,
      entries: [],
    );
  });

  testWidgets('shows direct directory onboarding without import action', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('先选择漫画目录'), findsOneWidget);
    expect(find.text('选择漫画根目录'), findsOneWidget);
    expect(find.text('导入漫画文件'), findsNothing);
  });

  testWidgets('renders an empty search result without a second clear action', (
    tester,
  ) async {
    await settings.setScanPath('/comics');
    librarySnapshot.value = const LibrarySnapshot(
      status: LibraryStatus.empty,
      entries: [],
      query: 'missing',
    );
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('书架里没有匹配「missing」的书。'), findsOneWidget);
    // The search field owns the escape hatch; the state adds no button.
    expect(find.text('清除搜索'), findsNothing);
  });

  testWidgets('keeps the shelf mounted while refreshing existing entries', (
    tester,
  ) async {
    await settings.setScanPath('/comics');
    librarySnapshot.value = const LibrarySnapshot(
      status: LibraryStatus.content,
      entries: [
        ComicLibraryEntry(
          path: '/comics/one.cbz',
          title: 'One',
          format: 'cbz',
          fileSize: 1,
          totalPages: 1,
          addedAt: 1,
        ),
      ],
    );
    librarySnapshot.value = librarySnapshot.value.copyWith(
      status: LibraryStatus.loading,
    );

    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
  });

  testWidgets('the inline search field drives the library query', (
    tester,
  ) async {
    await settings.setScanPath('/comics');
    librarySnapshot.value = const LibrarySnapshot(
      status: LibraryStatus.content,
      entries: [
        ComicLibraryEntry(
          path: '/comics/one.cbz',
          title: 'One',
          format: 'cbz',
          fileSize: 1,
          totalPages: 1,
          addedAt: 1,
        ),
      ],
    );
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    // Search lives in the header now — no dialog to open.
    expect(find.text('搜索书名'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // The pill owns the fill and the border, so the field inside must contribute
    // neither. `border: InputBorder.none` alone loses to the theme's
    // `enabledBorder` / `focusedBorder`, which stacks a second outline inside.
    final decoration = tester
        .widget<InputDecorator>(find.byType(InputDecorator))
        .decoration;
    expect(decoration.filled, isFalse);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();

    expect(find.text('书架里没有匹配「missing」的书。'), findsOneWidget);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();

    // Clearing empties the field, so the hint is back.
    expect(find.text('搜索书名'), findsOneWidget);
  });

  testWidgets('the library options sheet drives the ordering', (tester) async {
    await settings.setScanPath('/comics');
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    // Sort and rescan live behind the header button now, so the sheet is the
    // only place they exist.
    expect(find.byTooltip('书库选项'), findsOneWidget);
    expect(find.byKey(const Key('library-sort-title')), findsNothing);

    await tester.tap(find.byTooltip('书库选项'));
    await tester.pumpAndSettle();

    expect(find.text('排序'), findsOneWidget);
    expect(find.text('最近加入'), findsOneWidget);
    expect(find.text('书库'), findsOneWidget);
    expect(find.byKey(const Key('library-rescan')), findsOneWidget);
    // The rescan row reports the shelf size.
    expect(
      find.descendant(
        of: find.byKey(const Key('library-rescan')),
        matching: find.text('0 册'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('library-sort-title')));
    await tester.pumpAndSettle();

    expect(librarySnapshot.value.sort, LibrarySort.title);
    // Choosing closes the sheet again.
    expect(find.byKey(const Key('library-sort-title')), findsNothing);
  });
}

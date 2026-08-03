import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/library/comic_library.dart';
import 'package:zephyr_comics/signals/app_signals.dart';
import 'package:zephyr_comics/views/library/library_screen.dart';

void main() {
  setUp(() {
    scanDirectoryPath.value = '';
    isScanning.value = false;
    librarySnapshot.value = const LibrarySnapshot(
      status: LibraryStatus.initial,
      entries: [],
    );
  });

  testWidgets('shows direct directory onboarding without import action', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('还没有漫画'), findsOneWidget);
    expect(find.text('选择漫画目录'), findsOneWidget);
    expect(find.text('导入漫画文件'), findsNothing);
  });

  testWidgets('renders an empty search result and clear action', (
    tester,
  ) async {
    scanDirectoryPath.value = '/comics';
    librarySnapshot.value = const LibrarySnapshot(
      status: LibraryStatus.empty,
      entries: [],
      query: 'missing',
    );
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    expect(find.text('没有匹配的漫画'), findsOneWidget);
    expect(find.text('清除搜索'), findsOneWidget);
  });
}

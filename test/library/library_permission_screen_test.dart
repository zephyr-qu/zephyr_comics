import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/library/comic_library.dart';
import 'package:zephyr_comics/signals/app_signals.dart';
import 'package:zephyr_comics/views/library/library_screen.dart';

void main() {
  const storageChannel = MethodChannel('com.zephyr.comics/storage');

  setUp(() {
    scanDirectoryPath.value = '';
    isScanning.value = false;
    librarySnapshot.value = const LibrarySnapshot(
      status: LibraryStatus.initial,
      entries: [],
    );
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

  testWidgets('library explains all-files access before choosing a root', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));

    await tester.tap(find.text('选择漫画目录'));
    await tester.pumpAndSettle();

    expect(find.text('需要访问漫画文件'), findsOneWidget);
    expect(find.text('去授权'), findsOneWidget);
    expect(find.text('暂不授权'), findsOneWidget);
  });
}

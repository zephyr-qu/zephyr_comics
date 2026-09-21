import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr_comics/models/reader_mode.dart';
import 'package:zephyr_comics/signals/app_signals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const settingsChannel = MethodChannel('com.zephyr.comics/settings');
  const volumeKeysChannel = MethodChannel('com.zephyr.comics/volume_keys');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeKeysChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeKeysChannel, null);
  });

  test('startup refresh respects the automatic refresh preference', () async {
    await setScanPath('/comics');
    await setAutoRefreshLibrary(false);
    var refreshCalls = 0;

    await refreshLibraryIfConfigured(refresh: () async => refreshCalls++);

    expect(refreshCalls, 0);

    await setAutoRefreshLibrary(true);
    await refreshLibraryIfConfigured(refresh: () async => refreshCalls++);

    expect(refreshCalls, 1);
  });

  test('preferences round-trip through the seam', () async {
    await loadPreferences();
    await setScanPath('/comics');
    await setShowPageNumber(false);
    await setReaderMode(ReaderMode.rtl);

    settings.reset();

    await loadPreferences();

    expect(settings.snapshot.value.scanDirectoryPath, '/comics');
    expect(settings.snapshot.value.showPageNumber, isFalse);
    expect(settings.snapshot.value.readerMode, ReaderMode.rtl);
  });
}

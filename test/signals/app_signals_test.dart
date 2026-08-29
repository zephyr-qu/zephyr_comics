import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr_comics/models/reader_mode.dart';
import 'package:zephyr_comics/signals/app_signals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    scanDirectoryPath.value = '';
    autoRefreshLibrary.value = true;
  });

  test('startup refresh respects the automatic refresh preference', () async {
    scanDirectoryPath.value = '/comics';
    autoRefreshLibrary.value = false;
    var refreshCalls = 0;

    await refreshLibraryIfConfigured(refresh: () async => refreshCalls++);

    expect(refreshCalls, 0);

    autoRefreshLibrary.value = true;
    await refreshLibraryIfConfigured(refresh: () async => refreshCalls++);

    expect(refreshCalls, 1);
  });

  test('preferences round-trip through the seam', () async {
    await loadPreferences();
    await setScanPath('/comics');
    await setShowPageNumber(false);
    await setReaderMode(ReaderMode.rtl);

    scanDirectoryPath.value = '';
    showPageNumber.value = true;
    readerMode.value = ReaderMode.vertical;

    await loadPreferences();

    expect(scanDirectoryPath.value, '/comics');
    expect(showPageNumber.value, isFalse);
    expect(readerMode.value, ReaderMode.rtl);
  });
}

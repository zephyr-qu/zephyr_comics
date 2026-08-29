import 'package:signals_flutter/signals_flutter.dart';
import 'package:flutter/services.dart';
import '../models/reader_mode.dart';
import '../models/settings_options.dart';
import '../src/rust/api/comic.dart' show scanDirectoryToLibrary;
import '../library/comic_library.dart';
import '../library/library_root_access.dart';
import '../reading/reading_records.dart';
import '../services/android_library_root_access.dart';
import '../services/preferences.dart';

final scanDirectoryPath = signal<String>('');
final readerMode = signal<ReaderMode>(ReaderMode.vertical);
final isDarkMode = signal<bool>(true);
final themePreference = signal<ThemePreference>(ThemePreference.system);
final autoRefreshLibrary = signal<bool>(true);
final keepScreenAwake = signal<bool>(true);
final volumeKeyPaging = signal<bool>(false);
final showPageNumber = signal<bool>(true);
final orientationPreference = signal<OrientationPreference>(
  OrientationPreference.auto,
);
final readerBackground = signal<ReaderBackground>(ReaderBackground.black);

final comicLibrary = ComicLibrary(adapter: _RustComicLibraryAdapter());
final libraryRootAccess = LibraryRootAccess(
  permission: const AndroidAllFilesAccessAdapter(),
  picker: const FilePickerLibraryDirectoryPicker(),
);
final librarySnapshot = signal<LibrarySnapshot>(
  const LibrarySnapshot(status: LibraryStatus.initial, entries: []),
);
final readingRecords = ReadingRecords(adapter: FrbReadingRecordsAdapter());
Preferences? _preferences;

Future<Preferences> _prefs() async => _preferences ??= await Preferences.load();

class _RustComicLibraryAdapter implements ComicLibraryAdapter {
  @override
  Future<List<ComicLibraryEntry>> scan(String rootPath) async {
    final entries = await scanDirectoryToLibrary(path: rootPath);
    return entries
        .map(
          (entry) => ComicLibraryEntry(
            path: entry.filePath,
            title: entry.title?.trim().isNotEmpty == true
                ? entry.title!.trim()
                : entry.filePath.split(RegExp(r'[/\\]')).last,
            format: entry.format,
            fileSize: entry.fileSize.toInt(),
            totalPages: entry.totalPages.toInt(),
            addedAt: entry.addedAt.toInt(),
            lastReadAt: entry.lastOpenedAt?.toInt(),
            coverData: entry.coverData,
          ),
        )
        .toList(growable: false);
  }
}

Future<void> loadPreferences() async {
  final prefs = await _prefs();
  scanDirectoryPath.value = prefs.getString(Preferences.scanPath) ?? '';
  readerMode.value = ReaderMode.fromStorage(
    prefs.getString(Preferences.readerMode) ?? 'vertical',
  );
  isDarkMode.value = prefs.getBool(Preferences.isDarkMode) ?? true;
  themePreference.value = ThemePreference.values.firstWhere(
    (value) =>
        value.name ==
        (prefs.getString(Preferences.themePreference) ?? 'system'),
    orElse: () => ThemePreference.system,
  );
  autoRefreshLibrary.value =
      prefs.getBool(Preferences.autoRefreshLibrary) ?? true;
  keepScreenAwake.value = prefs.getBool(Preferences.keepScreenAwake) ?? true;
  volumeKeyPaging.value = prefs.getBool(Preferences.volumeKeyPaging) ?? false;
  showPageNumber.value = prefs.getBool(Preferences.showPageNumber) ?? true;
  orientationPreference.value = OrientationPreference.values.firstWhere(
    (value) =>
        value.name ==
        (prefs.getString(Preferences.orientationPreference) ?? 'auto'),
    orElse: () => OrientationPreference.auto,
  );
  readerBackground.value = ReaderBackground.values.firstWhere(
    (value) =>
        value.name ==
        (prefs.getString(Preferences.readerBackground) ?? 'black'),
    orElse: () => ReaderBackground.black,
  );
  await _applyOrientationPreference(orientationPreference.value);
}

Future<void> refreshLibraryIfConfigured({
  Future<void> Function()? refresh,
}) async {
  if (!autoRefreshLibrary.value || scanDirectoryPath.value.isEmpty) return;
  await (refresh ?? refreshLibrary)();
}

Future<void> refreshLibrary() async {
  final rawPath = scanDirectoryPath.value;
  if (rawPath.isEmpty) return;
  // 先在 await 前同步进入 loading，保证 UI 只看一个快照也能反映扫描中状态。
  librarySnapshot.value = librarySnapshot.value.copyWith(
    status: LibraryStatus.loading,
    message: null,
  );
  // comicLibrary 内部按代际守卫，返回的必然是最新的快照。
  librarySnapshot.value = await comicLibrary.refresh(rawPath);
}

Future<void> setScanPath(String path) async {
  scanDirectoryPath.value = path;
  await (await _prefs()).setString(Preferences.scanPath, path);
  await refreshLibrary();
}

Future<LibraryRootChoice> chooseAndSetLibraryRoot({
  required Future<bool> Function() confirmPermission,
}) async {
  final result = await libraryRootAccess.choose(
    confirmPermission: confirmPermission,
  );
  if (result.status == LibraryRootChoiceStatus.selected) {
    await setScanPath(result.path!);
  }
  return result;
}

void searchLibraryEntries(String query) {
  final snapshot = comicLibrary.search(query);
  librarySnapshot.value = snapshot;
}

void sortLibraryEntries(LibrarySort sort) {
  final snapshot = comicLibrary.sortBy(sort);
  librarySnapshot.value = snapshot;
}

Future<void> setReaderMode(ReaderMode mode) async {
  readerMode.value = mode;
  await (await _prefs()).setString(Preferences.readerMode, mode.storageValue);
}

Future<void> setDarkMode(bool dark) async {
  isDarkMode.value = dark;
  themePreference.value = dark ? ThemePreference.dark : ThemePreference.light;
  final prefs = await _prefs();
  await prefs.setBool(Preferences.isDarkMode, dark);
  await prefs.setString(
    Preferences.themePreference,
    themePreference.value.name,
  );
}

Future<void> setThemePreference(ThemePreference preference) async {
  themePreference.value = preference;
  if (preference != ThemePreference.system) {
    isDarkMode.value = preference == ThemePreference.dark;
  }
  await (await _prefs()).setString(
    Preferences.themePreference,
    preference.name,
  );
}

Future<void> setAutoRefreshLibrary(bool value) async {
  autoRefreshLibrary.value = value;
  await (await _prefs()).setBool(Preferences.autoRefreshLibrary, value);
}

Future<void> setKeepScreenAwake(bool value) async {
  keepScreenAwake.value = value;
  await (await _prefs()).setBool(Preferences.keepScreenAwake, value);
}

Future<void> setVolumeKeyPaging(bool value) async {
  volumeKeyPaging.value = value;
  await (await _prefs()).setBool(Preferences.volumeKeyPaging, value);
}

Future<void> setShowPageNumber(bool value) async {
  showPageNumber.value = value;
  await (await _prefs()).setBool(Preferences.showPageNumber, value);
}

Future<void> setOrientationPreference(OrientationPreference value) async {
  orientationPreference.value = value;
  await _applyOrientationPreference(value);
  await (await _prefs()).setString(
    Preferences.orientationPreference,
    value.name,
  );
}

Future<void> _applyOrientationPreference(OrientationPreference value) {
  final orientations = switch (value) {
    OrientationPreference.auto => <DeviceOrientation>[],
    OrientationPreference.portrait => [DeviceOrientation.portraitUp],
    OrientationPreference.landscape => [DeviceOrientation.landscapeLeft],
  };
  return SystemChrome.setPreferredOrientations(orientations);
}

Future<void> setReaderBackground(ReaderBackground value) async {
  readerBackground.value = value;
  await (await _prefs()).setString(Preferences.readerBackground, value.name);
}

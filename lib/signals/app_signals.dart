import 'package:signals_flutter/signals_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../models/reader_mode.dart';
import '../models/settings_options.dart';
import '../src/rust/library/db.dart' show LibraryEntry;
import '../src/rust/api/comic.dart' show scanDirectoryToLibrary;
import '../library/comic_library.dart';
import '../library/library_root_access.dart';
import '../reading/reading_records.dart';
import '../services/android_library_root_access.dart';

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
final libraryEntries = signal<List<LibraryEntry>>([]);
final isScanning = signal<bool>(false);
final errorMessage = signal<String?>(null);
final comicLibrary = ComicLibrary(adapter: _RustComicLibraryAdapter());
final libraryRootAccess = LibraryRootAccess(
  permission: const AndroidAllFilesAccessAdapter(),
  picker: const FilePickerLibraryDirectoryPicker(),
);
final librarySnapshot = signal<LibrarySnapshot>(
  const LibrarySnapshot(status: LibraryStatus.initial, entries: []),
);
final readingRecords = ReadingRecords(adapter: FrbReadingRecordsAdapter());
int _refreshGeneration = 0;

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
  final prefs = await SharedPreferences.getInstance();
  scanDirectoryPath.value = prefs.getString('scanPath') ?? '';
  readerMode.value = ReaderMode.fromStorage(
    prefs.getString('readerMode') ?? 'vertical',
  );
  isDarkMode.value = prefs.getBool('isDarkMode') ?? true;
  themePreference.value = ThemePreference.values.firstWhere(
    (value) => value.name == (prefs.getString('themePreference') ?? 'system'),
    orElse: () => ThemePreference.system,
  );
  autoRefreshLibrary.value = prefs.getBool('autoRefreshLibrary') ?? true;
  keepScreenAwake.value = prefs.getBool('keepScreenAwake') ?? true;
  volumeKeyPaging.value = prefs.getBool('volumeKeyPaging') ?? false;
  showPageNumber.value = prefs.getBool('showPageNumber') ?? true;
  orientationPreference.value = OrientationPreference.values.firstWhere(
    (value) =>
        value.name == (prefs.getString('orientationPreference') ?? 'auto'),
    orElse: () => OrientationPreference.auto,
  );
  readerBackground.value = ReaderBackground.values.firstWhere(
    (value) => value.name == (prefs.getString('readerBackground') ?? 'black'),
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
  final generation = ++_refreshGeneration;
  final rawPath = scanDirectoryPath.value;
  if (rawPath.isEmpty) return;

  isScanning.value = true;
  errorMessage.value = null;
  try {
    final snapshot = await comicLibrary.refresh(rawPath);
    if (generation != _refreshGeneration) return;
    librarySnapshot.value = snapshot;
    libraryEntries.value = snapshot.entries.map(_toRustEntry).toList();
    errorMessage.value = snapshot.message;
  } catch (e) {
    if (generation != _refreshGeneration) return;
    errorMessage.value = '扫描失败: $e';
  } finally {
    if (generation == _refreshGeneration) isScanning.value = false;
  }
}

LibraryEntry _toRustEntry(ComicLibraryEntry entry) => LibraryEntry(
  filePath: entry.path,
  title: entry.title,
  author: null,
  publisher: null,
  description: null,
  genres: const [],
  year: null,
  format: entry.format,
  fileSize: BigInt.from(entry.fileSize),
  totalPages: BigInt.from(entry.totalPages),
  coverData: entry.coverData,
  addedAt: BigInt.from(entry.addedAt),
  lastOpenedAt: entry.lastReadAt == null
      ? null
      : BigInt.from(entry.lastReadAt!),
);

Future<void> setScanPath(String path) async {
  scanDirectoryPath.value = path;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('scanPath', path);
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
  libraryEntries.value = snapshot.entries.map(_toRustEntry).toList();
}

void sortLibraryEntries(LibrarySort sort) {
  final snapshot = comicLibrary.sortBy(sort);
  librarySnapshot.value = snapshot;
  libraryEntries.value = snapshot.entries.map(_toRustEntry).toList();
}

Future<void> setReaderMode(ReaderMode mode) async {
  readerMode.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('readerMode', mode.storageValue);
}

Future<void> setDarkMode(bool dark) async {
  isDarkMode.value = dark;
  themePreference.value = dark ? ThemePreference.dark : ThemePreference.light;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isDarkMode', dark);
  await prefs.setString('themePreference', themePreference.value.name);
}

Future<void> setThemePreference(ThemePreference preference) async {
  themePreference.value = preference;
  if (preference != ThemePreference.system) {
    isDarkMode.value = preference == ThemePreference.dark;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('themePreference', preference.name);
}

Future<void> setAutoRefreshLibrary(bool value) async {
  autoRefreshLibrary.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('autoRefreshLibrary', value);
}

Future<void> setKeepScreenAwake(bool value) async {
  keepScreenAwake.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('keepScreenAwake', value);
}

Future<void> setVolumeKeyPaging(bool value) async {
  volumeKeyPaging.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('volumeKeyPaging', value);
}

Future<void> setShowPageNumber(bool value) async {
  showPageNumber.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('showPageNumber', value);
}

Future<void> setOrientationPreference(OrientationPreference value) async {
  orientationPreference.value = value;
  await _applyOrientationPreference(value);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('orientationPreference', value.name);
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
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('readerBackground', value.name);
}

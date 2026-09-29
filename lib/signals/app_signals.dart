import 'package:signals_flutter/signals_flutter.dart';
import '../src/rust/api/library.dart'
    show scanDirectoryToLibrary, updateLastOpened;
import '../library/comic_library.dart';
import '../library/library_root_access.dart';
import '../reading/reading_records.dart';
import '../services/android_library_root_access.dart';
import '../services/android_screen_awake.dart';
import '../services/android_volume_key_paging.dart';
import '../models/reader_mode.dart';
import '../models/settings_options.dart';
import '../settings/settings_controller.dart';
import '../utils/format.dart';

final _screenAwake = AndroidScreenAwakeAdapter();
final _volumeKeyPaging = AndroidVolumeKeyPagingAdapter();
final settings = SettingsController(
  applyKeepScreenAwake: _screenAwake.setEnabled,
  applyVolumeKeyPaging: _volumeKeyPaging.setEnabled,
);
final settingsSnapshot = settings.snapshot;
final comicLibrary = ComicLibrary(adapter: _RustComicLibraryAdapter());
final libraryRootAccess = LibraryRootAccess(
  permission: const AndroidAllFilesAccessAdapter(),
  picker: const FilePickerLibraryDirectoryPicker(),
);
final librarySnapshot = signal<LibrarySnapshot>(
  const LibrarySnapshot(status: LibraryStatus.initial, entries: []),
);
final readingRecords = ReadingRecords(adapter: FrbReadingRecordsAdapter());

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
                : baseName(entry.filePath),
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

  @override
  Future<void> markOpened(String path) async {
    updateLastOpened(filePath: path);
  }
}

Future<void> loadPreferences() async {
  await settings.load();
}

Future<void> refreshLibraryIfConfigured({
  Future<void> Function()? refresh,
}) async {
  final state = settings.snapshot.value;
  if (!state.autoRefreshLibrary || state.scanDirectoryPath.isEmpty) return;
  await (refresh ?? refreshLibrary)();
}

Future<void> refreshLibrary() async {
  final rawPath = settings.snapshot.value.scanDirectoryPath;
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
  await settings.setScanPath(path);
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
  await settings.setReaderMode(mode);
}

Future<void> setThemePreference(ThemePreference preference) async {
  await settings.setThemePreference(preference);
}

Future<void> setAutoRefreshLibrary(bool value) async {
  await settings.setAutoRefreshLibrary(value);
}

Future<void> setKeepScreenAwake(bool value) async {
  await settings.setKeepScreenAwake(value);
}

Future<void> setVolumeKeyPaging(bool value) async {
  await settings.setVolumeKeyPaging(value);
}

Future<void> setShowPageNumber(bool value) async {
  await settings.setShowPageNumber(value);
}

Future<void> setOrientationPreference(OrientationPreference value) async {
  await settings.setOrientationPreference(value);
}

Future<void> setReaderBackground(ReaderBackground value) async {
  await settings.setReaderBackground(value);
}

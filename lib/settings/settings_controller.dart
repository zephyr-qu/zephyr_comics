import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../models/reader_mode.dart';
import '../models/settings_options.dart';
import '../services/preferences.dart';

final class SettingsSnapshot {
  const SettingsSnapshot({
    required this.scanDirectoryPath,
    required this.readerMode,
    required this.themePreference,
    required this.autoRefreshLibrary,
    required this.keepScreenAwake,
    required this.volumeKeyPaging,
    required this.showPageNumber,
    required this.orientationPreference,
    required this.readerBackground,
  });

  /// The shipped defaults. The theme is [ThemePreference.light]: the identity is
  /// the paper-and-brass light palette, so "follow the system" would put a dark
  /// UI behind a paper launcher icon. Dark remains one tap away in settings.
  factory SettingsSnapshot.defaults() => const SettingsSnapshot(
    scanDirectoryPath: '',
    readerMode: ReaderMode.vertical,
    themePreference: ThemePreference.light,
    autoRefreshLibrary: true,
    keepScreenAwake: true,
    volumeKeyPaging: false,
    showPageNumber: true,
    orientationPreference: OrientationPreference.auto,
    readerBackground: ReaderBackground.black,
  );

  final String scanDirectoryPath;
  final ReaderMode readerMode;
  final ThemePreference themePreference;
  final bool autoRefreshLibrary;
  final bool keepScreenAwake;
  final bool volumeKeyPaging;
  final bool showPageNumber;
  final OrientationPreference orientationPreference;
  final ReaderBackground readerBackground;

  SettingsSnapshot copyWith({
    String? scanDirectoryPath,
    ReaderMode? readerMode,
    ThemePreference? themePreference,
    bool? autoRefreshLibrary,
    bool? keepScreenAwake,
    bool? volumeKeyPaging,
    bool? showPageNumber,
    OrientationPreference? orientationPreference,
    ReaderBackground? readerBackground,
  }) => SettingsSnapshot(
    scanDirectoryPath: scanDirectoryPath ?? this.scanDirectoryPath,
    readerMode: readerMode ?? this.readerMode,
    themePreference: themePreference ?? this.themePreference,
    autoRefreshLibrary: autoRefreshLibrary ?? this.autoRefreshLibrary,
    keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    volumeKeyPaging: volumeKeyPaging ?? this.volumeKeyPaging,
    showPageNumber: showPageNumber ?? this.showPageNumber,
    orientationPreference: orientationPreference ?? this.orientationPreference,
    readerBackground: readerBackground ?? this.readerBackground,
  );
}

final class SettingsController {
  SettingsController({
    Future<SettingsStorage> Function()? loadStorage,
    Future<void> Function(OrientationPreference)? applyOrientation,
    Future<void> Function(bool)? applyKeepScreenAwake,
    Future<void> Function(bool)? applyVolumeKeyPaging,
  }) : _loadStorage = loadStorage ?? (() => Preferences.load()),
       _applyOrientation = applyOrientation ?? _applySystemOrientation,
       _applyKeepScreenAwake = applyKeepScreenAwake ?? ((_) async {}),
       _applyVolumeKeyPaging = applyVolumeKeyPaging ?? ((_) async {});

  final Future<SettingsStorage> Function() _loadStorage;
  final Future<void> Function(OrientationPreference) _applyOrientation;
  final Future<void> Function(bool) _applyKeepScreenAwake;
  final Future<void> Function(bool) _applyVolumeKeyPaging;
  final Signal<SettingsSnapshot> _snapshot = signal(
    SettingsSnapshot.defaults(),
  );
  SettingsStorage? _storage;

  ReadonlySignal<SettingsSnapshot> get snapshot => _snapshot;

  /// Field-level views of [snapshot]. A listener that reads `.value` on one of
  /// these is only notified when *that* field changes, where reading
  /// `snapshot.value` notifies it on every settings write.
  late final Computed<String> scanDirectoryPath = computed(
    () => _snapshot.value.scanDirectoryPath,
  );
  late final Computed<ReaderMode> readerMode = computed(
    () => _snapshot.value.readerMode,
  );
  late final Computed<ThemePreference> themePreference = computed(
    () => _snapshot.value.themePreference,
  );
  late final Computed<bool> autoRefreshLibrary = computed(
    () => _snapshot.value.autoRefreshLibrary,
  );
  late final Computed<bool> keepScreenAwake = computed(
    () => _snapshot.value.keepScreenAwake,
  );
  late final Computed<bool> volumeKeyPaging = computed(
    () => _snapshot.value.volumeKeyPaging,
  );
  late final Computed<bool> showPageNumber = computed(
    () => _snapshot.value.showPageNumber,
  );
  late final Computed<OrientationPreference> orientationPreference = computed(
    () => _snapshot.value.orientationPreference,
  );
  late final Computed<ReaderBackground> readerBackground = computed(
    () => _snapshot.value.readerBackground,
  );

  Future<void> load() async {
    final prefs = await _getStorage();
    final next = SettingsSnapshot(
      scanDirectoryPath: prefs.getString(Preferences.scanPath) ?? '',
      readerMode: ReaderMode.fromStorage(
        prefs.getString(Preferences.readerMode) ?? 'vertical',
      ),
      themePreference: _enumValue(
        ThemePreference.values,
        prefs.getString(Preferences.themePreference),
        ThemePreference.light,
      ),
      autoRefreshLibrary: prefs.getBool(Preferences.autoRefreshLibrary) ?? true,
      keepScreenAwake: prefs.getBool(Preferences.keepScreenAwake) ?? true,
      volumeKeyPaging: prefs.getBool(Preferences.volumeKeyPaging) ?? false,
      showPageNumber: prefs.getBool(Preferences.showPageNumber) ?? true,
      orientationPreference: _enumValue(
        OrientationPreference.values,
        prefs.getString(Preferences.orientationPreference),
        OrientationPreference.auto,
      ),
      readerBackground: _enumValue(
        ReaderBackground.values,
        prefs.getString(Preferences.readerBackground),
        ReaderBackground.black,
      ),
    );
    _snapshot.value = next;
    await _applyOrientation(next.orientationPreference);
    await _applyKeepScreenAwake(next.keepScreenAwake);
    await _applyVolumeKeyPaging(next.volumeKeyPaging);
  }

  void reset() => _snapshot.value = SettingsSnapshot.defaults();

  Future<void> setScanPath(String value) async {
    await _setString(
      value,
      Preferences.scanPath,
      (state) => state.copyWith(scanDirectoryPath: value),
    );
  }

  Future<void> setReaderMode(ReaderMode value) async {
    await _setString(
      value.storageValue,
      Preferences.readerMode,
      (state) => state.copyWith(readerMode: value),
    );
  }

  Future<void> setThemePreference(ThemePreference value) async {
    await _setString(
      value.name,
      Preferences.themePreference,
      (state) => state.copyWith(themePreference: value),
    );
  }

  Future<void> setAutoRefreshLibrary(bool value) => _setBool(
    value,
    Preferences.autoRefreshLibrary,
    (state) => state.copyWith(autoRefreshLibrary: value),
  );

  Future<void> setKeepScreenAwake(bool value) => _setBool(
    value,
    Preferences.keepScreenAwake,
    (state) => state.copyWith(keepScreenAwake: value),
    apply: () => _applyKeepScreenAwake(value),
  );

  Future<void> setVolumeKeyPaging(bool value) => _setBool(
    value,
    Preferences.volumeKeyPaging,
    (state) => state.copyWith(volumeKeyPaging: value),
    apply: () => _applyVolumeKeyPaging(value),
  );

  Future<void> setShowPageNumber(bool value) => _setBool(
    value,
    Preferences.showPageNumber,
    (state) => state.copyWith(showPageNumber: value),
  );

  Future<void> setOrientationPreference(OrientationPreference value) async {
    _snapshot.value = _snapshot.value.copyWith(orientationPreference: value);
    await _applyOrientation(value);
    await (await _getStorage()).setString(
      Preferences.orientationPreference,
      value.name,
    );
  }

  Future<void> setReaderBackground(ReaderBackground value) async {
    await _setString(
      value.name,
      Preferences.readerBackground,
      (state) => state.copyWith(readerBackground: value),
    );
  }

  Future<void> _setString(
    String value,
    String key,
    SettingsSnapshot Function(SettingsSnapshot) update,
  ) async {
    _snapshot.value = update(_snapshot.value);
    await (await _getStorage()).setString(key, value);
  }

  Future<void> _setBool(
    bool value,
    String key,
    SettingsSnapshot Function(SettingsSnapshot) update, {
    Future<void> Function()? apply,
  }) async {
    _snapshot.value = update(_snapshot.value);
    await apply?.call();
    await (await _getStorage()).setBool(key, value);
  }

  Future<SettingsStorage> _getStorage() async {
    return _storage ??= await _loadStorage();
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    String? raw,
    T fallback,
  ) => values.firstWhere((value) => value.name == raw, orElse: () => fallback);

  static Future<void> _applySystemOrientation(OrientationPreference value) {
    final orientations = switch (value) {
      OrientationPreference.auto => <DeviceOrientation>[],
      OrientationPreference.portrait => [DeviceOrientation.portraitUp],
      OrientationPreference.landscape => [DeviceOrientation.landscapeLeft],
    };
    return SystemChrome.setPreferredOrientations(orientations);
  }
}

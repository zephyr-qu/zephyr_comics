import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/models/reader_mode.dart';
import 'package:zephyr_comics/models/settings_options.dart';
import 'package:zephyr_comics/services/preferences.dart';
import 'package:zephyr_comics/settings/settings_controller.dart';

final class MemorySettingsStorage implements SettingsStorage {
  MemorySettingsStorage([Map<String, Object?> initial = const {}])
    : _values = {...initial};

  final Map<String, Object?> _values;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;
}

void main() {
  test(
    'loads defaults and persists settings through the feature seam',
    () async {
      final storage = MemorySettingsStorage({
        Preferences.readerMode: 'rtl',
        Preferences.showPageNumber: false,
      });
      OrientationPreference? appliedOrientation;
      bool? appliedAwake;
      bool? appliedVolumePaging;
      final controller = SettingsController(
        loadStorage: () async => storage,
        applyOrientation: (value) async => appliedOrientation = value,
        applyKeepScreenAwake: (value) async => appliedAwake = value,
        applyVolumeKeyPaging: (value) async => appliedVolumePaging = value,
      );

      await controller.load();

      expect(controller.snapshot.value.readerMode, ReaderMode.rtl);
      expect(controller.snapshot.value.showPageNumber, isFalse);
      expect(controller.snapshot.value.autoRefreshLibrary, isTrue);
      // The identity is the light palette, so light is the shipped default.
      expect(controller.snapshot.value.themePreference, ThemePreference.light);
      expect(appliedOrientation, OrientationPreference.auto);
      expect(appliedAwake, isTrue);
      expect(appliedVolumePaging, isFalse);

      await controller.setKeepScreenAwake(false);
      await controller.setVolumeKeyPaging(true);
      await controller.setReaderBackground(ReaderBackground.paper);

      expect(controller.snapshot.value.keepScreenAwake, isFalse);
      expect(controller.snapshot.value.volumeKeyPaging, isTrue);
      expect(
        controller.snapshot.value.readerBackground,
        ReaderBackground.paper,
      );
      expect(storage.getBool(Preferences.keepScreenAwake), isFalse);
      expect(storage.getBool(Preferences.volumeKeyPaging), isTrue);
      expect(storage.getString(Preferences.readerBackground), 'paper');
      expect(appliedAwake, isFalse);
      expect(appliedVolumePaging, isTrue);
    },
  );

  test('a stored theme preference still wins over the light default', () async {
    final storage = MemorySettingsStorage({
      Preferences.themePreference: 'dark',
    });
    final controller = SettingsController(
      loadStorage: () async => storage,
      // Stubbed like the test above: the real appliers talk to SystemChrome,
      // which needs a binding this plain test does not have.
      applyOrientation: (_) async {},
      applyKeepScreenAwake: (_) async {},
      applyVolumeKeyPaging: (_) async {},
    );

    await controller.load();

    // Light is a default, not an override: the setting stays the user's.
    expect(controller.snapshot.value.themePreference, ThemePreference.dark);

    await controller.setThemePreference(ThemePreference.system);
    await controller.load();
    expect(controller.snapshot.value.themePreference, ThemePreference.system);
  });
}

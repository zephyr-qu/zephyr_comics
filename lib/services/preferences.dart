import 'package:shared_preferences/shared_preferences.dart';

/// 设置模块使用的持久化 seam。
abstract interface class SettingsStorage {
  String? getString(String key);

  bool? getBool(String key);

  Future<void> setString(String key, String value);

  Future<void> setBool(String key, bool value);
}

/// 偏好持久化的单一 seam：集中键名常量与类型化读写。
///
/// 键名在这里定义，读取与写入共用同一常量，杜绝拼写漂移。
final class Preferences implements SettingsStorage {
  Preferences._(this._prefs);

  final SharedPreferences _prefs;

  static Future<Preferences> load() async =>
      Preferences._(await SharedPreferences.getInstance());

  static const scanPath = 'scanPath';
  static const readerMode = 'readerMode';
  static const isDarkMode = 'isDarkMode';
  static const themePreference = 'themePreference';
  static const autoRefreshLibrary = 'autoRefreshLibrary';
  static const keepScreenAwake = 'keepScreenAwake';
  static const volumeKeyPaging = 'volumeKeyPaging';
  static const showPageNumber = 'showPageNumber';
  static const orientationPreference = 'orientationPreference';
  static const readerBackground = 'readerBackground';

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}

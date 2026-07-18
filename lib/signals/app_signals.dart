import 'package:signals_flutter/signals_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_mode.dart';

final scanDirectoryPath = signal<String>('');
final readerMode = signal<ReaderMode>(ReaderMode.vertical);
final isDarkMode = signal<bool>(true);

Future<void> loadPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  scanDirectoryPath.value = prefs.getString('scanPath') ?? '';
  readerMode.value = ReaderMode.fromStorage(
    prefs.getString('readerMode') ?? 'vertical',
  );
  isDarkMode.value = prefs.getBool('isDarkMode') ?? true;
}

Future<void> setScanPath(String path) async {
  scanDirectoryPath.value = path;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('scanPath', path);
}

Future<void> setReaderMode(ReaderMode mode) async {
  readerMode.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('readerMode', mode.storageValue);
}

Future<void> setDarkMode(bool dark) async {
  isDarkMode.value = dark;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isDarkMode', dark);
}

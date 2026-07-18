import 'package:flutter/material.dart';
import 'package:zephyr_comics/src/rust/frb_generated.dart';
import 'app.dart';
import 'signals/app_signals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await loadPreferences();
  runApp(const ZephyrApp());
}

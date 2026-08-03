import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'router/router.dart';
import 'signals/app_signals.dart';
import 'models/settings_options.dart';

class ZephyrApp extends StatelessWidget {
  const ZephyrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final preference = themePreference.value;
        return MaterialApp.router(
          title: 'Zephyr Comics',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.light,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          themeMode: switch (preference) {
            ThemePreference.system => ThemeMode.system,
            ThemePreference.light => ThemeMode.light,
            ThemePreference.dark => ThemeMode.dark,
          },
          routerConfig: router,
        );
      },
    );
  }
}

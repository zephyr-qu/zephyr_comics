import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'router/router.dart';
import 'signals/app_signals.dart';
import 'models/settings_options.dart';
import 'theme/zephyr_theme.dart';

class ZephyrApp extends StatelessWidget {
  const ZephyrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final preference = settingsSnapshot.value.themePreference;
        return MaterialApp.router(
          title: 'Zephyr Comics',
          debugShowCheckedModeBanner: false,
          theme: zephyrLightTheme(),
          darkTheme: zephyrDarkTheme(),
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

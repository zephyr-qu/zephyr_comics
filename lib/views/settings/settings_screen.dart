import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../models/reader_mode.dart';
import '../../models/settings_options.dart';
import '../../signals/app_signals.dart';
import '../library/library_root_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: false),
      body: ListView(
        children: [
          const _SectionHeader('书架'),
          const _ScanPathTile(),
          SignalBuilder(
            builder: (context) => SwitchListTile(
              secondary: const Icon(Icons.sync),
              title: const Text('启动时自动刷新'),
              value: autoRefreshLibrary.value,
              onChanged: setAutoRefreshLibrary,
            ),
          ),
          const Divider(),
          const _SectionHeader('阅读'),
          const _ReaderModeTile(),
          SignalBuilder(
            builder: (context) => SwitchListTile(
              secondary: const Icon(Icons.numbers_outlined),
              title: const Text('显示页码'),
              value: showPageNumber.value,
              onChanged: setShowPageNumber,
            ),
          ),
          const _OrientationTile(),
          const _BackgroundTile(),
          const Divider(),
          const _SectionHeader('外观'),
          const _ThemeTile(),
          const Divider(),
          const _SectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于 Zephyr Comics'),
            subtitle: const Text('版本 0.1.0 · 个人离线阅读器'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Zephyr Comics',
              applicationVersion: '0.1.0',
              applicationLegalese: '仅支持 CBZ/ZIP，本地离线使用。',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('许可证与隐私'),
            subtitle: Text('不联网、不采集遥测；源漫画文件不会被修改。'),
          ),
        ],
      ),
    );
  }
}

class _ScanPathTile extends StatelessWidget {
  const _ScanPathTile();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final path = scanDirectoryPath.value;
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('漫画目录'),
          subtitle: Text(
            path.isEmpty ? '尚未设置' : path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickPath(context),
        );
      },
    );
  }

  Future<void> _pickPath(BuildContext context) async {
    await chooseLibraryRootFrom(context);
  }
}

class _ReaderModeTile extends StatelessWidget {
  const _ReaderModeTile();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final mode = readerMode.value;
        return ListTile(
          leading: const Icon(Icons.view_carousel_outlined),
          title: const Text('默认阅读模式'),
          subtitle: Text(mode.label),
          trailing: DropdownButton<ReaderMode>(
            value: mode,
            underline: const SizedBox(),
            items: ReaderMode.values.map((m) {
              return DropdownMenuItem(value: m, child: Text(m.label));
            }).toList(),
            onChanged: (value) {
              if (value != null) setReaderMode(value);
            },
          ),
        );
      },
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final preference = themePreference.value;
        return ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('主题'),
          subtitle: Text(switch (preference) {
            ThemePreference.system => '跟随系统',
            ThemePreference.light => '浅色',
            ThemePreference.dark => '深色',
          }),
          trailing: DropdownButton<ThemePreference>(
            value: preference,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: ThemePreference.system,
                child: Text('系统'),
              ),
              DropdownMenuItem(value: ThemePreference.light, child: Text('浅色')),
              DropdownMenuItem(value: ThemePreference.dark, child: Text('深色')),
            ],
            onChanged: (value) {
              if (value != null) setThemePreference(value);
            },
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _OrientationTile extends StatelessWidget {
  const _OrientationTile();

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final value = orientationPreference.value;
      return ListTile(
        leading: const Icon(Icons.screen_rotation_outlined),
        title: const Text('屏幕方向'),
        trailing: DropdownButton<OrientationPreference>(
          value: value,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(
              value: OrientationPreference.auto,
              child: Text('自动'),
            ),
            DropdownMenuItem(
              value: OrientationPreference.portrait,
              child: Text('竖屏'),
            ),
            DropdownMenuItem(
              value: OrientationPreference.landscape,
              child: Text('横屏'),
            ),
          ],
          onChanged: (next) {
            if (next != null) setOrientationPreference(next);
          },
        ),
      );
    },
  );
}

class _BackgroundTile extends StatelessWidget {
  const _BackgroundTile();

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final value = readerBackground.value;
      return ListTile(
        leading: const Icon(Icons.format_color_fill_outlined),
        title: const Text('阅读背景'),
        trailing: DropdownButton<ReaderBackground>(
          value: value,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: ReaderBackground.black, child: Text('纯黑')),
            DropdownMenuItem(value: ReaderBackground.dark, child: Text('深灰')),
            DropdownMenuItem(value: ReaderBackground.paper, child: Text('纸张')),
            DropdownMenuItem(
              value: ReaderBackground.system,
              child: Text('跟随主题'),
            ),
          ],
          onChanged: (next) {
            if (next != null) setReaderBackground(next);
          },
        ),
      );
    },
  );
}

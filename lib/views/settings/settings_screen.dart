import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../models/reader_mode.dart';
import '../../signals/app_signals.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          const _ScanPathTile(),
          const Divider(),
          const _ReaderModeTile(),
          const Divider(),
          const _ThemeTile(),
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
    final controller = TextEditingController(text: scanDirectoryPath.value);
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('漫画目录路径'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '路径',
            hintText: '/sdcard/Comics/',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      await setScanPath(path);
    }
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
        return SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('深色模式'),
          value: isDarkMode.value,
          onChanged: (value) => setDarkMode(value),
        );
      },
    );
  }
}

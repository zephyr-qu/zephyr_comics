import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../signals/app_signals.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zephyr'), centerTitle: false),
      body: SignalBuilder(
        builder: (context) {
          final hasPath = scanDirectoryPath.value.isNotEmpty;
          if (!hasPath) {
            return _buildEmptyState(context);
          }
          // ponytail: empty library for now; real data comes from Rust SQLite
          return _buildEmptyState(context);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 96,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              '还没有漫画',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '选择漫画目录开始阅读',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _pickDirectory(context),
              icon: const Icon(Icons.folder_open),
              label: const Text('选择漫画目录'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDirectory(BuildContext context) async {
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

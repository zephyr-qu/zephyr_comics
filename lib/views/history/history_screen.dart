import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../library/comic_library.dart';
import '../../reading/reading_records.dart';
import '../../signals/app_signals.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.records, this.libraryEntries});

  final ReadingRecords? records;

  /// 库条目（path→entry 查找来源）；默认取全局 snapshot，
  /// 注入后测试与宿主可脱离全局状态。
  final List<ComicLibraryEntry>? libraryEntries;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<ReadingHistoryEntry>> _history;
  late final ReadingRecords _records;

  @override
  void initState() {
    super.initState();
    _records = widget.records ?? readingRecords;
    _history = _records.history();
  }

  Future<void> _reload() async {
    final history = _records.history();
    setState(() {
      _history = history;
    });
    await history;
  }

  Map<String, ComicLibraryEntry> _entriesByPath() {
    final source = widget.libraryEntries ?? librarySnapshot.value.entries;
    return {for (final entry in source) entry.path: entry};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读历史'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<ReadingHistoryEntry>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message(context, '历史暂时不可用', snapshot.error.toString());
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return _message(context, '暂无阅读记录', '阅读漫画后，记录会出现在这里。');
          }
          final entriesByPath = _entriesByPath();
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _HistoryTile(
                entry: entries[index],
                entryByPath: entriesByPath,
                onDeleted: _reload,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _message(BuildContext context, String title, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_rounded,
            size: 72,
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.entryByPath,
    required this.onDeleted,
  });
  final ReadingHistoryEntry entry;
  final Map<String, ComicLibraryEntry> entryByPath;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final libraryEntry = entryByPath[entry.filePath];
    final title =
        libraryEntry?.title ?? entry.filePath.split(RegExp(r'[/\\]')).last;
    final totalPages = libraryEntry?.totalPages;
    final progress = totalPages == null
        ? '第 ${entry.pageIndex + 1} 页 · ${entry.completionPercent.toStringAsFixed(0)}%'
        : '第 ${entry.pageIndex + 1} / $totalPages 页';
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: libraryEntry?.coverData == null
              ? const ColoredBox(
                  color: Colors.black12,
                  child: Icon(Icons.menu_book_outlined),
                )
              : Image.memory(libraryEntry!.coverData!, fit: BoxFit.cover),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$progress · ${_date(entry.lastReadAt)}'),
      onTap: () => context.push('/reader', extra: entry.filePath),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'delete') {
            await readingRecords.removeHistory(entry.filePath);
            onDeleted();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'delete', child: Text('从历史移除')),
        ],
      ),
    );
  }

  String _date(DateTime value) => '${value.month}/${value.day}';
}

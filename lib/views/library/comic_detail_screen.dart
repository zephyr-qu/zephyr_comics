import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../library/comic_library.dart';
import '../../reading/reading_records.dart';
import '../../reader/reader_launch.dart';
import '../../signals/app_signals.dart';

class ComicDetailScreen extends StatefulWidget {
  const ComicDetailScreen({super.key, required this.entry, this.records});

  final ComicLibraryEntry entry;
  final ReadingRecords? records;

  @override
  State<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends State<ComicDetailScreen> {
  late Future<_ComicDetailData> _data;

  ReadingRecords get _records => widget.records ?? readingRecords;

  @override
  void initState() {
    super.initState();
    _data = _loadData();
  }

  Future<_ComicDetailData> _loadData() async {
    final result = await Future.wait<Object?>([
      _records.progressFor(widget.entry.path),
      _records.bookmarksFor(widget.entry.path),
    ]);
    return _ComicDetailData(
      progress: result[0] as ReadingProgressRecord?,
      bookmarks: result[1] as List<BookmarkRecord>,
    );
  }

  void _reload() => setState(() => _data = _loadData());

  void _openReader({int? initialPage}) {
    context.push(
      '/reader',
      extra: ReaderLaunch(
        filePath: widget.entry.path,
        initialPage: initialPage,
        preserveProgressOnStart: initialPage == 0,
      ),
    );
  }

  Future<void> _resetProgress() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置阅读进度？'),
        content: const Text('这只会清除当前漫画的阅读进度，不会删除漫画文件或书签。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _records.resetProgress(widget.entry.path);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫画详情')),
      body: FutureBuilder<_ComicDetailData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(onRetry: _reload);
          }
          final data = snapshot.data!;
          return _content(context, data);
        },
      ),
    );
  }

  Widget _content(BuildContext context, _ComicDetailData data) {
    final progress = data.progress;
    final finished = progress?.isFinished == true;
    final color = Theme.of(context).colorScheme;
    final progressValue = progress == null
        ? 0.0
        : (progress.completionPercent / 100).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              height: 188,
              child: Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: widget.entry.coverData == null
                    ? ColoredBox(
                        color: color.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: color.onSurfaceVariant,
                        ),
                      )
                    : Image.memory(widget.entry.coverData!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.entry.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(widget.entry.format.toUpperCase())),
                      Chip(label: Text('${widget.entry.totalPages} 页')),
                      if (finished)
                        const Chip(
                          avatar: Icon(Icons.check, size: 16),
                          label: Text('已读完'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress == null
                        ? '还没有阅读记录'
                        : '已读 ${progress.completionPercent.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progressValue),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openReader(initialPage: progress?.pageIndex),
                icon: const Icon(Icons.play_arrow),
                label: Text(progress == null ? '开始阅读' : '继续阅读'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _openReader(initialPage: 0),
              icon: const Icon(Icons.restart_alt),
              label: const Text('从头'),
            ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _resetProgress,
            icon: const Icon(Icons.history_toggle_off),
            label: const Text('重置阅读进度'),
          ),
        ],
        const SizedBox(height: 24),
        Text('书签', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (data.bookmarks.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: const Text('暂无书签'),
              subtitle: const Text('在阅读器工具栏中可以保存当前页。'),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < data.bookmarks.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _BookmarkTile(
                    bookmark: data.bookmarks[index],
                    onTap: () => _openReader(
                      initialPage: data.bookmarks[index].pageIndex,
                    ),
                    onDelete: () async {
                      await _records.removeBookmark(
                        widget.entry.path,
                        data.bookmarks[index].pageIndex,
                      );
                      if (mounted) _reload();
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

final class _ComicDetailData {
  const _ComicDetailData({required this.progress, required this.bookmarks});

  final ReadingProgressRecord? progress;
  final List<BookmarkRecord> bookmarks;
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
  });

  final BookmarkRecord bookmark;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bookmark),
      title: Text('第 ${bookmark.pageIndex + 1} 页'),
      subtitle: bookmark.note == null ? null : Text(bookmark.note!),
      onTap: onTap,
      trailing: IconButton(
        tooltip: '删除书签',
        onPressed: () => onDelete(),
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('详情暂时不可用'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

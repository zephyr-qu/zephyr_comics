import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../library/comic_library.dart';
import '../../reading/reading_records.dart';
import '../../reader/reader_launch.dart';
import '../../signals/app_signals.dart';
import '../../theme/zephyr_theme.dart';
import '../../utils/format.dart';
import '../widgets/progress_hairline.dart';

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

  void _open(ReadingHistoryEntry entry) {
    context.push(
      '/reader',
      extra: ReaderLaunch(
        filePath: entry.filePath,
        initialPage: entry.pageIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The prototype has no app bar here — the page opens with its own h1, and
      // refreshing is a pull gesture rather than a toolbar button.
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<ReadingHistoryEntry>>(
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ZephyrSpacing.xl,
                  0,
                  ZephyrSpacing.xl,
                  ZephyrSpacing.xl,
                ),
                // Keep the pull gesture available even when the list is short.
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _PageHeader(count: entries.length),
                  _ResumeCard(
                    entry: entries.first,
                    libraryEntry: entriesByPath[entries.first.filePath],
                    onTap: () => _open(entries.first),
                  ),
                  // `.sa-list{margin-top:22px}`: the promoted card needs air
                  // before the first hairline of the list.
                  const SizedBox(height: ZephyrSpacing.xl),
                  for (final entry in entries)
                    _HistoryTile(
                      entry: entry,
                      entryByPath: entriesByPath,
                      records: _records,
                      onTap: () => _open(entry),
                      onDeleted: _reload,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String title, String message) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        // Off the ladder: the extra bottom band lifts the block clear of the
        // navigation bar so it reads as centred in the body, not the screen.
        padding: const EdgeInsets.fromLTRB(
          ZephyrSpacing.xl,
          ZephyrSpacing.xl,
          ZephyrSpacing.xl,
          70,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(
                Icons.history_rounded,
                size: 27,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: ZephyrSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: ZephyrSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.sa-h1` over `.sa-his-count`.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: ZephyrSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('阅读记录', style: theme.textTheme.headlineMedium),
          const SizedBox(height: ZephyrSpacing.sm),
          Text('$count 条 · 按最后阅读时间', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// `.sa-resume`: the most recent record, promoted above the list so "pick up
/// where I left off" is one tap instead of a scan.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.entry,
    required this.libraryEntry,
    required this.onTap,
  });

  final ReadingHistoryEntry entry;
  final ComicLibraryEntry? libraryEntry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalPages = libraryEntry?.totalPages;
    final finished = totalPages != null && entry.pageIndex + 1 >= totalPages;
    final title = libraryEntry?.title ?? baseName(entry.filePath);
    final meta = totalPages == null
        ? '读至第 ${entry.pageIndex + 1} 页'
        : finished
        ? '已读完 · 共 $totalPages 页'
        : '读至第 ${entry.pageIndex + 1} 页 · 共 $totalPages 页';

    return Padding(
      padding: const EdgeInsets.only(top: ZephyrSpacing.xl),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(ZephyrSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(ZephyrRadius.control),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.34)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 74,
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _CoverThumb(
                      entry: libraryEntry,
                      radius: ZephyrRadius.card,
                      elevated: true,
                    ),
                  ),
                ),
                const SizedBox(width: ZephyrSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '继续阅读',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              color: scheme.primary,
                            ),
                          ),
                          // `.sa-resume-body`'s own rhythm: 9px to the title and
                          // 6px to the meta line. That is one control's internal
                          // spacing, tuned by weight, not a list rhythm.
                          const SizedBox(height: 9),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 19,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      ProgressHairline(value: entry.completionPercent / 100),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.entryByPath,
    required this.records,
    required this.onTap,
    required this.onDeleted,
  });
  final ReadingHistoryEntry entry;
  final Map<String, ComicLibraryEntry> entryByPath;
  final ReadingRecords records;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final libraryEntry = entryByPath[entry.filePath];
    final title = libraryEntry?.title ?? baseName(entry.filePath);
    final totalPages = libraryEntry?.totalPages;
    final finished = totalPages != null && entry.pageIndex + 1 >= totalPages;
    final progress = totalPages == null
        ? '第 ${entry.pageIndex + 1} 页 · ${entry.completionPercent.toStringAsFixed(0)}%'
        : finished
        ? '已读完'
        : '第 ${entry.pageIndex + 1} / $totalPages 页';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: ZephyrSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: _CoverThumb(
                          entry: libraryEntry,
                          radius: ZephyrRadius.small,
                        ),
                      ),
                    ),
                    const SizedBox(width: ZephyrSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 14,
                            ),
                          ),
                          // `.sa-row-body`'s own 6px rhythm.
                          const SizedBox(height: 6),
                          Text(
                            '$progress · ${_date(entry.lastReadAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ProgressHairline(
                            value: entry.completionPercent / 100,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Touch has no hover, so the remove affordance must stay visible —
          // hiding it behind a menu is what `.sa-row-x` exists to avoid.
          IconButton(
            tooltip: '从记录移除',
            color: scheme.outline,
            onPressed: () async {
              await records.removeHistory(entry.filePath);
              onDeleted();
            },
            icon: const Icon(Icons.close, size: 15),
          ),
        ],
      ),
    );
  }

  /// The prototype labels recent reads by day (`今天 21:14`, `昨天 23:02`) and
  /// falls back to a plain date past that.
  String _date(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final time =
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return switch (today.difference(day).inDays) {
      0 => '今天 $time',
      1 => '昨天 $time',
      _ => '${value.month}月${value.day}日',
    };
  }
}

/// The prototype's cover placeholder: a 3:4 tile that falls back to a glyph
/// when the shelf has no cover bytes for the file.
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({this.entry, required this.radius, this.elevated = false});

  final ComicLibraryEntry? entry;
  final double radius;

  /// `.sa-resume-cover` floats on its own shadow; list thumbnails sit flat.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: entry?.coverData == null
            ? Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant)
            : Image.memory(entry!.coverData!, fit: BoxFit.cover),
      ),
    );
    if (!elevated) return cover;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: cover,
    );
  }
}

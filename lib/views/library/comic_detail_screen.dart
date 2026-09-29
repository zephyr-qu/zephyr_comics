import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../library/comic_library.dart';
import '../../reading/reading_records.dart';
import '../../reader/reader_launch.dart';
import '../../signals/app_signals.dart';
import '../../theme/zephyr_theme.dart';
import '../../utils/format.dart';
import '../widgets/progress_hairline.dart';

class ComicDetailScreen extends StatefulWidget {
  const ComicDetailScreen({super.key, required this.entry, this.records});

  final ComicLibraryEntry entry;
  final ReadingRecords? records;

  @override
  State<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends State<ComicDetailScreen> {
  late Future<_ComicDetailData> _data;

  /// The reset affordance confirms in place: the first tap arms it, the second
  /// commits. Matches the prototype, and keeps the destructive action two-step.
  bool _resetArmed = false;

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

  void _reload() {
    // A block body, not an arrow: an arrow hands setState the Future, and
    // Flutter rejects a setState callback that returns one.
    setState(() {
      _data = _loadData();
    });
  }

  void _openReader({int? initialPage}) {
    context.push(
      '/reader',
      extra: ReaderLaunch(
        filePath: widget.entry.path,
        initialPage: initialPage,
      ),
    );
  }

  Future<void> _resetProgress() async {
    await _records.resetProgress(widget.entry.path);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_ComicDetailData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _reload);
            }
            return _content(context, snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, _ComicDetailData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = data.progress;
    final finished = progress?.isFinished == true;
    final value = progress == null
        ? 0.0
        : (progress.completionPercent / 100).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZephyrSpacing.xl,
        0,
        ZephyrSpacing.xl,
        ZephyrSpacing.xxl,
      ),
      children: [
        // The prototype's detail has no app bar — just a back affordance.
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: '返回',
            onPressed: context.pop,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        const SizedBox(height: ZephyrSpacing.xs),
        _hero(context, scheme),
        const SizedBox(height: ZephyrSpacing.lg),
        Text(
          widget.entry.title,
          style: theme.textTheme.headlineMedium?.copyWith(fontSize: 25),
        ),
        const SizedBox(height: ZephyrSpacing.sm),
        Text(
          _metaLine(widget.entry, finished: finished),
          style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
        ),
        const SizedBox(height: ZephyrSpacing.xl),
        ProgressHairline(value: value),
        const SizedBox(height: ZephyrSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              progress == null
                  ? '尚未开始'
                  : finished
                  ? '已读完'
                  : '读至第 ${progress.pageIndex + 1} 页',
              style: theme.textTheme.labelMedium?.copyWith(fontSize: 11),
            ),
            Text(
              '${(value * 100).round()}%',
              style: theme.textTheme.labelMedium?.copyWith(fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: ZephyrSpacing.xl),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => _openReader(initialPage: progress?.pageIndex),
                child: Text(progress == null ? '开始阅读' : '继续阅读'),
              ),
            ),
            const SizedBox(width: ZephyrSpacing.md),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _openReader(initialPage: 0),
                child: const Text('从头阅读'),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZephyrSpacing.xl),
        _bookmarks(context, theme, scheme, data.bookmarks),
        _resetControl(theme, scheme, hasProgress: progress != null),
      ],
    );
  }

  /// `CBZ · 184 页 · 42.1 MB`, plus the finished marker.
  String _metaLine(ComicLibraryEntry entry, {required bool finished}) {
    final parts = <String>[
      entry.format.toUpperCase(),
      '${entry.totalPages} 页',
      if (entry.fileSize > 0) formatBytes(entry.fileSize),
      if (finished) '已读完',
    ];
    return parts.join(' · ');
  }

  Widget _hero(BuildContext context, ColorScheme scheme) {
    return SizedBox(
      height: 258,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.2),
                  scheme.primary.withValues(alpha: 0),
                ],
                stops: const [0.62, 1],
              ),
            ),
          ),
          // `.sa-det-cover`'s `saHero`: the cover settles in from 1.14× with a
          // small downward offset instead of appearing flat.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: 0.3 + 0.7 * t,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - t)),
                child: Transform.scale(scale: 1.14 - 0.14 * t, child: child),
              ),
            ),
            child: SizedBox(
              width: 166,
              height: 222,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ZephyrRadius.card),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ZephyrRadius.card),
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: widget.entry.coverData == null
                        ? Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 48,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : Image.memory(
                            widget.entry.coverData!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            // The hero is a fixed 166px cover, so bound the decode
                            // there instead of at the image's intrinsic size.
                            cacheWidth:
                                (166 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookmarks(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    List<BookmarkRecord> bookmarks,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.only(top: ZephyrSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: ZephyrSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '书签',
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
                ),
                Text(
                  '${bookmarks.length}',
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          if (bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ZephyrSpacing.md,
                horizontal: ZephyrSpacing.md,
              ),
              child: Text(
                '还没有书签。阅读时点按页面中央，即可记下当前页。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12.5,
                  height: 1.85,
                  color: scheme.outline,
                ),
              ),
            )
          else
            for (final bookmark in bookmarks)
              _BookmarkRow(
                bookmark: bookmark,
                onTap: () => _openReader(initialPage: bookmark.pageIndex),
                onDelete: () async {
                  await _records.removeBookmark(
                    widget.entry.path,
                    bookmark.pageIndex,
                  );
                  if (mounted) _reload();
                },
              ),
        ],
      ),
    );
  }

  Widget _resetControl(
    ThemeData theme,
    ColorScheme scheme, {
    required bool hasProgress,
  }) {
    return GestureDetector(
      key: const Key('detail-reset'),
      behavior: HitTestBehavior.opaque,
      onTap: hasProgress
          ? () {
              if (_resetArmed) {
                setState(() => _resetArmed = false);
                _resetProgress();
              } else {
                setState(() => _resetArmed = true);
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.only(
          top: ZephyrSpacing.lg,
          bottom: ZephyrSpacing.xl,
        ),
        child: Row(
          children: [
            Icon(
              Icons.restart_alt,
              size: 15,
              color: _resetArmed ? scheme.error : scheme.outline,
            ),
            const SizedBox(width: ZephyrSpacing.sm),
            Text(
              _resetArmed ? '再点一次确认重置' : '重置阅读进度',
              style: theme.textTheme.labelMedium?.copyWith(
                color: _resetArmed ? scheme.error : scheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ComicDetailData {
  const _ComicDetailData({required this.progress, required this.bookmarks});

  final ReadingProgressRecord? progress;
  final List<BookmarkRecord> bookmarks;
}

class _BookmarkRow extends StatelessWidget {
  const _BookmarkRow({
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
  });

  final BookmarkRecord bookmark;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ZephyrSpacing.md,
                horizontal: ZephyrSpacing.md,
              ),
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 54),
                    child: Text(
                      '第 ${bookmark.pageIndex + 1} 页',
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 11.5,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: ZephyrSpacing.md),
                  Expanded(
                    child: Text(
                      bookmark.note ?? '阅读时标记',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '删除书签',
          color: scheme.outline,
          onPressed: () => onDelete(),
          icon: const Icon(Icons.close, size: 15),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: ZephyrSpacing.md),
          Text('详情暂时不可用', style: theme.textTheme.titleLarge),
          const SizedBox(height: ZephyrSpacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

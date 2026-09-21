import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../library/comic_library.dart';
import '../../signals/app_signals.dart';
import '../../theme/zephyr_theme.dart';
import 'library_root_flow.dart';

/// The shelf is deliberately a thin projection of [ComicLibrary]. Scanning,
/// filtering and ordering stay in the seam so the same behavior is testable
/// without a Flutter surface or a real filesystem.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SignalBuilder(
          builder: (context) {
            final path = settingsSnapshot.value.scanDirectoryPath;
            final snapshot = librarySnapshot.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, snapshot),
                Expanded(
                  child: path.isEmpty
                      ? _buildNoPathState(context)
                      // Keep an existing shelf mounted during pull-to-refresh so
                      // the RefreshIndicator can finish its Future instead of
                      // being replaced by the full-screen loading state.
                      : snapshot.status == LibraryStatus.loading &&
                            snapshot.entries.isEmpty
                      ? _buildLoadingState(context, path)
                      : snapshot.status == LibraryStatus.warning
                      ? _buildWarningState(context, snapshot)
                      : snapshot.status == LibraryStatus.fatal
                      ? _buildFatalState(context, snapshot.message)
                      : snapshot.status == LibraryStatus.empty
                      ? _buildEmptyState(context, snapshot.query)
                      : _buildGrid(context, snapshot.entries),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// In-page header: the shelf title with its count, the library options button,
  /// and the inline search field. The prototype has no app bar on the shelf.
  Widget _header(BuildContext context, LibrarySnapshot snapshot) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZephyrSpacing.xl,
        ZephyrSpacing.xl,
        ZephyrSpacing.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('书架', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: ZephyrSpacing.sm),
                    Text(
                      '${snapshot.entries.length} 册',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '书库选项',
                icon: const Icon(Icons.tune, size: 19),
                onPressed: () => _showOptions(context, snapshot),
              ),
            ],
          ),
          // `.sa-search{margin-top:20px}`.
          const SizedBox(height: 20),
          _SearchField(
            controller: _searchController,
            active: snapshot.query.isNotEmpty,
          ),
        ],
      ),
    );
  }

  /// Sort and rescan are library-scoped actions, not application settings, and
  /// they are changed rarely — so they live in a sheet behind the header button
  /// instead of taking permanent space above the grid.
  Future<void> _showOptions(BuildContext context, LibrarySnapshot snapshot) {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZephyrRadius.panel),
        ),
      ),
      builder: (context) => _LibraryOptionsSheet(
        current: snapshot.sort,
        count: snapshot.entries.length,
      ),
    );
  }

  Widget _buildNoPathState(BuildContext context) {
    return _centerMessage(
      context,
      icon: Icons.folder_outlined,
      title: '先选择漫画目录',
      message:
          'Zephyr 从这里递归扫描全部 CBZ 与 ZIP，作为书架的唯一来源。'
          '原始文件不会被移动、改名或删除。',
      action: FilledButton(
        onPressed: () => _pickDirectory(context),
        child: const Text('选择漫画根目录'),
      ),
    );
  }

  /// `.sa-scan`: the scan reports itself inline instead of taking over the
  /// whole surface with a spinner.
  Widget _buildLoadingState(BuildContext context, String path) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        // `.sa-scan{padding:0 26px 90px}`: the block clears the bottom bar
        // instead of sitting on the geometric centre.
        padding: const EdgeInsets.fromLTRB(
          ZephyrSpacing.xl,
          0,
          ZephyrSpacing.xl,
          90,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '正在扫描',
              style: theme.textTheme.headlineSmall?.copyWith(fontSize: 17),
            ),
            const SizedBox(height: ZephyrSpacing.lg),
            LinearProgressIndicator(
              minHeight: 2,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: ZephyrSpacing.lg),
            Text(
              path,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String query) {
    if (query.isEmpty) {
      return _centerMessage(
        context,
        icon: Icons.folder_outlined,
        title: '目录中未找到漫画',
        message: '仅支持 CBZ 和 ZIP，图片格式为 JPEG、PNG、WebP。',
        action: OutlinedButton(
          onPressed: refreshLibrary,
          child: const Text('重新扫描'),
        ),
      );
    }
    // A query that matches nothing is just a sentence — the search field's own
    // clear affordance is the way out, so the prototype adds no badge or button.
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        // This state drops `.sa-empty`'s bottom offset (`paddingBottom: 0`), so
        // the sentence centres in the whole area instead of riding high.
        padding: const EdgeInsets.symmetric(horizontal: ZephyrSpacing.xl),
        child: Text(
          '书架里没有匹配「$query」的书。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildWarningState(BuildContext context, LibrarySnapshot snapshot) {
    final entries = snapshot.entries;
    return Column(
      children: [
        MaterialBanner(
          content: Text(snapshot.message ?? '扫描失败，显示上一次结果'),
          leading: const Icon(Icons.warning_amber_rounded),
          actions: [
            TextButton(onPressed: refreshLibrary, child: const Text('重试')),
          ],
        ),
        if (entries.isEmpty)
          Expanded(child: _buildFatalState(context, snapshot.message))
        else
          Expanded(child: _buildGrid(context, entries)),
      ],
    );
  }

  Widget _buildFatalState(BuildContext context, String? message) {
    return _centerMessage(
      context,
      icon: Icons.error_outline,
      title: '无法访问漫画目录',
      message: message ?? '请在设置中重新选择一个可访问的本地目录。',
      action: FilledButton(
        onPressed: () => _pickDirectory(context),
        child: const Text('重新选择目录'),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<ComicLibraryEntry> entries) {
    return RefreshIndicator(
      onRefresh: refreshLibrary,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          ZephyrSpacing.xl,
          ZephyrSpacing.xl,
          ZephyrSpacing.xl,
          ZephyrSpacing.xxl,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columnCount(context),
          childAspectRatio: _aspectRatio(context),
          crossAxisSpacing: _gridGap,
          mainAxisSpacing: ZephyrSpacing.xl,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) => _ComicCard(entry: entries[index]),
      ),
    );
  }

  int _columnCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / 150).floor().clamp(2, 6);
  }

  /// A cell is a 3:4 cover plus a fixed-height text block, so the grid ratio has
  /// to be derived from the column width — a constant would overflow the cell on
  /// narrow screens.
  double _aspectRatio(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = _columnCount(context);
    final cellWidth =
        (width - _pageMargin - _gridGap * (columns - 1)) / columns;
    return cellWidth / (cellWidth * 4 / 3 + _cardTextHeight);
  }

  /// The prototype's shelf grid (`.sa-grid`: `gap: 24px 18px`). The column gap
  /// is off the spacing ladder on purpose: it is a cover-grid gutter, not a page
  /// margin, and the nearest step (16) crowds two columns of art.
  static const double _gridGap = 18;

  /// The page's horizontal margin, two `xl` steps.
  static const double _pageMargin = ZephyrSpacing.xl * 2;

  /// Title line and meta line, plus the gaps above them. Off the ladder because
  /// it is derived from the two text lines, not a layout step.
  static const double _cardTextHeight = 56;

  Widget _centerMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
    String? note,
  }) {
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
              child: Icon(icon, size: 27, color: scheme.primary),
            ),
            const SizedBox(height: ZephyrSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: ZephyrSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12.5,
                height: 1.9,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: ZephyrSpacing.lg),
              Text(
                note,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: ZephyrSpacing.sm),
            action,
          ],
        ),
      ),
    );
  }

  Future<void> _pickDirectory(BuildContext context) async {
    await chooseLibraryRootFrom(context);
  }
}

/// `.sa-search`: one bordered pill holding the glyph, the field, and the clear
/// affordance; the border turns brass once a query is live.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.active});

  final TextEditingController controller;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      // The shared control height (`FilledButtonTheme`'s 46). Off the ladder
      // because it is a control dimension, not a spacing step.
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: ZephyrSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ZephyrRadius.control),
        border: Border.all(
          color: active
              ? scheme.primary.withValues(alpha: 0.34)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: scheme.outline),
          const SizedBox(width: ZephyrSpacing.md),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onChanged: (value) => searchLibraryEntries(value),
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              decoration: InputDecoration(
                isCollapsed: true,
                // The pill draws the fill and the border. `InputDecorationTheme`
                // supplies a filled `OutlineInputBorder`, so both have to be
                // switched off here — `border` alone does not win against the
                // theme's `enabledBorder`/`focusedBorder`, and leaving them on
                // stacks a second outline inside the pill.
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '搜索书名',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: scheme.outline,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: '清除搜索',
                    color: scheme.outline,
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: () {
                      controller.clear();
                      searchLibraryEntries('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ComicCard extends StatelessWidget {
  const _ComicCard({required this.entry});
  final ComicLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: () => context.push('/comic-detail', extra: entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZephyrRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ZephyrRadius.card),
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: entry.coverData == null
                      ? Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 48,
                            color: scheme.onSurface.withValues(alpha: 0.3),
                          ),
                        )
                      : Image.memory(
                          entry.coverData!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                ),
              ),
            ),
          ),
          // `.sa-cell`'s own rhythm: 10px to the title and 7px to the meta line
          // (the prototype pulls the meta up with `margin-top: -3px`). That is
          // the card's internal spacing, not the grid's.
          const SizedBox(height: 10),
          Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 7),
          Text(
            '${entry.totalPages} 页 · ${entry.format.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Library-scoped actions. The active sort carries a brass dot; the rescan row
/// uses an icon in the same leading slot so the labels stay in one column.
class _LibraryOptionsSheet extends StatelessWidget {
  const _LibraryOptionsSheet({required this.current, required this.count});

  final LibrarySort current;
  final int count;

  static const List<(LibrarySort, String)> _sorts = [
    (LibrarySort.recentlyRead, '最近阅读'),
    (LibrarySort.recentlyAdded, '最近加入'),
    (LibrarySort.title, '标题'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZephyrSpacing.xl,
          ZephyrSpacing.md,
          ZephyrSpacing.xl,
          ZephyrSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 2,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(ZephyrRadius.hairline),
                ),
              ),
            ),
            const SizedBox(height: ZephyrSpacing.lg),
            Text(
              '排序',
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 9.5),
            ),
            for (final (sort, label) in _sorts)
              _row(
                context,
                key: Key('library-sort-${sort.name}'),
                label: label,
                active: sort == current,
                onTap: () {
                  sortLibraryEntries(sort);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: ZephyrSpacing.lg),
            Text(
              '书库',
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 9.5),
            ),
            _row(
              context,
              key: const Key('library-rescan'),
              label: '重新扫描漫画目录',
              icon: Icons.refresh,
              hint: '$count 册',
              onTap: () {
                Navigator.pop(context);
                refreshLibrary();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    IconData? icon,
    String? hint,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      key: key,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Padding(
          // `.sa-sheet-row{padding:13px 0}`.
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: icon != null
                    ? Icon(icon, size: 16, color: scheme.outline)
                    : active
                    ? Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 13.5,
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (hint != null)
                Text(
                  hint,
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

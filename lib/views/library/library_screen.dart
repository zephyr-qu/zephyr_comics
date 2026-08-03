import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../library/comic_library.dart';
import '../../signals/app_signals.dart';
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
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            tooltip: '搜索漫画',
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(context),
          ),
          PopupMenuButton<LibrarySort>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            onSelected: sortLibraryEntries,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: LibrarySort.recentlyRead,
                child: Text('最近阅读'),
              ),
              PopupMenuItem(
                value: LibrarySort.recentlyAdded,
                child: Text('最近添加'),
              ),
              PopupMenuItem(value: LibrarySort.title, child: Text('标题')),
            ],
          ),
        ],
      ),
      body: SignalBuilder(
        builder: (context) {
          final path = scanDirectoryPath.value;
          final snapshot = librarySnapshot.value;
          if (path.isEmpty) return _buildNoPathState(context);
          if (snapshot.status == LibraryStatus.loading || isScanning.value) {
            return _buildLoadingState(context);
          }
          if (snapshot.status == LibraryStatus.warning) {
            return _buildWarningState(context, snapshot);
          }
          if (snapshot.status == LibraryStatus.fatal) {
            return _buildFatalState(context, snapshot.message);
          }
          if (snapshot.status == LibraryStatus.empty) {
            return _buildEmptyState(context, snapshot.query);
          }
          return _buildContent(context, snapshot);
        },
      ),
    );
  }

  Widget _buildNoPathState(BuildContext context) {
    return _centerMessage(
      context,
      icon: Icons.menu_book_rounded,
      title: '还没有漫画',
      message: '选择一个本地目录开始阅读',
      action: FilledButton.icon(
        onPressed: () => _pickDirectory(context),
        icon: const Icon(Icons.folder_open),
        label: const Text('选择漫画目录'),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return _centerMessage(
      context,
      icon: Icons.sync,
      title: '正在扫描漫画目录',
      message: '首次扫描可能需要一点时间，之后会复用未变化的文件。',
      action: const CircularProgressIndicator(),
    );
  }

  Widget _buildEmptyState(BuildContext context, String query) {
    return _centerMessage(
      context,
      icon: Icons.folder_outlined,
      title: query.isEmpty ? '目录中未找到漫画' : '没有匹配的漫画',
      message: query.isEmpty
          ? '仅支持 CBZ 和 ZIP，图片格式为 JPEG、PNG、WebP。'
          : '尝试其他关键词。',
      action: query.isEmpty
          ? OutlinedButton.icon(
              onPressed: refreshLibrary,
              icon: const Icon(Icons.refresh),
              label: const Text('重新扫描'),
            )
          : TextButton(
              onPressed: () => searchLibraryEntries(''),
              child: const Text('清除搜索'),
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
      action: FilledButton.icon(
        onPressed: () => _pickDirectory(context),
        icon: const Icon(Icons.folder_open),
        label: const Text('重新选择目录'),
      ),
    );
  }

  Widget _buildContent(BuildContext context, LibrarySnapshot snapshot) {
    return Column(
      children: [
        if (snapshot.query.isNotEmpty)
          ListTile(
            dense: true,
            leading: const Icon(Icons.search, size: 18),
            title: Text('搜索：${snapshot.query}'),
            trailing: TextButton(
              onPressed: () => searchLibraryEntries(''),
              child: const Text('清除'),
            ),
          ),
        Expanded(child: _buildGrid(context, snapshot.entries)),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, List<ComicLibraryEntry> entries) {
    return RefreshIndicator(
      onRefresh: refreshLibrary,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.7,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) => _ComicCard(entry: entries[index]),
      ),
    );
  }

  Widget _centerMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: color.primary.withValues(alpha: 0.45)),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            action,
          ],
        ),
      ),
    );
  }

  Future<void> _showSearch(BuildContext context) async {
    _searchController.text = librarySnapshot.value.query;
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索漫画'),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入标题'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _searchController.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (query != null) searchLibraryEntries(query);
  }

  Future<void> _pickDirectory(BuildContext context) async {
    await chooseLibraryRootFrom(context);
  }
}

class _ComicCard extends StatelessWidget {
  const _ComicCard({required this.entry});
  final ComicLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('/reader', extra: entry.path),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ColoredBox(
                color: color.surfaceContainerHighest,
                child: entry.coverData == null
                    ? Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: color.onSurface.withValues(alpha: 0.3),
                        ),
                      )
                    : Image.memory(
                        entry.coverData!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

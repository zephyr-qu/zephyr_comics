import 'dart:typed_data';

/// User-visible ordering options for the local shelf.
enum LibrarySort { recentlyRead, recentlyAdded, title }

/// Finite states rendered by the shelf instead of parsing infrastructure
/// exceptions in a Widget.
enum LibraryStatus { initial, loading, empty, content, warning, fatal }

class ComicLibraryEntry {
  const ComicLibraryEntry({
    required this.path,
    required this.title,
    required this.format,
    required this.fileSize,
    required this.totalPages,
    required this.addedAt,
    this.lastReadAt,
    this.coverData,
  });

  final String path;
  final String title;
  final String format;
  final int fileSize;
  final int totalPages;
  final int addedAt;
  final int? lastReadAt;
  final Uint8List? coverData;
}

class LibrarySnapshot {
  const LibrarySnapshot({
    required this.status,
    required this.entries,
    this.query = '',
    this.sort = LibrarySort.recentlyAdded,
    this.message,
  });

  final LibraryStatus status;
  final List<ComicLibraryEntry> entries;
  final String query;
  final LibrarySort sort;
  final String? message;

  LibrarySnapshot copyWith({
    LibraryStatus? status,
    List<ComicLibraryEntry>? entries,
    String? query,
    LibrarySort? sort,
    String? message,
  }) => LibrarySnapshot(
    status: status ?? this.status,
    entries: List.unmodifiable(entries ?? this.entries),
    query: query ?? this.query,
    sort: sort ?? this.sort,
    message: message ?? this.message,
  );
}

abstract interface class ComicLibraryAdapter {
  Future<List<ComicLibraryEntry>> scan(String rootPath);
}

/// Deterministic adapter for module and Widget tests. Production supplies the
/// direct-path Rust adapter at this seam.
class InMemoryComicLibraryAdapter implements ComicLibraryAdapter {
  InMemoryComicLibraryAdapter([Iterable<ComicLibraryEntry> entries = const []])
    : entries = List.unmodifiable(entries);

  List<ComicLibraryEntry> entries;
  Object? error;

  @override
  Future<List<ComicLibraryEntry>> scan(String rootPath) async {
    final failure = error;
    if (failure != null) throw failure;
    return entries;
  }
}

class ComicLibrary {
  ComicLibrary({required this.adapter, LibrarySnapshot? initial})
    : snapshot =
          initial ??
          const LibrarySnapshot(status: LibraryStatus.initial, entries: []),
      _allEntries = initial?.entries ?? const [];

  final ComicLibraryAdapter adapter;
  LibrarySnapshot snapshot;
  List<ComicLibraryEntry> _allEntries;
  int _refreshGeneration = 0;

  Future<LibrarySnapshot> refresh(String rootPath) async {
    final generation = ++_refreshGeneration;
    snapshot = snapshot.copyWith(status: LibraryStatus.loading, message: null);
    try {
      final scanned = await adapter.scan(rootPath);
      if (generation != _refreshGeneration) return snapshot;
      _allEntries = List.unmodifiable(scanned);
      final entries = _visible(_allEntries, snapshot.query, snapshot.sort);
      snapshot = snapshot.copyWith(
        status: entries.isEmpty ? LibraryStatus.empty : LibraryStatus.content,
        entries: entries,
        message: null,
      );
    } catch (error) {
      if (generation != _refreshGeneration) return snapshot;
      snapshot = snapshot.copyWith(
        status: LibraryStatus.warning,
        message: error.toString(),
      );
    }
    return snapshot;
  }

  LibrarySnapshot search(String query) {
    final normalized = query.trim().toLowerCase();
    final entries = _visible(_allEntries, normalized, snapshot.sort);
    snapshot = snapshot.copyWith(
      status: entries.isEmpty ? LibraryStatus.empty : LibraryStatus.content,
      entries: entries,
      query: normalized,
    );
    return snapshot;
  }

  LibrarySnapshot sortBy(LibrarySort sort) {
    final entries = _visible(_allEntries, snapshot.query, sort);
    snapshot = snapshot.copyWith(sort: sort, entries: entries);
    return snapshot;
  }

  static List<ComicLibraryEntry> _visible(
    Iterable<ComicLibraryEntry> source,
    String query,
    LibrarySort sort,
  ) {
    final filtered = source.where(
      (entry) => query.isEmpty || entry.title.toLowerCase().contains(query),
    );
    final entries = filtered.toList();
    entries.sort((a, b) {
      final result = switch (sort) {
        LibrarySort.recentlyRead => (b.lastReadAt ?? 0).compareTo(
          a.lastReadAt ?? 0,
        ),
        LibrarySort.recentlyAdded => b.addedAt.compareTo(a.addedAt),
        LibrarySort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
      };
      return result != 0 ? result : a.path.compareTo(b.path);
    });
    return List.unmodifiable(entries);
  }
}

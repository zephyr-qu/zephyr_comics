import '../src/rust/api/cache.dart' as rust;

/// Rebuildable application-owned data: derived covers, thumbnails and decode
/// scratch. See CONTEXT.md — the Derived Cache never includes the user's source
/// comic, so clearing it is safe but not free: the next open re-derives covers.
final class DerivedCacheStats {
  const DerivedCacheStats({
    required this.bytes,
    required this.limitBytes,
    required this.entries,
    required this.path,
  });

  final int bytes;
  final int limitBytes;
  final int entries;
  final String path;

  bool get isEmpty => bytes <= 0;
}

abstract interface class DerivedCacheAdapter {
  Future<DerivedCacheStats> readStats();

  Future<void> clear();
}

/// Product seam for the Settings storage section. Widgets never see the
/// generated FRB types behind it.
final class DerivedCache {
  const DerivedCache({required this.adapter});

  final DerivedCacheAdapter adapter;

  Future<DerivedCacheStats> stats() => adapter.readStats();

  Future<void> clear() => adapter.clear();
}

/// Production adapter over the existing Rust disk-cache API.
final class FrbDerivedCacheAdapter implements DerivedCacheAdapter {
  const FrbDerivedCacheAdapter();

  @override
  Future<DerivedCacheStats> readStats() async {
    final stats = rust.getDiskCacheStats();
    return DerivedCacheStats(
      bytes: stats.currentSize.toInt(),
      limitBytes: stats.maxSize.toInt(),
      entries: stats.cachedImages.toInt(),
      path: stats.cacheDir,
    );
  }

  @override
  Future<void> clear() async {
    rust.clearDiskCache();
  }
}

/// Deterministic adapter for module and widget tests.
final class InMemoryDerivedCacheAdapter implements DerivedCacheAdapter {
  InMemoryDerivedCacheAdapter({
    this.bytes = 0,
    this.limitBytes = 0,
    this.entries = 0,
    this.path = '',
    this.failure,
  });

  int bytes;
  int limitBytes;
  int entries;
  String path;

  /// When set, [readStats] throws it — used to cover the "size unknown" state.
  Object? failure;

  int clearCalls = 0;

  @override
  Future<DerivedCacheStats> readStats() async {
    final error = failure;
    if (error != null) throw error;
    return DerivedCacheStats(
      bytes: bytes,
      limitBytes: limitBytes,
      entries: entries,
      path: path,
    );
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    bytes = 0;
    entries = 0;
  }
}

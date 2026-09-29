import '../src/rust/api/cache.dart' as rust;

/// Rebuildable application-owned data: the derived covers stored alongside the
/// library entries. See CONTEXT.md — the Derived Cache never includes the user's
/// source comic, so clearing it is safe but not free: the next scan re-derives
/// the covers.
final class DerivedCacheStats {
  const DerivedCacheStats({required this.bytes, required this.entries});

  final int bytes;
  final int entries;

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

/// Production adapter over the covers the library stores in SQLite.
final class FrbDerivedCacheAdapter implements DerivedCacheAdapter {
  const FrbDerivedCacheAdapter();

  @override
  Future<DerivedCacheStats> readStats() async {
    final stats = rust.getDerivedCacheStats();
    return DerivedCacheStats(
      bytes: stats.bytes.toInt(),
      entries: stats.entries.toInt(),
    );
  }

  @override
  Future<void> clear() async {
    rust.clearDerivedCache();
  }
}

/// Deterministic adapter for module and widget tests.
final class InMemoryDerivedCacheAdapter implements DerivedCacheAdapter {
  InMemoryDerivedCacheAdapter({this.bytes = 0, this.entries = 0, this.failure});

  int bytes;
  int entries;

  /// When set, [readStats] throws it — used to cover the "size unknown" state.
  Object? failure;

  int clearCalls = 0;

  @override
  Future<DerivedCacheStats> readStats() async {
    final error = failure;
    if (error != null) throw error;
    return DerivedCacheStats(bytes: bytes, entries: entries);
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    bytes = 0;
    entries = 0;
  }
}

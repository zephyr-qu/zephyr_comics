# Zephyr Comics Architecture V3

> Status: Authoritative target architecture for the personal Android MVP  
> Supersedes: `开发设计文档 V1.0.md` and `ARCHITECTURE_V2.md`

## 1. Architectural Drivers

- Directly read large local CBZ/ZIP archives without duplicating them into cache.
- Keep source comics read-only and derived data recoverable.
- Hide FRB, SQLite, permission, archive, cache, and scheduling details from Widgets.
- Keep memory and concurrent work bounded during long reading sessions.
- Make product flows testable through the same interfaces used by Widgets.
- Produce an offline release APK for Android 11+.

## 2. System Shape

```text
Flutter Widgets
  -> feature module interfaces
       -> Dart adapters at local seams
            -> generated FRB bindings
                 -> Rust archive, metadata, and SQLite implementations
  -> Android filesystem permission adapter
  -> SharedPreferences adapter for user settings
```

Generated FRB types are infrastructure types. They may appear only inside Dart adapters and must be converted to product types before crossing a feature module interface.

## 3. Deep Modules

### ComicLibrary

The ComicLibrary module owns Library Root configuration, permission state, incremental scanning, deduplication, metadata/cover refresh, search, sorting, missing-file reconciliation, and library error normalization.

Its Widget-facing interface exposes library state and user operations such as choosing a root, refreshing, searching, and sorting. Widgets do not call several FRB functions to complete one refresh.

Internal seams:

- Android filesystem permission/path adapter.
- Rust library-engine adapter.
- SharedPreferences root/settings adapter.
- In-memory adapters used by tests.

### ReaderSession

ReaderSession owns opening a comic, page count, progress restoration, page loading, request deduplication, bounded directional prefetch, retry, current-page movement, progress persistence, completion, and close/flush behavior.

The existing `ReaderEngine` seam remains real because production uses an FRB adapter and tests use an in-memory adapter. Widgets receive product types and encoded page bytes only.

### ReadingRecords

ReadingRecords owns reading history, bookmarks, finished state, and progress-reset semantics. It presents one product interface to detail/history/reader surfaces and hides SQLite calls, schema versions, and migration behavior behind an adapter.

Progress, history, and bookmarks remain distinct domain concepts even if they share one database implementation.

### AppSettings

AppSettings owns user-visible preferences and their defaults: automatic refresh, default Reader Mode, keep-awake, volume keys, page number, orientation, theme, and reader background. Internal performance policy is not part of its interface.

## 4. Page Data Path

```text
ReaderScreen requests Page N
  -> ReaderSession deduplicates and prioritizes the request
  -> ReaderEngine.loadPageEncoded
  -> Rust locates the naturally sorted archive entry
  -> original JPEG/PNG/WebP bytes cross FRB
  -> Flutter decodes to a viewport-sized image
  -> bounded prefetch prepares neighboring pages
```

The product path does not decode to RGBA and re-encode PNG in Rust. It does not require an extracted source-page file cache. Flutter's decoded image cache and ReaderSession's encoded-byte cache are separate and bounded.

## 5. Library Data Path

```text
authorized Library Root
  -> recursive path discovery for CBZ/ZIP
  -> normalized path + size + modified time comparison
  -> unchanged entries reused
  -> changed/new archives inspected by Rust
  -> ComicInfo metadata and front cover resolved
  -> aspect-preserving Derived Cover generated
  -> SQLite upsert preserves durable reading fields
  -> LibrarySnapshot published once per refresh
```

Failed scans do not publish a destructive empty library. Source-file disappearance is reconciled only after a successful authorized scan.

## 6. Storage Ownership

- Source comics: user-owned, read-only, never deleted by the app.
- Library database: application-owned durable derived metadata and reading records.
- SharedPreferences: application-owned user preferences and Library Root.
- Derived Cache: application-owned and rebuildable covers/thumbnails only.

SQLite uses an explicit schema version and forward migrations. Application upgrades never use delete-and-recreate as a migration strategy.

## 7. State and Lifecycle

- Application-global state is limited to data used across routes: ComicLibrary state and AppSettings.
- ReaderSession is created per reader route and closed when that route is disposed.
- Controllers, toolbar state, and transient dialogs remain Widget-local.
- Async completions check module lifecycle before publishing state.
- New visible page work outranks speculative prefetch; obsolete queued work is canceled, active work is shared when it becomes relevant again.

## 8. Error Model

Feature modules convert infrastructure failures into finite product failures:

- permission required or revoked;
- Library Root missing;
- unsupported archive or page format;
- corrupt archive or page;
- page out of range;
- database/migration failure;
- derived cover failure;
- unexpected failure.

Fatal open failures, page-local failures, recoverable library warnings, and persistence warnings render differently. Widgets do not parse Rust error strings.

## 9. Testing Strategy

- Domain and scheduling behavior is tested at feature module interfaces with in-memory adapters.
- Archive, sort, metadata, thumbnail, and migration behavior is tested in Rust with generated local fixtures.
- Widget tests cover route states and user operations rather than private module state.
- A generated CBZ integration fixture validates the real Flutter -> FRB -> Rust -> image path.
- Device-only profile/release checks cover first-page latency, scrolling, and peak memory.

Tests replace obsolete shallow-path tests once the deep module interface covers the same behavior.

## 10. Android and Release Constraints

- `minSdk 30`, `targetSdk 35`, application ID `com.zephyr.comics`.
- All-files access is the only MVP library-access model; no SAF fallback.
- No network permission or network-dependent runtime behavior.
- Dependencies are pinned to verified version ranges and `pubspec.lock` is committed.
- One local verification command runs formatting, analysis, tests, and release APK build.

## 11. Explicit Non-Goals

- Google Play compliance for all-files access.
- Multi-root libraries, file mutation, in-app source deletion, or archive editing.
- CBR/RAR/PDF/EPUB, chapters, double-page layouts, online sources, WebDAV, or cloud backup.
- A general-purpose framework around Rust interfaces; seams exist only where production and test adapters both provide value.

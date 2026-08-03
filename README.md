# Zephyr Comics

Zephyr Comics is a personal, offline Android reader for local CBZ and ZIP comics. Flutter owns the product UI and feature modules; Rust owns archive inspection, metadata, thumbnails, and SQLite-backed reading data.

The project is currently being completed toward a personal Android MVP. CBR, PDF, EPUB, WebDAV, online sources, chapters, and double-page layouts are intentionally outside that MVP.

## Authoritative Documents

- [Product Requirements V2](docs/PRODUCT_REQUIREMENTS_V2.md)
- [Architecture V3](docs/ARCHITECTURE_V3.md)
- [Delivery Roadmap](docs/DELIVERY_ROADMAP.md)
- [Domain Language](CONTEXT.md)
- [Architectural Decisions](docs/adr)

Older V1/V2 documents are retained only as historical context and are marked as superseded.

## Current Development State

Completed Trellis tasks are archived under `.trellis/tasks/archive/`. The implementation is locally buildable but intentionally remains uncommitted until the user confirms the final dirty-worktree grouping.

## Development

Requirements: Flutter 3.44+ (Dart 3.12+), Rust/Cargo, and an Android SDK with
API 35 installed. The Android application ID is `com.zephyr.comics`; release
artifacts are local debug-signed APKs for device testing, not store publishing.

Generate the deterministic, copyright-free fixtures and run the complete local
gate with:

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

The gate runs Dart format checking, Flutter analyze/tests, Rust tests, and a
release APK build. The resulting APK is
`build/app/outputs/flutter-apk/app-release.apk`.

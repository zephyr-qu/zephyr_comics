<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/logo/vertical.svg">
    <img src="brand/logo/vertical-light.svg" alt="Zephyr Comics" width="240">
  </picture>
</p>

# Zephyr Comics

[简体中文](README.md) | English

Zephyr Comics is an offline comic reader for Android: it organizes and reads CBZ and ZIP archives stored locally on your device. Flutter owns the UI, routing, settings and reading-session scheduling; Rust owns archive reading, metadata parsing, cover thumbnails and SQLite-backed reading data. The application UI is in Simplified Chinese. The release artifact is fully offline — it requests no network permission and contains no analytics, telemetry, ads, update checks or background uploads.

This is a single-developer, personal project that is now public: the features are complete for the MVP scope and pass the local gate, and it is published as-is with no commercial support commitment.

> **Note:** the project documentation is written in Simplified Chinese. `README.md` is the authoritative version of this document; this file is its translation.

## Features

- **Library**: pick a comic root folder and scan it recursively; responsive cover grid, title search, sorting by recently read / recently added / title, pull-to-refresh with scan status, and stable de-duplication across repeated refreshes.
- **Comic details**: cover, title, archive format, page count, current progress and finished state, continue/restart reading, bookmark list, and an explicit reset-progress action with confirmation.
- **Reader**: five reading modes — single page, left-to-right, right-to-left, continuous, and webtoon; a page slider for direct navigation; add or remove a bookmark on the current page; fullscreen toggle. Switching modes keeps the current page and the reading session.
- **Reading records**: history sorted by last read time, with the last current page per comic restored as a valid page number on reopen; removing a history entry does not remove progress or bookmarks.
- **Settings**: comic root folder, refresh on startup, default reading mode, keep screen awake while reading, volume-key page turning, show page number, screen orientation, theme, reader page background, plus derived-cache size display and clearing.
- **Privacy and permissions**: the release artifact is fully offline; its only Android permission is "All files access" (`MANAGE_EXTERNAL_STORAGE`), used to read the comic root folder you pick directly. Debug/profile builds add only the `INTERNET` permission Flutter's tooling needs for hot reload, and it never reaches the release artifact. Comic content, paths and reading records never leave the device. Derived covers and thumbnails can be cleared at any time without affecting progress, history or bookmarks.
- **Read-only source files**: the app never deletes, renames, moves or rewrites your comic files.

## Supported and unsupported content

**Included**

- Archive formats: CBZ and ZIP.
- Page image formats: JPEG, PNG and WebP.
- One archive is one comic, i.e. one continuous page sequence.
- Pages are discovered recursively inside the archive; hidden entries and system-resource entries (for example entries starting with `.`, or `__MACOSX`) are ignored; pages are sorted naturally by their full path.

**Unsupported (deferred)**

- CBR/RAR, PDF, EPUB, AVIF, animated GIF, BMP and TIFF.
- Chapters, double-page spreads, automatic spread detection and cross-device sync.
- WebDAV, online sources, accounts, telemetry, update checks and cloud backup.

Unsupported formats are rejected honestly with a clear message and are never advertised as available features.

## Current status

Measured on 2026-10-10 with Flutter 3.47.2 / Dart 3.13.2; all of the following commands passed:

```text
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-fatal-infos
flutter test                 # 105 passed
cargo test --manifest-path rust/Cargo.toml          # 49 passed
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
flutter build apk --release  # succeeded
```

The table above is produced in one shot by `tool/verify_mvp.ps1`; test counts change with every commit, so the numbers here are measurements from that date, not a standing promise. The release APK size drifts with the toolchain and is deliberately not fixed here.

These numbers appear only in this section; no other section repeats them.

Two known gaps, neither of them a code defect:

- Real-device performance and startup evidence has never been collected (first visible page within 1.5 s, 100 consecutive pages, 300 MB memory target) — it can only be gathered by a person on a real device, and it is a user acceptance step.
- The real Flutter → FRB → Rust → image path is not covered by the default gate: `integration_test/reader_performance_test.dart` exercises that path and asserts the 1.5 s first-page budget, but it only runs when a CBZ is supplied by hand (`READER_BENCHMARK_CBZ`) and is skipped otherwise; end-to-end reading is verified in the on-device reading flow.

This repository publishes no prebuilt APK and has no app-store page: build the reader locally by following the next section.

## Build and run

### Requirements

| Dependency | Requirement |
|------------|-------------|
| Flutter | 3.44+ (Dart 3.12+); this repository's `pubspec.yaml` enforces a minimum Dart of `^3.10.9`; measured locally with Flutter 3.47.2 / Dart 3.13.2 |
| Rust | Cargo, plus the clippy component: `rustup component add clippy` |
| Android SDK | API 36 required (`compileSdk 36`; `targetSdk 35`, minimum API 30, i.e. Android 11 and above) |
| flutter_rust_bridge_codegen | 2.12.0: `cargo install flutter_rust_bridge_codegen --version 2.12.0` |
| LLVM | Only when codegen reports that it cannot find `libclang`: add LLVM's `bin` directory to `PATH` |

The Android application ID is `com.zephyr.comics`. The release artifact is signed with the local debug key and is meant for on-device testing, not for app-store distribution.

### Generate the Flutter-Rust bindings

The FRB bindings are generated artifacts and are not committed: both `lib/src/rust/` and `rust/src/frb_generated.rs` are ignored, while `rust/src/lib.rs` declares `mod frb_generated;`. A fresh clone must generate them once, otherwise the Rust crate cannot compile — `cargo test` keeps failing until this command has run:

```powershell
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

### Gate

Run the full local gate:

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

The gate runs seven stages in order: generate bindings, `dart format` check, `flutter analyze`, `flutter test`, `cargo test`, `cargo clippy -D warnings`, release APK build. It regenerates the ignored bindings first and leaves the working tree clean. The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

> The release build prints a tree-shaker warning about a missing `CupertinoIcons` font. This is a known Flutter toolchain defect ([flutter#119074](https://github.com/flutter/flutter/issues/119074)); the app never renders a Cupertino icon, so it is safe to ignore. Do not re-add the `cupertino_icons` dependency to silence it — `pubspec.yaml` records this as well.

### Brand assets

The Android launcher icon is generated from `brand/logo/icon.svg`; re-export it with:

```powershell
flutter test tool/export_brand_icons.dart
```

`test/brand/launcher_icon_test.dart` guards the committed icons: a missing icon, a wrong size, or an icon that is no longer the seal mark fails the test. The other lockups — `horizontal`, `vertical` and the standalone mark, each in dark-ground and light-ground variants — live in `brand/logo/`.

## Project structure

```text
lib/                 Flutter app
├── models/          Product data models
├── library/         ComicLibrary: root folder, scanning, dedup, search and sort
├── reader/          ReaderSession / ReaderEngine: open, page turn, progress, prefetch
├── reading/         ReadingRecords: history, bookmarks, finished state
├── settings/        AppSettings: user-visible preferences and defaults
├── services/        Android platform adapters (permissions, volume keys, screen-on, preferences)
├── views/           Routed screens and widgets
├── router/ theme/ utils/ signals/
└── main.dart app.dart

rust/src/            Rust backend
├── api/             FFI entry points (flutter_rust_bridge), orchestration only
├── archive.rs       CBZ/ZIP reading
├── cache/           Open ZIP handles + page table cache
├── library/         db.rs / scanner.rs / progress.rs
├── metadata.rs      ComicInfo.xml and cover thumbnails
├── sort.rs types.rs error.rs lib.rs

rust_builder/        cargokit build glue (contains vendored third-party code)
tool/                Local scripts: brand icon export, gate
test/ integration_test/ test_driver/    Tests
brand/logo/          Brand vector assets
docs/                PRD, architecture, roadmap, ADRs
```

The `lib/` / `rust/` boundary: Flutter does not parse archives or touch SQLite directly; Rust does no page pixel decoding — pages are handed to Flutter as the archive's original encoded bytes and decoded there at display size.

## Documents

- [Product requirements V2](docs/PRODUCT_REQUIREMENTS_V2.md) — authoritative MVP requirements and acceptance definition
- [Architecture V3](docs/ARCHITECTURE_V3.md) — layering, data paths, storage ownership, test strategy and explicit non-goals
- [Delivery roadmap](docs/DELIVERY_ROADMAP.md) — phases and current progress
- [Domain glossary](CONTEXT.md) — the language shared by requirements, code, tests and UI copy
- [Architecture decision records](docs/adr) — individual decisions and their context
- [Contributing guide](CONTRIBUTING.md) — environment, gate, commit messages and code conventions

These documents are written in Simplified Chinese.

## Licence

This project is released under the MIT licence; see [LICENSE](LICENSE), Copyright (c) 2026 Zephyr.

`rust_builder/cargokit/` is vendored third-party code (the official Flutter Rust Bridge integration approach), Copyright 2022 Matej Knopp, dual-licensed MIT OR Apache-2.0, with the licence text preserved at [rust_builder/cargokit/LICENSE](rust_builder/cargokit/LICENSE). Dart and Rust dependencies ship their own licences with their packages and are not enumerated here.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Before committing, make `pwsh -NoProfile -File tool/verify_mvp.ps1` fully green and use English Conventional Commits.

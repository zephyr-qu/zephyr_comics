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

Measured on 2026-10-10 with Flutter 3.47.2 / Dart 3.13.2: all seven stages of `tool/verify_mvp.ps1` pass — generate bindings, Dart format check, `flutter analyze`, 105 Flutter tests, 49 Rust tests, clippy (`-D warnings`), release APK build. Test counts change with every commit; these are measurements from that date, not a standing promise.

Two known gaps, neither of them a code defect:

- Real-device performance and startup evidence has never been collected (first visible page within 1.5 s, 100 consecutive pages, 300 MB memory target) — it can only be gathered by a person on a real device, and it is a user acceptance step.
- The real Flutter → FRB → Rust → image path is not covered by the default gate: `integration_test/reader_performance_test.dart` exercises that path and asserts the 1.5 s first-page budget, but it only runs when a CBZ is supplied by hand (`READER_BENCHMARK_CBZ`) and is skipped otherwise; end-to-end reading is verified on a real device only.

This repository publishes no prebuilt APK and has no app-store page: build the reader locally by following the next section.

## Build and run

```powershell
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml   # required on a fresh clone; bindings are not committed
pwsh -NoProfile -File tool/verify_mvp.ps1                                      # full gate; the APK lands in build/app/outputs/flutter-apk/
```

Requirements (Flutter 3.44+, Rust with clippy, Android SDK API 36, `flutter_rust_bridge_codegen` 2.12.0), the seven gate stages, the brand-icon export command, commit messages and code conventions all live in [CONTRIBUTING.md](CONTRIBUTING.md). The Android application ID is `com.zephyr.comics`; the release artifact is signed with the local debug key and is not for app-store distribution.

## Project structure

```text
lib/           Flutter app: models/ library/ reader/ reading/ settings/ services/ views/ router/ theme/ utils/ signals/
rust/src/      Rust backend: api/ is orchestration only; archive.rs, library/, cache/, metadata.rs, sort.rs
rust_builder/  cargokit build glue (contains vendored third-party code)
test/ integration_test/ test_driver/   tests      tool/ local scripts      brand/logo/ brand vectors      docs/ PRD, architecture, roadmap and ADRs
```

The `lib/` / `rust/` boundary: Flutter does not parse archives or touch SQLite directly; Rust does no page pixel decoding — pages are handed to Flutter as the archive's original encoded bytes and decoded there at display size. For the detailed layout and layering conventions see [AGENTS.md](AGENTS.md) and [Architecture V3](docs/ARCHITECTURE_V3.md).

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

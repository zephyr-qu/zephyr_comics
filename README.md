# Zephyr Comics

Zephyr Comics is a personal, offline Android reader for local CBZ and ZIP comics. Flutter owns the product UI and feature modules; Rust owns archive inspection, metadata, thumbnails, and SQLite-backed reading data.

The project is currently being completed toward a personal Android MVP. CBR, PDF, EPUB, WebDAV, online sources, chapters, and double-page layouts are intentionally outside that MVP.

## Authoritative Documents

- [Product Requirements V2](docs/PRODUCT_REQUIREMENTS_V2.md)
- [Architecture V3](docs/ARCHITECTURE_V3.md)
- [Delivery Roadmap](docs/DELIVERY_ROADMAP.md)
- [Domain Language](CONTEXT.md)
- [Architectural Decisions](docs/adr)


## Current Development State

The personal Android MVP is feature-complete: every roadmap phase — baseline,
library, reading records, reader experience, and performance/APK — has been
implemented and reviewed. Work after that has been brand and launch polish, so
the icon, the splash window, and the default theme now carry the brass-seal
identity in the app's own light palette.

The implementation is locally buildable and committed; the gate below is the
definition of green. At the last recorded run (`8ee4511`) it passed end to end
with 105 Flutter tests and 47 Rust tests and rebuilt a 64.5 MB release APK.

Two things stay explicitly open, and neither is a code gap:

- Device-only performance and launch evidence has never been collected. It is
  the user's acceptance step.
- `tool/generate_fixtures.ps1` is not byte-reproducible: the fixture archives
  are written in hashtable enumeration order, and `ZipArchive` stamps each
  entry with the current time. A gate run therefore dirties three fixtures in
  git even though their contents are stable.

## Development

Requirements: Flutter 3.44+ (Dart 3.12+), Rust/Cargo, and an Android SDK with
API 36 installed (`compileSdk 36`; the app targets API 35 and supports API 30 —
Android 11 and newer). The Android application ID is `com.zephyr.comics`;
release artifacts are local debug-signed APKs for device testing, not store
publishing.

The Flutter-Rust bridge bindings are generated, not tracked: `lib/src/rust/`
and `rust/src/frb_generated.rs` are ignored, while `rust/src/lib.rs` declares
`mod frb_generated;`. A fresh clone must generate them before the Rust crate
compiles at all — `cargo test` fails until `flutter_rust_bridge_codegen
generate --config-file flutter_rust_bridge.yaml` has run. Step 2 of the gate
below runs it for you. Note that `llvm_path` in `flutter_rust_bridge.yaml`
points at one local machine's LLVM install.

Generate the copyright-free fixtures and run the complete local gate with:

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

The gate runs Dart format checking, Flutter analyze/tests, Rust tests, and a
release APK build. The resulting APK is
`build/app/outputs/flutter-apk/app-release.apk`.

The Android launcher icons are generated from `brand/logo/icon.svg`; regenerate
them with `flutter test tool/export_brand_icons.dart`. The normal test suite
guards the committed icons via `test/brand/launcher_icon_test.dart` and fails if
they are missing, mis-sized, or not the seal mark. The other lockups —
`horizontal`, `vertical`, and the standalone mark, in dark- and light-ground
variants — live in `brand/logo/`, and `brand/preview.html` renders them
together.

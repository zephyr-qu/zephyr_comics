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

Completed Trellis tasks are archived under `.trellis/tasks/archive/`. The
implementation is locally buildable and committed; the gate below is the
definition of green.

## Development

Requirements: Flutter 3.44+ (Dart 3.12+), Rust/Cargo, and an Android SDK with
API 35 installed. The Android application ID is `com.zephyr.comics`; release
artifacts are local debug-signed APKs for device testing, not store publishing.

The Flutter-Rust bridge bindings are generated, not tracked: `lib/src/rust/`
and `rust/src/frb_generated.rs` are ignored, while `rust/src/lib.rs` declares
`mod frb_generated;`. A fresh clone must generate them before the Rust crate
compiles at all — `cargo test` fails until `flutter_rust_bridge_codegen
generate --config-file flutter_rust_bridge.yaml` has run. Step 2 of the gate
below runs it for you. Note that `llvm_path` in `flutter_rust_bridge.yaml`
points at one local machine's LLVM install.

Generate the deterministic, copyright-free fixtures and run the complete local
gate with:

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

The gate runs Dart format checking, Flutter analyze/tests, Rust tests, and a
release APK build. The resulting APK is
`build/app/outputs/flutter-apk/app-release.apk`.

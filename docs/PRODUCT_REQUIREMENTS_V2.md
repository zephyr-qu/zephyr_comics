# Zephyr Comics Product Requirements V2

> Status: Authoritative MVP product requirements  
> Product: Zephyr Comics  
> Audience: one personal Android user  
> Updated: 2026-08-03

## 1. Product Definition

Zephyr Comics is a private, offline Android application for organizing and reading local comics. The MVP optimizes for a small trustworthy surface: direct local access, a reliable library, smooth reading, durable progress, and a repeatable release build.

The application is complete only when it works as a daily reader without a development computer. A screen that renders under `flutter run` is not a finished product.

## 2. Platform and Distribution

- Android only.
- `minSdk 30` (Android 11), `targetSdk 35` (Android 15).
- Permanent application ID: `com.zephyr.comics`.
- Development versions use `0.1.x`; the completed MVP becomes `1.0.0`.
- Final artifact: a release APK that can be installed locally. Store publishing and formal release-key operations are out of scope.
- Simplified Chinese UI only.

## 3. Supported Content

### Included

- Archive formats: CBZ and ZIP.
- Page image formats: JPEG, PNG, and WebP.
- One archive is one comic and one continuous page sequence.
- Images are discovered recursively, metadata and hidden system entries are ignored, and pages are naturally sorted by their full archive path.

### Deferred

- CBR/RAR, PDF, EPUB, AVIF, animated GIF, BMP, and TIFF.
- Chapters, double-page spreads, automatic spread detection, and cross-device sync.
- WebDAV, online sources, accounts, telemetry, update checks, and cloud backup.

Unsupported content must be rejected honestly with a clear message. UI copy must not advertise deferred formats.

## 4. File and Library Model

- The user grants all-files access and selects one Library Root.
- The application reads comics directly from their filesystem paths and never modifies, renames, moves, or deletes source files.
- The Library Root is scanned recursively.
- Startup performs a lightweight incremental refresh by normalized path, size, and modification time; pull-to-refresh triggers the same operation.
- Unchanged files reuse stored metadata and Derived Covers.
- A missing or unauthorized root preserves existing Library Entries and shows a recovery banner. Entries are reconciled only after access is restored and a scan succeeds.
- There is no in-app “remove comic” or “delete source file” action. File management belongs to the Android file manager.

## 5. Library Experience

The library must provide:

- First-launch explanation and a single “选择漫画根目录” action.
- A responsive cover grid with title, reading summary, and deterministic placeholder covers.
- Search by title.
- Sorting by recently read, recently added, or title.
- Pull-to-refresh and visible scan/error states.
- Stable deduplication across repeated refreshes.

Cover selection uses a valid `ComicInfo.xml` `FrontCover` page first, otherwise the first naturally sorted page. Thumbnails preserve aspect ratio. Cover failure never removes the comic from the library.

## 6. Comic Detail

Selecting a Library Entry opens a detail screen with:

- Cover, title, archive format, page count, current progress, and finished state.
- “继续阅读” and “从头阅读”.
- Bookmarks for that comic, with jump and delete actions.
- An explicit “重置阅读进度” action with confirmation.

Starting from page one does not immediately clear the finished state. Resetting progress is separate from removing history.

## 7. Reading Experience

### Reader Modes

The MVP supports exactly five modes:

1. Single-page vertical.
2. Left-to-right.
3. Right-to-left.
4. Continuous.
5. Webtoon.

Changing mode preserves the current page and ReaderSession.

### Reader Controls

The reader toolbar includes:

- Back.
- Comic title and current/total page count.
- Page slider with direct jump.
- Reader mode selection.
- Add/remove bookmark for the current page.
- Fullscreen toggle.

The Android back action closes an open toolbar or overlay first; otherwise it saves progress and returns to comic detail.

### Completion and Failures

- The comic becomes finished when its final page becomes the current displayed page.
- The end state offers “返回书架” and “从头阅读”; it does not auto-open another comic.
- A corrupt or unsupported page produces a page-level error with retry and skip/navigation capability.
- One bad page must not make the whole comic unreadable.

## 8. Reading Records

### Progress

- Progress records the last current page per comic.
- Closing the reader flushes the latest pending progress.
- Reopening restores a valid clamped page.

### History

- History is ordered by last reading time.
- Each item shows cover, title, current/total pages, and time.
- Selecting an item continues reading.
- Removing a history entry does not remove progress or bookmarks.

### Bookmarks

- The current page can be bookmarked or unbookmarked from the reader.
- Detail shows bookmarks for that comic and supports jump/delete.
- Notes, tags, favorites, and a global bookmark center are deferred.

## 9. Settings

### Library

- Library Root.
- Refresh automatically on startup; default on.

### Reading

- Default Reader Mode; default single-page vertical.
- Keep screen awake; default on.
- Volume-key page turning; default off.
- Show page number; default on.
- Orientation: automatic, portrait, or landscape; default automatic.

### Appearance

- Theme: system, light, or dark; default system.
- Reader background: black or dark gray; default black.

### Storage

- Display Derived Cache size.
- Clear cover and thumbnail cache without touching source comics, progress, history, or bookmarks.

### About

- Product name and version.
- Offline/privacy statement.
- Open-source licenses.

Prefetch size, thread count, decode bounds, and memory limits are implementation policy and are not user settings.

## 10. Privacy and Permissions

- The MVP is completely offline and requests no network permission.
- It contains no analytics, telemetry, advertising SDK, update checker, or background upload.
- The about page states that comic content, paths, and reading records are never uploaded.
- If all-files access is denied, the app explains why it is required and offers authorization retry or exit. There is no SAF fallback in the MVP.

## 11. Quality Gates

On the user's validation phone and a fixed large CBZ of roughly 500 MB / 200 pages:

- First visible page within 1.5 seconds in a profile or release build.
- Normal continuous reading does not show loading inside the prepared page window.
- Reading 100 consecutive pages does not crash and stays within a 300 MB memory target.
- Closing and reopening restores the correct page.
- A corrupt page remains a page-level failure.

Automated verification includes:

- A small generated CBZ fixture containing sortable pages, metadata, an unsupported entry, and a corrupt-page variant.
- Dart formatting check, Flutter static analysis, Flutter tests, Rust tests, and release APK build through one local command.
- SQLite schema versioning and a migration test from the current schema. Database upgrades must not delete progress or bookmarks.

Device performance remains pending until the user runs the documented profile/release procedure and reports timing and memory evidence.

## 12. MVP Definition of Done

- Every included user flow has an automated or explicit device acceptance check.
- No screen is a placeholder.
- UI copy matches actual format and feature support.
- The repository has an understandable README, authoritative product/architecture documents, pinned dependencies, and a clean build baseline.
- The local verification command passes except for a separately documented device-only performance gate.
- A release APK builds successfully.

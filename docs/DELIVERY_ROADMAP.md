# Zephyr Comics MVP Delivery Roadmap

> This roadmap implements `PRODUCT_REQUIREMENTS_V2.md`.

> Status: every implementation gate below was completed on 2026-08-03. Device-only performance evidence remains a user acceptance step.
>
> Traceability: each phase was originally delivered as a separate tracked work item. Those records are not part of the repository; use the git history for per-item detail.

## Gate 0 — Existing Foundations

Existing shell, ReaderSession, real encoded-page path, library scan fixes, and continuous prefetch work are retained and audited. They are not treated as complete merely because code exists; each must be incorporated into a clean baseline with passing verification.

## Phase 1 — Buildable Baseline

- Audit the dirty worktree and existing task ownership.
- Preserve and commit a coherent buildable baseline.
- Set product identity and version policy.
- Pin dependencies.
- Add generated test CBZ fixtures.
- Replace stale demo integration tests.
- Add one local verification command.
- Remove only proven-unused legacy paths.
- Update README and mark old documents historical.

Exit gate: a clean checkout can run verification and build the current app without relying on hidden local state.

## Phase 2 — Trustworthy Library

- Direct filesystem access and permission recovery.
- One Library Root and incremental refresh.
- Accurate CBZ/ZIP format messaging.
- Stable deduplication and missing-file reconciliation.
- ComicInfo title/front-cover handling.
- Aspect-preserving cover and deterministic placeholder.
- Title search and three sort modes.

Exit gate: repeated startup/refresh operations produce a stable, truthful library without copying source archives.

## Phase 3 — Complete Reading Records

- Comic detail screen.
- Real reading history.
- Per-comic bookmarks.
- Finished state and end-of-comic actions.
- Progress reset and history deletion semantics.
- Database schema version and migrations.

Exit gate: every comic can be entered, resumed, restarted, bookmarked, finished, and found again through coherent product flows.

## Phase 4 — Reader and Product Experience

- Complete reader toolbar and Android back behavior.
- Implement all approved user settings and defaults.
- First-launch and permission states.
- Unified Material 3 visual tokens and feedback states.
- Honest empty/error/unsupported content messages.
- Remove remaining placeholder screens and inconsistent copy.

Exit gate: every route feels intentional, has loading/empty/error/content states, and contains no demo or misleading affordance.

## Phase 5 — Performance and APK

- Profile/release first-page and continuous-reader measurements.
- 100-page stability and memory check.
- Database migration verification.
- Offline/network-permission audit.
- Full local verification.
- Release APK build.

Exit gate: automated checks pass, release APK builds, and the user signs off on device-only performance evidence.

## Dependency Order

```text
Baseline
  -> Library
       -> Reading Records
            -> Reader Experience
                 -> Performance and APK
```

Phases may research ahead, but implementation does not start out of order. Each phase is reviewed before its dependent phase begins.

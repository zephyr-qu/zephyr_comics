---
status: accepted
---

# Use direct filesystem access for the personal Android MVP

Zephyr Comics targets a personally sideloaded Android 11+ application and reads one user-selected Library Root through Android's all-files access permission. We rejected a parallel SAF flow because Rust needs stable paths and copying 200–500 MB archives into application cache adds latency, storage duplication, and a second file-access implementation; if permission is denied, the MVP asks the user to authorize again instead of silently switching access models.

## Consequences

The MVP is not designed for Google Play distribution. Comic source files remain read-only, and application code must never delete or rewrite them.

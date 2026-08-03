---
status: accepted
---

# Pass original encoded page bytes through the reader seam

The reader extracts the original JPEG, PNG, or WebP archive entry and passes those encoded bytes through `ReaderEngine` to Flutter, where decoding is constrained to the display size. We rejected a default Rust RGBA-to-PNG path and a required decoded-file cache because they duplicate decode and encode work, retain multiple large representations, and make first-page latency worse; compatibility functions may remain, but the product reader does not use them.

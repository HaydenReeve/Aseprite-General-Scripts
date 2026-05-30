# Changelog

## V5 (2025-05-30)

Added content-anchored elastic grid algorithm as the primary sampling path. Passes 7/7 tests (6 perfect, 1 irreducible artefact-floor mismatch on Test 3).

- Content-anchored elastic grid detects opaque bounding box, row colour transitions, subdivides uniform gaps, derives column count from compression ratio, and anchors output using centre-based positioning with fence-post correction.
- Added to both integer-pitch and non-integer-pitch code paths.
- 30% opaque threshold eliminates outline bleed at character edges.
- Removed diagnostic trace infrastructure.
- Cleaned up debug scripts and test artifacts.

## V4 (2025-01-28)

Added elastic grid and drift-based split sampling. First version to pass all 7 tests.

- Elastic grid: detects internal colour transitions, assigns to logical grid indices, interpolates gaps. Majority-vote resampling within variable-width cells.
- Drift-based offset detection for split point sampling: computes upper sampling offset from cumulative grid drift at midpoint.
- Bottom-anchored detection for frames aligned to bottom edge.
- Harmonic fallback: prefers run-length pitch when profile pitch is a near-integer harmonic.

## V3 (2025-01-27)

Added integer sampler with binary-split offset heuristic.

- Dedicated sampling path for integer-pitch images where `source_dim % pitch == 0`.
- Binary-split heuristic: identifies peak row/column, applies different offsets above/below and left/right.
- Regularised DP walker path for images with strong profile signals.
- Repair pass for split-path output (speck removal, gap filling).

## V2 (2025-01-26)

Initial port from SpriteFusion PixelSnapper (Rust to Lua).

- K-Means palette quantisation.
- Gradient profile computation (row and column projections).
- Peak-based pitch estimation.
- Walker-based grid boundary detection.
- Majority-vote resampling.

## V1 (Legacy)

Prototype implementation. No longer maintained.

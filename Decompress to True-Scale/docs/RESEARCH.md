# Research

Investigation notes and algorithm analysis for the Decompress to True-Scale script.

## Problem Space

Pixel art assets arrive at non-native resolutions due to upload host compression (uneven pixel grids), AI generation artefacts (VAE encode/decode noise), or nearest-neighbour upscaling with offset errors. The goal is to recover the true-scale pixel representation from these damaged sources.

The core challenge: programmatically detecting grid boundaries in images where rows and columns have non-uniform widths, cumulative phase drift, and destroyed colour information at boundaries.

## PixelSnapper Algorithm Study

SpriteFusion PixelSnapper (Rust, ported to Python as a ComfyUI node) is the primary prior art.

**Method:**

1. Quantises image via K-Means
2. Computes gradient profiles on quantised image (sums `|gray[y, x+2] - gray[y, x]|` across rows)
3. Greedy walker: advances by step_size, snaps to nearest strong profile peak within ±35% search window
4. Falls back to regular spacing when no peak exceeds strength threshold

**Limitations for our use case:**

- Assumes fully opaque images (no alpha channel). AI art fills entire canvas.
- Transparent backgrounds produce zero gradient for most of the image, making profile signals sparse and unreliable.
- Characters occupying 15-25% of canvas area concentrate profile energy in few rows/columns.
- Transparent-opaque transitions at character boundaries create false grid line candidates.
- Weak internal signal: character bodies with mostly uniform colour provide minimal gradient signal.

**References:**

- [SpriteFusion PixelSnapper](https://github.com/Hugo-Dz/spritefusion-pixel-snapper) — Rust implementation
- [ComfyUI PixelSnapper port](https://github.com/x0x0b/ComfyUI-spritefusion-pixel-snapper) — Python port
- [PixelArt Detector](https://github.com/dimtoneff/ComfyUI-PixelArt-Detector) — alternative ComfyUI approach

## Structural Floor Analysis

Investigation into why fixed-block-boundary algorithms hit a hard performance floor.

### Test 2 (Colm Theron Token V3)

- 320×320 source, 64×64 target, pitch 5, 2 frames
- Binary split offsets are already OPTIMAL — oracle per-row Y offsets produce the same result
- All 65 mismatches (V3) have their correct pixel OUTSIDE the nominal block [ty×5, ty×5+5) × [tx×5, tx×5+5)
- All 365 expected opaque pixels exist within ±2 of nominal
- Mismatch breakdown: 23 false-transparent, 22 false-opaque, 20 wrong-colour
- Mismatches cluster at right silhouette boundary, rows 42-60

### Test 3 (Jardon Nash Token V1)

- 300×300 source, 60×60 target, pitch 5, 1 frame
- Bottom-anchored character with severe cumulative drift (~10px over 160 source rows)
- 33 detected row transitions (2 more than 31 expected from bbox)
- Even optimal 31-of-33 transition subset selection gives 450+ mismatches with elastic grid

### Oracle Bounds

| Test | Fixed Block | Oracle Row Phase | Oracle Col Phase | True Floor (±2 search) |
|------|-------------|------------------|------------------|------------------------|
| 2    | 65          | 65               | 66               | ~42                    |
| 3    | 90          | 71               | 74               | ~58                    |

**Conclusion:** Breaking through the fixed-block floor requires variable-width cell boundaries that adapt to the actual compression pattern per-region. This led to the content-anchored elastic grid approach.

## Approaches Tested and Rejected

| Approach | Test 2 | Test 3 | Verdict |
|----------|--------|--------|---------|
| Baseline (binary split) | 65 | 90 | V3 best |
| Regularised path (forced) | 146-147 | — | Profile too noisy |
| Centre-of-cell sampling | 146 | — | Same issue |
| Linear ramp offsets | 81-116 | — | Worse everywhere |
| Smoothness-optimised offsets | 122 | — | Metric unreliable |
| Phase detection (transition voting) | 183-249 | — | Signal too weak |
| Uniformity-based phase shifts | 250 | — | Background dominates |
| Coherence repair (neighbour matching) | 125 | — | Destroys correct edges |
| Lower alpha threshold | 66-71 | — | More false positives |
| Lower fill threshold | 67-102 | — | Fills with wrong colours |
| Two-pass transparent fill | 68 | — | Fills wrong cells |
| Extended threshold (±1) | 71 | — | Too many false fills |
| Boundary fill (colour match) | 69-98 | — | Fills boundary cells wrong |
| PixelSnapper-style walker | N/A | — | Gets 67 cells (not 64) |

## Content-Anchored Elastic Grid (V5 Solution)

The breakthrough: work from the content outward rather than fitting a grid from the outside in.

**Key insight:** The number of logical rows can be detected by counting colour transitions along the opaque bounding box. The compression ratio is then `row_span / n_content_rows`, and column count derives directly from that ratio.

**Critical implementation details:**

- Fence-post correction: `round(midpoint - (n-1)/2.0)` not `round(midpoint - n/2.0)` for even n.
- Row gap subdivision: gaps > 1.5× ratio indicate hidden transitions in uniform-colour regions.
- Column transitions are denser than rows (27 vs 33 for Test 3). Transition-based boundaries work reliably.
- 30% alpha threshold eliminates outline bleed.
- Must be called in both integer-pitch and non-integer-pitch code paths (Test 7 has pitch 9.4, fails the integer gate).

## Artefact Floor (Irreducible)

Test 3, cell (row=5, col=19): all 20 source pixels at rows 164-167, cols 159-163 are (248, 248, 248). The pass expects (240, 232, 208) — a cream colour destroyed by compression. No algorithm can recover colour information that does not exist in the source.

## Open Questions

1. **Colour recovery for destroyed pixels** — neighbour-based inference or palette-aware substitution could potentially recover artefact-floor pixels.
2. **Semi-transparent sprites** — current detection requires alpha > 0 for both adjacent pixels. Semi-transparent edges may produce unreliable transitions.
3. **Very low contrast transitions** — adjacent cells differing by < tolerance (40 RGB) may be missed.
4. **Non-square compression ratios** — all current tests have equal X and Y pitch. Different per-axis ratios would need separate detection.

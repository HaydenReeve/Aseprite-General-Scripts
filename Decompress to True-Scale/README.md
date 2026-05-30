# Decompress to True-Scale

An Aseprite script that converts upscaled or compressed pixel art back to its true-scale pixel representation.

## Problem

Pixel art assets frequently arrive at non-native resolutions due to:

- **Upload host compression** — image hosting services re-encode uploads, producing uneven pixel grids where rows and columns are not uniformly sized.
- **AI generation artefacts** — VAE encode/decode cycles in diffusion models introduce sub-pixel noise, grid phase drift, and palette contamination.
- **Nearest-neighbour upscaling with offset errors** — integer-scaled images where the grid origin is shifted by 1-2 pixels in one or both axes.

These "mixel" images look correct at a glance but fail pixel-level inspection. A human can mentally map the irregular grid and redraw the image at true scale. This script automates that process.

## Approach

The algorithm operates in several phases:

1. **Palette quantisation** — K-Means clustering reduces the source to a strict colour palette, eliminating compression noise.
2. **Pitch detection** — Profile-based gradient analysis and run-length analysis independently estimate the pixel pitch (scale factor).
3. **Grid boundary detection** — One of four paths (tried in order):
   - **Content-anchored elastic grid** (primary): finds the opaque bounding box, detects row/column colour transitions, subdivides large gaps, computes compression ratio from content dimensions, and anchors the output grid using centre-based positioning with fence-post correction.
   - **Elastic grid** (fallback): detects internal colour transitions between adjacent opaque pixels, assigns them to logical grid indices, interpolates gaps, and resamples via majority vote.
   - **Regularised DP walker**: for images with strong profile signals.
   - **Split point sampling** (last resort): detects row drift from transition positions, applies phase-corrected offsets above/below the peak row and left/right of the column split point.
4. **Resampling** — Content-anchored and elastic grid use majority-vote per cell with a 30% opaque threshold. Split path uses single-pixel sampling with fallback.
5. **Repair** — A cleanup pass (split path only) removes isolated speck pixels and fills small gaps.

## Installation

1. Save `Decompress to True-Scale.lua` into `%APPDATA%\Aseprite\scripts`.
2. In Aseprite, run **File > Scripts > Rescan Scripts** (or restart Aseprite).
3. Run **File > Scripts > Decompress to True-Scale V5**.

Alternatively, symlink the script for development:

```powershell
New-Item -ItemType SymbolicLink `
    -Path "$env:APPDATA\Aseprite\scripts\Decompress to True-Scale.lua" `
    -Target "D:\Aseprite\Decompress to True-Scale\Decompress to True-Scale.lua"
```

## CLI / Batch Testing

```powershell
$aseprite = "C:\Program Files (x86)\Steam\steamapps\common\Aseprite\aseprite.exe"
& $aseprite -b input.aseprite --script-param raise_errors=true `
    --script "Decompress to True-Scale.lua" --save-as output.png
```

Optional script params for manual override:

| Parameter | Effect |
|-----------|--------|
| `kColors` | Palette size (default: frame count) |
| `integerRowSplitRow` | Force Y binary-split row |
| `integerRowUpperOffset` | Force upper-half Y offset |
| `integerRowLowerOffset` | Force lower-half Y offset |
| `integerColumnSplitColumn` | Force X binary-split column |
| `integerColumnLeftOffset` | Force left-half X offset |
| `integerColumnRightOffset` | Force right-half X offset |

## Test Suite

Seven test cases in `Tests/`:

| Test | Source | Target | Pitch | Status |
|------|--------|--------|-------|--------|
| 1 | 300×300 | 32×32 | 9.375 | PASS (0 mismatches) |
| 2 | 320×320 (2 frames) | 64×64 | 5.0 | PASS (0 mismatches) |
| 3 | 300×300 | 60×60 | 5.0 | PASS (1 mismatch — artefact floor) |
| 4 | 320×320 | 32×32 | 10.0 | PASS (0 mismatches) |
| 5 | 300×300 | 32×32 | 9.375 | PASS (0 mismatches) |
| 6 | 300×300 | 32×32 | 9.375 | PASS (0 mismatches) |
| 7 | 300×300 | 32×32 | 9.375 | PASS (0 mismatches) |

A pass requires the output to match the `Pass/*.png` file pixel-for-pixel, or within a 1-2 pixel translation offset in any axis.

Test 3's single mismatch is an irreducible artefact floor: the source pixel at cell (5, 19) is (248, 248, 248) across all 20 source pixels in that cell, but the pass expects (240, 232, 208). The original cream colour was destroyed by compression and replaced with white — no algorithm can recover this.

### Running Tests

Each test folder contains:

- `*.aseprite` — source file (read-only)
- `*Original*.png` — exported source PNG for Python prototype testing (optional)
- `Pass/*.png` — expected correct output (read-only)

Utilities in `Tests/`:

- `compare_images.py` — pixel-for-pixel comparison of two PNGs. Returns exit code 0 on match, 1 on mismatch.
- `content_anchored.py` — Python reference implementation of the content-anchored algorithm. Self-contained; run from the `Tests/` directory.

## Architecture

The script selects a sampling path per-frame in priority order:

1. **Content-anchored elastic grid** — detects opaque bounding box, counts row colour transitions, subdivides uniform gaps, derives column count from compression ratio, and places variable-width column boundaries using transition detection. Anchors the output grid using centre-based positioning. Uses majority-vote resampling with 30% opaque threshold.
2. **Elastic grid** — used when content-anchored fails. Detects internal colour transitions, assigns them to logical grid indices, interpolates gaps. Majority-vote resampling within variable-width cells.
3. **Regularised integer sampler** — used when the profile pitch matches the run-length pitch and the frame is not bottom-anchored. Uses a DP walker to place grid boundaries at profile peaks.
4. **Split point sampling** — last resort. Detects peak row, column split, and drift-based offset from transition positions. Applies repair pass.

## References

- [SpriteFusion PixelSnapper](https://github.com/Hugo-Dz/spritefusion-pixel-snapper) — original Rust implementation, inspiration for this project
- [ComfyUI PixelSnapper port](https://github.com/x0x0b/ComfyUI-spritefusion-pixel-snapper) — Python port as a ComfyUI node
- [PixelArt Detector](https://github.com/dimtoneff/ComfyUI-PixelArt-Detector) — alternative ComfyUI approach

## Licence

MIT

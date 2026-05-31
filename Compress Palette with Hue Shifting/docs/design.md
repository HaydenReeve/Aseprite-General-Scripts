# Design: Compress Palette with Hue Shifting

Synthesised from the four research reports in `../research/`.

## Goal
Reduce a sprite's palette to a small set of perceptually distinct, hue-shifted ramps reminiscent of handcrafted retro pixel art. Operate in OKLab/OKLCh for perceptual fidelity, not RGB or HSV.

## High-level pipeline

```
Sprite pixels
  └─► (1) Histogram unique RGBA, drop alpha < threshold
       └─► (2) Convert to OKLab/OKLCh, cache
            └─► (3) Hue-clustering (weighted k-means on circular hue in OKLCh)
                 └─► (4) Per-cluster ramp fit (L sorted, hue-shift curve fit)
                      └─► (5) Synthesise output ramp (parametric hue-shift)
                           └─► (6) Build remap LUT (old RGB → new palette index)
                                └─► (7) Rewrite sprite + palette inside app.transaction
```

## Modes (user-selectable)

- **Hybrid** (default): detect ramps; resample lightness with smoothstep; bias endpoints toward warm/cool temperature *attractors* (not fixed offsets) with strength slider.
- **Stylise**: same pipeline as Hybrid but with strength = 1.0 and forced shared shadow.

`Preserve` mode dropped: critique 8 notes naive weighted k-means doesn't preserve ramp structure. Within-ramp constrained quantisation is already the Hybrid default with strength = 0, which is good enough for v0.1.

## OKLab implementation
- Ottosson's matrices, verbatim (research report 01, §5).
- `cbrt` helper since Lua lacks one.
- sRGB ↔ linear ↔ OKLab ↔ OKLCh chain, cached per unique source colour.
- Gamut clipping after synthesis: hue-preserving chroma reduction (keep L, h; binary-search C inside sRGB).

## Hue clustering
- Circular k-means on OKLCh hue, weighted by pixel frequency.
- Chroma threshold: colours with C < `achromatic_threshold` (≈ 0.02 in OKLab) go into a dedicated **grey ramp** (no hue, lightness only).
- Cap requested k to `min(user_k, distinct_chromatic_colours)` to avoid empty clusters (critique 2).
- Discard empty clusters after k-means; re-run with reduced k if any cluster has < 2 members.
- Default k = 4 hue ramps + grey if any achromatic colours exist. "Auto" uses elbow on WCSS up to k_max = 8.

## Ramp construction
- Stops per ramp: default 4, user-overridable. "Auto" uses source ramp's L span: wide span → 4-5 stops; narrow → 2-3.
- Lightness curve: smoothstep-spaced. Bounds adaptive (critique 7): `L_min` = source cluster L percentile 5; `L_max` = percentile 95. Strength = 1.0 lerps toward (0.15, 0.92) absolute bounds.
- Hue-shift via **temperature attractor** (critique 5):
  - Warm attractor hue: 70° (OKLCh; yellow-orange). Cool attractor hue: 250° (blue-violet).
  - At t = 1 (highlight): h_out = lerp_hue(base_hue, warm, strength · highlight_pull). Default highlight_pull = 0.25.
  - At t = 0 (shadow): h_out = lerp_hue(base_hue, cool, strength · shadow_pull). Default shadow_pull = 0.35.
  - lerp_hue uses shortest arc on the hue circle.
- Chroma curve: bell, peak at t≈0.5, `C(t) = C_base · (1 - 4·(t-0.5)²·falloff)`.
  - `C_base` = source cluster chroma percentile 75 (critique 6). Adaptive, not capped at fixed 0.18. Hard ceiling at 0.30 to keep inside sRGB.
- Shared shadow anchor: optional via advanced config; **off by default** in v0.1 (critique 1: risk of muddying when ramp identity matters more for testing).
- Gamut clipping: hue-preserving chroma reduction (binary search C with L, h fixed) after every synthesis.

## Pixel remap — constrained per-ramp (critique 1)
- During clustering, each source colour is assigned to a ramp.
- Remap each source colour to the nearest stop **within its assigned ramp** (not the global nearest). This prevents cross-ramp hopping.
- Achromatic source colours map to the grey ramp.
- No dithering.
- Alpha policy (critique 3): exclude alpha-0 pixels from histogram; preserve original alpha on write; partially transparent pixels get their RGB remapped, alpha untouched.

## UI surface (minimal — critique 9)

Visible in v0.1:
- Mode: `Hybrid | Stylise` (default Hybrid)
- Ramps: `Auto | 1..8` (default Auto)
- Stops per ramp: `Auto | 2..8` (default Auto)
- Strength: 0.0..1.0 slider (default 0.5)
- Output: `New layer | In place` (default New layer)
- Buttons: `Apply`, `Cancel`

Advanced (collapsible / hidden in v0.1, exposed via CLI only):
- `highlight_pull`, `shadow_pull`, `chroma_ceiling`, `shared_shadow`, `warm_attractor_hue`, `cool_attractor_hue`, `achromatic_threshold`.

No `Preview` button in v0.1 (critique 10): "New layer" output is already non-destructive — the user can toggle visibility to compare. Avoids preview/undo complexity for first iteration.

## CLI params
Same names as UI keys plus all advanced fields, plus `raise_errors`.

## Cel / frame / layer policy (critique 11)
- Collect pixels from **all visible cels across all frames** (single colour pool).
- Skip hidden and locked layers.
- Output mode `New layer`: create one new top-level layer named `Compressed (Hue-Shifted)` with one cel per frame containing remapped pixels (flat composite of input). Avoid name collision with `_2`, `_3` suffix.
- Output mode `In place`: rewrite each editable cel's image with its remapped version; do not touch hidden or background layers.
- Wrap the whole apply in one `app.transaction` for single-undo.

## Pixel format policy (critique 4)
- v0.1 supports RGB(A) sprites only. Indexed mode: `fail()` with a clear message instructing user to convert to RGB first (Sprite > Color Mode > RGB).
- Grayscale: same treatment as Indexed for v0.1.
- Indexed support is the first follow-up after the prototype is validated.

## Palette ordering (critique 13)
- Output palette ordered by ramp, then by lightness ascending.
- Ramps ordered by base hue ascending (0° red first, then orange, yellow, green, cyan, blue, magenta).
- Grey ramp last.
- First entry reserved for transparent if sprite has any alpha-0 pixels.

## Style/structure conventions (from existing scripts)
- Single `.lua` file at folder root.
- Top-level `DEFAULT_CONFIG` table for tunables.
- `COMMAND_TITLE` and `OUTPUT_LAYER_NAME` constants.
- `app.pixelColor` aliased as `pc`.
- `fail()` helper respecting `app.params.raise_errors`.
- All mutations inside `app.transaction(COMMAND_TITLE, function() ... end)`.
- Cache `math.floor`, `math.max`, etc. as locals before hot loops.
- Use Lua 5.4 `<const>` for compile-time constants (Aseprite ships 5.4).

## Spike plan (critique 12)
Skip the Python spike. Algorithm is small; the risky parts are Aseprite integration. Go directly to a Lua prototype. If colour-math debugging gets painful, drop in a focused Python script later.

## Out of scope for v0.1
- Dithering (not pixel-art style by default).
- Palette export to .pal/.gpl (Aseprite has built-in).
- Per-region/selection compression (only whole sprite).
- Animation-aware compression (treat all frames as one colour pool — acceptable for v0.1).
- Indexed-mode sprites (start with RGBA only; document the limitation).

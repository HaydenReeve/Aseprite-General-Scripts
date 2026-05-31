# Compress Palette with Hue Shifting

Reduces a sprite's palette using perceptually uniform OKLab/OKLCh and rebuilds it as a small set of hue-shifted ramps in the style of handcrafted retro pixel art (warm highlights, cool shadows, bell-shaped chroma curve).

> Prototype: v0.1. Subject to change as the algorithm is tuned against real sprites. See `docs/design.md` for the full design and `research/` for the source material.

## Run

GUI:

```
File > Scripts > Compress Palette with Hue Shifting
```

CLI:

```text
aseprite -b ".\sprite.aseprite" --script ".\Compress Palette with Hue Shifting\Compress Palette with Hue Shifting.lua"

aseprite -b ".\sprite.aseprite" `
  --script-param mode=Hybrid `
  --script-param ramps=4 `
  --script-param stops=4 `
  --script-param strength=0.5 `
  --script-param output="New layer" `
  --script ".\Compress Palette with Hue Shifting\Compress Palette with Hue Shifting.lua"
```

## UI

- **Mode** — `Hybrid` keeps the sprite's source hues and lightness range; `Stylise` forces strength = 1.0 (aggressive temperature shift, broader lightness range).
- **Ramps** — number of hue ramps. `0` = auto (elbow method on hue WCSS).
- **Stops per ramp** — colours per ramp. `0` = auto, derived from source lightness span.
- **Strength** — blends source-derived ramp parameters with the stylised reference (warm highlights / cool shadows). `0` = preserve source, `1` = full stylisation.
- **Output** — `New layer` (non-destructive) or `In place` (rewrite all editable cels).

## CLI params

Visible UI params, plus:

| Param                  | Default | Purpose |
|-----------------------|---------|---------|
| `highlight_pull`      | 0.25    | Max hue pull toward warm attractor at brightest stop. |
| `shadow_pull`         | 0.35    | Max hue pull toward cool attractor at darkest stop. |
| `warm_attractor_hue`  | 70      | OKLCh degrees. Yellow-orange by default. |
| `cool_attractor_hue`  | 250     | OKLCh degrees. Blue-violet by default. |
| `chroma_ceiling`      | 0.30    | Hard chroma cap (sRGB gamut safety). |
| `achromatic_threshold`| 0.02    | OKLab chroma below which a colour joins the grey ramp. |
| `shared_shadow`       | false   | (Reserved) Merge all ramps' darkest stop to one anchor. |
| `raise_errors`        | false   | Convert UI alerts to thrown errors (for CLI / batch). |

## Pipeline

1. Histogram all unique RGBA values from visible cels (alpha-0 excluded; alpha preserved on write).
2. Convert each unique colour to OKLab + OKLCh; cache.
3. Split into chromatic (`C ≥ achromatic_threshold`) and achromatic pools.
4. Cluster chromatic colours with weighted, circular k-means on hue (k-means++ seeded).
5. Per cluster: derive base hue, source-percentile lightness bounds, and source-percentile chroma; synthesise a smoothstep-spaced ramp with temperature-attractor hue pull on endpoints and a bell-shaped chroma curve. Hue-preserving gamut clip per stop.
6. Build an achromatic grey ramp from the achromatic pool if any exist.
7. Order palette by ramp base hue, dark-to-light within each ramp, grey ramp last. Reserve index 0 for transparency when needed.
8. Remap each source colour to the nearest stop **within its assigned ramp** (constrained, no cross-ramp hopping).
9. Apply inside `app.transaction` — single undo.

## Limitations (v0.1)

- RGB sprites only. Indexed and grayscale sprites are rejected with a clear message.
- Treats all frames as one colour pool.
- No dithering.
- Output palette ordering is fixed (ramp-by-hue, dark-to-light). Not user-configurable yet.
- `shared_shadow` parameter is reserved but not yet wired into the synthesis step.

## References

See `research/` for the four source reports:

- `01-oklab-color-science.md` — OKLab conversions, perceptual distance, quantisation algorithms.
- `02-hue-shifting-technique.md` — Artist conventions, palette analyses, parametric rules.
- `03-existing-implementations.md` — Aseprite Lua patterns, palette libraries, OKLab ports.
- `04-ramp-detection-grouping.md` — Ramp detection, hue clustering, parametric ramp synthesis.

## Install

Clone this repository and symlink the folder into Aseprite's scripts directory:

```powershell
$src = "D:\Aseprite\Compress Palette with Hue Shifting"
$dst = "$env:APPDATA\Aseprite\scripts\Compress Palette with Hue Shifting"
New-Item -ItemType SymbolicLink -Path $dst -Target $src
```

Then `File > Scripts > Rescan Scripts` inside Aseprite.

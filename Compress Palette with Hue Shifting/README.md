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
- **Size by** — `Ramps x Stops` (specify both directly) or `Total colours` (specify a single budget like 32; stops-per-ramp is solved to hit it, accounting for shared anchors).
- **Target colours** — total palette size when `Size by = Total colours`.
- **Ramps** — number of hue ramps. `0` = auto (elbow method on hue WCSS).
- **Stops per ramp** — colours per ramp when `Size by = Ramps x Stops`. `0` = auto, derived from source lightness span.
- **Strength** — blends source-derived ramp parameters with the stylised reference (warm highlights / cool shadows). `0` = preserve source, `1` = full stylisation.
- **Share shadow anchor** / **Share highlight anchor** — replace every chromatic ramp's darkest / brightest stop with one weighted-OKLab averaged colour, emitted once in the palette. Improves ramp cohesion and reduces palette size. Both on by default.
- **Preserve accents** — detect rare, high-chroma source colours (vivid rim lights, glow specks, attention-grabbing details) and reserve them as standalone palette entries instead of folding them into a ramp. On by default.
- **Accent slots** — hard cap on how many accents the script may reserve. The script also self-limits to `floor((n_chromatic - 1) / 3)` so ramps still get most of the palette.
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
| `grey_budget`         | 3       | Grey ramp stops when achromatic colours are present and `size_mode = Total colours`. |
| `shared_shadow`       | true    | Merge all chromatic ramps' darkest stop to one anchor. |
| `shared_highlight`    | true    | Merge all chromatic ramps' brightest stop to one anchor. |
| `accent_detection`    | true    | Enable rare-or-vivid accent preservation. |
| `max_accent_slots`    | 8       | Maximum palette entries reserved for accents. |
| `accent_score_threshold` | 0.55 | Combined chroma + visibility score threshold for accent eligibility. |
| `accent_cluster_floor`| 0.10    | OKLCh chroma below which per-cluster outliers will not be promoted to accents. |
| `accent_tolerance`    | 0.07    | OKLab ΔE; accents closer than this to an existing palette entry reuse it instead of emitting a duplicate. |
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
- Output palette ordering is fixed (shared dark anchor → ramps by hue ascending → shared light anchor → grey ramp). Not user-configurable yet.

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

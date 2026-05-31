# Changelog

## v0.2 — Iteration

- **Total-colours sizing**. New `Size by` toggle: pick a single target palette size (e.g. 32) instead of ramps × stops. `stops_per_ramp` is solved from the budget, accounting for shared-anchor savings.
- **Shared ramp anchors**. New `Share shadow anchor` and `Share highlight anchor` checkboxes (both on by default). Each chromatic ramp's darkest and brightest stops are replaced with one weighted-OKLab averaged colour, emitted once in the palette. Ramps now flow into common end-points instead of fanning out into near-black/near-white duplicates.
- Palette ordering updated to surface shared anchors at the start/end of the chromatic block.
- CLI: new `size_mode`, `target_colours`, `shared_highlight`, `grey_budget` params.

## v0.1 — Prototype

Initial prototype. OKLab-based palette compression with hue-shifted ramp synthesis.

- Histogram → circular hue k-means → per-cluster parametric ramp.
- OKLab/OKLCh conversions from Ottosson's reference matrices.
- Hue-preserving gamut clipping via binary search on chroma.
- Constrained remap (each source colour stays inside its assigned ramp).
- Adaptive lightness and chroma bounds from source percentiles; strength slider blends toward absolute reference bounds.
- Warm/cool temperature attractors for endpoint hue pull.
- Dialog UI: Mode, Ramps, Stops, Strength, Output. Advanced params exposed via CLI.
- New-layer (non-destructive) and in-place output modes.
- RGB sprites only; Indexed and grayscale rejected with clear message.

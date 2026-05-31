# Changelog

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

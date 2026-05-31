# Changelog

## v0.5 — Eye-colour preservation and saner accents

- **Accent scoring rebalanced.** The salience formula previously favoured hyper-rare singletons over moderately-rare-but-vivid colours, so a 1-pixel colour at chroma 0.16 would beat a 24-pixel eye colour at chroma 0.149. The rarity term flips to a *visibility* term (`log(1+w)/log(1+max_w)`), so colours that the eye actually sees get priority. Defaults shift to `chroma 0.65 / visibility 0.35`.
- **Pixel floor.** Singleton-pixel noise no longer counts as accents on larger sprites (`w < ceil(total_pixels / 2000)`). Tiny sprites (< 512 opaque pixels) keep singletons eligible so deliberate one-pixel highlights still register.
- **Upper-frequency guard.** Colours occupying ≥ 15 % of opaque pixels are excluded from accent candidacy; those are body tones, not accents.
- **Per-cluster outlier promotion.** After hue clustering, a second pass scans each cluster for high-chroma residual outliers (`C > max(0.10, 1.8 × cluster_median_C)`) and promotes them to standalone accent entries. This catches the common case where a vivid eye-red is bucketed into a brown/orange ramp and would otherwise be averaged out.
- **Ramp chroma percentile raised from P75 to P90** (P75 for clusters with fewer than 8 source colours) so the synthesised ramp's vibrant midpoint reflects the cluster's actual chromatic peak, not its median.
- **Default `max_accent_slots` raised from 4 to 8** to fit eyes, weapons, and rim lights on detailed character sprites.
- **UI trimmed.** `Share shadow anchor` and `Share highlight anchor` checkboxes removed from the dialog (both still on by default; toggle via CLI if needed). Dialog now has eight visible controls instead of ten.
- CLI: removed `accent_chroma_mad`. Added `accent_cluster_floor`.

## v0.4 — Accent preservation

- New `Preserve accents` toggle (default ON). Detects rare, high-chroma source colours via OKLCh chroma MAD outlier test combined with rarity score, and reserves them as standalone palette entries instead of folding them into a ramp.
- New `Accent slots` field (default 4) caps how many entries the script may reserve for accents. Hard internal cap of `floor((n_chromatic - 1) / 3)` ensures ramps still get at least two-thirds of the chromatic pool.
- Total-colours budget mode subtracts reserved accent slots from the target so palette size honours the user's cap. If accents would starve the ramp budget, the lowest-score accents are dropped first.
- Reinsertion is duplicate-aware: if an accent's exact RGB or OKLab ΔE neighbour is already present in the synthesised palette, it reuses that index rather than emitting a duplicate.
- Palette ordering: `[α] [shared dark] [ramps] [shared light] [accents] [grey]`. Accents sit before grey so they read as a distinct vivid block in Aseprite's palette panel.
- CLI: new `accent_detection`, `max_accent_slots`, `accent_chroma_mad`, `accent_score_threshold`, `accent_tolerance` params.

## v0.3 — Total-colours undershoot fix

- Per-ramp stop cap raised from 8 to 16 (was choking the budget when ramp count was small, producing palettes far below the requested target).
- `Total colours` solver now distributes leftover budget to ramps with the widest source lightness span before clamping. Ramps that cover broader tonal range get more stops; flatter ramps stay compact.
- Internal `stop_to_pal` key spacing widened to accommodate the higher per-ramp cap.

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

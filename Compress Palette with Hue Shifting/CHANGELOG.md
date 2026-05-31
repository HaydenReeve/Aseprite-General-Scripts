# Changelog

## v0.8 — Sparse-cluster accent promotion

- **Tiny vivid clusters now render verbatim instead of being synthesised into a desaturated ramp.** A 2-pixel saturated eye-green (`#37946E`) was previously bucketed by k-means into its own hue cluster, given a full 7-stop ramp, and the source pixels remapped to a desaturated synthesised stop (`#659979`), reading as hazel. The new `promote_sparse_clusters` pass detects clusters that have at most 6 unique members AND total pixel weight ≤ `min(2% of opaque, 64)` AND max member chroma ≥ `sparse_cluster_chroma_gate` (0.10), then promotes every member with chroma ≥ `accent_cluster_floor` (0.06) to a verbatim accent. The cluster is dropped, freeing a ramp slot.
- **`verbatim` accents bypass `accent_tolerance` deduping** in `flatten_palette` so a sparse-promoted source colour can never be merged into a near-by ramp stop. Exact-RGB matching against existing palette entries is still honoured (no duplicate emission).
- **Slot budget is balanced.** Sparse promotion is capped at `floor(slots_left × 0.5)` (minimum 2) so per-cluster outlier promotion still has room to rescue accents from inside larger clusters.
- **CLI:** new `sparse_cluster_chroma_gate` param. The existing `accent_cluster_floor` is reused as the per-member threshold.

## v0.7 — Pixel-art contrast preservation

- **`Preserve contrast` toggle (default ON).** Adjacent regions with different identities (e.g. warm skin vs neutral shirt) were collapsing into visually similar near-white blobs because each chromatic ramp's top stop was being shared into one weighted-average light entry with OKLab ΔE ≈ 0.025 from the grey ramp's top. The toggle disables `shared_highlight` for the run so each chromatic ramp keeps its own distinct top, lowers `L_hi_abs` from 0.92 to 0.86 so warm tops stay coloured rather than bleached, and asymmetrically raises the highlight-side chroma-bell floor from 0.25 to 0.45 so ramp tops carry their hue identity. The shadow side is unchanged so darks don't pick up a coloured rim.
- **Accent tolerance tightened from 0.07 to 0.04.** With the lower highlight L cap, ramp midpoints sit closer to several source accents (e.g. eye reds at L≈0.46). The wider tolerance was deduping legitimate accents into ramp stops; the new tolerance keeps the source colour as a standalone palette entry so the eye/rim accent renders verbatim.
- **CLI:** new `preserve_contrast`, `contrast_l_hi_abs`, `contrast_highlight_bell_floor` params. Dialog gains a single `Preserve contrast` checkbox.
- **Internal:** the highlight bell floor is now asymmetric (`shadow_bell_floor` const; `highlight_bell_floor` driven by config), so future tuning of one extreme doesn't disturb the other.

## v0.6 — Multi-frame correctness and chroma-led accents

- **Frame-composited histogram.** `collect_histogram` now walks every frame via `Image:drawSprite` instead of reading raw cel pixels. This matches what an exporter sees: hidden layers, overpainted regions, and stray cels under upper layers no longer pollute the histogram, and a colour visible on multiple frames is counted on each frame so frame-stable accents (eye glints, rim lights) carry their true visual weight. Every entry now carries a `frames` field with the number of distinct frames it appears on.
- **Accents are chroma-led with frame gates, not frame rewards.** Previously, visibility and frame coverage were *additive rewards* in the salience score. Common skin tones with high frame coverage outscored vivid rare colours, defeating the entire point of the accent slot. Now the score is dominated by chroma percentile (S_c), with a small frame-stability tiebreak (`0.85..1.0`). Single-frame singletons on multi-frame sprites are gated out as AA noise; very common colours (≥ 12 % of opaque pixels) are gated out because ramps will handle them.
- **Initial selector reserves half the slots for per-cluster promotion.** The cluster-promotion pass is the only mechanism that can rescue intra-cluster vivid outliers (e.g. an eye red trapped inside a brown hue cluster). With `max_accent_slots = 8`, the initial sprite-wide selector now takes at most 4, leaving 4 for promotion. The initial threshold is raised to `0.80` so only sprite-wide statistical outliers qualify.
- **Per-cluster floor lowered from 0.10 to 0.06.** Catches mid-chroma vivid colours (e.g. `C ≈ 0.07-0.10`) that previously slipped past promotion.
- **Auto ramp count scales with target_colours.** Elbow-k was producing as few as 2 chromatic ramps when target was 64, bottlenecking the palette at ~16 stops per ramp and ~30 unique output colours. Auto mode now enforces a floor of `~sqrt(target_colours - accents)` ramps in `Total colours` mode, so a 64-colour budget yields ~8 ramps rather than 2.
- **CLI: new `debug=1` flag.** When set, the script prints histogram counts, accent picks (with C/w/frames), and final palette size. Useful when tuning the per-sprite balance.

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

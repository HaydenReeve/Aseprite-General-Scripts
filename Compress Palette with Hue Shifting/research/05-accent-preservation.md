# 05 — Accent Colour Detection & Preservation During Palette Reduction

> **Purpose:** Research report informing a Lua extension to the v0.2  
> *Compress Palette with Hue Shifting* script for Aseprite. The extension  
> must detect the small handful of rare, highly-saturated "accent" colours  
> in a sprite's palette and ensure they survive the OKLab hue-clustering  
> and ramp-synthesis pipeline.  
> **Date:** 2025-07  
> **Relates to:** `design.md`, `01-oklab-color-science.md`, `04-ramp-detection-grouping.md`

---

## Table of Contents

1. [The Problem in Concrete Terms](#1-the-problem-in-concrete-terms)
2. [Detection Algorithms](#2-detection-algorithms)
   - 2.1 Chroma Outliers (OKLCh)
   - 2.2 Frequency Outliers
   - 2.3 Spatial Salience
   - 2.4 Local Contrast (ΔE neighbours)
   - 2.5 Density-Based Outliers (DBSCAN-style)
   - 2.6 Combined Salience Score
3. [Preservation Strategies](#3-preservation-strategies)
4. [Specific References & Existing Implementations](#4-specific-references--existing-implementations)
5. [Concrete Recommendation for Our Script](#5-concrete-recommendation-for-our-script)

---

## 1. The Problem in Concrete Terms

### 1.1 Why Frequency-Weighted k-Means Discards Rare Colours

The v0.2 pipeline runs **circular k-means on OKLCh hue, weighted by pixel
frequency** (`design.md §Hue clustering`). A k-means centroid is pulled toward the
weighted centre-of-mass of its Voronoi cell; the cost function minimised is

```
WCSS = Σ_i w_i · d(h_i, centroid_{assign(i)})²
```

where `w_i` is the pixel count of colour `i`. This is correct for preserving the
*modal* hue family but is structurally blind to outliers with tiny `w_i`.

**Three failure modes follow:**

1. **Absorption.** A single neon-red pixel (`C ≈ 0.28`, 3 pixels) sits inside the
   Voronoi cell of the main red/orange ramp (thousands of pixels). Its hue pulls the
   centroid by ≈ 0.003° — imperceptible. During ramp synthesis, `build_chromatic_ramp`
   takes `C_base = percentile(Cs, 0.75)`, which is dominated by the duller cluster
   members. The neon red is remapped to the nearest ramp stop — a desaturated terracotta.

2. **Merging.** With Auto-k (elbow method), a rare violet eye-glow and the main blue
   ramp sit on adjacent hues; the elbow prefers `k` that merges them. The violet is
   folded into "blue" and its `C ≈ 0.26` gets averaged away.

3. **Remap clamp.** Even if a cluster were formed, `build_remap` constrains each
   source colour to the stops of its assigned ramp only (`design.md §Pixel remap`).
   A synthetic ramp stop is never exactly the accent colour; the closest stop within
   the ramp may be ΔE ≈ 0.08–0.15 away perceptually — enough to mute a vibrant rim
   light completely.

### 1.2 Human Visual Attention and Chroma Outliers

The Human Visual System (HVS) is exquisitely sensitive to **local chroma contrast**,
not absolute chroma. Three well-established mechanisms drive this:

**Opponent-colour channels (Hering, 1878 / De Valois & De Valois, 1993).**
The L–M (red–green) and S–(L+M) (blue–yellow) post-receptoral channels respond to
*chromatic contrast against a surround*. A small patch of high chroma against a
low-chroma surround fires the opponent channels maximally, even if the patch covers
< 1% of visual area. This is why a single saturated pixel on a muted sprite is
immediately noticed.

**Itti–Koch saliency maps (Itti, Koch & Niebur, 1998).**
The landmark paper "A model of saliency-based visual attention for rapid scene
analysis" (IEEE Trans. Pattern Anal. Mach. Intell., 20(11):1254–1259,
doi: 10.1109/34.730558) proposes a biologically plausible bottom-up saliency system.
It computes centre-surround feature maps across multiple scales for intensity, colour
(opponent red–green and blue–yellow), and orientation. These are combined into a
**topographic saliency map** via a dynamical winner-take-all neural network. The key
insight relevant here: **chroma outliers** — regions whose colour differs strongly
from a local neighbourhood — spike the colour saliency channel independently of
spatial frequency. Rare pixels that would be discarded by frequency-weighted
clustering are exactly the pixels that dominate saliency maps.

**Pop-out preattentive effect (Treisman & Gelade, 1980).**
A single highly-chromatic item in a field of achromatic or low-chroma distractors is
detected in < 200 ms regardless of display size — a hallmark of preattentive feature
processing. Pixel artists exploit this consciously.

### 1.3 Pixel-Art-Specific Framing

Pixel artists place accents deliberately in roles where the HVS pop-out effect is
the *entire point*:

| Role | Typical description | Why it matters |
|---|---|---|
| **Rim light** | Single bright saturated halo on a silhouette edge | Creates 3-D separation from background |
| **Specular highlight** | 1–4 pixels of near-white, often hue-shifted toward light colour | Sells surface material (metal, glass, skin) |
| **Eye sparkle** | 1–3 bright pixels (saturated accent or near-white) | Establishes character's "life"; most read first |
| **Magic / VFX glow** | Oversaturated bloom aura, neon trails | Genre/power communication |
| **Accent piping** | Thin saturated outline on costume/armour | Creates visual interest in large silhouettes |
| **Status colour** | Saturated red on health bar, gold on coin | Immediate game-state communication |

In all cases: **few pixels, maximum saturation relative to the rest of the sprite**.
A vanilla palette quantiser that weights by pixel count treats these as statistical
noise and discards them. The goal of this extension is to treat them as *signal*.

---

## 2. Detection Algorithms

> All algorithms operate on the `entries` array already computed in step 2 of the
> v0.2 pipeline: each entry has fields `{key, r, g, b, w, L, A, B, C, h}`.
> OKLCh `C` (chroma) is already available. All pseudocode is Lua 5.4 compatible
> (no tables-of-tables beyond what the existing script uses, no `require`, no FFI).

---

### 2.1 Chroma Outliers (OKLCh)

**Principle.** Compute a robust central tendency and spread of `C` across all
chromatic entries; flag entries whose `C` exceeds a threshold as accent candidates.

Four statistical methods, in order of robustness:

#### 2.1.A Percentile Threshold

Simplest approach: sort `C` values and flag anything above the P-th percentile.
Not robust to bimodal chroma distributions.

```lua
local function flag_chroma_percentile(entries, percentile_threshold, ach_thresh)
    local cs = {}
    for _, e in ipairs(entries) do
        if e.C >= ach_thresh then cs[#cs + 1] = e.C end
    end
    table.sort(cs)
    if #cs == 0 then return {} end
    local idx = math.max(1, math.floor(percentile_threshold * #cs))
    local cutoff = cs[idx]   -- e.g. 90th percentile → flag top 10%
    local accents = {}
    for _, e in ipairs(entries) do
        if e.C > cutoff then accents[#accents + 1] = e end
    end
    return accents
end
-- Suggested call: flag_chroma_percentile(entries, 0.90, cfg.achromatic_threshold)
```

**Source:** Standard descriptive statistics. Applied to palette analysis in
Mokrzycki & Tatol, "Colour Difference ΔE — A Survey", *Machine Graphics &
Vision* 20(4), 2011.

---

#### 2.1.B Z-Score on Chroma

Flag entries whose `C` exceeds `mean + k·σ`. Sensitive to heavy tails (outliers
inflate `σ`), so less robust than MAD.

```lua
local function flag_chroma_zscore(entries, k_sigma, ach_thresh)
    local sum, sum2, n = 0, 0, 0
    for _, e in ipairs(entries) do
        if e.C >= ach_thresh then
            sum  = sum  + e.C
            sum2 = sum2 + e.C * e.C
            n = n + 1
        end
    end
    if n < 2 then return {} end
    local mean = sum / n
    local std  = math.sqrt(math.max(0, sum2/n - mean*mean))
    local accents = {}
    for _, e in ipairs(entries) do
        if e.C - mean > k_sigma * std then accents[#accents + 1] = e end
    end
    return accents
    -- Typical k_sigma: 2.0 (flag top ~2.3%) or 1.5 (flag top ~6.7%)
end
```

---

#### 2.1.C Median Absolute Deviation (MAD) ← **Recommended**

MAD is resistant to outliers skewing the scale estimate. For Gaussian data,
`σ̂ ≈ 1.4826 × MAD` (Rousseeuw & Croux, 1993).

```lua
local function flag_chroma_mad(entries, k_mad, ach_thresh)
    local cs = {}
    for _, e in ipairs(entries) do
        if e.C >= ach_thresh then cs[#cs + 1] = e.C end
    end
    if #cs < 2 then return {} end
    table.sort(cs)
    -- Median of C values
    local mid = math.floor(#cs / 2)
    local median_c = (#cs % 2 == 1) and cs[mid + 1]
        or (cs[mid] + cs[mid + 1]) * 0.5
    -- Absolute deviations from median
    local devs = {}
    for _, c in ipairs(cs) do devs[#devs + 1] = math.abs(c - median_c) end
    table.sort(devs)
    local mid2 = math.floor(#devs / 2)
    local mad = math.max(1e-6,
        (#devs % 2 == 1) and devs[mid2 + 1]
        or (devs[mid2] + devs[mid2 + 1]) * 0.5)
    local threshold = median_c + k_mad * 1.4826 * mad   -- Gaussian-equivalent σ̂
    local accents = {}
    for _, e in ipairs(entries) do
        if e.C > threshold then accents[#accents + 1] = e end
    end
    return accents
    -- Suggested k_mad: 2.5  (analogous to 2.5σ for normally distributed chroma)
end
```

**Source:**
Rousseeuw, P.J. & Croux, C. (1993). "Alternatives to the median absolute deviation."
*J. Am. Stat. Assoc.*, 88(424):1273–1283. doi: 10.1080/01621459.1993.10476408.
Wikipedia: "Median absolute deviation" — k = 1.4826 is the standard Gaussian scale
factor.

---

#### 2.1.D Tukey Fences (IQR Method)

Flag values above `Q3 + k × IQR`. Tukey (1977): k = 1.5 = "mild outlier";
k = 3.0 = "extreme outlier".

```lua
local function flag_chroma_tukey(entries, k_tukey, ach_thresh)
    local cs = {}
    for _, e in ipairs(entries) do
        if e.C >= ach_thresh then cs[#cs + 1] = e.C end
    end
    if #cs < 4 then return {} end
    table.sort(cs)
    local n = #cs
    local q1 = cs[math.max(1, math.floor(n * 0.25))]
    local q3 = cs[math.min(n, math.floor(n * 0.75))]
    local fence = q3 + k_tukey * (q3 - q1)
    local accents = {}
    for _, e in ipairs(entries) do
        if e.C > fence then accents[#accents + 1] = e end
    end
    return accents
end
-- Suggested: flag_chroma_tukey(entries, 1.5, cfg.achromatic_threshold)
```

**Source:** Tukey, J.W. (1977). *Exploratory Data Analysis*. Addison-Wesley.
The `Q3 + 1.5·IQR` fence is the standard box-plot outlier definition.

---

### 2.2 Frequency Outliers (Rare + Bright)

**Principle.** A colour used by only 2–5 pixels AND with high chroma is a strong
accent candidate regardless of whether its chroma is a global outlier. We work in the
`(log w, C)` plane and look for the "low-frequency, high-chroma" quadrant.

```lua
-- Flag entries in the low-frequency, high-chroma quadrant.
-- freq_percentile: bottom fraction of pixel counts considered "rare" (e.g. 0.25)
-- chroma_percentile: top fraction of chromas considered "vivid" (e.g. 0.25)
local function flag_frequency_chroma_quadrant(entries, freq_pct, chroma_pct, ach_thresh)
    local ws, cs = {}, {}
    for _, e in ipairs(entries) do
        if e.C >= ach_thresh then
            ws[#ws + 1] = e.w
            cs[#cs + 1] = e.C
        end
    end
    if #ws == 0 then return {} end
    table.sort(ws)
    table.sort(cs)
    local freq_cutoff   = ws[math.max(1, math.floor(freq_pct * #ws))]
    local chroma_cutoff = cs[math.min(#cs, math.floor((1 - chroma_pct) * #cs) + 1)]
    local accents = {}
    for _, e in ipairs(entries) do
        if e.C >= ach_thresh
            and e.w   <= freq_cutoff
            and e.C   >= chroma_cutoff then
            accents[#accents + 1] = e
        end
    end
    return accents
    -- Suggested: freq_pct = 0.25, chroma_pct = 0.25
end
```

**Rationale / source.** This is the palette-domain analogue of libimagequant's
`liq_image_set_importance_map`: the library scales each pixel's histogram contribution
by an 8-bit importance weight, allowing rare-but-important pixels to punch above
their frequency weight (`imagequant-sys/libimagequant.h`, ImageOptim/libimagequant,
main branch). Our quadrant method does the equivalent at the unique-colour level.

---

### 2.3 Spatial Salience (Adapted Itti–Koch)

**Principle.** A colour that is frequently *surrounded* by very different colours in
image space generates high local contrast — it is spatially salient. This is the
palette-domain adaptation of the Itti–Koch colour saliency channel (centre-surround
opponent differences across scales).

**Source:**
Itti, L., Koch, C. & Niebur, E. (1998). "A model of saliency-based visual attention
for rapid scene analysis." *IEEE Trans. Pattern Anal. Mach. Intell.*, 20(11):1254–1259.
doi: 10.1109/34.730558.

```lua
-- For each pixel, measure OKLab distance to its 4-connected neighbours.
-- Accumulate per colour key: mean spatial ΔE (OKLab) across all pixel occurrences.
-- Returns: avg_delta table, key -> mean spatial OKLab distance to neighbours.
local function compute_spatial_salience(sprite, lab_cache)
    -- lab_cache: rgb_key -> {L, A, B}  (build from entries before calling)
    local sum_delta = {}  -- key -> cumulative OKLab ΔE to neighbours
    local count_nb  = {}  -- key -> number of (pixel, neighbour) pairs

    for _, layer in ipairs(sprite.layers) do
        if layer.isVisible and not layer.isReference then
            for _, cel in ipairs(layer.cels) do
                local img = cel.image
                if not img then goto next_cel end
                local W, H = img.width, img.height
                for y = 0, H - 1 do
                    for x = 0, W - 1 do
                        local px = img:getPixel(x, y)
                        if pc.rgbaA(px) == 0 then goto next_px end
                        local key0 = pc.rgbaR(px)*65536 + pc.rgbaG(px)*256 + pc.rgbaB(px)
                        local lab0 = lab_cache[key0]
                        if not lab0 then goto next_px end
                        -- 4-connected neighbours
                        for _, d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                            local nx, ny = x + d[1], y + d[2]
                            if nx >= 0 and nx < W and ny >= 0 and ny < H then
                                local npx = img:getPixel(nx, ny)
                                if pc.rgbaA(npx) == 0 then goto next_nb end
                                local nkey = pc.rgbaR(npx)*65536 + pc.rgbaG(npx)*256 + pc.rgbaB(npx)
                                local nlab = lab_cache[nkey]
                                if nlab then
                                    local dL = lab0[1]-nlab[1]
                                    local dA = lab0[2]-nlab[2]
                                    local dB = lab0[3]-nlab[3]
                                    local delta = math.sqrt(dL*dL + dA*dA + dB*dB)
                                    sum_delta[key0] = (sum_delta[key0] or 0) + delta
                                    count_nb[key0]  = (count_nb[key0]  or 0) + 1
                                end
                                ::next_nb::
                            end
                        end
                        ::next_px::
                    end
                end
                ::next_cel::
            end
        end
    end

    local avg_delta = {}
    for key, s in pairs(sum_delta) do
        avg_delta[key] = s / math.max(1, count_nb[key] or 1)
    end
    return avg_delta
end
```

> **Performance note.** This pass is O(W·H·cels). For pixel-art sprites
> (typically 16–512 px per side) this is fast. For sprites larger than 1 k × 1 k,
> consider sampling every 2nd pixel or only the first frame.

---

### 2.4 Local Contrast (ΔE to Palette Neighbours — Palette-Domain Approximation)

When spatial iteration is too slow, an approximation works at palette level only:
for each colour, compute its mean OKLab distance to its K nearest palette peers.
High mean distance → isolated in colour space → accent candidate.

```lua
-- Returns: scores indexed by entry index (1..#entries), values = mean ΔE to K nearest.
local function palette_local_contrast(entries, K)
    K = K or 5
    local result = {}
    for i, ei in ipairs(entries) do
        local dists = {}
        for j, ej in ipairs(entries) do
            if i ~= j then
                local dL = ei.L - ej.L
                local dA = ei.A - ej.A
                local dB = ei.B - ej.B
                dists[#dists + 1] = math.sqrt(dL*dL + dA*dA + dB*dB)
            end
        end
        table.sort(dists)
        local sum, cnt = 0, math.min(K, #dists)
        for k = 1, cnt do sum = sum + dists[k] end
        result[i] = cnt > 0 and (sum / cnt) or 0
    end
    return result  -- index -> mean OKLab ΔE to K nearest palette peers
end
```

**Interpretation.** A colour whose 5 nearest palette peers are all ΔE > 0.12 away
is *isolated* in OKLab space and will not be well approximated by any ramp stop.

**Source:** Zolliker & Simon (2007) show that local colour distinctiveness (mean
distance to neighbours) is the primary perceptual metric for colour preservation in
gamut mapping — our palette-domain metric is their "local colour distinctiveness"
applied to discrete palette entries.

---

### 2.5 Density-Based Outliers (DBSCAN-Style)

**Principle.** DBSCAN (Ester et al., 1996) labels points as core points (≥ minPts
neighbours within radius ε), border points, or noise. Colours labelled *noise* are
isolated in colour space — exactly what accent colours are. We need only the
noise-labelling half; full cluster enumeration is unnecessary.

```lua
-- Lightweight DBSCAN noise labelling. O(n²) but n = palette size (< 256 in practice).
-- Returns: is_noise[i] = true if entry i has fewer than min_pts peers within eps.
local function dbscan_noise_labels(entries, eps, min_pts)
    local eps2 = eps * eps
    local is_noise = {}
    for i, ei in ipairs(entries) do
        local count = 0
        for j, ej in ipairs(entries) do
            if i ~= j then
                local dL = ei.L - ej.L
                local dA = ei.A - ej.A
                local dB = ei.B - ej.B
                if dL*dL + dA*dA + dB*dB <= eps2 then
                    count = count + 1
                    if count >= min_pts then break end
                end
            end
        end
        is_noise[i] = (count < min_pts)
    end
    return is_noise
    -- Suggested: eps = 0.08 (OKLab units), min_pts = 2
    -- A colour with no other palette colour within OKLab 0.08 is a strong candidate.
end
```

**Parameter guidance for OKLab:**
- `eps = 0.06`: tight — only near-duplicates cluster; most accents flagged as noise.
- `eps = 0.10`: loose — main-ramp colours cluster; only extreme outliers are noise.
- `min_pts = 2`: even a 2-stop stub accent ramp (two close colours) is not flagged.

**Source:** Ester, M., Kriegel, H-P., Sander, J. & Xu, X. (1996). "A density-based
algorithm for discovering clusters in large spatial databases with noise." *KDD-96*,
pp. 226–231. (ACM Test of Time Award 2014.)

---

### 2.6 Combined Salience Score

Weight and blend the individual signals into a single score `S ∈ [0, 1]` per entry.
The three most independent signals are:

| Component | Symbol | Captures |
|---|---|---|
| Chroma outlier (MAD) | `S_c` | High chroma relative to palette median |
| Rarity | `S_r` | Low pixel count (rare in image) |
| Spatial contrast | `S_s` | Surrounded by different colours in image space |

```lua
-- Compute combined salience scores for all entries.
-- avg_spatial_delta: key->mean_spatial_OKLab (from §2.3), or nil to omit S_s.
-- Returns: scores[i] ∈ [0,1] for each entry index.
local function compute_salience_scores(entries, ach_thresh, avg_spatial_delta)
    -- === S_c: MAD chroma outlier ===
    local cs = {}
    for _, e in ipairs(entries) do cs[#cs + 1] = e.C end
    table.sort(cs)
    local n   = #cs
    local mid = math.floor(n / 2)
    local median_c = (n % 2 == 1) and cs[mid+1] or (cs[mid] + cs[mid+1]) * 0.5
    local devs = {}
    for _, c in ipairs(cs) do devs[#devs+1] = math.abs(c - median_c) end
    table.sort(devs)
    local mid2 = math.floor(n / 2)
    local mad  = math.max(1e-6,
        (n % 2 == 1) and devs[mid2+1] or (devs[mid2] + devs[mid2+1]) * 0.5)
    local sigma_hat = 1.4826 * mad

    -- === S_r: Rarity (inverse log-frequency) ===
    local max_w = 1
    for _, e in ipairs(entries) do if e.w > max_w then max_w = e.w end end
    local log_max = math.log(math.max(1, max_w))

    -- === S_s: Spatial contrast ===
    local max_spatial = 0
    if avg_spatial_delta then
        for _, v in pairs(avg_spatial_delta) do
            if v > max_spatial then max_spatial = v end
        end
    end

    local scores = {}
    for i, e in ipairs(entries) do
        -- S_c: z-score above median, clamped at 3σ → [0,1]
        local z   = (e.C - median_c) / sigma_hat
        local S_c = math.max(0, math.min(1, z / 3.0))

        -- S_r: 1 - normalised log frequency → [0,1], high for rare colours
        local log_w = math.log(math.max(1, e.w))
        local S_r   = 1.0 - log_w / math.max(1e-6, log_max)

        -- S_s: normalised spatial contrast → [0,1]
        local S_s = 0.0
        if avg_spatial_delta and max_spatial > 0 then
            S_s = math.min(1.0, (avg_spatial_delta[e.key] or 0) / max_spatial)
        end

        -- Weighted blend
        local w_c, w_r, w_s = 0.5, 0.3, 0.2
        if not avg_spatial_delta then w_c, w_r, w_s = 0.6, 0.4, 0.0 end
        scores[i] = w_c * S_c + w_r * S_r + w_s * S_s
    end
    return scores
end

-- Flag entries as accent candidates if score exceeds threshold.
local function flag_by_salience(entries, scores, threshold)
    local accents = {}
    for i, e in ipairs(entries) do
        if scores[i] >= threshold then accents[#accents + 1] = e end
    end
    return accents
    -- Suggested threshold: 0.55 (conservative) … 0.45 (aggressive)
end
```

**Design notes:**
- `S_c` dominates because absolute chroma is the most semantically clear accent
  signal in pixel art.
- `S_r` guards against treating common saturated colours (e.g. an entirely neon-green
  sprite) as accents.
- `S_s` is the most expensive but most precise; make it optional via a user toggle or
  only run it on sprites smaller than a size threshold.
- When `max_accent_slots` is reached, take the top-N entries ranked by score.

---

## 3. Preservation Strategies

### 3.1 Reserved Slots (Pre-Allocation)

Extract detected accent colours from the chromatic pool before clustering. After ramp
synthesis, append them as verbatim standalone palette entries. Pixel remap routes
their pixels directly, bypassing ramp-stop nearest-neighbour search.

```lua
local function partition_accents(entries, scores, threshold, max_slots)
    -- Sort descending by score so top-N are taken when max_slots is exceeded.
    local idx_sorted = {}
    for i = 1, #entries do idx_sorted[i] = i end
    table.sort(idx_sorted, function(a, b) return scores[a] > scores[b] end)

    local is_accent = {}
    local taken = 0
    for _, i in ipairs(idx_sorted) do
        if scores[i] >= threshold and taken < max_slots then
            is_accent[i] = true
            taken = taken + 1
        end
    end

    local accent_entries, normal_entries = {}, {}
    for i, e in ipairs(entries) do
        if is_accent[i] then accent_entries[#accent_entries + 1] = e
        else                  normal_entries[#normal_entries + 1] = e end
    end
    return accent_entries, normal_entries
end
```

**Pros:** Simple; guarantees exact RGB retention; zero ΔE for accent pixels.
**Cons:** Accent colours are isolated entries with no ramp neighbours.

---

### 3.2 Protected (Fixed) Centroids in k-Means

Pin detected accent colours as immovable centroids in hue k-means. In the M-step,
skip centroid update for pinned slots. This is the hue-domain equivalent of
`liq_image_add_fixed_color()` in libimagequant:

> `liq_image_add_fixed_color(img, color)`: "Adds a color guaranteed to be in the
> final palette. Acts as a fixed centroid that other colors cluster around but cannot
> displace."
> — `imagequant-sys/libimagequant.h`, ImageOptim/libimagequant (confirmed in
>   `src/hist.rs::add_fixed_color` and `src/quant.rs::with_fixed_colors`).

```lua
-- Extended kmeans_hue with fixed centroid hues.
-- fixed_hues: array of hue values (degrees) to pin.
-- These centroids are never updated in the M-step.
local function kmeans_hue_with_fixed(entries, k, max_iter, seed, fixed_hues)
    fixed_hues = fixed_hues or {}
    local n_fixed = #fixed_hues
    -- Total centroids = n_fixed + (k - n_fixed) free
    -- Initialise: slots 1..n_fixed = fixed_hues; slots n_fixed+1..k = k-means++
    local centroids = {}
    for i, h in ipairs(fixed_hues) do centroids[i] = h end
    -- ... k-means++ seeding for remaining slots, then iterate ...
    -- In M-step: for j = 1, n_fixed do skip update end
    -- (Extend existing kmeans_hue implementation)
end
```

**Pros:** Accents influence clustering naturally; nearby colours flow to them.
**Cons:** Wastes a cluster slot; may split a natural ramp if accent hue falls inside.

---

### 3.3 Importance-Weighted Quantisation

Scale each entry's effective weight before clustering:
`w_eff = w × importance_scale(score)`, where `importance_scale` maps
`score ∈ [0,1] → [1, boost_max]`.

```lua
local function boost_weights_by_salience(entries, scores, boost_max)
    boost_max = boost_max or 10.0
    for i, e in ipairs(entries) do
        e.w_original = e.w
        e.w = e.w * (1.0 + (boost_max - 1.0) * scores[i])
    end
end
-- Restore with: e.w = e.w_original  (before building ramps from cluster Cs/Ls).
```

**Reference:** libimagequant's `liq_image_set_importance_map` multiplies histogram
bin accumulation by the importance byte value (0–255) before quantisation, allowing
rare-but-important pixels to influence palette selection proportionally to their
visual importance rather than their pixel count.

**Pros:** Elegant; no structural pipeline change. Accent colours pull centroids
without leaving the pool.
**Cons:** May be insufficient for extremely rare colours (1–3 pixels competing against
hundreds of common ones).

---

### 3.4 Post-Hoc Reinsertion ← **Recommended for v0.3**

Run the entire v0.2 pipeline unchanged. After ramp synthesis, check each detected
accent colour: if its nearest existing ramp stop is > `accent_tolerance` ΔE away,
add it as a standalone palette entry.

```lua
local function reinsert_accents_post_hoc(accent_entries, palette_entries,
                                          remap, accent_tolerance)
    local new_entries = {}
    for _, ae in ipairs(accent_entries) do
        local best_d2 = math.huge
        for _, pe in ipairs(palette_entries) do
            local dL = ae.L - pe.L
            local dA = ae.A - pe.A
            local dB = ae.B - pe.B
            local d2 = dL*dL + dA*dA + dB*dB
            if d2 < best_d2 then best_d2 = d2 end
        end
        if math.sqrt(best_d2) > accent_tolerance then
            local new_pi = #palette_entries + #new_entries  -- 0-based
            new_entries[#new_entries + 1] = {
                r = ae.r, g = ae.g, b = ae.b, a = 255,
                L = ae.L, A = ae.A, B = ae.B,
                ramp = 0, stop = 0, is_accent = true,
            }
            remap[ae.key] = new_pi
        end
        -- If best_d < accent_tolerance: accent is already well represented → no insert.
    end
    for _, ne in ipairs(new_entries) do
        palette_entries[#palette_entries + 1] = ne
    end
end
-- Suggested accent_tolerance: 0.07 (OKLab) ≈ "just noticeable" colour difference
```

**Pros:** Non-invasive; leaves all existing ramp machinery untouched; graceful
degradation (if accent is already represented it silently skips it).
**Cons:** Palette size may exceed budget if many accents are detected.

---

### 3.5 Asymmetric Stub Ramps

When an accent sits within an existing hue family but at much higher chroma, build a
1–2 stop "stub ramp" at high chroma hanging off the main palette, giving artists a
dark sibling for edge anti-aliasing.

```lua
local function build_stub_ramp(ae, parent_base_h, cfg)
    if circular_dist(ae.h, parent_base_h) > 25 then return nil end
    -- Highlight stop: the accent itself
    local r1, g1, b1, L1, C1, h1 = gamut_clip_oklch(ae.L, ae.C, ae.h)
    local stop_hi = { r=r1, g=g1, b=b1, L=L1, C=C1, h=h1, t=1.0 }
    -- Shadow stop: slightly darker, less chromatic sibling
    local L2 = math.max(0.05, ae.L - 0.12)
    local r2, g2, b2 = gamut_clip_oklch(L2, ae.C * 0.8, ae.h)
    local stop_lo = { r=r2, g=g2, b=b2, L=L2, C=ae.C*0.8, h=ae.h, t=0.4 }
    return {
        stops = {stop_lo, stop_hi},
        base_h = ae.h,
        kind = "chromatic",
        weight = ae.w,
        is_stub = true,
    }
end
```

**Use case:** A neon-red rim light (C = 0.27) in the "red" hue family vs. the main
ramp's C_base = 0.14. The 2-stop stub gives the artist a usable dark-edge colour
while preserving the vivid accent. Ordered after normal ramps but before the grey ramp.

---

## 4. Specific References & Existing Implementations

### 4.1 libimagequant / pngquant

**Repository:** ImageOptim/libimagequant — https://github.com/ImageOptim/libimagequant  
**API reference:** https://pngquant.org/lib/ | Licence: GPL v3 / commercial dual.

Two C API functions directly map to our strategies:

**`liq_image_set_importance_map(img, buffer[], buffer_size, ownership)`**
(`imagequant-sys/libimagequant.h`, confirmed in repository):
Accepts a `width×height` byte array. Value 255 = maximum importance; 0 = excluded.
Internally, each byte scales the pixel's contribution to histogram bin accumulation
before quantisation. This is the production implementation of §3.3 importance
weighting applied at the pixel level rather than the unique-colour level.

**`liq_image_add_fixed_color(img, color)`**
(`imagequant-sys/libimagequant.h`; Rust: `src/hist.rs::add_fixed_color`,
`src/quant.rs::with_fixed_colors`):
Forces a specific RGBA colour into the final palette, seeded as a fixed centroid.
This is the production implementation of §3.2 protected centroids.

### 4.2 Color Thief — Median-Cut Variant

Color Thief (https://lokeshdhakar.com/projects/color-thief/) uses Heckbert's 1979
median-cut. Each cut selects the box with the largest `volume × population` product.
Accent colours, being rare, rarely have the largest product and are split last or
never. This is cited as a negative example of frequency-dominated quantisation — the
identical structural failure as our frequency-weighted hue k-means.

### 4.3 RgbQuant.js

**Repository:** leeoniya/RgbQuant.js — https://github.com/leeoniya/RgbQuant.js
Licence: MIT.

RgbQuant's `method: 2` divides the image into a spatial grid and weights each
sub-region equally by *area* (not pixel count). This prevents large uniform
backgrounds from dominating palette generation — the coarse-granularity equivalent
of our spatial salience pre-pass (§2.3). `colorDist` supports Euclidean-RGB,
Manhattan, and a weighted-Euclidean Lab approximation, but no OKLab.

### 4.4 Mark Ferrari and the Lospec Community

**Mark Ferrari — GDC 2016 "The Aesthetics of Game Art":**
Ferrari's VGA-era work at LucasArts (*Loom*, 1990; *The Secret of Monkey Island*,
1990) required hand-reserving 2–4 palette slots for "jewel" colours — highly
saturated entries not part of any lightness ramp, placed at magic effects and
character eyes. This is exactly the reserved-slots strategy (§3.1).

**Slynyrd, "Pixelblog #1 — Color Palettes" (2018):**
> "Accent colours … are the odd ones out. They're not part of any ramp. They exist
> to draw the eye to a single focal point."
> — https://slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes

**Lospec Palette List** (https://lospec.com/palette-list): community palettes are
frequently tagged "accent" and "spot colour"; the practitioner convention is design
main ramps first, then add 1–3 vivid accent colours outside the ramp structure.

### 4.5 Adobe Capture / Android Palette API

Android's `Palette` API (https://developer.android.com/training/material/palette-colors)
extracts palettes with named targets including "Vibrant" (`mTargetSaturation = 1.0`,
high chroma), "Light Vibrant", and "Muted". Each target uses an explicit chroma +
lightness range, scored and ranked by pixel coverage within those constraints — a
production implementation of our combined salience score with chroma weighted highest.
Adobe Capture's extraction mode uses the same underlying logic.

### 4.6 Academic References

**Celebi, M.E. (2011).** "Improving the performance of k-means for color
quantization." *Image Vis. Comput.*, 29(4):260–271. doi: 10.1016/j.imavis.2010.10.002.
Demonstrates that frequency-weighted k-means outperforms median-cut but is insensitive
to rare colours; recommends pre-processing to boost rare-colour representation.

**Mojsilović, A., Hu, J. & Soljanin, E. (2002).** "Extraction of Perceptually
Important Colors and Similarity Measurement for Image Matching, Retrieval and
Analysis." *IEEE Trans. Image Processing*, 11(11):1238–1248. doi: 10.1109/TIP.2002.804513.
Proposes extracting "visually important" colours based on compactness and distinctness
in CIE Lab — direct academic antecedent of chroma-outlier detection in OKLab (§2.1).

**Zolliker, P. & Simon, K. (2007).** "Retaining Local Image Information in Gamut
Mapping Algorithms." *IEEE Trans. Image Processing*, 16(3):664–672.
doi: 10.1109/TIP.2006.891345.
Shows that local colour contrast (mean ΔE to neighbours) is the key perceptual metric
for preserving artistic intent — the palette-local-contrast metric in §2.4 is their
"local colour distinctiveness."

**Cohen-Or, D. et al. (2006).** "Color Harmonization." *ACM SIGGRAPH 2006*.
doi: 10.1145/1179352.1141933.
Palette selection for colour harmony; harmonic template fitting can inadvertently
discard accent colours falling outside template hue sectors — the same structural
problem as hue k-means.

**No specific "saliency-aware colour quantisation" paper** exists as a standalone work
in the reviewed literature as of 2025; the techniques described in §2 synthesise
results from Itti–Koch saliency (1998), Rousseeuw–Croux robust statistics (1993),
Ester et al. DBSCAN (1996), and Mojsilović et al. perceptual importance (2002).

---

## 5. Concrete Recommendation for Our Aseprite Script

### 5.1 Recommended Algorithm: Post-Hoc Reinsertion with MAD Detection

Given that v0.2 is stable and the goal is a minimal, safe extension, use
**Strategy §3.4 (Post-Hoc Reinsertion)** with **MAD chroma detection (§2.1.C)**:

- Does not modify existing clustering or ramp synthesis.
- Adds one pre-pass (detect accents from chromatic entries) and one post-pass
  (reinsert if not already well-approximated).
- Robust to edge cases (see §5.4).
- O(n log n) cost on palette; n < 256 in all practical cases.

**Modified `run()` execution order:**

```
(1) Histogram                                [unchanged]
(2) OKLab/OKLCh conversion & cache          [unchanged]
(3) Split chromatic / achromatic             [unchanged]
(3b) [NEW] Detect accent candidates          ← flag_chroma_mad + rarity filter
(3c) [NEW] Partition: accent_entries vs      ← partition_accents()
           chromatic_for_clustering
(4–9) Hue clustering, ramp synthesis,        [unchanged; use chromatic_for_clustering]
      shared anchors, grey ramp
(10) Flatten palette                         [unchanged]
(10b)[NEW] Post-hoc reinsert accents         ← reinsert_accents_post_hoc()
(11) Build remap (add accent direct mappings)[minimal addition]
(12) Apply pixels / palette                  [unchanged]
```

### 5.2 Suggested User Parameters

Add to `DEFAULT_CONFIG` and the UI dialog:

```lua
DEFAULT_CONFIG = {
    -- ... existing fields unchanged ...

    -- Accent preservation (new in v0.3):
    accent_detection  = true,   -- bool:  enable accent detection & preservation
    max_accent_slots  = 4,      -- int:   max palette entries reserved for accents
    accent_chroma_mad = 2.5,    -- float: MAD multiplier threshold (higher = fewer detected)
    -- Internal derived constant (not user-visible):
    -- accent_tolerance = 0.07  -- OKLab ΔE below which accent is already represented
}
```

**Dialog UI (visible):**
- `Preserve accents` — boolean checkbox, default ON, placed in the advanced section.
- `Accent slots` — integer spinner 0–8, default 4 (shown when toggle is ON).
- `Sensitivity` — labelled "Conservative ↔ Aggressive", maps slider 0–1 to
  `accent_chroma_mad` range [3.5 → 1.5] (fewer ↔ more accents detected).

**CLI / advanced only:**
- `accent_chroma_mad` numeric, for scripted use.
- `accent_tolerance` numeric (OKLab ΔE), default 0.07.

### 5.3 Palette Ordering and Remap Integration

**Palette ordering.** Accent entries appear *after* all chromatic ramps, *before*
the grey ramp. This preserves the existing ordering contract (`design.md §Palette
ordering`) while making accents identifiable in Aseprite's palette panel:

```
[α slot?] [shared_dark?] [ramp 1] … [ramp N] [shared_light?]
[accent 1] [accent 2] … [accent M]               ← new block
[grey ramp]
```

**Ramp assignment.** Accent entries are excluded from the chromatic pool *before*
hue k-means, so they cannot bias centroid initialisation. Insert after step 3 of
`run()`:

```lua
local accent_entries, chromatic_filtered = {}, chromatic
if cfg.accent_detection and #chromatic > 0 then
    local scores = compute_salience_scores(chromatic, cfg.achromatic_threshold, nil)
    -- Derive threshold from k_mad via MAD (pre-computed inside compute_salience_scores)
    local threshold = 0.55  -- or derived from cfg.accent_chroma_mad
    accent_entries, chromatic_filtered =
        partition_accents(chromatic, scores, threshold, cfg.max_accent_slots)
end
-- Use chromatic_filtered instead of chromatic for steps 4–9.
```

**Direct remap for accent pixels:**

```lua
-- After reinsert_accents_post_hoc, build direct mappings:
local accent_key_to_pi = {}  -- populated during reinsertion
for _, ae in ipairs(accent_entries_reinserted) do
    accent_key_to_pi[ae.key] = ae.palette_index  -- set during reinsert
end
-- Merge into remap before pixel write:
for key, pi in pairs(accent_key_to_pi) do remap[key] = pi end
```

### 5.4 Edge Cases

**A: All colours are "accent-like" (uniformly high-saturation sprite — cartoon style).**
MAD detection adapts automatically: if all chromas are high, the median and MAD are
both high, and `threshold = median + k·σ̂` rises accordingly. Fewer or zero colours
exceed it. The `max_accent_slots` cap provides a hard upper bound. Result: on a
uniformly saturated sprite, the extension is nearly a no-op.

**B: No accent colours (muted/desaturated sprite).**
All entries have similar low chroma. `flag_chroma_mad` returns empty. `accent_entries`
is empty. The extension is a complete no-op; output is identical to v0.2. Log at
debug level: `"[Accent] No accent candidates (all within 2.5σ of median chroma)."`.

**C: Accent is common (large high-chroma glow region).**
If `w` is large, `S_r` is low; combined salience is reduced. If the combined score
still clears `threshold` (chroma is very extreme), it may still be flagged — which
is correct, because an extremely saturated colour covering 15% of the sprite should
indeed be handled as a standalone entry rather than degraded by ramp averaging.

**D: Budget exhaustion (`size_mode = "Total colours"`).**
Check remaining budget before reinsertion:

```lua
local budget_remaining = cfg.target_colours - #palette_entries
local insertable = {}
for _, ae in ipairs(accent_candidates) do
    if #insertable < budget_remaining then insertable[#insertable+1] = ae end
end
-- Only reinsert up to budget_remaining accents (highest salience first).
```
If budget is zero, skip reinsertion and emit a user-visible warning:
`"Accent colours could not be preserved: palette budget exhausted. Increase target colours or reduce accent slots."`.

**E: Accent colour is near-achromatic (very pale specular highlight, C ≈ 0.01–0.03).**
The achromatic split (`e.C < cfg.achromatic_threshold`, default 0.02) routes these to
the grey ramp, where they are well represented. Accent detection operates only on the
chromatic pool; no special handling needed.

---

## Summary

Accent colours are rare, high-chroma, spatially-contrasting palette entries that
frequency-weighted k-means systematically discards via absorption, cluster merging,
and constrained remap. The HVS is disproportionately sensitive to exactly these
colours (Itti–Koch 1998 colour saliency channel; opponent pop-out; Treisman &
Gelade 1980). The minimum-viable detection algorithm is **MAD chroma outlier
detection** on OKLCh `C` values of the chromatic entry pool, optionally combined with
rarity weighting into a combined salience score. The minimum-viable preservation
strategy is **post-hoc reinsertion**: run v0.2 unchanged, then append detected accent
colours as standalone palette entries if no existing ramp stop is within OKLab ΔE 0.07
of them. Three user parameters suffice: `accent_detection` (bool), `max_accent_slots`
(int), `sensitivity` (slider → `accent_chroma_mad`). The extension is a no-op for
muted sprites and self-limiting for uniformly saturated ones.

---

## References

1. Itti, L., Koch, C. & Niebur, E. (1998). "A model of saliency-based visual
   attention for rapid scene analysis." *IEEE Trans. Pattern Anal. Mach. Intell.*,
   20(11):1254–1259. doi: [10.1109/34.730558](https://doi.org/10.1109/34.730558).

2. Rousseeuw, P.J. & Croux, C. (1993). "Alternatives to the median absolute
   deviation." *J. Am. Stat. Assoc.*, 88(424):1273–1283.
   doi: [10.1080/01621459.1993.10476408](https://doi.org/10.1080/01621459.1993.10476408).

3. Tukey, J.W. (1977). *Exploratory Data Analysis*. Addison-Wesley.

4. Ester, M., Kriegel, H-P., Sander, J. & Xu, X. (1996). "A density-based algorithm
   for discovering clusters in large spatial databases with noise." *KDD-96*,
   pp. 226–231.

5. Ottosson, B. (2020). "A perceptual color space for image processing (OKLab)."
   https://bottosson.github.io/posts/oklab/

6. ImageOptim / libimagequant (2024). `imagequant-sys/libimagequant.h`,
   `src/hist.rs`, `src/quant.rs`.
   https://github.com/ImageOptim/libimagequant (main branch, MIT/GPL).

7. Celebi, M.E. (2011). "Improving the performance of k-means for color
   quantization." *Image Vis. Comput.*, 29(4):260–271.
   doi: [10.1016/j.imavis.2010.10.002](https://doi.org/10.1016/j.imavis.2010.10.002).

8. Cohen-Or, D. et al. (2006). "Color Harmonization." *ACM SIGGRAPH 2006*.
   doi: [10.1145/1179352.1141933](https://doi.org/10.1145/1179352.1141933).

9. Mojsilović, A., Hu, J. & Soljanin, E. (2002). "Extraction of Perceptually
   Important Colors and Similarity Measurement for Image Matching, Retrieval and
   Analysis." *IEEE Trans. Image Processing*, 11(11):1238–1248.
   doi: [10.1109/TIP.2002.804513](https://doi.org/10.1109/TIP.2002.804513).

10. Zolliker, P. & Simon, K. (2007). "Retaining Local Image Information in Gamut
    Mapping Algorithms." *IEEE Trans. Image Processing*, 16(3):664–672.
    doi: [10.1109/TIP.2006.891345](https://doi.org/10.1109/TIP.2006.891345).

11. Slynyrd (2018). "Pixelblog #1 — Color Palettes."
    https://slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes

12. Android Developer Docs. "Extract color profiles with the Palette API."
    https://developer.android.com/training/material/palette-colors

13. De Valois, R.L. & De Valois, K.K. (1993). "A multi-stage color model."
    *Vision Research*, 33(8):1053–1065. doi: 10.1016/0042-6989(93)90240-W.

14. Treisman, A.M. & Gelade, G. (1980). "A feature-integration theory of attention."
    *Cognitive Psychology*, 12(1):97–136. doi: 10.1016/0010-0285(80)90005-5.
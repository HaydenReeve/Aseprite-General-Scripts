# 04 — Ramp Detection, Grouping & Synthesis

> **Scope:** Algorithms for automatically detecting colour ramps inside an
> arbitrary pixel-art sprite, grouping palette entries into ramps, mapping
> source pixels onto a compressed target palette, synthesising new hue-shifted
> ramps to replace detected ones, and choosing the right number of ramps and
> stops.  All pseudocode is written to be portable to Lua 5.4 (Aseprite's
> embedded interpreter).

---

## Table of Contents

1. [Ramp Detection from Arbitrary Images](#1-ramp-detection-from-arbitrary-images)
2. [Clustering in Perceptual Space for Ramp Assignment](#2-clustering-in-perceptual-space-for-ramp-assignment)
3. [Mapping Source Pixels to a Target Compressed Palette](#3-mapping-source-pixels-to-a-target-compressed-palette)
4. [Synthesising New Hue-Shifted Ramps](#4-synthesising-new-hue-shifted-ramps)
5. [Determining the Target Ramp Count and Stops per Ramp](#5-determining-the-target-ramp-count-and-stops-per-ramp)
6. [Reference Index](#6-reference-index)

---

## 1  Ramp Detection from Arbitrary Images

### 1.1  Cluster-by-Hue → Sort-by-Lightness (Baseline)

The simplest practical pipeline converts every palette entry to a perceptual
polar space (OKLCh: *L*, *C*, *h*), clusters on circular hue angle *h*, then
sorts each cluster by lightness *L*.  The result is one ordered list per hue
cluster — a candidate ramp.

**Why OKLCh instead of HSL/HSV?**  HSL hue is not perceptually uniform: a
fully saturated yellow and a fully saturated blue appear wildly different in
lightness yet share the same HSL "saturation = 1".  OKLab (Ottosson 2020,
[ref 1]) corrects this by deriving its coordinates from a cube-root-compressed
LMS cone model; its polar form OKLCh inherits the perceptual uniformity.

```lua
-- Pseudocode: cluster-by-hue → sort-by-lightness
-- Input:  palette  – array of {r,g,b} in [0,1]
-- Output: ramps    – array of arrays of palette indices, each ordered
--                    dark→light

local HUE_BUCKET_DEG = 30   -- degrees; tune to taste

local function oklch_of(r, g, b)
  -- sRGB → linear
  local function lin(v)
    return v <= 0.04045 and v/12.92 or ((v+0.055)/1.055)^2.4
  end
  local rl, gl, bl = lin(r), lin(g), lin(b)
  -- linear sRGB → OKLab  (Ottosson 2020)
  local l = 0.4122214708*rl + 0.5363325363*gl + 0.0514459929*bl
  local m = 0.2119034982*rl + 0.6806995451*gl + 0.1073969566*bl
  local s = 0.0883024619*rl + 0.2817188376*gl + 0.6299787005*bl
  l, m, s = l^(1/3), m^(1/3), s^(1/3)
  local L =  0.2104542553*l + 0.7936177850*m - 0.0040720468*s
  local a =  1.9779984951*l - 2.4285922050*m + 0.4505937099*s
  local b2=  0.0259040371*l + 0.7827717662*m - 0.8086757660*s
  local C  = math.sqrt(a*a + b2*b2)
  local h  = math.atan(b2, a) * 180 / math.pi   -- degrees
  if h < 0 then h = h + 360 end
  return L, C, h
end

local function detect_ramps_hue_bucket(palette)
  local buckets = {}
  for i, col in ipairs(palette) do
    local L, C, h = oklch_of(col.r, col.g, col.b)
    -- Achromatic guard: skip near-grey entries from hue clustering
    if C < 0.04 then
      -- put in a dedicated "grey" ramp
      local key = "grey"
      buckets[key] = buckets[key] or {}
      table.insert(buckets[key], {idx=i, L=L, C=C, h=h})
    else
      local bucket = math.floor(h / HUE_BUCKET_DEG)
      local key = tostring(bucket)
      buckets[key] = buckets[key] or {}
      table.insert(buckets[key], {idx=i, L=L, C=C, h=h})
    end
  end
  -- Sort each bucket dark→light
  local ramps = {}
  for _, entries in pairs(buckets) do
    table.sort(entries, function(a, b) return a.L < b.L end)
    table.insert(ramps, entries)
  end
  return ramps
end
```

**Limitations:** A fixed 30° bucket boundary may split a warm skin-tone ramp
(hues 20°–50°) across two buckets.  §2 addresses this with adaptive
clustering.

---

### 1.2  Colour Adjacency Graph → Chain Extraction

**Concept.** Build a graph *G* where nodes are palette entries and an edge
(u, v) exists if colours *u* and *v* appear in spatially adjacent pixels
in the image.  Ramps correspond to *chains* in G — paths where successive
nodes differ primarily in lightness, not hue.

This idea appears in **Huang & Lee 2015** [ref 2] who define:

> *"a ramp is a group of colors whose hues are adjacent in the palette graph,
> ordered by lightness"*

and build a binary distance matrix on the palette to find such chains.

**Algorithm sketch:**

```lua
-- Step 1: build adjacency counts from the image canvas
local function build_adjacency(image, palette_map)
  -- palette_map: pixel RGBA → palette index
  local adj = {}   -- adj[i][j] = count of i-j neighbouring pairs
  for px in image:pixels() do
    local ci = palette_map[px()]           -- index of this pixel's colour
    -- check 4-connected neighbours
    for _, np in ipairs(neighbours(image, px.x, px.y)) do
      local cj = palette_map[np()]
      if ci and cj and ci ~= cj then
        adj[ci] = adj[ci] or {}
        adj[ci][cj] = (adj[ci][cj] or 0) + 1
        adj[cj] = adj[cj] or {}
        adj[cj][ci] = (adj[cj][ci] or 0) + 1
      end
    end
  end
  return adj
end

-- Step 2: weight edges by "lightness-step / hue-deviation" ratio
-- High ratio ≈ ramp transition; low ratio ≈ hue jump (different ramp)
local function edge_weight(ci, cj, lch)
  local dL = math.abs(lch[ci].L - lch[cj].L)
  local dh = circular_dist(lch[ci].h, lch[cj].h, 360)
  return dL / (dh + 1e-6)   -- high = ramp-like
end

-- Step 3: find maximal-weight chains via greedy path extension
-- (DFS from each unvisited node, always choosing the highest-weight
--  unvisited neighbour that still moves in the same direction in L)
local function extract_chains(adj, lch, threshold)
  local visited = {}
  local chains = {}
  for start, _ in pairs(adj) do
    if not visited[start] then
      local chain = {start}
      visited[start] = true
      local node = start
      while true do
        local best_w, best_nb = -math.huge, nil
        for nb, _ in pairs(adj[node] or {}) do
          if not visited[nb] then
            local w = edge_weight(node, nb, lch)
            -- Must advance in L (dark→light direction)
            local advancing = lch[nb].L > lch[node].L
            if w > threshold and advancing and w > best_w then
              best_w, best_nb = w, nb
            end
          end
        end
        if not best_nb then break end
        visited[best_nb] = true
        table.insert(chain, best_nb)
        node = best_nb
      end
      if #chain > 1 then
        table.insert(chains, chain)
      end
    end
  end
  return chains
end
```

**Tuning `threshold`:** A value of ≈ 3.0 (ΔL three times larger than Δh)
works well for typical pixel art; expose it as a user parameter.

---

### 1.3  Convex Hull in RGB-Space (Tan et al. 2016)

**Tan, Lien & Gingold (2016)** [ref 3] observe that Porter-Duff "over"
compositing is linear in RGB, so a multi-layer image's pixel cloud in
RGB-space is contained within the convex hull of the layer base colours.
Their algorithm:

1. Compute the convex hull of all pixel colours in R³.
2. Simplify the hull to *k* vertices (user-chosen palette size) using
   iterative face-merging (similar to mesh decimation).
3. Each palette vertex is an "ideal paint colour"; pixels are expressed as
   convex combinations (barycentric weights) of the nearest simplex face.

**Relevance to ramp detection:** After extracting a *k*-colour palette from
the hull, sort those *k* colours in OKLCh and apply the hue-clustering step
from §1.1.  The hull guarantees palette colours span the full gamut of the
image, including "hidden" dark and light anchor colours that pure clustering
would miss.

**Efficient variant — RGBXY-space (Tan et al. 2018)** [ref 4]:  Extend each
pixel's coordinate to 5-D (R, G, B, x, y) so that spatial proximity is
encoded alongside colour.  The resulting hull decomposition simultaneously
respects colour similarity and spatial coherence, which is ideal when the
same hue appears in multiple spatially-separated ramps (e.g., a red sword
and red lava in one sprite sheet).

```lua
-- Pseudocode: simplified convex-hull palette extraction
-- Real 3-D convex hull needs a geometry library; this is the concept.

local function convex_hull_palette(pixels, k)
  -- pixels: array of {r,g,b}
  -- 1. Compute 3-D convex hull (use gift-wrapping or Quickhull)
  local hull_verts = quickhull_3d(pixels)       -- implementation-dependent
  -- 2. Simplify hull to k vertices by iteratively collapsing smallest faces
  while #hull_verts > k do
    local i = smallest_face_index(hull_verts)   -- face with smallest area
    hull_verts = collapse_face(hull_verts, i)
  end
  -- 3. Return simplified hull vertices as palette
  return hull_verts
end
```

*Full Quickhull in Lua is non-trivial; consider delegating to a small C
extension or approximating via the PCA-based bounding box followed by
iterative outermost-point extraction.*

---

### 1.4  NMF / Soft Unmixing (Aksoy et al. 2017)

**Aksoy, Aydın, Smolić & Gross (2017)** [ref 5] decompose an image into *K*
soft colour segments (layers), each with a uniform colour and a per-pixel
alpha map.  The energy minimised is:

```
E = Σ_p ||c_p - Σ_k α_pk · s_k||²  +  λ · Σ_k ||∇α_k||²
```

where *c_p* is the observed colour, *s_k* is the *k*-th segment colour, and
*α_pk* are mixing weights (summing to 1).  The spatial gradient term enforces
smooth alpha maps.

The segment colours {s_k} are the analogues of ramp *anchor* colours.  For
pixel art the gradient regulariser weight λ can be set high (or replaced with
a bilateral filter) to keep each segment spatially compact.

**NMF connection:** If the image matrix **X** (pixels × channels) is
approximately factorised as **X ≈ W H** with *W*, *H* ≥ 0 (Non-negative
Matrix Factorisation), the columns of **H** correspond to basis spectra
(colours) and the rows of **W** give per-pixel mixing weights.  Applied to
indexed pixel art where **X** is the usage histogram, NMF recovers which
palette subsets co-occur — which maps directly to ramp membership.

```lua
-- NMF multiplicative update rule (Lee & Seung 1999)
-- X : n_pixels × 3  (or palette_size × 1 histogram)
-- W : n_pixels × k  (mixing weights, non-negative)
-- H : k × 3         (basis colours, non-negative)
local function nmf_step(X, W, H, iters)
  for _ = 1, iters do
    -- Update H
    local WtX  = mat_mul(transpose(W), X)
    local WtWH = mat_mul(mat_mul(transpose(W), W), H)
    H = element_mul(H, element_div(WtX, WtWH))
    -- Update W
    local XHt  = mat_mul(X,  transpose(H))
    local WHHt = mat_mul(mat_mul(W, H), transpose(H))
    W = element_mul(W, element_div(XHt, WHHt))
  end
  return W, H
end
```

For pixel art specifically, run NMF on the *palette histogram* (a
`palette_size × 3` matrix) rather than the full image to keep Lua runtime
acceptable.

---

## 2  Clustering in Perceptual Space for Ramp Assignment

### 2.1  K-Means on Hue (Circular Distance)

Standard K-means breaks at the 0°/360° seam.  Use the **circular mean** and
**circular distance**:

```lua
local function circular_dist(a, b, period)
  local d = math.abs(a - b) % period
  return math.min(d, period - d)
end

local function circular_mean(angles, period)
  -- Convert to unit vectors, average, convert back
  local sx, sy = 0, 0
  for _, a in ipairs(angles) do
    local r = a * math.pi * 2 / period
    sx = sx + math.cos(r)
    sy = sy + math.sin(r)
  end
  local mean_r = math.atan(sy, sx)
  if mean_r < 0 then mean_r = mean_r + 2*math.pi end
  return mean_r * period / (2*math.pi)
end

local function kmeans_hue(entries, k, max_iter)
  -- entries: array of {idx, L, C, h}
  -- Initialise centroids by evenly spacing in [0,360)
  local centroids = {}
  for i = 1, k do centroids[i] = 360*(i-1)/k end

  for _ = 1, max_iter do
    -- Assign
    local clusters = {}
    for i = 1, k do clusters[i] = {} end
    for _, e in ipairs(entries) do
      local best_k, best_d = 1, math.huge
      for i, c in ipairs(centroids) do
        local d = circular_dist(e.h, c, 360)
        if d < best_d then best_k, best_d = i, d end
      end
      table.insert(clusters[best_k], e)
    end
    -- Update centroids
    local changed = false
    for i, cl in ipairs(clusters) do
      if #cl > 0 then
        local angles = {}
        for _, e in ipairs(cl) do table.insert(angles, e.h) end
        local new_c = circular_mean(angles, 360)
        if circular_dist(new_c, centroids[i], 360) > 0.01 then
          centroids[i] = new_c
          changed = true
        end
      end
    end
    if not changed then break end
  end
  return clusters, centroids
end
```

**Choosing k** for K-means: see §5 (elbow method on hue-quantisation error).

---

### 2.2  DBSCAN on (Hue, Chroma) Plane

DBSCAN (Ester et al. 1996 [ref 6]) discovers clusters of arbitrary shape and
labels outliers as noise — ideal for palettes where one ramp might be
monochromatic (chroma ≈ 0, all hues meaningless) and another has a wide
chroma range.

**Key parameters:**
- `eps` — neighbourhood radius in the (h, C) plane.  A good default for
  OKLCh is `eps = 0.12` (OKLCh chroma ranges 0–0.4; hue in radians 0–2π).
  Normalise both axes to [0,1] first.
- `minPts` — minimum neighbours to form a core point.  Use 2 for pixel art
  (ramps can be as small as 2 colours).

```lua
local function dbscan(entries, eps, min_pts)
  -- entries: array of {idx, L, C, h_rad}  (h in radians, C in [0,1])
  local function dist(a, b)
    -- Circular distance on hue, if both have meaningful chroma
    local dh = math.min(math.abs(a.h_rad - b.h_rad),
                        2*math.pi - math.abs(a.h_rad - b.h_rad))
    local dC = math.abs(a.C - b.C)
    -- Weight hue less for low-chroma colours
    local w = math.min(a.C, b.C) * 5   -- 0 when grey, 1 when saturated
    return math.sqrt((w*dh)^2 + dC^2)
  end

  local labels = {}   -- cluster id per entry; -1 = noise
  local cluster_id = 0

  local function region_query(p)
    local nb = {}
    for i, q in ipairs(entries) do
      if dist(p, q) <= eps then table.insert(nb, i) end
    end
    return nb
  end

  for i, p in ipairs(entries) do
    if not labels[i] then
      local nb = region_query(p)
      if #nb < min_pts then
        labels[i] = -1   -- noise
      else
        cluster_id = cluster_id + 1
        labels[i] = cluster_id
        -- Expand cluster
        local seed_set = nb
        local j = 1
        while j <= #seed_set do
          local q_idx = seed_set[j]
          if labels[q_idx] == -1 then labels[q_idx] = cluster_id end
          if not labels[q_idx] then
            labels[q_idx] = cluster_id
            local q_nb = region_query(entries[q_idx])
            if #q_nb >= min_pts then
              for _, r in ipairs(q_nb) do table.insert(seed_set, r) end
            end
          end
          j = j + 1
        end
      end
    end
  end
  return labels, cluster_id
end
```

Noise-labelled entries (labels[i] == -1) are near-grey or transitional
colours; collect them into an auxiliary "achromatic ramp" sorted by *L*.

---

### 2.3  Mean-Shift in OKLCh to Find Hue Modes

Mean-shift (Fukunaga & Hostetler 1975; Comaniciu & Meer 2002 [ref 7]) seeks
density modes of the hue distribution without needing a pre-specified *k*.

```lua
-- Flat kernel mean-shift on the 1-D circular hue axis
local function meanshift_hue(entries, bandwidth_deg, max_iter)
  -- entries: array with .h in [0,360)
  -- Only consider entries with C > chroma_threshold
  local CHROMA_THRESH = 0.06

  local function shift(current_h)
    local wx, wy = 0, 0
    local total_w = 0
    for _, e in ipairs(entries) do
      if e.C > CHROMA_THRESH then
        local d = circular_dist(current_h, e.h, 360)
        if d < bandwidth_deg then
          -- Weight by chroma (more saturated colours anchor the mode more)
          local w = e.C
          local r = e.h * math.pi / 180
          wx = wx + w * math.cos(r)
          wy = wy + w * math.sin(r)
          total_w = total_w + w
        end
      end
    end
    if total_w == 0 then return current_h end
    local new_r = math.atan(wy, wx)
    if new_r < 0 then new_r = new_r + 2*math.pi end
    return new_r * 180 / math.pi
  end

  -- Run a trajectory from each entry until convergence
  local modes = {}
  for _, e in ipairs(entries) do
    if e.C > CHROMA_THRESH then
      local h = e.h
      for _ = 1, max_iter do
        local new_h = shift(h)
        if circular_dist(new_h, h, 360) < 0.5 then break end
        h = new_h
      end
      -- Merge with existing mode if within half a bandwidth
      local found = false
      for _, m in ipairs(modes) do
        if circular_dist(h, m.h, 360) < bandwidth_deg * 0.5 then
          m.count = m.count + 1
          found = true; break
        end
      end
      if not found then table.insert(modes, {h=h, count=1}) end
    end
  end
  return modes
end
```

**Bandwidth selection:** Start with 25°–40°; use the **Sheather-Jones
plug-in** for optimal bandwidth if implementing a full pipeline.

---

### 2.4  Two-Stage Pipeline (Recommended for Pixel Art)

```
Stage 1 — Hue mode detection
  • Run mean-shift (§2.3) or DBSCAN (§2.2) on the (h, C) distribution of
    all palette entries with C > 0.04.
  • Each mode/cluster defines one ramp's hue neighbourhood.

Stage 2 — Per-cluster lightness sort
  • Assign each palette entry (including near-grey ones) to the nearest
    hue mode using weighted circular distance.
  • Within each cluster, sort ascending by L.
  • Entries whose C < 0.04 form the achromatic "grey" ramp.

Stage 3 — Ramp coherence check
  • Verify each candidate ramp has monotonically increasing L.
  • Detect and repair inversions (two adjacent stops with L_i > L_{i+1})
    by re-merging the offending pair into one stop (average colour).
```

---

## 3  Mapping Source Pixels to a Target Compressed Palette

### 3.1  Dithering vs. No-Dithering for Pixel Art

Error-diffusion dithering (Floyd-Steinberg 1976 [ref 8]) diffuses quantisation
error to neighbouring pixels, producing a halftone-like result.  This is
appropriate for photographs but **destroys the crisply-bounded shapes** that
define pixel art aesthetics.  The strong consensus in the pixel-art community
is to use **nearest-neighbour mapping with no dither**.

| Technique | Error | Visual Result | Pixel Art Appropriate? |
|-----------|-------|---------------|------------------------|
| Floyd-Steinberg diffusion | Diffused | Halftone, noisy | ✗ |
| Ordered (Bayer) dithering | Patterned | Cross-hatched | ✗ (rarely) |
| Nearest-neighbour, no dither | Sharp | Crisply flat | ✓ |

---

### 3.2  Nearest-Neighbour in OKLab vs OKLCh

**OKLab (Cartesian)** distance:

```lua
local function oklab_dist2(a, b)
  local dL = a.L - b.L
  local da = a.a - b.a
  local db2 = a.b - b.b
  return dL*dL + da*da + db2*db2
end
```

**OKLCh weighted distance** lets you penalise hue difference separately from
lightness error — useful when you want to preserve ramp identity (a pixel
should never jump from a warm ramp to a cool ramp even if the nearest OKLab
colour happens to be across the hue wheel):

```lua
-- Weights: wL for lightness, wC for chroma, wH for hue (in radians).
-- Empirical starting point: wL=1.0, wC=0.5, wH=2.0
local function oklch_weighted_dist2(a, b, wL, wC, wH)
  local dL  = a.L - b.L
  local dC  = a.C - b.C
  local dh  = circular_dist(a.h_rad, b.h_rad, 2*math.pi)
  -- Scale hue distance by mean chroma so grey has no hue penalty
  local C_avg = (a.C + b.C) * 0.5
  return (wL*dL)^2 + (wC*dC)^2 + (wH * C_avg * dh)^2
end
```

---

### 3.3  Preserving Ramp Identity During Remapping

The problem: when remapping, a mid-ramp orange could be equidistant in OKLab
from both the compressed orange ramp and the compressed red ramp.  The random
choice will create "ramp hopping" — pixels that should shade smoothly suddenly
switch families.

**Solution — two-pass constrained nearest-neighbour:**

```lua
-- Pass 1: assign each source ramp entry to exactly one target ramp.
--         Use a greedy bipartite match: for each source ramp, find the
--         target ramp whose median OKLab colour is closest.
local function match_ramps(src_ramps, tgt_ramps, lch)
  local assignment = {}
  local used = {}
  for si, sramp in ipairs(src_ramps) do
    -- Compute source ramp median colour in OKLab
    local med = ramp_median_oklab(sramp, lch)
    local best_ti, best_d = 1, math.huge
    for ti, tramp in ipairs(tgt_ramps) do
      if not used[ti] then
        local d = oklab_dist2(med, ramp_median_oklab(tramp, lch))
        if d < best_d then best_ti, best_d = ti, d end
      end
    end
    assignment[si] = best_ti
    used[best_ti] = true
  end
  return assignment
end

-- Pass 2: remap each pixel.
--         First identify which source ramp it belongs to (from §1),
--         then find the nearest stop within the *matched* target ramp only.
local function remap_pixel(pixel_oklch, src_ramp_id, assignment, tgt_ramps, lch)
  local ti = assignment[src_ramp_id]
  local tramp = tgt_ramps[ti]
  local best_idx, best_d = nil, math.huge
  for _, stop in ipairs(tramp) do
    local d = oklch_weighted_dist2(pixel_oklch, lch[stop], 1.0, 0.5, 2.0)
    if d < best_d then best_idx, best_d = stop, d end
  end
  return best_idx
end
```

**Tie-breaking:** When two target stops inside the matched ramp are equidistant,
prefer the one with the same *direction* (if the source pixel is lighter than
the source ramp median, pick the lighter target stop).

---

## 4  Synthesising New Hue-Shifted Ramps

### 4.1  Parametric Hue-Shifted Ramp Model

A "hue-shifted ramp" in pixel art varies hue as it varies lightness — dark
shadows are pushed toward cooler/warmer hues, highlights toward the opposite.
Define the model with five parameters:

| Parameter | Symbol | Description |
|-----------|--------|-------------|
| Base hue | h₀ | Hue at mid-lightness (degrees, OKLCh) |
| Hue slope | Δh | Degrees of hue rotation per unit of L |
| Lightness range | [L_min, L_max] | Dark → light span |
| Base chroma | C₀ | Chroma at mid-L |
| Chroma curve | κ | Chroma = C₀ · (1 − κ·(L − L_mid)²) |

A stop at normalised position *t ∈ [0,1]* is:

```
L(t) = L_min + t·(L_max − L_min)
h(t) = h₀ + Δh · (t − 0.5)          -- linear hue shift
C(t) = C₀ · (1 − κ · (t − 0.5)²)   -- quadratic chroma arc
```

The quadratic chroma arc models the typical pixel-art pattern where mid-tones
are most saturated and both deep shadows and bright highlights desaturate.

---

### 4.2  Least-Squares Fitting in OKLCh

Given a detected ramp (ordered array of OKLCh triples), fit the five
parameters {h₀, Δh, L_min, L_max, C₀, κ} by minimising:

```
E = Σ_i [ (L_i - L̂(t_i))² + w_h·(h_i - ĥ(t_i))² + w_C·(C_i - Ĉ(t_i))² ]
```

where t_i = (L_i − L_min)/(L_max − L_min) is computed from the observed
lightness, and ŵ = (L̂, ĥ, Ĉ) are model predictions.

```lua
local function fit_ramp(stops_lch)
  -- stops_lch: array of {L, C, h} ordered by L ascending
  local n = #stops_lch
  assert(n >= 2, "Need at least 2 stops")

  -- Direct estimates for linear parameters
  local L_min = stops_lch[1].L
  local L_max = stops_lch[n].L
  local L_mid = (L_min + L_max) * 0.5

  -- Hue: linear regression L→h (handling circular wraparound via atan2)
  local sum_t, sum_hx, sum_hy = 0, 0, 0
  for i, s in ipairs(stops_lch) do
    local t = (n == 1) and 0.5 or (i-1)/(n-1)
    local hr = s.h * math.pi / 180
    sum_t  = sum_t  + t
    sum_hx = sum_hx + math.cos(hr)
    sum_hy = sum_hy + math.sin(hr)
  end
  local mean_hx = sum_hx / n
  local mean_hy = sum_hy / n
  local h0_rad  = math.atan(mean_hy, mean_hx)
  if h0_rad < 0 then h0_rad = h0_rad + 2*math.pi end
  local h0 = h0_rad * 180 / math.pi

  -- Hue slope via linear regression of (t − 0.5) → Δh_i
  local sum_xy, sum_xx = 0, 0
  for i, s in ipairs(stops_lch) do
    local t = (n == 1) and 0.5 or (i-1)/(n-1)
    local dh = s.h - h0   -- signed delta, may need wraparound correction
    -- Wrap dh to [-180,180]
    dh = ((dh + 180) % 360) - 180
    local x = t - 0.5
    sum_xy = sum_xy + x * dh
    sum_xx = sum_xx + x * x
  end
  local dh_slope = (sum_xx > 1e-9) and (sum_xy / sum_xx) or 0

  -- Chroma: quadratic regression C_i = C0 · (1 − κ·(t−0.5)²)
  -- Let u_i = (t_i − 0.5)²; then C_i = C0 − C0·κ·u_i
  -- Simple: C0 = mean C at t≈0.5; κ = curvature from endpoints
  local C0 = stops_lch[math.ceil(n/2)].C
  local C_ends = (stops_lch[1].C + stops_lch[n].C) * 0.5
  local kappa = (C0 > 1e-6) and (1 - C_ends/C0) / 0.25 or 0

  return {h0=h0, dh_slope=dh_slope,
          L_min=L_min, L_max=L_max,
          C0=C0, kappa=kappa}
end

local function sample_ramp(params, n_stops)
  local stops = {}
  for i = 1, n_stops do
    local t  = (i-1)/(n_stops-1)
    local L  = params.L_min + t * (params.L_max - params.L_min)
    local h  = params.h0 + params.dh_slope * (t - 0.5)
    local C  = params.C0 * (1 - params.kappa * (t-0.5)^2)
    C = math.max(0, C)
    h = h % 360
    table.insert(stops, {L=L, C=C, h=h})
  end
  return stops
end
```

---

### 4.3  Snapping to a Library of Ideal Ramps

For constrained pipelines, pre-define a library of ideal ramp archetypes:

```lua
local RAMP_LIBRARY = {
  -- {name, h0, dh_slope, C0, kappa}
  -- Warm-to-cool: shadow shifts blue, highlight shifts orange
  {name="warm_to_cool",  h0=30,  dh_slope=-40, C0=0.18, kappa=0.8},
  -- Cool-to-warm: complement of above
  {name="cool_to_warm",  h0=220, dh_slope= 40, C0=0.16, kappa=0.8},
  -- Monochromatic: no hue shift
  {name="mono_warm",     h0=40,  dh_slope=  0, C0=0.12, kappa=0.3},
  {name="mono_cool",     h0=200, dh_slope=  0, C0=0.14, kappa=0.3},
  -- Complementary split (e.g., skin-to-purple)
  {name="skin_purple",   h0=50,  dh_slope=-60, C0=0.20, kappa=1.2},
  -- Neutral grey
  {name="grey",          h0=0,   dh_slope=  0, C0=0.00, kappa=0.0},
}

local function snap_to_library(detected_params, library)
  local best, best_err = nil, math.huge
  for _, archetype in ipairs(library) do
    local err = (circular_dist(detected_params.h0, archetype.h0, 360) / 30)^2
              + (detected_params.dh_slope - archetype.dh_slope)^2 / 400
              + (detected_params.C0 - archetype.C0)^2 / 0.01
    if err < best_err then best, best_err = archetype, err end
  end
  return best
end
```

Snapping is useful when the target hardware (fantasy console, demoscene
restriction) mandates a fixed set of hue-shift styles.

---

### 4.4  Remapping to OKLCh → sRGB with Gamut Clipping

After synthesising stops in OKLCh, convert back to sRGB.  Colours with high
chroma near L extremes may fall outside sRGB.  Use **OKLab gamut clipping**
(Ottosson 2021, "How to make a perceptual color picker" [ref 9]):

```lua
-- Clip an OKLab colour to the sRGB gamut by binary-searching along
-- the line from the L-axis to the colour.
local function clip_to_srgb(L, a, b_ok)
  -- Try the colour as-is
  local r, g, b = oklab_to_srgb(L, a, b_ok)
  if r>=0 and r<=1 and g>=0 and g<=1 and b>=0 and b<=1 then
    return r, g, b
  end
  -- Binary search: interpolate toward the neutral grey (L, 0, 0)
  local lo, hi = 0, 1
  for _ = 1, 16 do
    local mid = (lo + hi) * 0.5
    local cr, cg, cb = oklab_to_srgb(L, a*mid, b_ok*mid)
    if cr>=0 and cr<=1 and cg>=0 and cg<=1 and cb>=0 and cb<=1 then
      lo = mid
    else
      hi = mid
    end
  end
  return oklab_to_srgb(L, a*lo, b_ok*lo)
end
```

---

## 5  Determining the Target Ramp Count and Stops per Ramp

### 5.1  Elbow Method on Hue-Quantisation Error

Run the hue-K-means from §2.1 for *k* = 1…K_max.  Record the
within-cluster sum of squared circular hue distances (WCSS).  The elbow —
where WCSS drops more slowly — is the natural ramp count.

```lua
local function elbow_ramp_count(entries, k_max)
  local wcss_list = {}
  for k = 1, k_max do
    local clusters, centroids = kmeans_hue(entries, k, 50)
    local wcss = 0
    for i, cl in ipairs(clusters) do
      for _, e in ipairs(cl) do
        local d = circular_dist(e.h, centroids[i], 360)
        wcss = wcss + d*d
      end
    end
    wcss_list[k] = wcss
  end
  -- Find elbow: largest second derivative of WCSS
  local best_k, best_dd = 2, 0
  for k = 2, k_max - 1 do
    local dd = wcss_list[k-1] - 2*wcss_list[k] + wcss_list[k+1]
    if dd > best_dd then best_k, best_dd = k, dd end
  end
  return best_k
end
```

**Practical defaults:** For sprites ≤ 64 colours, `k_max = 8` is usually
sufficient.

---

### 5.2  Fixed User-Supplied Count

Expose `ramp_count` and `stops_per_ramp` as user parameters (spinner widgets
in the Aseprite dialog).  Sensible defaults:

```lua
local DEFAULTS = {
  ramp_count      = 4,   -- number of distinct hue ramps
  stops_per_ramp  = 4,   -- colours per ramp
  grey_ramp_stops = 3,   -- separate achromatic ramp
}
```

---

### 5.3  Minimum Description Length (MDL)

MDL (Rissanen 1978 [ref 10]) selects the model that minimises
*code_length(model) + code_length(data | model)*.  For colour palettes:

```
MDL(k) = k · bits_per_ramp_param   +   Σ_p bits_to_encode_pixel_given_k_ramps
```

The second term is approximated by the quantisation error in OKLab:

```
bits_per_pixel ≈ − log2( exp( − dist²(pixel, nearest_stop) / (2·σ²) ) )
               = dist² / (2·σ² · ln2)
```

where σ² is a perceptual JND variance (≈ 0.001 in OKLab² for pixel art).

```lua
local BITS_PER_RAMP = 5 * 8   -- 5 parameters × 8 bits each
local SIGMA2        = 0.001

local function mdl_score(ramps_lch, all_pixels_lch)
  local model_bits = #ramps_lch * BITS_PER_RAMP
  local data_bits  = 0
  for _, px in ipairs(all_pixels_lch) do
    local best_d2 = math.huge
    for _, ramp in ipairs(ramps_lch) do
      for _, stop in ipairs(ramp) do
        local d2 = oklab_dist2(px, stop)
        if d2 < best_d2 then best_d2 = d2 end
      end
    end
    data_bits = data_bits + best_d2 / (2 * SIGMA2 * math.log(2))
  end
  return model_bits + data_bits
end
```

Compute `mdl_score` for *k* = 1…K_max and pick the *k* that minimises it.

---

### 5.4  Per-Ramp Stop Count

Given a detected source ramp of *n* stops, the compressed ramp should have:

```lua
local MIN_STOPS = 2
local MAX_STOPS = 8

local function target_stop_count(src_n, global_budget, n_ramps)
  -- Distribute global_budget stops proportionally, then clamp.
  local raw = math.round(src_n / (src_n_total) * global_budget)
  return math.max(MIN_STOPS, math.min(MAX_STOPS, raw))
end
```

**Heuristic:** If the source ramp spans more than 0.5 in OKLab *L*
(very wide lightness range), allocate at least 4 stops; if it spans less
than 0.2, 2 stops usually suffice.

---

## 6  Reference Index

| # | Citation | URL / DOI |
|---|----------|-----------|
| 1 | B. Ottosson, "Oklab — a perceptual colour space for image processing", 2020 | https://bottosson.github.io/posts/oklab/ |
| 2 | M.R. Huang & R.R. Lee, "Pixel art color palette synthesis", *Information Science and Applications*, Springer, 2015 | https://doi.org/10.1007/978-3-662-46578-3_38 |
| 3 | J. Tan, J-M. Lien & Y. Gingold, "Decomposing Images into Layers via RGB-space Geometry", *ACM TOG*, 2016 | https://doi.org/10.1145/2988229 |
| 4 | J. Tan, J. Echevarria & Y. Gingold, "Efficient palette-based decomposition and recoloring of images via RGBXY-space geometry", *ACM TOG*, 2018 | https://doi.org/10.1145/3272127.3275054 |
| 5 | Y. Aksoy, T. Aydın, A. Smolić & M. Gross, "Unmixing-based soft color segmentation for image manipulation", *ACM TOG*, 2017 | https://doi.org/10.1145/3002176 |
| 6 | M. Ester, H.-P. Kriegel, J. Sander & X. Xu, "A density-based algorithm for discovering clusters in large spatial databases with noise" (DBSCAN), *KDD*, 1996 | https://dl.acm.org/doi/10.5555/3001460.3001507 |
| 7 | D. Comaniciu & P. Meer, "Mean shift: A robust approach toward feature space analysis", *IEEE TPAMI*, 2002 | https://doi.org/10.1109/34.1000236 |
| 8 | R.W. Floyd & L. Steinberg, "An adaptive algorithm for spatial greyscale", *Proc. SID*, 1976 | (no DOI; widely reprinted) |
| 9 | B. Ottosson, "How to make a perceptual color picker", 2021 (gamut clipping section) | https://bottosson.github.io/posts/colorpicker/ |
| 10 | J. Rissanen, "Modeling by shortest data description", *Automatica*, 1978 | https://doi.org/10.1016/0005-1098(78)90005-5 |
| 11 | J. Tan, J. Echevarria & Y. Gingold, "Palette-based image decomposition, harmonization, and color transfer", arXiv:1804.01225, 2018 | https://arxiv.org/abs/1804.01225 |
| 12 | K. Fukunaga & L.D. Hostetler, "The estimation of the gradient of a density function", *IEEE TIT*, 1975 | https://doi.org/10.1109/TIT.1975.1055330 |
| 13 | D.D. Lee & H.S. Seung, "Learning the parts of objects by non-negative matrix factorization", *Nature*, 1999 | https://doi.org/10.1038/44565 |

---

*Document version: 2025-07-11 — Created by research subagent*
```

---

## Summary

**File to create:** `D:\Aseprite\Compress Palette with Hue Shifting\research\04-ramp-detection-grouping.md
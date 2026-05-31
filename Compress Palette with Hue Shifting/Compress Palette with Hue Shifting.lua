-- Compress Palette with Hue Shifting V0.6
-- Install:
-- 1. Save this file as "Compress Palette with Hue Shifting.lua".
-- 2. Copy or symlink it (and its folder) into %APPDATA%\Aseprite\scripts.
-- 3. In Aseprite, run File > Scripts > Rescan Scripts, or restart Aseprite.
-- 4. Run File > Scripts > Compress Palette with Hue Shifting.

local COMMAND_TITLE <const> = "Compress Palette with Hue Shifting"
local OUTPUT_LAYER_NAME <const> = "Compressed (Hue-Shifted)"

local DEFAULT_CONFIG <const> = {
    mode = "Hybrid",                -- Hybrid | Stylise
    size_mode = "Ramps x Stops",    -- Ramps x Stops | Total colours
    target_colours = 32,             -- used when size_mode = "Total colours"
    ramps = 0,                       -- 0 = auto
    stops = 0,                       -- 0 = auto
    strength = 0.5,                  -- 0..1
    output = "New layer",           -- New layer | In place
    -- advanced (CLI / hidden):
    highlight_pull = 0.25,
    shadow_pull = 0.35,
    warm_attractor_hue = 70.0,      -- yellow-orange
    cool_attractor_hue = 250.0,     -- blue-violet
    chroma_ceiling = 0.30,
    achromatic_threshold = 0.02,
    shared_shadow = true,
    shared_highlight = true,
    grey_budget = 3,                 -- default grey ramp stops if achromatic present
    kmeans_max_iter = 40,
    kmeans_seed = 42,
    elbow_kmax = 8,
    grey_stops_max = 5,
    -- Accent preservation
    accent_detection = true,
    max_accent_slots = 8,
    accent_score_threshold = 0.80,
    accent_tolerance = 0.07,        -- OKLab ΔE below which accent is considered already represented
    accent_cluster_floor = 0.06,    -- absolute OKLCh chroma below which per-cluster outliers are ignored
}

local pc <const> = app.pixelColor

-- ============================================================
-- Utility
-- ============================================================

local function fail(message)
    local params = app.params or {}
    local raise = params.raise_errors or params.raiseErrors
    local force = false
    if raise ~= nil then
        local s = tostring(raise):lower()
        force = (s == "1" or s == "true" or s == "yes")
    end
    if app.isUIAvailable and not force then
        app.alert { title = COMMAND_TITLE, text = message }
        return
    end
    error(message)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function round(v)
    if v >= 0 then return math.floor(v + 0.5) end
    return math.ceil(v - 0.5)
end

local function smoothstep(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Shortest-arc hue interpolation, hues in degrees [0, 360).
local function lerp_hue(a, b, t)
    local d = b - a
    if d > 180 then d = d - 360
    elseif d < -180 then d = d + 360 end
    local h = a + d * t
    if h < 0 then h = h + 360
    elseif h >= 360 then h = h - 360 end
    return h
end

local function circular_dist(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then d = 360 - d end
    return d
end

-- ============================================================
-- sRGB <-> linear <-> OKLab <-> OKLCh
-- Coefficients from Ottosson, https://bottosson.github.io/posts/oklab/
-- ============================================================

local function srgb_to_linear(c)
    c = c / 255.0
    if c >= 0.04045 then
        return ((c + 0.055) / 1.055) ^ 2.4
    end
    return c / 12.92
end

local function linear_to_srgb(c)
    if c <= 0 then return 0 end
    if c >= 1 then return 255 end
    if c >= 0.0031308 then
        c = 1.055 * c ^ (1 / 2.4) - 0.055
    else
        c = 12.92 * c
    end
    return round(c * 255)
end

local function cbrt(x)
    if x >= 0 then return x ^ (1 / 3) end
    return -((-x) ^ (1 / 3))
end

local function rgb_to_oklab(r, g, b)
    local rl = srgb_to_linear(r)
    local gl = srgb_to_linear(g)
    local bl = srgb_to_linear(b)

    local l = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl
    local m = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl
    local s = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl

    local lp = cbrt(l)
    local mp = cbrt(m)
    local sp = cbrt(s)

    return 0.2104542553 * lp + 0.7936177850 * mp - 0.0040720468 * sp,
        1.9779984951 * lp - 2.4285922050 * mp + 0.4505937099 * sp,
        0.0259040371 * lp + 0.7827717662 * mp - 0.8086757660 * sp
end

local function oklab_to_linear_rgb(L, a, b)
    local lp = L + 0.3963377774 * a + 0.2158037573 * b
    local mp = L - 0.1055613458 * a - 0.0638541728 * b
    local sp = L - 0.0894841775 * a - 1.2914855480 * b

    local l = lp * lp * lp
    local m = mp * mp * mp
    local s = sp * sp * sp

    return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

local function oklab_to_rgb(L, a, b)
    local rl, gl, bl = oklab_to_linear_rgb(L, a, b)
    return linear_to_srgb(rl), linear_to_srgb(gl), linear_to_srgb(bl)
end

local function oklab_in_gamut(L, a, b)
    local rl, gl, bl = oklab_to_linear_rgb(L, a, b)
    return rl >= -1e-4 and rl <= 1.0001
        and gl >= -1e-4 and gl <= 1.0001
        and bl >= -1e-4 and bl <= 1.0001
end

local function oklch_to_oklab(L, C, h)
    local hr = math.rad(h)
    return L, C * math.cos(hr), C * math.sin(hr)
end

local function oklab_to_oklch(L, a, b)
    local C = math.sqrt(a * a + b * b)
    local h = math.deg(math.atan(b, a))
    if h < 0 then h = h + 360 end
    return L, C, h
end

-- Hue-preserving gamut clip: reduce chroma until inside sRGB. Keeps L and h.
local function gamut_clip_oklch(L, C, h)
    if C <= 0 then
        local a, b = 0, 0
        local r, g, b8 = oklab_to_rgb(L, a, b)
        return r, g, b8, L, 0, h
    end
    local lo, hi = 0.0, C
    local La, aa, ba = oklch_to_oklab(L, hi, h)
    if oklab_in_gamut(La, aa, ba) then
        local r, g, b8 = oklab_to_rgb(La, aa, ba)
        return r, g, b8, L, C, h
    end
    for _ = 1, 24 do
        local mid = (lo + hi) * 0.5
        local Lm, am, bm = oklch_to_oklab(L, mid, h)
        if oklab_in_gamut(Lm, am, bm) then
            lo = mid
        else
            hi = mid
        end
    end
    local Lf, af, bf = oklch_to_oklab(L, lo, h)
    local r, g, b8 = oklab_to_rgb(Lf, af, bf)
    return r, g, b8, L, lo, h
end

-- ============================================================
-- Sprite pixel collection
-- ============================================================

-- Walk every frame's *composited* output. This matches what an exporter sees
-- and prevents hidden/overpainted cel pixels from polluting the histogram.
-- A colour appearing on multiple frames is counted on each frame, naturally
-- weighting frame-stable colours over single-frame AA noise. We also track
-- the number of distinct frames each colour appears on so accent scoring can
-- reward frame-consistent vivid colours.
local function collect_histogram(sprite)
    local hist = {}                  -- key (r<<16|g<<8|b) -> total pixel count across frames
    local frames_seen = {}           -- key -> number of distinct frames containing this colour
    local alpha_present = false
    local total_frames = #sprite.frames
    for f = 1, total_frames do
        local img = Image(sprite.spec)
        img:drawSprite(sprite, f)
        local seen_this_frame = {}
        for it in img:pixels() do
            local px = it()
            local a = pc.rgbaA(px)
            if a == 0 then
                alpha_present = true
            else
                local r = pc.rgbaR(px)
                local g = pc.rgbaG(px)
                local b = pc.rgbaB(px)
                local key = r * 65536 + g * 256 + b
                hist[key] = (hist[key] or 0) + 1
                if not seen_this_frame[key] then
                    seen_this_frame[key] = true
                    frames_seen[key] = (frames_seen[key] or 0) + 1
                end
                if a < 255 then alpha_present = true end
            end
        end
    end
    return hist, alpha_present, frames_seen, total_frames
end

-- ============================================================
-- Hue k-means (circular)
-- ============================================================

local function weighted_circular_mean(entries, indices)
    local sx, sy = 0, 0
    for _, i in ipairs(indices) do
        local e = entries[i]
        local hr = math.rad(e.h)
        sx = sx + math.cos(hr) * e.w
        sy = sy + math.sin(hr) * e.w
    end
    if sx == 0 and sy == 0 then return 0 end
    local h = math.deg(math.atan(sy, sx))
    if h < 0 then h = h + 360 end
    return h
end

local function kmeans_hue(entries, k, max_iter, seed)
    if k <= 0 or #entries == 0 then return {}, {} end
    if k > #entries then k = #entries end

    -- k-means++ seeding on hue circle, weighted by entry weight
    math.randomseed(seed)
    local centroids = {}
    local first = math.random(1, #entries)
    centroids[1] = entries[first].h
    for c = 2, k do
        local dist2 = {}
        local total = 0
        for i, e in ipairs(entries) do
            local best = math.huge
            for j = 1, c - 1 do
                local d = circular_dist(e.h, centroids[j])
                if d < best then best = d end
            end
            local d2 = best * best * e.w
            dist2[i] = d2
            total = total + d2
        end
        if total <= 0 then
            centroids[c] = entries[math.random(1, #entries)].h
        else
            local r = math.random() * total
            local acc = 0
            for i, e in ipairs(entries) do
                acc = acc + dist2[i]
                if acc >= r then
                    centroids[c] = e.h
                    break
                end
            end
            if not centroids[c] then centroids[c] = entries[#entries].h end
        end
    end

    local assign = {}
    for iter = 1, max_iter do
        local changed = false
        for i, e in ipairs(entries) do
            local best, best_d = 1, math.huge
            for j = 1, #centroids do
                local d = circular_dist(e.h, centroids[j])
                if d < best_d then best_d = d; best = j end
            end
            if assign[i] ~= best then changed = true end
            assign[i] = best
        end
        if not changed and iter > 1 then break end

        local clusters = {}
        for j = 1, #centroids do clusters[j] = {} end
        for i, _ in ipairs(entries) do
            local j = assign[i]
            clusters[j][#clusters[j] + 1] = i
        end
        for j = 1, #centroids do
            if #clusters[j] > 0 then
                centroids[j] = weighted_circular_mean(entries, clusters[j])
            end
        end
    end

    -- Build cluster index lists
    local clusters = {}
    for j = 1, #centroids do clusters[j] = {} end
    for i, _ in ipairs(entries) do
        local j = assign[i]
        clusters[j][#clusters[j] + 1] = i
    end
    return clusters, centroids
end

local function elbow_k(entries, k_max)
    if #entries <= 2 then return math.min(#entries, 1) end
    local wcss = {}
    for k = 1, math.min(k_max, #entries) do
        local clusters, centroids = kmeans_hue(entries, k, 25, 42)
        local total = 0
        for j, c in ipairs(clusters) do
            for _, i in ipairs(c) do
                local d = circular_dist(entries[i].h, centroids[j])
                total = total + d * d * entries[i].w
            end
        end
        wcss[k] = total
    end
    local best_k, best_dd = 1, -1
    for k = 2, #wcss - 1 do
        local dd = wcss[k - 1] - 2 * wcss[k] + wcss[k + 1]
        if dd > best_dd then best_dd = dd; best_k = k end
    end
    if best_k == 1 and #wcss >= 2 then best_k = 2 end
    return best_k
end

-- ============================================================
-- Ramp construction
-- ============================================================

local function percentile(values, p)
    if #values == 0 then return 0 end
    table.sort(values)
    local idx = clamp(round(p * (#values - 1)) + 1, 1, #values)
    return values[idx]
end

local function weighted_mean(values, weights)
    local sv, sw = 0, 0
    for i = 1, #values do
        sv = sv + values[i] * weights[i]
        sw = sw + weights[i]
    end
    if sw == 0 then return 0 end
    return sv / sw
end

local function build_chromatic_ramp(entries, cluster_indices, cfg, stops_override)
    local Ls, Cs, hs, ws = {}, {}, {}, {}
    for _, i in ipairs(cluster_indices) do
        local e = entries[i]
        Ls[#Ls + 1] = e.L
        Cs[#Cs + 1] = e.C
        hs[#hs + 1] = e.h
        ws[#ws + 1] = e.w
    end
    -- Source bounds
    local L_lo_src = percentile({ table.unpack(Ls) }, 0.05)
    local L_hi_src = percentile({ table.unpack(Ls) }, 0.95)
    if L_hi_src - L_lo_src < 0.05 then
        -- Degenerate: widen artificially
        L_lo_src = math.max(0, L_lo_src - 0.08)
        L_hi_src = math.min(1, L_hi_src + 0.08)
    end
    local L_lo_abs <const> = 0.15
    local L_hi_abs <const> = 0.92
    local s = cfg.strength
    local L_lo = lerp(L_lo_src, L_lo_abs, s)
    local L_hi = lerp(L_hi_src, L_hi_abs, s)

    -- C_base from a high percentile (P90) so cluster vibrancy survives the bell curve.
    -- For small clusters where P90 collapses to the max, fall back to P75 to avoid
    -- a single residual outlier blowing the ramp out (per-cluster promotion has
    -- already stripped the strongest outliers upstream).
    local cs_sorted = { table.unpack(Cs) }
    table.sort(cs_sorted)
    local C_base
    if #cs_sorted >= 8 then
        C_base = percentile(cs_sorted, 0.90)
    else
        C_base = percentile(cs_sorted, 0.75)
    end
    C_base = math.min(C_base, cfg.chroma_ceiling)
    if C_base < 0.01 then C_base = 0.01 end

    local base_h = weighted_circular_mean(entries, cluster_indices)

    -- Stop count
    local n
    if stops_override and stops_override > 0 then
        n = stops_override
    else
        local span = L_hi - L_lo
        if span >= 0.5 then n = 5
        elseif span >= 0.3 then n = 4
        elseif span >= 0.15 then n = 3
        else n = 2 end
    end
    n = clamp(n, 2, 16)

    local stops = {}
    for k = 1, n do
        local t = (k - 1) / (n - 1)
        local ts = smoothstep(t)
        local L = lerp(L_lo, L_hi, ts)
        -- Chroma bell
        local bell = 1 - 4 * (t - 0.5) * (t - 0.5)
        bell = math.max(0.25, bell)
        local C = C_base * bell
        -- Hue temperature pull
        local h
        if t < 0.5 then
            local tt = (0.5 - t) * 2                    -- 0..1 shadowness
            local pull = cfg.shadow_pull * s * tt
            h = lerp_hue(base_h, cfg.cool_attractor_hue, pull)
        elseif t > 0.5 then
            local tt = (t - 0.5) * 2                    -- 0..1 highlightness
            local pull = cfg.highlight_pull * s * tt
            h = lerp_hue(base_h, cfg.warm_attractor_hue, pull)
        else
            h = base_h
        end
        local r, g, b, Lf, Cf, hf = gamut_clip_oklch(L, C, h)
        stops[k] = { r = r, g = g, b = b, L = Lf, C = Cf, h = hf, t = t }
    end
        local total_w = 0
        for _, i in ipairs(cluster_indices) do total_w = total_w + entries[i].w end
        return { stops = stops, base_h = base_h, kind = "chromatic", weight = total_w }
end

local function build_grey_ramp(entries, indices, cfg, stops_override)
    if #indices == 0 then return nil end
    local Ls = {}
    for _, i in ipairs(indices) do Ls[#Ls + 1] = entries[i].L end
    local L_lo = percentile({ table.unpack(Ls) }, 0.05)
    local L_hi = percentile({ table.unpack(Ls) }, 0.95)
    if L_hi - L_lo < 0.05 then
        L_lo = math.max(0, L_lo - 0.05)
        L_hi = math.min(1, L_hi + 0.05)
    end
    local n = stops_override and stops_override > 0 and stops_override
        or math.min(cfg.grey_stops_max, math.max(2, math.floor((L_hi - L_lo) / 0.18) + 2))
    n = clamp(n, 2, cfg.grey_stops_max)
    local stops = {}
    for k = 1, n do
        local t = (k - 1) / (n - 1)
        local L = lerp(L_lo, L_hi, smoothstep(t))
        local r, g, b = oklab_to_rgb(L, 0, 0)
        stops[k] = { r = r, g = g, b = b, L = L, C = 0, h = 0, t = t }
    end
    return { stops = stops, base_h = 0, kind = "grey", weight = 0 }
end

-- ============================================================
-- Shared anchors: weighted-OKLab average of all chromatic ramps' endpoint stops.
-- Replaces each ramp's stop[1] (shadow) and/or stop[n] (highlight) with the merged colour.
-- Returns the merged RGB for each end (or nil if not applied).
-- ============================================================

local function compute_anchor_oklab(ramps, stop_picker)
    local sL, sa, sb, sw = 0, 0, 0, 0
    for _, r in ipairs(ramps) do
        local s = stop_picker(r)
        local L, A, B = rgb_to_oklab(s.r, s.g, s.b)
        local w = r.weight > 0 and r.weight or 1
        sL = sL + L * w; sa = sa + A * w; sb = sb + B * w
        sw = sw + w
    end
    if sw == 0 then return nil end
    return sL / sw, sa / sw, sb / sw
end

local function apply_shared_anchors(chrom_ramps, cfg)
    local shared_dark, shared_light = nil, nil
    if #chrom_ramps < 2 then return shared_dark, shared_light end

    if cfg.shared_shadow then
        local L, a, b = compute_anchor_oklab(chrom_ramps, function(r) return r.stops[1] end)
        if L then
            local _, C, h = oklab_to_oklch(L, a, b)
            local r8, g8, b8, Lf, Cf, hf = gamut_clip_oklch(L, C, h)
            shared_dark = { r = r8, g = g8, b = b8, L = Lf, C = Cf, h = hf }
            for _, ramp in ipairs(chrom_ramps) do
                local s = ramp.stops[1]
                s.r, s.g, s.b, s.L, s.C, s.h = r8, g8, b8, Lf, Cf, hf
            end
        end
    end

    if cfg.shared_highlight then
        local L, a, b = compute_anchor_oklab(chrom_ramps, function(r) return r.stops[#r.stops] end)
        if L then
            local _, C, h = oklab_to_oklch(L, a, b)
            local r8, g8, b8, Lf, Cf, hf = gamut_clip_oklch(L, C, h)
            shared_light = { r = r8, g = g8, b = b8, L = Lf, C = Cf, h = hf }
            for _, ramp in ipairs(chrom_ramps) do
                local s = ramp.stops[#ramp.stops]
                s.r, s.g, s.b, s.L, s.C, s.h = r8, g8, b8, Lf, Cf, hf
            end
        end
    end

    return shared_dark, shared_light
end

-- ============================================================
-- Remap
-- ============================================================

-- Squared OKLab distance.
local function oklab_d2(L1, a1, b1, L2, a2, b2)
    local dL = L1 - L2; local da = a1 - a2; local db = b1 - b2
    return dL * dL + da * da + db * db
end

-- ============================================================
-- Accent detection (rare-or-vivid colours preserved as standalone palette entries)
-- ============================================================

-- Compute combined salience (chroma MAD + visibility + frame coverage) for chromatic entries.
-- Returns: scores[i] in [0,1] per chromatic index, or nil if input too small/degenerate.
local function compute_accent_scores(chromatic, total_pixels, total_frames)
    local n = #chromatic
    if n < 4 then return nil end

    -- Median + MAD of chroma
    local cs = {}
    for i = 1, n do cs[i] = chromatic[i].C end
    table.sort(cs)
    local mid = math.floor(n / 2)
    local median_c = (n % 2 == 1) and cs[mid + 1] or (cs[mid] + cs[mid + 1]) * 0.5
    local devs = {}
    for i = 1, n do devs[i] = math.abs(cs[i] - median_c) end
    table.sort(devs)
    local mid2 = math.floor(n / 2)
    local mad = (n % 2 == 1) and devs[mid2 + 1] or (devs[mid2] + devs[mid2 + 1]) * 0.5
    local sigma_hat = 1.4826 * mad
    if sigma_hat < 1e-4 then sigma_hat = 1e-4 end

    -- Visibility normaliser
    local max_w = 1
    for i = 1, n do if chromatic[i].w > max_w then max_w = chromatic[i].w end end
    local log_denom = math.log(max_w + 1)
    if log_denom < 1e-6 then log_denom = 1e-6 end

    local tf = math.max(1, total_frames or 1)
    -- Upper frequency guard: ignore very common colours (≥ 12% of opaque pixels);
    -- those belong in ramps, not as standalone accents.
    local common_cutoff = math.max(1, total_pixels * 0.12)
    -- Pixel floor: skip 1-pixel noise on larger sprites; preserve singletons on tiny sprites.
    local pixel_floor = (total_pixels < 512) and 1 or math.max(2, math.ceil(total_pixels / 2000))

    -- Accents are chroma-led. Visibility and frame coverage act as GATES, not
    -- rewards: rewarding either pulls common ramp colours into the accent slots
    -- (the eye-red case where w=24 vivid loses to a w=210 mid-chroma skin tone).
    local scores = {}
    for i = 1, n do
        local e = chromatic[i]
        local frames = e.frames or 1
        -- Gates
        local single_frame_noise = (tf > 1) and (frames == 1) and (e.w <= 2)
        local too_rare = e.w < pixel_floor
        local too_common = e.w >= common_cutoff
        if too_rare or too_common or single_frame_noise then
            scores[i] = 0
        else
            local z = (e.C - median_c) / sigma_hat
            local S_c = math.max(0, math.min(1, z / 3.0))
            -- Light frame-stability tiebreaker: a vivid colour that recurs is more
            -- likely an intentional accent than a one-frame artefact, but the
            -- weight is small so it cannot promote a mid-chroma colour above a
            -- high-chroma one. Capped so single-cel-but-many-pixel accents
            -- (cel covers one frame, eg. eye glint) aren't unfairly penalised.
            local frame_factor = 0.85 + 0.15 * math.min(1.0, frames / math.max(2, tf * 0.5))
            scores[i] = S_c * frame_factor
        end
    end
    return scores
end

-- Pick the highest-salience entries above threshold, capped by max_slots.
local function select_accents(chromatic, scores, threshold, max_slots)
    if not scores or max_slots <= 0 then return {}, {} end
    local order = {}
    for i = 1, #chromatic do
        if scores[i] >= threshold then
            order[#order + 1] = { idx = i, score = scores[i] }
        end
    end
    table.sort(order, function(a, b) return a.score > b.score end)
    local accents, key_set = {}, {}
    for i = 1, math.min(max_slots, #order) do
        local e = chromatic[order[i].idx]
        accents[#accents + 1] = e
        key_set[e.key] = true
    end
    return accents, key_set
end

-- Build a filtered chromatic list excluding accents, plus a forward index map
-- (filtered_index -> original_chromatic_index) so cluster assignments can be unmapped later.
local function partition_accents(chromatic, accent_key_set)
    local filtered, to_orig = {}, {}
    for i, e in ipairs(chromatic) do
        if not accent_key_set[e.key] then
            filtered[#filtered + 1] = e
            to_orig[#filtered] = i
        end
    end
    return filtered, to_orig
end

-- Promote per-cluster chroma outliers to the accent list. The eye-red case: a vivid
-- colour folded into a hue-neighbouring brown ramp would otherwise dilute the cluster's
-- C_base and lose its punch. This pass strips those entries before ramp synthesis.
-- Mutates `clusters` (removes promoted indices) and returns a list of promoted entries.
local function promote_cluster_outliers(clusters, chrom_pool, slots_remaining, pixel_floor, abs_chroma_floor)
    if slots_remaining <= 0 then return {} end
    -- Collect all per-cluster candidates globally so the best score wins, not the earliest cluster.
    local candidates = {}     -- { ci, idx_in_cluster, entry, score }
    for ci, cluster in ipairs(clusters) do
        if #cluster >= 3 then
            local cs = {}
            for _, idx in ipairs(cluster) do cs[#cs + 1] = chrom_pool[idx].C end
            table.sort(cs)
            local mid = math.floor(#cs / 2)
            local med = (#cs % 2 == 1) and cs[mid + 1] or (cs[mid] + cs[mid + 1]) * 0.5
            local threshold = math.max(abs_chroma_floor, med * 1.8)
            for ii, idx in ipairs(cluster) do
                local e = chrom_pool[idx]
                if e.C > threshold and e.w >= pixel_floor then
                    -- Score: chroma magnitude × log visibility (in-cluster importance)
                    local score = e.C * (1.0 + math.log(1 + e.w))
                    candidates[#candidates + 1] = {
                        ci = ci, ii = ii, idx = idx, entry = e, score = score,
                    }
                end
            end
        end
    end
    if #candidates == 0 then return {} end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    local promoted = {}
    local removals = {}   -- ci -> set of ii's to drop
    for k = 1, math.min(slots_remaining, #candidates) do
        local c = candidates[k]
        promoted[#promoted + 1] = c.entry
        removals[c.ci] = removals[c.ci] or {}
        removals[c.ci][c.ii] = true
    end
    -- Rebuild affected clusters without the promoted indices.
    for ci, drop_set in pairs(removals) do
        local new_cluster = {}
        for ii, idx in ipairs(clusters[ci]) do
            if not drop_set[ii] then new_cluster[#new_cluster + 1] = idx end
        end
        clusters[ci] = new_cluster
    end
    return promoted
end

-- Build palette index for output. Shared anchors emitted once; (ramp, endpoint) pairs map to the shared index.
-- Returns: entries (palette), ordered_ramps, stop_to_pal map, accent_key_to_pi.
local function flatten_palette(ramps, alpha_present, shared_dark, shared_light, accents, accent_tolerance)
    local chroma, grey = {}, {}
    for _, r in ipairs(ramps) do
        if r.kind == "grey" then grey[#grey + 1] = r
        else chroma[#chroma + 1] = r end
    end
    table.sort(chroma, function(a, b) return a.base_h < b.base_h end)
    local ordered = {}
    for _, r in ipairs(chroma) do ordered[#ordered + 1] = r end
    for _, r in ipairs(grey) do ordered[#ordered + 1] = r end

    local entries = {}
    local stop_to_pal = {}

    local function emit(r8, g8, b8, ri, si)
        local L, A, B = rgb_to_oklab(r8, g8, b8)
        entries[#entries + 1] = {
            r = r8, g = g8, b = b8, a = 255, L = L, A = A, B = B, ramp = ri, stop = si,
        }
        return #entries - 1
    end

    if alpha_present then
        entries[#entries + 1] = { r = 0, g = 0, b = 0, a = 0, L = 0, A = 0, B = 0, ramp = 0, stop = 0 }
    end

    local n_chrom = #chroma
    local use_shared_dark = shared_dark and n_chrom >= 2
    local use_shared_light = shared_light and n_chrom >= 2

    local shared_dark_pi, shared_light_pi

    if use_shared_dark then
        shared_dark_pi = emit(shared_dark.r, shared_dark.g, shared_dark.b, -1, -1)
        for ri = 1, n_chrom do
            stop_to_pal[ri * 64 + 1] = shared_dark_pi
        end
    end

    for ri = 1, n_chrom do
        local ramp = chroma[ri]
        local n = #ramp.stops
        local first = use_shared_dark and 2 or 1
        local last = use_shared_light and (n - 1) or n
        for si = first, last do
            local s = ramp.stops[si]
            stop_to_pal[ri * 64 + si] = emit(s.r, s.g, s.b, ri, si)
        end
    end

    if use_shared_light then
        shared_light_pi = emit(shared_light.r, shared_light.g, shared_light.b, -1, -1)
        for ri = 1, n_chrom do
            stop_to_pal[ri * 64 + #chroma[ri].stops] = shared_light_pi
        end
    end

    -- Accents: emit each accent as a standalone entry unless an existing palette
    -- entry already matches it by exact RGB or sits within accent_tolerance ΔE in OKLab.
    local accent_key_to_pi = {}
    if accents and #accents > 0 then
        local rgb_to_pi = {}
        for pi_zero = 0, #entries - 1 do
            local pe = entries[pi_zero + 1]
            if pe.a ~= 0 then
                local rk = pe.r * 65536 + pe.g * 256 + pe.b
                if rgb_to_pi[rk] == nil then rgb_to_pi[rk] = pi_zero end
            end
        end
        local tol2 = (accent_tolerance or 0.07) ^ 2
        for _, ae in ipairs(accents) do
            local rk = ae.r * 65536 + ae.g * 256 + ae.b
            local match_pi = rgb_to_pi[rk]
            if match_pi == nil then
                local best_d2 = math.huge
                for pi_zero = 0, #entries - 1 do
                    local pe = entries[pi_zero + 1]
                    if pe.a ~= 0 then
                        local d2 = oklab_d2(ae.L, ae.A, ae.B, pe.L, pe.A, pe.B)
                        if d2 < best_d2 then
                            best_d2 = d2
                            if d2 <= tol2 then match_pi = pi_zero end
                        end
                    end
                end
            end
            if match_pi ~= nil then
                accent_key_to_pi[ae.key] = match_pi
            else
                accent_key_to_pi[ae.key] = emit(ae.r, ae.g, ae.b, -2, -2)
            end
        end
    end

    -- Grey ramps (each entry distinct, no sharing across grey ramps in v0.2)
    local grey_offset = n_chrom
    for gi, r in ipairs(grey) do
        local ri = grey_offset + gi
        for si, s in ipairs(r.stops) do
            stop_to_pal[ri * 64 + si] = emit(s.r, s.g, s.b, ri, si)
        end
    end

    return entries, ordered, stop_to_pal, accent_key_to_pi
end

local function build_remap(entries, assignments, palette_entries, ordered_ramps, stop_to_pal, skip_keys)
    local remap = {}
    for i, e in ipairs(entries) do
        if not (skip_keys and skip_keys[e.key]) then
            local ri = assignments[i]
            local ramp = ri and ordered_ramps[ri] or nil
            if ramp then
                local best_pi, best_d2 = 0, math.huge
                for si, s in ipairs(ramp.stops) do
                    local L, A, B = rgb_to_oklab(s.r, s.g, s.b)
                    local d2 = oklab_d2(e.L, e.A, e.B, L, A, B)
                    if d2 < best_d2 then
                        best_d2 = d2
                        best_pi = stop_to_pal[ri * 64 + si] or 0
                    end
                end
                remap[e.key] = best_pi
            end
        end
    end
    return remap
end

-- Solve stops_per_chrom_ramp to hit target_colours budget, given grey reserve and shared anchors.
-- palette_size = n_chrom * stops - savings + grey_stops + alpha_slot
-- where savings = (shared_dark ? n_chrom-1 : 0) + (shared_light ? n_chrom-1 : 0)
-- Returns: base_stops (int), per_ramp_extra (table of additional stops for ramps with widest L-span).
local STOPS_HARD_CAP <const> = 16

local function solve_stops_for_target(target, n_chrom, grey_stops, alpha_slot, shared_dark, shared_light, chrom_ramp_lspans)
    if n_chrom == 0 then return 0, {} end
    local alpha = alpha_slot and 1 or 0
    local savings = 0
    if n_chrom >= 2 then
        if shared_dark then savings = savings + (n_chrom - 1) end
        if shared_light then savings = savings + (n_chrom - 1) end
    end
    local remaining = target - grey_stops - alpha + savings
    local base = math.floor(remaining / n_chrom + 0.5)
    if base < 2 then base = 2 end
    if base > STOPS_HARD_CAP then base = STOPS_HARD_CAP end

    -- Allocate leftover budget to ramps with widest source L-span.
    local extra = {}
    for i = 1, n_chrom do extra[i] = 0 end
    if not chrom_ramp_lspans then return base, extra end

    local function palette_size_for(base_n, extras)
        local total_stops = 0
        for i = 1, n_chrom do total_stops = total_stops + base_n + extras[i] end
        return total_stops - savings + grey_stops + alpha
    end

    -- Indices sorted by descending L-span
    local order = {}
    for i = 1, n_chrom do order[i] = i end
    table.sort(order, function(a, b) return chrom_ramp_lspans[a] > chrom_ramp_lspans[b] end)

    local guard = 0
    while palette_size_for(base, extra) < target and guard < n_chrom * STOPS_HARD_CAP do
        local progressed = false
        for _, ri in ipairs(order) do
            if base + extra[ri] < STOPS_HARD_CAP then
                extra[ri] = extra[ri] + 1
                progressed = true
                if palette_size_for(base, extra) >= target then break end
            end
        end
        if not progressed then break end
        guard = guard + 1
    end

    return base, extra
end

-- ============================================================
-- Main
-- ============================================================

local function parse_cli_params(cfg)
    local p = app.params or {}
    local function num(name)
        if p[name] == nil or p[name] == "" then return nil end
        local n = tonumber(p[name])
        if not n then error(name .. " must be a number.") end
        return n
    end
    local function bool(name)
        if p[name] == nil or p[name] == "" then return nil end
        local s = tostring(p[name]):lower()
        return s == "1" or s == "true" or s == "yes"
    end
    local function str(name)
        if p[name] == nil or p[name] == "" then return nil end
        return tostring(p[name])
    end

    cfg.mode = str("mode") or cfg.mode
    cfg.size_mode = str("size_mode") or cfg.size_mode
    cfg.target_colours = num("target_colours") or cfg.target_colours
    cfg.ramps = num("ramps") or cfg.ramps
    cfg.stops = num("stops") or cfg.stops
    cfg.strength = num("strength") or cfg.strength
    cfg.output = str("output") or cfg.output
    cfg.highlight_pull = num("highlight_pull") or cfg.highlight_pull
    cfg.shadow_pull = num("shadow_pull") or cfg.shadow_pull
    cfg.warm_attractor_hue = num("warm_attractor_hue") or cfg.warm_attractor_hue
    cfg.cool_attractor_hue = num("cool_attractor_hue") or cfg.cool_attractor_hue
    cfg.chroma_ceiling = num("chroma_ceiling") or cfg.chroma_ceiling
    cfg.achromatic_threshold = num("achromatic_threshold") or cfg.achromatic_threshold
    cfg.grey_budget = num("grey_budget") or cfg.grey_budget
    local ss = bool("shared_shadow"); if ss ~= nil then cfg.shared_shadow = ss end
    local sh = bool("shared_highlight"); if sh ~= nil then cfg.shared_highlight = sh end
    local ad = bool("accent_detection"); if ad ~= nil then cfg.accent_detection = ad end
    cfg.max_accent_slots = num("max_accent_slots") or cfg.max_accent_slots
    cfg.accent_score_threshold = num("accent_score_threshold") or cfg.accent_score_threshold
    cfg.accent_tolerance = num("accent_tolerance") or cfg.accent_tolerance
    cfg.accent_cluster_floor = num("accent_cluster_floor") or cfg.accent_cluster_floor
    return cfg
end

local function run(cfg)
    local sprite = app.activeSprite
    if not sprite then fail("No active sprite.") ; return end
    if sprite.colorMode ~= ColorMode.RGB then
        fail("Sprite must be in RGB colour mode. Use Sprite > Color Mode > RGB.")
        return
    end

    if cfg.mode == "Stylise" then cfg.strength = 1.0 end
    cfg.strength = clamp(cfg.strength, 0, 1)

    -- 1. Histogram (composited per-frame)
    local hist, alpha_present, frames_seen, total_frames = collect_histogram(sprite)
    local unique_count = 0
    for _ in pairs(hist) do unique_count = unique_count + 1 end
    if unique_count == 0 then
        fail("Sprite has no opaque pixels.")
        return
    end

    -- 2. Convert all unique colours to OKLab/OKLCh
    local entries = {}
    for key, w in pairs(hist) do
        local r = math.floor(key / 65536) % 256
        local g = math.floor(key / 256) % 256
        local b = key % 256
        local L, A, B = rgb_to_oklab(r, g, b)
        local _, C, h = oklab_to_oklch(L, A, B)
        entries[#entries + 1] = {
            key = key, r = r, g = g, b = b, w = w,
            L = L, A = A, B = B, C = C, h = h,
            frames = frames_seen[key] or 1,
        }
    end

    -- 3. Split chromatic vs achromatic
    local chromatic, achromatic = {}, {}
    for _, e in ipairs(entries) do
        if e.C >= cfg.achromatic_threshold then
            chromatic[#chromatic + 1] = e
        else
            achromatic[#achromatic + 1] = e
        end
    end

    -- 3b. Accent detection: identify rare-or-vivid colours to preserve verbatim.
    local total_opaque = 0
    for _, e in ipairs(entries) do total_opaque = total_opaque + e.w end
    local pixel_floor = (total_opaque < 512) and 1 or math.max(2, math.ceil(total_opaque / 2000))

    local accents, accent_key_set = {}, {}
    if cfg.accent_detection and cfg.max_accent_slots and cfg.max_accent_slots > 0 then
        local scores = compute_accent_scores(chromatic, total_opaque, total_frames)
        if scores then
            local hard_cap = math.max(0, math.floor((#chromatic - 1) / 3))
            local cap = math.min(cfg.max_accent_slots, hard_cap)
            -- Reserve at least half the slots for per-cluster promotion downstream,
            -- which is the only signal that can rescue intra-cluster vivid outliers
            -- (e.g. an eye red trapped inside a brown cluster's k-means partition).
            -- Initial pass only takes genuine sprite-wide outliers; promotion picks
            -- up local outliers afterwards.
            local initial_cap = math.max(1, math.floor(cap / 2))
            accents, accent_key_set = select_accents(chromatic, scores, cfg.accent_score_threshold, initial_cap)
        end
    end

    -- 3b'. Budget pre-trim: in "Total colours" mode, drop accents from the tail until
    -- the remaining budget can accommodate at least the minimum ramps + grey + alpha.
    -- Done before partitioning so dropped accents fall back into the cluster pool.
    if cfg.size_mode == "Total colours" and #accents > 0 then
        local has_grey = #achromatic > 0
        local grey_stops = has_grey and math.max(2, math.min(cfg.grey_stops_max, cfg.grey_budget)) or 0
        local alpha_slot = alpha_present and 1 or 0
        -- Pessimistic n_chrom estimate: if user pinned ramps, use it; otherwise take an upper bound.
        local n_chrom_est
        if cfg.ramps and cfg.ramps > 0 then
            n_chrom_est = math.floor(cfg.ramps)
        else
            n_chrom_est = math.min(cfg.elbow_kmax, math.max(0, #chromatic - #accents))
        end
        local min_ramp_slots = 2 * n_chrom_est       -- at least 2 stops per ramp
        while #accents > 0
            and (cfg.target_colours - #accents) < (min_ramp_slots + grey_stops + alpha_slot) do
            local dropped = accents[#accents]
            accent_key_set[dropped.key] = nil
            accents[#accents] = nil
        end
    end

    -- 3c. Filter accents out of chromatic pool used for clustering.
    local chrom_for_cluster, cluster_to_chrom_idx
    if #accents > 0 then
        chrom_for_cluster, cluster_to_chrom_idx = partition_accents(chromatic, accent_key_set)
    else
        chrom_for_cluster = chromatic
        cluster_to_chrom_idx = {}
        for i = 1, #chromatic do cluster_to_chrom_idx[i] = i end
    end

    -- 4. Decide ramp count (from cfg or elbow)
    local target_ramps
    if cfg.ramps and cfg.ramps > 0 then
        target_ramps = math.floor(cfg.ramps)
    else
        if #chrom_for_cluster >= 2 then
            -- Auto: pick elbow, but in Total-colours mode also enforce a floor based on
            -- target_colours so a big budget doesn't get bottlenecked into 2 fat ramps.
            -- Empirical: ~sqrt(target) gives a healthy ramp-vs-stop ratio. Clamp to a
            -- generous cap so we still consolidate when the sprite has few hues.
            local elbow_cap = math.min(cfg.elbow_kmax, #chrom_for_cluster)
            local k_floor = 2
            if cfg.size_mode == "Total colours" and cfg.target_colours then
                local budget_floor = math.floor(math.sqrt(math.max(4, cfg.target_colours - #accents)) + 0.5)
                k_floor = math.max(k_floor, math.min(budget_floor, elbow_cap))
            end
            local k_elbow = elbow_k(chrom_for_cluster, elbow_cap)
            target_ramps = math.max(k_elbow, k_floor)
        else
            target_ramps = #chrom_for_cluster
        end
    end
    target_ramps = clamp(target_ramps, 0, math.max(0, #chrom_for_cluster))

    -- 5. Cluster chromatic colours by hue
    local clusters, centroids = {}, {}
    if target_ramps > 0 then
        clusters, centroids = kmeans_hue(chrom_for_cluster, target_ramps, cfg.kmeans_max_iter, cfg.kmeans_seed)
        local kept_c, kept_h = {}, {}
        for j = 1, #clusters do
            if #clusters[j] >= 1 then
                kept_c[#kept_c + 1] = clusters[j]
                kept_h[#kept_h + 1] = centroids[j]
            end
        end
        clusters, centroids = kept_c, kept_h
    end

    -- 5b. Per-cluster outlier promotion: catches vivid colours bucketed into a
    -- hue-neighbouring ramp (e.g. red eye dropped into a brown ramp) that would
    -- otherwise be averaged out by the cluster's chroma percentile.
    if cfg.accent_detection and #clusters > 0 then
        local slots_left = cfg.max_accent_slots - #accents
        if slots_left > 0 then
            local promoted = promote_cluster_outliers(
                clusters, chrom_for_cluster, slots_left,
                pixel_floor, cfg.accent_cluster_floor)
            for _, e in ipairs(promoted) do
                if not accent_key_set[e.key] then
                    accents[#accents + 1] = e
                    accent_key_set[e.key] = true
                end
            end
            -- Drop any clusters that emptied out after promotion.
            local kept_c, kept_h = {}, {}
            for j = 1, #clusters do
                if #clusters[j] >= 1 then
                    kept_c[#kept_c + 1] = clusters[j]
                    kept_h[#kept_h + 1] = centroids[j]
                end
            end
            clusters, centroids = kept_c, kept_h
        end
    end

    -- 6. Decide stops per ramp.
    -- If size_mode = "Total colours", solve from target_colours budget given shared-anchor savings.
    local stops_override
    local per_ramp_extra = nil
    if cfg.size_mode == "Total colours" then
        local n_chrom = #clusters
        local has_grey = #achromatic > 0
        local grey_stops = has_grey and math.max(2, math.min(cfg.grey_stops_max, cfg.grey_budget)) or 0
        -- Pre-compute each cluster's source lightness span so the solver can prefer
        -- ramps with the widest range when distributing leftover budget.
        local lspans = {}
        for ci, cluster in ipairs(clusters) do
            local lo, hi = math.huge, -math.huge
            for _, idx in ipairs(cluster) do
                local L = chrom_for_cluster[idx].L
                if L < lo then lo = L end
                if L > hi then hi = L end
            end
            lspans[ci] = hi - lo
        end
        -- Reserve accent slots out of the budget so the final palette honours the target.
        local effective_target = cfg.target_colours - #accents
        local base
        base, per_ramp_extra = solve_stops_for_target(
            effective_target, n_chrom, grey_stops, alpha_present,
            cfg.shared_shadow, cfg.shared_highlight, lspans)
        stops_override = base
        cfg._grey_stops_forced = grey_stops
    else
        stops_override = (cfg.stops and cfg.stops > 0) and math.floor(cfg.stops) or 0
    end

    -- 7. Build chromatic ramps
    local ramps = {}
    local chromatic_assignments = {}
    for j, cluster in ipairs(clusters) do
        local stops_for_this = stops_override
        if per_ramp_extra and per_ramp_extra[j] then
            stops_for_this = stops_override + per_ramp_extra[j]
        end
        ramps[#ramps + 1] = build_chromatic_ramp(chrom_for_cluster, cluster, cfg, stops_for_this)
        for _, ci in ipairs(cluster) do
            chromatic_assignments[ci] = #ramps
        end
    end

    -- 8. Apply shared anchors to chromatic ramps (mutates ramp stops in place)
    local chrom_ramps = {}
    for _, r in ipairs(ramps) do
        if r.kind == "chromatic" then chrom_ramps[#chrom_ramps + 1] = r end
    end
    local shared_dark, shared_light = apply_shared_anchors(chrom_ramps, cfg)

    -- 9. Build grey ramp
    if #achromatic > 0 then
        local idx = {}
        for i = 1, #achromatic do idx[i] = i end
        local grey_stops_arg = cfg._grey_stops_forced or stops_override
        local grey = build_grey_ramp(achromatic, idx, cfg, grey_stops_arg)
        if grey then
            ramps[#ramps + 1] = grey
        end
    end

    if #ramps == 0 and #accents == 0 then
        fail("Could not build any ramps from sprite.")
        return
    end

    -- 10. Flatten palette (also emits accents between shared_light and grey)
    local palette_entries, ordered_ramps, stop_to_pal, accent_key_to_pi =
        flatten_palette(ramps, alpha_present, shared_dark, shared_light, accents, cfg.accent_tolerance)

    local params_dbg = app.params or {}
    if params_dbg.debug == "1" or params_dbg.debug == "true" then
        print(string.format("[debug] entries=%d chromatic=%d accents=%d ramps=%d palette=%d frames=%d",
            #entries, #chromatic, #accents, #ramps, #palette_entries, total_frames or 1))
        for i, a in ipairs(accents) do
            print(string.format("[debug] accent %d #%02X%02X%02X C=%.3f w=%d frames=%d/%d",
                i, a.r, a.g, a.b, a.C, a.w, a.frames or 1, total_frames or 1))
        end
    end

    -- 11. Re-map original assignments to (possibly reordered) ordered_ramps
    local ramp_to_ordered = {}
    for orig_i, r in ipairs(ramps) do
        for new_i, or_r in ipairs(ordered_ramps) do
            if or_r == r then ramp_to_ordered[orig_i] = new_i; break end
        end
    end

    -- 12. Build per-source assignments over `entries` array
    local source_assignments = {}
    -- Map original chromatic index -> entry index
    local chrom_to_entry = {}
    do
        local ci = 0
        for ei, e in ipairs(entries) do
            if e.C >= cfg.achromatic_threshold then
                ci = ci + 1
                chrom_to_entry[ci] = ei
            end
        end
    end
    local grey_ordered_index = nil
    for i, r in ipairs(ordered_ramps) do
        if r.kind == "grey" then grey_ordered_index = i; break end
    end
    for ei, e in ipairs(entries) do
        if e.C < cfg.achromatic_threshold and grey_ordered_index then
            source_assignments[ei] = grey_ordered_index
        end
    end
    -- chromatic_assignments is keyed by index into chrom_for_cluster; map via cluster_to_chrom_idx.
    for filtered_ci, ramp_idx in pairs(chromatic_assignments) do
        local orig_ci = cluster_to_chrom_idx[filtered_ci]
        if orig_ci then
            local ei = chrom_to_entry[orig_ci]
            if ei then source_assignments[ei] = ramp_to_ordered[ramp_idx] end
        end
    end

    local remap = build_remap(entries, source_assignments, palette_entries, ordered_ramps, stop_to_pal, accent_key_set)
    -- Direct accent mappings (skip the ramp distance search).
    if accent_key_to_pi then
        for k, pi in pairs(accent_key_to_pi) do remap[k] = pi end
    end

    -- 9. Apply: write new palette + remap pixels
    app.transaction(COMMAND_TITLE, function()
        -- Build Palette object
        local new_pal = Palette(#palette_entries)
        for i, p in ipairs(palette_entries) do
            new_pal:setColor(i - 1, Color { r = p.r, g = p.g, b = p.b, a = p.a })
        end
        sprite:setPalette(new_pal)

        if cfg.output == "In place" then
            for _, layer in ipairs(sprite.layers) do
                if layer.isVisible and layer.isEditable and not layer.isReference then
                    for _, cel in ipairs(layer.cels) do
                        local img = cel.image
                        if img then
                            local newImg = img:clone()
                            for it in newImg:pixels() do
                                local px = it()
                                local a = pc.rgbaA(px)
                                if a ~= 0 then
                                    local r = pc.rgbaR(px); local g = pc.rgbaG(px); local b = pc.rgbaB(px)
                                    local key = r * 65536 + g * 256 + b
                                    local pi = remap[key]
                                    if pi then
                                        local pe = palette_entries[pi + 1]
                                        it(pc.rgba(pe.r, pe.g, pe.b, a))
                                    end
                                end
                            end
                            cel.image = newImg
                        end
                    end
                end
            end
        else
            -- New layer
            local layer_name = OUTPUT_LAYER_NAME
            local existing_names = {}
            for _, l in ipairs(sprite.layers) do existing_names[l.name] = true end
            local n = 1
            while existing_names[layer_name] do
                n = n + 1
                layer_name = OUTPUT_LAYER_NAME .. " " .. n
            end
            local newLayer = sprite:newLayer()
            newLayer.name = layer_name
            for f = 1, #sprite.frames do
                local composite = Image(sprite.spec)
                composite:drawSprite(sprite, f)
                for it in composite:pixels() do
                    local px = it()
                    local a = pc.rgbaA(px)
                    if a ~= 0 then
                        local r = pc.rgbaR(px); local g = pc.rgbaG(px); local b = pc.rgbaB(px)
                        local key = r * 65536 + g * 256 + b
                        local pi = remap[key]
                        if pi then
                            local pe = palette_entries[pi + 1]
                            it(pc.rgba(pe.r, pe.g, pe.b, a))
                        end
                    end
                end
                sprite:newCel(newLayer, f, composite, Point(0, 0))
            end
        end
    end)

    app.refresh()
end

-- ============================================================
-- Dialog UI
-- ============================================================

local function show_dialog()
    local cfg = {}
    for k, v in pairs(DEFAULT_CONFIG) do cfg[k] = v end
    parse_cli_params(cfg)

    local dlg = Dialog(COMMAND_TITLE)
    dlg:combobox { id = "mode", label = "Mode", option = cfg.mode,
        options = { "Hybrid", "Stylise" } }
    dlg:combobox {
        id = "size_mode", label = "Size by", option = cfg.size_mode,
        options = { "Ramps x Stops", "Total colours" },
        onchange = function()
            local d = dlg.data
            local total = d.size_mode == "Total colours"
            dlg:modify { id = "target_colours", visible = total }
            dlg:modify { id = "stops", visible = not total }
        end,
    }
    dlg:number { id = "target_colours", label = "Target colours",
        text = tostring(cfg.target_colours), decimals = 0,
        visible = cfg.size_mode == "Total colours" }
    dlg:number { id = "ramps", label = "Ramps (0 = auto)", text = tostring(cfg.ramps), decimals = 0 }
    dlg:number { id = "stops", label = "Stops per ramp (0 = auto)",
        text = tostring(cfg.stops), decimals = 0,
        visible = cfg.size_mode ~= "Total colours" }
    dlg:slider { id = "strength", label = "Strength", min = 0, max = 100, value = round(cfg.strength * 100) }
    dlg:separator { text = "Accent preservation" }
    dlg:check { id = "accent_detection", label = "Preserve accents",
        selected = cfg.accent_detection,
        onclick = function()
            local on = dlg.data.accent_detection
            dlg:modify { id = "max_accent_slots", visible = on }
        end,
    }
    dlg:number { id = "max_accent_slots", label = "Accent slots",
        text = tostring(cfg.max_accent_slots), decimals = 0,
        visible = cfg.accent_detection }
    dlg:separator()
    dlg:combobox { id = "output", label = "Output", option = cfg.output,
        options = { "New layer", "In place" } }
    dlg:separator()
    dlg:button { id = "apply", text = "Apply", focus = true }
    dlg:button { id = "cancel", text = "Cancel" }
    dlg:show { wait = true }

    local data = dlg.data
    if not data.apply then return end

    cfg.mode = data.mode
    cfg.size_mode = data.size_mode
    cfg.target_colours = data.target_colours or cfg.target_colours
    cfg.ramps = data.ramps or 0
    cfg.stops = data.stops or 0
    cfg.strength = (data.strength or 50) / 100.0
    cfg.accent_detection = data.accent_detection
    cfg.max_accent_slots = data.max_accent_slots or cfg.max_accent_slots
    cfg.output = data.output
    run(cfg)
end

if app.isUIAvailable then
    show_dialog()
else
    local cfg = {}
    for k, v in pairs(DEFAULT_CONFIG) do cfg[k] = v end
    parse_cli_params(cfg)
    run(cfg)
end

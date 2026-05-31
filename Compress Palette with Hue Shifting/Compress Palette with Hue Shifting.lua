-- Compress Palette with Hue Shifting V0.1
-- Install:
-- 1. Save this file as "Compress Palette with Hue Shifting.lua".
-- 2. Copy or symlink it (and its folder) into %APPDATA%\Aseprite\scripts.
-- 3. In Aseprite, run File > Scripts > Rescan Scripts, or restart Aseprite.
-- 4. Run File > Scripts > Compress Palette with Hue Shifting.

local COMMAND_TITLE <const> = "Compress Palette with Hue Shifting"
local OUTPUT_LAYER_NAME <const> = "Compressed (Hue-Shifted)"

local DEFAULT_CONFIG <const> = {
    mode = "Hybrid",                -- Hybrid | Stylise
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
    shared_shadow = false,
    kmeans_max_iter = 40,
    kmeans_seed = 42,
    elbow_kmax = 8,
    grey_stops_max = 5,
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

local function collect_histogram(sprite)
    local hist = {}                  -- key = packed rgba (alpha-0 excluded) -> count
    local alpha_present = false
    for _, layer in ipairs(sprite.layers) do
        if layer.isVisible and not layer.isReference then
            for _, cel in ipairs(layer.cels) do
                local img = cel.image
                if img then
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
                            if a < 255 then alpha_present = true end
                        end
                    end
                end
            end
        end
    end
    return hist, alpha_present
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

    local C_base = percentile({ table.unpack(Cs) }, 0.75)
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
    n = clamp(n, 2, 8)

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
    return { stops = stops, base_h = base_h, kind = "chromatic" }
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
    return { stops = stops, base_h = 0, kind = "grey" }
end

-- ============================================================
-- Remap
-- ============================================================

-- Squared OKLab distance.
local function oklab_d2(L1, a1, b1, L2, a2, b2)
    local dL = L1 - L2; local da = a1 - a2; local db = b1 - b2
    return dL * dL + da * da + db * db
end

-- Build palette index for output (palette ordering: ramp by hue asc, stops dark->light, grey last; transparent first if needed).
local function flatten_palette(ramps, alpha_present)
    -- Order ramps: chromatic by base_h asc, then grey last
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
    if alpha_present then
        entries[#entries + 1] = { r = 0, g = 0, b = 0, a = 0, L = 0, A = 0, B = 0, ramp = 0, stop = 0 }
    end
    for ri, r in ipairs(ordered) do
        for si, s in ipairs(r.stops) do
            local L, A, B = rgb_to_oklab(s.r, s.g, s.b)
            entries[#entries + 1] = {
                r = s.r, g = s.g, b = s.b, a = 255,
                L = L, A = A, B = B,
                ramp = ri, stop = si,
            }
        end
    end
    return entries, ordered
end

-- Build per-source-colour remap table: rgb_key -> palette index.
-- Constrained remap: assignments[i] gives source colour i's assigned ramp; remap to nearest stop within that ramp.
local function build_remap(entries, assignments, palette, ordered_ramps)
    -- Map (ramp index in `ordered_ramps`, stop index) -> palette index.
    local stop_to_pal = {}
    for pi, p in ipairs(palette) do
        if p.ramp > 0 then
            stop_to_pal[p.ramp * 16 + p.stop] = pi - 1   -- 0-based palette index
        end
    end

    -- Source ramp index -> ordered ramp index lookup is identity in our setup
    -- because we build `ramps` in the same order as `assignments`.

    local remap = {}
    for i, e in ipairs(entries) do
        local ri = assignments[i]
        local ramp = ordered_ramps[ri]
        local best_pi, best_d2 = 0, math.huge
        for si, s in ipairs(ramp.stops) do
            local L, A, B = rgb_to_oklab(s.r, s.g, s.b)
            local d2 = oklab_d2(e.L, e.A, e.B, L, A, B)
            if d2 < best_d2 then
                best_d2 = d2
                best_pi = stop_to_pal[ri * 16 + si] or 0
            end
        end
        remap[e.key] = best_pi
    end
    return remap
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
    local ss = bool("shared_shadow"); if ss ~= nil then cfg.shared_shadow = ss end
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

    -- 1. Histogram
    local hist, alpha_present = collect_histogram(sprite)
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

    -- 4. Decide ramp count
    local target_ramps
    if cfg.ramps and cfg.ramps > 0 then
        target_ramps = math.floor(cfg.ramps)
    else
        if #chromatic >= 2 then
            target_ramps = elbow_k(chromatic, math.min(cfg.elbow_kmax, #chromatic))
        else
            target_ramps = #chromatic
        end
    end
    target_ramps = clamp(target_ramps, 0, math.max(0, #chromatic))

    -- 5. Cluster chromatic colours by hue
    local clusters, centroids = {}, {}
    if target_ramps > 0 then
        clusters, centroids = kmeans_hue(chromatic, target_ramps, cfg.kmeans_max_iter, cfg.kmeans_seed)
        -- Drop empty clusters
        local kept_c, kept_h = {}, {}
        for j = 1, #clusters do
            if #clusters[j] >= 1 then
                kept_c[#kept_c + 1] = clusters[j]
                kept_h[#kept_h + 1] = centroids[j]
            end
        end
        clusters, centroids = kept_c, kept_h
    end

    -- 6. Build ramps
    local stops_override = (cfg.stops and cfg.stops > 0) and math.floor(cfg.stops) or 0
    local ramps = {}
    local chromatic_assignments = {}    -- chromatic entry index -> ramp index in `ramps`
    for j, cluster in ipairs(clusters) do
        ramps[#ramps + 1] = build_chromatic_ramp(chromatic, cluster, cfg, stops_override)
        for _, ci in ipairs(cluster) do
            chromatic_assignments[ci] = #ramps
        end
    end

    if #achromatic > 0 then
        -- Build grey ramp from indices
        local idx = {}
        for i = 1, #achromatic do idx[i] = i end
        local grey = build_grey_ramp(achromatic, idx, cfg, stops_override)
        if grey then
            ramps[#ramps + 1] = grey
        end
    end

    if #ramps == 0 then
        fail("Could not build any ramps from sprite.")
        return
    end

    -- 7. Flatten palette + ordering
    local palette_entries, ordered_ramps = flatten_palette(ramps, alpha_present)

    -- Re-map original assignments to the (possibly reordered) ramp indices in `ordered_ramps`
    local ramp_to_ordered = {}
    for orig_i, r in ipairs(ramps) do
        for new_i, or_r in ipairs(ordered_ramps) do
            if or_r == r then ramp_to_ordered[orig_i] = new_i; break end
        end
    end

    -- 8. Build assignments table over all source entries, then remap
    local source_assignments = {}    -- entries-array index -> ordered ramp index
    -- We need to map chromatic-list indices back to entries-list indices
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
    -- Grey ramp index in ordered_ramps (last one if exists)
    local grey_ordered_index = nil
    for i, r in ipairs(ordered_ramps) do
        if r.kind == "grey" then grey_ordered_index = i; break end
    end
    for ei, e in ipairs(entries) do
        if e.C >= cfg.achromatic_threshold then
            -- find chromatic index
        else
            if grey_ordered_index then source_assignments[ei] = grey_ordered_index end
        end
    end
    for ci, ramp_idx in pairs(chromatic_assignments) do
        local ei = chrom_to_entry[ci]
        source_assignments[ei] = ramp_to_ordered[ramp_idx]
    end

    local remap = build_remap(entries, source_assignments, palette_entries, ordered_ramps)

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
    dlg:number { id = "ramps", label = "Ramps (0 = auto)", text = tostring(cfg.ramps), decimals = 0 }
    dlg:number { id = "stops", label = "Stops per ramp (0 = auto)", text = tostring(cfg.stops), decimals = 0 }
    dlg:slider { id = "strength", label = "Strength", min = 0, max = 100, value = round(cfg.strength * 100) }
    dlg:combobox { id = "output", label = "Output", option = cfg.output,
        options = { "New layer", "In place" } }
    dlg:separator()
    dlg:button { id = "apply", text = "Apply", focus = true }
    dlg:button { id = "cancel", text = "Cancel" }
    dlg:show { wait = true }

    local data = dlg.data
    if not data.apply then return end

    cfg.mode = data.mode
    cfg.ramps = data.ramps or 0
    cfg.stops = data.stops or 0
    cfg.strength = (data.strength or 50) / 100.0
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

-- Histogram all source pixels across all frames/layers, sorted by count.
-- Plus filter to "greenish" pixels to see the eye-colour cluster.
local spr = app.activeSprite
local pc = app.pixelColor

local function rgba_unmul(c)
    local a = pc.rgbaA(c); if a == 0 then return nil end
    return pc.rgbaR(c), pc.rgbaG(c), pc.rgbaB(c), a
end

local hist = {}
for _, layer in ipairs(spr.layers) do
    if layer.isVisible and layer.isImage then
        for _, cel in ipairs(layer.cels) do
            local img, pos = cel.image, cel.position
            for it in img:pixels() do
                local r, g, b, a = rgba_unmul(it())
                if r and a > 0 then
                    local k = string.format("#%02X%02X%02X", r, g, b)
                    hist[k] = (hist[k] or 0) + 1
                end
            end
        end
    end
end

local entries = {}
for k, v in pairs(hist) do table.insert(entries, {k=k, n=v}) end
table.sort(entries, function(a, b) return a.n > b.n end)

print("=== top 60 source colours ===")
for i = 1, math.min(60, #entries) do
    print(string.format("%2d  %s  x%d", i, entries[i].k, entries[i].n))
end

print("=== greenish (G dominant by >=12) ===")
for _, e in ipairs(entries) do
    local r = tonumber(e.k:sub(2,3), 16)
    local g = tonumber(e.k:sub(4,5), 16)
    local b = tonumber(e.k:sub(6,7), 16)
    if g > r + 12 and g > b + 4 then
        print(string.format("  %s  x%d  (r=%d g=%d b=%d)", e.k, e.n, r, g, b))
    end
end

print(string.format("=== total unique = %d ===", #entries))

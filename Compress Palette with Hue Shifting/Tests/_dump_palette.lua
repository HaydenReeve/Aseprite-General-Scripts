-- Run the compressor with output=New layer, then dump the resulting palette
-- and the colours actually present at the shirt/skin boundary region.
app.params.output = "New layer"
app.params.size_mode = "Total colours"
app.params.target_colours = app.params.target_colours or "64"
app.params.quiet = "true"
dofile("D:/Aseprite/Compress Palette with Hue Shifting/Compress Palette with Hue Shifting.lua")

local spr = app.activeSprite
print("=== palette ===")
local pal = spr.palettes[1]
for i = 0, #pal - 1 do
    local c = pal:getColor(i)
    print(string.format("%02d  #%02X%02X%02X  rgba(%d,%d,%d,%d)", i, c.red, c.green, c.blue, c.red, c.green, c.blue, c.alpha))
end

-- Sample the compressed-output layer at frame 1, in the user's region of interest.
-- Region: skin 30..37 x 25..27, shirt 27..35 x 28..31
local out_layer
for _, l in ipairs(spr.layers) do
    if l.name == "Compressed (Hue-Shifted)" then out_layer = l; break end
end
if out_layer then
    local cel = out_layer:cel(1)
    if cel then
        local img = cel.image
        local pos = cel.position
        local function at(x, y)
            local lx, ly = x - pos.x, y - pos.y
            if lx < 0 or ly < 0 or lx >= img.width or ly >= img.height then return nil end
            return img:getPixel(lx, ly)
        end
        local pc = app.pixelColor
        local function dump(label, x0, y0, x1, y1)
            print(string.format("--- %s (%d,%d)..(%d,%d) ---", label, x0, y0, x1, y1))
            local seen = {}
            for y = y0, y1 do
                for x = x0, x1 do
                    local px = at(x, y)
                    if px and pc.rgbaA(px) > 0 then
                        local k = string.format("#%02X%02X%02X", pc.rgbaR(px), pc.rgbaG(px), pc.rgbaB(px))
                        seen[k] = (seen[k] or 0) + 1
                    end
                end
            end
            for k, n in pairs(seen) do print(string.format("  %s x%d", k, n)) end
        end
        dump("skin", 30, 25, 37, 27)
        dump("shirt", 27, 28, 35, 31)
    else
        print("(no cel on output layer at frame 1)")
    end
else
    print("(compressed output layer not found)")
end

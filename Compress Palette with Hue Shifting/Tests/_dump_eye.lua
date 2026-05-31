-- Find eye-coloured pixels in source vs same coords in output, across all frames.
app.params.output = "New layer"
app.params.size_mode = "Total colours"
app.params.target_colours = "64"
app.params.quiet = "true"
dofile("D:/Aseprite/Compress Palette with Hue Shifting/Compress Palette with Hue Shifting.lua")

local spr = app.activeSprite
local pc = app.pixelColor

local out_layer
for _, l in ipairs(spr.layers) do
    if l.name == "Compressed (Hue-Shifted)" then out_layer = l; break end
end

-- Walk all source layers (visible, image), find any pixel matching the eye green
-- and report its frame, position, and compressed-output value at same coords.
local TARGETS = { ["#37946E"] = true, ["#558766"] = true }

local function key(c) return string.format("#%02X%02X%02X", pc.rgbaR(c), pc.rgbaG(c), pc.rgbaB(c)) end

print("=== source eye-green pixels and their compressed equivalents ===")
for fnum = 1, #spr.frames do
    local out_cel = out_layer:cel(fnum)
    local out_img, out_pos
    if out_cel then out_img, out_pos = out_cel.image, out_cel.position end
    for _, layer in ipairs(spr.layers) do
        if layer.isVisible and layer.isImage and layer.name ~= "Compressed (Hue-Shifted)" then
            local cel = layer:cel(fnum)
            if cel then
                local img, pos = cel.image, cel.position
                for it in img:pixels() do
                    local v = it()
                    if pc.rgbaA(v) > 0 then
                        local k = key(v)
                        if TARGETS[k] then
                            local sx, sy = it.x + pos.x, it.y + pos.y
                            local out_v = nil
                            if out_img then
                                local lx, ly = sx - out_pos.x, sy - out_pos.y
                                if lx >= 0 and ly >= 0 and lx < out_img.width and ly < out_img.height then
                                    out_v = out_img:getPixel(lx, ly)
                                end
                            end
                            print(string.format("frame=%d (%d,%d) src=%s out=%s",
                                fnum, sx, sy, k, out_v and key(out_v) or "?"))
                        end
                    end
                end
            end
        end
    end
end

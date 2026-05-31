-- Inspect sprite structure
local spr = app.activeSprite
print("frames=" .. #spr.frames)
print("layers=" .. #spr.layers)
for i, l in ipairs(spr.layers) do
    print(string.format("  layer %d: name=%q visible=%s editable=%s reference=%s cels=%d",
        i, l.name, tostring(l.isVisible), tostring(l.isEditable), tostring(l.isReference), #l.cels))
end
-- Count raw cel pixels per layer
for _, l in ipairs(spr.layers) do
    if l.isVisible and not l.isReference then
        local raw_total = 0
        local unique = {}
        for _, cel in ipairs(l.cels) do
            if cel.image then
                for it in cel.image:pixels() do
                    local px = it()
                    if app.pixelColor.rgbaA(px) > 0 then
                        raw_total = raw_total + 1
                        local r = app.pixelColor.rgbaR(px); local g = app.pixelColor.rgbaG(px); local b = app.pixelColor.rgbaB(px)
                        unique[r*65536+g*256+b] = true
                    end
                end
            end
        end
        local n=0; for _ in pairs(unique) do n=n+1 end
        print(string.format("  layer %q raw_opaque_pixels=%d unique=%d", l.name, raw_total, n))
    end
end
-- Composited frame totals
local comp_total = 0
local comp_unique = {}
local per_frame_pixels = {}
for f = 1, #spr.frames do
    local img = Image(spr.spec)
    img:drawSprite(spr, f)
    local frame_count = 0
    for it in img:pixels() do
        local px = it()
        if app.pixelColor.rgbaA(px) > 0 then
            comp_total = comp_total + 1; frame_count = frame_count + 1
            local r = app.pixelColor.rgbaR(px); local g = app.pixelColor.rgbaG(px); local b = app.pixelColor.rgbaB(px)
            comp_unique[r*65536+g*256+b] = true
        end
    end
    per_frame_pixels[f] = frame_count
end
local cn=0; for _ in pairs(comp_unique) do cn=cn+1 end
print(string.format("COMPOSITED total_opaque=%d unique=%d", comp_total, cn))
for f, n in ipairs(per_frame_pixels) do print(string.format("  frame %d opaque=%d", f, n)) end

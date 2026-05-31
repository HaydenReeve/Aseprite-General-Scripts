-- Test harness: run compression script in-place, save, then run FoundryVTT export.
-- Driven by app.params:
--   target_colours, max_accent_slots, accent_score_threshold, accent_cluster_floor, strength, ramps
local p = app.params or {}

-- Force in-place output so the FoundryVTT export composites the remapped pixels.
p.output = "In place"
p.size_mode = p.size_mode or "Total colours"
p.raise_errors = "true"

-- 1. Run compression
dofile([[D:\Aseprite\Compress Palette with Hue Shifting\Compress Palette with Hue Shifting.lua]])

-- 2. Save the sprite (sprite path was set by -b file.aseprite)
local spr = app.activeSprite
if not spr then error("No sprite to save after compression.") end
spr:saveAs(spr.filename)

-- 3. Run FoundryVTT export with upscale off, no outline
p.upscale = "false"
p.whiteOutline = "false"
p.outline = "4-way"
p.quiet = "true"
dofile([[D:\Aseprite\Export For FoundryVTT\Export For FoundryVTT.lua]])

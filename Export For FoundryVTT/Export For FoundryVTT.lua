-- Export For FoundryVTT
-- Installation:
-- 1. Save this file as "Export For FoundryVTT.lua".
-- 2. Copy it into your Aseprite scripts folder:
--    Windows: %APPDATA%\Aseprite\scripts
--    macOS: ~/Library/Application Support/Aseprite/scripts
--    Linux: ~/.config/aseprite/scripts
-- 3. Create the "scripts" folder if it does not exist yet.
-- 4. In Aseprite, run File > Scripts > Rescan Scripts, or restart Aseprite.
-- 5. Run the script from File > Scripts > Export For FoundryVTT.
--
-- Notes:
-- - Your sprite must be saved before running the script.
-- - The script exports PNG frames beside the source file, exporting every slice when slices
--   exist (or the whole sprite when they do not), ignoring background layers, with optional
--   white outline, optional nearest-neighbour upscaling, a configurable output base name, and
--   optional slice-name filenames in "{Slice} Token {Parent Folder} 001" format.
-- - Empty slices are ignored to match Aseprite's export behaviour.
-- - Outline is applied within exact export bounds, so tightly cropped slices can clip it.

local function fail(message)
    if app.isUIAvailable then
        app.alert(message)
        return
    end

    error(message)
end

local spr = app.activeSprite
if not spr then
    fail("No active sprite found.")
    return
end

local sprPath = spr.filename
if sprPath == "" then
    fail("Please save your sprite first to establish an export directory.")
    return
end

local path = app.fs.filePath(sprPath)
local baseName = app.fs.fileTitle(sprPath)
local params = app.params or {}

local scaleFactor = 10

local function hasValue(value)
    return value ~= nil and value ~= ""
end

local function hasAnyOptionParams()
    return hasValue(params.name)
        or hasValue(params.upscale)
        or hasValue(params.whiteOutline)
        or hasValue(params.outline)
        or hasValue(params.sliceNames)
        or hasValue(params.quiet)
end

local function parseBoolean(value, defaultValue, optionName)
    if value == nil or value == "" then
        return defaultValue
    end

    local valueType = type(value)
    if valueType == "boolean" then
        return value
    end

    if valueType == "number" then
        if value == 1 then
            return true
        elseif value == 0 then
            return false
        end
    end

    if valueType == "string" then
        local lowered = string.lower(value)
        if lowered == "1" or lowered == "true" then
            return true
        elseif lowered == "0" or lowered == "false" then
            return false
        end
    end

    error("Invalid boolean option for " .. optionName .. ": " .. tostring(value) .. ". Use true, false, 1, or 0.")
end

local function resolveExportName(value)
    if value == nil then
        return baseName
    end

    value = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return baseName
    end

    return value
end

local function splitTrailingNumber(value)
    return tostring(value or ""):match("^(.-)(%d+)$")
end

local function getLastPathComponent(value)
    if value == nil then
        return nil
    end

    local normalized = tostring(value):gsub("[/\\]+$", "")
    if normalized == "" then
        return nil
    end

    local component = normalized:match("([^/\\]+)$")
    if component and not component:match("^[A-Za-z]:$") then
        return component
    end

    return nil
end

local function resolveOutlineOption(value)
    if not value or value == "" then
        return "4-way"
    end

    if type(value) ~= "string" then
        value = tostring(value)
    end

    local requested = string.lower(value)

    if requested == "4-way" or requested == "4way" or requested == "circle" then
        return "4-way"
    elseif requested == "8-way" or requested == "8way" or requested == "square" then
        return "8-way"
    end

    error("Invalid outline option: " .. requested .. ". Use 4-way or 8-way.")
end

local function outlineMatrixForOption(option)
    if option == "8-way" then
        return "square"
    end

    return "circle"
end

local function setDialogWidthFromSizeHint(dlg, widthMultiplier)
    local bounds = dlg.bounds
    local sizeHint = dlg.sizeHint
    local targetWidth = math.max(bounds.width, math.floor(sizeHint.width * widthMultiplier + 0.5))
    local targetHeight = math.max(bounds.height, sizeHint.height)

    bounds.size = Size(targetWidth, targetHeight)
    dlg.bounds = bounds
end

local function resolveExportOptions()
    local defaults = {
        name = baseName,
        upscale = true,
        whiteOutline = true,
        outline = "4-way",
        sliceNames = false,
        quiet = not app.isUIAvailable
    }

    if app.isUIAvailable and not hasAnyOptionParams() then
        local dlg = Dialog{ title="Export For FoundryVTT", resizeable=true }
        dlg:entry{ id="name", label="Name:", text=defaults.name, hexpand=true, focus=false }
        dlg:check{ id="sliceNames", label="Use slice names:", selected=defaults.sliceNames }
        dlg:check{ id="upscale", label="Upscale:", selected=defaults.upscale }
        dlg:check{ id="whiteOutline", label="White outline:", selected=defaults.whiteOutline }
        dlg:combobox{ id="outline", label="Outline:", option=defaults.outline, options={"4-way", "8-way"} }
        dlg:button{ id="ok", text="Export", focus=true }
        dlg:button{ id="cancel", text="Cancel" }
        setDialogWidthFromSizeHint(dlg, 2)
        dlg:show()

        if not dlg.data.ok then
            return nil
        end

        return {
            name = resolveExportName(dlg.data.name),
            sliceNames = parseBoolean(dlg.data.sliceNames, defaults.sliceNames, "sliceNames"),
            upscale = parseBoolean(dlg.data.upscale, defaults.upscale, "upscale"),
            whiteOutline = parseBoolean(dlg.data.whiteOutline, defaults.whiteOutline, "whiteOutline"),
            outline = resolveOutlineOption(dlg.data.outline),
            quiet = defaults.quiet
        }
    end

    return {
        name = resolveExportName(params.name),
        sliceNames = parseBoolean(params.sliceNames, defaults.sliceNames, "sliceNames"),
        upscale = parseBoolean(params.upscale, defaults.upscale, "upscale"),
        whiteOutline = parseBoolean(params.whiteOutline, defaults.whiteOutline, "whiteOutline"),
        outline = resolveOutlineOption(params.outline),
        quiet = parseBoolean(params.quiet, defaults.quiet, "quiet")
    }
end

local options = resolveExportOptions()
if not options then
    return
end

local quiet = options.quiet
local parentFolderName = getLastPathComponent(path)

-- Helper for filename based on native Aseprite behavior
local function getFrameFilename(base, frameIndex)
    local prefix, numStr = splitTrailingNumber(base)
    if prefix and numStr then
        local startNum = tonumber(numStr)
        local numLength = #numStr
        local currentNum = startNum + frameIndex - 1
        return prefix .. string.format("%0" .. numLength .. "d", currentNum)
    else
        return base .. string.format("%03d", frameIndex)
    end
end

local function getSliceExportBaseName(sliceLabel)
    if not parentFolderName then
        error("Could not derive parent folder name for slice-name filenames.")
    end

    return string.format("%s Token %s ", sliceLabel, parentFolderName)
end

local function getNextExportIndex(exportIndexesByBaseName, exportBaseName)
    local nextIndex = (exportIndexesByBaseName[exportBaseName] or 0) + 1
    exportIndexesByBaseName[exportBaseName] = nextIndex
    return nextIndex
end

local function hasVisibleExportLayer(layers)
    for _, layer in ipairs(layers) do
        if layer.isVisible then
            if layer.isGroup then
                if hasVisibleExportLayer(layer.layers) then
                    return true
                end
            elseif layer.isImage or layer.isTilemap then
                return true
            end
        end
    end

    return false
end

local function createWorkingSprite(sprite)
    local duplicate = Sprite(sprite)
    local backgroundLayer = duplicate.backgroundLayer

    if backgroundLayer then
        duplicate:deleteLayer(backgroundLayer)
    end

    if not hasVisibleExportLayer(duplicate.layers) then
        error("Sprite has no visible non-background layers to export.")
    end

    duplicate.selection = Selection()
    return duplicate
end

local function validateExportBounds(bounds, label, sprite)
    if bounds.width <= 0 or bounds.height <= 0 then
        error("Export region \"" .. label .. "\" is empty.")
    end

    if bounds.x < 0 or bounds.y < 0
        or bounds.x + bounds.width > sprite.width
        or bounds.y + bounds.height > sprite.height then
        error("Export region \"" .. label .. "\" extends outside sprite bounds.")
    end

    return Rectangle(bounds.x, bounds.y, bounds.width, bounds.height)
end

local function getExportRegions(sprite)
    -- Lua exposes only static slice.bounds values, so animated slice keys cannot be exported here.
    if #sprite.slices == 0 then
        return {
            {
                label = "sprite",
                bounds = Rectangle(0, 0, sprite.width, sprite.height)
            }
        }
    end

    local regions = {}
    for index, slice in ipairs(sprite.slices) do
        local label = slice.name
        if label == "" then
            label = "slice #" .. index
        end

        regions[#regions + 1] = {
            label = label,
            bounds = validateExportBounds(slice.bounds, label, sprite)
        }
    end

    return regions
end

local createCompositeFrameImage

local function filterEmptySliceRegions(sprite, regions)
    if #sprite.slices == 0 then
        return regions, 0
    end

    local regionHasContent = {}
    for frameNumber = 1, #sprite.frames do
        local frameImage = createCompositeFrameImage(sprite, frameNumber)

        for regionIndex, region in ipairs(regions) do
            if not regionHasContent[regionIndex] then
                local regionImage = Image(frameImage, region.bounds)
                if regionImage and not regionImage:isEmpty() then
                    regionHasContent[regionIndex] = true
                end
            end
        end
    end

    local filteredRegions = {}
    local ignoredCount = 0
    for regionIndex, region in ipairs(regions) do
        if regionHasContent[regionIndex] then
            filteredRegions[#filteredRegions + 1] = region
        else
            ignoredCount = ignoredCount + 1
        end
    end

    return filteredRegions, ignoredCount
end

local function getPaletteForFrame(sprite, frameNumber)
    return sprite.palettes[math.min(frameNumber, #sprite.palettes)]
end

createCompositeFrameImage = function(sprite, frameNumber)
    local image = Image(sprite.spec)
    image:drawSprite(sprite, frameNumber)
    return image
end

local function createExportSprite(sourceSprite, frameNumber, image)
    local exportSprite = Sprite(image.width, image.height, sourceSprite.colorMode)

    if sourceSprite.colorMode == ColorMode.INDEXED then
        exportSprite:setPalette(Palette(getPaletteForFrame(sourceSprite, frameNumber)))
        exportSprite.transparentColor = sourceSprite.transparentColor
    end

    exportSprite:newCel(exportSprite.layers[1], 1, image, Point(0, 0))
    exportSprite.selection = Selection()
    return exportSprite
end

local function applyOutline(exportSprite)
    if not options.whiteOutline then
        return
    end

    app.activeSprite = exportSprite
    app.activeLayer = exportSprite.layers[1]
    app.activeFrame = exportSprite.frames[1]
    app.command.Outline{
        ui=false,
        color=Color{r=255, g=255, b=255, a=255},
        place="outside",
        matrix=outlineMatrixForOption(options.outline)
    }
end

local function applyScale(exportSprite)
    if not options.upscale then
        return
    end

    app.activeSprite = exportSprite
    app.command.SpriteSize{
        ui=false,
        width=exportSprite.width * scaleFactor,
        height=exportSprite.height * scaleFactor,
        method="nearest"
    }
end

local dup = nil
local exportCount = 0
local regionCount = 0
local hasSlices = #spr.slices > 0
local ignoredEmptySliceCount = 0

local runOk, runErr = pcall(function()
    dup = createWorkingSprite(spr)

    local regions = getExportRegions(dup)
    local totalFrames = #dup.frames
    regions, ignoredEmptySliceCount = filterEmptySliceRegions(dup, regions)
    regionCount = #regions

    local frameImages = {}
    for frameNumber = 1, totalFrames do
        frameImages[frameNumber] = createCompositeFrameImage(dup, frameNumber)
    end

    local exportIndexesByBaseName = {}
    for regionIndex, region in ipairs(regions) do
        for frameNumber = 1, totalFrames do
            local tmp = nil
            local tmpOk, tmpErr = pcall(function()
                local frameImage = frameImages[frameNumber]
                local exportIndex = (regionIndex - 1) * totalFrames + frameNumber
                local exportBaseName = options.name
                if options.sliceNames and hasSlices then
                    exportBaseName = getSliceExportBaseName(region.label)
                    exportIndex = getNextExportIndex(exportIndexesByBaseName, exportBaseName)
                end

                local regionImage = Image(frameImage, region.bounds)
                if not regionImage then
                    error("Failed to crop export region \"" .. region.label .. "\" for frame " .. frameNumber .. ".")
                end

                tmp = createExportSprite(dup, frameNumber, regionImage)
                applyOutline(tmp)
                applyScale(tmp)

                local outName = app.fs.joinPath(path, getFrameFilename(exportBaseName, exportIndex) .. ".png")
                tmp:saveCopyAs(outName)
                exportCount = exportCount + 1
            end)

            if tmp then
                pcall(function()
                    tmp:close()
                end)
            end

            if not tmpOk then
                error(tmpErr)
            end
        end
    end
end)

-- Clean up duplicate
pcall(function()
    if dup then
        dup:close()
    end
end)
app.activeSprite = spr

if not runOk then
    error(runErr)
end

local function buildCompletionMessage()
    local namingText = string.format("with basename \"%s\"", options.name)
    local outlineText = options.whiteOutline and "with white outline" or "without outline"
    local scaleText = options.upscale and "at 1000% with nearest-neighbour scaling" or "at native size"
    local scopeText = hasSlices and string.format("across %d non-empty slices", regionCount) or "from the full sprite"
    local emptySliceText = ignoredEmptySliceCount > 0
        and string.format(" Ignored %d empty slices.", ignoredEmptySliceCount)
        or ""
    if options.sliceNames and hasSlices then
        namingText = string.format(
            "using slice-name filenames in format \"{Slice} Token %s 001\"",
            parentFolderName
        )
    end
    return string.format(
        "Export complete! Saved %d individual .png files %s, %s, %s, %s. Background layers were ignored.%s",
        exportCount,
        namingText,
        scopeText,
        outlineText,
        scaleText,
        emptySliceText
    )
end

local completionMessage = buildCompletionMessage()
if quiet then
    print(completionMessage)
else
    app.alert(completionMessage)
end

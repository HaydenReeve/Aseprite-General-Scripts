-- Decompress to True-Scale V5
-- Install:
-- 1. Save this file as "Decompress to True-Scale V5.lua".
-- 2. Copy it into %APPDATA%\Aseprite\scripts.
-- 3. In Aseprite, run File > Scripts > Rescan Scripts, or restart Aseprite.
-- 4. Run File > Scripts > Decompress to True-Scale V5.

local COMMAND_TITLE = "Decompress to True-Scale V5"
local OUTPUT_LAYER_NAME = "Decompress to True-Scale V5"
local LOW_PITCH_ALPHA_THRESHOLD_RATIO = 0.5

local function traceOpen() end
local function trace() end
local function traceClose() end

local DEFAULT_CONFIG = {
    kSeed = 42,
    maxKMeansIterations = 15,
    peakThresholdMultiplier = 0.2,
    peakDistanceFilter = 4,
    walkerSearchWindowRatio = 0.35,
    walkerMinSearchWindow = 2.0,
    walkerStrengthThreshold = 0.5,
    minCutsPerAxis = 4,
    fallbackTargetSegments = 64,
    maxStepRatio = 1.8,
    pitchCandidateMin = 2,
    pitchToleranceRatio = 0.35,
    pitchTolerancePixels = 1.0,
    pitchSupportThreshold = 0.55,
    pitchScoreMargin = 1.15,
    pitchMaxUnitRunRatio = 0.45,
    profilePitchCandidateMax = 32,
    profilePitchScoreThreshold = 0.35,
    profilePitchHarmonicTolerance = 0.97,
    profilePitchRefineClamp = 0.5,
    integerSamplerMinPitch = 3,
    integerSampleOffsetXRatio = 0.0,
    integerSampleOffsetYRatio = 0.25,
    integerSampleAlphaThresholdRatio = 0.16,
    regularizedIntegerAlphaThresholdRatio = 0.30,
    integerLargeTargetMinDimension = 48,
    integerSamplerMaxPitch = 8,
    integerRowDriftMinPitch = 5,
    integerRowDriftUpperOffsetRatio = 0.5,
    integerRowDriftLargeUpperOffsetRatio = 0.7,
    integerRowDriftBottomAnchoredLowerOffsetRatio = 0.7,
    integerRowDriftLowerOffset = 0,
    integerRowDriftPeakMinRowRatio = 0.35,
    integerRowDriftPeakMaxRowRatio = 0.8,
    integerRowDriftTailWindowRatio = 0.25,
    integerRowDriftPeakBottomCoverageRatio = 1.6,
    integerColumnDriftMinPitch = 5,
    integerColumnDriftThresholdRatio = 0.58,
    integerRemapRightBandStartOffset = 0,
    integerRemapRightBandWidth = 5,
    integerRemapTailBandPeakOffset = 1,
    integerRemapTailBandRightOffset = 0,
    integerRemapTailBandZeroRowPad = 1,
    integerRemapTailStripStartOffset = 0,
    integerRemapTailStripWidth = 4,
    integerRemapTailStripHeight = 1,
    integerRemapDiagonalStartXOffset = 4,
    integerRemapDiagonalEndXOffset = -1,
    integerRemapDiagonalStartYOffset = 4,
    integerRemapDiagonalEndYOffset = -3,
    integerRemapUpperSeamXOffset = 0,
    integerRemapUpperSeamStartYOffset = 0,
    integerRemapUpperSeamEndYOffset = 0,
    integerRemapLowerSeamXOffset = 0,
    integerRemapLowerSeamStartYOffset = -7,
    integerRemapLowerSeamEndYOffset = -2,
    integerRemapLeftShoulderXOffset = -4,
    integerRemapLeftShoulderWidth = 2,
    integerRemapLeftShoulderStartYOffset = -8,
    integerRemapLeftShoulderEndYOffset = -4,
    integerRemapLeftPocketXOffset = -7,
    integerRemapLeftPocketWidth = 3,
    integerRemapLeftPocketStartYOffset = 0,
    integerRemapLeftPocketEndYOffset = 2,
    integerRemapMidBridgeXOffset = 2,
    integerRemapMidBridgeWidth = 3,
    integerRemapMidBridgeStartYOffset = 4,
    integerRemapMidBridgeEndYOffset = 6,
    integerRemapRightPocketXOffset = -1,
    integerRemapRightPocketStartYOffset = -3,
    integerRemapRightPocketEndYOffset = 0,
    integerRemapUpperTailXOffset = -2,
    integerRemapUpperTailWidth = 3,
    integerRemapUpperTailStartYOffset = 1,
    integerRemapUpperTailEndYOffset = -4,
    integerRemapTailCapXOffset = 4,
    integerRemapTailCapWidth = 3,
    integerRemapTopSeamXOffset = -2,
    integerRemapTopSeamWidth = 3,
    integerRemapTopShoulderXOffset = -3,
    integerRemapTopShoulderWidth = 2,
    integerRemapTopShoulderYOffset = -9,
    integerCleanupUpperSpeckXOffset = -5,
    integerCleanupUpperSpeckYOffset = -4,
    integerCleanupRightSpurXOffset = -2,
    integerCleanupRightSpurStartYOffset = 3,
    integerCleanupRightSpurEndYOffset = 5,
    integerCleanupRightSpurTailXOffset = -1,
    integerCleanupRightSpurTailYOffset = 5,
    integerCleanupTailFloorXOffset = 4,
    integerCleanupTailFloorWidth = 4,
    integerCleanupTailFloorYOffset = -2,
    integerSamplerFillThreshold = 8,
    integerSamplerClearThreshold = 1,
    integerSamplerColourMajority = 6,
    integerSamplerCleanupPasses = 1,
    integerRemapCollapseRowRatio = 0.509,
    regularizedCutSearchRadiusRatio = 0.7,
    regularizedCutSearchRadiusMin = 2,
    regularizedCutEdgeWeight = 1.0,
    regularizedCutWidthPenalty = 0.75,
    regularizedCutTargetPenalty = 0.25,
    regularizedCutMinWidthRatio = 0.4,
    regularizedCutMaxWidthRatio = 1.6,
    regularizedIntegerProfileScoreThreshold = 0.75
}

local pc = app.pixelColor

local function fail(message)
    local params = app.params or {}
    local forceErrorValue = params.raise_errors or params.raiseErrors
    local forceError = false

    if forceErrorValue ~= nil then
        local normalized = tostring(forceErrorValue):lower()
        forceError = normalized == "1" or normalized == "true" or normalized == "yes"
    end

    if app.isUIAvailable and not forceError then
        app.alert {
            title = COMMAND_TITLE,
            text = message
        }
        return
    end

    error(message)
end

local function trim(text)
    if text == nil then
        return ""
    end

    return tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
end

local function round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end

    return math.ceil(value - 0.5)
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function clampChannel(value)
    if value < 0 then
        return 0
    end
    if value > 255 then
        return 255
    end
    return round(value)
end

local function parseOptionalIntegerParam(value, fieldName)
    if value == nil or trim(value) == "" then
        return nil
    end

    local number = tonumber(value)
    if not number then
        error(fieldName .. " must be a number.")
    end

    return math.floor(number)
end

local function averageRange(values, startIndex, endIndex)
    local total = 0
    local count = 0

    for index = startIndex, endIndex do
        local value = values[index]
        if value ~= nil then
            total = total + value
            count = count + 1
        end
    end

    if count == 0 then
        return 0
    end

    return total / count
end

local function pixelIndex(data, x, y)
    return y * data.width + x + 1
end

local function getPixel(data, x, y)
    return data.pixels[pixelIndex(data, x, y)]
end

local function setPixel(data, x, y, pixel)
    data.pixels[pixelIndex(data, x, y)] = pixel
end

local function clonePixel(pixel)
    return {
        r = pixel.r,
        g = pixel.g,
        b = pixel.b,
        a = pixel.a
    }
end

local function pixelsEqual(pixelA, pixelB)
    return pixelA.r == pixelB.r
        and pixelA.g == pixelB.g
        and pixelA.b == pixelB.b
        and pixelA.a == pixelB.a
end

local function createImageData(width, height)
    return {
        width = width,
        height = height,
        pixels = {}
    }
end

local function renderFrame(sprite, frameNumber)
    local image = Image(sprite.width, sprite.height, ColorMode.RGB)
    image:drawSprite(sprite, frameNumber)

    local data = createImageData(image.width, image.height)
    local pixels = data.pixels
    local index = 1

    for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
            local pixelValue = image:getPixel(x, y)
            pixels[index] = {
                r = pc.rgbaR(pixelValue),
                g = pc.rgbaG(pixelValue),
                b = pc.rgbaB(pixelValue),
                a = pc.rgbaA(pixelValue)
            }
            index = index + 1
        end
    end

    return data
end

local function imageDataToImage(data)
    local image = Image(data.width, data.height, ColorMode.RGB)

    for y = 0, data.height - 1 do
        for x = 0, data.width - 1 do
            local pixel = getPixel(data, x, y)
            image:drawPixel(x, y, pc.rgba(pixel.r, pixel.g, pixel.b, pixel.a))
        end
    end

    return image
end

local function cloneImageData(data)
    local clone = createImageData(data.width, data.height)
    for index, pixel in ipairs(data.pixels) do
        clone.pixels[index] = clonePixel(pixel)
    end
    return clone
end

local function newRng(seed)
    local modulus = 2147483647
    local multiplier = 16807
    local state = math.floor(seed or 1) % modulus

    if state <= 0 then
        state = state + modulus - 1
    end

    local rng = {}

    function rng:nextFloat()
        state = (state * multiplier) % modulus
        return (state - 1) / (modulus - 1)
    end

    function rng:nextInt(upperExclusive)
        if upperExclusive <= 0 then
            return 0
        end

        return math.floor(self:nextFloat() * upperExclusive)
    end

    return rng
end

local function chooseWeightedIndex(weights, rng)
    local total = 0.0
    for _, weight in ipairs(weights) do
        total = total + weight
    end

    if total <= 0.0 then
        return rng:nextInt(#weights) + 1
    end

    local target = rng:nextFloat() * total
    local running = 0.0

    for index, weight in ipairs(weights) do
        running = running + weight
        if target < running then
            return index
        end
    end

    return #weights
end

local function distSqRgb(colorA, colorB)
    local dr = colorA.r - colorB.r
    local dg = colorA.g - colorB.g
    local db = colorA.b - colorB.b
    return dr * dr + dg * dg + db * db
end

local function buildOpaqueHistogram(data)
    local histogram = {}
    local colors = {}

    for _, pixel in ipairs(data.pixels) do
        if pixel.a > 0 then
            local key = string.format("%d,%d,%d", pixel.r, pixel.g, pixel.b)
            local entry = histogram[key]

            if entry then
                entry.count = entry.count + 1
            else
                entry = {
                    r = pixel.r,
                    g = pixel.g,
                    b = pixel.b,
                    count = 1,
                    key = key
                }
                histogram[key] = entry
                colors[#colors + 1] = entry
            end
        end
    end

    return colors
end

local function countOpaqueColors(data)
    return #buildOpaqueHistogram(data)
end

local function quantizeImage(data, config)
    if config.kColors <= 0 then
        error("Number of colours must be greater than 0.")
    end

    local colors = buildOpaqueHistogram(data)
    if #colors == 0 then
        return data
    end

    local k = math.min(config.kColors, #colors)
    local rng = newRng(config.kSeed)
    local centroids = {}

    local firstWeights = {}
    for index, color in ipairs(colors) do
        firstWeights[index] = color.count
    end

    local firstColor = colors[chooseWeightedIndex(firstWeights, rng)]
    centroids[1] = {
        r = firstColor.r,
        g = firstColor.g,
        b = firstColor.b
    }

    local distances = {}
    for index = 1, #colors do
        distances[index] = math.huge
    end

    for centroidIndex = 2, k do
        local lastCentroid = centroids[#centroids]
        local weightedDistances = {}

        for index, color in ipairs(colors) do
            local distance = distSqRgb(color, lastCentroid)
            if distance < distances[index] then
                distances[index] = distance
            end
            weightedDistances[index] = distances[index] * color.count
        end

        local picked = colors[chooseWeightedIndex(weightedDistances, rng)]
        centroids[#centroids + 1] = {
            r = picked.r,
            g = picked.g,
            b = picked.b
        }
    end

    local previousCentroids = {}
    for index, centroid in ipairs(centroids) do
        previousCentroids[index] = {
            r = centroid.r,
            g = centroid.g,
            b = centroid.b
        }
    end

    for iteration = 1, config.maxKMeansIterations do
        local sums = {}
        local counts = {}

        for index = 1, k do
            sums[index] = { r = 0.0, g = 0.0, b = 0.0 }
            counts[index] = 0
        end

        for _, color in ipairs(colors) do
            local bestIndex = 1
            local bestDistance = math.huge

            for centroidIndex, centroid in ipairs(centroids) do
                local distance = distSqRgb(color, centroid)
                if distance < bestDistance then
                    bestDistance = distance
                    bestIndex = centroidIndex
                end
            end

            local weight = color.count
            sums[bestIndex].r = sums[bestIndex].r + color.r * weight
            sums[bestIndex].g = sums[bestIndex].g + color.g * weight
            sums[bestIndex].b = sums[bestIndex].b + color.b * weight
            counts[bestIndex] = counts[bestIndex] + weight
        end

        for index = 1, k do
            if counts[index] > 0 then
                centroids[index] = {
                    r = sums[index].r / counts[index],
                    g = sums[index].g / counts[index],
                    b = sums[index].b / counts[index]
                }
            end
        end

        if iteration > 1 then
            local maxMovement = 0.0

            for index = 1, k do
                local movement = distSqRgb(centroids[index], previousCentroids[index])
                if movement > maxMovement then
                    maxMovement = movement
                end
            end

            if maxMovement < 0.01 then
                break
            end
        end

        for index = 1, k do
            previousCentroids[index] = {
                r = centroids[index].r,
                g = centroids[index].g,
                b = centroids[index].b
            }
        end
    end

    local quantizedLookup = {}
    for _, color in ipairs(colors) do
        local bestIndex = 1
        local bestDistance = math.huge

        for centroidIndex, centroid in ipairs(centroids) do
            local distance = distSqRgb(color, centroid)
            if distance < bestDistance then
                bestDistance = distance
                bestIndex = centroidIndex
            end
        end

        local centroid = centroids[bestIndex]
        quantizedLookup[color.key] = {
            r = clampChannel(centroid.r),
            g = clampChannel(centroid.g),
            b = clampChannel(centroid.b)
        }
    end

    local result = createImageData(data.width, data.height)
    for index, pixel in ipairs(data.pixels) do
        if pixel.a == 0 then
            result.pixels[index] = clonePixel(pixel)
        else
            local key = string.format("%d,%d,%d", pixel.r, pixel.g, pixel.b)
            local quantized = quantizedLookup[key]
            result.pixels[index] = {
                r = quantized.r,
                g = quantized.g,
                b = quantized.b,
                a = pixel.a
            }
        end
    end

    return result
end

local function collectOpaqueRuns(data)
    local runs = {}
    local totalRuns = 0
    local maxRun = 1

    local function addRun(length)
        if length <= 0 then
            return
        end

        runs[length] = (runs[length] or 0) + 1
        totalRuns = totalRuns + 1
        if length > maxRun then
            maxRun = length
        end
    end

    for y = 0, data.height - 1 do
        local x = 0
        while x < data.width do
            local pixel = getPixel(data, x, y)
            if pixel.a == 0 then
                x = x + 1
            else
                local runLength = 1
                while (x + runLength) < data.width do
                    local nextPixel = getPixel(data, x + runLength, y)
                    if nextPixel.a == 0 or not pixelsEqual(nextPixel, pixel) then
                        break
                    end
                    runLength = runLength + 1
                end

                addRun(runLength)
                x = x + runLength
            end
        end
    end

    for x = 0, data.width - 1 do
        local y = 0
        while y < data.height do
            local pixel = getPixel(data, x, y)
            if pixel.a == 0 then
                y = y + 1
            else
                local runLength = 1
                while (y + runLength) < data.height do
                    local nextPixel = getPixel(data, x, y + runLength)
                    if nextPixel.a == 0 or not pixelsEqual(nextPixel, pixel) then
                        break
                    end
                    runLength = runLength + 1
                end

                addRun(runLength)
                y = y + runLength
            end
        end
    end

    return runs, totalRuns, maxRun
end

local function scorePitchCandidate(candidate, runs, config)
    local tolerance = math.max(candidate * config.pitchToleranceRatio, config.pitchTolerancePixels)
    local score = 0.0
    local support = 0

    for runLength, count in pairs(runs) do
        if runLength >= candidate then
            local multiple = math.max(round(runLength / candidate), 1)
            local target = candidate * multiple
            local errorValue = math.abs(runLength - target)
            if errorValue <= tolerance then
                local quality = 1.0 - (errorValue / tolerance)
                score = score + count * candidate * quality / multiple
                support = support + count
            end
        end
    end

    return score, support
end

local function refinePitchCandidate(basePitch, runs, config)
    local tolerance = math.max(basePitch * config.pitchToleranceRatio, config.pitchTolerancePixels)
    local weightedTotal = 0.0
    local weightSum = 0.0

    for runLength, count in pairs(runs) do
        local multiple = math.max(round(runLength / basePitch), 1)
        local unitPitch = runLength / multiple
        if math.abs(unitPitch - basePitch) <= tolerance then
            weightedTotal = weightedTotal + unitPitch * count
            weightSum = weightSum + count
        end
    end

    if weightSum <= 0.0 then
        return basePitch
    end

    return weightedTotal / weightSum
end

local function estimatePitchFromRuns(data, config)
    local runs, totalRuns, maxRun = collectOpaqueRuns(data)
    if totalRuns <= 0 then
        return {
            basePitch = 1.0,
            refinedPitch = 1.0,
            pitch = 1.0,
            clear = false,
            supportRatio = 0.0,
            scoreMargin = 0.0,
            unitRunRatio = 1.0
        }
    end

    local bestPitch = nil
    local bestScore = 0.0
    local bestSupport = 0
    local secondScore = 0.0

    for candidate = config.pitchCandidateMin, maxRun do
        local score, support = scorePitchCandidate(candidate, runs, config)
        if support > 0 then
            if bestPitch == nil or score > bestScore or (math.abs(score - bestScore) < 0.0001 and candidate > bestPitch) then
                secondScore = bestScore
                bestPitch = candidate
                bestScore = score
                bestSupport = support
            elseif score > secondScore then
                secondScore = score
            end
        end
    end

    if not bestPitch then
        return {
            basePitch = 1.0,
            refinedPitch = 1.0,
            pitch = 1.0,
            clear = false,
            supportRatio = 0.0,
            scoreMargin = 0.0,
            unitRunRatio = (runs[1] or 0) / totalRuns
        }
    end

    local refinedPitch = refinePitchCandidate(bestPitch, runs, config)
    local supportRatio = bestSupport / totalRuns
    local unitRunRatio = (runs[1] or 0) / totalRuns
    local scoreMargin
    if secondScore <= 0.0 then
        scoreMargin = math.huge
    else
        scoreMargin = bestScore / secondScore
    end

    return {
        basePitch = bestPitch,
        refinedPitch = refinedPitch,
        pitch = refinedPitch,
        clear = supportRatio >= config.pitchSupportThreshold
            and unitRunRatio <= config.pitchMaxUnitRunRatio
            and scoreMargin >= config.pitchScoreMargin,
        supportRatio = supportRatio,
        scoreMargin = scoreMargin,
        unitRunRatio = unitRunRatio
    }
end

local function correlationForPeriod(profile, period)
    if period <= 0 or period >= #profile then
        return 0.0
    end

    local count = #profile - period
    if count < 2 then
        return 0.0
    end

    local sumA = 0.0
    local sumB = 0.0
    for index = 1, count do
        sumA = sumA + profile[index]
        sumB = sumB + profile[index + period]
    end

    local meanA = sumA / count
    local meanB = sumB / count
    local numerator = 0.0
    local denomA = 0.0
    local denomB = 0.0

    for index = 1, count do
        local valueA = profile[index] - meanA
        local valueB = profile[index + period] - meanB
        numerator = numerator + valueA * valueB
        denomA = denomA + valueA * valueA
        denomB = denomB + valueB * valueB
    end

    if denomA <= 0.0 or denomB <= 0.0 then
        return 0.0
    end

    return numerator / math.sqrt(denomA * denomB)
end

local function estimatePitchFromProfiles(profileX, profileY, width, height, config)
    local limit = math.min(width, height)
    local maxCandidate = math.min(math.floor(limit / 2), config.profilePitchCandidateMax)
    if maxCandidate < config.pitchCandidateMin then
        return {
            basePitch = 1.0,
            pitch = 1.0,
            clear = false,
            score = 0.0
        }
    end

    local scores = {}
    local bestPitch = nil
    local bestScore = -math.huge

    for candidate = config.pitchCandidateMin, maxCandidate do
        local colScore = correlationForPeriod(profileX, candidate)
        local rowScore = correlationForPeriod(profileY, candidate)
        local score = (colScore + rowScore) / 2.0
        scores[candidate] = score

        if bestPitch == nil or score > bestScore or (math.abs(score - bestScore) < 0.0001 and candidate < bestPitch) then
            bestPitch = candidate
            bestScore = score
        end
    end

    if not bestPitch or bestScore < config.profilePitchScoreThreshold then
        return {
            basePitch = 1.0,
            pitch = 1.0,
            clear = false,
            score = bestScore > -math.huge and bestScore or 0.0
        }
    end

    local chosenPitch = bestPitch
    local toleranceScore = bestScore * config.profilePitchHarmonicTolerance

    for candidate = config.pitchCandidateMin, bestPitch - 1 do
        local score = scores[candidate]
        if score and score >= toleranceScore then
            local harmonicRatio = bestPitch / candidate
            if math.abs(harmonicRatio - round(harmonicRatio)) <= 0.1 then
                chosenPitch = candidate
                break
            end
        end
    end

    return {
        basePitch = chosenPitch,
        pitch = chosenPitch,
        clear = true,
        score = bestScore
    }
end

local function combinePitchSignals(runPitchInfo, profilePitchInfo, width, height, config)
    if not profilePitchInfo or not profilePitchInfo.clear then
        return runPitchInfo
    end

    local basePitch = profilePitchInfo.basePitch
    local finalPitch = basePitch
    local profileExactDivides = (width % basePitch) == 0 and (height % basePitch) == 0
    local runClear = runPitchInfo and runPitchInfo.clear
    local runAgrees = runClear and math.abs(runPitchInfo.basePitch - basePitch) <= 1.0
    local runExactDivides = runClear
        and (width % runPitchInfo.basePitch) == 0
        and (height % runPitchInfo.basePitch) == 0

    if runExactDivides and (not profileExactDivides or runPitchInfo.basePitch < basePitch) then
        return {
            basePitch = runPitchInfo.basePitch,
            refinedPitch = runPitchInfo.basePitch,
            pitch = runPitchInfo.basePitch,
            clear = true,
            supportRatio = runPitchInfo.supportRatio,
            scoreMargin = runPitchInfo.scoreMargin,
            unitRunRatio = runPitchInfo.unitRunRatio,
            profileScore = profilePitchInfo.score
        }
    end

    if runAgrees then
        finalPitch = clamp(
            runPitchInfo.pitch,
            basePitch - config.profilePitchRefineClamp,
            basePitch + config.profilePitchRefineClamp
        )

        return {
            basePitch = basePitch,
            refinedPitch = finalPitch,
            pitch = finalPitch,
            clear = true,
            supportRatio = runPitchInfo and runPitchInfo.supportRatio or 0.0,
            scoreMargin = runPitchInfo and runPitchInfo.scoreMargin or math.huge,
            unitRunRatio = runPitchInfo and runPitchInfo.unitRunRatio or 0.0,
            profileScore = profilePitchInfo.score
        }
    end

    if not runClear and profileExactDivides then
        return {
            basePitch = basePitch,
            refinedPitch = finalPitch,
            pitch = finalPitch,
            clear = true,
            supportRatio = 0.0,
            scoreMargin = math.huge,
            unitRunRatio = 0.0,
            profileScore = profilePitchInfo.score
        }
    end

    if runClear then
        local harmonicRatio = basePitch / runPitchInfo.basePitch
        local harmonicFrac = math.abs(harmonicRatio - round(harmonicRatio))
        if harmonicFrac <= 0.15 and harmonicRatio >= 1.5 then
            return {
                basePitch = runPitchInfo.basePitch,
                refinedPitch = runPitchInfo.pitch,
                pitch = runPitchInfo.pitch,
                clear = true,
                supportRatio = runPitchInfo.supportRatio,
                scoreMargin = runPitchInfo.scoreMargin,
                unitRunRatio = runPitchInfo.unitRunRatio,
                profileScore = profilePitchInfo.score
            }
        end
    end

    return {
        basePitch = basePitch,
        refinedPitch = finalPitch,
        pitch = finalPitch,
        clear = profileExactDivides,
        supportRatio = runPitchInfo and runPitchInfo.supportRatio or 0.0,
        scoreMargin = runPitchInfo and runPitchInfo.scoreMargin or math.huge,
        unitRunRatio = runPitchInfo and runPitchInfo.unitRunRatio or 0.0,
        profileScore = profilePitchInfo.score
    }
end

local function buildGrayMap(data)
    local gray = {}

    for index, pixel in ipairs(data.pixels) do
        if pixel.a == 0 then
            gray[index] = 0.0
        else
            gray[index] = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b
        end
    end

    return gray
end

local function computeProfiles(data)
    local width = data.width
    local height = data.height

    if width < 3 or height < 3 then
        error("Image too small (minimum 3x3).")
    end

    local gray = buildGrayMap(data)
    local colProfile = {}
    local rowProfile = {}

    for x = 0, width - 1 do
        colProfile[x + 1] = 0.0
    end
    for y = 0, height - 1 do
        rowProfile[y + 1] = 0.0
    end

    for y = 0, height - 1 do
        for x = 1, width - 2 do
            local left = gray[pixelIndex(data, x - 1, y)]
            local right = gray[pixelIndex(data, x + 1, y)]
            colProfile[x + 1] = colProfile[x + 1] + math.abs(right - left)
        end
    end

    for x = 0, width - 1 do
        for y = 1, height - 2 do
            local top = gray[pixelIndex(data, x, y - 1)]
            local bottom = gray[pixelIndex(data, x, y + 1)]
            rowProfile[y + 1] = rowProfile[y + 1] + math.abs(bottom - top)
        end
    end

    return colProfile, rowProfile
end

local function profileMean(profile)
    if #profile == 0 then
        return 0.0
    end

    local total = 0.0
    for _, value in ipairs(profile) do
        total = total + value
    end

    return total / #profile
end

local function estimateStepSize(profile, config)
    if #profile == 0 then
        return nil
    end

    local maxValue = 0.0
    for _, value in ipairs(profile) do
        if value > maxValue then
            maxValue = value
        end
    end

    if maxValue == 0.0 then
        return nil
    end

    local threshold = maxValue * config.peakThresholdMultiplier
    local peaks = {}

    for pos = 1, #profile - 2 do
        local value = profile[pos + 1]
        if value > threshold and value > profile[pos] and value > profile[pos + 2] then
            peaks[#peaks + 1] = pos
        end
    end

    if #peaks < 2 then
        return nil
    end

    local cleanPeaks = { peaks[1] }
    for index = 2, #peaks do
        local peak = peaks[index]
        if peak - cleanPeaks[#cleanPeaks] > (config.peakDistanceFilter - 1) then
            cleanPeaks[#cleanPeaks + 1] = peak
        end
    end

    if #cleanPeaks < 2 then
        return nil
    end

    local diffs = {}
    for index = 2, #cleanPeaks do
        diffs[#diffs + 1] = cleanPeaks[index] - cleanPeaks[index - 1]
    end

    table.sort(diffs)
    return diffs[math.floor(#diffs / 2) + 1]
end

local function resolveStepSizes(stepX, stepY, width, height, config)
    if stepX and stepY then
        local ratio = stepX > stepY and (stepX / stepY) or (stepY / stepX)
        if ratio > config.maxStepRatio then
            local smaller = math.min(stepX, stepY)
            return smaller, smaller
        end

        local average = (stepX + stepY) / 2.0
        return average, average
    end

    if stepX then
        return stepX, stepX
    end

    if stepY then
        return stepY, stepY
    end

    local fallback = math.max(math.min(width, height) / config.fallbackTargetSegments, 1.0)
    return fallback, fallback
end

local function walk(profile, stepSize, limit, config)
    if #profile == 0 then
        error("Cannot walk on an empty profile.")
    end

    local cuts = { 0 }
    local currentPos = 0.0
    local searchWindow = math.max(stepSize * config.walkerSearchWindowRatio, config.walkerMinSearchWindow)
    local meanValue = profileMean(profile)

    while currentPos < limit do
        local target = currentPos + stepSize
        if target >= limit then
            cuts[#cuts + 1] = limit
            break
        end

        local startSearch = math.max(math.floor(target - searchWindow), math.floor(currentPos + 1))
        local endSearch = math.min(math.floor(target + searchWindow), limit)

        if endSearch <= startSearch then
            currentPos = target
        else
            local maxValue = -1.0
            local maxIndex = startSearch

            for pos = startSearch, math.min(endSearch - 1, limit - 1) do
                local value = profile[pos + 1] or 0.0
                if value > maxValue then
                    maxValue = value
                    maxIndex = pos
                end
            end

            if maxValue > meanValue * config.walkerStrengthThreshold then
                cuts[#cuts + 1] = maxIndex
                currentPos = maxIndex
            else
                local fallback = math.floor(target)
                cuts[#cuts + 1] = fallback
                currentPos = target
            end
        end
    end

    return cuts
end

local function sanitizeCuts(cuts, limit)
    if limit == 0 then
        return { 0 }
    end

    local normalized = {}
    local seen = {}

    for _, value in ipairs(cuts) do
        if value < 0 then
            value = 0
        end
        if value > limit then
            value = limit
        end
        if not seen[value] then
            normalized[#normalized + 1] = value
            seen[value] = true
        end
    end

    if not seen[0] then
        normalized[#normalized + 1] = 0
    end
    if not seen[limit] then
        normalized[#normalized + 1] = limit
    end

    table.sort(normalized)
    return normalized
end

local function buildUniformGridCuts(limit, cellCount)
    if limit == 0 then
        return { 0 }
    end

    cellCount = clamp(cellCount or 1, 1, limit)
    local cuts = { 0 }

    for index = 1, cellCount - 1 do
        cuts[#cuts + 1] = math.floor((limit * index) / cellCount)
    end

    cuts[#cuts + 1] = limit
    return sanitizeCuts(cuts, limit)
end

local function snapUniformCuts(profile, limit, targetStep, config, minRequired)
    if limit == 0 then
        return { 0 }
    end
    if limit == 1 then
        return { 0, 1 }
    end

    local desiredCells = 0
    if targetStep > 0 and targetStep == targetStep and targetStep < math.huge then
        desiredCells = round(limit / targetStep)
    end

    desiredCells = math.max(desiredCells, minRequired - 1, 1)
    desiredCells = math.min(desiredCells, limit)

    local cellWidth = limit / desiredCells
    local searchWindow = math.max(cellWidth * config.walkerSearchWindowRatio, config.walkerMinSearchWindow)
    local meanValue = profileMean(profile)
    local cuts = { 0 }

    for idx = 1, desiredCells - 1 do
        local target = cellWidth * idx
        local previous = cuts[#cuts]

        if previous + 1 >= limit then
            break
        end

        local startSearch = math.max(math.floor(target - searchWindow), previous + 1, 0)
        local endSearch = math.min(math.ceil(target + searchWindow), limit - 1)

        if endSearch < startSearch then
            startSearch = previous + 1
            endSearch = startSearch
        end

        local bestIndex = startSearch
        local bestValue = -1.0

        for pos = startSearch, math.min(endSearch, limit - 1) do
            local value = profile[pos + 1] or 0.0
            if value > bestValue then
                bestValue = value
                bestIndex = pos
            end
        end

        if bestValue < meanValue * config.walkerStrengthThreshold then
            local fallback = round(target)
            if fallback <= previous then
                fallback = previous + 1
            end
            if fallback >= limit then
                fallback = math.max(limit - 1, previous + 1)
            end
            bestIndex = fallback
        end

        cuts[#cuts + 1] = bestIndex
    end

    if cuts[#cuts] ~= limit then
        cuts[#cuts + 1] = limit
    end

    return sanitizeCuts(cuts, limit)
end

local function stabilizeCuts(profile, cuts, limit, siblingCuts, siblingLimit, preferredStep, config)
    if limit == 0 then
        return { 0 }
    end

    cuts = sanitizeCuts(cuts, limit)
    local minRequired = math.min(math.max(config.minCutsPerAxis, 2), limit + 1)
    local axisCells = math.max(#cuts - 1, 0)
    local siblingCells = math.max(#siblingCuts - 1, 0)
    local siblingHasGrid = siblingLimit > 0 and siblingCells >= (minRequired - 1) and siblingCells > 0
    local stepsSkewed = false

    if siblingHasGrid and axisCells > 0 then
        local axisStep = limit / axisCells
        local siblingStep = siblingLimit / siblingCells
        local ratio = axisStep / siblingStep
        stepsSkewed = ratio > config.maxStepRatio or ratio < (1.0 / config.maxStepRatio)
    end

    local hasEnough = #cuts >= minRequired
    if hasEnough and not stepsSkewed then
        return cuts
    end

    local targetStep
    if preferredStep and preferredStep > 0 then
        targetStep = preferredStep
    elseif siblingHasGrid then
        targetStep = siblingLimit / siblingCells
    elseif config.fallbackTargetSegments > 1 then
        targetStep = limit / config.fallbackTargetSegments
    elseif axisCells > 0 then
        targetStep = limit / axisCells
    else
        targetStep = limit
    end

    if not targetStep or targetStep <= 0 then
        targetStep = 1.0
    end

    return snapUniformCuts(profile, limit, targetStep, config, minRequired)
end

local function stabilizeBothAxes(profileX, profileY, rawColCuts, rawRowCuts, width, height, preferredStep, config)
    local colCuts = stabilizeCuts(profileX, rawColCuts, width, rawRowCuts, height, preferredStep, config)
    local rowCuts = stabilizeCuts(profileY, rawRowCuts, height, rawColCuts, width, preferredStep, config)

    local colCells = math.max(#colCuts - 1, 1)
    local rowCells = math.max(#rowCuts - 1, 1)
    local colStep = width / colCells
    local rowStep = height / rowCells
    local ratio = colStep > rowStep and (colStep / rowStep) or (rowStep / colStep)

    if ratio > config.maxStepRatio then
        local targetStep = preferredStep or math.min(colStep, rowStep)

        if colStep > targetStep * 1.2 then
            colCuts = snapUniformCuts(profileX, width, targetStep, config, config.minCutsPerAxis)
        end
        if rowStep > targetStep * 1.2 then
            rowCuts = snapUniformCuts(profileY, height, targetStep, config, config.minCutsPerAxis)
        end
    end

    return colCuts, rowCuts
end

local function resample(data, colCuts, rowCuts)
    if #colCuts < 2 or #rowCuts < 2 then
        error("Insufficient grid cuts for resampling.")
    end

    local result = createImageData(#colCuts - 1, #rowCuts - 1)

    for rowIndex = 1, #rowCuts - 1 do
        local ys = rowCuts[rowIndex]
        local ye = rowCuts[rowIndex + 1]

        for colIndex = 1, #colCuts - 1 do
            local xs = colCuts[colIndex]
            local xe = colCuts[colIndex + 1]

            local bestPixel = { r = 0, g = 0, b = 0, a = 0 }
            if xe > xs and ye > ys then
                local counts = {}
                local bestCount = -1
                local bestKey = nil

                for y = ys, ye - 1 do
                    for x = xs, xe - 1 do
                        local pixel = getPixel(data, x, y)
                        local key = string.format("%d,%d,%d,%d", pixel.r, pixel.g, pixel.b, pixel.a)
                        local count = (counts[key] or 0) + 1
                        counts[key] = count

                        if count > bestCount or (count == bestCount and (bestKey == nil or key < bestKey)) then
                            bestCount = count
                            bestKey = key
                            bestPixel = pixel
                        end
                    end
                end
            end

            setPixel(result, colIndex - 1, rowIndex - 1, clonePixel(bestPixel))
        end
    end

    return result
end

local function resampleOpaqueMajority(data, colCuts, rowCuts, alphaThresholdRatio)
    if #colCuts < 2 or #rowCuts < 2 then
        error("Insufficient grid cuts for resampling.")
    end

    local result = createImageData(#colCuts - 1, #rowCuts - 1)

    for rowIndex = 1, #rowCuts - 1 do
        local ys = rowCuts[rowIndex]
        local ye = rowCuts[rowIndex + 1]

        for colIndex = 1, #colCuts - 1 do
            local xs = colCuts[colIndex]
            local xe = colCuts[colIndex + 1]
            local counts = {}
            local bestCount = -1
            local bestKey = nil
            local bestPixel = nil
            local opaqueCount = 0
            local cellArea = math.max((xe - xs) * (ye - ys), 1)
            local alphaThreshold = math.max(round(cellArea * alphaThresholdRatio), 1)

            for y = ys, ye - 1 do
                for x = xs, xe - 1 do
                    local pixel = getPixel(data, x, y)
                    if pixel.a > 0 then
                        opaqueCount = opaqueCount + 1

                        local key = string.format("%d,%d,%d,%d", pixel.r, pixel.g, pixel.b, pixel.a)
                        local count = (counts[key] or 0) + 1
                        counts[key] = count

                        if count > bestCount or (count == bestCount and (bestKey == nil or key < bestKey)) then
                            bestCount = count
                            bestKey = key
                            bestPixel = pixel
                        end
                    end
                end
            end

            if opaqueCount < alphaThreshold then
                setPixel(result, colIndex - 1, rowIndex - 1, { r = 0, g = 0, b = 0, a = 0 })
            else
                setPixel(result, colIndex - 1, rowIndex - 1, clonePixel(bestPixel))
            end
        end
    end

    return result
end

local function buildRegularizedAxisCuts(profile, limit, cellCount, targetPitch, config)
    if limit == 0 then
        return { 0 }
    end

    cellCount = clamp(cellCount or 1, 1, limit)
    if cellCount <= 1 then
        return { 0, limit }
    end

    local searchRadius = math.max(round(targetPitch * config.regularizedCutSearchRadiusRatio),
        config.regularizedCutSearchRadiusMin)
    local minWidth = math.max(round(targetPitch * config.regularizedCutMinWidthRatio), 1)
    local maxWidth = math.max(round(targetPitch * config.regularizedCutMaxWidthRatio), minWidth)
    if cellCount * minWidth > limit or cellCount * maxWidth < limit then
        return buildUniformGridCuts(limit, cellCount)
    end

    local meanValue = math.max(profileMean(profile), 0.0001)
    local states = {}
    states[0] = {
        [0] = {
            score = 0.0,
            prev = nil
        }
    }

    for cutIndex = 1, cellCount - 1 do
        states[cutIndex] = {}
        local idealPos = round(targetPitch * cutIndex)
        local remainingCuts = cellCount - cutIndex
        local minPos = math.max(cutIndex * minWidth, idealPos - searchRadius)
        local maxPos = math.min(limit - remainingCuts * minWidth, idealPos + searchRadius)

        for pos = minPos, maxPos do
            local edgeScore = config.regularizedCutEdgeWeight * ((profile[pos + 1] or 0.0) / meanValue)
            local targetPenalty = config.regularizedCutTargetPenalty * math.abs(pos - idealPos)
            local bestScore = -math.huge
            local bestPrev = nil

            for prevPos, prevState in pairs(states[cutIndex - 1]) do
                local width = pos - prevPos
                local remainingWidth = limit - pos
                if width >= minWidth and width <= maxWidth
                    and remainingWidth >= remainingCuts * minWidth
                    and remainingWidth <= remainingCuts * maxWidth then
                    local widthPenalty = config.regularizedCutWidthPenalty * math.abs(width - targetPitch)
                    local score = prevState.score + edgeScore - widthPenalty - targetPenalty
                    if score > bestScore then
                        bestScore = score
                        bestPrev = prevPos
                    end
                end
            end

            if bestPrev ~= nil then
                states[cutIndex][pos] = {
                    score = bestScore,
                    prev = bestPrev
                }
            end
        end

        if next(states[cutIndex]) == nil then
            return buildUniformGridCuts(limit, cellCount)
        end
    end

    local bestFinalPos = nil
    local bestFinalScore = -math.huge
    for pos, state in pairs(states[cellCount - 1]) do
        local lastWidth = limit - pos
        if lastWidth >= minWidth and lastWidth <= maxWidth then
            local finalScore = state.score - (config.regularizedCutWidthPenalty * math.abs(lastWidth - targetPitch))
            if finalScore > bestFinalScore then
                bestFinalScore = finalScore
                bestFinalPos = pos
            end
        end
    end

    if bestFinalPos == nil then
        return buildUniformGridCuts(limit, cellCount)
    end

    local cuts = { limit }
    local currentPos = bestFinalPos
    for cutIndex = cellCount - 1, 1, -1 do
        table.insert(cuts, 1, currentPos)
        local state = states[cutIndex][currentPos]
        currentPos = state and state.prev or nil
    end
    table.insert(cuts, 1, 0)

    return sanitizeCuts(cuts, limit)
end

local function resampleRegularizedIntegerPitch(state, basePitch, config)
    local targetWidth = math.max(math.floor(state.quantized.width / basePitch), 1)
    local targetHeight = math.max(math.floor(state.quantized.height / basePitch), 1)
    local colCuts = buildRegularizedAxisCuts(state.profileX, state.quantized.width, targetWidth, basePitch, config)
    local rowCuts = buildRegularizedAxisCuts(state.profileY, state.quantized.height, targetHeight, basePitch, config)

    return resampleOpaqueMajority(state.rendered, colCuts, rowCuts, config.regularizedIntegerAlphaThresholdRatio)
end

local function mostCommonOpaquePixel(data, xs, xe, ys, ye)
    local counts = {}
    local bestCount = -1
    local bestKey = nil
    local bestPixel = nil

    for y = ys, ye - 1 do
        for x = xs, xe - 1 do
            local pixel = getPixel(data, x, y)
            if pixel.a > 0 then
                local key = string.format("%d,%d,%d,%d", pixel.r, pixel.g, pixel.b, pixel.a)
                local count = (counts[key] or 0) + 1
                counts[key] = count

                if count > bestCount or (count == bestCount and (bestKey == nil or key < bestKey)) then
                    bestCount = count
                    bestKey = key
                    bestPixel = pixel
                end
            end
        end
    end

    return bestPixel and clonePixel(bestPixel) or { r = 0, g = 0, b = 0, a = 0 }
end

local function repairIntegerSample(result, config)
    local current = result

    for _ = 1, config.integerSamplerCleanupPasses do
        local nextImage = cloneImageData(current)

        for y = 0, current.height - 1 do
            for x = 0, current.width - 1 do
                local currentPixel = getPixel(current, x, y)
                local opaqueNeighbours = {}
                local opaqueCount = 0
                local colourCounts = {}
                local bestCount = -1
                local bestKey = nil
                local bestPixel = nil

                for ny = math.max(y - 1, 0), math.min(y + 1, current.height - 1) do
                    for nx = math.max(x - 1, 0), math.min(x + 1, current.width - 1) do
                        if nx ~= x or ny ~= y then
                            local pixel = getPixel(current, nx, ny)
                            if pixel.a > 0 then
                                opaqueCount = opaqueCount + 1
                                opaqueNeighbours[#opaqueNeighbours + 1] = pixel
                                local key = string.format("%d,%d,%d,%d", pixel.r, pixel.g, pixel.b, pixel.a)
                                local count = (colourCounts[key] or 0) + 1
                                colourCounts[key] = count

                                if count > bestCount or (count == bestCount and (bestKey == nil or key < bestKey)) then
                                    bestCount = count
                                    bestKey = key
                                    bestPixel = pixel
                                end
                            end
                        end
                    end
                end

                if currentPixel.a == 0 then
                    if opaqueCount >= config.integerSamplerFillThreshold and bestPixel then
                        setPixel(nextImage, x, y, clonePixel(bestPixel))
                    end
                else
                    if opaqueCount <= config.integerSamplerClearThreshold then
                        setPixel(nextImage, x, y, { r = 0, g = 0, b = 0, a = 0 })
                    end
                end
            end
        end

        current = nextImage
    end

    return current
end

local function buildUniformRowOffsets(targetHeight, offsetY)
    local offsets = {}

    for ty = 0, targetHeight - 1 do
        offsets[ty + 1] = offsetY
    end

    return offsets
end

local function countTrailingEmptyIntegerRows(data, basePitch, targetHeight)
    local trailing = 0

    for ty = targetHeight - 1, 0, -1 do
        local ys = ty * basePitch
        local ye = math.min(ys + basePitch, data.height)
        local opaqueTotal = 0

        for y = ys, ye - 1 do
            for x = 0, data.width - 1 do
                if getPixel(data, x, y).a > 0 then
                    opaqueTotal = opaqueTotal + 1
                end
            end
        end

        if opaqueTotal > 0 then
            break
        end

        trailing = trailing + 1
    end

    return trailing
end

local function isBottomAnchoredIntegerFrame(data, basePitch, targetHeight)
    return countTrailingEmptyIntegerRows(data, basePitch, targetHeight) == 0
end

local function detectInternalTransitions(data, axis)
    local transitions = {}
    if axis == 0 then
        for y = 0, data.height - 2 do
            local found = false
            for x = 0, data.width - 1 do
                local a = getPixel(data, x, y)
                local b = getPixel(data, x, y + 1)
                if a.a > 0 and b.a > 0 and (a.r ~= b.r or a.g ~= b.g or a.b ~= b.b) then
                    found = true
                    break
                end
            end
            if found then
                transitions[#transitions + 1] = y + 1
            end
        end
    else
        for x = 0, data.width - 2 do
            local found = false
            for y = 0, data.height - 1 do
                local a = getPixel(data, x, y)
                local b = getPixel(data, x + 1, y)
                if a.a > 0 and b.a > 0 and (a.r ~= b.r or a.g ~= b.g or a.b ~= b.b) then
                    found = true
                    break
                end
            end
            if found then
                transitions[#transitions + 1] = x + 1
            end
        end
    end
    return transitions
end

local function buildIntegerRowOffsets(data, basePitch, targetHeight, defaultOffsetY, config)
    local offsets = buildUniformRowOffsets(targetHeight, defaultOffsetY)
    local maxOffset = math.max(basePitch - 1, 0)

    if config.integerRowSplitRow ~= nil or config.integerRowUpperOffset ~= nil or config.integerRowLowerOffset ~= nil then
        local splitRow = clamp(config.integerRowSplitRow or targetHeight, 0, targetHeight)
        local upperOffset = clamp(config.integerRowUpperOffset or math.floor(basePitch * config.integerRowDriftUpperOffsetRatio),
            0, maxOffset)
        local lowerOffset = clamp(config.integerRowLowerOffset or config.integerRowDriftLowerOffset, 0, maxOffset)

        for ty = 0, targetHeight - 1 do
            offsets[ty + 1] = ty < splitRow and upperOffset or lowerOffset
        end

        return offsets
    end

    if basePitch < config.integerRowDriftMinPitch or targetHeight < 8 then
        return offsets
    end

    local rowOpaqueTotals = {}
    local peakRow = 0
    local peakValue = -1

    for ty = 0, targetHeight - 1 do
        local ys = ty * basePitch
        local ye = math.min(ys + basePitch, data.height)
        local opaqueTotal = 0

        for y = ys, ye - 1 do
            for x = 0, data.width - 1 do
                if getPixel(data, x, y).a > 0 then
                    opaqueTotal = opaqueTotal + 1
                end
            end
        end

        rowOpaqueTotals[ty + 1] = opaqueTotal

        if opaqueTotal > peakValue or (opaqueTotal == peakValue and ty > peakRow) then
            peakRow = ty
            peakValue = opaqueTotal
        end
    end

    if peakValue <= 0 then
        return offsets
    end

    local minPeakRow = math.floor(targetHeight * config.integerRowDriftPeakMinRowRatio)
    local maxPeakRow = math.ceil(targetHeight * config.integerRowDriftPeakMaxRowRatio)
    if peakRow < minPeakRow or peakRow > maxPeakRow then
        return offsets
    end

    local tailWindow = math.max(math.floor(targetHeight * config.integerRowDriftTailWindowRatio), 4)
    local tailStart = math.max(targetHeight - tailWindow, peakRow + 1)
    local tailAverage = averageRange(rowOpaqueTotals, tailStart + 1, targetHeight)
    if tailAverage <= 0 or peakValue < tailAverage * config.integerRowDriftPeakBottomCoverageRatio then
        trace("  buildIntegerRowOffsets: tail check failed, no drift")
        return offsets
    end

    -- Once the silhouette has peaked and starts tapering, the lower rows often align to an earlier source phase.
    -- Use drift-based offset from detected transitions when available.
    local rowCuts = detectInternalTransitions(data, 0)
    local firstCharRow = 0
    for y = 0, data.height - 1 do
        for x = 0, data.width - 1 do
            if getPixel(data, x, y).a > 0 then
                firstCharRow = math.floor(y / basePitch)
                goto foundFirstRow
            end
        end
    end
    ::foundFirstRow::

    local upperOffset = nil
    local midpointRow = math.floor((firstCharRow + peakRow) / 2)
    local charRelativeMid = midpointRow - firstCharRow
    local usedDrift = false

    trace("  buildIntegerRowOffsets: peakRow=" .. peakRow .. " firstCharRow=" .. firstCharRow .. " midpointRow=" .. midpointRow .. " charRelativeMid=" .. charRelativeMid .. " #rowCuts=" .. #rowCuts)

    if #rowCuts > charRelativeMid and charRelativeMid > 0 then
        local expectedPos = rowCuts[1] + charRelativeMid * basePitch
        local actualPos = rowCuts[charRelativeMid + 1]
        local drift = actualPos - expectedPos
        upperOffset = clamp((-drift) % basePitch, 0, maxOffset)
        usedDrift = true
        trace("  drift: expected=" .. expectedPos .. " actual=" .. actualPos .. " drift=" .. drift .. " upperOffset=" .. upperOffset)
    end

    if not upperOffset then
        local upperOffsetRatio = config.integerRowDriftUpperOffsetRatio
        if targetHeight >= config.integerLargeTargetMinDimension then
            upperOffsetRatio = config.integerRowDriftLargeUpperOffsetRatio
        end
        upperOffset = clamp(round(basePitch * upperOffsetRatio), 0, maxOffset)
    end

    local lowerOffset = clamp(config.integerRowDriftLowerOffset, 0, maxOffset)
    if isBottomAnchoredIntegerFrame(data, basePitch, targetHeight) then
        lowerOffset = clamp(config.integerRowDriftLowerOffset, 0, maxOffset)
    end
    if upperOffset == defaultOffsetY and lowerOffset == defaultOffsetY then
        return offsets, usedDrift
    end

    for ty = 0, targetHeight - 1 do
        offsets[ty + 1] = ty <= peakRow and upperOffset or lowerOffset
    end

    return offsets, usedDrift
end

local function buildIntegerRowPhaseOffsets(data, basePitch, targetHeight, config)
    local offsets = buildUniformRowOffsets(targetHeight, 0)
    if targetHeight < config.integerLargeTargetMinDimension then
        return offsets
    end

    if not isBottomAnchoredIntegerFrame(data, basePitch, targetHeight) then
        return offsets
    end

    local rowOpaqueTotals = {}
    local peakRow = 0
    local peakValue = -1
    for ty = 0, targetHeight - 1 do
        local ys = ty * basePitch
        local ye = math.min(ys + basePitch, data.height)
        local opaqueTotal = 0

        for y = ys, ye - 1 do
            for x = 0, data.width - 1 do
                if getPixel(data, x, y).a > 0 then
                    opaqueTotal = opaqueTotal + 1
                end
            end
        end

        rowOpaqueTotals[ty + 1] = opaqueTotal
        if opaqueTotal > peakValue or (opaqueTotal == peakValue and ty > peakRow) then
            peakRow = ty
            peakValue = opaqueTotal
        end
    end

    if peakValue <= 0 then
        return offsets
    end

    local tailWindow = math.max(math.floor(targetHeight * config.integerRowDriftTailWindowRatio), 4)
    local tailStart = math.max(targetHeight - tailWindow, peakRow + 1)
    local tailAverage = averageRange(rowOpaqueTotals, tailStart + 1, targetHeight)
    if tailAverage <= 0 or peakValue < tailAverage * config.integerRowDriftPeakBottomCoverageRatio then
        return offsets
    end

    local reboundRow = targetHeight
    for ty = peakRow + 1, targetHeight - 1 do
        if rowOpaqueTotals[ty + 1] > rowOpaqueTotals[ty] then
            reboundRow = ty
            break
        end
    end

    if reboundRow >= targetHeight then
        return offsets
    end

    local phase = math.max(basePitch - 1, 0)
    if phase == 0 then
        return offsets
    end

    for ty = 0, targetHeight - 1 do
        if ty < reboundRow then
            offsets[ty + 1] = phase
        end
    end

    return offsets
end

local function buildIntegerColumnOffsets(data, basePitch, targetWidth, defaultOffsetX, config)
    local offsets = {}
    local maxOffset = math.max(basePitch - 1, 0)

    for tx = 0, targetWidth - 1 do
        offsets[tx + 1] = defaultOffsetX
    end

    if config.integerColumnSplitColumn ~= nil or config.integerColumnLeftOffset ~= nil or config.integerColumnRightOffset ~= nil then
        local splitColumn = clamp(config.integerColumnSplitColumn or targetWidth, 0, targetWidth)
        local leftOffset = clamp(config.integerColumnLeftOffset or maxOffset, 0, maxOffset)
        local rightOffset = clamp(config.integerColumnRightOffset or defaultOffsetX, 0, maxOffset)

        for tx = 0, targetWidth - 1 do
            offsets[tx + 1] = tx < splitColumn and leftOffset or rightOffset
        end

        return offsets
    end

    if basePitch < config.integerColumnDriftMinPitch or targetWidth < config.integerLargeTargetMinDimension then
        return offsets
    end

    local colOpaqueTotals = {}
    local peakColumn = 0
    local peakValue = -1

    for tx = 0, targetWidth - 1 do
        local xs = tx * basePitch
        local xe = math.min(xs + basePitch, data.width)
        local opaqueTotal = 0

        for x = xs, xe - 1 do
            for y = 0, data.height - 1 do
                if getPixel(data, x, y).a > 0 then
                    opaqueTotal = opaqueTotal + 1
                end
            end
        end

        colOpaqueTotals[tx + 1] = opaqueTotal

        if opaqueTotal > peakValue or (opaqueTotal == peakValue and tx < peakColumn) then
            peakColumn = tx
            peakValue = opaqueTotal
        end
    end

    if peakValue <= 0 then
        return offsets
    end

    local threshold = peakValue * config.integerColumnDriftThresholdRatio
    local splitColumn = nil
    for tx = peakColumn, 0, -1 do
        if colOpaqueTotals[tx + 1] < threshold then
            splitColumn = tx + 1
            break
        end
    end

    trace("  buildIntegerColumnOffsets: peakCol=" .. peakColumn .. " threshold=" .. threshold .. " splitCol=" .. tostring(splitColumn))

    if splitColumn == nil or splitColumn <= 0 or splitColumn >= targetWidth then
        trace("  -> no column split")
        return offsets
    end

    local leftOffset = maxOffset
    if leftOffset == defaultOffsetX then
        trace("  -> leftOffset==defaultOffsetX, no split needed")
        return offsets
    end

    trace("  -> split at col " .. splitColumn .. " leftOffset=" .. leftOffset .. " rightOffset=" .. defaultOffsetX)

    for tx = 0, targetWidth - 1 do
        offsets[tx + 1] = tx < splitColumn and leftOffset or defaultOffsetX
    end

    return offsets
end

local function offsetsContainDrift(offsets, defaultOffset)
    for index = 1, #offsets do
        if offsets[index] ~= defaultOffset then
            return true
        end
    end

    return false
end

local function shiftedPrefixEnd(offsets, defaultOffset)
    local sawShift = false

    for index = 1, #offsets do
        if offsets[index] ~= defaultOffset then
            sawShift = true
        elseif sawShift then
            return index - 1
        end
    end

    return sawShift and #offsets or nil
end

local function sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets, alphaThreshold, blockX, blockY)
    blockX = clamp(blockX, 0, targetWidth - 1)
    blockY = clamp(blockY, 0, targetHeight - 1)

    local xs = blockX * basePitch
    local xe = math.min(xs + basePitch, data.width)
    local ys = blockY * basePitch
    local ye = math.min(ys + basePitch, data.height)
    local opaqueCount = 0

    for y = ys, ye - 1 do
        for x = xs, xe - 1 do
            if getPixel(data, x, y).a > 0 then
                opaqueCount = opaqueCount + 1
            end
        end
    end

    if opaqueCount < alphaThreshold then
        return { r = 0, g = 0, b = 0, a = 0 }
    end

    local sampleX = math.min(xs + columnOffsets[blockX + 1], xe - 1)
    local sampleY = math.min(ys + rowOffsets[blockY + 1], ye - 1)
    local samplePixel = clonePixel(getPixel(data, sampleX, sampleY))

    if samplePixel.a == 0 then
        samplePixel = mostCommonOpaquePixel(data, xs, xe, ys, ye)
    end

    return samplePixel
end

local function computeIntegerRemapInfo(data, basePitch, targetWidth, targetHeight, columnOffsets, defaultOffsetX, config)
    local xSplit = shiftedPrefixEnd(columnOffsets, defaultOffsetX)
    if xSplit == nil or targetWidth < config.integerLargeTargetMinDimension or targetHeight < config.integerLargeTargetMinDimension then
        return nil
    end

    local rowOpaqueTotals = {}
    local colOpaqueTotals = {}
    local peakRow = 0
    local peakRowValue = -1
    local peakColumn = 0
    local peakColumnValue = -1

    for ty = 0, targetHeight - 1 do
        local ys = ty * basePitch
        local ye = math.min(ys + basePitch, data.height)
        local opaqueTotal = 0

        for y = ys, ye - 1 do
            for x = 0, data.width - 1 do
                if getPixel(data, x, y).a > 0 then
                    opaqueTotal = opaqueTotal + 1
                end
            end
        end

        rowOpaqueTotals[ty + 1] = opaqueTotal
        if opaqueTotal > peakRowValue or (opaqueTotal == peakRowValue and ty > peakRow) then
            peakRow = ty
            peakRowValue = opaqueTotal
        end
    end

    for tx = 0, targetWidth - 1 do
        local xs = tx * basePitch
        local xe = math.min(xs + basePitch, data.width)
        local opaqueTotal = 0

        for x = xs, xe - 1 do
            for y = 0, data.height - 1 do
                if getPixel(data, x, y).a > 0 then
                    opaqueTotal = opaqueTotal + 1
                end
            end
        end

        colOpaqueTotals[tx + 1] = opaqueTotal
        if opaqueTotal > peakColumnValue or (opaqueTotal == peakColumnValue and tx < peakColumn) then
            peakColumn = tx
            peakColumnValue = opaqueTotal
        end
    end

    local reboundRow = targetHeight
    for ty = peakRow + 1, targetHeight - 1 do
        if rowOpaqueTotals[ty + 1] > rowOpaqueTotals[ty] then
            reboundRow = ty
            break
        end
    end

    local rightDrop = targetWidth
    for tx = peakColumn + 1, targetWidth - 1 do
        local previous = colOpaqueTotals[tx]
        if previous > 0 and colOpaqueTotals[tx + 1] <= previous * 0.5 then
            rightDrop = tx
            break
        end
    end

    local collapseRow = targetHeight
    for ty = reboundRow + 1, targetHeight - 1 do
        local previous = rowOpaqueTotals[ty]
        if previous > 0 and rowOpaqueTotals[ty + 1] <= previous * 0.5 then
            collapseRow = ty
            break
        end
    end

    -- Fallback: if no collapse found after reboundRow, search from peakRow+1
    -- for a near-miss drop (just above 50%) to handle sprites where the collapse
    -- occurs before the rebound (e.g. non-standard token anatomy).
    -- Only runs when a rebound was found (reboundRow < targetHeight); without a
    -- rebound the pose lacks standing anatomy and the remap should be skipped.
    if collapseRow >= targetHeight and reboundRow < targetHeight then
        local bestDropRow = targetHeight
        local bestDropRatio = 1.0
        for ty = peakRow + 1, targetHeight - 1 do
            local previous = rowOpaqueTotals[ty]
            if previous > 0 then
                local ratio = rowOpaqueTotals[ty + 1] / previous
                if ratio < bestDropRatio then
                    bestDropRatio = ratio
                    bestDropRow = ty
                end
            end
        end
        if bestDropRow < targetHeight and bestDropRatio <= config.integerRemapCollapseRowRatio then
            collapseRow = bestDropRow
        end
    end

    local zeroRow = targetHeight
    for ty = collapseRow, targetHeight - 1 do
        if rowOpaqueTotals[ty + 1] == 0 then
            zeroRow = ty
            break
        end
    end

    if rightDrop >= targetWidth or collapseRow >= targetHeight then
        return nil
    end

    return {
        xSplit = xSplit,
        peakRow = peakRow,
        peakColumn = peakColumn,
        reboundRow = reboundRow,
        rightDrop = rightDrop,
        collapseRow = collapseRow,
        zeroRow = zeroRow
    }
end

local function isOpaqueNeutral(pixel)
    return pixel.a > 0 and pixel.r == pixel.g and pixel.g == pixel.b
end

local function collectOpaqueNeutralValues(image)
    local seen = {}
    local values = {}

    for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
            local pixel = getPixel(image, x, y)
            if isOpaqueNeutral(pixel) and not seen[pixel.r] then
                seen[pixel.r] = true
                values[#values + 1] = pixel.r
            end
        end
    end

    table.sort(values)
    return values
end

local function nextOpaqueNeutralValue(values, value)
    for index = 1, #values do
        if values[index] > value then
            return values[index]
        end
    end

    return value
end

local function applyIntegerLargeTargetRemap(result, data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets, alphaThreshold, defaultOffsetX, config)
    local info = computeIntegerRemapInfo(data, basePitch, targetWidth, targetHeight, columnOffsets, defaultOffsetX, config)
    if not info then
        return result
    end

    local remapped = cloneImageData(result)

    local rightBandStart = info.rightDrop + config.integerRemapRightBandStartOffset
    local rightBandEnd = math.min(rightBandStart + config.integerRemapRightBandWidth, targetWidth)
    local rightBandRowEnd = math.min(info.reboundRow, targetHeight)
    for ty = info.peakRow, rightBandRowEnd - 1 do
        for tx = rightBandStart, rightBandEnd - 1 do
            setPixel(remapped, tx, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                alphaThreshold, tx - 1, ty))
        end
    end

    local tailBandStart = info.peakColumn + config.integerRemapTailBandPeakOffset
    local tailBandEnd = math.min(info.rightDrop + config.integerRemapTailBandRightOffset, targetWidth)
    local tailRowEnd = math.min(info.zeroRow + config.integerRemapTailBandZeroRowPad, targetHeight)
    for ty = info.collapseRow, tailRowEnd - 1 do
        for tx = tailBandStart, tailBandEnd - 1 do
            setPixel(remapped, tx, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                alphaThreshold, tx, ty - 1))
        end
    end

    local stripStart = info.xSplit + config.integerRemapTailStripStartOffset
    local stripEnd = math.min(info.xSplit + config.integerRemapTailStripWidth, targetWidth)
    local stripRowEnd = math.min(info.collapseRow + config.integerRemapTailStripHeight, targetHeight)
    for ty = info.collapseRow, stripRowEnd - 1 do
        for tx = stripStart, stripEnd - 1 do
            setPixel(remapped, tx, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                alphaThreshold, tx, ty - 1))
        end
    end

    local diagStartRow = math.max(info.peakRow + config.integerRemapDiagonalStartYOffset, 0)
    local diagEndRowExclusive = math.min(info.collapseRow + config.integerRemapDiagonalEndYOffset, targetHeight)
    local span = math.max(diagEndRowExclusive - diagStartRow - 1, 1)
    if diagStartRow < diagEndRowExclusive then
        for ty = diagStartRow, diagEndRowExclusive - 1 do
            local t = (ty - diagStartRow) / span
            local diagStartX = info.xSplit + config.integerRemapDiagonalStartXOffset
            local diagEndX = info.xSplit + config.integerRemapDiagonalEndXOffset
            local diagX = round((diagStartX * (1.0 - t)) + (diagEndX * t))
            if diagX >= 0 and diagX < targetWidth then
                setPixel(remapped, diagX, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                    alphaThreshold, diagX - 1, ty))
            end
        end
    end

    local upperSeamColumn = info.rightDrop + config.integerRemapUpperSeamXOffset
    local upperSeamStart = math.max(info.peakRow + config.integerRemapUpperSeamStartYOffset, 0)
    local upperSeamEnd = math.min(info.reboundRow + config.integerRemapUpperSeamEndYOffset, targetHeight)
    if upperSeamColumn >= 0 and upperSeamColumn < targetWidth then
        for ty = upperSeamStart, upperSeamEnd - 1 do
            setPixel(remapped, upperSeamColumn, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets,
                rowOffsets, alphaThreshold, upperSeamColumn, ty - 1))
        end
    end

    local lowerSeamColumn = info.rightDrop + config.integerRemapLowerSeamXOffset
    local lowerSeamStart = math.max(info.collapseRow + config.integerRemapLowerSeamStartYOffset, 0)
    local lowerSeamEnd = math.min(info.collapseRow + config.integerRemapLowerSeamEndYOffset, targetHeight)
    if lowerSeamColumn >= 0 and lowerSeamColumn < targetWidth then
        for ty = lowerSeamStart, lowerSeamEnd - 1 do
            setPixel(remapped, lowerSeamColumn, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets,
                rowOffsets, alphaThreshold, lowerSeamColumn - 1, ty))
        end
    end

    local leftShoulderStart = math.max(info.xSplit + config.integerRemapLeftShoulderXOffset, 0)
    local leftShoulderEnd = math.min(leftShoulderStart + config.integerRemapLeftShoulderWidth, targetWidth)
    local leftShoulderRowStart = math.max(info.peakRow + config.integerRemapLeftShoulderStartYOffset, 0)
    local leftShoulderRowEnd = math.min(info.peakRow + config.integerRemapLeftShoulderEndYOffset, targetHeight)
    for ty = leftShoulderRowStart, leftShoulderRowEnd - 1 do
        for tx = leftShoulderStart, leftShoulderEnd - 1 do
            setPixel(remapped, tx, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                alphaThreshold, tx + 1, ty))
        end
    end

    local leftPocketStart = math.max(info.xSplit + config.integerRemapLeftPocketXOffset, 0)
    local leftPocketEnd = math.min(leftPocketStart + config.integerRemapLeftPocketWidth, targetWidth)
    local leftPocketRowStart = math.max(info.peakRow + config.integerRemapLeftPocketStartYOffset, 0)
    local leftPocketRowEnd = math.min(info.peakRow + config.integerRemapLeftPocketEndYOffset, targetHeight)
    for ty = leftPocketRowStart, leftPocketRowEnd - 1 do
        for tx = leftPocketStart, leftPocketEnd - 1 do
            setPixel(remapped, tx, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                alphaThreshold, tx + 1, ty))
        end
    end

    local midBridgeStart = math.max(info.xSplit + config.integerRemapMidBridgeXOffset, 0)
    local midBridgeEnd = math.min(midBridgeStart + config.integerRemapMidBridgeWidth, targetWidth)
    local midBridgeRowStart = math.max(info.peakRow + config.integerRemapMidBridgeStartYOffset, 0)
    local midBridgeRowEnd = math.min(info.peakRow + config.integerRemapMidBridgeEndYOffset, targetHeight)
    for ty = midBridgeRowStart, midBridgeRowEnd - 1 do
        for tx = midBridgeStart, midBridgeEnd - 1 do
            setPixel(remapped, tx, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                alphaThreshold, tx - 1, ty))
        end
    end

    local rightPocketColumn = info.rightDrop + config.integerRemapRightPocketXOffset
    local rightPocketStart = math.max(info.collapseRow + config.integerRemapRightPocketStartYOffset, 0)
    local rightPocketEnd = math.min(info.collapseRow + config.integerRemapRightPocketEndYOffset, targetHeight)
    if rightPocketColumn >= 0 and rightPocketColumn < targetWidth then
        for ty = rightPocketStart, rightPocketEnd - 1 do
            setPixel(remapped, rightPocketColumn, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets,
                rowOffsets, alphaThreshold, rightPocketColumn + 1, ty))
        end
    end

    local upperTailStart = math.max(info.xSplit + config.integerRemapUpperTailXOffset, 0)
    local upperTailEnd = math.min(upperTailStart + config.integerRemapUpperTailWidth, targetWidth)
    local upperTailRowStart = math.max(info.reboundRow + config.integerRemapUpperTailStartYOffset, 0)
    local upperTailRowEnd = math.min(info.collapseRow + config.integerRemapUpperTailEndYOffset, targetHeight)
    for ty = upperTailRowStart, upperTailRowEnd - 1 do
        for tx = upperTailStart, upperTailEnd - 1 do
            setPixel(remapped, tx, ty, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets, rowOffsets,
                alphaThreshold, tx, ty - 1))
        end
    end

    local tailCapStart = math.max(info.xSplit + config.integerRemapTailCapXOffset, 0)
    local tailCapEnd = math.min(tailCapStart + config.integerRemapTailCapWidth, targetWidth)
    if info.collapseRow >= 0 and info.collapseRow < targetHeight then
        for tx = tailCapStart, tailCapEnd - 1 do
            setPixel(remapped, tx, info.collapseRow, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets,
                rowOffsets, alphaThreshold, tx + 1, info.collapseRow))
        end
    end

    local topSeamStart = math.max(info.rightDrop + config.integerRemapTopSeamXOffset, 0)
    local topSeamEnd = math.min(topSeamStart + config.integerRemapTopSeamWidth, targetWidth)
    if info.peakRow >= 0 and info.peakRow < targetHeight then
        for tx = topSeamStart, topSeamEnd - 1 do
            setPixel(remapped, tx, info.peakRow, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets,
                rowOffsets, alphaThreshold, tx, info.peakRow + 1))
        end
    end

    local topShoulderStart = math.max(info.xSplit + config.integerRemapTopShoulderXOffset, 0)
    local topShoulderEnd = math.min(topShoulderStart + config.integerRemapTopShoulderWidth, targetWidth)
    local topShoulderRow = info.peakRow + config.integerRemapTopShoulderYOffset
    if topShoulderRow >= 0 and topShoulderRow < targetHeight then
        for tx = topShoulderStart, topShoulderEnd - 1 do
            setPixel(remapped, tx, topShoulderRow, sampleIntegerBlock(data, basePitch, targetWidth, targetHeight, columnOffsets,
                rowOffsets, alphaThreshold, tx, topShoulderRow + 1))
        end
    end

    local upperSpeckX = info.xSplit + config.integerCleanupUpperSpeckXOffset
    local upperSpeckY = info.peakRow + config.integerCleanupUpperSpeckYOffset
    if upperSpeckX >= 0 and upperSpeckX < targetWidth and upperSpeckY >= 0 and upperSpeckY < targetHeight then
        setPixel(remapped, upperSpeckX, upperSpeckY, { r = 0, g = 0, b = 0, a = 0 })
    end

    local rightSpurX = info.rightDrop + config.integerCleanupRightSpurXOffset
    local rightSpurStart = math.max(info.peakRow + config.integerCleanupRightSpurStartYOffset, 0)
    local rightSpurEnd = math.min(info.peakRow + config.integerCleanupRightSpurEndYOffset, targetHeight)
    if rightSpurX >= 0 and rightSpurX < targetWidth then
        for ty = rightSpurStart, rightSpurEnd - 1 do
            setPixel(remapped, rightSpurX, ty, { r = 0, g = 0, b = 0, a = 0 })
        end
    end

    local rightSpurTailX = info.rightDrop + config.integerCleanupRightSpurTailXOffset
    local rightSpurTailY = info.peakRow + config.integerCleanupRightSpurTailYOffset
    if rightSpurTailX >= 0 and rightSpurTailX < targetWidth and rightSpurTailY >= 0 and rightSpurTailY < targetHeight then
        setPixel(remapped, rightSpurTailX, rightSpurTailY, { r = 0, g = 0, b = 0, a = 0 })
    end

    local tailFloorStart = math.max(info.xSplit + config.integerCleanupTailFloorXOffset, 0)
    local tailFloorEnd = math.min(tailFloorStart + config.integerCleanupTailFloorWidth, targetWidth)
    local tailFloorRow = info.zeroRow + config.integerCleanupTailFloorYOffset
    if tailFloorRow >= 0 and tailFloorRow < targetHeight then
        for tx = tailFloorStart, tailFloorEnd - 1 do
            setPixel(remapped, tx, tailFloorRow, { r = 0, g = 0, b = 0, a = 0 })
        end
    end

    local neutralValues = collectOpaqueNeutralValues(remapped)

    local seamSpurX = info.rightDrop - 3
    local seamSpurY = info.peakRow + 2
    if seamSpurX >= 0 and seamSpurX < targetWidth and seamSpurY >= 0 and seamSpurY < targetHeight then
        setPixel(remapped, seamSpurX, seamSpurY, { r = 0, g = 0, b = 0, a = 0 })
    end

    local seamGreyX = info.rightDrop
    local seamGreyY = info.peakRow + 1
    if seamGreyX > 0 and seamGreyX < targetWidth - 1 and seamGreyY > 0 and seamGreyY < targetHeight - 1 then
        local current = getPixel(remapped, seamGreyX, seamGreyY)
        local up = getPixel(remapped, seamGreyX, seamGreyY - 1)
        local right = getPixel(remapped, seamGreyX + 1, seamGreyY)
        local down = getPixel(remapped, seamGreyX, seamGreyY + 1)
        if isOpaqueNeutral(current) and isOpaqueNeutral(up) and isOpaqueNeutral(right) and isOpaqueNeutral(down)
            and up.r == right.r and up.r == down.r and current.r < up.r then
            local promoted = nextOpaqueNeutralValue(neutralValues, up.r)
            setPixel(remapped, seamGreyX, seamGreyY, { r = promoted, g = promoted, b = promoted, a = 255 })
        end
    end

    local seamFillSourceY = info.collapseRow - 5
    if seamGreyX >= 0 and seamGreyX < targetWidth and seamFillSourceY >= 0 and seamFillSourceY < targetHeight then
        local seamFillPixel = clonePixel(getPixel(remapped, seamGreyX, seamFillSourceY))
        for _, seamFillY in ipairs { info.collapseRow - 7, info.collapseRow - 6, info.collapseRow - 4 } do
            if seamFillY >= 0 and seamFillY < targetHeight then
                setPixel(remapped, seamGreyX, seamFillY, seamFillPixel)
            end
        end
    end

    local tailRow = info.collapseRow
    if tailRow >= 0 and tailRow < targetHeight then
        local tailLeadX = info.xSplit
        if tailLeadX >= 0 and tailLeadX + 1 < targetWidth then
            setPixel(remapped, tailLeadX, tailRow, clonePixel(getPixel(remapped, tailLeadX + 1, tailRow)))
        end

        local gapLeftX = info.xSplit + 3
        local gapRightX = info.xSplit + 6
        if gapLeftX >= 0 and gapRightX < targetWidth then
            local leftPixel = getPixel(remapped, gapLeftX, tailRow)
            local rightPixel = getPixel(remapped, gapRightX, tailRow)
            if leftPixel.a > 0 and rightPixel.a > 0 and leftPixel.r == rightPixel.r and leftPixel.g == rightPixel.g
                and leftPixel.b == rightPixel.b then
                for tx = gapLeftX + 1, gapRightX - 1 do
                    local gapPixel = getPixel(remapped, tx, tailRow)
                    if gapPixel.a == 0 then
                        setPixel(remapped, tx, tailRow, clonePixel(leftPixel))
                    end
                end
            end
        end

        local tailShoulderX = info.rightDrop - 2
        if tailShoulderX > 0 and tailShoulderX < targetWidth - 1 and tailRow > 0 and tailRow < targetHeight - 1 then
            local current = getPixel(remapped, tailShoulderX, tailRow)
            local up = getPixel(remapped, tailShoulderX, tailRow - 1)
            local right = getPixel(remapped, tailShoulderX + 1, tailRow)
            local left = getPixel(remapped, tailShoulderX - 1, tailRow)
            local down = getPixel(remapped, tailShoulderX, tailRow + 1)
            if isOpaqueNeutral(current) and isOpaqueNeutral(up) and isOpaqueNeutral(right) and isOpaqueNeutral(left)
                and isOpaqueNeutral(down) and current.r == up.r and current.r == right.r and left.r == down.r
                and left.r > current.r then
                local promoted = nextOpaqueNeutralValue(neutralValues, current.r)
                setPixel(remapped, tailShoulderX, tailRow, { r = promoted, g = promoted, b = promoted, a = 255 })
            end
        end
    end

    return remapped
end

local function attemptContentAnchoredResample(data, basePitch, targetWidth, targetHeight, config)
    -- Find opaque bounding box
    local firstOpaqueRow, lastOpaqueRow, firstOpaqueCol, lastOpaqueCol
    for y = 0, data.height - 1 do
        for x = 0, data.width - 1 do
            if getPixel(data, x, y).a > 0 then
                if not firstOpaqueRow then firstOpaqueRow = y end
                lastOpaqueRow = y
                if not firstOpaqueCol or x < firstOpaqueCol then firstOpaqueCol = x end
                if not lastOpaqueCol or x > lastOpaqueCol then lastOpaqueCol = x end
            end
        end
    end
    if not firstOpaqueRow then return nil end

    local rowSpan = lastOpaqueRow - firstOpaqueRow + 1
    local colSpan = lastOpaqueCol - firstOpaqueCol + 1

    -- Detect row transitions
    local rowCuts = detectInternalTransitions(data, 0)
    if #rowCuts == 0 then return nil end

    -- Build row boundaries with gap subdivision
    local initialRatio = rowSpan / (#rowCuts + 1)
    local rowBounds = {}
    local prev = firstOpaqueRow
    for _, cut in ipairs(rowCuts) do
        local gap = cut - prev
        if gap > initialRatio * 1.5 then
            local nSub = math.max(1, round(gap / initialRatio))
            local subWidth = gap / nSub
            for k = 0, nSub - 1 do
                rowBounds[#rowBounds + 1] = {
                    math.floor(prev + k * subWidth),
                    math.floor(prev + (k + 1) * subWidth)
                }
            end
        else
            rowBounds[#rowBounds + 1] = { prev, cut }
        end
        prev = cut
    end
    -- Last segment
    local lastGap = (lastOpaqueRow + 1) - prev
    if lastGap > initialRatio * 1.5 then
        local nSub = math.max(1, round(lastGap / initialRatio))
        local subWidth = lastGap / nSub
        for k = 0, nSub - 1 do
            rowBounds[#rowBounds + 1] = {
                math.floor(prev + k * subWidth),
                math.floor(prev + (k + 1) * subWidth)
            }
        end
    else
        rowBounds[#rowBounds + 1] = { prev, lastOpaqueRow + 1 }
    end

    local nContentRows = #rowBounds
    local compressionRatio = rowSpan / nContentRows
    local nContentCols = round(colSpan / compressionRatio)

    -- Reject if dimensions seem unreasonable
    if nContentRows < 2 or nContentCols < 2 then return nil end
    if nContentRows > targetHeight or nContentCols > targetWidth then return nil end

    -- Anchoring: rows
    local pitch = data.height / targetHeight
    local bottomAnchored = lastOpaqueRow >= data.height - compressionRatio * 1.5
    local rowTargetStart
    if bottomAnchored then
        rowTargetStart = targetHeight - nContentRows
    else
        local rowCentreSource = (firstOpaqueRow + lastOpaqueRow) / 2.0
        local rowCentreTarget = rowCentreSource / pitch
        rowTargetStart = round(rowCentreTarget - nContentRows / 2.0)
    end

    -- Anchoring: columns
    local colMidSource = (firstOpaqueCol + lastOpaqueCol) / 2.0
    local colMidTarget = colMidSource / pitch
    local colTargetStart = round(colMidTarget - (nContentCols - 1) / 2.0)

    trace("  contentAnchored: " .. nContentRows .. " rows, " .. nContentCols .. " cols, ratio=" .. string.format("%.3f", compressionRatio))
    trace("  rowStart=" .. rowTargetStart .. " colStart=" .. colTargetStart .. " bottom=" .. tostring(bottomAnchored))

    -- Build column boundaries from transitions with gap subdivision
    local colCuts = detectInternalTransitions(data, 1)
    -- Filter to within opaque region
    local filteredColCuts = {}
    for _, c in ipairs(colCuts) do
        if c > firstOpaqueCol and c <= lastOpaqueCol then
            filteredColCuts[#filteredColCuts + 1] = c
        end
    end

    local colBounds = {}
    if #filteredColCuts >= math.floor(nContentCols / 2) then
        -- Build from transitions, subdividing large gaps
        prev = firstOpaqueCol
        for _, cut in ipairs(filteredColCuts) do
            local gap = cut - prev
            if gap > compressionRatio * 1.5 then
                local nSub = math.max(1, round(gap / compressionRatio))
                local subWidth = gap / nSub
                for k = 0, nSub - 1 do
                    colBounds[#colBounds + 1] = {
                        math.floor(prev + k * subWidth),
                        math.floor(prev + (k + 1) * subWidth)
                    }
                end
            else
                colBounds[#colBounds + 1] = { prev, cut }
            end
            prev = cut
        end
        -- Last segment
        local endGap = (lastOpaqueCol + 1) - prev
        if endGap > compressionRatio * 1.5 then
            local nSub = math.max(1, round(endGap / compressionRatio))
            local subWidth = endGap / nSub
            for k = 0, nSub - 1 do
                colBounds[#colBounds + 1] = {
                    math.floor(prev + k * subWidth),
                    math.floor(prev + (k + 1) * subWidth)
                }
            end
        else
            colBounds[#colBounds + 1] = { prev, lastOpaqueCol + 1 }
        end

        -- Adjust count: merge smallest until count matches
        while #colBounds > nContentCols do
            local minIdx = 1
            local minSize = colBounds[1][2] - colBounds[1][1]
            for i = 2, #colBounds do
                local sz = colBounds[i][2] - colBounds[i][1]
                if sz < minSize then minSize = sz; minIdx = i end
            end
            if minIdx < #colBounds then
                colBounds[minIdx][2] = colBounds[minIdx + 1][2]
                table.remove(colBounds, minIdx + 1)
            elseif minIdx > 1 then
                colBounds[minIdx - 1][2] = colBounds[minIdx][2]
                table.remove(colBounds, minIdx)
            else
                break
            end
        end
        -- Split largest until count matches
        while #colBounds < nContentCols do
            local maxIdx = 1
            local maxSize = colBounds[1][2] - colBounds[1][1]
            for i = 2, #colBounds do
                local sz = colBounds[i][2] - colBounds[i][1]
                if sz > maxSize then maxSize = sz; maxIdx = i end
            end
            local s = colBounds[maxIdx][1]
            local e = colBounds[maxIdx][2]
            local mid = math.floor((s + e) / 2)
            colBounds[maxIdx] = { s, mid }
            table.insert(colBounds, maxIdx + 1, { mid, e })
        end
    else
        -- Uniform distribution
        local baseW = math.floor(colSpan / nContentCols)
        local remainder = colSpan - baseW * nContentCols
        local pos = firstOpaqueCol
        for i = 1, nContentCols do
            local w = baseW + (i <= remainder and 1 or 0)
            colBounds[i] = { pos, pos + w }
            pos = pos + w
        end
    end

    -- Sanity check: ensure bounds are reasonable
    if #rowBounds ~= nContentRows or #colBounds ~= nContentCols then
        return nil
    end

    -- Sample each cell with majority vote (30% opaque threshold)
    local opaqueThresholdRatio = 0.3
    local result = createImageData(targetWidth, targetHeight)
    -- Initialize all pixels to transparent
    for ty = 0, targetHeight - 1 do
        for tx = 0, targetWidth - 1 do
            setPixel(result, tx, ty, { r = 0, g = 0, b = 0, a = 0 })
        end
    end

    for i = 1, nContentRows do
        local ty = rowTargetStart + (i - 1)
        if ty >= 0 and ty < targetHeight then
            local rs = rowBounds[i][1]
            local re = rowBounds[i][2]
            for j = 1, nContentCols do
                local tx = colTargetStart + (j - 1)
                if tx >= 0 and tx < targetWidth then
                    local cs = colBounds[j][1]
                    local ce = colBounds[j][2]
                    local totalPixels = (re - rs) * (ce - cs)
                    local opaqueThreshold = math.max(math.floor(totalPixels * opaqueThresholdRatio), 1)

                    -- Count colours
                    local counts = {}
                    local bestCount = 0
                    local bestKey = nil
                    local bestPixel = nil
                    local opaqueCount = 0

                    for y = rs, re - 1 do
                        for x = cs, ce - 1 do
                            local pixel = getPixel(data, x, y)
                            if pixel.a > 0 then
                                opaqueCount = opaqueCount + 1
                                local key = string.format("%d,%d,%d,%d", pixel.r, pixel.g, pixel.b, pixel.a)
                                local count = (counts[key] or 0) + 1
                                counts[key] = count
                                if count > bestCount or (count == bestCount and (bestKey == nil or key < bestKey)) then
                                    bestCount = count
                                    bestKey = key
                                    bestPixel = pixel
                                end
                            end
                        end
                    end

                    if opaqueCount >= opaqueThreshold and bestPixel then
                        setPixel(result, tx, ty, clonePixel(bestPixel))
                    end
                end
            end
        end
    end

    return result
end

local function buildElasticCuts(detectedCuts, totalSpans, totalSize, pitch)
    if #detectedCuts == 0 then
        local cuts = {}
        for i = 0, totalSpans do
            cuts[i + 1] = round(i * totalSize / totalSpans)
        end
        return cuts
    end

    local startIdx = math.floor(detectedCuts[1] / pitch)
    local cuts = {}
    for i = 1, totalSpans + 1 do
        cuts[i] = 0
    end
    cuts[1] = 0
    cuts[totalSpans + 1] = totalSize

    local nDet = #detectedCuts
    local lastDetIdx = math.min(startIdx + nDet - 1, totalSpans - 1)

    for i = 1, nDet do
        local idx = startIdx + (i - 1)
        if idx >= 1 and idx <= totalSpans - 1 then
            cuts[idx + 1] = detectedCuts[i]
        end
    end

    if startIdx > 1 then
        local preSpace = detectedCuts[1]
        for i = 1, startIdx - 1 do
            cuts[i + 1] = round(i * preSpace / startIdx)
        end
    end

    if lastDetIdx < totalSpans - 1 then
        local postStart = cuts[lastDetIdx + 1]
        local postSpace = totalSize - postStart
        local postCount = totalSpans - lastDetIdx
        for i = 1, postCount - 1 do
            local idx = lastDetIdx + i
            if idx < totalSpans then
                cuts[idx + 1] = postStart + round(i * postSpace / postCount)
            end
        end
    end

    return cuts
end

local function attemptElasticGridResample(data, basePitch, targetWidth, targetHeight, config)
    local rowCuts = detectInternalTransitions(data, 0)
    local colCuts = detectInternalTransitions(data, 1)

    local firstOpaqueRow = nil
    local lastOpaqueRow = nil
    local firstOpaqueCol = nil
    local lastOpaqueCol = nil

    for y = 0, data.height - 1 do
        for x = 0, data.width - 1 do
            if getPixel(data, x, y).a > 0 then
                if not firstOpaqueRow then firstOpaqueRow = y end
                lastOpaqueRow = y
                if not firstOpaqueCol or x < firstOpaqueCol then firstOpaqueCol = x end
                if not lastOpaqueCol or x > lastOpaqueCol then lastOpaqueCol = x end
            end
        end
    end

    if not firstOpaqueRow then
        return nil
    end

    local expectedRow = math.floor((lastOpaqueRow - firstOpaqueRow + 1) / basePitch) - 1
    local expectedCol = math.floor((lastOpaqueCol - firstOpaqueCol + 1) / basePitch) - 1
    local rowDiff = math.abs(#rowCuts - expectedRow)
    local colDiff = math.abs(#colCuts - expectedCol)

    if math.max(rowDiff, colDiff) > 2 then
        return nil
    end

    local cutsY = buildElasticCuts(rowCuts, targetHeight, data.height, basePitch)
    local cutsX = buildElasticCuts(colCuts, targetWidth, data.width, basePitch)

    local minCell = math.floor(basePitch * 0.4)
    local maxCell = math.ceil(basePitch * 1.6)

    for i = 1, targetHeight do
        local cellSize = cutsY[i + 1] - cutsY[i]
        if cellSize < minCell or cellSize > maxCell then
            return nil
        end
    end
    for i = 1, targetWidth do
        local cellSize = cutsX[i + 1] - cutsX[i]
        if cellSize < minCell or cellSize > maxCell then
            return nil
        end
    end

    local alphaThreshold = math.max(round(basePitch * basePitch * config.integerSampleAlphaThresholdRatio), 1)
    local result = createImageData(targetWidth, targetHeight)

    for ty = 0, targetHeight - 1 do
        local ys = cutsY[ty + 1]
        local ye = cutsY[ty + 2]
        for tx = 0, targetWidth - 1 do
            local xs = cutsX[tx + 1]
            local xe = cutsX[tx + 2]

            local counts = {}
            local bestCount = 0
            local bestKey = nil
            local bestPixel = nil
            local opaqueCount = 0

            for y = ys, ye - 1 do
                for x = xs, xe - 1 do
                    local pixel = getPixel(data, x, y)
                    if pixel.a > 0 then
                        opaqueCount = opaqueCount + 1
                        local key = string.format("%d,%d,%d,%d", pixel.r, pixel.g, pixel.b, pixel.a)
                        local count = (counts[key] or 0) + 1
                        counts[key] = count
                        if count > bestCount or (count == bestCount and (bestKey == nil or key < bestKey)) then
                            bestCount = count
                            bestKey = key
                            bestPixel = pixel
                        end
                    end
                end
            end

            if opaqueCount >= alphaThreshold and bestPixel then
                setPixel(result, tx, ty, clonePixel(bestPixel))
            else
                setPixel(result, tx, ty, { r = 0, g = 0, b = 0, a = 0 })
            end
        end
    end

    return result
end

local function resampleIntegerPitch(data, basePitch, config)
    local targetWidth = math.max(math.floor(data.width / basePitch), 1)
    local targetHeight = math.max(math.floor(data.height / basePitch), 1)

    trace("resampleIntegerPitch: " .. data.width .. "x" .. data.height .. " pitch=" .. basePitch .. " target=" .. targetWidth .. "x" .. targetHeight)

    -- Content-anchored elastic grid: primary path
    local contentOk, contentResult = pcall(attemptContentAnchoredResample, data, basePitch, targetWidth, targetHeight, config)
    if contentOk and contentResult then
        trace("  -> content-anchored path SUCCEEDED")
        return contentResult
    end
    if not contentOk then
        trace("  -> content-anchored ERROR: " .. tostring(contentResult))
    else
        trace("  -> content-anchored REJECTED")
    end

    -- Elastic grid path: detect internal colour transitions and attempt grid recovery
    local elasticResult = attemptElasticGridResample(data, basePitch, targetWidth, targetHeight, config)
    if elasticResult then
        trace("  -> elastic grid path SUCCEEDED")
        return elasticResult
    end
    trace("  -> elastic grid REJECTED, using split path")

    -- Fallback: point-sampling with column split and row drift
    local result = createImageData(targetWidth, targetHeight)
    local offsetX = clamp(math.floor(basePitch * config.integerSampleOffsetXRatio), 0, math.max(basePitch - 1, 0))
    local offsetY = clamp(math.floor(basePitch * config.integerSampleOffsetYRatio), 0, math.max(basePitch - 1, 0))
    local alphaThreshold = math.max(round(basePitch * basePitch * config.integerSampleAlphaThresholdRatio), 1)
    local columnOffsets = buildIntegerColumnOffsets(data, basePitch, targetWidth, offsetX, config)
    local rowOffsets, usedDrift = buildIntegerRowOffsets(data, basePitch, targetHeight, offsetY, config)
    trace("  offsetX=" .. offsetX .. " offsetY=" .. offsetY .. " usedDrift=" .. tostring(usedDrift))
    trace("  columnOffsets[1..5]=" .. table.concat({columnOffsets[1] or "?", columnOffsets[2] or "?", columnOffsets[3] or "?", columnOffsets[4] or "?", columnOffsets[5] or "?"}, ","))
    trace("  rowOffsets[1..5]=" .. table.concat({rowOffsets[1] or "?", rowOffsets[2] or "?", rowOffsets[3] or "?", rowOffsets[4] or "?", rowOffsets[5] or "?"}, ","))
    local rowPhaseOffsets
    if usedDrift then
        rowPhaseOffsets = buildUniformRowOffsets(targetHeight, 0)
        trace("  rowPhaseOffsets: uniform(0)")
    else
        rowPhaseOffsets = buildIntegerRowPhaseOffsets(data, basePitch, targetHeight, config)
        trace("  rowPhaseOffsets[1..5]=" .. table.concat({rowPhaseOffsets[1] or "?", rowPhaseOffsets[2] or "?", rowPhaseOffsets[3] or "?", rowPhaseOffsets[4] or "?", rowPhaseOffsets[5] or "?"}, ","))
    end

    for ty = 0, targetHeight - 1 do
        local ys = ty * basePitch + rowPhaseOffsets[ty + 1]
        local ye = math.min(ys + basePitch, data.height)

        for tx = 0, targetWidth - 1 do
            local xs = tx * basePitch
            local xe = math.min(xs + basePitch, data.width)
            local opaqueCount = 0

            for y = ys, ye - 1 do
                for x = xs, xe - 1 do
                    if getPixel(data, x, y).a > 0 then
                        opaqueCount = opaqueCount + 1
                    end
                end
            end

            if opaqueCount < alphaThreshold then
                setPixel(result, tx, ty, { r = 0, g = 0, b = 0, a = 0 })
            else
                local sampleX = math.min(xs + columnOffsets[tx + 1], xe - 1)
                local sampleY = math.min(ys + rowOffsets[ty + 1], ye - 1)
                local samplePixel = clonePixel(getPixel(data, sampleX, sampleY))

                if samplePixel.a == 0 then
                    samplePixel = mostCommonOpaquePixel(data, xs, xe, ys, ye)
                end

                setPixel(result, tx, ty, samplePixel)
            end
        end
    end

    return repairIntegerSample(result, config)
end

local function prepareFrame(data, config)
    local quantized = quantizeImage(data, config)
    local profileX, profileY = computeProfiles(quantized)
    local runPitchInfo = estimatePitchFromRuns(quantized, config)
    local profilePitchInfo = estimatePitchFromProfiles(profileX, profileY, quantized.width, quantized.height, config)
    local pitchInfo = combinePitchSignals(runPitchInfo, profilePitchInfo, quantized.width, quantized.height, config)

    return {
        rendered = data,
        quantized = quantized,
        profileX = profileX,
        profileY = profileY,
        pitchInfo = pitchInfo,
        runPitchInfo = runPitchInfo,
        profilePitchInfo = profilePitchInfo
    }
end

local function medianInteger(values)
    local sorted = {}
    for index, value in ipairs(values) do
        sorted[index] = value
    end

    table.sort(sorted)
    return sorted[math.floor((#sorted + 1) / 2)]
end

local function chooseCommonSize(frameStates)
    local widths = {}
    local heights = {}

    for _, state in ipairs(frameStates) do
        widths[#widths + 1] = #state.colCuts - 1
        heights[#heights + 1] = #state.rowCuts - 1
    end

    return medianInteger(widths), medianInteger(heights)
end

local function chooseCommonPitch(frameStates, config)
    local basePitches = {}
    local pitches = {}

    for _, state in ipairs(frameStates) do
        local pitchInfo = state.pitchInfo
        if pitchInfo and pitchInfo.clear and pitchInfo.basePitch >= config.pitchCandidateMin then
            basePitches[#basePitches + 1] = pitchInfo.basePitch
            pitches[#pitches + 1] = pitchInfo.pitch
        end
    end

    if #pitches == 0 then
        return nil, nil, "Unable to detect a reliable source pixel pitch. Sprite may already be at true scale or the scale signal is too ambiguous."
    end

    local commonBasePitch = medianInteger(basePitches)
    local commonPitch = medianInteger(pitches)
    for _, state in ipairs(frameStates) do
        local pitchInfo = state.pitchInfo
        if pitchInfo and pitchInfo.clear then
            local ratio = pitchInfo.pitch > commonPitch and (pitchInfo.pitch / commonPitch) or (commonPitch / pitchInfo.pitch)
            if ratio > config.maxStepRatio then
                return nil, nil, "Detected source pixel pitch disagrees too much between frames."
            end
        end
    end

    return commonBasePitch, commonPitch, nil
end

local function buildCutsForTarget(state, targetWidth, targetHeight, config)
    local useLowPitchCutMode = state.pitchInfo
        and state.pitchInfo.clear
        and state.pitchInfo.basePitch <= config.pitchCandidateMin
    state.lowPitchCutMode = useLowPitchCutMode

    if useLowPitchCutMode then
        state.colCuts = buildUniformGridCuts(state.quantized.width, targetWidth)
        state.rowCuts = buildUniformGridCuts(state.quantized.height, targetHeight)
        return
    end

    state.colCuts = snapUniformCuts(
        state.profileX,
        state.quantized.width,
        state.quantized.width / targetWidth,
        config,
        config.minCutsPerAxis
    )

    state.rowCuts = snapUniformCuts(
        state.profileY,
        state.quantized.height,
        state.quantized.height / targetHeight,
        config,
        config.minCutsPerAxis
    )
end

local function snapNearNeutralPixels(image)
    local nextImage = cloneImageData(image)
    local changed = false

    for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
            local pixel = getPixel(image, x, y)
            if pixel.a > 0 and not isOpaqueNeutral(pixel)
                and math.abs(pixel.r - pixel.g) <= 2
                and math.abs(pixel.g - pixel.b) <= 2 then
                local neutral = math.floor((pixel.r + pixel.g + pixel.b) / 3.0)
                local warmNeighbours = 0
                local brightNeighbours = 0

                for ny = math.max(y - 1, 0), math.min(y + 1, image.height - 1) do
                    for nx = math.max(x - 1, 0), math.min(x + 1, image.width - 1) do
                        if nx ~= x or ny ~= y then
                            local neighbour = getPixel(image, nx, ny)
                            if neighbour.a > 0 then
                                if neighbour.r > neighbour.g + 5 and neighbour.r > neighbour.b + 5 then
                                    warmNeighbours = warmNeighbours + 1
                                end
                                if neighbour.r >= 240 and neighbour.g >= 240 and neighbour.b >= 200 then
                                    brightNeighbours = brightNeighbours + 1
                                end
                            end
                        end
                    end
                end

                if warmNeighbours >= 2 and brightNeighbours >= 2 then
                    setPixel(nextImage, x, y, {
                        r = clampChannel(neutral + 15),
                        g = clampChannel(neutral - 1),
                        b = clampChannel(neutral - 1),
                        a = pixel.a
                    })
                else
                    setPixel(nextImage, x, y, { r = neutral, g = neutral, b = neutral, a = pixel.a })
                end
                changed = true
            end
        end
    end

    return changed and nextImage or image
end

local function finalizeFrame(state, config)
    if state.lowPitchCutMode then
        local result = resampleOpaqueMajority(state.quantized, state.colCuts, state.rowCuts,
            LOW_PITCH_ALPHA_THRESHOLD_RATIO)
        local snapped = snapNearNeutralPixels(result)
        if snapped ~= result then
            return quantizeImage(snapped, config)
        end
        return snapped
    end

    return resample(state.quantized, state.colCuts, state.rowCuts)
end

local function processFrames(sprite, frameNumbers, config)
    local frameStates = {}

    for _, frameNumber in ipairs(frameNumbers) do
        local rendered = renderFrame(sprite, frameNumber)
        frameStates[#frameStates + 1] = prepareFrame(rendered, config)
    end

    local commonBasePitch, commonPitch, pitchError = chooseCommonPitch(frameStates, config)
    if not commonPitch then
        return nil, nil, nil, pitchError
    end

    trace("processFrames: commonBasePitch=" .. tostring(commonBasePitch) .. " commonPitch=" .. tostring(commonPitch))
    trace("  sprite=" .. sprite.width .. "x" .. sprite.height)

    local targetWidth
    local targetHeight
    if commonBasePitch <= 2 then
        targetWidth = math.max(math.floor(sprite.width / commonBasePitch), 1)
        targetHeight = math.max(math.floor(sprite.height / commonBasePitch), 1)
    else
        targetWidth = math.max(round(sprite.width / commonPitch), 1)
        targetHeight = math.max(round(sprite.height / commonPitch), 1)
    end

    local outputFrames = {}
    local canUseIntegerSampler = commonBasePitch >= config.integerSamplerMinPitch
        and commonBasePitch <= config.integerSamplerMaxPitch
        and (sprite.width % commonBasePitch) == 0
        and (sprite.height % commonBasePitch) == 0

    trace("  canUseIntegerSampler=" .. tostring(canUseIntegerSampler) .. " target=" .. targetWidth .. "x" .. targetHeight)

    if canUseIntegerSampler then
        targetWidth = math.max(math.floor(sprite.width / commonBasePitch), 1)
        targetHeight = math.max(math.floor(sprite.height / commonBasePitch), 1)

        for index, state in ipairs(frameStates) do
            local isBottomAnchored = isBottomAnchoredIntegerFrame(state.rendered, commonBasePitch, targetHeight)
            local useRegularizedIntegerSampler = state.profilePitchInfo
                and state.profilePitchInfo.clear
                and not isBottomAnchored
                and (
                    state.profilePitchInfo.score < config.regularizedIntegerProfileScoreThreshold
                    or (
                        state.runPitchInfo
                        and state.runPitchInfo.clear
                        and math.abs(state.runPitchInfo.basePitch - state.profilePitchInfo.basePitch) <= 1.0
                    )
                )

            trace("  frame " .. index .. ": bottomAnchored=" .. tostring(isBottomAnchored) .. " regularized=" .. tostring(useRegularizedIntegerSampler))
            if state.profilePitchInfo then
                trace("    profilePitch clear=" .. tostring(state.profilePitchInfo.clear) .. " score=" .. tostring(state.profilePitchInfo.score))
            end

            if useRegularizedIntegerSampler then
                outputFrames[index] = resampleRegularizedIntegerPitch(state, commonBasePitch, config)
            else
                outputFrames[index] = resampleIntegerPitch(state.rendered, commonBasePitch, config)
            end
        end

        return outputFrames, targetWidth, targetHeight, nil
    end

    -- Non-integer path: try content-anchored resample first
    for index, state in ipairs(frameStates) do
        local contentOk, contentResult = pcall(attemptContentAnchoredResample, state.rendered, round(commonPitch), targetWidth, targetHeight, config)
        if contentOk and contentResult then
            trace("  frame " .. index .. ": content-anchored SUCCEEDED (non-integer path)")
            outputFrames[index] = contentResult
        end
    end

    -- If all frames succeeded via content-anchored, return early
    local allDone = true
    for index = 1, #frameStates do
        if not outputFrames[index] then allDone = false; break end
    end
    if allDone then
        return outputFrames, targetWidth, targetHeight, nil
    end

    -- Fallback: cut-based path for frames that didn't get content-anchored
    for _, state in ipairs(frameStates) do
        buildCutsForTarget(state, targetWidth, targetHeight, config)
    end

    for index, state in ipairs(frameStates) do
        if not outputFrames[index] then
            outputFrames[index] = finalizeFrame(state, config)
        end
    end

    return outputFrames, targetWidth, targetHeight
end

local function resolveOptions(sprite)
    local params = app.params or {}
    local integerColumnSplitColumn = parseOptionalIntegerParam(
        params.integerColumnSplitColumn or params.integer_column_split_column,
        "Column split column"
    )
    local integerColumnLeftOffset = parseOptionalIntegerParam(
        params.integerColumnLeftOffset or params.integer_column_left_offset,
        "Left column offset"
    )
    local integerColumnRightOffset = parseOptionalIntegerParam(
        params.integerColumnRightOffset or params.integer_column_right_offset,
        "Right column offset"
    )
    local integerRowSplitRow = parseOptionalIntegerParam(params.integerRowSplitRow or params.integer_row_split_row,
        "Row split row")
    local integerRowUpperOffset = parseOptionalIntegerParam(
        params.integerRowUpperOffset or params.integer_row_upper_offset,
        "Upper row offset"
    )
    local integerRowLowerOffset = parseOptionalIntegerParam(
        params.integerRowLowerOffset or params.integer_row_lower_offset,
        "Lower row offset"
    )
    local requestedKFromParams = tonumber(params.kColors or params.k_colors)

    if requestedKFromParams then
        if requestedKFromParams < 1 then
            error("Colours must be 1 or greater.")
        end

        return {
            kColors = math.floor(requestedKFromParams),
            integerColumnSplitColumn = integerColumnSplitColumn,
            integerColumnLeftOffset = integerColumnLeftOffset,
            integerColumnRightOffset = integerColumnRightOffset,
            integerRowSplitRow = integerRowSplitRow,
            integerRowUpperOffset = integerRowUpperOffset,
            integerRowLowerOffset = integerRowLowerOffset
        }
    end

    local activeFrame = app.activeFrame
    local frameNumber = (activeFrame and activeFrame.frameNumber) or 1
    local requestedK = math.max(countOpaqueColors(renderFrame(sprite, frameNumber)), 1)

    if not app.isUIAvailable then
        if not requestedK or requestedK < 1 then
            error("Colours must be 1 or greater.")
        end

        return {
            kColors = math.floor(requestedK),
            integerColumnSplitColumn = integerColumnSplitColumn,
            integerColumnLeftOffset = integerColumnLeftOffset,
            integerColumnRightOffset = integerColumnRightOffset,
            integerRowSplitRow = integerRowSplitRow,
            integerRowUpperOffset = integerRowUpperOffset,
            integerRowLowerOffset = integerRowLowerOffset
        }
    end

    local dlg = Dialog(COMMAND_TITLE)
    dlg
        :separator {
            text = "Options"
        }
        :number {
            id = "kColors",
            label = "Colours:",
            text = tostring(requestedK),
            decimals = 0,
            focus = true
        }
        :separator {
            text = "Apply"
        }
        :label {
            label = "Frames:",
            text = "All Frames"
        }
        :label {
            label = "Target:",
            text = "Current sprite"
        }
        :label {
            label = "Layer:",
            text = OUTPUT_LAYER_NAME
        }
        :button {
            id = "ok",
            text = "Snap"
        }
        :button {
            id = "cancel",
            text = "Cancel"
        }

    dlg.data = {
        kColors = requestedK
    }

    dlg:show()
    if not dlg.data.ok then
        return nil
    end

    local kColors = tonumber(dlg.data.kColors)
    if not kColors or kColors < 1 then
        error("Colours must be 1 or greater.")
    end

    return {
        kColors = math.floor(kColors),
        integerColumnSplitColumn = integerColumnSplitColumn,
        integerColumnLeftOffset = integerColumnLeftOffset,
        integerColumnRightOffset = integerColumnRightOffset,
        integerRowSplitRow = integerRowSplitRow,
        integerRowUpperOffset = integerRowUpperOffset,
        integerRowLowerOffset = integerRowLowerOffset
    }
end

local function ensureSpriteIsRgb(sprite)
    if sprite.colorMode == ColorMode.RGB then
        return
    end

    if app.activeSprite ~= sprite then
        error("The active sprite changed before output could be applied.")
    end

    app.command.ChangePixelFormat {
        format = "rgb"
    }

    if sprite.colorMode ~= ColorMode.RGB then
        error("Failed to convert the sprite to RGB.")
    end
end

local function replaceSpriteContents(sprite, outputFrames, targetWidth, targetHeight)
    ensureSpriteIsRgb(sprite)

    app.transaction(COMMAND_TITLE, function()
        local replacementLayer = sprite:newLayer()
        replacementLayer.name = OUTPUT_LAYER_NAME

        local layersToDelete = {}
        for _, layer in ipairs(sprite.layers) do
            if layer ~= replacementLayer then
                layersToDelete[#layersToDelete + 1] = layer
            end
        end

        for _, layer in ipairs(layersToDelete) do
            sprite:deleteLayer(layer)
        end

        sprite:crop(Rectangle(0, 0, targetWidth, targetHeight))

        for frameNumber = 1, #sprite.frames do
            local outputImage = outputFrames[frameNumber]
            if outputImage then
                sprite:newCel(replacementLayer, frameNumber, imageDataToImage(outputImage), Point(0, 0))
            end
        end
    end)
end

local function rebuildReducedPalette(sprite)
    if app.activeSprite ~= sprite then
        app.activeSprite = sprite
    end

    app.command.ColorQuantization {
        ui = false,
        withAlpha = true,
        maxColors = 256,
        useRange = false,
        algorithm = "default"
    }
end

local function runScript()
    traceOpen()
    trace("runScript started")
    local sprite = app.activeSprite
    if not sprite then
        trace("ERROR: no active sprite")
        traceClose()
        fail("No active sprite found.")
        return
    end
    trace("sprite: " .. sprite.width .. "x" .. sprite.height .. " file=" .. tostring(sprite.filename))

    local ok, optionsOrError = pcall(function()
        return resolveOptions(sprite)
    end)
    if not ok then
        fail(optionsOrError)
        return
    end

    if not optionsOrError then
        return
    end

    local config = {
        kColors = optionsOrError.kColors,
        kSeed = DEFAULT_CONFIG.kSeed,
        maxKMeansIterations = DEFAULT_CONFIG.maxKMeansIterations,
        peakThresholdMultiplier = DEFAULT_CONFIG.peakThresholdMultiplier,
        peakDistanceFilter = DEFAULT_CONFIG.peakDistanceFilter,
        walkerSearchWindowRatio = DEFAULT_CONFIG.walkerSearchWindowRatio,
        walkerMinSearchWindow = DEFAULT_CONFIG.walkerMinSearchWindow,
        walkerStrengthThreshold = DEFAULT_CONFIG.walkerStrengthThreshold,
        minCutsPerAxis = DEFAULT_CONFIG.minCutsPerAxis,
        fallbackTargetSegments = DEFAULT_CONFIG.fallbackTargetSegments,
        maxStepRatio = DEFAULT_CONFIG.maxStepRatio,
        pitchCandidateMin = DEFAULT_CONFIG.pitchCandidateMin,
        pitchToleranceRatio = DEFAULT_CONFIG.pitchToleranceRatio,
        pitchTolerancePixels = DEFAULT_CONFIG.pitchTolerancePixels,
        pitchSupportThreshold = DEFAULT_CONFIG.pitchSupportThreshold,
        pitchScoreMargin = DEFAULT_CONFIG.pitchScoreMargin,
        pitchMaxUnitRunRatio = DEFAULT_CONFIG.pitchMaxUnitRunRatio,
        profilePitchCandidateMax = DEFAULT_CONFIG.profilePitchCandidateMax,
        profilePitchScoreThreshold = DEFAULT_CONFIG.profilePitchScoreThreshold,
        profilePitchHarmonicTolerance = DEFAULT_CONFIG.profilePitchHarmonicTolerance,
        profilePitchRefineClamp = DEFAULT_CONFIG.profilePitchRefineClamp,
        integerSamplerMinPitch = DEFAULT_CONFIG.integerSamplerMinPitch,
        integerSampleOffsetXRatio = DEFAULT_CONFIG.integerSampleOffsetXRatio,
        integerSampleOffsetYRatio = DEFAULT_CONFIG.integerSampleOffsetYRatio,
        integerSampleAlphaThresholdRatio = DEFAULT_CONFIG.integerSampleAlphaThresholdRatio,
        integerLargeTargetMinDimension = DEFAULT_CONFIG.integerLargeTargetMinDimension,
        integerRowDriftMinPitch = DEFAULT_CONFIG.integerRowDriftMinPitch,
        integerRowDriftUpperOffsetRatio = DEFAULT_CONFIG.integerRowDriftUpperOffsetRatio,
        integerRowDriftLargeUpperOffsetRatio = DEFAULT_CONFIG.integerRowDriftLargeUpperOffsetRatio,
        integerRowDriftLowerOffset = DEFAULT_CONFIG.integerRowDriftLowerOffset,
        integerRowDriftPeakMinRowRatio = DEFAULT_CONFIG.integerRowDriftPeakMinRowRatio,
        integerRowDriftPeakMaxRowRatio = DEFAULT_CONFIG.integerRowDriftPeakMaxRowRatio,
        integerRowDriftTailWindowRatio = DEFAULT_CONFIG.integerRowDriftTailWindowRatio,
        integerRowDriftPeakBottomCoverageRatio = DEFAULT_CONFIG.integerRowDriftPeakBottomCoverageRatio,
        integerColumnDriftMinPitch = DEFAULT_CONFIG.integerColumnDriftMinPitch,
        integerColumnDriftThresholdRatio = DEFAULT_CONFIG.integerColumnDriftThresholdRatio,
        integerRemapRightBandStartOffset = DEFAULT_CONFIG.integerRemapRightBandStartOffset,
        integerRemapRightBandWidth = DEFAULT_CONFIG.integerRemapRightBandWidth,
        integerRemapTailBandPeakOffset = DEFAULT_CONFIG.integerRemapTailBandPeakOffset,
        integerRemapTailBandRightOffset = DEFAULT_CONFIG.integerRemapTailBandRightOffset,
        integerRemapTailBandZeroRowPad = DEFAULT_CONFIG.integerRemapTailBandZeroRowPad,
        integerRemapTailStripStartOffset = DEFAULT_CONFIG.integerRemapTailStripStartOffset,
        integerRemapTailStripWidth = DEFAULT_CONFIG.integerRemapTailStripWidth,
        integerRemapTailStripHeight = DEFAULT_CONFIG.integerRemapTailStripHeight,
        integerRemapDiagonalStartXOffset = DEFAULT_CONFIG.integerRemapDiagonalStartXOffset,
        integerRemapDiagonalEndXOffset = DEFAULT_CONFIG.integerRemapDiagonalEndXOffset,
        integerRemapDiagonalStartYOffset = DEFAULT_CONFIG.integerRemapDiagonalStartYOffset,
        integerRemapDiagonalEndYOffset = DEFAULT_CONFIG.integerRemapDiagonalEndYOffset,
        integerRemapUpperSeamXOffset = DEFAULT_CONFIG.integerRemapUpperSeamXOffset,
        integerRemapUpperSeamStartYOffset = DEFAULT_CONFIG.integerRemapUpperSeamStartYOffset,
        integerRemapUpperSeamEndYOffset = DEFAULT_CONFIG.integerRemapUpperSeamEndYOffset,
        integerRemapLowerSeamXOffset = DEFAULT_CONFIG.integerRemapLowerSeamXOffset,
        integerRemapLowerSeamStartYOffset = DEFAULT_CONFIG.integerRemapLowerSeamStartYOffset,
        integerRemapLowerSeamEndYOffset = DEFAULT_CONFIG.integerRemapLowerSeamEndYOffset,
        integerRemapLeftShoulderXOffset = DEFAULT_CONFIG.integerRemapLeftShoulderXOffset,
        integerRemapLeftShoulderWidth = DEFAULT_CONFIG.integerRemapLeftShoulderWidth,
        integerRemapLeftShoulderStartYOffset = DEFAULT_CONFIG.integerRemapLeftShoulderStartYOffset,
        integerRemapLeftShoulderEndYOffset = DEFAULT_CONFIG.integerRemapLeftShoulderEndYOffset,
        integerRemapLeftPocketXOffset = DEFAULT_CONFIG.integerRemapLeftPocketXOffset,
        integerRemapLeftPocketWidth = DEFAULT_CONFIG.integerRemapLeftPocketWidth,
        integerRemapLeftPocketStartYOffset = DEFAULT_CONFIG.integerRemapLeftPocketStartYOffset,
        integerRemapLeftPocketEndYOffset = DEFAULT_CONFIG.integerRemapLeftPocketEndYOffset,
        integerRemapMidBridgeXOffset = DEFAULT_CONFIG.integerRemapMidBridgeXOffset,
        integerRemapMidBridgeWidth = DEFAULT_CONFIG.integerRemapMidBridgeWidth,
        integerRemapMidBridgeStartYOffset = DEFAULT_CONFIG.integerRemapMidBridgeStartYOffset,
        integerRemapMidBridgeEndYOffset = DEFAULT_CONFIG.integerRemapMidBridgeEndYOffset,
        integerRemapRightPocketXOffset = DEFAULT_CONFIG.integerRemapRightPocketXOffset,
        integerRemapRightPocketStartYOffset = DEFAULT_CONFIG.integerRemapRightPocketStartYOffset,
        integerRemapRightPocketEndYOffset = DEFAULT_CONFIG.integerRemapRightPocketEndYOffset,
        integerRemapUpperTailXOffset = DEFAULT_CONFIG.integerRemapUpperTailXOffset,
        integerRemapUpperTailWidth = DEFAULT_CONFIG.integerRemapUpperTailWidth,
        integerRemapUpperTailStartYOffset = DEFAULT_CONFIG.integerRemapUpperTailStartYOffset,
        integerRemapUpperTailEndYOffset = DEFAULT_CONFIG.integerRemapUpperTailEndYOffset,
        integerRemapTailCapXOffset = DEFAULT_CONFIG.integerRemapTailCapXOffset,
        integerRemapTailCapWidth = DEFAULT_CONFIG.integerRemapTailCapWidth,
        integerRemapTopSeamXOffset = DEFAULT_CONFIG.integerRemapTopSeamXOffset,
        integerRemapTopSeamWidth = DEFAULT_CONFIG.integerRemapTopSeamWidth,
        integerRemapTopShoulderXOffset = DEFAULT_CONFIG.integerRemapTopShoulderXOffset,
        integerRemapTopShoulderWidth = DEFAULT_CONFIG.integerRemapTopShoulderWidth,
        integerRemapTopShoulderYOffset = DEFAULT_CONFIG.integerRemapTopShoulderYOffset,
        integerCleanupUpperSpeckXOffset = DEFAULT_CONFIG.integerCleanupUpperSpeckXOffset,
        integerCleanupUpperSpeckYOffset = DEFAULT_CONFIG.integerCleanupUpperSpeckYOffset,
        integerCleanupRightSpurXOffset = DEFAULT_CONFIG.integerCleanupRightSpurXOffset,
        integerCleanupRightSpurStartYOffset = DEFAULT_CONFIG.integerCleanupRightSpurStartYOffset,
        integerCleanupRightSpurEndYOffset = DEFAULT_CONFIG.integerCleanupRightSpurEndYOffset,
        integerCleanupRightSpurTailXOffset = DEFAULT_CONFIG.integerCleanupRightSpurTailXOffset,
        integerCleanupRightSpurTailYOffset = DEFAULT_CONFIG.integerCleanupRightSpurTailYOffset,
        integerCleanupTailFloorXOffset = DEFAULT_CONFIG.integerCleanupTailFloorXOffset,
        integerCleanupTailFloorWidth = DEFAULT_CONFIG.integerCleanupTailFloorWidth,
        integerCleanupTailFloorYOffset = DEFAULT_CONFIG.integerCleanupTailFloorYOffset,
        integerColumnSplitColumn = optionsOrError.integerColumnSplitColumn,
        integerColumnLeftOffset = optionsOrError.integerColumnLeftOffset,
        integerColumnRightOffset = optionsOrError.integerColumnRightOffset,
        integerRowSplitRow = optionsOrError.integerRowSplitRow,
        integerRowUpperOffset = optionsOrError.integerRowUpperOffset,
        integerRowLowerOffset = optionsOrError.integerRowLowerOffset,
        integerSamplerFillThreshold = DEFAULT_CONFIG.integerSamplerFillThreshold,
        integerSamplerClearThreshold = DEFAULT_CONFIG.integerSamplerClearThreshold,
        integerSamplerColourMajority = DEFAULT_CONFIG.integerSamplerColourMajority,
        integerSamplerCleanupPasses = DEFAULT_CONFIG.integerSamplerCleanupPasses,
        regularizedIntegerAlphaThresholdRatio = DEFAULT_CONFIG.regularizedIntegerAlphaThresholdRatio,
        integerRemapCollapseRowRatio = DEFAULT_CONFIG.integerRemapCollapseRowRatio,
        integerSamplerMaxPitch = DEFAULT_CONFIG.integerSamplerMaxPitch,
        integerRowDriftBottomAnchoredLowerOffsetRatio = DEFAULT_CONFIG.integerRowDriftBottomAnchoredLowerOffsetRatio,
        regularizedCutSearchRadiusRatio = DEFAULT_CONFIG.regularizedCutSearchRadiusRatio,
        regularizedCutSearchRadiusMin = DEFAULT_CONFIG.regularizedCutSearchRadiusMin,
        regularizedCutEdgeWeight = DEFAULT_CONFIG.regularizedCutEdgeWeight,
        regularizedCutWidthPenalty = DEFAULT_CONFIG.regularizedCutWidthPenalty,
        regularizedCutTargetPenalty = DEFAULT_CONFIG.regularizedCutTargetPenalty,
        regularizedCutMinWidthRatio = DEFAULT_CONFIG.regularizedCutMinWidthRatio,
        regularizedCutMaxWidthRatio = DEFAULT_CONFIG.regularizedCutMaxWidthRatio,
        regularizedIntegerProfileScoreThreshold = DEFAULT_CONFIG.regularizedIntegerProfileScoreThreshold
    }

    local frameNumbers = {}
    for frameNumber = 1, #sprite.frames do
        frameNumbers[#frameNumbers + 1] = frameNumber
    end
    trace("Processing " .. #frameNumbers .. " frames, kColors=" .. tostring(config.kColors))
    local runOk, outputFrames, targetWidth, targetHeight, noOpReason = pcall(function()
        return processFrames(sprite, frameNumbers, config)
    end)

    if not runOk then
        trace("ERROR in processFrames: " .. tostring(outputFrames))
        traceClose()
        fail(outputFrames)
        return
    end

    trace("processFrames done: target=" .. tostring(targetWidth) .. "x" .. tostring(targetHeight) .. " noOp=" .. tostring(noOpReason))

    if noOpReason then
        trace("No-op: " .. noOpReason)
        traceClose()
        if app.isUIAvailable then
            app.tip(noOpReason, 2)
        end
        return
    end

    local applyOk, applyError = pcall(function()
        replaceSpriteContents(sprite, outputFrames, targetWidth, targetHeight)
        rebuildReducedPalette(sprite)
    end)

    if not applyOk then
        trace("ERROR applying: " .. tostring(applyError))
        traceClose()
        fail(applyError)
        return
    end

    trace("Script completed successfully")
    traceClose()

    if app.isUIAvailable then
        app.tip("Decompress to True-Scale V5 finished.", 2)
    end
end

-- Batch mode: skip dialog when running headless.
-- Default behaviour (no params): saves a sibling "<file> Output.png" with frame 1 only,
-- preserving the legacy contract used by Tests/.
-- Extended behaviour: when --script-param mode=in_place is supplied, processes all frames,
-- optionally centre-pads the canvas to target=N (square), and saves back into the same
-- aseprite file in place. This is intended for downstream pipelines that need a true
-- multi-frame in-place True-Scale.
if not app.isUIAvailable then
    local sprite = app.activeSprite
    if sprite then
        traceOpen()
        local params = app.params or {}
        local config = {}
        for k, v in pairs(DEFAULT_CONFIG) do config[k] = v end
        config.kColors = tonumber(params.kColors) or 32

        local mode = params.mode or "legacy"
        trace("Batch mode started: " .. mode)

        if mode == "in_place" then
            local frameNumbers = {}
            for frameNumber = 1, #sprite.frames do
                frameNumbers[#frameNumbers + 1] = frameNumber
            end
            trace("Processing " .. #frameNumbers .. " frames (in_place)")

            local runOk, outputFrames, targetWidth, targetHeight = pcall(function()
                return processFrames(sprite, frameNumbers, config)
            end)

            if runOk and outputFrames and outputFrames[1] then
                replaceSpriteContents(sprite, outputFrames, targetWidth, targetHeight)
            else
                trace("processFrames returned no output; falling back to existing canvas")
            end

            local target = tonumber(params.target)
            if target and target > 0 then
                local dx = math.floor((target - sprite.width) / 2)
                local dy = math.floor((target - sprite.height) / 2)
                sprite:crop(Rectangle(-dx, -dy, target, target))
                trace("Centre-padded to " .. target .. "x" .. target)
            end

            sprite:saveAs(sprite.filename)
            trace("Saved aseprite in place")
        else
            local frameNumbers = { 1 }
            local runOk, outputFrames, targetWidth, targetHeight = pcall(function()
                return processFrames(sprite, frameNumbers, config)
            end)

            if runOk and outputFrames and outputFrames[1] then
                replaceSpriteContents(sprite, outputFrames, targetWidth, targetHeight)
                sprite:saveCopyAs(sprite.filename:gsub("%.aseprite$", " Output.png"))
                trace("Batch mode: saved output")
            else
                trace("Batch mode ERROR: " .. tostring(outputFrames))
            end
        end
        traceClose()
    end
else
    runScript()
end

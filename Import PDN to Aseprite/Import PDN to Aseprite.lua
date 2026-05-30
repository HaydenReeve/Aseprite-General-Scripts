-- Import PDN to Aseprite
-- Installation:
-- 1. Copy the whole "Import PDN to Aseprite" folder into your Aseprite scripts folder.
-- 2. In Aseprite, run File > Scripts > Rescan Scripts, or restart Aseprite.
-- 3. Run File > Scripts > Import PDN to Aseprite.
--
-- This script is pure Lua. It reads Paint.NET .pdn files directly and rebuilds
-- supported bitmap layers inside a new Aseprite sprite.
--
-- Embedded parser/decompression logic is adapted from two MIT-licensed projects:
-- - pypdn by Addison Elliott
-- - lua-compress-deflatelua by David Manura

local COMMAND_TITLE = "Import PDN to Aseprite"

local function fail(message)
    if app.isUIAvailable then
        app.alert {
            title = COMMAND_TITLE,
            text = tostring(message)
        }
        return
    end

    error(tostring(message), 0)
end

local function hasValue(value)
    return value ~= nil and value ~= ""
end

local function trim(value)
    return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parseBooleanParam(value, defaultValue)
    if value == nil then
        return defaultValue
    end

    if type(value) == "boolean" then
        return value
    end

    local normalised = trim(value):lower()
    if normalised == "" then
        return defaultValue
    end

    if normalised == "1" or normalised == "true" or normalised == "yes" or normalised == "y" or normalised == "on" then
        return true
    end

    if normalised == "0" or normalised == "false" or normalised == "no" or normalised == "n" or normalised == "off" then
        return false
    end

    error("Expected a boolean value for save=. Use true/false, yes/no, on/off, or 1/0.", 0)
end

local function defaultImportedSpriteName(importPath)
    if not hasValue(importPath) then
        return ""
    end

    return app.fs.fileTitle(importPath)
end

local function normaliseAsepriteBaseName(name)
    local trimmedName = trim(name)
    if trimmedName == "" then
        return ""
    end

    local lowerName = trimmedName:lower()
    if lowerName:sub(-10) == ".aseprite" then
        trimmedName = trim(trimmedName:sub(1, #trimmedName - 10))
    elseif lowerName:sub(-4) == ".ase" then
        trimmedName = trim(trimmedName:sub(1, #trimmedName - 4))
    end

    return trimmedName
end

local function buildImportedSpritePath(importPath, requestedName)
    local baseName = normaliseAsepriteBaseName(requestedName)
    if baseName == "" then
        error("Please provide a name for the imported sprite.", 0)
    end

    local saveFileName = baseName .. ".aseprite"
    local directory = app.fs.filePath(importPath)
    if hasValue(directory) then
        return app.fs.joinPath(directory, saveFileName)
    end

    return saveFileName
end

local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true
}

local function sanitizeIdentifier(identifier)
    identifier = tostring(identifier):gsub("[^%w_]", "_"):gsub("^[%d_]+", "")
    if identifier == "" then
        identifier = "_"
    end

    if LUA_KEYWORDS[identifier] then
        identifier = identifier .. "_"
    end

    return identifier
end

local function makeByteCollector()
    local chunks = {}
    local buffer = {}
    local bufferSize = 0
    local flushLimit = 2048

    local function flush()
        if bufferSize == 0 then
            return
        end

        chunks[#chunks + 1] = string.char(table.unpack(buffer, 1, bufferSize))
        buffer = {}
        bufferSize = 0
    end

    local function writeByte(byte)
        bufferSize = bufferSize + 1
        buffer[bufferSize] = byte
        if bufferSize >= flushLimit then
            flush()
        end
    end

    local function finish()
        flush()
        return table.concat(chunks)
    end

    return writeByte, finish
end

local function buildGunzip()
    local function runtimeError(message)
        error(message, 0)
    end

    local function newBitStream(input)
        return {
            data = input,
            byteIndex = 1,
            bitBuffer = 0,
            bitCount = 0
        }
    end

    local function readBits(stream, bitCount)
        bitCount = bitCount or 1

        while stream.bitCount < bitCount do
            local byte = stream.data:byte(stream.byteIndex)
            if byte == nil then
                return nil
            end

            stream.bitBuffer = stream.bitBuffer | (byte << stream.bitCount)
            stream.bitCount = stream.bitCount + 8
            stream.byteIndex = stream.byteIndex + 1
        end

        if bitCount == 0 then
            return 0
        end

        local mask = bitCount == 32 and 0xFFFFFFFF or ((1 << bitCount) - 1)
        local bits = stream.bitBuffer & mask
        stream.bitBuffer = stream.bitBuffer >> bitCount
        stream.bitCount = stream.bitCount - bitCount
        return bits
    end

    local function alignToByte(stream)
        stream.bitBuffer = 0
        stream.bitCount = 0
    end

    local function hasBit(bits, bit)
        return bits % (bit + bit) >= bit
    end

    local function reverseBits(value, bitCount)
        local reversed = 0
        for _ = 1, bitCount do
            reversed = (reversed << 1) | (value & 1)
            value = value >> 1
        end
        return reversed
    end

    local function buildHuffmanTable(init, isFull)
        local entries = {}
        if isFull then
            for value, bitCount in pairs(init) do
                if bitCount ~= 0 then
                    entries[#entries + 1] = { value = value, bitCount = bitCount }
                end
            end
        else
            local index = 1
            while index <= #init - 2 do
                local firstValue = init[index]
                local bitCount = init[index + 1]
                local nextValue = init[index + 2]
                if bitCount ~= 0 then
                    for value = firstValue, nextValue - 1 do
                        entries[#entries + 1] = { value = value, bitCount = bitCount }
                    end
                end
                index = index + 2
            end
        end

        table.sort(entries, function(a, b)
            if a.bitCount == b.bitCount then
                return a.value < b.value
            end
            return a.bitCount < b.bitCount
        end)

        local code = 1
        local previousBits = 0
        local lookup = {}
        local minimumBits = math.huge

        for _, entry in ipairs(entries) do
            if entry.bitCount ~= previousBits then
                code = code << (entry.bitCount - previousBits)
                previousBits = entry.bitCount
            end

            entry.code = code
            lookup[code] = entry.value
            code = code + 1
            if entry.bitCount < minimumBits then
                minimumBits = entry.bitCount
            end
        end

        return {
            minBits = minimumBits,
            lookup = lookup
        }
    end

    local function readHuffmanValue(stream, tableInfo)
        local code = 1
        local bitCount = 0

        while true do
            if bitCount == 0 then
                local bits = readBits(stream, tableInfo.minBits)
                if bits == nil then
                    runtimeError("Unexpected end of compressed stream.")
                end
                code = (1 << tableInfo.minBits) | reverseBits(bits, tableInfo.minBits)
                bitCount = tableInfo.minBits
            else
                local bit = readBits(stream, 1)
                if bit == nil then
                    runtimeError("Unexpected end of compressed stream.")
                end
                bitCount = bitCount + 1
                code = (code << 1) | bit
            end

            local value = tableInfo.lookup[code]
            if value ~= nil then
                return value
            end
        end
    end

    local function parseGzipHeader(stream)
        local id1 = readBits(stream, 8)
        local id2 = readBits(stream, 8)
        if id1 ~= 31 or id2 ~= 139 then
            runtimeError("Compressed chunk is not in gzip format.")
        end

        local compressionMethod = readBits(stream, 8)
        local flags = readBits(stream, 8)
        if compressionMethod ~= 8 then
            runtimeError("Unsupported gzip compression method.")
        end

        readBits(stream, 32) -- mtime
        readBits(stream, 8)  -- xfl
        readBits(stream, 8)  -- os

        if hasBit(flags, 2 ^ 2) then
            local extraLength = readBits(stream, 16)
            for _ = 1, extraLength do
                readBits(stream, 8)
            end
        end

        local function readZeroTerminatedString()
            while true do
                local byte = readBits(stream, 8)
                if byte == nil then
                    runtimeError("Invalid gzip header.")
                end
                if byte == 0 then
                    return
                end
            end
        end

        if hasBit(flags, 2 ^ 3) then
            readZeroTerminatedString()
        end

        if hasBit(flags, 2 ^ 4) then
            readZeroTerminatedString()
        end

        if hasBit(flags, 2 ^ 1) then
            readBits(stream, 16)
        end
    end

    local function parseDynamicTables(stream)
        local literalCount = readBits(stream, 5) + 257
        local distanceCount = readBits(stream, 5) + 1
        local codeLengthCount = readBits(stream, 4) + 4

        local codeLengthOrder = {
            16, 17, 18, 0, 8, 7, 9, 6, 10,
            5, 11, 4, 12, 3, 13, 2, 14, 1, 15
        }

        local codeLengthInit = {}
        for index = 1, codeLengthCount do
            codeLengthInit[codeLengthOrder[index]] = readBits(stream, 3)
        end

        local codeLengthTable = buildHuffmanTable(codeLengthInit, true)

        local function decode(count)
            local init = {}
            local value = 0
            local previousBits = 0

            while value < count do
                local codeLength = readHuffmanValue(stream, codeLengthTable)
                local repeatCount
                local bitCount

                if codeLength <= 15 then
                    repeatCount = 1
                    bitCount = codeLength
                    previousBits = bitCount
                elseif codeLength == 16 then
                    repeatCount = 3 + readBits(stream, 2)
                    bitCount = previousBits
                elseif codeLength == 17 then
                    repeatCount = 3 + readBits(stream, 3)
                    bitCount = 0
                    previousBits = 0
                elseif codeLength == 18 then
                    repeatCount = 11 + readBits(stream, 7)
                    bitCount = 0
                    previousBits = 0
                else
                    runtimeError("Invalid dynamic Huffman code length.")
                end

                for _ = 1, repeatCount do
                    init[value] = bitCount
                    value = value + 1
                end
            end

            return buildHuffmanTable(init, true)
        end

        return decode(literalCount), decode(distanceCount)
    end

    local LENGTH_BASE = {
        [257] = 3, [258] = 4, [259] = 5, [260] = 6, [261] = 7, [262] = 8, [263] = 9, [264] = 10,
        [265] = 11, [266] = 13, [267] = 15, [268] = 17, [269] = 19, [270] = 23, [271] = 27, [272] = 31,
        [273] = 35, [274] = 43, [275] = 51, [276] = 59, [277] = 67, [278] = 83, [279] = 99, [280] = 115,
        [281] = 131, [282] = 163, [283] = 195, [284] = 227, [285] = 258
    }
    local LENGTH_EXTRA = {
        [257] = 0, [258] = 0, [259] = 0, [260] = 0, [261] = 0, [262] = 0, [263] = 0, [264] = 0,
        [265] = 1, [266] = 1, [267] = 1, [268] = 1, [269] = 2, [270] = 2, [271] = 2, [272] = 2,
        [273] = 3, [274] = 3, [275] = 3, [276] = 3, [277] = 4, [278] = 4, [279] = 4, [280] = 4,
        [281] = 5, [282] = 5, [283] = 5, [284] = 5, [285] = 0
    }
    local DIST_BASE = {
        [0] = 1, [1] = 2, [2] = 3, [3] = 4, [4] = 5, [5] = 7, [6] = 9, [7] = 13,
        [8] = 17, [9] = 25, [10] = 33, [11] = 49, [12] = 65, [13] = 97, [14] = 129, [15] = 193,
        [16] = 257, [17] = 385, [18] = 513, [19] = 769, [20] = 1025, [21] = 1537, [22] = 2049, [23] = 3073,
        [24] = 4097, [25] = 6145, [26] = 8193, [27] = 12289, [28] = 16385, [29] = 24577
    }
    local DIST_EXTRA = {
        [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 1, [5] = 1, [6] = 2, [7] = 2,
        [8] = 3, [9] = 3, [10] = 4, [11] = 4, [12] = 5, [13] = 5, [14] = 6, [15] = 6,
        [16] = 7, [17] = 7, [18] = 8, [19] = 8, [20] = 9, [21] = 9, [22] = 10, [23] = 10,
        [24] = 11, [25] = 11, [26] = 12, [27] = 12, [28] = 13, [29] = 13
    }

    local function newOutputState()
        local writeByte, finish = makeByteCollector()
        return {
            window = {},
            windowPosition = 1,
            writeByte = writeByte,
            finish = finish
        }
    end

    local function emitByte(state, byte)
        state.writeByte(byte)
        state.window[state.windowPosition] = byte
        state.windowPosition = (state.windowPosition % 32768) + 1
    end

    local function parseCompressedItem(stream, state, literalTable, distanceTable)
        local value = readHuffmanValue(stream, literalTable)
        if value < 256 then
            emitByte(state, value)
            return false
        end

        if value == 256 then
            return true
        end

        local lengthBase = LENGTH_BASE[value]
        local lengthExtraBits = LENGTH_EXTRA[value]
        local length = lengthBase + readBits(stream, lengthExtraBits)

        local distanceValue = readHuffmanValue(stream, distanceTable)
        local distanceBase = DIST_BASE[distanceValue]
        local distanceExtraBits = DIST_EXTRA[distanceValue]
        local distance = distanceBase + readBits(stream, distanceExtraBits)

        for _ = 1, length do
            local position = ((state.windowPosition - 1 - distance) % 32768) + 1
            local byte = state.window[position]
            if byte == nil then
                runtimeError("Invalid deflate distance.")
            end
            emitByte(state, byte)
        end

        return false
    end

    local FIXED_LITERAL_TABLE = buildHuffmanTable { 0, 8, 144, 9, 256, 7, 280, 8, 288, nil }
    local FIXED_DISTANCE_TABLE = buildHuffmanTable { 0, 5, 32, nil }

    local function parseBlock(stream, state)
        local isFinal = readBits(stream, 1)
        local blockType = readBits(stream, 2)

        if blockType == 0 then
            alignToByte(stream)
            local length = readBits(stream, 16)
            readBits(stream, 16) -- nlen

            for _ = 1, length do
                local byte = readBits(stream, 8)
                if byte == nil then
                    runtimeError("Unexpected end of stored deflate block.")
                end
                emitByte(state, byte)
            end
        elseif blockType == 1 or blockType == 2 then
            local literalTable = FIXED_LITERAL_TABLE
            local distanceTable = FIXED_DISTANCE_TABLE
            if blockType == 2 then
                literalTable, distanceTable = parseDynamicTables(stream)
            end

            while true do
                if parseCompressedItem(stream, state, literalTable, distanceTable) then
                    break
                end
            end
        else
            runtimeError("Unsupported deflate block type.")
        end

        return isFinal ~= 0
    end

    local function gunzipString(input)
        local stream = newBitStream(input)
        parseGzipHeader(stream)

        local state = newOutputState()
        repeat
            local isFinal = parseBlock(stream, state)
            if isFinal then
                break
            end
        until false

        alignToByte(stream)
        readBits(stream, 32) -- crc32
        readBits(stream, 32) -- isize
        return state.finish()
    end

    return gunzipString
end

local gunzipString = buildGunzip()

local function createBinaryReader(path)
    local handle, openError = io.open(path, "rb")
    if not handle then
        error("Failed to open file: " .. tostring(openError), 0)
    end

    local reader = {
        handle = handle,
        position = 0
    }

    function reader:close()
        if self.handle then
            self.handle:close()
            self.handle = nil
        end
    end

    function reader:readExact(count)
        local data = self.handle:read(count)
        if type(data) ~= "string" or #data ~= count then
            error(string.format("Unexpected end of file at byte %d.", self.position), 0)
        end
        self.position = self.position + count
        return data
    end

    function reader:readByte()
        return self:readExact(1):byte(1)
    end

    function reader:readUInt24LE()
        local a, b, c = self:readExact(3):byte(1, 3)
        return a + b * 256 + c * 65536
    end

    function reader:readUInt16LE()
        local a, b = self:readExact(2):byte(1, 2)
        return a + b * 256
    end

    function reader:readInt16LE()
        local value = self:readUInt16LE()
        if value >= 32768 then
            return value - 65536
        end
        return value
    end

    function reader:readUInt32LE()
        local a, b, c, d = self:readExact(4):byte(1, 4)
        return a + b * 256 + c * 65536 + d * 16777216
    end

    function reader:readInt32LE()
        local value = self:readUInt32LE()
        if value >= 2147483648 then
            return value - 4294967296
        end
        return value
    end

    function reader:readUInt32BE()
        local a, b, c, d = self:readExact(4):byte(1, 4)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end

    function reader:readInt64LE()
        local lo = self:readUInt32LE()
        local hi = self:readUInt32LE()
        local value = lo + hi * 4294967296
        if hi >= 2147483648 then
            value = value - 18446744073709551616
        end
        return value
    end

    function reader:readUInt64LE()
        local lo = self:readUInt32LE()
        local hi = self:readUInt32LE()
        return lo + hi * 4294967296
    end

    function reader:readLengthPrefixedString()
        local length = 0
        local shift = 0

        for _ = 1, 5 do
            local byte = self:readByte()
            length = length + ((byte & 0x7F) << shift)
            if (byte & 0x80) == 0 then
                return self:readExact(length)
            end
            shift = shift + 7
        end

        error("NRBF length-prefixed string overflow.", 0)
    end

    return reader
end

local PrimitiveType = {
    Boolean = 1,
    Byte = 2,
    Char = 3,
    Decimal = 5,
    Double = 6,
    Int16 = 7,
    Int32 = 8,
    Int64 = 9,
    SByte = 10,
    Single = 11,
    TimeSpan = 12,
    DateTime = 13,
    UInt16 = 14,
    UInt32 = 15,
    UInt64 = 16,
    Null = 17,
    String = 18
}

local BinaryType = {
    Primitive = 0,
    String = 1,
    Object = 2,
    SystemClass = 3,
    Class = 4,
    ObjectArray = 5,
    StringArray = 6,
    PrimitiveArray = 7
}

local BinaryArrayType = {
    Single = 0,
    Jagged = 1,
    Rectangular = 2,
    SingleOffset = 3,
    JaggedOffset = 4,
    RectangularOffset = 5
}

local RecordType = {
    SerializedStreamHeader = 0,
    ClassWithId = 1,
    SystemClassWithMembers = 2,
    ClassWithMembers = 3,
    SystemClassWithMembersAndTypes = 4,
    ClassWithMembersAndTypes = 5,
    BinaryObjectString = 6,
    BinaryArray = 7,
    MemberPrimitiveTyped = 8,
    MemberReference = 9,
    ObjectNull = 10,
    MessageEnd = 11,
    BinaryLibrary = 12,
    ObjectNullMultiple256 = 13,
    ObjectNullMultiple = 14,
    ArraySinglePrimitive = 15,
    ArraySingleObject = 16,
    ArraySingleString = 17
}

local function newReference(objectId)
    return {
        __kind = "reference",
        objectId = objectId,
        parent = nil,
        index = nil
    }
end

local function isReference(value)
    return type(value) == "table" and value.__kind == "reference"
end

local function newObjectNullMultiple(count)
    return {
        __kind = "object-null-multiple",
        count = count
    }
end

local function isObjectNullMultiple(value)
    return type(value) == "table" and value.__kind == "object-null-multiple"
end

local function newBinaryLibrary(libraryId, name)
    return {
        __kind = "binary-library",
        id = libraryId,
        name = name,
        objects = {}
    }
end

local function isBinaryLibrary(value)
    return type(value) == "table" and value.__kind == "binary-library"
end

local function createClassInfo(objectId, className, fieldNames, isSystemClass)
    return {
        id = objectId,
        originalClassName = className,
        className = sanitizeIdentifier(className),
        fieldNames = fieldNames,
        typeInfo = nil,
        isSystemClass = isSystemClass
    }
end

local function createObject(classInfo, objectId)
    local obj = {
        __classInfo = classInfo,
        __className = classInfo.className,
        __originalClassName = classInfo.originalClassName,
        __fieldNames = classInfo.fieldNames,
        __id = objectId
    }

    for index, fieldName in ipairs(classInfo.fieldNames) do
        obj[index] = nil
        obj[fieldName] = nil
    end

    return obj
end

local function setIndexedValue(container, index, value)
    container[index] = value
    if container.__fieldNames then
        local fieldName = container.__fieldNames[index]
        if fieldName then
            container[fieldName] = value
        end
    end
end

local function getContainerLength(container)
    if type(container) ~= "table" then
        return 0
    end

    if container.__fieldNames then
        return #container.__fieldNames
    end

    return container.__length or #container
end

local function convert1DArrayND(array1d, dims, state)
    state = state or { index = 1 }
    if #dims == 1 then
        local array = { __length = dims[1] }
        for index = 1, dims[1] do
            array[index] = array1d[state.index]
            state.index = state.index + 1
        end
        return array
    end

    local array = { __length = dims[1] }
    local subDims = {}
    for index = 2, #dims do
        subDims[#subDims + 1] = dims[index]
    end

    for index = 1, dims[1] do
        array[index] = convert1DArrayND(array1d, subDims, state)
    end

    return array
end

local function newNrbfParser(reader)
    return {
        reader = reader,
        rootId = nil,
        headerId = nil,
        classById = {},
        objectsById = {},
        binaryLibraries = {},
        deferredMemoryBlocks = {}
    }
end

local function readPrimitive(parser, primitiveType)
    local reader = parser.reader

    if primitiveType == PrimitiveType.Boolean then
        return reader:readByte() ~= 0
    elseif primitiveType == PrimitiveType.Byte then
        return reader:readByte()
    elseif primitiveType == PrimitiveType.Int16 then
        return reader:readInt16LE()
    elseif primitiveType == PrimitiveType.Int32 then
        return reader:readInt32LE()
    elseif primitiveType == PrimitiveType.Int64 then
        return reader:readInt64LE()
    elseif primitiveType == PrimitiveType.SByte then
        local value = reader:readByte()
        if value >= 128 then
            return value - 256
        end
        return value
    elseif primitiveType == PrimitiveType.UInt16 then
        return reader:readUInt16LE()
    elseif primitiveType == PrimitiveType.UInt32 then
        return reader:readUInt32LE()
    elseif primitiveType == PrimitiveType.UInt64 then
        return reader:readUInt64LE()
    elseif primitiveType == PrimitiveType.String then
        return reader:readLengthPrefixedString()
    elseif primitiveType == PrimitiveType.Null then
        return nil
    elseif primitiveType == PrimitiveType.Char then
        return reader:readLengthPrefixedString()
    end

    error("Unsupported NRBF primitive type: " .. tostring(primitiveType), 0)
end

local function readPrimitiveArray(parser, primitiveType, length)
    local reader = parser.reader

    if primitiveType == PrimitiveType.Byte then
        return reader:readExact(length)
    end

    local array = { __length = length }
    for index = 1, length do
        array[index] = readPrimitive(parser, primitiveType)
    end
    return array
end

local function readAdditionalInfo(parser, binaryType)
    if binaryType == BinaryType.Primitive or binaryType == BinaryType.PrimitiveArray then
        return parser.reader:readByte()
    elseif binaryType == BinaryType.String or binaryType == BinaryType.Object
        or binaryType == BinaryType.ObjectArray or binaryType == BinaryType.StringArray then
        return nil
    elseif binaryType == BinaryType.SystemClass then
        return parser.reader:readLengthPrefixedString()
    elseif binaryType == BinaryType.Class then
        return {
            className = parser.reader:readLengthPrefixedString(),
            libraryId = parser.reader:readInt32LE()
        }
    end

    error("Unsupported NRBF additional info type: " .. tostring(binaryType), 0)
end

local readRecord

local function readObjectArray(parser, length)
    local array = { __length = length }
    local index = 1

    while index <= length do
        local value = readRecord(parser)

        if isBinaryLibrary(value) then
        elseif isObjectNullMultiple(value) then
            index = index + value.count
        else
            if isReference(value) then
                value.parent = array
                value.index = index
            end
            array[index] = value
            index = index + 1
        end
    end

    return array
end

local function readClassInfo(parser, isSystemClass)
    local objectId = parser.reader:readInt32LE()
    local className = parser.reader:readLengthPrefixedString()
    local memberCount = parser.reader:readInt32LE()
    local fieldNames = {}

    for index = 1, memberCount do
        fieldNames[index] = sanitizeIdentifier(parser.reader:readLengthPrefixedString())
    end

    local classInfo = createClassInfo(objectId, className, fieldNames, isSystemClass)
    parser.classById[objectId] = classInfo
    return classInfo
end

local function readMemberTypeInfo(parser, classInfo)
    local typeInfo = {}
    for index = 1, #classInfo.fieldNames do
        typeInfo[index] = {
            binaryType = parser.reader:readByte()
        }
    end

    for index = 1, #classInfo.fieldNames do
        typeInfo[index].additionalInfo = readAdditionalInfo(parser, typeInfo[index].binaryType)
    end

    classInfo.typeInfo = typeInfo
end

local function readClassMembers(parser, objectValue, objectId, libraryId)
    local fieldCount = #objectValue.__fieldNames
    local index = 1

    while index <= fieldCount do
        local memberTypeInfo = objectValue.__classInfo.typeInfo and objectValue.__classInfo.typeInfo[index] or nil
        local binaryType = memberTypeInfo and memberTypeInfo.binaryType or BinaryType.Object
        local additionalInfo = memberTypeInfo and memberTypeInfo.additionalInfo or nil
        local value

        if binaryType == BinaryType.Primitive then
            value = readPrimitive(parser, additionalInfo)
        else
            value = readRecord(parser)
            if isBinaryLibrary(value) then
                goto continue
            elseif isObjectNullMultiple(value) then
                index = index + value.count
                goto continue
            elseif isReference(value) then
                value.parent = objectValue
                value.index = index
            end
        end

        setIndexedValue(objectValue, index, value)
        index = index + 1

        ::continue::
    end

    parser.objectsById[objectId] = objectValue
    if libraryId and parser.binaryLibraries[libraryId] then
        parser.binaryLibraries[libraryId].objects[objectId] = objectValue
    end

    if objectValue.__className == "PaintDotNet_MemoryBlock" and objectValue.deferred then
        parser.deferredMemoryBlocks[#parser.deferredMemoryBlocks + 1] = objectValue
    end

    return objectValue
end

readRecord = function(parser)
    local recordType = parser.reader:readByte()

    if recordType == RecordType.SerializedStreamHeader then
        parser.rootId = parser.reader:readInt32LE()
        parser.headerId = parser.reader:readInt32LE()
        local major = parser.reader:readInt32LE()
        local minor = parser.reader:readInt32LE()
        if major ~= 1 or minor ~= 0 then
            error("Unsupported NRBF serialization version.", 0)
        end
        return nil
    elseif recordType == RecordType.ClassWithId then
        local objectId = parser.reader:readInt32LE()
        local metadataId = parser.reader:readInt32LE()
        local classInfo = parser.classById[metadataId]
        if not classInfo then
            error("Missing NRBF metadata class: " .. tostring(metadataId), 0)
        end
        return readClassMembers(parser, createObject(classInfo, objectId), objectId)
    elseif recordType == RecordType.SystemClassWithMembers then
        local classInfo = readClassInfo(parser, true)
        return readClassMembers(parser, createObject(classInfo, classInfo.id), classInfo.id)
    elseif recordType == RecordType.ClassWithMembers then
        local classInfo = readClassInfo(parser, false)
        local libraryId = parser.reader:readInt32LE()
        return readClassMembers(parser, createObject(classInfo, classInfo.id), classInfo.id, libraryId)
    elseif recordType == RecordType.SystemClassWithMembersAndTypes then
        local classInfo = readClassInfo(parser, true)
        readMemberTypeInfo(parser, classInfo)
        return readClassMembers(parser, createObject(classInfo, classInfo.id), classInfo.id)
    elseif recordType == RecordType.ClassWithMembersAndTypes then
        local classInfo = readClassInfo(parser, false)
        readMemberTypeInfo(parser, classInfo)
        local libraryId = parser.reader:readInt32LE()
        return readClassMembers(parser, createObject(classInfo, classInfo.id), classInfo.id, libraryId)
    elseif recordType == RecordType.BinaryObjectString then
        local objectId = parser.reader:readInt32LE()
        local value = parser.reader:readLengthPrefixedString()
        parser.objectsById[objectId] = value
        return value
    elseif recordType == RecordType.MemberPrimitiveTyped then
        return readPrimitive(parser, parser.reader:readByte())
    elseif recordType == RecordType.BinaryArray then
        local objectId = parser.reader:readInt32LE()
        local arrayType = parser.reader:readByte()
        local rank = parser.reader:readInt32LE()
        local lengths = {}
        local totalLength = 1

        for index = 1, rank do
            lengths[index] = parser.reader:readInt32LE()
            totalLength = totalLength * lengths[index]
        end

        if arrayType == BinaryArrayType.SingleOffset
            or arrayType == BinaryArrayType.JaggedOffset
            or arrayType == BinaryArrayType.RectangularOffset then
            for _ = 1, rank do
                parser.reader:readInt32LE()
            end
        end

        local binaryType = parser.reader:readByte()
        local additionalInfo = readAdditionalInfo(parser, binaryType)
        local array

        if binaryType == BinaryType.Primitive then
            array = readPrimitiveArray(parser, additionalInfo, totalLength)
        else
            array = readObjectArray(parser, totalLength)
        end

        if arrayType == BinaryArrayType.Rectangular or arrayType == BinaryArrayType.RectangularOffset then
            array = convert1DArrayND(array, lengths)
        end

        parser.objectsById[objectId] = array
        return array
    elseif recordType == RecordType.MemberReference then
        return newReference(parser.reader:readInt32LE())
    elseif recordType == RecordType.ObjectNull then
        return nil
    elseif recordType == RecordType.MessageEnd then
        return { __kind = "message-end" }
    elseif recordType == RecordType.BinaryLibrary then
        local libraryId = parser.reader:readInt32LE()
        local name = parser.reader:readLengthPrefixedString()
        local library = newBinaryLibrary(libraryId, name)
        parser.binaryLibraries[libraryId] = library
        return library
    elseif recordType == RecordType.ObjectNullMultiple256 then
        return newObjectNullMultiple(parser.reader:readByte())
    elseif recordType == RecordType.ObjectNullMultiple then
        return newObjectNullMultiple(parser.reader:readInt32LE())
    elseif recordType == RecordType.ArraySinglePrimitive then
        local objectId = parser.reader:readInt32LE()
        local length = parser.reader:readInt32LE()
        local primitiveType = parser.reader:readByte()
        local array = readPrimitiveArray(parser, primitiveType, length)
        parser.objectsById[objectId] = array
        return array
    elseif recordType == RecordType.ArraySingleObject or recordType == RecordType.ArraySingleString then
        local objectId = parser.reader:readInt32LE()
        local length = parser.reader:readInt32LE()
        local array = readObjectArray(parser, length)
        parser.objectsById[objectId] = array
        return array
    end

    error("Unsupported NRBF record type: " .. tostring(recordType), 0)
end

local function resolveReferences(parser)
    for _, objectValue in pairs(parser.objectsById) do
        if type(objectValue) == "table" then
            local length = getContainerLength(objectValue)
            for index = 1, length do
                local item = objectValue[index]
                if isReference(item) then
                    local replacement = parser.objectsById[item.objectId]
                    if replacement == nil then
                        error("Unresolved NRBF reference: " .. tostring(item.objectId), 0)
                    end
                    setIndexedValue(objectValue, index, replacement)
                end
            end
        end
    end
end

local function readNrbfGraph(parser)
    readRecord(parser)
    if parser.rootId == nil then
        error("Invalid NRBF stream: missing header.", 0)
    end

    while true do
        local record = readRecord(parser)
        if type(record) == "table" and record.__kind == "message-end" then
            break
        end
    end

    resolveReferences(parser)
    return parser.objectsById[parser.rootId]
end

local function readDeferredMemoryBlock(reader, memoryBlock)
    if memoryBlock.hasParent then
        error("Unsupported Paint.NET MemoryBlock parent chain.", 0)
    end

    if not memoryBlock.deferred then
        error("Unsupported non-deferred Paint.NET MemoryBlock.", 0)
    end

    local length = memoryBlock.length64 or memoryBlock.length
    if type(length) ~= "number" or length < 0 then
        error("Invalid Paint.NET MemoryBlock length.", 0)
    end

    if length == 0 then
        return ""
    end

    local formatVersion = reader:readByte()
    local chunkSize = reader:readUInt32BE()
    if chunkSize <= 0 then
        error("Invalid Paint.NET chunk size.", 0)
    end

    local chunkCount = math.floor((length + chunkSize - 1) / chunkSize)
    local chunks = {}

    for _ = 1, chunkCount do
        local chunkNumber = reader:readUInt32BE()
        local dataSize = reader:readUInt32BE()

        if chunkNumber >= chunkCount then
            error("Paint.NET chunk number is out of bounds.", 0)
        end

        local slot = chunkNumber + 1
        if chunks[slot] ~= nil then
            error("Duplicate Paint.NET chunk number encountered.", 0)
        end

        local rawChunk = reader:readExact(dataSize)
        local chunkOffset = chunkNumber * chunkSize
        local actualChunkSize = math.min(chunkSize, length - chunkOffset)
        local decodedChunk

        if formatVersion == 0 then
            decodedChunk = gunzipString(rawChunk)
        elseif formatVersion == 1 then
            decodedChunk = rawChunk
        else
            error("Unsupported Paint.NET chunk format version: " .. tostring(formatVersion), 0)
        end

        if #decodedChunk ~= actualChunkSize then
            error("Paint.NET chunk decompressed to an unexpected size.", 0)
        end

        chunks[slot] = decodedChunk
    end

    for index = 1, chunkCount do
        if chunks[index] == nil then
            error("Paint.NET chunk data is incomplete.", 0)
        end
    end

    return table.concat(chunks)
end

local LEGACY_BLEND_CLASS_TO_ID = {
    PaintDotNet_UserBlendOps_NormalBlendOp = 0,
    PaintDotNet_UserBlendOps_MultiplyBlendOp = 1,
    PaintDotNet_UserBlendOps_AdditiveBlendOp = 2,
    PaintDotNet_UserBlendOps_ColorBurnBlendOp = 3,
    PaintDotNet_UserBlendOps_ColorDodgeBlendOp = 4,
    PaintDotNet_UserBlendOps_ReflectBlendOp = 5,
    PaintDotNet_UserBlendOps_GlowBlendOp = 6,
    PaintDotNet_UserBlendOps_OverlayBlendOp = 7,
    PaintDotNet_UserBlendOps_DifferenceBlendOp = 8,
    PaintDotNet_UserBlendOps_NegationBlendOp = 9,
    PaintDotNet_UserBlendOps_LightenBlendOp = 10,
    PaintDotNet_UserBlendOps_DarkenBlendOp = 11,
    PaintDotNet_UserBlendOps_ScreenBlendOp = 12,
    PaintDotNet_UserBlendOps_XorBlendOp = 13
}

local BLEND_MODE_NAMES = {
    [0] = "Normal",
    [1] = "Multiply",
    [2] = "Additive",
    [3] = "Color Burn",
    [4] = "Color Dodge",
    [5] = "Reflect",
    [6] = "Glow",
    [7] = "Overlay",
    [8] = "Difference",
    [9] = "Negation",
    [10] = "Lighten",
    [11] = "Darken",
    [12] = "Screen",
    [13] = "XOR"
}

local ASEPRITE_BLEND_MAP = {
    [0] = BlendMode.NORMAL,
    [1] = BlendMode.MULTIPLY,
    [2] = BlendMode.ADDITION,
    [3] = BlendMode.COLOR_BURN,
    [4] = BlendMode.COLOR_DODGE,
    [7] = BlendMode.OVERLAY,
    [8] = BlendMode.DIFFERENCE,
    [10] = BlendMode.LIGHTEN,
    [11] = BlendMode.DARKEN,
    [12] = BlendMode.SCREEN
}

local function resolveBlendModeId(bitmapLayer)
    local props = bitmapLayer.Layer_properties
    if type(props) == "table" and type(props.blendMode) == "table" and type(props.blendMode.value__) == "number" then
        return props.blendMode.value__
    end

    local legacyProperties = bitmapLayer.properties
    local blendOp = legacyProperties and legacyProperties.blendOp
    if type(blendOp) == "table" and type(blendOp.__className) == "string" then
        return LEGACY_BLEND_CLASS_TO_ID[blendOp.__className] or 0
    end

    return 0
end

local function parsePdnFile(path)
    local reader = createBinaryReader(path)
    local ok, resultOrError = pcall(function()
        local magic = reader:readExact(4)
        if magic ~= "PDN3" then
            error("Selected file is not a Paint.NET PDN document.", 0)
        end

        local headerSize = reader:readUInt24LE()
        local headerXml = reader:readExact(headerSize)
        local marker = reader:readExact(2)
        if marker ~= "\0\1" then
            error("Unsupported PDN stream marker. Only deferred PDN documents are supported.", 0)
        end

        local parser = newNrbfParser(reader)
        local document = readNrbfGraph(parser)

        for _, memoryBlock in ipairs(parser.deferredMemoryBlocks) do
            memoryBlock.rawData = readDeferredMemoryBlock(reader, memoryBlock)
        end

        local width = tonumber(document.width)
        local height = tonumber(document.height)
        if not width or not height or width < 1 or height < 1 then
            error("PDN document has invalid dimensions.", 0)
        end

        local layersObject = document.layers
        local layerItems = layersObject and layersObject.ArrayList__items
        local layerCount = layersObject and layersObject.ArrayList__size
        if type(layerItems) ~= "table" or type(layerCount) ~= "number" then
            error("PDN document layers could not be read.", 0)
        end

        local warnings = {}
        local layers = {}

        for index = 1, layerCount do
            local layerObject = layerItems[index]
            if type(layerObject) ~= "table" then
                warnings[#warnings + 1] = string.format("Skipped layer %d because its metadata was empty.", index)
            elseif layerObject.__className ~= "PaintDotNet_BitmapLayer" then
                warnings[#warnings + 1] = string.format(
                    "Skipped unsupported layer type on layer %d: %s.",
                    index,
                    tostring(layerObject.__className or layerObject.__originalClassName or "Unknown")
                )
            else
                local props = layerObject.Layer_properties
                local surface = layerObject.surface
                local scan0 = surface and surface.scan0

                if type(props) ~= "table" or type(surface) ~= "table" or type(scan0) ~= "table" then
                    warnings[#warnings + 1] = string.format("Skipped layer %d because required bitmap metadata was missing.", index)
                elseif tonumber(layerObject.Layer_width) ~= width or tonumber(layerObject.Layer_height) ~= height then
                    warnings[#warnings + 1] = string.format("Skipped layer %d because its size did not match the document.", index)
                elseif type(scan0.rawData) ~= "string" then
                    warnings[#warnings + 1] = string.format("Skipped layer %d because its pixel buffer could not be reconstructed.", index)
                else
                    layers[#layers + 1] = {
                        index = index,
                        name = hasValue(props.name) and props.name or ("Layer " .. index),
                        visible = props.visible ~= false,
                        isBackground = props.isBackground == true,
                        opacity = math.max(0, math.min(255, tonumber(props.opacity) or 255)),
                        blendModeId = resolveBlendModeId(layerObject),
                        stride = tonumber(surface.stride) or 0,
                        rawData = scan0.rawData
                    }
                end
            end
        end

        if #layers == 0 then
            error("No supported bitmap layers were found in this PDN document.", 0)
        end

        return {
            width = width,
            height = height,
            headerXml = headerXml,
            layers = layers,
            warnings = warnings
        }
    end)

    reader:close()

    if not ok then
        error(resultOrError, 0)
    end

    return resultOrError
end

local function convertBgraToRgbaBytes(rawData, width, height, stride)
    local visibleStride = width * 4
    local minimumLength = (height - 1) * stride + visibleStride
    if stride < visibleStride or #rawData < minimumLength then
        error("PDN layer pixel buffer is shorter than expected.", 0)
    end

    if stride == visibleStride then
        return (rawData:gsub("(.)(.)(.)(.)", "%3%2%1%4"))
    end

    local rows = {}
    for rowIndex = 0, height - 1 do
        local startIndex = rowIndex * stride + 1
        local row = rawData:sub(startIndex, startIndex + visibleStride - 1)
        rows[#rows + 1] = (row:gsub("(.)(.)(.)(.)", "%3%2%1%4"))
    end

    return table.concat(rows)
end

local function configureImportedLayer(layer, layerInfo, warnings)
    layer.name = layerInfo.name
    layer.isVisible = layerInfo.visible

    local asepriteBlendMode = ASEPRITE_BLEND_MAP[layerInfo.blendModeId]
    if asepriteBlendMode ~= nil then
        layer.blendMode = asepriteBlendMode
    else
        layer.blendMode = BlendMode.NORMAL
        local originalBlendName = BLEND_MODE_NAMES[layerInfo.blendModeId] or ("Unknown(" .. tostring(layerInfo.blendModeId) .. ")")
        layer.data = "Original PDN blend mode: " .. originalBlendName
        warnings[#warnings + 1] = string.format(
            "Layer \"%s\" used unsupported PDN blend mode \"%s\". Imported as Normal.",
            layerInfo.name,
            originalBlendName
        )
    end

    if not layerInfo.isBackground then
        layer.opacity = layerInfo.opacity
    elseif layerInfo.opacity ~= 255 then
        warnings[#warnings + 1] = string.format(
            "Background layer \"%s\" had opacity %d. Aseprite background layers are always fully opaque.",
            layerInfo.name,
            layerInfo.opacity
        )
    end
end

local function rebuildImportedPalette(sprite, warnings)
    app.activeSprite = sprite

    local ok, err = pcall(function()
        app.command.ColorQuantization {
            ui = false,
            withAlpha = true,
            maxColors = 256,
            useRange = false,
            algorithm = "default"
        }
    end)

    if not ok then
        warnings[#warnings + 1] = "Could not build a palette from the imported sprite: " .. tostring(err)
    end
end

local function importParsedPdn(model, sourcePath)
    local sprite = Sprite(model.width, model.height, ColorMode.RGB)
    local runOk, runError = pcall(function()
        app.transaction(COMMAND_TITLE, function()
            local firstLayer = sprite.layers[1]
            local firstImportedLayer = nil
            local firstImportedInfo = nil
            local createdLayerCount = 0

            for _, layerInfo in ipairs(model.layers) do
                createdLayerCount = createdLayerCount + 1
                local layer = createdLayerCount == 1 and firstLayer or sprite:newLayer()
                if not firstImportedLayer then
                    firstImportedLayer = layer
                    firstImportedInfo = layerInfo
                end

                configureImportedLayer(layer, layerInfo, model.warnings)

                local image = Image(model.width, model.height, ColorMode.RGB)
                image.bytes = convertBgraToRgbaBytes(layerInfo.rawData, model.width, model.height, layerInfo.stride)
                sprite:newCel(layer, 1, image, Point(0, 0))
            end

            if firstImportedLayer and firstImportedInfo and firstImportedInfo.isBackground then
                app.activeSprite = sprite
                app.activeLayer = firstImportedLayer
                local backgroundOk, backgroundError = pcall(function()
                    app.command.BackgroundFromLayer()
                end)
                if not backgroundOk then
                    model.warnings[#model.warnings + 1] = "Could not convert the first PDN layer into an Aseprite background layer: " .. tostring(backgroundError)
                end
            end

            sprite.data = "Imported from PDN: " .. app.fs.fileName(sourcePath)
        end)

        rebuildImportedPalette(sprite, model.warnings)
    end)

    if not runOk then
        pcall(function()
            sprite:close()
        end)
        error(runError, 0)
    end

    return sprite
end

local function presentWarnings(warnings)
    if #warnings == 0 then
        return
    end

    local message = table.concat(warnings, "\n")
    if app.isUIAvailable then
        app.alert {
            title = COMMAND_TITLE .. " warnings",
            text = message
        }
    else
        print(message)
    end
end

local function finaliseImportedSprite(sprite, savePath, saveImmediately)
    sprite.filename = savePath

    if saveImmediately then
        sprite:saveAs(savePath)
    end
end

local function resolveImportOptions()
    local params = app.params or {}
    if hasValue(params.file) then
        local importPath = trim(params.file)
        local requestedName = hasValue(params.name) and trim(params.name) or defaultImportedSpriteName(importPath)
        return {
            importPath = importPath,
            savePath = buildImportedSpritePath(importPath, requestedName),
            saveImmediately = parseBooleanParam(params.save, true)
        }
    end

    if not app.isUIAvailable then
        error("Provide file=<path-to.pdn> when running without the Aseprite UI.", 0)
    end

    local dlg = Dialog { title = COMMAND_TITLE, resizeable = true }
    local autoName = ""
    local updatingName = false
    local nameWasEdited = false

    local function syncNameFromFile()
        local currentFile = trim(dlg.data.file or "")
        local nextAutoName = defaultImportedSpriteName(currentFile)
        if nextAutoName == "" then
            return
        end

        local currentName = trim(dlg.data.name or "")
        if not nameWasEdited or currentName == "" or currentName == autoName then
            autoName = nextAutoName
            updatingName = true
            dlg:modify { id = "name", text = nextAutoName }
            updatingName = false
            nameWasEdited = false
            return
        end

        autoName = nextAutoName
    end

    dlg:file {
        id = "file",
        label = "Paint.NET:",
        title = "Open PDN File",
        open = true,
        filetypes = { "pdn" },
        entry = true,
        hexpand = true,
        focus = true,
        onchange = syncNameFromFile
    }
    dlg:entry {
        id = "name",
        label = "Name:",
        text = "",
        hexpand = true,
        onchange = function()
            if updatingName then
                return
            end

            local currentName = trim(dlg.data.name or "")
            nameWasEdited = currentName ~= "" and currentName ~= autoName
        end
    }
    dlg:check {
        id = "saveImmediately",
        label = "Save:",
        text = "Write .aseprite file to disk immediately",
        selected = true
    }
    dlg:button { id = "ok", text = "Import" }
    dlg:button { id = "cancel", text = "Cancel" }
    dlg:show()

    if not dlg.data.ok then
        return nil
    end

    local filePath = trim(dlg.data.file or "")
    if filePath == "" then
        error("Please choose a Paint.NET .pdn file to import.", 0)
    end

    local requestedName = trim(dlg.data.name or "")
    if requestedName == "" then
        requestedName = defaultImportedSpriteName(filePath)
    end

    return {
        importPath = filePath,
        savePath = buildImportedSpritePath(filePath, requestedName),
        saveImmediately = dlg.data.saveImmediately == true
    }
end

local function run()
    local importOptions = resolveImportOptions()
    if not importOptions then
        return
    end

    local ok, resultOrError = pcall(function()
        local parsed = parsePdnFile(importOptions.importPath)
        local sprite = importParsedPdn(parsed, importOptions.importPath)
        finaliseImportedSprite(sprite, importOptions.savePath, importOptions.saveImmediately)
        return parsed
    end)

    if not ok then
        fail(resultOrError)
        return
    end

    presentWarnings(resultOrError.warnings)
end

run()

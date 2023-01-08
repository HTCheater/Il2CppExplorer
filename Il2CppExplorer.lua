-- https://github.com/HTCheater/Il2CppExplorer
if (explorer == nil or type(explorer) ~= 'table') then
    explorer = {}
end
-- Output debug messages
if explorer.debug == nil then
    explorer.debug = false
end
-- Let people know you are using my framework :D
if (explorer.printAdvert == nil) then
    explorer.printAdvert = true
end
-- Exit if selected process isn't Unity game
if (explorer.exitOnNotUnityGame == nil) then
    explorer.exitOnNotUnityGame = true
end
-- Contains start address of libil2cpp.so once either explorer.getLib or explorer.patchLib or explorer.editFunction was called
explorer.libStart = 0x0
explorer.maxStringLength = 1000
local alphabet = {}

if explorer.printAdvert then
    print("✨Made with Il2CppExplorer by HTCheater")
end

if (explorer.exitOnNotUnityGame and #gg.getRangesList("global-metadata.dat") < 1) then
    print("🔴 Please, select Unity game")
    os.exit()
end

-- String utils, feel free to use in your own script.

string.startsWith = function(self, str)
    return self:find("^" .. str) ~= nil
end

string.endsWith = function(str, ending)
    return ending == "" or str:sub(-(#ending)) == ending
end

string.toUpper = function(str)
    res, c = str:gsub("^%l", string.upper)
    return res
end

string.removeEnd = function(str, rem)
    return (str:gsub("^(.-)" .. rem .. "$", "%1"))
end

string.removeStart = function(str, rem)
    return (str:gsub("^" .. rem .. "(.-)$", "%1"))
end

-- some functions
local isx64 = gg.getTargetInfo().x64
local metadata = gg.getRangesList("global-metadata.dat")

if #metadata > 0 then
    metadata = metadata[1]
end

function explorer.setAllRanges()
    gg.setRanges(gg.REGION_JAVA_HEAP | gg.REGION_C_HEAP | gg.REGION_C_ALLOC | gg.REGION_C_DATA | gg.REGION_C_BSS |
                     gg.REGION_PPSSPP | gg.REGION_ANONYMOUS | gg.REGION_JAVA | gg.REGION_STACK | gg.REGION_ASHMEM |
                     gg.REGION_VIDEO | gg.REGION_OTHER | gg.REGION_BAD | gg.REGION_CODE_APP | gg.REGION_CODE_SYS)
end

-- Check wether the metadata class name pointer is suitable to find instances. Returns boolean.

function explorer.isClassPointer(address)
    local t = {}
    t[1] = {}
    t[1].address = address - (isx64 and 0x10 or 0x8)
    t[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
    gg.clearResults()
    gg.loadResults(t)
    t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_WRITABLE)
    if t[1] == nil then
        return false
    end

    t[1].address = address - (isx64 and 0x8 or 0x4)
    t[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
    gg.clearResults()
    gg.loadResults(t)
    t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_NO)
    if t[1] == nil then
        return false
    end

    t[1].address = address + (isx64 and 0x8 or 0x4)
    t[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
    gg.clearResults()
    gg.loadResults(t)
    t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_READ_ONLY)
    if t[1] == nil then
        return false
    end
    return true
end

-- Get instances of class. Returns table with search results or empty table.

function explorer.getInstances(classname)
    explorer.setAllRanges()
    gg.clearResults()
    local stringBytes = gg.bytes(classname, "UTF-8")
    local searchStr = "0"
    for k, v in ipairs(stringBytes) do
        searchStr = searchStr .. "; " .. v
    end
    searchStr = searchStr .. "; 0::" .. (2 + #stringBytes)

    gg.searchNumber(searchStr, gg.TYPE_BYTE, false, gg.SIGN_EQUAL, metadata.start, metadata["end"], 2)

    if gg.getResultsCount() < 1 then
        if debug then
            print("🔴 Can't find " .. classname .. " in metadata")
        end
        local r = {}
        return r
    end
    local r = {}
    r[1] = gg.getResults(2)[2]

    local addr = 0x0
    for k, v in pairs(gg.getRangesList("libc_malloc")) do
        gg.clearResults()
        gg.searchNumber(string.format("%X", r[1].address) .. "h", isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD, false,
            gg.SIGN_EQUAL, v.start, v["end"], 0)

        local results = gg.getResults(100)
        gg.clearResults()

        for i, res in ipairs(results) do
            if explorer.isClassPointer(res.address) == true then
                addr = res.address
                break
            end
        end
        if addr > 0 then
            break
        end
    end
    if addr == 0 then
        if debug then
            explorer.print("🔴 There is no valid pointer for " .. classname)
        end
        local r = {}
        return r
    end

    gg.setRanges(gg.REGION_ANONYMOUS)
    gg.loadResults(gg.getResults(1))
    r = {}
    r[1] = {}
    r[1].address = addr - (isx64 and 0x10 or 0x8)
    r[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
    gg.loadResults(r)
    gg.searchPointer(0)
    r = gg.getResults(100000)
    if gg.getResultsCount() == 0 and debug then
        explorer.print("🔴 There are no instances for the " .. classname .. ", try to load the class first")
    end
    gg.clearResults()
    return r
end

-- Patch libil2cpp.so;
-- patchedBytes is a table which contains patches that can be either a dword number or a string containing opcode
-- or a string containig hex (must start with "h" and contain only 4 bytes each).
-- Consider using explorer.editFunction

function explorer.patchLib(offset, offsetX32, patchedBytes, patchedBytesX32)
    gg.clearResults()
    if explorer.libStart == 0 then
        explorer.getLib()
    end
    local patch = {}
    if not isx64 then
        patchedBytes = patchedBytesX32
        offset = offsetX32
    end
    if (patchedBytes == nil or offset == nil) then
        explorer.print("🔴 There is no valid patch for current architecture")
        return
    end
    local currAddress = explorer.libStart + offset
    for k, v in ipairs(patchedBytes) do
        local t = {}
        t[1] = {}
        t[1].address = currAddress
        t[1].flags = gg.TYPE_DWORD
        if type(v) == "number" then
            t[1].value = v
            gg.setValues(t)
        end
        if type(v) == "string" then
            if v:startsWith("h") then
                t[1].value = v
                gg.setValues(t)
            else
                t[1].value = (isx64 and "~A8 " or "~A ") .. v
                gg.setValues(t)
            end
        end
        currAddress = currAddress + 4
    end
end

-- Call explorer.getLib in case you need access to explorer.libStart

function explorer.getLib()
    explorer.setAllRanges()
    local libil2cpp
    if gg.getRangesList("libil2cpp.so")[1] ~= nil then
        explorer.libStart = gg.getRangesList("libil2cpp.so")[1].start
        return
    end

    local ranges = gg.getRangesList("bionic_alloc_small_objects")
    for i, range in pairs(ranges) do
        gg.searchNumber("47;108;105;98;105;108;50;99;112;112;46;115;111;0::14", gg.TYPE_BYTE, false, gg.SIGN_EQUAL,
            range['start'], range['end'], 1)
        gg.refineNumber("47", gg.TYPE_BYTE)
        if gg.getResultsCount() ~= 0 then
            local str = gg.getResults(1)[1]
            gg.clearResults()
            addr = str.address
            while explorer.readByte(addr) ~= 0 do
                addr = addr - 1
            end
            local t = {}
            t[1] = {}
            t[1].address = addr + 1
            t[1].flags = gg.TYPE_BYTE
            for k, v in pairs(gg.getRangesList("linker_alloc")) do
                gg.clearResults()
                gg.loadResults(t)
                gg.searchPointer(0, v['start'], v['end'])
                for index, res in pairs(gg.getResults(1)) do
                    local t = {}
                    t[1] = {}
                    t[1].address = res.address - (isx64 and 0x8 or 0x4)
                    t[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
                    gg.loadResults(t)
                    local pointers = gg.getResults(1, 0, nil, nil, nil, nil, nil, nil, gg.POINTER_EXECUTABLE)
                    if #pointers ~= 0 then
                        explorer.libStart = explorer.readPointer(t[1].address)
                        break
                    end
                end
            end
            break
        end
    end
    if explorer.libStart == 0x0 then
        explorer.print("🔴 Failed to get libil2cpp.so address, try entering the game first")
    end
end

-- Get field value in instance from instances table specified by index

function explorer.getField(instancesTable, offset, offsetX32, type, index)
    if instancesTable == nil then
        explorer.print("🔴 Instances table is nil")
        return nil
    end
    local instance = instancesTable[index]
    if instance == nil then
        explorer.print("🔴 Wrong index (no results found?)")
        return nil
    end
    if not isx64 then
        offset = offsetX32
    end
    if offset == nil then
        explorer.print("🔴 Offset for this architecture is not specified")
        return nil
    end
    return explorer.readValue(instance.address + offset, type)
end

-- Edit field value in instance from instances table specified by index

function explorer.editField(instancesTable, offset, offsetX32, type, index, value)
    if instancesTable == nil then
        explorer.print("🔴 Instances table is nil")
        return nil
    end
    local instance = instancesTable[index]
    if instance == nil then
        explorer.print("🔴 Wrong index (no results found?)")
        return nil
    end
    if not isx64 then
        offset = offsetX32
    end
    if offset == nil then
        explorer.print("🔴 Offset for this architecture is not specified")
        return nil
    end

    local t = {}
    t[1] = {}
    t[1].address = instance.address + offset
    t[1].flags = type
    t[1].value = value
    gg.setValues(t)
end

function explorer.getFunction(className, functionName)
    explorer.setAllRanges()
    gg.clearResults()
    local stringBytes = gg.bytes(functionName, "UTF-8")
    local searchStr = "0"
    for k, v in ipairs(stringBytes) do
        searchStr = searchStr .. "; " .. v
    end
    searchStr = searchStr .. "; 0::" .. (2 + #stringBytes)

    gg.searchNumber(searchStr, gg.TYPE_BYTE, false, gg.SIGN_EQUAL, metadata.start, metadata["end"],
        (className == nil) and 2 or nil)
    gg.refineNumber("0; " .. stringBytes[1], gg.TYPE_BYTE)
    gg.refineNumber(stringBytes[1], gg.TYPE_BYTE)

    if gg.getResultsCount() == 0 then
        explorer.print("Can't find " .. functionName .. " in metadata")
        local r = {}
        return r
    end

    local addr = 0x0

    for index, result in pairs(gg.getResults(100000)) do
        for k, v in pairs(gg.getRangesList("libc_malloc")) do
            gg.clearResults()
            gg.searchNumber(string.format("%X", result.address) .. "h", isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD, false,
                gg.SIGN_EQUAL, v.start, v["end"], 0)

            local results = gg.getResults(100)
            gg.clearResults()

            for i, res in ipairs(results) do
                if explorer.isFunctionPointer(res.address, className) then
                    addr = explorer.readPointer(res.address - (isx64 and 0x10 or 0x8))
                    break
                end
            end
            if addr > 0 then
                break
            end
        end
    end

    if addr == 0 then
        explorer.print("🔴 There is no valid pointer for " .. className)
        return
    end

    if explorer.libStart == 0 then
        explorer.getLib()
    end

    addr = addr - explorer.libStart

    explorer.print("🟢 Offset for " .. functionName .. ": " .. string.format('%X', addr))

    return addr
end

-- Find function offset and edit assembly
-- className should be specified to prevent finding wrong functions with the same name
function explorer.editFunction(className, functionName, patchedBytes, patchedBytesX32)
    local offs = explorer.getFunction(className, functionName)
    explorer.patchLib(offs, offs, patchedBytes, patchedBytesX32)
end

function explorer.isFunctionPointer(address, className)
    local t = {}
    t[1] = {}
    t[1].address = address - (isx64 and 0x10 or 0x8)
    t[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
    gg.clearResults()
    gg.loadResults(t)
    t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_EXECUTABLE)
    if t[1] == nil then
        return false
    end

    t[1].address = address - (isx64 and 0x8 or 0x4)
    t[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
    gg.clearResults()
    gg.loadResults(t)
    t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_EXECUTABLE)
    if t[1] == nil then
        return false
    end

    t[1].address = address + (isx64 and 0x8 or 0x4)
    t[1].flags = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
    gg.clearResults()
    gg.loadResults(t)
    t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_WRITABLE)
    if t[1] == nil then
        return false
    end
    if className ~= nil then
        currAddr =
            explorer.readPointer(explorer.readPointer(address + (isx64 and 0x8 or 0x4)) + (isx64 and 0x10 or 0x8))
        classBytes = gg.bytes(className, "UTF-8")
        for k, v in pairs(classBytes) do
            if (v ~= explorer.readByte(currAddr)) then
                return false
            end
            currAddr = currAddr + 0x1
        end
    end
    return true
end

function explorer.readValue(addr, type)
    local t = {}
    t[1] = {}
    t[1].address = addr
    t[1].flags = type

    t = gg.getValues(t)

    return t[1].value
end

function explorer.readByte(addr)
    return explorer.readValue(addr, gg.TYPE_BYTE)
end

function explorer.readShort(addr)
    return explorer.readValue(addr, gg.TYPE_WORD)
end

function explorer.readInt(addr)
    return explorer.readValue(addr, gg.TYPE_DWORD)
end

-- returns pointed address
function explorer.readPointer(addr)
    return explorer.readValue(addr, isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD)
end

-- Print debug messages
function explorer.print(str)
    if explorer.debug then
        print(str)
    end
end

function explorer.readString(addr)
    -- Unity uses UTF-16LE
    if (type(addr) ~= 'number') then
        explorer.print('🔴 Wrong argument in explorer.readString: expected number, got ' .. type(addr))
        return nil
    end
    local len = explorer.readInt(addr + (isx64 and 0x10 or 0x8))
    if len > explorer.maxStringLength then
        return nil
    end
    local str = ""
    for i = 1, len, 1 do
        local c = explorer.readShort(addr + (isx64 and 0x14 or 0xC) + (2 * (i - 1)))
        if (c > -1 and c < 129) then
            str = str .. string.char(c) -- works from 0 to 128
        else
            if (alphabet[c] ~= nil) then
                str = str .. alphabet[c]
            else
                explorer.print('🟡 Warn: unrecognised character ' .. c .. '. Consider adding it to the alphabet')
            end
        end
    end
    return str
end

function explorer.setAlphabet(str)
    if (str == nil or not (type(str) == 'string')) then
        explorer.print('🔴 Wrong argument in explorer.setAlphabet: expected string, got ' .. type(str))
        return
    end
    alphabet = {}
    str:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c)
        local bytes = gg.bytes(c, 'UTF-16LE')
        local utf8Chars = ''
        for k, v in pairs(bytes) do
            utf8Chars = utf8Chars .. string.char(v)
        end
        local short = string.unpack("<i2", utf8Chars)
        alphabet[short] = c
    end)
end

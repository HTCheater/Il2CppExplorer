--https://github.com/HTCheater/Il2CppExplorer
if (ht == nil or type(ht) ~= table) then
    ht = {}
end
--Output debug messages
if ht.debug == nil then
    ht["debug"] = false
end
--Let people know you are using my framework :D
if (ht.printAdvert == nil) then
    ht["printAdvert"] = true
end
--Exit if selected process isn't Unity game
if (ht.exitOnNotUnityGame == nil) then
    ht["exitOnNotUnityGame"] = true
end
--Contains start address of libil2cpp.so once either ht.getLib or ht.patchLib or ht.editFunction was called
ht["libStart"] = 0x0
--Contains end address of libil2cpp.so once either ht.getLib or ht.patchLib or ht.editFunction was called
ht["libEnd"] = 0x0

if ht.printAdvert then
    print("✨Made with Ill2CppExplorer by HTCheater")
end

if (ht.exitOnNotUnityGame and #gg.getRangesList("global-metadata.dat") < 1) then
    print("❌Please, select Unity game")
    os.exit()
end

--String utils, feel free to use in your own script.

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

--some functions
local isx64 = gg.getTargetInfo().x64
local metadata = gg.getRangesList("global-metadata.dat")

if #metadata > 0 then
    metadata = metadata[1]
end

function ht.setAllRanges()
    gg.setRanges(
        gg.REGION_JAVA_HEAP | gg.REGION_C_HEAP | gg.REGION_C_ALLOC | gg.REGION_C_DATA | gg.REGION_C_BSS |
            gg.REGION_PPSSPP |
            gg.REGION_ANONYMOUS |
            gg.REGION_JAVA |
            gg.REGION_STACK |
            gg.REGION_ASHMEM |
            gg.REGION_VIDEO |
            gg.REGION_OTHER |
            gg.REGION_BAD |
            gg.REGION_CODE_APP |
            gg.REGION_CODE_SYS
    )
end

--Check wether the metadata class name pointer is suitable to find instances. Returns boolean.

function ht.isClassPointer(address)
    t = {}
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

--Get instances of class. Returns table with search results or empty table.

function ht.getInstances(classname)
    ht.setAllRanges()
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
            print("Can't find " .. classname .. " in metadata")
        end
        local r = {}
        return r
    end
    local r = {}
    r[1] = gg.getResults(2)[2]

    local addr = 0x0
    for k, v in pairs(gg.getRangesList("libc_malloc")) do
        gg.clearResults()
        gg.searchNumber(
            string.format("%X", r[1].address) .. "h",
            isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD,
            false,
            gg.SIGN_EQUAL,
            v.start,
            v["end"],
            0
        )

        local results = gg.getResults(100)
        gg.clearResults()

        for i, res in ipairs(results) do
            if ht.isClassPointer(res.address) == true then
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
            print("There is no valid pointer for " .. classname)
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
    if gg.getResultsCount == 0 and debug then
        print("There are no instances for the " .. classname .. ", try to load the class first")
    end
    gg.clearResults()
    return r
end

--Patch libil2cpp.so;
--patchedBytes is a table which contains patches that can be either a dword number or a string containing opcode
--or a string containig hex (must start with "h" and contain only 4 bytes each).
--Consider using ht.editFunction

function ht.patchLib(offset, offsetX32, patchedBytes, patchedBytesX32)
    gg.clearResults()
    if ht.libStart == 0 then
        ht.getLib()
    end
    local patch = {}
    if not isx64 then
        patchedBytes = patchedBytesX32
        offset = offsetX32
    end
    if (patchedBytes == nil or offset == nil) then
        ht.print("❌There is no valid patch for current architecture")
        return
    end
    local currAddress = ht.libStart + offset
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

--Call ht.getLib in case you need access to ht.libStart or ht.libEnd.

function ht.getLib()
    local libil2cpp
    if gg.getRangesList("libil2cpp.so")[1] ~= nil then
        ht.libStart = gg.getRangesList("libil2cpp.so")[1].start
        ht.libEnd = gg.getRangesList("libil2cpp.so")[1]["end"]
    else
        local apkconf = gg.getRangesList("/data/app/*split_config.arm*.apk")
        local k = 1
        libs = {}
        for i, lib in ipairs(apkconf) do
            if lib["state"] == "Xa" and lib["type"] == "r-xp" then
                libs[k] = lib
                k = k + 1
            end
        end

        local diff = 0

        for i, lib in ipairs(libs) do
            local t = {}
            t[1] = {}
            t[1].address = lib["start"]
            t[1].flags = gg.TYPE_BYTE
            t[2] = {}
            t[2].address = lib["start"] + 1
            t[2].flags = gg.TYPE_BYTE
            t[3] = {}
            t[3].address = lib["start"] + 2
            t[3].flags = gg.TYPE_BYTE
            t[4] = {}
            t[4].address = lib["start"] + 3
            t[4].flags = gg.TYPE_BYTE
            local r = gg.getValues(t)
            if r[1]["value"] == 127 and r[2]["value"] == 69 and r[3]["value"] == 76 and r[4]["value"] == 70 then
                if (lib["end"] - lib["start"]) > diff then
                    diff = (lib["end"] - lib["start"]) + 0.0
                    libil2cpp = lib
                end
            end
        end
        ht.libStart = libil2cpp.start
        ht.libEnd = libil2cpp["end"]
    end
    if ht.libStart == 0x0 then
        ht.print("Failed to get libil2cpp.so address, try entering the game first")
    end
end

--Get field value in instance from instances table specified by index

function ht.getFieldValue(instancesTable, offset, offsetX32, type, index)
    if instancesTable == nil then
        ht.print("❌Instances table is nil")
        return nil
    end
    local instance = instancesTable[index]
    if instance == nil then
        ht.print("❌Wrong index (no results found?)")
        return nil
    end
    if not isx64 then
        offset = offsetX32
    end
    if offset == nil then
        ht.print("❌Offset for this architecture is not specified")
        return nil
    end
    return ht.readValue(instance.address + offset, type)
end

--Edit field value in instance from instances table specified by index

function ht.editFieldValue(instancesTable, offset, offsetX32, type, index, value)
    if instancesTable == nil then
        ht.print("❌Instances table is nil")
        return nil
    end
    local instance = instancesTable[index]
    if instance == nil then
        ht.print("❌Wrong index (no results found?)")
        return nil
    end
    if not isx64 then
        offset = offsetX32
    end
    if offset == nil then
        ht.print("❌Offset for this architecture is not specified")
        return nil
    end

    local t = {}
    t[1] = {}
    t[1].address = instance.address + offset
    t[1].flags = type
    t[1].value = value
    gg.setValues(t)
end

--Find function offset and edit assembly
--className should be specified to prevent finding wrong functions with the same name
function ht.editFunction(className, functionName, patchedBytes, patchedBytesX32)
    ht.setAllRanges()
    gg.clearResults()
    local stringBytes = gg.bytes(functionName, "UTF-8")
    local searchStr = "0"
    for k, v in ipairs(stringBytes) do
        searchStr = searchStr .. "; " .. v
    end
    searchStr = searchStr .. "; 0::" .. (2 + #stringBytes)

    gg.searchNumber(
        searchStr,
        gg.TYPE_BYTE,
        false,
        gg.SIGN_EQUAL,
        metadata.start,
        metadata["end"],
        (className == nil) and 2 or nil
    )
    gg.refineNumber("0; " .. stringBytes[1], gg.TYPE_BYTE)
    gg.refineNumber(stringBytes[1], gg.TYPE_BYTE)

    if gg.getResultsCount() == 0 then
        ht.print("Can't find " .. functionName .. " in metadata")
        local r = {}
        return r
    end

    local addr = 0x0

    for index, result in pairs(gg.getResults(100000)) do
        for k, v in pairs(gg.getRangesList("libc_malloc")) do
            gg.clearResults()
            gg.searchNumber(
                string.format("%X", result.address) .. "h",
                isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD,
                false,
                gg.SIGN_EQUAL,
                v.start,
                v["end"],
                0
            )

            local results = gg.getResults(100)
            gg.clearResults()

            for i, res in ipairs(results) do
                if ht.isFunctionPointer(res.address, className) then
                    addr = ht.readPointer(res.address - (isx64 and 0x10 or 0x8))
                    break
                end
            end
            if addr > 0 then
                break
            end
        end
    end

    if addr == 0 then
        ht.print("There is no valid pointer for " .. className)
        return
    end

    if ht.libStart == 0 then
        ht.getLib()
    end

    addr = addr - ht.libStart

    ht.patchLib(addr, addr, patchedBytes, patchedBytesX32)
end

function ht.isFunctionPointer(address, className)
    t = {}
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
        currAddr = ht.readPointer(ht.readPointer(address + (isx64 and 0x8 or 0x4)) + (isx64 and 0x10 or 0x8))
        classBytes = gg.bytes(className, "UTF-8")
        for k, v in pairs(classBytes) do
            if (v ~= ht.readByte(currAddr)) then
                return false
            end
            currAddr = currAddr + 0x1
        end
    end
    return true
end

function ht.readValue(addr, type)
    local t = {}
    t[1] = {}
    t[1].address = addr
    t[1].flags = type

    t = gg.getValues(t)

    return t[1].value
end

--returns dword value
function ht.readInt(addr)
    return ht.readValue(addr, gg.TYPE_DWORD)
end

--returns byte value
function ht.readByte(addr)
    return ht.readValue(addr, gg.TYPE_BYTE)
end

--returns pointed address
function ht.readPointer(addr)
    return ht.readValue(addr, isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD)
end

--Print debug messages
function ht.print(str)
    if ht.debug then
        print(str)
    end
end

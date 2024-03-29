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
local libStart = 0x0
explorer.maxStringLength = 1000
local alphabet = {}

if explorer.printAdvert then
	print('✨ Made with Il2CppExplorer by HTCheater')
end

if (explorer.exitOnNotUnityGame and #gg.getRangesList('global-metadata.dat') < 1) then
	print('🔴 Please, select Unity game')
	os.exit()
end

-- String utils, feel free to use in your own script.

string.startsWith = function(self, str)
	return self:find('^' .. str) ~= nil
end

string.endsWith = function(str, ending)
	return ending == '' or str:sub(-(#ending)) == ending
end

string.toUpper = function(str)
	res, c = str:gsub('^%l', string.upper)
	return res
end

string.removeEnd = function(str, rem)
	return (str:gsub('^(.-)' .. rem .. '$', '%1'))
end

string.removeStart = function(str, rem)
	return (str:gsub('^' .. rem .. '(.-)$', '%1'))
end

local isx64 = gg.getTargetInfo().x64
local metadata = gg.getRangesList('global-metadata.dat')
local TYPE_PTR = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD

if #metadata > 0 then
	metadata = metadata[1]
end

function explorer.setAllRanges()
	gg.setRanges(gg.REGION_JAVA_HEAP | gg.REGION_C_HEAP | gg.REGION_C_ALLOC | gg.REGION_C_DATA | gg.REGION_C_BSS | gg.REGION_PPSSPP |
					             gg.REGION_ANONYMOUS | gg.REGION_JAVA | gg.REGION_STACK | gg.REGION_ASHMEM | gg.REGION_VIDEO | gg.REGION_OTHER |
					             gg.REGION_BAD | gg.REGION_CODE_APP | gg.REGION_CODE_SYS)
end

-- Check wether the metadata class name pointer is suitable to find instances. Returns boolean.
-- Use it if you know what you are doing

function explorer.isClassPointer(address)
	local t = {}
	t[1] = {}
	t[1].address = address - (isx64 and 0x10 or 0x8)
	t[1].flags = TYPE_PTR
	gg.clearResults()
	gg.loadResults(t)
	t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_WRITABLE)
	if t[1] == nil then
		return false
	end

	t[1].address = address - (isx64 and 0x8 or 0x4)
	t[1].flags = TYPE_PTR
	gg.clearResults()
	gg.loadResults(t)
	t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_NO)
	if t[1] == nil then
		return false
	end

	t[1].address = address + (isx64 and 0x8 or 0x4)
	t[1].flags = TYPE_PTR
	gg.clearResults()
	gg.loadResults(t)
	t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_READ_ONLY)
	if t[1] == nil then
		return false
	end
	return true
end

function explorer.getClassMetadataPtr(classname)
	if type(classname) ~= 'string' then
		explorer.print('🔴 explorer.getClassMetadataPtr: expected string for parameter classname, got ' .. type(classname))
		return {}
	end

	explorer.setAllRanges()
	gg.clearResults()
	local stringBytes = gg.bytes(classname, 'UTF-8')
	local searchStr = '0'
	for k, v in ipairs(stringBytes) do
		searchStr = searchStr .. '; ' .. v
	end
	searchStr = searchStr .. '; 0::' .. (2 + #stringBytes)

	gg.searchNumber(searchStr, gg.TYPE_BYTE, false, gg.SIGN_EQUAL, metadata.start, metadata['end'], 2)

	if gg.getResultsCount() < 2 then
		if debug then
			print('🔴 explorer.getClassMetadataPtr: can\'t find ' .. classname .. ' in metadata')
		end
		return 0
	end
	return gg.getResults(2)[2].address
end

function explorer.getAllocatedClassPtr(metadataPtr)
	local addr = 0x0
	for k, v in pairs(gg.getRangesList('libc_malloc')) do
		gg.clearResults()
		gg.searchNumber(string.format('%X', metadataPtr) .. 'h', TYPE_PTR, false, gg.SIGN_EQUAL, v.start, v['end'], 0)

		local results = gg.getResults(100000)
		gg.clearResults()

		for i, res in ipairs(results) do
			if explorer.isClassPointer(res.address) then
				addr = res.address - (isx64 and 0x10 or 0x8)
				break
			end
		end
		if addr > 0 then
			break
		end
	end
	if (debug and (addr == 0)) then
		explorer.print('🔴 explorer.getAllocatedClassPtr: there is no valid pointer for ' .. string.format('%X', metadataPtr))
	end
	return addr
end

-- Get instances of class. Returns table with search results or empty table.

function explorer.getInstances(className)
	local mPtr = explorer.getClassMetadataPtr(className)
	if ((mPtr == 0) or (mPtr == nil)) then
		return {}
	end
	local allocPtr = explorer.getAllocatedClassPtr(mPtr)
	if (allocPtr == 0) then
		return {}
	end
	gg.setRanges(gg.REGION_ANONYMOUS)
	gg.clearResults()
	local r = {}
	r[1] = {}
	r[1].address = allocPtr
	r[1].flags = TYPE_PTR
	gg.loadResults(r)
	gg.searchPointer(0)
	r = gg.getResults(100000)
	if ((#r == 0) and debug) then
		explorer.print('🔴 explorer.getInstances: there are no instances for the ' .. classname .. ', try to load the class first')
	end
	gg.clearResults()
	return r
end

-- Patch libil2cpp.so;
-- patchedBytes is a table which contains patches that can be either a dword number or a string containing opcode
-- or a string containig hex (must start with "h" and contain only 4 bytes each).
-- Consider using explorer.editFunction
-- You shouldn't use it in your scripts

function explorer.patchLib(offset, offsetX32, patchedBytes, patchedBytesX32)
	gg.clearResults()
	if libStart == 0 then
		explorer.getLib()
	end
	local patch = {}
	if not isx64 then
		patchedBytes = patchedBytesX32
		offset = offsetX32
	end
	if (patchedBytes == nil or offset == nil) then
		explorer.print('🔴 explorer.patchLib: there is no valid patch for current architecture')
		return
	end
	local currAddress = libStart + offset
	for k, v in ipairs(patchedBytes) do
		local t = {}
		t[1] = {}
		t[1].address = currAddress
		t[1].flags = gg.TYPE_DWORD
		if type(v) == 'number' then
			t[1].value = v
			gg.setValues(t)
		end
		if type(v) == 'string' then
			if v:startsWith('h') then
				t[1].value = v
				gg.setValues(t)
			else
				t[1].value = (isx64 and '~A8 ' or '~A ') .. v
				gg.setValues(t)
			end
		end
		currAddress = currAddress + 4
	end
end

function explorer.getLibStart()
	return libStart
end

-- Call explorer.getLib in case you need access to libStart

function explorer.getLib()
	explorer.setAllRanges()
	local libil2cpp
	if gg.getRangesList('libil2cpp.so')[1] ~= nil then
		libStart = gg.getRangesList('libil2cpp.so')[1].start
		return
	end

	local ranges = gg.getRangesList('bionic_alloc_small_objects')
	for i, range in pairs(ranges) do
		gg.searchNumber('47;108;105;98;105;108;50;99;112;112;46;115;111;0::14', gg.TYPE_BYTE, false, gg.SIGN_EQUAL, range['start'],
		                range['end'], 1)
		gg.refineNumber('47', gg.TYPE_BYTE)
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
			for k, v in pairs(gg.getRangesList('linker_alloc')) do
				gg.clearResults()
				gg.loadResults(t)
				gg.searchPointer(0, v['start'], v['end'])
				for index, res in pairs(gg.getResults(1)) do
					local t = {}
					t[1] = {}
					t[1].address = res.address - (isx64 and 0x8 or 0x4)
					t[1].flags = TYPE_PTR
					gg.loadResults(t)
					local pointers = gg.getResults(1, 0, nil, nil, nil, nil, nil, nil, gg.POINTER_EXECUTABLE)
					if #pointers ~= 0 then
						libStart = explorer.readPointer(t[1].address)
						break
					end
				end
			end
			break
		end
	end
	if libStart == 0x0 then
		explorer.print('🔴 explorer.getLib: failed to get libil2cpp.so address, try entering the game first')
	end
end

-- Get field value in instance from instances table specified by index

function explorer.getField(instance, offset, offsetX32, valueType)
	if type(instance) ~= 'table' then
		explorer.print('🔴 explorer.getField: expected table for parameter instance, got ' .. type(instance))
		return nil
	end
	if type(instance.address) ~= 'number' then
		explorer.print('🔴 explorer.getField: expected number for instance.address, got ' .. type(instance.address))
		return nil
	end
	if type(valueType) ~= 'number' then
		explorer.print('🔴 explorer.getField: expected number for valueType, got ' .. type(valueType))
		return nil
	end
	if not isx64 then
		offset = offsetX32
	end
	if offset == nil then
		explorer.print('🔴 explorer.getField: offset for this architecture is not specified')
		return nil
	end
	return explorer.readValue(instance.address + offset, valueType)
end

-- Edit field value in instance from instances table specified by index

function explorer.editField(instance, offset, offsetX32, valueType, value)
	if type(instance) ~= 'table' then
		explorer.print('🔴 explorer.editField: expected table for parameter instance, got ' .. type(instance))
		return
	end
	if type(instance.address) ~= 'number' then
		explorer.print('🔴 explorer.editField: expected number for instance.address, got ' .. type(instance.address))
		return
	end
	if type(valueType) ~= 'number' then
		explorer.print('🔴 explorer.editField: expected number for parameter valueType, got ' .. type(valueType))
		return
	end
	if type(value) ~= 'number' then
		explorer.print('🔴 explorer.editField: expected number for parameter value, got ' .. type(value))
		return
	end
	if not isx64 then
		offset = offsetX32
	end
	if offset == nil then
		explorer.print('🔴 explorer.editField: offset for this architecture is not specified')
		return
	end

	local t = {}
	t[1] = {}
	t[1].address = instance.address + offset
	t[1].flags = valueType
	t[1].value = value
	gg.setValues(t)
end

function explorer.getFunction(className, functionName)
	if type(functionName) ~= 'string' then
		explorer.print('🔴 explorer.getFunction: expected string for parameter functionName, got ' .. type(functionName))
		return nil
	end
	if ((type(className) ~= 'nil') and (type(className) ~= 'string')) then
		explorer.print('🔴 explorer.getFunction: expected string for parameter className, got ' .. type(className))
		return nil
	end
	explorer.setAllRanges()
	gg.clearResults()
	local stringBytes = gg.bytes(functionName, 'UTF-8')
	local searchStr = '0'
	for k, v in ipairs(stringBytes) do
		searchStr = searchStr .. '; ' .. v
	end
	searchStr = searchStr .. '; 0::' .. (2 + #stringBytes)

	gg.searchNumber(searchStr, gg.TYPE_BYTE, false, gg.SIGN_EQUAL, metadata.start, metadata['end'], (className == nil) and 2 or nil)
	gg.refineNumber('0; ' .. stringBytes[1], gg.TYPE_BYTE)
	gg.refineNumber(stringBytes[1], gg.TYPE_BYTE)

	if gg.getResultsCount() == 0 then
		explorer.print('Can\'t find ' .. functionName .. ' in metadata')
		local r = {}
		return r
	end

	local addr = 0x0

	for index, result in pairs(gg.getResults(100000)) do
		for k, v in pairs(gg.getRangesList('libc_malloc')) do
			gg.clearResults()
			gg.searchNumber(string.format('%X', result.address) .. 'h', TYPE_PTR, false, gg.SIGN_EQUAL, v.start, v['end'], 0)

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
		explorer.print('🔴 explorer.getFunction: there is no valid pointer for ' .. functionName ..
						               ((className == nil) and '' or (' in ' .. className)))
		return nil
	end

	if libStart == 0 then
		explorer.getLib()
	end

	addr = addr - libStart

	explorer.print('🟢 explorer.getFunction: offset for ' .. functionName .. ': ' .. string.format('%X', addr))

	return addr
end

-- Find function offset and edit assembly
-- className should be specified to prevent finding wrong functions with the same name
function explorer.editFunction(className, functionName, patchedBytes, patchedBytesX32)
	if ((type(className) ~= 'nil') and (type(className) ~= 'string')) then
		explorer.print('🔴 explorer.editFunction: expected string or nil for parameter className, got ' .. type(className))
		return
	end
	if type(functionName) ~= 'string' then
		explorer.print('🔴 explorer.editFunction: expected string for parameter functionName, got ' .. type(functionName))
		return
	end
	local offs = explorer.getFunction(className, functionName)
	if (offs == nil) then
		return
	end
	explorer.patchLib(offs, offs, patchedBytes, patchedBytesX32)
end

function explorer.isFunctionPointer(address, className)
	local t = {}
	t[1] = {}
	t[1].address = address - (isx64 and 0x10 or 0x8)
	t[1].flags = TYPE_PTR
	gg.clearResults()
	gg.loadResults(t)
	t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_EXECUTABLE)
	if t[1] == nil then
		return false
	end

	t[1].address = address - (isx64 and 0x8 or 0x4)
	t[1].flags = TYPE_PTR
	gg.clearResults()
	gg.loadResults(t)
	t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_EXECUTABLE)
	if t[1] == nil then
		return false
	end

	t[1].address = address + (isx64 and 0x8 or 0x4)
	t[1].flags = TYPE_PTR
	gg.clearResults()
	gg.loadResults(t)
	t = gg.getResults(1, nil, nil, nil, nil, nil, nil, nil, gg.POINTER_WRITABLE)
	if t[1] == nil then
		return false
	end
	if className ~= nil then
		currAddr = explorer.readPointer(explorer.readPointer(address + (isx64 and 0x8 or 0x4)) + (isx64 and 0x10 or 0x8))
		classBytes = gg.bytes(className, 'UTF-8')
		for k, v in pairs(classBytes) do
			if (v ~= explorer.readByte(currAddr)) then
				return false
			end
			currAddr = currAddr + 0x1
		end
	end
	return true
end

function explorer.readValue(addr, valueType)
	if type(addr) ~= 'number' then
		explorer.print('🔴 explorer.readValue: expected number for parameter addr, got ' .. type(addr))
		return
	end

	if type(valueType) ~= 'number' then
		explorer.print('🔴 explorer.readValue: expected number for parameter valueType, got ' .. type(valueType))
		return
	end
	local t = {}
	t[1] = {}
	t[1].address = addr
	t[1].flags = valueType

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
	return explorer.readValue(addr, TYPE_PTR)
end

-- Print debug messages
function explorer.print(str)
	if explorer.debug then
		print(str)
	end
end

function explorer.readString(addr)
	-- Unity uses UTF-16LE
	if type(addr) ~= 'number' then
		explorer.print('🔴 explorer.readString: wrong argument in explorer.readString: expected number, got ' .. type(addr))
		return ''
	end
	local len = explorer.readInt(addr + (isx64 and 0x10 or 0x8))
	if len > explorer.maxStringLength then
		return ''
	end
	local strTable = {}
	for i = 1, len do
		strTable[i] = {}
		strTable[i].address = addr + (isx64 and 0x14 or 0xC) + (2 * (i - 1))
		strTable[i].flags = gg.TYPE_WORD
	end
	--reading all string at once is faster than reading characters one by one
	strTable = gg.getValues(strTable)
	local str = ''
	for k, v in ipairs(strTable) do
		local c = v.value
		if (c > -1 and c < 129) then
			str = str .. string.char(c) -- works from 0 to 128
		else
			if (alphabet[c] ~= nil) then
				str = str .. alphabet[c]
			else
				explorer.print('🟡 explorer.readString: unrecognised character ' .. c .. '. Consider adding it to the alphabet')
			end
		end
	end
	return str
end

function explorer.setAlphabet(str)
	if type(str) ~= 'string' then
		explorer.print('🔴 explorer.setAlphabet: wrong argument in explorer.setAlphabet: expected string, got ' .. type(str))
		return
	end
	alphabet = {}
	str:gsub('[%z\1-\127\194-\244][\128-\191]*', function(c)
		local bytes = gg.bytes(c, 'UTF-16LE')
		local utf8Chars = ''
		for k, v in pairs(bytes) do
			utf8Chars = utf8Chars .. string.char(v)
		end
		local short = string.unpack('<i2', utf8Chars)
		alphabet[short] = c
	end)
end

memory = {}
local currentAddress = nil
local freeSpace = nil
local pages = {}
local pageIndex = 0

-- in case someone needs access to this fields

function memory.getcurrentAddressess()
	return currAddr
end

function memory.getFreeSpace()
	return freeSpace
end

function memory.getPages()
	return pages
end

function memory.alloc()
	if (pageIndex < #pages) then
		pageIndex = pageIndex + 1
		freeSpace = 4096
		currentAddress = pages[pageIndex]
		explorer.print('🟢 memory.alloc: reused page ' .. string.format('%X', currentAddress))
		return pages[pageIndex]
	end
	local ptr = gg.allocatePage(gg.PROT_READ | gg.PROT_WRITE | gg.PROT_EXEC)
	currentAddress = ptr
	freeSpace = 4096
	pageIndex = pageIndex + 1
	pages[pageIndex] = ptr
	explorer.print('🟢 memory.alloc: allocated page ' .. string.format('%X', currentAddress))
	return ptr
end

function memory.write(t)
	if type(t) ~= 'table' then
		explorer.print('🔴 memory.write: expected table for first parameter, got ' .. type(t))
		return false
	end
	if #t > 4096 then
		explorer.print('🔴 memory.write: table size cannot be over 4096, table size ' .. #t)
		return false
	end

	local spaceNeeded = 0
	for k, v in pairs(t) do
		if (v.flags == nil) then
			v.flags = (math.type(v.value) == 'float') and gg.TYPE_FLOAT or gg.TYPE_DWORD
			t[k] = v
		end
		spaceNeeded = spaceNeeded + v.flags
	end

	if spaceNeeded > 4096 then
		explorer.print('🔴 memory.write: not enough free space in page (4096 bytes) to write the whole table with size ' ..
						               spaceNeeded .. ' bytes')
		return false
	end
	if (spaceNeeded > freeSpace) then
		memory.alloc()
	end

	if #t > 4096 then
		explorer.print('🔴 memory.write: not enough free space to write the whole table')
		return false
	end

	for k, v in ipairs(t) do
		v.address = currentAddress
		t[k] = v
		currentAddress = currentAddress + v.flags
		freeSpace = freeSpace - v.flags
	end
	local res = gg.setValues(t)
	if type(res) ~= 'boolean' then
		explorer.print('🔴 memory.write: error while writing')
		explorer.print(res)
		return false
	end
	explorer.print('🟢 memory.write: free sapce left ' .. freeSpace)
	return true
end

-- it doesn't actually *free* memory but let reuse already allocated pages
function memory.free()
	if (page[0] == nil) then
		return
	end
	currAddr = page[0]
end

# Il2CppExplorer

Il2CppExplorer is a [Game Guardian](https://gameguardian.net/download) framework which is designed to make script creation for games built with Unity easier. To get function and class names and more get [Il2CppDumper](https://github.com/Perfare/Il2CppDumper)

## Installation

You can download the Il2CppExplorer.lua and write your code after mine or use this code in your script:

```lua
--With simple integrity check
function init()
    local file = io.open(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua', 'r')

    if file == nil then
        response = gg.makeRequest('https://github.com/HTCheater/Il2CppExplorer/releases/latest/download/Il2CppExplorer.lua')
        if response.code ~= 200 then
            print('Check internet connection')
            os.exit()
        end
        file = io.open(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua', 'w')
        file:write(response.content)
    else
        checksumResponse = gg.makeRequest('https://github.com/HTCheater/Il2CppExplorer/releases/latest/download/Il2CppExplorer.checksum')
        if checksumResponse.code ~= 200 then
            print('Check internet connection')
            os.exit()
        end
        file:close()
        file = io.open(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua', 'rb')
        local size = file:seek('end')
        local checksum = 0
        file:seek('set', 0)
        while file:seek() < size do
            checksum = checksum + file:read(1):byte()
        end
        if (checksumResponse.content ~= tostring(checksum)) then
            os.exit()
        end
    end
    file:close()

    framework = loadfile(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua')
    framework()
end

init()
```

or if you don't want to check script integrity and recieve updates

```lua
--Without simple integrity check
function init()
    local file = io.open(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua', 'r')

    if file == nil then
        response = gg.makeRequest('https://github.com/HTCheater/Il2CppExplorer/releases/latest/download/Il2CppExplorer.lua')
        if response.code ~= 200 then
            print('Check internet connection')
            os.exit()
        end
        file = io.open(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua', 'w')
        file:write(response.content)
        file:close()
    end

    framework = loadfile(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua')
    framework()
end

init()
```

## Usage

### Fields
#### ht.debug
Control debug messages output, recommended to set value to true if you are developing script.
Default value is false
#### ht.printAdvert
Let user know what are you using :D.
Default value is true
#### ht.exitOnNotUnityGame
Exit if selected process isn't a Unity game, **it isn't recommended to change**.
Default value is true
#### ht.libStart
Get start address of libil2cpp.so, works with splitted apk
Default value is 0
#### ht.libEnd
Get end address of libil2cpp.so, doesn't support splitted apk well
Default value is 0
### General functions

#### ht.getInstances(className)
Returns a table with search results
**Parameters:**
1st parameter is a string
**Example:**
```lua
ht.getInstances('RGHand')
```
#### ht.getFieldValue(instancesTable, offset, offsetX32, type, index)
Get field's value
**Parameters:**
1st parameter is return value of ht.getInstances
2nd parameter is offset for 64-bit architecture
3rd parameter is offset for 32-bit architecture
4th parameter is one of gg.TYPE_\*
5th parameter is desired index
**Example:**
```lua
ht.getFieldValue(ht.getInstances('RGHand'), 0x10, 0x8, gg.TYPE_DWORD, 1)
```
#### ht.editFieldValue(instancesTable, offset, offsetX32, type, index, value)
Edit field's value
**Parameters:**
1st parameter is return value of ht.getInstances
2nd parameter is offset for 64-bit architecture
3rd parameter is offset for 32-bit architecture
4th parameter is one of gg.TYPE_\*
5th parameter is desired index
6th parameter is value to set
**Example:**
```lua
ht.editFieldValue(ht.getInstances('RGHand'), 0x10, 0x8, gg.TYPE_DWORD, 1, 99999)
```
#### ht.editFunction(className, functionName, patchedBytes, patchedBytesX32)
Edit assembly of function. You should specify className to prevent finding functions with the same name.
Put nil if you don't want to specify information for some architecture.
patchedBytes is a table that can contain either numbers or strings with opcodes or hex (must start with h)
**Parameters:**
1st parameter is name of class
2nd parameter is name of function located in the classs
3rd parameter is values table for 64-bit architecture
4th parameter is values table for 32-bit architecture
**Example:**
```lua
ht.editFunction(nil, 'get_hp', {'MOV X0, #99999', 'RET'})
```
#### ht.patchLib(offset, offsetX32, patchedBytes, patchedBytesX32)
CONSIDER USING ht.editFunction!
Edit assembly in libil2cpp.so.
Put nil if you don't want to specify information for some architecture.
patchedBytes is a table that can contain either numbers or strings with opcodes or hex (must start with h)
**Parameters:**
1st parameter is offset for 64-bit architecture
2nd parameter is offset for 32-bit architecture
3rd parameter is values table for 64-bit architecture
4th parameter is values table for 32-bit architecture
**Example:**
```lua
ht.patchLib(0x19CFDA, 0x9DFCA, {'RET'}, {'h1EFF2FE1'})
ht.patchLib(0x19CFDA, nil, {-698416192})
```
#### ht.isLibX64()
Get whether libil2cpp.so is 64-bit
#### ht.getLib()
Run if you need ht.libStart or ht.libEnd before you called either ht.editFunction or ht.isLibX64 or ht.patchLib

## Problems
32-bit support isn't ready yet

## Contributing
Pull requests are welcome.
# Il2CppExplorer

Il2CppExplorer is a [Game Guardian](https://gameguardian.net/download) framework which is designed to make script creation for games built with Unity easier. To get function and class names and more get [Il2CppDumper](https://github.com/Perfare/Il2CppDumper)

## Installation

Add this code to start of your script:

```lua
--With simple integrity check
--Don't change the path, so other scripts using framework can access it too
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
            os.remove(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua')
            init()
        end
    end
    file:close()

    framework = loadfile(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua')
    framework()
end

init()
```

or use this if you don't want to check script integrity and recieve updates

```lua
--Without simple integrity check
--Don't change the path, so other scripts using framework can access it too
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
    end
    file:close()

    framework = loadfile(gg.EXT_FILES_DIR .. '/Il2CppExplorer.lua')
    framework()
end

init()
```

# Usage

## Fields
### explorer.debug
Control debug messages output, recommended to set value to true if you make script.  
Default value is false
### explorer.printAdvert
Let user know what are you using :D. You need to set value before running the framework.  
Default value is true
### explorer.exitOnNotUnityGame
Exit if selected process isn't a Unity game, **it isn't recommended to change**. You need to set value before running framework  
Default value is true
### explorer.maxStringLength
Set maximum string length to read  
Default value is 1000
## General functions

### explorer.getInstances(className)
Find instances of class.
Returns a table with search results  
**Parameters:**  
1st parameter is a string  
**Example:**
```lua
explorer.getInstances('RGHand')
```
### explorer.getField(instance, offset, offsetX32, type)
Get field's value  
**Parameters:**  
1st parameter is return value of explorer.getInstances  
2nd parameter is offset for 64-bit architecture  
3rd parameter is offset for 32-bit architecture  
4th parameter is one of gg.TYPE_\*  
5th parameter is desired index  
**Example:**
```lua
explorer.getField(explorer.getInstances('RGHand')[1], 0x10, 0x8, gg.TYPE_DWORD)
```
### explorer.editField(instance, offset, offsetX32, type, value)
Edit field's value  
**Parameters:**  
1st parameter is return value of explorer.getInstances  
2nd parameter is offset for 64-bit architecture  
3rd parameter is offset for 32-bit architecture  
4th parameter is one of gg.TYPE_\*  
5th parameter is desired index  
6th parameter is value to set  
**Example:**
```lua
explorer.editField(explorer.getInstances('RGHand')[1], 0x10, 0x8, gg.TYPE_DWORD, 99999)
```
### explorer.getLibStart()
Get start address of libil2cpp.so. Returns 0 if [explorer.getLib](#explorergetLib) wasn't called or library isn't loaded
### explorer.editFunction(className, functionName, patchedBytes, patchedBytesX32)
Edit assembly of function. You should specify className to prevent finding functions with the same name. Target class must be loaded in memory to find offset (e. g. you are in menu, so you need to enter game at first place to modificate functions related to heal points ). If 1st parameter is nil, class name will be ignored (can boost search speed)  
You can put nil in 3rd or 4th parameter if you don't want to specify information for some architecture.  
patchedBytes is a table that can contain either numbers or strings with opcodes or strings with hex (must start with h)  
**Parameters:**  
1st parameter is name of class  
2nd parameter is name of function located in the classs  
3rd parameter is values table for 64-bit architecture  
4th parameter is values table for 32-bit architecture  
**Example:**
```lua
explorer.editFunction(nil, 'get_hp', {'MOV X0, #99999', 'RET'})
```
### explorer.getFunction(className, functionName)
Get function offset in il2cpp.so. You should specify className to prevent finding functions with the same name. Target class must be loaded in memory to find offset (e. g. you are in menu, so you need to enter game at first place to modificate functions related to heal points ). If 1st parameter is nil, class name will be ignored (can boost search speed)  
**Parameters:**  
1st parameter is name of class  
2nd parameter is name of function located in the classs  
3rd parameter is values table for 64-bit architecture  
4th parameter is values table for 32-bit architecture  
**Example:**
```lua
local off = explorer.getFunction(nil, 'get_hp')
print('get_hp offset: ' .. string.format('%X', off))
```

### explorer.patchLib(offset, offsetX32, patchedBytes, patchedBytesX32)
CONSIDER USING [explorer.editFunction](#explorereditfunctionclassname-functionname-patchedbytes-patchedbytesx32)! This function shouldn't be used in your script  
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
explorer.patchLib(0x19CFDA, 0x9DFCA, {'RET'}, {'h1EFF2FE1'})
explorer.patchLib(0x19CFDA, nil, {-698416192})
```
### explorer.getLib()
Run if you need [explorer.getLibStart](#explorergetLibStart) before you called either explorer.editFunction or explorer.patchLib

### explorer.readString(addr)
Read string at desired address. If string length is too large, returns empty string. You can modify maximum length in [explorer.maxStringLength](#explorermaxStringLength) field. If you want to read non-ASCII characters, you should check out [explorer.setAlphabet](#explorersetalphabetstr) 
**Parameters:**  
1st parameter is a pointer to String instance  
**Example:**  
```lua
local isx64 = gg.getTargetInfo().x64
local ptrLength = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
local instances = explorer.getInstances('ClassWithStringField')
local ptr = explorer.getField(instances, 0x10, 0x8, ptrLength, 1) --get pointed address
local str = explorer.readString(address)
print(str)
```

### explorer.setAlphabet(str)
To read read non-ASCII characters you need to call this function.  
**Parameters:**  
1st parameter is a string with all needed characters  
**Example:**  
```lua
local isx64 = gg.getTargetInfo().x64
local ptrLength = isx64 and gg.TYPE_QWORD or gg.TYPE_DWORD
local instances = explorer.getInstances('ClassWithStringField')
local ptr = explorer.getField(instances, 0x10, 0x8, ptrLength, 1) --get pointed address

--attemp to read string "бамбетель" without setting alphabet
--if explorer.debug is true, you will get warnings with missing UTF-16LE character codes
local str = explorer.readString(address)
print(str) --result is an empty string
explorer.setAlphabet('АаБбВвГгҐґДдЕеЄєЖжЗзИиІіЇїЙйКкЛлМмНнОоПпРрСсТтУуФфХхЦцЧчШшЩщьЮюЯя') --ASCII characters included automatically
--attemp to read "бамбетель" after setting alphabet
str = explorer.readString(address)
print(str) --result is "бамбетель"
```
# Contributing
Pull requests are welcome.

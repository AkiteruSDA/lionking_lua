-- Written by Akiteru with some code taken from Pasky13 and FractalFusion --

-- Small dirty edit by SBDWolf to make it work with the bsnesv115+ core (set memory domain to WRAM)

local function isGenesis()
    return gameinfo.getromhash() == "E37BF6813648EC5E8BDBD2F7070010F8";
end

-- Util functions --
local function read_u8(addr)
    return memory.read_u8(addr);
end
local function read_s8(addr)
    return memory.read_s8(addr);
end
local function read_u16(addr)
    return memory.read_u16_le(addr);
end
local function read_s16(addr)
    return memory.read_s16_le(addr);
end
local function isInactiveGeyser(addr)
    return read_u16(addr + 0x30) == 0xDC17;
end
local function isActiveGeyser(addr)
    return read_u16(addr + 0x30) == 0xD8CC;
end
if (isGenesis()) then
    read_u16 = function(addr)
        return memory.read_u16_be(addr);
    end
    read_s16 = function(addr)
        return memory.read_s16_be(addr);
    end
    isInactiveGeyser = function(addr)
        return read_u16(addr + 0x32) == 0x35F0;
    end
    isActiveGeyser = function(addr)
        return read_u16(addr + 0x32) == 0x3270;
    end
end
-- Util functions end--

-- Constants --
local LINKED_START = 0x76;
local LINKED_END = 0x78;
local LINKED_FREE = 0x7A;
local SIMBA_X = 0xB21B;
local SIMBA_SUB_X = 0xB248;
local SIMBA_Y = 0xB21D;
local SIMBA_SUB_Y = 0xB24A;
local SIMBA_SPD_X = 0xB24D;
local SIMBA_SUBSPD_X = 0xB24C;
local SIMBA_SPD_Y = 0xB251;
local SIMBA_SUBSPD_Y = 0xB250;
local CAMERA_X = 0xB29B;
local CAMERA_Y = 0xB29D;
local RNG_A = 0x1E00;
local RNG_B = 0x1E01;
local RNG_C = 0x1E02;
local RNG_ROLL = 0xC0CBBA;
if (isGenesis()) then
    -- Set correct addresses for Genesis
    LINKED_START = 0xC350;
    LINKED_END = 0xC352;
    LINKED_FREE = 0xC34E;
    SIMBA_X = 0x93D6;
    SIMBA_SUB_X = 0x9402;
    SIMBA_Y = 0x93D8;
    SIMBA_SUB_Y = 0x9404;
    SIMBA_SPD_X = 0x9406;
    SIMBA_SUBSPD_X = 0x9408;
    SIMBA_SPD_Y = 0x940A;
    SIMBA_SUBSPD_Y = 0x940C;
    CAMERA_X = 0x9456;
    CAMERA_Y = 0x9458;
    RNG_A = 0x81AF;
    RNG_B = 0x81AE;
    RNG_C = 0x81AD;
    RNG_ROLL = 0x000B28;
end
-- Constants end --

-- Set memory domain --
if (isGenesis()) then
    memory.usememorydomain("68K RAM");
else
    memory.usememorydomain("WRAM");
end
-- Set memory domain end --

-- Some helper function stuff --
local hexDigit = {"0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};
local xm;
local ym;
local xmOff;
local ymOff;
-- Some helper function stuff end --

-- (Partially) implement some 65C816 instructions for the RNG simulator --
local function lsr(val, mask)
    mask = mask or 0xFF;
    val = val & mask;
    local next = val >> 1;
    local carry = val & 1;
    return {next, carry};
end

local function rol(val, carry, mask)
    mask = mask or 0xFF;
    val = val & mask;
    local nextCarry = (val & 0x80) >> 7;
    local next = ((val << 1) & mask) | carry;
    return {next, nextCarry};
end

local function ror(val, carry, mask)
    mask = mask or 0xFF;
    val = val & mask;
    local nextCarry = val & 1;
    local next = (val >> 1) | (carry << 7);
    return {next, nextCarry};
end

local function sbc(acc, val, carry, mask)
    mask = mask or 0xFF;
    acc = acc & mask;
    val = val & mask;
    local nextCarry = 0;
    if acc >= val then
        nextCarry = 1;
    end
    local next = (acc - val - 1 + carry) & mask;
    return {next, nextCarry};
end
-- (Partially) implement some 65C816 instructions for the RNG simulator end --

local function scaler()
    xmOff = client.borderwidth();
    ymOff = client.borderheight();
    xm = (client.screenwidth() - 2 * xmOff) / 256;
    ym = (client.screenheight() - 2 * ymOff) / 224;
end

local function hexStr(val, length)
    length = length or 4;
    local str = "";
    for i = 1,length do
        str = hexDigit[val%16+1] .. str;
        val = math.floor(val / 16);
    end
    return str;
end

local LINE_HEIGHT = 10;

local function text(...)
    local arg = {...};
    local xPos = arg[1];
    local currY = arg[2];
    local lineCount = 0;
    for i = 3, #arg do
        gui.text(xPos * xm + xmOff, currY * ym + ymOff, arg[i]);
        lineCount = lineCount + 1;
        currY = arg[2] + LINE_HEIGHT * lineCount;
    end
    return LINE_HEIGHT * lineCount;
end

-- Simulates a roll of the RNG and returns the new seed, as well as the value that would be written to $a68e at the end of $c0cbba --
local function rngSim(a, b, c)
    a = a or read_u8(RNG_A);
    b = b or read_u8(RNG_B);
    c = c or read_u8(RNG_C);
    local acc = a;
    local temp = nil;
    local carry = nil;
    temp = lsr(acc); acc = temp[1]; carry = temp[2];
    temp = lsr(acc); acc = temp[1]; carry = temp[2];
    temp = rol(c, carry); c = temp[1]; carry = temp[2];
    temp = rol(b, carry); b = temp[1]; carry = temp[2];
    temp = sbc(acc, a, carry); acc = temp[1]; carry = temp[2];
    temp = lsr(acc); acc = temp[1]; carry = temp[2];
    temp = ror(a, carry); a = temp[1]; carry = temp[2];
    acc = a;
    acc = acc ~ b;
    local result = acc & 0xFF;
    return {a, b, c, result};
end

-- Simulate a calculation of a geyser countdown initialization value based on the given RNG value (found at $c2dc6b or so) --
local function geyserSim(val)
    return (val & 0xF) + 0x32;
end

local function printLinked()
    local x = 10;
    local y = 25;
    y = y + text(x, y, "Next free: " .. hexStr(read_u16(LINKED_FREE)));
    local addr = read_u16(LINKED_START);
    local i = 1;
    while addr ~= 0 do
        local extra = "";
        -- These cases are for geysers
        if isInactiveGeyser(addr) then
            extra = "(" .. read_u16(addr + 0x4C) .. " R, " .. hexStr(read_u16(addr + 0x46), 2) .. " CD)";
        elseif isActiveGeyser(addr) then
            extra = "(" .. read_u16(addr + 0x4C) .. " R, " .. hexStr(read_u16(addr + 0x46), 2) .. " CD: OK)";
        end
        y = y + text(x, y, i .. ": " .. hexStr(addr) .. " " .. extra);
        addr = read_u16(addr + 2);
        i = i + 1;
    end
end

local prevA = nil;
local prevB = nil;
local prevC = nil;
local rngCount = 0;
local rngCountStr = "";
local function printData()
    local x = 100;
    local y = 25;
    local a = read_u8(RNG_A);
    local b = read_u8(RNG_B);
    local c = read_u8(RNG_C);
    if prevA ~= nil and (a ~= prevA or b ~= prevB or c ~= prevC) then
        rngCountStr = "Num. rolls: " .. rngCount;
    end
    y = y + text(x, y, "Curr. seed: " .. hexStr(a, 2) .. " " .. hexStr(b, 2) .. " " .. hexStr(c, 2));
    text(x, y, "Nexts: ");
    x = x + 30;
    prevA = a;
    prevB = b;
    prevC = c;
    local geyserStr = "Geyser CDs: ";
    for i = 1,10 do
        local sim = rngSim(a, b, c);
        y = y + text(x, y, hexStr(sim[4], 2) .. " (Seed: " .. hexStr(sim[1], 2) .. " " .. hexStr(sim[2], 2) .. " " .. hexStr(sim[3], 2) .. ")");
        a = sim[1];
        b = sim[2];
        c = sim[3];
        if i <= 4 then
            geyserStr = geyserStr .. hexStr(geyserSim(sim[4]), 2);
            if i <= 3 then
                geyserStr = geyserStr .. ", ";
            end
        end
    end
    x = x - 20;
    if rngCountStr ~= "" then
        y = y + text(x, y, rngCountStr);
    end
    y = y + text(x, y, geyserStr);
    local simbaX = read_u16(SIMBA_X);
    local simbaSubX = read_u8(SIMBA_SUB_X);
    local simbaSpdX = read_s16(SIMBA_SPD_X);
    local simbaSubSpdX = read_u8(SIMBA_SUBSPD_X);
    local simbaY = read_u16(SIMBA_Y);
    local simbaSubY = read_u8(SIMBA_SUB_Y);
    local simbaSpdY = read_s16(SIMBA_SPD_Y);
    local simbaSubSpdY = read_u8(SIMBA_SUBSPD_Y);
    local cameraX = read_u16(CAMERA_X);
    local cameraY = read_u16(CAMERA_Y);
    y = y + text(
        x,
        y,
        "Simba X Pos: " .. simbaX .. ":" .. simbaSubX,
        "Simba X Spd: " .. simbaSpdX .. ":" .. simbaSubSpdX,
        "Simba Y Pos: " .. simbaY .. ":" .. simbaSubY,
        "Simba Y Spd: " .. simbaSpdY .. ":" .. simbaSubSpdY,
        "Camera X: " .. cameraX,
        "Camera Y: " .. cameraY
    );
    local pixel = "o o o o";
    if (simbaX % 4 == 0) then
        pixel = "x o o o";
    end
    if (simbaX % 4 == 1) then
        pixel = "o x o o";
    end
    if (simbaX % 4 == 2) then
        pixel = "o o x o";
    end
    if (simbaX % 4 == 3) then
        pixel = "o o o x";
    end
    y = y + text(x, y, "Pixel: " .. pixel);
end

local function resetCount()
    rngCount = 0;
end
local function incCount()
    rngCount = rngCount + 1;
end
event.onframestart(resetCount);
event.onmemoryexecute(incCount, RNG_ROLL);

while true do
    scaler();
    printLinked();
    printData();
    emu.frameadvance();
end

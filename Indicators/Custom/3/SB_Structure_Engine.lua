-- SB Structure Engine (Skeleton)
-- Standalone module extracted from SB_Full_Manual_Workflow_FXCM logic.

local NAME = "SB Structure Engine"

local source = nil
local state = {
    asiaHigh = nil,
    asiaLow = nil,
    hasSweep = false,
    hasBos = false,
    bosLevel = nil,
    fvgUpper = nil,
    fvgLower = nil,
}

local outAsiaH = nil
local outAsiaL = nil
local outBos = nil
local outFvgU = nil
local outFvgL = nil

local function parseHHMM(s)
    local h = tonumber(string.sub(s, 1, 2)) or 0
    local m = tonumber(string.sub(s, 3, 4)) or 0
    return h, m
end

local function parseSession(txt)
    local a, b = string.match(txt, "(%d%d%d%d)%-(%d%d%d%d)")
    return a or "0000", b or "2359"
end

local function minFromDate(t)
    local dt = core.dateToTable(t)
    return dt.hour * 60 + dt.min
end

local function inSession(t, sessionTxt)
    local s1, s2 = parseSession(sessionTxt)
    local h1, m1 = parseHHMM(s1)
    local h2, m2 = parseHHMM(s2)
    local x = h1 * 60 + m1
    local y = h2 * 60 + m2
    local v = minFromDate(t)
    if x <= y then
        return v >= x and v <= y
    end
    return (v >= x) or (v <= y)
end

function Init()
    indicator:name(NAME)
    indicator:description("Skeleton: session sweep / BOS / FVG state machine")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Sessions")
    indicator.parameters:addString("asiaSession", "Asia Session", "2000-0000")
end

function Prepare(nameOnly)
    source = instance.source
    instance:name(NAME)
    if nameOnly then
        return
    end

    local first = source:first()
    outAsiaH = instance:addStream("ASIAH", core.Line, "Asia High", "AsiaH", first)
    outAsiaL = instance:addStream("ASIAL", core.Line, "Asia Low", "AsiaL", first)
    outBos = instance:addStream("BOS", core.Line, "BOS", "BOS", first)
    outFvgU = instance:addStream("FVGU", core.Line, "FVG Upper", "FVGU", first)
    outFvgL = instance:addStream("FVGL", core.Line, "FVG Lower", "FVGL", first)
end

function Update(period, mode)
    if period < source:first() then
        return
    end

    local t = source:date(period)
    local h = source.high[period]
    local l = source.low[period]

    if inSession(t, instance.parameters.asiaSession) then
        state.asiaHigh = (state.asiaHigh == nil) and h or math.max(state.asiaHigh, h)
        state.asiaLow = (state.asiaLow == nil) and l or math.min(state.asiaLow, l)
    end

    -- TODO: migrate sweep/BOS/FVG detection logic.
    outAsiaH[period] = state.asiaHigh
    outAsiaL[period] = state.asiaLow
    outBos[period] = state.bosLevel
    outFvgU[period] = state.fvgUpper
    outFvgL[period] = state.fvgLower
end

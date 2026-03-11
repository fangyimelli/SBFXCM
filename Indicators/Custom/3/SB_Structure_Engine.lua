-- SB Structure Engine (Skeleton)
-- Standalone module extracted from SB_Full_Manual_Workflow_FXCM logic.

local NAME = "SB Structure Engine"

local STAGE = {
    IDLE = 0,
    ASIAREADY = 1,
    SWEPT = 2,
    BOS = 3,
    WAITFVG = 4,
    WAITMIT = 5,
    WAITRET = 6,
    BLUE1 = 7,
    BLUE2 = 8,
    BLUE3 = 9,
    DONE = 10,
}

local source = nil
local state = {
    stage = STAGE.IDLE,
    bias = 0,
    sweepDir = 0,
    bosDir = 0,
    asiaHigh = nil,
    asiaLow = nil,
    hasSweep = false,
    hasBos = false,
    bosLevel = nil,
    fvgUpper = nil,
    fvgLower = nil,
    gate = {
        gateReason = "init",
        gateType = "system",
        decisionTs = nil,
        decisionDayKey = nil,
    },
}

local outAsiaH = nil
local outAsiaL = nil
local outBos = nil
local outFvgU = nil
local outFvgL = nil

local function parseHHMM(hhmm)
    local digits = tostring(hhmm or "0000")
    if string.len(digits) < 4 then
        digits = string.rep("0", 4 - string.len(digits)) .. digits
    end
    local h = tonumber(string.sub(digits, 1, 2)) or 0
    local m = tonumber(string.sub(digits, 3, 4)) or 0
    h = math.min(23, math.max(0, h))
    m = math.min(59, math.max(0, m))
    return h, m
end

local function parseSession(sess)
    local a, b = string.match(tostring(sess or ""), "(%d%d%d%d)%-(%d%d%d%d)")
    return a or "0000", b or "2359"
end

local function inSession(ts, sess)
    local s1, s2 = parseSession(sess)
    local h1, m1 = parseHHMM(s1)
    local h2, m2 = parseHHMM(s2)
    local x = h1 * 60 + m1
    local y = h2 * 60 + m2
    local dt = core.dateToTable(ts)
    local v = dt.hour * 60 + dt.min
    if x <= y then
        return v >= x and v <= y
    end
    return v >= x or v <= y
end

local function dayKey(ts)
    local d = core.dateToTable(ts)
    return (d.year * 10000) + (d.month * 100) + d.day
end

local function normalizeDir(v)
    if v == nil then
        return 0
    end
    if v > 0 then
        return 1
    end
    if v < 0 then
        return -1
    end
    return 0
end

local function recordDecision(ts, gateType, gateReason)
    state.gate.gateType = gateType
    state.gate.gateReason = gateReason
    state.gate.decisionTs = ts
    state.gate.decisionDayKey = dayKey(ts)
end

function Init()
    indicator:name(NAME)
    indicator:description("Skeleton: session sweep / BOS / FVG state machine")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Sessions")
    indicator.parameters:addString("asiaSession", "Asia Session", "2000-0000")

    indicator.parameters:addGroup("Debug")
    indicator.parameters:addBoolean("debugMode", "Debug Mode", false)
end

local function dbg(msg)
    if instance.parameters.debugMode then
        core.host:trace(NAME .. " | " .. msg)
    end
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

    state.bias = normalizeDir(state.bias)
    state.sweepDir = normalizeDir(state.sweepDir)
    state.bosDir = normalizeDir(state.bosDir)

    if inSession(t, instance.parameters.asiaSession) then
        state.asiaHigh = (state.asiaHigh == nil) and h or math.max(state.asiaHigh, h)
        state.asiaLow = (state.asiaLow == nil) and l or math.min(state.asiaLow, l)
    end

    recordDecision(t, "input", "structure_update")

    -- TODO: migrate sweep/BOS/FVG detection logic.
    outAsiaH[period] = state.asiaHigh
    outAsiaL[period] = state.asiaLow
    outBos[period] = state.bosLevel
    outFvgU[period] = state.fvgUpper
    outFvgL[period] = state.fvgLower
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
    -- Intentionally empty: this skeleton currently does not use async history requests.
    dbg(string.format("AsyncOperationFinished(cookie=%s, success=%s)", tostring(cookie), tostring(success)))
end

function ReleaseInstance()
    outAsiaH = nil
    outAsiaL = nil
    outBos = nil
    outFvgU = nil
    outFvgL = nil
    source = nil
end

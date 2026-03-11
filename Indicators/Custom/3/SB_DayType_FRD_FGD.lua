-- SB DayType FRD/FGD (Skeleton)
-- Standalone module extracted from SB_Full_Manual_Workflow_FXCM logic.

local NAME = "SB DayType FRD FGD"

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
    dayKey = nil,
    bias = 0,
    sweepDir = 0,
    bosDir = 0,
    isTradeDay = false,
    stage = STAGE.IDLE,
    gate = {
        gateReason = "init",
        gateType = "system",
        decisionTs = nil,
        decisionDayKey = nil,
    },
}

local outBias = nil
local outTradeDay = nil

local function dbg(msg)
    if instance.parameters.debugMode then
        core.host:trace(NAME .. " | " .. msg)
    end
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
    indicator:description("Skeleton: FRD/FGD day type detector")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Core")
    indicator.parameters:addInteger("dayMoveAtrLen", "Day Move ATR Length", 14, 2, 100)
    indicator.parameters:addDouble("dumpPumpMinAtrMult", "Dump/Pump Min ATR Mult", 1.0, 0.1, 5.0)

    indicator.parameters:addGroup("Debug")
    indicator.parameters:addBoolean("debugMode", "Debug Mode", false)
end

function Prepare(nameOnly)
    source = instance.source
    instance:name(NAME)
    if nameOnly then
        return
    end

    local first = source:first()
    outBias = instance:addStream("BIAS", core.Line, "Bias", "Bias", first)
    outTradeDay = instance:addStream("TRDAY", core.Line, "TradeDay", "TradeDay", first)
end

function Update(period, mode)
    if period < source:first() then
        return
    end

    local t = source:date(period)
    local key = dayKey(t)
    if state.dayKey ~= key then
        state.dayKey = key
        state.bias = 0
        state.isTradeDay = false
        state.stage = STAGE.IDLE
    end

    state.bias = normalizeDir(state.bias)
    state.sweepDir = normalizeDir(state.sweepDir)
    state.bosDir = normalizeDir(state.bosDir)
    recordDecision(t, "input", "daytype_update")

    -- TODO: migrate complete FRD/FGD classification logic from monolith.
    outBias[period] = state.bias
    outTradeDay[period] = state.isTradeDay and 1 or 0
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
    -- Intentionally empty: this skeleton currently does not use async history requests.
    dbg(string.format("AsyncOperationFinished(cookie=%s, success=%s)", tostring(cookie), tostring(success)))
end

function ReleaseInstance()
    outBias = nil
    outTradeDay = nil
    source = nil
end

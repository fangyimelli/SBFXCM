-- SB DayType FRD/FGD (Skeleton)
-- Standalone module extracted from SB_Full_Manual_Workflow_FXCM logic.

local NAME = "SB DayType FRD FGD"

local source = nil
local state = {
    dayKey = nil,
    bias = 0,
    isTradeDay = false,
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
    end

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

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

local function dayKeyFromTime(t)
    local d = core.dateToTable(t)
    return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

function Init()
    indicator:name(NAME)
    indicator:description("Skeleton: FRD/FGD day type detector")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Core")
    indicator.parameters:addInteger("dayMoveAtrLen", "Day Move ATR Length", 14, 2, 100)
    indicator.parameters:addDouble("dumpPumpMinAtrMult", "Dump/Pump Min ATR Mult", 1.0, 0.1, 5.0)
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
    local key = dayKeyFromTime(t)
    if state.dayKey ~= key then
        state.dayKey = key
        state.bias = 0
        state.isTradeDay = false
    end

    -- TODO: migrate complete FRD/FGD classification logic from monolith.
    outBias[period] = state.bias
    outTradeDay[period] = state.isTradeDay and 1 or 0
end

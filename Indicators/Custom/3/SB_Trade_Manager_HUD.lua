-- SB Trade Manager HUD (Skeleton)
-- Standalone module extracted from SB_Full_Manual_Workflow_FXCM logic.

local NAME = "SB Trade Manager HUD"

local source = nil
local state = {
    entry = nil,
    takeProfit = nil,
    stopLoss = nil,
    dailyTrades = 0,
    blocked = false,
}

local outEntry = nil
local outTP = nil
local outSL = nil
local outDailyTrades = nil
local outBlocked = nil

function Init()
    indicator:name(NAME)
    indicator:description("Skeleton: trade line and HUD stream manager")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Risk")
    indicator.parameters:addInteger("targetPips", "Target Pips", 20, 1, 500)
    indicator.parameters:addInteger("slPipsDefault", "SL Pips Default", 12, 1, 500)

    indicator.parameters:addGroup("HUD")
    indicator.parameters:addInteger("dailyMaxTrades", "Daily Max Trades", 2, 1, 20)
end

function Prepare(nameOnly)
    source = instance.source
    instance:name(NAME)
    if nameOnly then
        return
    end

    local first = source:first()
    outEntry = instance:addStream("ENTRY", core.Line, "Entry", "Entry", first)
    outTP = instance:addStream("TP", core.Line, "Take Profit", "TP", first)
    outSL = instance:addStream("SL", core.Line, "Stop Loss", "SL", first)
    outDailyTrades = instance:addStream("TRADES", core.Line, "Daily Trades", "Trades", first)
    outBlocked = instance:addStream("BLOCKED", core.Line, "Blocked", "Blocked", first)
end

function Update(period, mode)
    if period < source:first() then
        return
    end

    state.blocked = state.dailyTrades >= instance.parameters.dailyMaxTrades

    -- TODO: migrate TP/SL lifecycle, slot-consumption and HUD logic.
    outEntry[period] = state.entry
    outTP[period] = state.takeProfit
    outSL[period] = state.stopLoss
    outDailyTrades[period] = state.dailyTrades
    outBlocked[period] = state.blocked and 1 or 0
end

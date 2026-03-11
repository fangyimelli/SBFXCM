-- SB Trade Manager HUD (Skeleton)
-- Standalone module extracted from SB_Full_Manual_Workflow_FXCM logic.

local NAME = "SB Trade Manager HUD"

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
    entry = nil,
    takeProfit = nil,
    stopLoss = nil,
    dailyTrades = 0,
    blocked = false,
    gate = {
        gateReason = "init",
        gateType = "system",
        decisionTs = nil,
        decisionDayKey = nil,
    },
}

local outEntry = nil
local outTP = nil
local outSL = nil
local outDailyTrades = nil
local outBlocked = nil

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
    indicator:description("Skeleton: trade line and HUD stream manager")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Risk")
    indicator.parameters:addInteger("targetPips", "Target Pips", 20, 1, 500)
    indicator.parameters:addInteger("slPipsDefault", "SL Pips Default", 12, 1, 500)

    indicator.parameters:addGroup("HUD")
    indicator.parameters:addInteger("dailyMaxTrades", "Daily Max Trades", 2, 1, 20)

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

    local t = source:date(period)
    state.bias = normalizeDir(state.bias)
    state.sweepDir = normalizeDir(state.sweepDir)
    state.bosDir = normalizeDir(state.bosDir)

    -- HUD is output-only: blocked status should be derived by upstream logic.
    recordDecision(t, "render", "hud_output_refresh")

    -- TODO: migrate TP/SL lifecycle, slot-consumption and HUD logic.
    outEntry[period] = state.entry
    outTP[period] = state.takeProfit
    outSL[period] = state.stopLoss
    outDailyTrades[period] = state.dailyTrades
    outBlocked[period] = state.blocked and 1 or 0
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
    -- Intentionally empty: this skeleton currently does not use async history requests.
    dbg(string.format("AsyncOperationFinished(cookie=%s, success=%s)", tostring(cookie), tostring(success)))
end

function ReleaseInstance()
    outEntry = nil
    outTP = nil
    outSL = nil
    outDailyTrades = nil
    outBlocked = nil
    source = nil
end

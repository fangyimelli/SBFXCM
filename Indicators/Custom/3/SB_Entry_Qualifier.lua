-- SB Entry Qualifier (Skeleton)
-- Standalone module extracted from SB_Full_Manual_Workflow_FXCM logic.

local NAME = "SB Entry Qualifier"

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
    retestUpper = nil,
    retestLower = nil,
    blue1 = false,
    blue2 = false,
    blue3 = false,
    score = 0,
    gate = {
        gateReason = "init",
        gateType = "system",
        decisionTs = nil,
        decisionDayKey = nil,
    },
}

local outRetU = nil
local outRetL = nil
local outBlue1 = nil
local outBlue2 = nil
local outBlue3 = nil
local outScore = nil

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
    indicator:description("Skeleton: retest / Blue signal / score gating")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Entry")
    indicator.parameters:addInteger("entryExpireMinutes", "Entry Expire Minutes", 45, 1, 300)
    indicator.parameters:addBoolean("scoreEnabled", "Score Enabled", true)
    indicator.parameters:addInteger("minScoreToDisplay", "Min Score To Display", 0, 0, 100)

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
    outRetU = instance:addStream("RETU", core.Line, "Retest Upper", "RetU", first)
    outRetL = instance:addStream("RETL", core.Line, "Retest Lower", "RetL", first)
    outBlue1 = instance:addStream("BLUE1", core.Line, "Blue1", "Blue1", first)
    outBlue2 = instance:addStream("BLUE2", core.Line, "Blue2", "Blue2", first)
    outBlue3 = instance:addStream("BLUE3", core.Dot, "Blue3", "Blue3", first)
    outScore = instance:addStream("SCORE", core.Line, "Score", "Score", first)
end

function Update(period, mode)
    if period < source:first() then
        return
    end

    local t = source:date(period)
    state.bias = normalizeDir(state.bias)
    state.sweepDir = normalizeDir(state.sweepDir)
    state.bosDir = normalizeDir(state.bosDir)
    recordDecision(t, "input", "entry_update")

    -- TODO: migrate retest and Blue1/Blue2/Blue3 qualifier logic.
    outRetU[period] = state.retestUpper
    outRetL[period] = state.retestLower
    outBlue1[period] = state.blue1 and 1 or 0
    outBlue2[period] = state.blue2 and 1 or 0
    outBlue3[period] = state.blue3 and source.close[period] or nil
    outScore[period] = state.score
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
    -- Intentionally empty: this skeleton currently does not use async history requests.
    dbg(string.format("AsyncOperationFinished(cookie=%s, success=%s)", tostring(cookie), tostring(success)))
end

function ReleaseInstance()
    outRetU = nil
    outRetL = nil
    outBlue1 = nil
    outBlue2 = nil
    outBlue3 = nil
    outScore = nil
    source = nil
end

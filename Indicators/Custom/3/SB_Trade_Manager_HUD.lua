-- SB Trade Manager HUD
-- Standalone module with scoring + gating + stream outputs.

local NAME = "SB Trade Manager HUD"

local source = nil
local state = {
    -- required core fields
    scoreA = 0,
    scoreAPlus = 0,
    displayOk = false,
    blockedReason = "init",
    todayTradeCount = 0,
    doneToday = false,
    entry = nil,
    tp = nil,
    sl = nil,
    focusDayKey = nil,
    focusAnchor = nil,
    lastNYBarTimeUsed = nil,
    nyBarsInFocusDay = 0,

    slotConsumed = false,
    lastDayKey = nil,
}

local entrystream = nil
local tpstream = nil
local slstream = nil
local scorestream = nil
local tradectstream = nil
local blockedstream = nil
local focusstream = nil
local gatestream = nil

local function dbg(msg)
    if instance.parameters.debugmode then
        core.host:trace(NAME .. " | " .. msg)
    end
end

local function dayKey(ts)
    local d = core.dateToTable(ts)
    return (d.year * 10000) + (d.month * 100) + d.day
end

local function isNY0930(ts)
    local d = core.dateToTable(ts)
    return d.hour == 9 and d.min == 30
end

local function isAfterNY0930(ts)
    local d = core.dateToTable(ts)
    return (d.hour > 9) or (d.hour == 9 and d.min >= 30)
end

-- Core logic: score function.
local function f_score(period)
    if not instance.parameters.scoreenabled then
        return 100
    end

    local o = source.open[period]
    local h = source.high[period]
    local l = source.low[period]
    local c = source.close[period]

    local range = math.max(h - l, source:pipSize())
    local body = math.abs(c - o)
    local bodyPct = math.min(1, body / range)

    local closePos = (c - l) / range -- 0..1
    local closeBias = math.abs(closePos - 0.5) * 2 -- 0..1

    local volNorm = 0
    if period > source:first() then
        local prevRange = math.max(source.high[period - 1] - source.low[period - 1], source:pipSize())
        volNorm = math.min(1, range / prevRange)
    end

    local score = (bodyPct * 45) + (closeBias * 35) + (volNorm * 20)
    return math.floor(math.max(0, math.min(100, score)) + 0.5)
end

local function blockedCode(reason)
    if reason == "ok" then return 0 end
    if reason == "focus_wait_0930" then return 1 end
    if reason == "below_min_score" then return 2 end
    if reason == "daily_max_reached" then return 3 end
    if reason == "slot_wait_entry" then return 4 end
    if reason == "slot_wait_tp" then return 5 end
    if reason == "slot_wait_sl" then return 6 end
    return 9
end

local function gateCode(reason)
    if reason == "ok" then return 1 end
    return 0
end

local function updateDailyReset(ts)
    local dk = dayKey(ts)
    if state.lastDayKey ~= dk then
        state.lastDayKey = dk
        state.focusDayKey = dk
        state.focusAnchor = nil
        state.lastNYBarTimeUsed = nil
        state.nyBarsInFocusDay = 0
        state.slotConsumed = false
        state.doneToday = state.todayTradeCount >= instance.parameters.dailymax
    end
end

local function maybeConsumeSlot(c)
    local mode = string.lower(instance.parameters.consumesloton or "entry")
    if state.slotConsumed then
        return
    end

    if mode == "entry" and state.entry ~= nil then
        state.slotConsumed = true
        state.todayTradeCount = state.todayTradeCount + 1
    elseif mode == "tp" and state.tp ~= nil and ((state.entry <= state.tp and c >= state.tp) or (state.entry > state.tp and c <= state.tp)) then
        state.slotConsumed = true
        state.todayTradeCount = state.todayTradeCount + 1
    elseif mode == "sl" and state.sl ~= nil and ((state.entry >= state.sl and c <= state.sl) or (state.entry < state.sl and c >= state.sl)) then
        state.slotConsumed = true
        state.todayTradeCount = state.todayTradeCount + 1
    end

    if state.todayTradeCount >= instance.parameters.dailymax then
        state.doneToday = true
    end
end

function Init()
    indicator:name(NAME)
    indicator:description("Trade line and HUD stream manager with score/focus gates")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Scoring / Gates")
    indicator.parameters:addBoolean("scoreenabled", "Score Enabled", true)
    indicator.parameters:addInteger("minscore", "Minimum Score", 60, 0, 100)
    indicator.parameters:addInteger("dailymax", "Daily Max Trades", 2, 1, 20)
    indicator.parameters:addString("consumesloton", "Consume Slot On (entry/tp/sl)", "entry")
    indicator.parameters:addBoolean("focusmode", "Focus Mode (require NY 09:30 anchor)", true)
    indicator.parameters:addBoolean("debugmode", "Debug Mode", false)

    indicator.parameters:addGroup("Threshold")
    indicator.parameters:addInteger("athreshold", "A Threshold", 70, 0, 100)
    indicator.parameters:addInteger("aplusthreshold", "A+ Threshold", 85, 0, 100)

    indicator.parameters:addGroup("Risk")
    indicator.parameters:addInteger("tppips", "Target Pips", 20, 1, 500)
    indicator.parameters:addInteger("slpips", "SL Pips", 12, 1, 500)
end

function Prepare(nameOnly)
    source = instance.source
    instance:name(NAME)
    if nameOnly then
        return
    end

    local first = source:first()
    entrystream = instance:addStream("ENTRY", core.Line, "Entry", "Entry", first)
    tpstream = instance:addStream("TP", core.Line, "Take Profit", "TP", first)
    slstream = instance:addStream("SL", core.Line, "Stop Loss", "SL", first)
    scorestream = instance:addStream("SCORE", core.Line, "Score", "Score", first)
    tradectstream = instance:addStream("TRADECT", core.Line, "Today Trade Count", "TradeCt", first)

    -- optional helper streams for UI/debug visibility
    blockedstream = instance:addStream("BLOCKED", core.Line, "Blocked Reason Code", "Blocked", first)
    focusstream = instance:addStream("FOCUS", core.Line, "Focus Ready(1/0)", "Focus", first)
    gatestream = instance:addStream("GATE", core.Line, "Gate OK(1/0)", "Gate", first)
end

function Update(period, mode)
    if period < source:first() then
        return
    end

    local ts = source:date(period)
    local c = source.close[period]
    updateDailyReset(ts)

    if state.focusDayKey ~= dayKey(ts) then
        state.focusDayKey = dayKey(ts)
        state.focusAnchor = nil
        state.nyBarsInFocusDay = 0
    end

    if isNY0930(ts) then
        state.focusAnchor = c
        state.lastNYBarTimeUsed = ts
    end

    if state.focusAnchor ~= nil and isAfterNY0930(ts) then
        state.nyBarsInFocusDay = state.nyBarsInFocusDay + 1
    end

    local score = f_score(period)
    state.scoreA = score >= instance.parameters.athreshold and 1 or 0
    state.scoreAPlus = score >= instance.parameters.aplusthreshold and 1 or 0

    local gateReason = "ok"
    if state.doneToday or state.todayTradeCount >= instance.parameters.dailymax then
        state.doneToday = true
        gateReason = "daily_max_reached"
    elseif instance.parameters.focusmode and state.focusAnchor == nil then
        gateReason = "focus_wait_0930"
    elseif score < instance.parameters.minscore then
        gateReason = "below_min_score"
    elseif not state.slotConsumed then
        local sm = string.lower(instance.parameters.consumesloton or "entry")
        if sm == "entry" then
            gateReason = "slot_wait_entry"
        elseif sm == "tp" then
            gateReason = "slot_wait_tp"
        elseif sm == "sl" then
            gateReason = "slot_wait_sl"
        end
    end

    -- allow first signal to pass even before slot is consumed
    if gateReason == "slot_wait_entry" or gateReason == "slot_wait_tp" or gateReason == "slot_wait_sl" then
        gateReason = "ok"
    end

    state.blockedReason = gateReason
    state.displayOk = (gateReason == "ok")

    if state.displayOk and state.entry == nil then
        state.entry = c
        state.tp = c + (instance.parameters.tppips * source:pipSize())
        state.sl = c - (instance.parameters.slpips * source:pipSize())
    end

    maybeConsumeSlot(c)

    entrystream[period] = state.entry
    tpstream[period] = state.tp
    slstream[period] = state.sl
    scorestream[period] = score
    tradectstream[period] = state.todayTradeCount
    blockedstream[period] = blockedCode(state.blockedReason)
    focusstream[period] = state.focusAnchor ~= nil and 1 or 0
    gatestream[period] = gateCode(state.blockedReason)

    -- Debug must not mutate state: output-only diagnostics.
    if instance.parameters.debugmode then
        dbg(string.format(
            "canAnswer=%s gate=%s blockedReason=%s score=%d A=%d Aplus=%d trades=%d/%d focusAnchor=%s focusBars=%d",
            tostring(state.displayOk),
            state.displayOk and "OPEN" or "BLOCKED",
            state.blockedReason,
            score,
            state.scoreA,
            state.scoreAPlus,
            state.todayTradeCount,
            instance.parameters.dailymax,
            tostring(state.focusAnchor),
            state.nyBarsInFocusDay
        ))
    end
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
    dbg(string.format("AsyncOperationFinished(cookie=%s, success=%s)", tostring(cookie), tostring(success)))
end

function ReleaseInstance()
    entrystream = nil
    tpstream = nil
    slstream = nil
    scorestream = nil
    tradectstream = nil
    blockedstream = nil
    focusstream = nil
    gatestream = nil
    source = nil
end

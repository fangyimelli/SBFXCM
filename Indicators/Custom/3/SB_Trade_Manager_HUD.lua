local IDLE = 0
local ASIAREADY = 1
local SWEPT = 2
local BOS = 3
local WAITFVG = 4
local WAITMIT = 5
local WAITRET = 6
local BLUE1 = 7
local BLUE2 = 8
local BLUE3 = 9
local DONE = 10

local S = {}
local T = {}
local H = {}
local I = {}

local function trace(msg)
    if S.debugmode or S.debug then
        pcall(function()
            core.host:trace("SB_Trade_Manager_HUD: " .. tostring(msg))
        end)
    end
end

function Init()
    indicator:name("SB Trade Manager HUD")
    indicator:description("SB Trade Manager HUD")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addBoolean("scoreenabled", "Enable score gating", "", true)
    indicator.parameters:addDouble("scorethra", "Score threshold A", "", 0)
    indicator.parameters:addDouble("scorethraP", "Score threshold A+", "", 0)
    indicator.parameters:addDouble("scorewny", "Score weight NY", "", 1)
    indicator.parameters:addDouble("scorewsweep", "Score weight Sweep", "", 1)
    indicator.parameters:addDouble("scorewbos", "Score weight BOS", "", 1)
    indicator.parameters:addDouble("scorewfvg", "Score weight FVG/Mit", "", 1)
    indicator.parameters:addDouble("scorewentry", "Score weight Entry Path", "", 1)
    indicator.parameters:addDouble("minscore", "Min score", "", 2)
    indicator.parameters:addInteger("dailymax", "Daily max trades", "", 1)
    indicator.parameters:addString("consumesloton", "Consume slot on", "", "Blue3")
    indicator.parameters:addBoolean("drawtargets", "Draw TP", "", true)
    indicator.parameters:addDouble("tppips", "TP pips", "", 20)
    indicator.parameters:addBoolean("drawsl", "Draw SL", "", true)
    indicator.parameters:addString("slmode", "SL mode", "", "FIXED")
    indicator.parameters:addDouble("slpips", "SL pips", "", 15)
    indicator.parameters:addDouble("slpipsmax", "SL max pips", "", 50)
    indicator.parameters:addDouble("slbufpips", "SL buffer pips", "", 0)
    indicator.parameters:addBoolean("focusmode", "Focus mode", "", false)
    indicator.parameters:addString("focusinput", "Focus day input", "", "")
    indicator.parameters:addBoolean("allowalertsfocus", "Allow alerts in focus mode", "", false)
    indicator.parameters:addBoolean("showhud", "Show HUD", "", true)
    indicator.parameters:addBoolean("debugmode", "Debug mode", "", false)
    indicator.parameters:addBoolean("debug", "Debug", "", false)
end

local function dayKey(ts)
    return math.floor(ts)
end

local function parseHHMM(hhmm)
    if hhmm == nil then
        return nil
    end

    local s = tostring(hhmm)
    local hh, mm = string.match(s, "^(%d%d?)(%d%d)$")
    if hh == nil then
        hh, mm = string.match(s, "^(%d%d?):(%d%d)$")
    end

    hh = tonumber(hh)
    mm = tonumber(mm)
    if hh == nil or mm == nil or hh < 0 or hh > 23 or mm < 0 or mm > 59 then
        return nil
    end

    return hh * 60 + mm
end

local function minuteOfDay(ts)
    local f = ts - math.floor(ts)
    if f < 0 then
        f = f + 1
    end

    local m = math.floor(f * 1440 + 0.000001)
    if m < 0 then
        return 0
    end
    if m > 1439 then
        return 1439
    end
    return m
end

local function inSession(ts, sess)
    if sess == nil or sess == "" then
        return false
    end

    local nowMin = minuteOfDay(ts)
    for token in string.gmatch(sess, "[^,]+") do
        local a, b = string.match(token, "^%s*(%d%d?:?%d%d)%s*%-%s*(%d%d?:?%d%d)%s*$")
        if a ~= nil and b ~= nil then
            local s = parseHHMM(a)
            local e = parseHHMM(b)
            if s ~= nil and e ~= nil then
                if s <= e then
                    if nowMin >= s and nowMin <= e then
                        return true
                    end
                else
                    if nowMin >= s or nowMin <= e then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function pipSize(symbol)
    if type(symbol) == "table" then
        local okPip, p = pcall(function() return symbol:pipSize() end)
        if okPip and p ~= nil and p > 0 then
            return p
        end

        local okPoint, point = pcall(function() return symbol:pointSize() end)
        if okPoint and point ~= nil and point > 0 then
            return point * 10
        end

        local okName, name = pcall(function() return symbol:name() end)
        if okName and name ~= nil then
            symbol = name
        end
    end

    local s = string.upper(tostring(symbol or ""))
    if string.find(s, "JPY", 1, true) ~= nil then
        return 0.01
    end
    if string.find(s, "XAU", 1, true) ~= nil or string.find(s, "XAG", 1, true) ~= nil then
        return 0.1
    end
    return 0.0001
end

local function safeGetHistory(instrument, timeframe, isBid)
    local ok, history = pcall(function()
        return core.host:execute("getSyncHistory", instrument, timeframe, isBid, 0, 0)
    end)

    if not ok or history == nil then
        trace("getSyncHistory failed for " .. tostring(timeframe))
        return nil
    end

    return history
end

local function safeGetPriceStream(history, field)
    if history == nil then
        return nil
    end

    local ok, stream = pcall(function() return history[field] end)
    if not ok then
        return nil
    end
    return stream
end

local function safeAddStream(id, style, label, color, first)
    local ok, stream = pcall(function()
        return instance:addStream(id, style, label, "", color, first)
    end)

    if not ok then
        trace("addStream failed for " .. tostring(id))
        return nil
    end

    return stream
end

local function fScore(inNy, hasSweep, hasBos, hasFvgMit, hasEntryPath)
    local score = 0
    if inNy then
        score = score + (T.scorewny or 0)
    end
    if hasSweep then
        score = score + (T.scorewsweep or 0)
    end
    if hasBos then
        score = score + (T.scorewbos or 0)
    end
    if hasFvgMit then
        score = score + (T.scorewfvg or 0)
    end
    if hasEntryPath then
        score = score + (T.scorewentry or 0)
    end
    return score
end

local function resetForNewDay(ts)
    S.dayKey = dayKey(ts)
    S.todayTradeCount = 0
    S.doneToday = false
    S.entry = nil
    S.tp = nil
    S.sl = nil
    S.lastEntryTime = nil
    S.blockedReason = ""
    S.nyBarsInFocusDay = 0
    S.lastNYBarTimeUsed = nil
    S.state = IDLE
end

local function updateDayReset(period)
    local ts = S.source:date(period)
    local k = dayKey(ts)
    if S.dayKey == nil or S.dayKey ~= k then
        resetForNewDay(ts)
    end
end

local function updateFocusWindow(period)
    local ts = S.source:date(period)
    S.inNy = inSession(ts, T.nysession)

    if not T.focusmode then
        S.focusAnchor = ts
        S.focusDayKey = dayKey(ts)
        return true
    end

    if T.focusDayKey == nil then
        S.blockedReason = "Focus day not configured"
        return false
    end

    S.focusDayKey = T.focusDayKey
    if dayKey(ts) ~= S.focusDayKey then
        return false
    end

    S.focusAnchor = ts
    if S.inNy then
        S.nyBarsInFocusDay = (S.nyBarsInFocusDay or 0) + 1
        S.lastNYBarTimeUsed = ts
    end

    return true
end

local function updateScore(period)
    local open = S.source.open[period]
    local close = S.source.close[period]
    local high = S.source.high[period]
    local low = S.source.low[period]
    local range = high - low
    local body = math.abs(close - open)

    -- Placeholder flags managed by this file only.
    -- TODO: hook these booleans to Structure/Entry event streams if cross-indicator wiring is enabled.
    S.hasSweep = false
    S.hasBos = false
    S.hasFvgMit = false
    S.hasEntryPath = (range > 0 and body / range >= 0.3)

    S.scoreA = fScore(S.inNy, S.hasSweep, S.hasBos, S.hasFvgMit, S.hasEntryPath)
    -- A+ currently mirrors A; keep both fields for future stricter gating/weighting.
    S.scoreAPlus = S.scoreA

    if T.scoreenabled and S.scoreA < T.minscore then
        S.displayOk = false
        if S.blockedReason == "" then
            S.blockedReason = "Min score not reached"
        end
    else
        S.displayOk = true
    end
end

local function consumeTradeSlotIfNeeded(eventName)
    if S.doneToday then
        return
    end

    local mode = string.upper(tostring(T.consumesloton or "BLUE3"))
    local evt = string.upper(tostring(eventName or ""))
    if mode == evt then
        S.todayTradeCount = (S.todayTradeCount or 0) + 1
        if S.todayTradeCount >= T.dailymax then
            S.doneToday = true
        end
    end
end

local function updateTradeLimit()
    if (S.todayTradeCount or 0) >= T.dailymax then
        S.doneToday = true
    end

    if S.doneToday then
        S.displayOk = false
        S.blockedReason = "Daily limit reached"
    end
end

local function updateTargets(period)
    if not S.displayOk or S.doneToday then
        return
    end

    if S.entry ~= nil then
        return
    end

    if not S.hasEntryPath then
        return
    end

    local price = S.source.close[period]
    local dir = 1
    if S.source.close[period] < S.source.open[period] then
        dir = -1
    end

    local p = T.pip
    local tpPips = math.max(0, T.tppips)
    local slPips = math.max(0, math.min(T.slpips, T.slpipsmax)) + math.max(0, T.slbufpips)

    S.entry = price
    S.tp = price + (dir * tpPips * p)

    if string.upper(tostring(T.slmode or "FIXED")) == "FIXED" then
        S.sl = price - (dir * slPips * p)
    else
        -- TODO: add structure-based stop integration when structure stop stream is available.
        S.sl = price - (dir * slPips * p)
    end

    S.lastEntryTime = S.source:date(period)

    -- Placeholder consume point: until BLUE1/BLUE3 event stream is connected,
    -- we consume slot on synthetic BLUE3 at entry creation.
    consumeTradeSlotIfNeeded("BLUE3")
    S.state = DONE
end

local function writeManagerStreams(period)
    if T.streams.entrystream ~= nil then
        T.streams.entrystream[period] = S.entry
    end
    if T.streams.tpstream ~= nil then
        if T.drawtargets then
            T.streams.tpstream[period] = S.tp
        else
            T.streams.tpstream[period] = nil
        end
    end
    if T.streams.slstream ~= nil then
        if T.drawsl then
            T.streams.slstream[period] = S.sl
        else
            T.streams.slstream[period] = nil
        end
    end
    if T.streams.scorestream ~= nil then
        T.streams.scorestream[period] = S.scoreA
    end
    if T.streams.tradectstream ~= nil then
        T.streams.tradectstream[period] = S.todayTradeCount
    end
    if T.streams.displayokstream ~= nil then
        T.streams.displayokstream[period] = S.displayOk and 1 or 0
    end
    if T.streams.focusstream ~= nil then
        T.streams.focusstream[period] = T.focusmode and 1 or 0
    end
    if T.streams.hudstate ~= nil then
        T.streams.hudstate[period] = S.state or IDLE
    end
    if T.streams.blockedstream ~= nil then
        if S.blockedReason ~= "" then
            T.streams.blockedstream[period] = 1
        else
            T.streams.blockedstream[period] = 0
        end
    end
end

function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()

    instance:name(profile:id() .. "(" .. S.source:name() .. ")")

    if nameOnly then
        return
    end

    T.scoreenabled = instance.parameters.scoreenabled
    T.scorethra = instance.parameters.scorethra
    T.scorethraP = instance.parameters.scorethraP
    T.scorewny = instance.parameters.scorewny
    T.scorewsweep = instance.parameters.scorewsweep
    T.scorewbos = instance.parameters.scorewbos
    T.scorewfvg = instance.parameters.scorewfvg
    T.scorewentry = instance.parameters.scorewentry
    T.minscore = instance.parameters.minscore
    T.dailymax = math.max(1, instance.parameters.dailymax)
    T.consumesloton = instance.parameters.consumesloton
    T.drawtargets = instance.parameters.drawtargets
    T.tppips = instance.parameters.tppips
    T.drawsl = instance.parameters.drawsl
    T.slmode = instance.parameters.slmode
    T.slpips = instance.parameters.slpips
    T.slpipsmax = instance.parameters.slpipsmax
    T.slbufpips = instance.parameters.slbufpips
    T.focusmode = instance.parameters.focusmode
    T.focusinput = instance.parameters.focusinput
    T.allowalertsfocus = instance.parameters.allowalertsfocus
    T.showhud = instance.parameters.showhud
    S.debugmode = instance.parameters.debugmode
    S.debug = instance.parameters.debug

    T.nysession = "0930-1600"
    T.pip = pipSize(S.source:instrument())

    local focusNum = tonumber(T.focusinput)
    if T.focusmode and focusNum ~= nil then
        T.focusDayKey = math.floor(focusNum)
    else
        T.focusDayKey = nil
    end

    T.streams = {}
    T.streams.entrystream = safeAddStream("entrystream", core.Line, "Entry", core.rgb(0, 220, 0), S.first)
    T.streams.tpstream = safeAddStream("tpstream", core.Line, "TP", core.rgb(30, 144, 255), S.first)
    T.streams.slstream = safeAddStream("slstream", core.Line, "SL", core.rgb(220, 20, 60), S.first)
    T.streams.scorestream = safeAddStream("scorestream", core.Line, "Score", core.rgb(255, 215, 0), S.first)
    T.streams.tradectstream = safeAddStream("tradectstream", core.Line, "TradeCount", core.rgb(186, 85, 211), S.first)
    T.streams.displayokstream = safeAddStream("displayokstream", core.Line, "DisplayOK", core.rgb(0, 191, 255), S.first)
    T.streams.focusstream = safeAddStream("focusstream", core.Line, "Focus", core.rgb(255, 140, 0), S.first)
    T.streams.hudstate = safeAddStream("hudstate", core.Line, "HUDState", core.rgb(128, 128, 128), S.first)
    T.streams.blockedstream = safeAddStream("blockedstream", core.Line, "Blocked", core.rgb(255, 99, 71), S.first)

    H.m5 = safeGetHistory(S.source:instrument(), "m5", S.source:isBid())
    H.m15 = safeGetHistory(S.source:instrument(), "m15", S.source:isBid())
    H.d1 = safeGetHistory(S.source:instrument(), "D1", S.source:isBid())

    I.ema20m5 = safeGetPriceStream(H.m5, "close")

    resetForNewDay(S.source:date(S.first))
    S.consumeSlotOn = T.consumesloton
    S.scoreA = 0
    S.scoreAPlus = 0
    S.displayOk = true
    S.focusDayKey = T.focusDayKey
    S.focusAnchor = nil
    S.nyBarsInFocusDay = 0
    S.lastNYBarTimeUsed = nil
    S.inNy = false
    S.hasSweep = false
    S.hasBos = false
    S.hasFvgMit = false
    S.hasEntryPath = false
end

function Update(period, mode)
    if period < S.first then
        return
    end

    updateDayReset(period)
    S.blockedReason = ""

    local focusOk = updateFocusWindow(period)
    if not focusOk then
        S.displayOk = false
        if S.blockedReason == "" then
            S.blockedReason = "Focus day filtered"
        end
        writeManagerStreams(period)
        return
    end

    updateScore(period)
    updateTradeLimit()
    updateTargets(period)
    writeManagerStreams(period)
end

function ReleaseInstance()
    H.m5 = nil
    H.m15 = nil
    H.d1 = nil
    I.ema20m5 = nil
end

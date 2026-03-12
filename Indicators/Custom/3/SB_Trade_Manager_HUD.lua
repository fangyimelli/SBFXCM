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

local HUD_STRING_STYLE = core.String ~= nil and core.String or core.Line

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

local function writeHudStream(stream, period, textValue, numericFallback)
    if stream == nil then
        return
    end

    local ok = pcall(function()
        stream[period] = textValue
    end)

    if not ok then
        stream[period] = numericFallback
    end
end

local function normalizeBlockedReason(reason)
    local key = string.lower(tostring(reason or ""))
    if key == "" then
        return ""
    end

    if string.find(key, "not trade day", 1, true) ~= nil then
        return "NOT TRADE DAY"
    end
    if string.find(key, "bias none", 1, true) ~= nil then
        return "BIAS NONE"
    end
    if string.find(key, "min score", 1, true) ~= nil or string.find(key, "score low", 1, true) ~= nil then
        return "SCORE BELOW MIN"
    end
    if string.find(key, "daily limit", 1, true) ~= nil then
        return "DAILY LIMIT REACHED"
    end

    return string.upper(tostring(reason or ""))
end

local function formatPrice(v)
    if v == nil then
        return "-"
    end
    return tostring(v)
end

local function formatFocusDayText()
    if not T.focusmode then
        return "FOCUS MODE: OFF"
    end

    local raw = tostring(T.focusinput or "")
    if string.match(raw, "^%d%d%d%d%-%d%d%-%d%d$") ~= nil then
        return "FOCUS MODE: ON | FOCUS DAY: " .. raw
    end

    if T.focusDayKey ~= nil and core.dateToTable ~= nil then
        local ok, dt = pcall(function()
            return core.dateToTable(T.focusDayKey)
        end)
        if ok and dt ~= nil and dt.year ~= nil and dt.month ~= nil and dt.day ~= nil then
            local iso = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
            return "FOCUS MODE: ON | FOCUS DAY: " .. iso
        end
    end

    return "FOCUS MODE: ON | FOCUS DAY: " .. tostring(T.focusDayKey or "-")
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

    local displayText = "DISPLAY OK: " .. (S.displayOk and "YES" or "NO")
    local tradeText = "TODAY TRADES: " .. tostring(S.todayTradeCount or 0) .. "/" .. tostring(T.dailymax or 0)
    local scoreText = "SCORE A: " .. tostring(S.scoreA or 0) .. " | SCORE A+: " .. tostring(S.scoreAPlus or 0)
    local targetsText = "ENTRY: " .. formatPrice(S.entry) .. " | TP: " .. formatPrice(S.tp) .. " | SL: " .. formatPrice(S.sl)
    local blockedText = normalizeBlockedReason(S.blockedReason)
    local focusText = formatFocusDayText()

    writeHudStream(T.streams.hud_trade, period, displayText .. " | " .. tradeText, S.displayOk and 1 or 0)
    writeHudStream(T.streams.hud_score, period, scoreText, S.scoreA or 0)
    writeHudStream(T.streams.hud_targets, period, targetsText, S.entry or 0)
    writeHudStream(T.streams.hud_blocked, period, blockedText ~= "" and ("BLOCKED: " .. blockedText) or "BLOCKED: NONE", blockedText ~= "" and 1 or 0)
    writeHudStream(T.streams.hud_focus, period, focusText, T.focusmode and 1 or 0)
end

function Prepare(nameOnly)
    trace("Prepare start")

    if instance == nil then
        trace("instance missing")
        return
    end

    S.source = instance.source
    if S.source == nil then
        trace("source failed")
        return
    end
    trace("source ok")

    S.first = S.source:first()
    if S.first == nil then
        trace("first failed")
        return
    end

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
    trace("parameters ok")

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
    T.streams.hud_trade = safeAddStream("hud_trade", HUD_STRING_STYLE, "HUD Trade", core.rgb(240, 240, 240), S.first)
    T.streams.hud_score = safeAddStream("hud_score", HUD_STRING_STYLE, "HUD Score", core.rgb(255, 215, 0), S.first)
    T.streams.hud_targets = safeAddStream("hud_targets", HUD_STRING_STYLE, "HUD Targets", core.rgb(135, 206, 250), S.first)
    T.streams.hud_blocked = safeAddStream("hud_blocked", HUD_STRING_STYLE, "HUD Blocked", core.rgb(255, 99, 71), S.first)
    T.streams.hud_focus = safeAddStream("hud_focus", HUD_STRING_STYLE, "HUD Focus", core.rgb(255, 140, 0), S.first)

    if T.streams.entrystream ~= nil and T.streams.tpstream ~= nil and T.streams.slstream ~= nil and T.streams.scorestream ~= nil and T.streams.tradectstream ~= nil and T.streams.displayokstream ~= nil and T.streams.focusstream ~= nil and T.streams.hudstate ~= nil and T.streams.blockedstream ~= nil and T.streams.hud_trade ~= nil and T.streams.hud_score ~= nil and T.streams.hud_targets ~= nil and T.streams.hud_blocked ~= nil and T.streams.hud_focus ~= nil then
        trace("streams ok")
    else
        trace("streams failed")
    end

    H.m5 = safeGetHistory(S.source:instrument(), "m5", S.source:isBid())
    H.m15 = safeGetHistory(S.source:instrument(), "m15", S.source:isBid())
    H.d1 = safeGetHistory(S.source:instrument(), "D1", S.source:isBid())

    if H.m5 ~= nil and H.m15 ~= nil and H.d1 ~= nil then
        trace("history ok")
    else
        trace("history failed")
        if H.m5 == nil then
            trace("failed to create m5 history")
        end
        if H.m15 == nil then
            trace("failed to create m15 history")
        end
        if H.d1 == nil then
            trace("failed to create d1 history")
        end
    end

    I.ema20m5 = safeGetPriceStream(H.m5, "close")
    if I.ema20m5 == nil then
        trace("failed to create ema20m5")
    end

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
    trace("Prepare finish")
end

function Update(period, mode)
    trace("Update start")

    if S == nil or S.source == nil or S.first == nil then
        trace("missing source/first")
        return
    end

    if period < S.first then
        return
    end

    if H == nil or H.m5 == nil or H.m15 == nil or H.d1 == nil then
        trace("missing histories")
        return
    end

    if I == nil or I.ema20m5 == nil then
        trace("missing indicator ema20m5")
        return
    end

    if S.dayKey == nil then
        trace("missing S.dayKey")
    end
    if S.bias == nil then
        trace("missing S.bias")
    end
    if S.entry == nil then
        trace("missing S.entry")
    end
    if S.tp == nil then
        trace("missing S.tp")
    end
    if S.sl == nil then
        trace("missing S.sl")
    end

    updateDayReset(period)
    trace("day reset")
    S.blockedReason = ""
    trace("core calculation start")

    local focusOk = updateFocusWindow(period)
    if not focusOk then
        S.displayOk = false
        if S.blockedReason == "" then
            S.blockedReason = "Focus day filtered"
        end
        trace("core calculation finish")
        writeManagerStreams(period)
        trace("stream write finish")
        return
    end

    updateScore(period)
    updateTradeLimit()
    updateTargets(period)
    trace("core calculation finish")
    writeManagerStreams(period)
    trace("stream write finish")
end

function ReleaseInstance()
    H.m5 = nil
    H.m15 = nil
    H.d1 = nil
    I.ema20m5 = nil
end


function AsyncOperationFinished(cookie, success, message, message1, message2)
end

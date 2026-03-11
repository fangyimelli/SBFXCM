-- SB Full Manual Workflow (FXCM / Indicore Lua)
-- Compatibility target: Trading Station Desktop v01.16.050523 (Marketscope 2.0)

local NAME = "SB Full Manual Workflow FXCM"

local STATEWAITASIA = 0
local STATEASIAREADY = 1
local STATESWEPT = 2
local STATEWAITFVG = 3
local STATEWAITRETEST = 4
local STATEENTRYWINDOW = 5

local gSource = nil

local S = {
    inited = false,
    sessionState = STATEWAITASIA,
    asiaHigh = nil,
    asiaLow = nil,
    sweepUsed = false,
    sweepDir = 0,
    sweepTime = nil,
    bosDir = 0,
    bosLevel = nil,
    bosTime = nil,
    fvgUpper = nil,
    fvgLower = nil,
    fvgMid = nil,
    fvgTime = nil,
    fvgMit = false,
    retestUpper = nil,
    retestLower = nil,
    retestTime = nil,
    blue1 = false,
    blue2 = false,
    blue3 = false,
    blue1Last = -100000,
    blue2Last = -100000,
    blue3Last = -100000,
    scoreA = 0,
    scoreAPlus = 0,
    blockedReason = "",
    focusDayKey = nil,
    focusAnchor = nil,
    todayTradeCount = 0,
    doneToday = false,
    entry = nil,
    tp = nil,
    sl = nil,
    currentDayKey = nil,
    judgeTrace = "",
}

local H = {
    h5 = nil,
    h15 = nil,
    hD = nil,
    map5to15 = {},
    map5toD = {},
    focusStart = nil,
    focusEnd = nil,
    focusKey = nil,
}

local T = {
    streamOHLC5 = {},
    streamOHLC15 = {},
    streamOHLCD = {},
    out = {},
}

local I = {
    ema20 = {},
    atr5 = {},
    atr15 = {},
    atrD = {},
}

local function dbg(msg)
    if instance.parameters.debugMode then
        terminal:alertMessage(NAME .. " | " .. msg, core.host:execute("getTradingProperty", "baseUnitSize"), "")
    end
end

function Init()
    indicator:name(NAME)
    indicator:description("Port of TradingView SB Full Manual Workflow to Indicore Lua")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Sessions")
    indicator.parameters:addString("nySession", "NY Session", "0930-1130")
    indicator.parameters:addString("asiaSession", "Asia Session", "2000-0000")
    indicator.parameters:addBoolean("prefilterLock", "Lock Asia at NY open", true)
    indicator.parameters:addBoolean("allowEntryAfterSession", "Allow Entry after NY session", false)

    indicator.parameters:addGroup("Grade")
    indicator.parameters:addStringAlternative("liveGradeMode", "Live Grade Mode", "Manual", "Manual")
    indicator.parameters:addStringAlternative("liveGradeMode", "", "Auto", "Auto")
    indicator.parameters:addStringAlternative("manualGrade", "Manual Grade", "Aplus", "A+")
    indicator.parameters:addStringAlternative("manualGrade", "", "A", "A")

    indicator.parameters:addGroup("DayType")
    indicator.parameters:addBoolean("requireSbDayType", "Require SB DayType", false)
    indicator.parameters:addInteger("dayMoveAtrLen", "Day Move ATR Length", 14, 2, 100)
    indicator.parameters:addDouble("dumpPumpMinAtrMult", "Dump/Pump Min ATR Mult", 1.0, 0.1, 5)
    indicator.parameters:addBoolean("mrnBlock", "MRN Block", false)
    indicator.parameters:addBoolean("tradeDayOnly", "TradeDay Only", false)

    indicator.parameters:addGroup("Sweep/BOS/FVG")
    indicator.parameters:addInteger("sweepMinTicks", "Sweep Min Ticks", 8, 1, 200)
    indicator.parameters:addInteger("sweepAtrLen", "Sweep ATR Len", 14, 2, 100)
    indicator.parameters:addDouble("sweepMinAtrMult", "Sweep Min ATR Mult", 0.2, 0.0, 5)
    indicator.parameters:addInteger("sweepReclaimBars", "Sweep Reclaim Bars", 2, 1, 10)
    indicator.parameters:addInteger("bosSwingLeft", "BOS Swing Left", 2, 1, 20)
    indicator.parameters:addInteger("bosSwingRight", "BOS Swing Right", 2, 1, 20)
    indicator.parameters:addInteger("bosConfirmBars", "BOS Confirm Bars", 1, 1, 10)
    indicator.parameters:addDouble("bosMinAtrMultA", "BOS Min ATR Mult A", 0.2, 0.0, 5)
    indicator.parameters:addDouble("bosMinAtrMultAplus", "BOS Min ATR Mult A+", 0.3, 0.0, 5)
    indicator.parameters:addBoolean("useFvg", "Use FVG", true)
    indicator.parameters:addInteger("fvgLookbackBars", "FVG Lookback Bars", 30, 3, 300)
    indicator.parameters:addInteger("fvgExpireMinutes", "FVG Expire Minutes", 60, 1, 1000)
    indicator.parameters:addDouble("fvgMinAtrMultA", "FVG Min ATR Mult A", 0.05, 0.0, 5)
    indicator.parameters:addDouble("fvgMinAtrMultAplus", "FVG Min ATR Mult A+", 0.1, 0.0, 5)

    indicator.parameters:addGroup("Retest/Blue")
    indicator.parameters:addStringAlternative("retestMode", "Retest Mode", "BOS", "BOS level")
    indicator.parameters:addStringAlternative("retestMode", "", "Pivot", "pre-break pivot zone")
    indicator.parameters:addStringAlternative("retestMode", "", "Band", "band buffer")
    indicator.parameters:addDouble("retestBufferAtrMultA", "Retest Buffer ATR Mult A", 0.1, 0.0, 2)
    indicator.parameters:addDouble("retestBufferAtrMultAplus", "Retest Buffer ATR Mult A+", 0.08, 0.0, 2)
    indicator.parameters:addInteger("entryExpireMinutes", "Entry Expire Minutes", 45, 1, 300)
    indicator.parameters:addBoolean("requireEma20ForBlue3", "Require EMA20 for Blue3", true)
    indicator.parameters:addInteger("reactionWindowBars", "Reaction Window Bars", 6, 1, 30)
    indicator.parameters:addBoolean("requireReclaimForBlue2", "Require Reclaim for Blue2", true)
    indicator.parameters:addBoolean("enableRejectForBlue2", "Enable Reject for Blue2", true)
    indicator.parameters:addDouble("rejectWickRatioMin", "Reject Wick Ratio Min", 0.5, 0.0, 1)
    indicator.parameters:addDouble("rejectBodyRatioMax", "Reject Body Ratio Max", 0.5, 0.0, 1)
    indicator.parameters:addInteger("cooldownBlue1", "Cooldown Blue1 (min)", 15, 0, 300)
    indicator.parameters:addInteger("cooldownBlue2", "Cooldown Blue2 (min)", 10, 0, 300)
    indicator.parameters:addInteger("cooldownBlue3", "Cooldown Blue3 (min)", 30, 0, 500)
    indicator.parameters:addStringAlternative("consumeSlotOn", "Consume Slot On", "Blue3", "Blue3")
    indicator.parameters:addStringAlternative("consumeSlotOn", "", "Blue1", "Blue1")

    indicator.parameters:addGroup("Risk/Target")
    indicator.parameters:addBoolean("drawTargetLines", "Draw TP/SL", true)
    indicator.parameters:addInteger("targetPips", "Target Pips", 20, 1, 500)
    indicator.parameters:addStringAlternative("slMode", "SL Mode", "Fixed", "FixedPips")
    indicator.parameters:addStringAlternative("slMode", "", "Swing", "StructureSwing")
    indicator.parameters:addInteger("slPipsDefault", "SL Pips Default", 12, 1, 500)
    indicator.parameters:addInteger("slPipsMaxHint", "SL Max Hint", 50, 1, 1000)
    indicator.parameters:addInteger("slBufferPips", "SL Buffer Pips", 2, 0, 100)
    indicator.parameters:addStringAlternative("lineLifecycle", "Line Lifecycle", "NextBlue3", "Next Blue3")
    indicator.parameters:addStringAlternative("lineLifecycle", "", "SessionEnd", "Session End")
    indicator.parameters:addStringAlternative("lineLifecycle", "", "DayEnd", "Day End")
    indicator.parameters:addBoolean("showLabels", "Show Labels (stream proxy)", false)

    indicator.parameters:addGroup("Score/Display")
    indicator.parameters:addBoolean("scoreEnabled", "Score Enabled", true)
    indicator.parameters:addInteger("scoreThresholdA", "Score Threshold A", 55, 0, 100)
    indicator.parameters:addInteger("scoreThresholdAplus", "Score Threshold A+", 70, 0, 100)
    indicator.parameters:addInteger("weightNy", "Weight In NY", 15, 0, 100)
    indicator.parameters:addInteger("weightSweep", "Weight Sweep", 20, 0, 100)
    indicator.parameters:addInteger("weightBos", "Weight BOS", 20, 0, 100)
    indicator.parameters:addInteger("weightFvg", "Weight FVG Mit", 20, 0, 100)
    indicator.parameters:addInteger("weightEntry", "Weight Entry", 25, 0, 100)
    indicator.parameters:addInteger("dailyMaxTrades", "Daily Max Trades", 2, 1, 20)
    indicator.parameters:addInteger("minScoreToDisplay", "Min Score To Display", 0, 0, 100)
    indicator.parameters:addBoolean("showDaytypeLabels", "Show DayType Labels (stream)", true)

    indicator.parameters:addGroup("Focus/HUD")
    indicator.parameters:addBoolean("focusmode", "Focus Mode", false)
    indicator.parameters:addString("focusdate", "Focus Date YYYY-MM-DD", "")
    indicator.parameters:addBoolean("showhud", "Show HUD streams", true)
    indicator.parameters:addBoolean("debugMode", "Debug Mode", false)
end

local function dayKey(ts)
    local d = core.dateToTable(ts)
    return (d.year * 10000) + (d.month * 100) + d.day
end

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

local function pipSize(symbol)
    local p = nil
    if instance ~= nil and instance.bid ~= nil and instance.bid:instrument() ~= nil then
        p = instance.bid:instrument():getPipSize()
    end
    if p ~= nil and p > 0 then
        return p
    end
    local symText = (type(symbol) == "string") and symbol or tostring(symbol or "")
    if string.find(string.upper(symText), "JPY", 1, true) ~= nil then
        return 0.01
    end
    return 0.0001
end

local function wickReject(dir, o, h, l, c, wickMin, bodyMax)
    local body = math.abs(c - o)
    local range = h - l
    if range <= 0 then return false end
    local upperWick = h - math.max(o, c)
    local lowerWick = math.min(o, c) - l
    local wick = (dir == 1) and lowerWick or upperWick
    return (wick / range) >= wickMin and (body / range) <= bodyMax
end

local function pivotHigh(stream, p, left, right)
    if stream == nil or p - left < 0 or p + right >= stream:size() then
        return nil
    end
    local v = stream[p]
    for i = p - left, p + right do
        if i ~= p and stream[i] >= v then
            return nil
        end
    end
    return v
end

local function pivotLow(stream, p, left, right)
    if stream == nil or p - left < 0 or p + right >= stream:size() then
        return nil
    end
    local v = stream[p]
    for i = p - left, p + right do
        if i ~= p and stream[i] <= v then
            return nil
        end
    end
    return v
end

local function safeGetHistory(instrument, timeframe, from, count)
    local fromV = tonumber(from) or 0
    local countV = tonumber(count) or 0
    return host:execute("getHistory", instrument, tostring(timeframe), fromV, countV)
end

local function safeGetPriceStream(history, fieldName)
    if history == nil then return nil end
    local base = string.lower(tostring(fieldName or ""))
    local candidates = {
        base,
        string.upper(base),
        fieldName,
        base .. "s",
        string.upper(base) .. "S",
    }
    for _, key in ipairs(candidates) do
        local ok, s = pcall(function() return history[key] end)
        if ok and s ~= nil then
            return s
        end
    end
    return nil
end

local function alignTimeIndex(baseHistory, targetHistory)
    local mapping = {}
    local j = 0
    if baseHistory == nil or targetHistory == nil then
        return mapping
    end
    for i = 0, baseHistory:size() - 1 do
        local ts = baseHistory:date(i)
        while (j + 1) < targetHistory:size() and targetHistory:date(j + 1) <= ts do
            j = j + 1
        end
        mapping[i] = j
    end
    return mapping
end

local function parseFocusDate(s)
    local y, m, d = string.match(s, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y == nil then
        return nil
    end
    local dt = core.host:execute("convertTime", 0, core.TZ_EST)
    local tbl = core.dateToTable(dt)
    tbl.year = tonumber(y)
    tbl.month = tonumber(m)
    tbl.day = tonumber(d)
    tbl.hour = 9
    tbl.min = 30
    tbl.sec = 0
    return core.tableToDate(tbl)
end

local function emaFallback(arr, period, i)
    if i == 0 then return arr[0] end
    local k = 2 / (period + 1)
    I.ema20[i] = arr[i] * k + (I.ema20[i - 1] or arr[i]) * (1 - k)
    return I.ema20[i]
end

local function atrFallback(histO, histH, histL, histC, period, outArr, i)
    if i == 0 then outArr[i] = histH[i] - histL[i]; return outArr[i] end
    local prev = histC[i - 1] or histC[i]
    local tr = math.max(histH[i] - histL[i], math.abs(histH[i] - prev), math.abs(histL[i] - prev))
    outArr[i] = ((outArr[i - 1] or tr) * (period - 1) + tr) / period
    return outArr[i]
end

local function fscore(inNyVal, hasSweep, hasBos, hasFvgVal, hasEntry)
    local sc = 0
    if inNyVal then sc = sc + instance.parameters.weightNy end
    if hasSweep then sc = sc + instance.parameters.weightSweep end
    if hasBos then sc = sc + instance.parameters.weightBos end
    if hasFvgVal then sc = sc + instance.parameters.weightFvg end
    if hasEntry then sc = sc + instance.parameters.weightEntry end
    return math.min(100, sc)
end

local function isBlockedByDayType(bias)
    if instance.parameters.requireSbDayType and bias == 0 then
        S.blockedReason = "Blocked: bias=0"
        return true
    end
    if instance.parameters.tradeDayOnly and bias == 0 then
        S.blockedReason = "Blocked: not TradeDay"
        return true
    end
    return false
end

local function resetDay()
    S.todayTradeCount = 0
    S.doneToday = false
    S.sweepUsed = false
    S.sessionState = STATEWAITASIA
    S.asiaHigh = nil
    S.asiaLow = nil
    S.sweepDir = 0
    S.sweepTime = nil
    S.bosDir = 0
    S.bosLevel = nil
    S.bosTime = nil
    S.fvgUpper = nil
    S.fvgLower = nil
    S.fvgMid = nil
    S.fvgTime = nil
    S.fvgMit = false
    S.retestUpper = nil
    S.retestLower = nil
    S.retestTime = nil
    S.entry = nil
    S.tp = nil
    S.sl = nil
    S.blue1 = false
    S.blue2 = false
    S.blue3 = false
    S.blockedReason = ""
    S.judgeTrace = "day-reset"
end

function Prepare(nameOnly)
    gSource = instance.source
    local name = NAME
    instance:name(name)
    if nameOnly then return end

    local first = gSource:first()

    -- Mandatory fixed-argument getHistory signature
    H.h5 = safeGetHistory(gSource:instrument(), "m5", 0, 10000)
    H.h15 = safeGetHistory(gSource:instrument(), "m15", 0, 10000)
    H.hD = safeGetHistory(gSource:instrument(), "D1", 0, 3000)

    T.streamOHLC5.open = safeGetPriceStream(H.h5, "open")
    T.streamOHLC5.high = safeGetPriceStream(H.h5, "high")
    T.streamOHLC5.low = safeGetPriceStream(H.h5, "low")
    T.streamOHLC5.close = safeGetPriceStream(H.h5, "close")

    T.streamOHLC15.open = safeGetPriceStream(H.h15, "open")
    T.streamOHLC15.high = safeGetPriceStream(H.h15, "high")
    T.streamOHLC15.low = safeGetPriceStream(H.h15, "low")
    T.streamOHLC15.close = safeGetPriceStream(H.h15, "close")

    T.streamOHLCD.open = safeGetPriceStream(H.hD, "open")
    T.streamOHLCD.high = safeGetPriceStream(H.hD, "high")
    T.streamOHLCD.low = safeGetPriceStream(H.hD, "low")
    T.streamOHLCD.close = safeGetPriceStream(H.hD, "close")

    H.map5to15 = alignTimeIndex(H.h5, H.h15)
    H.map5toD = alignTimeIndex(H.h5, H.hD)

    H.focusKey = instance.parameters.focusdate
    if instance.parameters.focusmode and H.focusKey ~= "" then
        local t = parseFocusDate(H.focusKey)
        if t ~= nil then
            H.focusStart = t
            H.focusEnd = t + (24 * 60 * 60)
            S.focusAnchor = t
            S.focusDayKey = dayKey(t)
        end
    end

    T.out.asiaH = instance:addStream("ASIAH", core.Line, "Asia High", "AsiaH", first)
    T.out.asiaL = instance:addStream("ASIAL", core.Line, "Asia Low", "AsiaL", first)
    T.out.bos = instance:addStream("BOSLV", core.Line, "BOS Level", "BOS", first)
    T.out.fvgU = instance:addStream("FVGU", core.Line, "FVG Upper", "FVGU", first)
    T.out.fvgL = instance:addStream("FVGL", core.Line, "FVG Lower", "FVGL", first)
    T.out.retU = instance:addStream("RETU", core.Line, "Retest Upper", "RetU", first)
    T.out.retL = instance:addStream("RETL", core.Line, "Retest Lower", "RetL", first)
    T.out.entry = instance:addStream("ENTRY", core.Line, "Entry", "Entry", first)
    T.out.tp = instance:addStream("TP", core.Line, "Take Profit", "TP", first)
    T.out.sl = instance:addStream("SL", core.Line, "Stop Loss", "SL", first)
    T.out.blue3 = instance:addStream("BLUE3", core.Dot, "Blue3 Signal", "Blue3", first)

    T.out.tradeDay = instance:addStream("TRADEDAY", core.Line, "TradeDay", "TradeDay", first)
    T.out.inNy = instance:addStream("INNY", core.Line, "In NY", "InNY", first)
    T.out.hasBos = instance:addStream("HASBOS", core.Line, "Has BOS", "HasBOS", first)
    T.out.fvgMit = instance:addStream("FVGMIT", core.Line, "FVG Mit", "FvgMit", first)
    T.out.blue1 = instance:addStream("BLUE1", core.Line, "Blue1", "Blue1", first)
    T.out.blue2 = instance:addStream("BLUE2", core.Line, "Blue2", "Blue2", first)
    T.out.blue3State = instance:addStream("BLUE3S", core.Line, "Blue3State", "Blue3State", first)
    T.out.score = instance:addStream("SCORE", core.Line, "Score", "Score", first)
    T.out.debug = instance:addStream("DEBUG", core.Line, "Debug", "Debug", first)
end

local function computeBias(dIndex)
    if dIndex < 2 then return 0, false, false end
    local yOpen = T.streamOHLCD.open[dIndex - 1]
    local yClose = T.streamOHLCD.close[dIndex - 1]
    local yHigh = T.streamOHLCD.high[dIndex - 1]
    local yLow = T.streamOHLCD.low[dIndex - 1]
    local yRange = yHigh - yLow
    local yAtr = atrFallback(T.streamOHLCD.open, T.streamOHLCD.high, T.streamOHLCD.low, T.streamOHLCD.close, instance.parameters.dayMoveAtrLen, I.atrD, dIndex - 1)

    local dumpYesterday = (yOpen - yClose) >= (yAtr * instance.parameters.dumpPumpMinAtrMult)
    local pumpYesterday = (yClose - yOpen) >= (yAtr * instance.parameters.dumpPumpMinAtrMult)
    local dFgd = dumpYesterday and yRange >= yAtr
    local dFrd = pumpYesterday and yRange >= yAtr

    local p2Open = T.streamOHLCD.open[dIndex - 2]
    local p2Close = T.streamOHLCD.close[dIndex - 2]
    local p2Dump = (p2Open - p2Close) >= yAtr * instance.parameters.dumpPumpMinAtrMult
    local p2Pump = (p2Close - p2Open) >= yAtr * instance.parameters.dumpPumpMinAtrMult

    local yFgd = p2Dump and pumpYesterday
    local yFrd = p2Pump and dumpYesterday
    local tradeDay = yFgd or yFrd or dFgd or dFrd
    local bias = 0
    if yFgd or dFgd then bias = 1 end
    if yFrd or dFrd then bias = -1 end
    return bias, tradeDay, dFgd, dFrd
end

local function visibleForFocus(t)
    if not instance.parameters.focusmode then return true end
    if H.focusStart == nil or H.focusEnd == nil then return false end
    return t >= H.focusStart and t < H.focusEnd
end

function Update(period, mode)
    if not S.inited then S.inited = true end
    if period < 2 then return end

    S.blue1, S.blue2, S.blue3 = false, false, false
    S.blockedReason = ""

    local t5 = gSource:date(period)
    local inFocus = visibleForFocus(t5)
    local inAsia = inSession(t5, instance.parameters.asiaSession)
    local inNy = inSession(t5, instance.parameters.nySession)
    local idx15 = H.map5to15[period] or 0
    local idxD = H.map5toD[period] or 0

    local o5 = gSource.open[period]
    local h5v = gSource.high[period]
    local l5v = gSource.low[period]
    local c5 = gSource.close[period]
    local a5 = atrFallback(gSource.open, gSource.high, gSource.low, gSource.close, instance.parameters.sweepAtrLen, I.atr5, period)
    local e20 = emaFallback(gSource.close, 20, period)

    local dayK = dayKey(t5)
    if S.currentDayKey == nil then S.currentDayKey = dayK end
    if dayK ~= S.currentDayKey then
        S.currentDayKey = dayK
        resetDay()
    end

    local bias, tradeDay = computeBias(idxD)
    local dayBlocked = isBlockedByDayType(bias)

    if inAsia then
        S.asiaHigh = (S.asiaHigh == nil) and h5v or math.max(S.asiaHigh, h5v)
        S.asiaLow = (S.asiaLow == nil) and l5v or math.min(S.asiaLow, l5v)
    end
    if instance.parameters.prefilterLock and inNy and S.sessionState == STATEWAITASIA and S.asiaHigh ~= nil and S.asiaLow ~= nil then
        S.sessionState = STATEASIAREADY
    end

    if S.sessionState >= STATEASIAREADY and not S.sweepUsed and idx15 >= 1 then
        local h15v = T.streamOHLC15.high[idx15]
        local l15v = T.streamOHLC15.low[idx15]
        local c15 = T.streamOHLC15.close[idx15]
        local o15 = T.streamOHLC15.open[idx15]
        local a15 = atrFallback(T.streamOHLC15.open, T.streamOHLC15.high, T.streamOHLC15.low, T.streamOHLC15.close, instance.parameters.sweepAtrLen, I.atr15, idx15)
        local sweepThreshold = math.max(instance.parameters.sweepMinTicks * pipSize(gSource:instrument()), a15 * instance.parameters.sweepMinAtrMult)
        local upSweep = S.asiaHigh ~= nil and (h15v - S.asiaHigh) >= sweepThreshold
        local dnSweep = S.asiaLow ~= nil and (S.asiaLow - l15v) >= sweepThreshold
        local reclaimUp = c15 < S.asiaHigh or (instance.parameters.manualGrade == "A" and o15 < S.asiaHigh)
        local reclaimDn = c15 > S.asiaLow or (instance.parameters.manualGrade == "A" and o15 > S.asiaLow)
        if upSweep and reclaimUp then
            S.sweepUsed, S.sweepDir, S.sweepTime, S.sessionState = true, 1, t5, STATESWEPT
            S.judgeTrace = "sweep-up"
        elseif dnSweep and reclaimDn then
            S.sweepUsed, S.sweepDir, S.sweepTime, S.sessionState = true, -1, t5, STATESWEPT
            S.judgeTrace = "sweep-down"
        end
    end

    if S.sessionState == STATESWEPT and idx15 >= (instance.parameters.bosSwingLeft + instance.parameters.bosSwingRight + 1) then
        local hh = T.streamOHLC15.high[idx15 - 1]
        local ll = T.streamOHLC15.low[idx15 - 1]
        local c15 = T.streamOHLC15.close[idx15]
        local h15v = T.streamOHLC15.high[idx15]
        local l15v = T.streamOHLC15.low[idx15]
        local a15 = I.atr15[idx15] or atrFallback(T.streamOHLC15.open, T.streamOHLC15.high, T.streamOHLC15.low, T.streamOHLC15.close, instance.parameters.sweepAtrLen, I.atr15, idx15)
        local minBos = a15 * ((instance.parameters.manualGrade == "Aplus") and instance.parameters.bosMinAtrMultAplus or instance.parameters.bosMinAtrMultA)
        if S.sweepDir == 1 then
            local broke = ((instance.parameters.manualGrade == "Aplus") and c15 < ll) or (l15v < ll)
            if broke and (ll - l15v) >= minBos then
                S.bosDir, S.bosLevel, S.bosTime = -1, ll, t5
                S.sessionState = instance.parameters.useFvg and STATEWAITFVG or STATEWAITRETEST
            end
        elseif S.sweepDir == -1 then
            local broke = ((instance.parameters.manualGrade == "Aplus") and c15 > hh) or (h15v > hh)
            if broke and (h15v - hh) >= minBos then
                S.bosDir, S.bosLevel, S.bosTime = 1, hh, t5
                S.sessionState = instance.parameters.useFvg and STATEWAITFVG or STATEWAITRETEST
            end
        end
    end

    if S.sessionState == STATEWAITFVG and idx15 >= 2 then
        local lo = T.streamOHLC15.low[idx15]
        local hi2 = T.streamOHLC15.high[idx15 - 2]
        local hi = T.streamOHLC15.high[idx15]
        local lo2 = T.streamOHLC15.low[idx15 - 2]
        local a15 = I.atr15[idx15] or 0
        local minFvg = a15 * ((instance.parameters.manualGrade == "Aplus") and instance.parameters.fvgMinAtrMultAplus or instance.parameters.fvgMinAtrMultA)
        if S.bosDir == 1 and lo > hi2 and (lo - hi2) >= minFvg then
            S.fvgLower, S.fvgUpper, S.fvgTime = hi2, lo, t5
        elseif S.bosDir == -1 and hi < lo2 and (lo2 - hi) >= minFvg then
            S.fvgLower, S.fvgUpper, S.fvgTime = hi, lo2, t5
        end
        if S.fvgUpper ~= nil and S.fvgLower ~= nil then
            S.fvgMid = (S.fvgUpper + S.fvgLower) / 2
        end
        if S.fvgTime ~= nil then
            if (t5 - S.fvgTime) > (instance.parameters.fvgExpireMinutes * 60) then
                S.fvgTime, S.fvgUpper, S.fvgLower, S.fvgMid = nil, nil, nil, nil
                S.sessionState = STATEWAITASIA
            elseif h5v >= S.fvgLower and l5v <= S.fvgUpper then
                S.fvgMit = true
                S.sessionState = STATEWAITRETEST
            end
        end
    end

    if S.sessionState == STATEWAITRETEST and S.bosLevel ~= nil then
        local a15 = I.atr15[idx15] or a5
        local buff = a15 * ((instance.parameters.manualGrade == "Aplus") and instance.parameters.retestBufferAtrMultAplus or instance.parameters.retestBufferAtrMultA)
        if instance.parameters.retestMode == "BOS" then
            S.retestUpper, S.retestLower = S.bosLevel + buff, S.bosLevel - buff
        elseif instance.parameters.retestMode == "Pivot" then
            S.retestUpper, S.retestLower = S.bosLevel + buff * 2, S.bosLevel - buff * 2
        else
            S.retestUpper, S.retestLower = S.bosLevel + buff * 3, S.bosLevel - buff * 3
        end
        S.retestTime = S.retestTime or t5
        local retHit = h5v >= S.retestLower and l5v <= S.retestUpper
        if retHit and ((t5 - S.blue1Last) / 60) >= instance.parameters.cooldownBlue1 and not dayBlocked then
            S.blue1, S.blue1Last, S.sessionState = true, t5, STATEENTRYWINDOW
            if instance.parameters.consumeSlotOn == "Blue1" then
                S.todayTradeCount = S.todayTradeCount + 1
            end
        end
        if S.retestTime and (t5 - S.retestTime) > (instance.parameters.entryExpireMinutes * 60) then
            S.sessionState = STATEWAITASIA
        end
    end

    if S.sessionState == STATEENTRYWINDOW then
        local canBlue2 = ((t5 - S.blue1Last) / 300) <= instance.parameters.reactionWindowBars
        if canBlue2 and ((t5 - S.blue2Last) / 60) >= instance.parameters.cooldownBlue2 then
            local reclaim = (S.bosDir == 1 and c5 > S.bosLevel) or (S.bosDir == -1 and c5 < S.bosLevel)
            local rejectOk = (not instance.parameters.enableRejectForBlue2) or wickReject(S.bosDir, o5, h5v, l5v, c5, instance.parameters.rejectWickRatioMin, instance.parameters.rejectBodyRatioMax)
            if ((not instance.parameters.requireReclaimForBlue2) or reclaim) and rejectOk then
                S.blue2, S.blue2Last = true, t5
            end
        end

        local emaOk = (not instance.parameters.requireEma20ForBlue3) or ((S.bosDir == 1 and c5 > e20) or (S.bosDir == -1 and c5 < e20))
        local dirOk = (instance.parameters.manualGrade ~= "Aplus") or ((S.bosDir == 1 and c5 > o5) or (S.bosDir == -1 and c5 < o5))
        if ((t5 - S.blue3Last) / 60) >= instance.parameters.cooldownBlue3 and emaOk and dirOk and S.todayTradeCount < instance.parameters.dailyMaxTrades then
            S.blue3, S.blue3Last, S.sessionState = true, t5, STATEWAITASIA
            if instance.parameters.consumeSlotOn == "Blue3" then
                S.todayTradeCount = S.todayTradeCount + 1
            end
        elseif S.todayTradeCount >= instance.parameters.dailyMaxTrades then
            S.blockedReason = "Daily limit reached"
            S.doneToday = true
        end
    end

    S.scoreA = fscore(inNy, S.sweepUsed, S.bosLevel ~= nil, S.fvgMit, S.blue3)
    S.scoreAPlus = S.scoreA
    local score = S.scoreA
    local threshold = (instance.parameters.manualGrade == "Aplus") and instance.parameters.scoreThresholdAplus or instance.parameters.scoreThresholdA
    local displayOk = (not instance.parameters.scoreEnabled) or (score >= threshold and score >= instance.parameters.minScoreToDisplay)

    if inFocus and displayOk then
        T.out.asiaH[period] = S.asiaHigh
        T.out.asiaL[period] = S.asiaLow
        T.out.bos[period] = S.bosLevel
        T.out.fvgU[period] = S.fvgUpper
        T.out.fvgL[period] = S.fvgLower
        T.out.retU[period] = S.retestUpper
        T.out.retL[period] = S.retestLower
        if S.blue3 then
            local pip = pipSize(gSource:instrument())
            S.entry = c5
            S.tp = S.entry + (S.bosDir * instance.parameters.targetPips * pip)
            S.sl = S.entry - (S.bosDir * instance.parameters.slPipsDefault * pip)
            T.out.entry[period] = S.entry
            T.out.tp[period] = S.tp
            T.out.sl[period] = S.sl
            T.out.blue3[period] = S.entry
        end
    end

    if instance.parameters.showhud and inFocus then
        T.out.tradeDay[period] = tradeDay and 1 or 0
        T.out.inNy[period] = inNy and 1 or 0
        T.out.hasBos[period] = (S.bosLevel ~= nil) and 1 or 0
        T.out.fvgMit[period] = S.fvgMit and 1 or 0
        T.out.blue1[period] = S.blue1 and 1 or 0
        T.out.blue2[period] = S.blue2 and 1 or 0
        T.out.blue3State[period] = S.blue3 and 1 or 0
        T.out.score[period] = score
        if S.blockedReason == "Daily limit reached" then
            T.out.debug[period] = -1
        elseif dayBlocked then
            T.out.debug[period] = -2
        else
            T.out.debug[period] = 0
        end
    end

    if instance.parameters.focusmode and inFocus == false and instance.parameters.debugMode then
        T.out.debug[period] = -9
    end

    if instance.parameters.focusmode and H.focusStart ~= nil and inNy and inFocus and instance.parameters.debugMode then
        dbg("Focus " .. H.focusKey .. " active; day=" .. tostring(dayK) .. ", trades=" .. tostring(S.todayTradeCount) .. ", score=" .. tostring(score))
    end
end

function ReleaseInstance()
    S.inited = false
end

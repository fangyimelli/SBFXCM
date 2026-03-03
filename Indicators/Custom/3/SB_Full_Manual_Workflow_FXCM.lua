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
local h5 = nil
local h15 = nil
local hD = nil
local streamOHLC5 = {}
local streamOHLC15 = {}
local streamOHLCD = {}

local map5to15 = {}
local map5toD = {}
local focusStart = nil
local focusEnd = nil
local focusKey = nil

local inited = false
local sessionState = STATEWAITASIA
local asiaHigh = nil
local asiaLow = nil
local sweepUsed = false
local sweepDir = 0
local sweepTime = nil
local bosDir = 0
local bosLevel = nil
local bosTime = nil
local fvgU = nil
local fvgL = nil
local fvgTime = nil
local fvgMit = false
local retU = nil
local retL = nil
local retTime = nil

local currentDayKey = nil
local dailyTrades = 0
local blockedReason = ""
local blue1Last = -100000
local blue2Last = -100000
local blue3Last = -100000

local ema20 = {}
local atr5 = {}
local atr15 = {}
local atrD = {}

local outAsiaH, outAsiaL, outBos, outFvgU, outFvgL, outRetU, outRetL, outEntry, outTP, outSL, outBlue3
local outTradeDay, outInNy, outHasBos, outFvgMit, outBlue1, outBlue2, outBlue3State, outScore, outDebug

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

local function safeStream(history, field)
    local candidates = {
        string.lower(field),
        string.upper(field),
        field,
        field .. "s",
    }
    for _, key in ipairs(candidates) do
        local ok, s = pcall(function() return history[key] end)
        if ok and s ~= nil then
            return s
        end
    end
    return nil
end

local function parseHHMM(s)
    local h = tonumber(string.sub(s, 1, 2)) or 0
    local m = tonumber(string.sub(s, 3, 4)) or 0
    return h, m
end

local function parseSession(txt)
    local a, b = string.match(txt, "(%d%d%d%d)%-(%d%d%d%d)")
    return a or "0000", b or "2359"
end

local function minFromDate(t)
    local dt = core.dateToTable(t)
    return dt.hour * 60 + dt.min, dt
end

local function inSession(t, sessionTxt)
    local s1, s2 = parseSession(sessionTxt)
    local h1, m1 = parseHHMM(s1)
    local h2, m2 = parseHHMM(s2)
    local x = h1 * 60 + m1
    local y = h2 * 60 + m2
    local v = minFromDate(t)
    if x <= y then
        return v >= x and v <= y
    end
    return (v >= x) or (v <= y)
end

local function dayKeyFromTime(t)
    local d = core.dateToTable(t)
    return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
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
    ema20[i] = arr[i] * k + (ema20[i - 1] or arr[i]) * (1 - k)
    return ema20[i]
end

local function atrFallback(histO, histH, histL, histC, period, outArr, i)
    if i == 0 then outArr[i] = histH[i] - histL[i]; return outArr[i] end
    local prev = histC[i - 1] or histC[i]
    local tr = math.max(histH[i] - histL[i], math.abs(histH[i] - prev), math.abs(histL[i] - prev))
    outArr[i] = ((outArr[i - 1] or tr) * (period - 1) + tr) / period
    return outArr[i]
end

local function buildMaps()
    map5to15 = {}
    map5toD = {}
    local j15 = 0
    local jD = 0
    for i = 0, h5:size() - 1 do
        local t5 = h5:date(i)
        while j15 + 1 < h15:size() and h15:date(j15 + 1) <= t5 do
            j15 = j15 + 1
        end
        while jD + 1 < hD:size() and hD:date(jD + 1) <= t5 do
            jD = jD + 1
        end
        map5to15[i] = j15
        map5toD[i] = jD
    end
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
        blockedReason = "Blocked: bias=0"
        return true
    end
    if instance.parameters.tradeDayOnly and bias == 0 then
        blockedReason = "Blocked: not TradeDay"
        return true
    end
    return false
end

local function resetDay()
    dailyTrades = 0
    sweepUsed = false
    sessionState = STATEWAITASIA
    asiaHigh = nil
    asiaLow = nil
    sweepDir = 0
    bosDir = 0
    fvgU = nil
    fvgL = nil
    fvgMit = false
    retU = nil
    retL = nil
end

function Prepare(nameOnly)
    gSource = instance.source
    local name = NAME
    instance:name(name)
    if nameOnly then return end

    local first = gSource:first()

    -- Mandatory fixed-argument getHistory signature
    h5 = host:execute("getHistory", gSource:instrument(), "m5", 0, 10000)
    h15 = host:execute("getHistory", gSource:instrument(), "m15", 0, 10000)
    hD = host:execute("getHistory", gSource:instrument(), "D1", 0, 3000)

    streamOHLC5.open = safeStream(h5, "open")
    streamOHLC5.high = safeStream(h5, "high")
    streamOHLC5.low = safeStream(h5, "low")
    streamOHLC5.close = safeStream(h5, "close")

    streamOHLC15.open = safeStream(h15, "open")
    streamOHLC15.high = safeStream(h15, "high")
    streamOHLC15.low = safeStream(h15, "low")
    streamOHLC15.close = safeStream(h15, "close")

    streamOHLCD.open = safeStream(hD, "open")
    streamOHLCD.high = safeStream(hD, "high")
    streamOHLCD.low = safeStream(hD, "low")
    streamOHLCD.close = safeStream(hD, "close")

    buildMaps()

    focusKey = instance.parameters.focusdate
    if instance.parameters.focusmode and focusKey ~= "" then
        local t = parseFocusDate(focusKey)
        if t ~= nil then
            focusStart = t
            focusEnd = t + (24 * 60 * 60)
        end
    end

    outAsiaH = instance:addStream("ASIAH", core.Line, "Asia High", "AsiaH", first)
    outAsiaL = instance:addStream("ASIAL", core.Line, "Asia Low", "AsiaL", first)
    outBos = instance:addStream("BOSLV", core.Line, "BOS Level", "BOS", first)
    outFvgU = instance:addStream("FVGU", core.Line, "FVG Upper", "FVGU", first)
    outFvgL = instance:addStream("FVGL", core.Line, "FVG Lower", "FVGL", first)
    outRetU = instance:addStream("RETU", core.Line, "Retest Upper", "RetU", first)
    outRetL = instance:addStream("RETL", core.Line, "Retest Lower", "RetL", first)
    outEntry = instance:addStream("ENTRY", core.Line, "Entry", "Entry", first)
    outTP = instance:addStream("TP", core.Line, "Take Profit", "TP", first)
    outSL = instance:addStream("SL", core.Line, "Stop Loss", "SL", first)
    outBlue3 = instance:addStream("BLUE3", core.Dot, "Blue3 Signal", "Blue3", first)

    outTradeDay = instance:addStream("TRADEDAY", core.Line, "TradeDay", "TradeDay", first)
    outInNy = instance:addStream("INNY", core.Line, "In NY", "InNY", first)
    outHasBos = instance:addStream("HASBOS", core.Line, "Has BOS", "HasBOS", first)
    outFvgMit = instance:addStream("FVGMIT", core.Line, "FVG Mit", "FvgMit", first)
    outBlue1 = instance:addStream("BLUE1", core.Line, "Blue1", "Blue1", first)
    outBlue2 = instance:addStream("BLUE2", core.Line, "Blue2", "Blue2", first)
    outBlue3State = instance:addStream("BLUE3S", core.Line, "Blue3State", "Blue3State", first)
    outScore = instance:addStream("SCORE", core.Line, "Score", "Score", first)
    outDebug = instance:addStream("DEBUG", core.Line, "Debug", "Debug", first)
end

local function computeBias(dIndex)
    if dIndex < 2 then return 0, false, false end
    local yOpen = streamOHLCD.open[dIndex - 1]
    local yClose = streamOHLCD.close[dIndex - 1]
    local yHigh = streamOHLCD.high[dIndex - 1]
    local yLow = streamOHLCD.low[dIndex - 1]
    local yRange = yHigh - yLow
    local yAtr = atrFallback(streamOHLCD.open, streamOHLCD.high, streamOHLCD.low, streamOHLCD.close, instance.parameters.dayMoveAtrLen, atrD, dIndex - 1)

    local dumpYesterday = (yOpen - yClose) >= (yAtr * instance.parameters.dumpPumpMinAtrMult)
    local pumpYesterday = (yClose - yOpen) >= (yAtr * instance.parameters.dumpPumpMinAtrMult)
    local dFgd = dumpYesterday and yRange >= yAtr
    local dFrd = pumpYesterday and yRange >= yAtr

    local p2Open = streamOHLCD.open[dIndex - 2]
    local p2Close = streamOHLCD.close[dIndex - 2]
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
    if focusStart == nil or focusEnd == nil then return false end
    return t >= focusStart and t < focusEnd
end

local function wickReject(o, h, l, c)
    local body = math.abs(c - o)
    local range = h - l
    if range <= 0 then return false end
    local wick = range - body
    return (wick / range) >= instance.parameters.rejectWickRatioMin and (body / range) <= instance.parameters.rejectBodyRatioMax
end

function Update(period, mode)
    if not inited then inited = true end
    if period < 2 then return end

    local t5 = gSource:date(period)
    local inFocus = visibleForFocus(t5)
    local inAsia = inSession(t5, instance.parameters.asiaSession)
    local inNy = inSession(t5, instance.parameters.nySession)

    local idx15 = map5to15[period] or 0
    local idxD = map5toD[period] or 0

    local o5 = gSource.open[period]
    local h5v = gSource.high[period]
    local l5v = gSource.low[period]
    local c5 = gSource.close[period]

    local a5 = atrFallback(gSource.open, gSource.high, gSource.low, gSource.close, instance.parameters.sweepAtrLen, atr5, period)
    local e20 = emaFallback(gSource.close, 20, period)

    local dayKey = dayKeyFromTime(t5)
    if currentDayKey == nil then currentDayKey = dayKey end
    if dayKey ~= currentDayKey then
        currentDayKey = dayKey
        resetDay()
    end

    local bias, tradeDay = computeBias(idxD)
    local dayBlocked = isBlockedByDayType(bias)

    if inAsia then
        asiaHigh = (asiaHigh == nil) and h5v or math.max(asiaHigh, h5v)
        asiaLow = (asiaLow == nil) and l5v or math.min(asiaLow, l5v)
    end
    if instance.parameters.prefilterLock and inNy and sessionState == STATEWAITASIA and asiaHigh ~= nil and asiaLow ~= nil then
        sessionState = STATEASIAREADY
    end

    local blue1, blue2, blue3 = false, false, false

    if sessionState >= STATEASIAREADY and not sweepUsed and idx15 >= 1 then
        local h15v = streamOHLC15.high[idx15]
        local l15v = streamOHLC15.low[idx15]
        local c15 = streamOHLC15.close[idx15]
        local o15 = streamOHLC15.open[idx15]
        local a15 = atrFallback(streamOHLC15.open, streamOHLC15.high, streamOHLC15.low, streamOHLC15.close, instance.parameters.sweepAtrLen, atr15, idx15)
        local mintick = instance.bid:instrument():getPipSize() or 0.0001
        local sweepThreshold = math.max(instance.parameters.sweepMinTicks * mintick, a15 * instance.parameters.sweepMinAtrMult)

        local upSweep = asiaHigh ~= nil and (h15v - asiaHigh) >= sweepThreshold
        local dnSweep = asiaLow ~= nil and (asiaLow - l15v) >= sweepThreshold
        local reclaimUp = c15 < asiaHigh or (instance.parameters.manualGrade == "A" and o15 < asiaHigh)
        local reclaimDn = c15 > asiaLow or (instance.parameters.manualGrade == "A" and o15 > asiaLow)

        if upSweep and reclaimUp then
            sweepUsed = true
            sweepDir = 1
            sweepTime = t5
            sessionState = STATESWEPT
        elseif dnSweep and reclaimDn then
            sweepUsed = true
            sweepDir = -1
            sweepTime = t5
            sessionState = STATESWEPT
        end
    end

    if sessionState == STATESWEPT and idx15 >= (instance.parameters.bosSwingLeft + instance.parameters.bosSwingRight + 1) then
        local hh = streamOHLC15.high[idx15 - 1]
        local ll = streamOHLC15.low[idx15 - 1]
        local c15 = streamOHLC15.close[idx15]
        local h15v = streamOHLC15.high[idx15]
        local l15v = streamOHLC15.low[idx15]
        local a15 = atr15[idx15] or atrFallback(streamOHLC15.open, streamOHLC15.high, streamOHLC15.low, streamOHLC15.close, instance.parameters.sweepAtrLen, atr15, idx15)

        local minBos = a15 * ((instance.parameters.manualGrade == "Aplus") and instance.parameters.bosMinAtrMultAplus or instance.parameters.bosMinAtrMultA)
        if sweepDir == 1 then
            local broke = ((instance.parameters.manualGrade == "Aplus") and c15 < ll) or (l15v < ll)
            if broke and (ll - l15v) >= minBos then
                bosDir = -1
                bosLevel = ll
                bosTime = t5
                sessionState = instance.parameters.useFvg and STATEWAITFVG or STATEWAITRETEST
            end
        elseif sweepDir == -1 then
            local broke = ((instance.parameters.manualGrade == "Aplus") and c15 > hh) or (h15v > hh)
            if broke and (h15v - hh) >= minBos then
                bosDir = 1
                bosLevel = hh
                bosTime = t5
                sessionState = instance.parameters.useFvg and STATEWAITFVG or STATEWAITRETEST
            end
        end
    end

    if sessionState == STATEWAITFVG and idx15 >= 2 then
        local lo = streamOHLC15.low[idx15]
        local hi2 = streamOHLC15.high[idx15 - 2]
        local hi = streamOHLC15.high[idx15]
        local lo2 = streamOHLC15.low[idx15 - 2]
        local a15 = atr15[idx15] or 0
        local minFvg = a15 * ((instance.parameters.manualGrade == "Aplus") and instance.parameters.fvgMinAtrMultAplus or instance.parameters.fvgMinAtrMultA)

        if bosDir == 1 and lo > hi2 and (lo - hi2) >= minFvg then
            fvgL = hi2
            fvgU = lo
            fvgTime = t5
        elseif bosDir == -1 and hi < lo2 and (lo2 - hi) >= minFvg then
            fvgL = hi
            fvgU = lo2
            fvgTime = t5
        end

        if fvgTime ~= nil then
            local exp = instance.parameters.fvgExpireMinutes * 60
            if (t5 - fvgTime) > exp then
                fvgTime = nil
                fvgU = nil
                fvgL = nil
                sessionState = STATEWAITASIA
            else
                if h5v >= fvgL and l5v <= fvgU then
                    fvgMit = true
                    sessionState = STATEWAITRETEST
                end
            end
        end
    end

    if sessionState == STATEWAITRETEST and bosLevel ~= nil then
        local a15 = atr15[idx15] or a5
        local buff = a15 * ((instance.parameters.manualGrade == "Aplus") and instance.parameters.retestBufferAtrMultAplus or instance.parameters.retestBufferAtrMultA)
        if instance.parameters.retestMode == "BOS" then
            retU = bosLevel + buff
            retL = bosLevel - buff
        elseif instance.parameters.retestMode == "Pivot" then
            retU = bosLevel + buff * 2
            retL = bosLevel - buff * 2
        else
            retU = bosLevel + buff * 3
            retL = bosLevel - buff * 3
        end
        retTime = retTime or t5
        local retHit = h5v >= retL and l5v <= retU
        if retHit then
            local minsSinceBlue1 = (t5 - blue1Last) / 60
            if minsSinceBlue1 >= instance.parameters.cooldownBlue1 and not dayBlocked then
                blue1 = true
                blue1Last = t5
                sessionState = STATEENTRYWINDOW
                if instance.parameters.consumeSlotOn == "Blue1" then
                    dailyTrades = dailyTrades + 1
                end
            end
        end

        if retTime and (t5 - retTime) > (instance.parameters.entryExpireMinutes * 60) then
            sessionState = STATEWAITASIA
        end
    end

    if sessionState == STATEENTRYWINDOW then
        local canBlue2 = ((t5 - blue1Last) / 300) <= instance.parameters.reactionWindowBars
        if canBlue2 then
            local minsSinceBlue2 = (t5 - blue2Last) / 60
            if minsSinceBlue2 >= instance.parameters.cooldownBlue2 then
                local reclaim = (bosDir == 1 and c5 > bosLevel) or (bosDir == -1 and c5 < bosLevel)
                local rejectOk = (not instance.parameters.enableRejectForBlue2) or wickReject(o5, h5v, l5v, c5)
                if ((not instance.parameters.requireReclaimForBlue2) or reclaim) and rejectOk then
                    blue2 = true
                    blue2Last = t5
                end
            end
        end

        local minsSinceBlue3 = (t5 - blue3Last) / 60
        local emaOk = (not instance.parameters.requireEma20ForBlue3) or ((bosDir == 1 and c5 > e20) or (bosDir == -1 and c5 < e20))
        local dirOk = (instance.parameters.manualGrade ~= "Aplus") or ((bosDir == 1 and c5 > o5) or (bosDir == -1 and c5 < o5))
        if minsSinceBlue3 >= instance.parameters.cooldownBlue3 and emaOk and dirOk and dailyTrades < instance.parameters.dailyMaxTrades then
            blue3 = true
            blue3Last = t5
            sessionState = STATEWAITASIA
            if instance.parameters.consumeSlotOn == "Blue3" then
                dailyTrades = dailyTrades + 1
            end
        elseif dailyTrades >= instance.parameters.dailyMaxTrades then
            blockedReason = "Daily limit reached"
        end
    end

    local score = fscore(inNy, sweepUsed, bosLevel ~= nil, fvgMit, blue3)
    local threshold = (instance.parameters.manualGrade == "Aplus") and instance.parameters.scoreThresholdAplus or instance.parameters.scoreThresholdA
    local displayOk = (not instance.parameters.scoreEnabled) or (score >= threshold and score >= instance.parameters.minScoreToDisplay)

    if inFocus and displayOk then
        outAsiaH[period] = asiaHigh
        outAsiaL[period] = asiaLow
        outBos[period] = bosLevel
        outFvgU[period] = fvgU
        outFvgL[period] = fvgL
        outRetU[period] = retU
        outRetL[period] = retL
        if blue3 then
            local entry = c5
            local pip = instance.bid:instrument():getPipSize() or 0.0001
            local tp = entry + (bosDir * instance.parameters.targetPips * pip)
            local sl = entry - (bosDir * instance.parameters.slPipsDefault * pip)
            outEntry[period] = entry
            outTP[period] = tp
            outSL[period] = sl
            outBlue3[period] = entry
        end
    end

    if instance.parameters.showhud and inFocus then
        outTradeDay[period] = tradeDay and 1 or 0
        outInNy[period] = inNy and 1 or 0
        outHasBos[period] = (bosLevel ~= nil) and 1 or 0
        outFvgMit[period] = fvgMit and 1 or 0
        outBlue1[period] = blue1 and 1 or 0
        outBlue2[period] = blue2 and 1 or 0
        outBlue3State[period] = blue3 and 1 or 0
        outScore[period] = score
        if blockedReason == "Daily limit reached" then
            outDebug[period] = -1
        elseif dayBlocked then
            outDebug[period] = -2
        else
            outDebug[period] = 0
        end
    end

    if instance.parameters.focusmode and inFocus == false and instance.parameters.debugMode then
        outDebug[period] = -9
    end

    if instance.parameters.focusmode and focusStart ~= nil and inNy and inFocus and instance.parameters.debugMode then
        dbg("Focus " .. focusKey .. " active; day=" .. dayKey .. ", trades=" .. tostring(dailyTrades) .. ", score=" .. tostring(score))
    end
end

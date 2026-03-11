function Init()
    indicator:name("SB Entry Qualifier")
    indicator:description("SB Entry Qualifier")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addBoolean("usefvg", "Use FVG", "Enable fair value gap filter", true)
    indicator.parameters:addInteger("fvglookback", "FVG Lookback", "Bars to scan for fair value gaps", 20)
    indicator.parameters:addInteger("fvgexpire", "FVG Expire", "Bars before a fair value gap expires", 10)
    indicator.parameters:addDouble("fvgminatra", "FVG Min ATR", "Minimum ATR multiple for fair value gap size", 1.0)
    indicator.parameters:addDouble("fvgminatraP", "FVG Min ATR Percent", "Minimum ATR ratio percent threshold for fair value gap size", 100.0)
    indicator.parameters:addString("retestmode", "Retest Mode", "Retest mode selector", "BOS")
    indicator.parameters:addDouble("retbufa", "Retest Buffer ATR", "Retest buffer in ATR units", 0.1)
    indicator.parameters:addDouble("retbufaP", "Retest Buffer ATR Percent", "Retest buffer ATR percent", 10.0)
    indicator.parameters:addInteger("entryexp", "Entry Expire", "Bars before entry signal expires", 3)
    indicator.parameters:addBoolean("usebluelights", "Use Blue Lights", "Enable blue lights gating", true)
    indicator.parameters:addInteger("reactbars", "React Bars", "Maximum bars allowed for reaction", 2)
    indicator.parameters:addBoolean("requirereclaimb2", "Require Reclaim B2", "Require reclaim confirmation on blue light stage two", false)
    indicator.parameters:addBoolean("enablerejectb2", "Enable Reject B2", "Enable rejection filter on blue light stage two", true)
    indicator.parameters:addDouble("rejectwickmin", "Reject Wick Min", "Minimum wick ratio for rejection filter", 0.5)
    indicator.parameters:addDouble("rejectbodymax", "Reject Body Max", "Maximum body ratio for rejection filter", 0.5)
    indicator.parameters:addInteger("cdblue1", "Cooldown Blue 1", "Cooldown bars for blue light stage one", 0)
    indicator.parameters:addInteger("cdblue2", "Cooldown Blue 2", "Cooldown bars for blue light stage two", 0)
    indicator.parameters:addInteger("cdblue3", "Cooldown Blue 3", "Cooldown bars for blue light stage three", 0)
    indicator.parameters:addBoolean("reqema20b3", "Require EMA20 B3", "Require EMA20 alignment for blue light stage three", false)
    indicator.parameters:addBoolean("debug", "Debug", "Enable debug traces", false)
end

local source = nil
local first = nil
local S = {}
local T = {}
local H = {}
local I = {}

local IDLE, WAITFVG, WAITMIT, WAITRET, BLUE1, BLUE2, BLUE3, BLOCKED, EXPIRED, FAILED, DONE =
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

-- safety helpers ------------------------------------------------------------
local function dayKey(ts)
    if ts == nil then
        return nil
    end
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
    if ts == nil then
        return nil
    end
    local f = ts - math.floor(ts)
    if f < 0 then
        f = f + 1
    end
    local m = math.floor(f * 1440 + 0.000001)
    if m < 0 then
        m = 0
    elseif m > 1439 then
        m = 1439
    end
    return m
end

local function inSession(ts, sess)
    if ts == nil or sess == nil or sess == "" then
        return false
    end

    local nowMin = minuteOfDay(ts)
    if nowMin == nil then
        return false
    end

    for token in string.gmatch(sess, "[^,]+") do
        local a, b = string.match(token, "^%s*(%d%d?:?%d%d)%s*%-%s*(%d%d?:?%d%d)%s*$")
        if a ~= nil and b ~= nil then
            local s = parseHHMM(a)
            local e = parseHHMM(b)
            if s ~= nil and e ~= nil then
                if s <= e and nowMin >= s and nowMin <= e then
                    return true
                end
                if s > e and (nowMin >= s or nowMin <= e) then
                    return true
                end
            end
        end
    end

    return false
end

local function wickReject(openPrice, highPrice, lowPrice, closePrice, dir, minWickRatio, maxBodyRatio)
    if openPrice == nil or highPrice == nil or lowPrice == nil or closePrice == nil then
        return false
    end

    local range = highPrice - lowPrice
    if range <= 0 then
        return false
    end

    local body = math.abs(closePrice - openPrice) / range
    local upperWick = (highPrice - math.max(openPrice, closePrice)) / range
    local lowerWick = (math.min(openPrice, closePrice) - lowPrice) / range

    if body > (maxBodyRatio or 0.5) then
        return false
    end

    local wickMin = minWickRatio or 0.5
    if dir ~= nil and dir < 0 then
        return upperWick >= wickMin
    end
    return lowerWick >= wickMin
end

local function pivotHigh(stream, p, left, right)
    if stream == nil or p == nil then
        return nil
    end
    local start = p - (left or 0)
    local stop = p + (right or 0)
    if start < stream:first() or stop > stream:size() - 1 then
        return nil
    end

    local ph = stream.high[p]
    local i = start
    while i <= stop do
        if i ~= p and stream.high[i] >= ph then
            return nil
        end
        i = i + 1
    end
    return ph
end

local function pivotLow(stream, p, left, right)
    if stream == nil or p == nil then
        return nil
    end
    local start = p - (left or 0)
    local stop = p + (right or 0)
    if start < stream:first() or stop > stream:size() - 1 then
        return nil
    end

    local pl = stream.low[p]
    local i = start
    while i <= stop do
        if i ~= p and stream.low[i] <= pl then
            return nil
        end
        i = i + 1
    end
    return pl
end

local function safeGetHistory(instrument, timeframe, isBid)
    local ok, history = pcall(function()
        return core.host:execute("getSyncHistory", instrument, timeframe, isBid, 0, 0)
    end)

    if not ok or history == nil then
        return nil, "getSyncHistory failed for " .. tostring(timeframe)
    end

    return history, nil
end

local function safeGetPriceStream(history, field)
    if history == nil then
        return nil, "history is nil for field " .. tostring(field)
    end
    local ok, stream = pcall(function() return history[field] end)
    if not ok or stream == nil then
        return nil, "price stream unavailable: " .. tostring(field)
    end
    return stream, nil
end

local function safeAddStream(id, style, label, color, firstPeriod)
    local ok, stream = pcall(function()
        return instance:addStream(id, style, label, "", color, firstPeriod)
    end)
    if not ok or stream == nil then
        return nil, "addStream failed for " .. tostring(id)
    end
    return stream, nil
end

local function emptyStreamValue()
    return nil
end

local function normalizeStreamValue(value)
    if value == nil then
        return emptyStreamValue()
    end
    if type(value) == "number" and value ~= value then
        return emptyStreamValue()
    end
    return value
end

local function isTriggerOnPeriod(triggerMark, period)
    if triggerMark == nil or period == nil then
        return false
    end
    if triggerMark == period then
        return true
    end
    if source == nil or source.date == nil then
        return false
    end
    local ts = source:date(period)
    if ts == nil then
        return false
    end
    return triggerMark == ts
end

local function writeEntryStreams(period)
    if T.fvgu ~= nil then
        T.fvgu[period] = normalizeStreamValue(S.fvgUpper)
    end
    if T.fvgl ~= nil then
        T.fvgl[period] = normalizeStreamValue(S.fvgLower)
    end
    if T.retu ~= nil then
        T.retu[period] = normalizeStreamValue(S.retestUpper)
    end
    if T.retl ~= nil then
        T.retl[period] = normalizeStreamValue(S.retestLower)
    end

    local closePrice = source ~= nil and source.close[period] or nil
    local blue1Value = isTriggerOnPeriod(S.blue1Time, period) and closePrice or emptyStreamValue()
    local blue2Value = isTriggerOnPeriod(S.blue2Time, period) and closePrice or emptyStreamValue()
    local blue3Value = isTriggerOnPeriod(S.blue3Time, period) and closePrice or emptyStreamValue()

    if T.blue1 ~= nil then
        T.blue1[period] = normalizeStreamValue(blue1Value)
    end
    if T.blue2 ~= nil then
        T.blue2[period] = normalizeStreamValue(blue2Value)
    end
    if T.blue3 ~= nil then
        T.blue3[period] = normalizeStreamValue(blue3Value)
    end
    if T.statedebug ~= nil then
        T.statedebug[period] = normalizeStreamValue(S.state)
    end

    if T.fvgmid ~= nil then
        T.fvgmid[period] = normalizeStreamValue(S.fvgMid)
    end
end

local function inCooldown(lastTs, minutes, nowTs)
    if lastTs == nil or minutes == nil or minutes <= 0 or nowTs == nil then
        return false
    end
    local spanDays = minutes / 1440
    return nowTs <= (lastTs + spanDays)
end

local function calcATR(history, idx, len)
    if history == nil or idx == nil or len == nil or len <= 0 then
        return nil
    end

    local start = idx - len + 1
    if start < history:first() + 1 then
        return nil
    end

    local sum = 0
    local count = 0
    local i = start
    while i <= idx do
        local h = history.high[i]
        local l = history.low[i]
        local c1 = history.close[i - 1]
        local tr = math.max(h - l, math.max(math.abs(h - c1), math.abs(l - c1)))
        sum = sum + tr
        count = count + 1
        i = i + 1
    end

    if count == 0 then
        return nil
    end
    return sum / count
end

local function block(reason)
    S.blockedReason = reason
    trace("blocked: " .. tostring(reason))
end

local function trace(message)
    if not T.debug then
        return
    end

    local text = "[SB_Entry_Qualifier] " .. tostring(message)
    if terminal ~= nil and terminal:alertMessage ~= nil then
        terminal:alertMessage(text, core.now())
    elseif core ~= nil and core.host ~= nil and core.host:trace ~= nil then
        core.host:trace(text)
    end
end

local function getParam(id, defaultValue)
    local value = instance.parameters[id]
    if value == nil then
        trace("missing parameter '" .. tostring(id) .. "', fallback to " .. tostring(defaultValue))
        return defaultValue
    end
    return value
end

function Prepare(nameOnly)
    source = instance.source
    first = source:first()

    S.state = IDLE
    S.dayKey = nil
    S.bosDir = nil
    S.bosLevel = nil
    S.bosTime = nil
    S.bosValidMinutes = 180
    S.lastPivotHigh = nil
    S.lastPivotLow = nil
    S.lastPivotHighTime = nil
    S.lastPivotLowTime = nil
    S.fvgUpper = nil
    S.fvgLower = nil
    S.fvgMid = nil
    S.fvgTime = nil
    S.fvgMit = nil
    S.retestUpper = nil
    S.retestLower = nil
    S.retestTime = nil
    S.blue1Time = nil
    S.blue2Time = nil
    S.blue3Time = nil
    S.lastBlue1Alert = nil
    S.lastBlue2Alert = nil
    S.lastBlue3Alert = nil
    S.blockedReason = nil

    H.source = source
    H.m5 = nil
    H.m15 = nil
    H.d1 = nil

    I.atr = nil
    I.ema20 = nil
    I.ema20m5 = nil
    I.atr15 = nil
    I.atr15Fallback = true

    T.debug = instance.parameters.debug == true
    T.usefvg = getParam("usefvg", true)
    T.fvglookback = getParam("fvglookback", 20)
    T.fvgexpire = getParam("fvgexpire", 10)
    T.fvgminatra = getParam("fvgminatra", 1.0)
    T.fvgminatraP = getParam("fvgminatraP", 100.0)
    T.retestmode = getParam("retestmode", "BOS")
    T.retbufa = getParam("retbufa", 0.1)
    T.retbufaP = getParam("retbufaP", 10.0)
    T.entryexp = getParam("entryexp", 3)
    T.usebluelights = getParam("usebluelights", true)
    T.reactbars = getParam("reactbars", 2)
    T.requirereclaimb2 = getParam("requirereclaimb2", false)
    T.enablerejectb2 = getParam("enablerejectb2", true)
    T.rejectwickmin = getParam("rejectwickmin", 0.5)
    T.rejectbodymax = getParam("rejectbodymax", 0.5)
    T.cdblue1 = getParam("cdblue1", 0)
    T.cdblue2 = getParam("cdblue2", 0)
    T.cdblue3 = getParam("cdblue3", 0)
    T.reqema20b3 = getParam("reqema20b3", false)

    T.fvgu = safeAddStream("fvgu", core.Line, "FVG Upper", core.rgb(0, 206, 209), first)
    T.fvgl = safeAddStream("fvgl", core.Line, "FVG Lower", core.rgb(0, 139, 139), first)
    T.retu = safeAddStream("retu", core.Line, "Retest Upper", core.rgb(255, 165, 0), first)
    T.retl = safeAddStream("retl", core.Line, "Retest Lower", core.rgb(255, 140, 0), first)
    T.blue1 = safeAddStream("blue1", core.Line, "Blue 1", core.rgb(30, 144, 255), first)
    T.blue2 = safeAddStream("blue2", core.Line, "Blue 2", core.rgb(65, 105, 225), first)
    T.blue3 = safeAddStream("blue3", core.Line, "Blue 3", core.rgb(0, 0, 255), first)
    T.statedebug = safeAddStream("statedebug", core.Line, "State", core.rgb(138, 43, 226), first)
    -- Optional stream: enable when runtime stability is confirmed.
    T.fvgmid = nil

    local instrument = source ~= nil and source:instrument() or nil
    local isBid = source ~= nil and source:isBid() or true

    local reason = nil
    H.m5, reason = safeGetHistory(instrument, "m5", isBid)
    if H.m5 == nil then
        trace(reason)
        block("mtf_m5_missing")
    end

    H.m15, reason = safeGetHistory(instrument, "m15", isBid)
    if H.m15 == nil then
        trace(reason)
        block("mtf_m15_missing")
    end

    H.d1, reason = safeGetHistory(instrument, "D1", isBid)
    if H.d1 == nil and reason ~= nil then
        trace("optional daily history unavailable: " .. reason)
    end

    local m5Close = nil
    m5Close, reason = safeGetPriceStream(H.m5, "close")
    if m5Close == nil then
        trace(reason)
        block("m5_close_missing")
    end

    local okEma, emaObj = pcall(function()
        return core.indicators:create("EMA", m5Close, 20)
    end)
    if okEma and emaObj ~= nil then
        I.ema20m5 = emaObj
    else
        I.ema20m5 = { stream = m5Close, period = 20, fallback = true }
        trace("EMA(20) on m5 close unavailable, using rolling fallback")
    end

    local okAtr, atrObj = pcall(function()
        return core.indicators:create("ATR", H.m15, 14)
    end)
    if okAtr and atrObj ~= nil then
        I.atr15 = atrObj
        I.atr15Fallback = false
    else
        I.atr15 = { history = H.m15, period = 14, fallback = true }
        I.atr15Fallback = true
        trace("ATR(14) on m15 unavailable, using rolling ATR fallback")
    end

    instance:name(profile:id() .. "(" .. source:name() .. ")")
end

local function locateHistoryIndex(history, ts)
    if history == nil or ts == nil then
        return nil
    end
    local i = history:size() - 1
    while i >= history:first() do
        local barTs = history:date(i)
        if barTs ~= nil and barTs <= ts then
            return i
        end
        i = i - 1
    end
    return nil
end

local function currentATR15(m15Index)
    if I.atr15 == nil or H.m15 == nil or m15Index == nil then
        return nil
    end
    if I.atr15Fallback == true then
        return calcATR(H.m15, m15Index, 14)
    end
    return I.atr15.DATA[m15Index]
end

local function resetFvg(waitState)
    S.fvgUpper = nil
    S.fvgLower = nil
    S.fvgMid = nil
    S.fvgTime = nil
    S.fvgMit = nil
    if waitState ~= nil then
        S.state = waitState
    end
end

-- minimal BOS prerequisite for entry qualifier ------------------------------
-- This block only provides the minimum BOS payload needed by entry filters:
--   * direction  : S.bosDir
--   * key level  : S.bosLevel
--   * trigger ts : S.bosTime
--
-- Replaceable sync point:
-- If an external structure engine is introduced later, replace this function
-- with a state-sync adapter that writes the same three fields.
local function updateMinimalBos(period)
    local nowTs = source:date(period)
    local m15Index = locateHistoryIndex(H.m15, nowTs)
    if m15Index == nil then
        S.bosDir = nil
        S.bosLevel = nil
        S.bosTime = nil
        S.blockedReason = "bos_unavailable"
        resetFvg(WAITFVG)
        return false
    end

    local pivotIndex = m15Index - 2
    if pivotIndex >= (H.m15:first() + 2) then
        local ph = pivotHigh(H.m15, pivotIndex, 2, 2)
        if ph ~= nil then
            S.lastPivotHigh = ph
            S.lastPivotHighTime = H.m15:date(pivotIndex)
        end

        local pl = pivotLow(H.m15, pivotIndex, 2, 2)
        if pl ~= nil then
            S.lastPivotLow = pl
            S.lastPivotLowTime = H.m15:date(pivotIndex)
        end
    end

    local breakIndex = m15Index - 1
    if breakIndex >= H.m15:first() then
        local c = H.m15.close[breakIndex]
        local breakTs = H.m15:date(breakIndex)
        if c ~= nil and breakTs ~= nil then
            if S.lastPivotHigh ~= nil and S.lastPivotHighTime ~= nil and breakTs >= S.lastPivotHighTime and c > S.lastPivotHigh then
                S.bosDir = 1
                S.bosLevel = S.lastPivotHigh
                S.bosTime = breakTs
            elseif S.lastPivotLow ~= nil and S.lastPivotLowTime ~= nil and breakTs >= S.lastPivotLowTime and c < S.lastPivotLow then
                S.bosDir = -1
                S.bosLevel = S.lastPivotLow
                S.bosTime = breakTs
            end
        end
    end

    if S.bosTime ~= nil and S.bosValidMinutes ~= nil and S.bosValidMinutes > 0 then
        local expireTs = S.bosTime + (S.bosValidMinutes / 1440)
        if nowTs > expireTs then
            S.bosDir = nil
            S.bosLevel = nil
            S.bosTime = nil
            S.blockedReason = "bos_expired"
            resetFvg(WAITFVG)
            return false
        end
    end

    if S.bosDir == nil or S.bosLevel == nil or S.bosTime == nil then
        S.blockedReason = "bos_invalid"
        resetFvg(WAITFVG)
        return false
    end

    if S.blockedReason == "bos_unavailable" or S.blockedReason == "bos_expired" or S.blockedReason == "bos_invalid" then
        S.blockedReason = nil
    end

    return true
end

local function updateFvg(period)
    if T.usefvg ~= true then
        S.state = WAITRET
        return
    end

    local nowTs = source:date(period)
    local m15Index = locateHistoryIndex(H.m15, nowTs)
    if m15Index == nil or m15Index < (H.m15:first() + 2) then
        return
    end

    if S.state == WAITMIT and S.fvgTime ~= nil and T.fvgexpire > 0 then
        if nowTs > (S.fvgTime + (T.fvgexpire / 1440)) then
            resetFvg(WAITFVG)
        end
        return
    end

    if S.state ~= WAITFVG then
        return
    end

    local low = H.m15.low[m15Index]
    local high = H.m15.high[m15Index]
    local low2 = H.m15.low[m15Index - 2]
    local high2 = H.m15.high[m15Index - 2]
    local bull = low > high2
    local bear = high < low2
    if (S.bosDir or 0) > 0 and not bull then
        return
    end
    if (S.bosDir or 0) < 0 and not bear then
        return
    end

    local upper = nil
    local lower = nil
    if bull then
        upper = low
        lower = high2
    elseif bear then
        upper = low2
        lower = high
    else
        return
    end

    local atr15 = currentATR15(m15Index)
    if atr15 == nil then
        return
    end
    local minByA = atr15 * (T.fvgminatra or 0)
    local minByP = atr15 * ((T.fvgminatraP or 0) / 100)
    local minGap = math.max(minByA, minByP)
    if (upper - lower) < minGap then
        return
    end

    S.fvgUpper = upper
    S.fvgLower = lower
    S.fvgMid = (upper + lower) / 2
    S.fvgTime = H.m15:date(m15Index)
    S.fvgMit = false
    S.state = WAITMIT
end

local function updateMitigation(period)
    if S.state ~= WAITMIT or S.fvgUpper == nil or S.fvgLower == nil then
        return
    end
    local price = nil
    if (S.bosDir or 0) > 0 then
        price = H.m5.low[period]
        if price == nil then return end
        local isAplus = S.isAplus == true
        local target = isAplus and (S.fvgMid or S.fvgUpper) or S.fvgUpper
        if price <= target then
            S.fvgMit = true
            S.state = WAITRET
        end
    elseif (S.bosDir or 0) < 0 then
        price = H.m5.high[period]
        if price == nil then return end
        local isAplus = S.isAplus == true
        local target = isAplus and (S.fvgMid or S.fvgLower) or S.fvgLower
        if price >= target then
            S.fvgMit = true
            S.state = WAITRET
        end
    end
end

local function updateRetest(period)
    if S.state ~= WAITRET then
        return false
    end
    local nowTs = source:date(period)
    if S.retestTime ~= nil and T.entryexp > 0 and nowTs > (S.retestTime + (T.entryexp / 1440)) then
        S.retestUpper = nil
        S.retestLower = nil
        S.retestTime = nil
        resetFvg(WAITFVG)
        return false
    end

    local m15Index = locateHistoryIndex(H.m15, nowTs)
    local atr15 = currentATR15(m15Index)
    if atr15 == nil then
        return false
    end
    local buf = math.max(atr15 * (T.retbufa or 0), atr15 * ((T.retbufaP or 0) / 100))

    local mode = string.upper(tostring(T.retestmode or "BOS"))
    local center = S.bosLevel or source.close[period]
    if mode == "PREPIVOT" then
        if (S.bosDir or 0) > 0 then
            center = pivotHigh(H.m5, period - 1, 2, 2) or center
        else
            center = pivotLow(H.m5, period - 1, 2, 2) or center
        end
    elseif mode == "BAND" then
        center = S.fvgMid or center
    end

    S.retestUpper = center + buf
    S.retestLower = center - buf
    S.retestTime = S.retestTime or nowTs

    local hit = false
    if (S.bosDir or 0) > 0 then
        hit = H.m5.low[period] <= S.retestUpper and H.m5.high[period] >= S.retestLower
    elseif (S.bosDir or 0) < 0 then
        hit = H.m5.high[period] >= S.retestLower and H.m5.low[period] <= S.retestUpper
    end
    return hit
end

local function updateBlueSignals(period, retestHit)
    local nowTs = source:date(period)
    local blocked = S.blockedReason ~= nil
    if retestHit and T.usebluelights and not blocked and not inCooldown(S.lastBlue1Alert, T.cdblue1, nowTs) then
        S.blue1Time = nowTs
        S.lastBlue1Alert = nowTs
        S.state = BLUE1
    end

    if S.blue1Time ~= nil and (nowTs - S.blue1Time) <= ((T.reactbars or 0) / 288) then
        local reclaimOk = true
        if T.requirereclaimb2 then
            if (S.bosDir or 0) > 0 then
                reclaimOk = source.close[period] >= (S.retestUpper or source.close[period])
            else
                reclaimOk = source.close[period] <= (S.retestLower or source.close[period])
            end
        end
        local rejectOk = true
        if T.enablerejectb2 then
            rejectOk = wickReject(source.open[period], source.high[period], source.low[period], source.close[period], S.bosDir, T.rejectwickmin, T.rejectbodymax)
        end
        if reclaimOk and rejectOk and not inCooldown(S.lastBlue2Alert, T.cdblue2, nowTs) then
            S.blue2Time = nowTs
            S.lastBlue2Alert = nowTs
            S.state = BLUE2
        end
    end

    if S.blue2Time ~= nil then
        local dirOk = ((S.bosDir or 0) > 0 and source.close[period] >= source.open[period]) or
            ((S.bosDir or 0) < 0 and source.close[period] <= source.open[period])
        local emaOk = true
        if T.reqema20b3 then
            local ema = I.ema20m5.DATA ~= nil and I.ema20m5.DATA[period] or nil
            if ema == nil and I.ema20m5.fallback == true then
                ema = source.median[period]
            end
            if (S.bosDir or 0) > 0 then
                emaOk = source.close[period] >= ema
            else
                emaOk = source.close[period] <= ema
            end
        end
        if dirOk and emaOk and not inCooldown(S.lastBlue3Alert, T.cdblue3, nowTs) then
            S.blue3Time = nowTs
            S.lastBlue3Alert = nowTs
            S.state = BLUE3
        end
    end
end

function Update(period, mode)
    if period < first then
        return
    end

    if H.m5 == nil or H.m15 == nil then
        block("mtf_dependency_missing")
        writeEntryStreams(period)
        return
    end

    if I.ema20m5 == nil then
        block("ema20m5_unavailable")
        writeEntryStreams(period)
        return
    end

    if I.atr15 == nil then
        block("atr15_unavailable")
        writeEntryStreams(period)
        return
    end

    if I.atr15Fallback == true then
        local idx = locateHistoryIndex(H.m15, source:date(period))
        local atr = calcATR(H.m15, idx, 14)
        if atr == nil then
            block("atr15_fallback_not_ready")
            writeEntryStreams(period)
            return
        end
    end

    if S.state == IDLE then
        S.state = WAITFVG
    end

    local bosReady = updateMinimalBos(period)
    if not bosReady then
        writeEntryStreams(period)
        return
    end

    updateFvg(period)
    updateMitigation(period)
    local retestHit = updateRetest(period)
    updateBlueSignals(period, retestHit)

    writeEntryStreams(period)
end

function ReleaseInstance()
end

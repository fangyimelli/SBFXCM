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
    indicator.parameters:addString("retestmode", "Retest Mode", "Retest mode selector", "close")
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

local function inCooldown(lastPeriod, cooldownBars, nowPeriod)
    if lastPeriod == nil or cooldownBars == nil or cooldownBars <= 0 or nowPeriod == nil then
        return false
    end
    return nowPeriod <= (lastPeriod + cooldownBars)
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
    S.fvgUpper = nil
    S.fvgLower = nil
    S.fvgMid = nil
    S.fvgTime = nil
    S.fvgMit = nil
    S.retestUpper = nil
    S.retestLower = nil
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
    T.retestmode = getParam("retestmode", "close")
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

function Update(period, mode)
    if period < first then
        return
    end

    if H.m5 == nil or H.m15 == nil then
        block("mtf_dependency_missing")
        return
    end

    if I.ema20m5 == nil then
        block("ema20m5_unavailable")
        return
    end

    if I.atr15 == nil then
        block("atr15_unavailable")
        return
    end

    if I.atr15Fallback == true then
        local idx = H.m15:size() - 1
        local atr = calcATR(H.m15, idx, 14)
        if atr == nil then
            block("atr15_fallback_not_ready")
            return
        end
    end
end

function ReleaseInstance()
end

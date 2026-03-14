local S = {
    source = nil,
    first = nil,
    state = {
        day = {
            isTradeDay = false,
            isFrd = false,
            isFgd = false,
            bias = 0
        },
        consolidation = {
            idSeed = 0,
            active = false,
            id = nil,
            high = nil,
            low = nil,
            startBar = nil,
            endBar = nil,
            lastInsideBar = nil,
            brokenDown = false,
            brokenUp = false
        },
        session = {
            active = false,
            sourceConsolidationId = nil,
            startBar = nil,
            high = nil,
            low = nil
        },
        events = {
            consolidationCreated = nil,
            bisFired = nil,
            sessionHighUpdated = nil,
            sessionLowUpdated = nil,
            lastBisConsolidationId = nil
        },
        display = {
            setupId = nil,
            consShown = false,
            bisShown = false,
            sessionHighShown = false,
            sessionLowShown = false,
            consStartBar = nil,
            consEndBar = nil,
            consHigh = nil,
            consLow = nil
        }
    }
}

local U = {
    tradeDay = nil,
    frd = nil,
    fgd = nil,
    bias = nil
}

local T = {}
local O = {}

local PROFILE_PRESETS = {
    default = { consolidationminbars = 8, consolidationstalebars = 3, atrlen = 14, maxconsolidationatrmult = 1.0, maxdriftratio = 0.45 },
    tight = { consolidationminbars = 10, consolidationstalebars = 4, atrlen = 21, maxconsolidationatrmult = 0.8, maxdriftratio = 0.30 },
    loose = { consolidationminbars = 6, consolidationstalebars = 2, atrlen = 10, maxconsolidationatrmult = 1.2, maxdriftratio = 0.60 }
}

local function resolveProfileName(rawProfile)
    local value = string.lower(tostring(rawProfile or "default"))
    if PROFILE_PRESETS[value] ~= nil then return value end
    return "default"
end

local function safeTextSet(out, period, price, text)
    if out == nil or period == nil or price == nil or text == nil then return end
    out:set(period, price, text)
end

local function minuteOfDay(ts)
    if ts == nil then return nil end
    local f = ts - math.floor(ts)
    if f < 0 then f = f + 1 end
    local m = math.floor(f * 1440 + 0.000001)
    if m < 0 then m = 0 elseif m > 1439 then m = 1439 end
    return m
end

local function inBisWindow(ts)
    local m = minuteOfDay(ts)
    return m ~= nil and m >= 0 and m < (9 * 60 + 30)
end

local function clearEvents(ev)
    ev.consolidationCreated = nil
    ev.bisFired = nil
    ev.sessionHighUpdated = nil
    ev.sessionLowUpdated = nil
end

local function isReadableStream(v)
    if v == nil or type(v) ~= "userdata" then return false end
    return type(v.first) == "function" and type(v.name) == "function"
end

local function streamValue(stream, period)
    if not isReadableStream(stream) or period == nil then return nil end
    local first = stream:first()
    if first == nil or period < first then return nil end
    return stream[period]
end

local function computeATR(stream, period, len)
    if stream == nil or period == nil or len == nil or len <= 0 then return nil end
    local start = period - len + 1
    if start < stream:first() then return nil end

    local sumTr = 0
    local count = 0
    for i = start, period do
        local prevClose = (i > stream:first()) and stream.close[i - 1] or stream.close[i]
        if prevClose ~= nil then
            local tr = math.max(stream.high[i] - stream.low[i], math.abs(stream.high[i] - prevClose), math.abs(stream.low[i] - prevClose))
            sumTr = sumTr + tr
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return sumTr / count
end

local function findConsolidationCandidate(stream, period, minBars, atrLen, maxAtrMult, trendLimit)
    if stream == nil or period == nil then return nil end
    local start = period - minBars + 1
    if start < stream:first() then return nil end

    local high = stream.high[start]
    local low = stream.low[start]
    for i = start + 1, period do
        if stream.high[i] > high then high = stream.high[i] end
        if stream.low[i] < low then low = stream.low[i] end
    end

    local range = high - low
    local atr = computeATR(stream, period, atrLen)
    if atr == nil or range <= 0 then return nil end
    if range > atr * maxAtrMult then return nil end

    local drift = math.abs(stream.close[period] - stream.close[start])
    if drift > (range * trendLimit) then return nil end

    return {
        high = high,
        low = low,
        startBar = start,
        endBar = period
    }
end

local function detectConsolidation(period, canRender)
    local st = S.state
    local con = st.consolidation
    local ev = st.events
    local src = S.source
    local canFireBis = inBisWindow(src:date(period))

    if not canRender then
        con.active = false
        return
    end

    local params = PROFILE_PRESETS[resolveProfileName(instance.parameters.profile)] or PROFILE_PRESETS.default
    local minBars = math.max(3, params.consolidationminbars)
    local staleBars = math.max(1, params.consolidationstalebars)
    local atrLen = math.max(2, params.atrlen)
    local maxAtrMult = math.max(0.1, params.maxconsolidationatrmult)
    local trendLimit = math.max(0.05, math.min(1.0, params.maxdriftratio))

    local candidate = findConsolidationCandidate(src, period, minBars, atrLen, maxAtrMult, trendLimit)

    if con.active and not con.brokenDown then
        local brokeUp = src.close[period] > con.high
        local brokeDown = src.close[period] < con.low
        local stillInside = src.high[period] <= con.high and src.low[period] >= con.low

        if stillInside then
            con.lastInsideBar = period
            con.endBar = period
        elseif brokeUp then
            if canFireBis and ev.lastBisConsolidationId ~= con.id then
                con.active = false
                ev.bisFired = { id = con.id, bar = period, price = src.high[period], dir = "up" }
                ev.lastBisConsolidationId = con.id
            else
                con.active = false
            end
        elseif brokeDown then
            if canFireBis and ev.lastBisConsolidationId ~= con.id then
                con.brokenDown = true
                con.active = false
                ev.bisFired = { id = con.id, bar = period, price = src.low[period], dir = "down" }
                ev.lastBisConsolidationId = con.id
            else
                con.active = false
            end
        elseif candidate ~= nil then
            con.high = candidate.high
            con.low = candidate.low
            con.lastInsideBar = period
            con.endBar = period
        elseif period - con.lastInsideBar > staleBars then
            con.active = false
        end
    end

    if (not con.active) and candidate ~= nil then
        con.idSeed = con.idSeed + 1
        con.active = true
        con.id = con.idSeed
        con.high = candidate.high
        con.low = candidate.low
        con.startBar = candidate.startBar
        con.endBar = candidate.endBar
        con.lastInsideBar = period
        con.brokenDown = false
        con.brokenUp = false
        ev.consolidationCreated = {
            id = con.id,
            bar = period,
            high = con.high,
            low = con.low,
            startBar = con.startBar,
            endBar = con.endBar
        }
    end
end

local function updateSession(period, canRender)
    local st = S.state
    local sess = st.session
    local ev = st.events
    local src = S.source

    if not canRender then
        sess.active = false
        return
    end

    if ev.bisFired ~= nil then
        sess.active = true
        sess.sourceConsolidationId = ev.bisFired.id
        sess.startBar = period
        sess.high = src.high[period]
        sess.low = src.low[period]
        ev.sessionHighUpdated = { bar = period, price = sess.high }
        ev.sessionLowUpdated = { bar = period, price = sess.low }
        return
    end

    if not sess.active then return end

    if src.high[period] > sess.high then
        sess.high = src.high[period]
        ev.sessionHighUpdated = { bar = period, price = sess.high }
    end
    if src.low[period] < sess.low then
        sess.low = src.low[period]
        ev.sessionLowUpdated = { bar = period, price = sess.low }
    end
end

local function render(period, canRender)
    local src = S.source
    local st = S.state
    local sess = st.session
    local ev = st.events
    local disp = st.display

    T.consolidationHigh[period] = nil
    T.consolidationLow[period] = nil
    T.sessionHigh[period] = nil
    T.sessionLow[period] = nil

    if not canRender then return end

    local range = src.high[period] - src.low[period]
    local offset = range > 0 and range * 0.2 or src:pipSize() * 8

    if ev.consolidationCreated ~= nil then
        if disp.setupId ~= ev.consolidationCreated.id then
            disp.setupId = ev.consolidationCreated.id
            disp.consShown = false
            disp.bisShown = false
            disp.sessionHighShown = false
            disp.sessionLowShown = false
        end
        disp.consStartBar = ev.consolidationCreated.startBar
        disp.consEndBar = ev.consolidationCreated.endBar or ev.consolidationCreated.bar
        disp.consHigh = ev.consolidationCreated.high
        disp.consLow = ev.consolidationCreated.low
    end

    if disp.consStartBar ~= nil and disp.consEndBar ~= nil and disp.consHigh ~= nil and disp.consLow ~= nil and period >= disp.consStartBar and period <= disp.consEndBar then
        T.consolidationHigh[period] = disp.consHigh
        T.consolidationLow[period] = disp.consLow
    end

    if sess.active then
        T.sessionHigh[period] = sess.high
        T.sessionLow[period] = sess.low
    end

    if ev.consolidationCreated ~= nil and not disp.consShown then
        safeTextSet(O.txtConsolidation, ev.consolidationCreated.bar, ev.consolidationCreated.low - offset, "CONS ✓")
        disp.consShown = true
    end

    if ev.bisFired ~= nil and not disp.bisShown and inBisWindow(src:date(ev.bisFired.bar)) then
        safeTextSet(O.txtBis, ev.bisFired.bar, ev.bisFired.price - offset, "BIS " .. ev.bisFired.dir .. " ✓")
        disp.bisShown = true
    end

    if ev.sessionHighUpdated ~= nil and not disp.sessionHighShown then
        safeTextSet(O.txtTarget, ev.sessionHighUpdated.bar, ev.sessionHighUpdated.price + offset, "HOS/HOD ✓")
        disp.sessionHighShown = true
    end

    if ev.sessionLowUpdated ~= nil and not disp.sessionLowShown then
        safeTextSet(O.txtTarget, ev.sessionLowUpdated.bar, ev.sessionLowUpdated.price - offset, "LOS/LOD ✓")
        disp.sessionLowShown = true
    end
end

function Init()
    indicator:name("SB Structure Engine (Simple)")
    indicator:description("Simple Structure output: Consolidation -> BIS -> Session High/Low")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addString("profile", "Profile", "", "Default")
    indicator.parameters:addStringAlternative("Default", "Default", "")
    indicator.parameters:addStringAlternative("Tight", "Tight", "")
    indicator.parameters:addStringAlternative("Loose", "Loose", "")

    indicator.parameters:addBoolean("requiretradeday", "Require Trade Day Gate", "", true)
    indicator.parameters:addBoolean("fallbackistradeday", "Fallback Is Trade Day", "", true)
    if indicator.parameters.addSource ~= nil then
        indicator.parameters:addSource("daytype_trade_day_stream", "DayType is_trade_day stream", "")
        indicator.parameters:addSource("daytype_frd_event_stream", "DayType is_frd_event_day stream", "")
        indicator.parameters:addSource("daytype_fgd_event_stream", "DayType is_fgd_event_day stream", "")
        indicator.parameters:addSource("daytype_bias_stream", "DayType day_bias stream", "")
    end
end

function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()

    instance:name(profile:id() .. "(" .. S.source:name() .. ")")
    if nameOnly then return end

    U.tradeDay = instance.parameters.daytype_trade_day_stream
    U.frd = instance.parameters.daytype_frd_event_stream
    U.fgd = instance.parameters.daytype_fgd_event_stream
    U.bias = instance.parameters.daytype_bias_stream

    T.consolidationHigh = instance:addStream("consolidation_high", core.Line, "Consolidation High", "", core.rgb(205, 205, 205), S.first)
    T.consolidationLow = instance:addStream("consolidation_low", core.Line, "Consolidation Low", "", core.rgb(205, 205, 205), S.first)
    T.sessionHigh = instance:addStream("session_high", core.Line, "Session High", "", core.rgb(255, 215, 0), S.first)
    T.sessionLow = instance:addStream("session_low", core.Line, "Session Low", "", core.rgb(135, 206, 250), S.first)

    O.txtConsolidation = instance:createTextOutput("", "SB_CONSOLIDATION", "Arial", 8, core.H_Center, core.V_Top, core.rgb(210, 210, 210), 0)
    O.txtBis = instance:createTextOutput("", "SB_BIS", "Arial", 9, core.H_Center, core.V_Top, core.rgb(220, 20, 60), 0)
    O.txtTarget = instance:createTextOutput("", "SB_TARGET", "Arial", 8, core.H_Center, core.V_Top, core.rgb(255, 215, 0), 0)
end

function Update(period, mode)
    if S.source == nil or period < S.first then return end

    local st = S.state
    clearEvents(st.events)

    local streamTrade = streamValue(U.tradeDay, period)
    local streamFrd = streamValue(U.frd, period)
    local streamFgd = streamValue(U.fgd, period)
    local streamBias = streamValue(U.bias, period)

    if streamTrade ~= nil then
        st.day.isTradeDay = streamTrade > 0
    else
        st.day.isTradeDay = instance.parameters.fallbackistradeday
    end

    if streamFrd ~= nil then st.day.isFrd = streamFrd > 0 else st.day.isFrd = false end
    if streamFgd ~= nil then st.day.isFgd = streamFgd > 0 else st.day.isFgd = false end

    if streamBias ~= nil then
        st.day.bias = streamBias
    elseif st.day.isFrd then
        st.day.bias = -1
    elseif st.day.isFgd then
        st.day.bias = 1
    else
        st.day.bias = 0
    end

    local canRenderStructure = (not instance.parameters.requiretradeday) or st.day.isTradeDay

    detectConsolidation(period, canRenderStructure)
    updateSession(period, canRenderStructure)
    render(period, canRenderStructure)
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

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
            consLow = nil,
            session = nil,
            sessionStartBar = nil,
            sessionEndBar = nil,
            sessionMid = nil
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

local function createSessionDisplay(params)
    local color = params.sessioncolor or core.rgb(255, 215, 0)
    return {
        high = nil,
        low = nil,
        bands = {
            upper = nil,
            lower = nil,
            mid = nil
        },
        labels = {
            high = nil,
            low = nil
        },
        color = color,
        style = params.sessionlinestyle,
        fillAlpha = params.sessionfillalpha,
        showSessionHigh = params.showsessionhigh,
        showSessionLow = params.showsessionlow,
        showSessionLabels = params.showsessionlabels,
        showSessionMid = params.showsessionmid
    }
end

local function createChannelGroup(name, color, alpha)
    if instance == nil or type(instance.createChannelGroup) ~= "function" then return nil end
    local ok, group = pcall(function()
        return instance:createChannelGroup(name, color, alpha)
    end)
    if not ok then return nil end
    return group
end

local function addInternalBandStream(id, title, first, color)
    if type(instance.addInternalStream) == "function" then
        local ok, stream = pcall(function()
            return instance:addInternalStream(id, core.Line, title, "", color, first)
        end)
        if ok and stream ~= nil then return stream end
    end
    return instance:addStream(id, core.Line, title, "", color, first)
end

local function bindChannelGroup(group, upper, lower)
    if group == nil or upper == nil or lower == nil then return false end

    local attempts = {
        function() group:addStream(upper, lower) end,
        function() group:addStream(upper) group:addStream(lower) end,
        function() group:setStreams(upper, lower) end,
        function() group:setStream(upper, lower) end,
        function() group:setStream(1, upper) group:setStream(2, lower) end,
        function() group.upper = upper group.lower = lower end
    }

    for _, attempt in ipairs(attempts) do
        local ok = pcall(attempt)
        if ok then return true end
    end
    return false
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
    if not instance.parameters.bisusetimewindow then return true end
    local m = minuteOfDay(ts)
    if m == nil then return false end
    local startMin = math.max(0, math.min(1439, instance.parameters.biswindowstartmin or 0))
    local endMin = math.max(0, math.min(1439, instance.parameters.biswindowendmin or (9 * 60 + 30)))
    if startMin == endMin then return true end
    if startMin < endMin then
        return m >= startMin and m < endMin
    end
    return m >= startMin or m < endMin
end

local function resolveHorizontalAlign(align)
    local value = string.lower(tostring(align or "Center"))
    if value == "left" then return core.H_Left end
    if value == "right" then return core.H_Right end
    return core.H_Center
end

local function renderBisLabel(ev, period, offset)
    if ev == nil or (not instance.parameters.showbislabel) then return false end

    local isUp = ev.dir == "up"
    local label = isUp and "BIS UP ✓" or "BIS DOWN ✓"
    local price = isUp and (ev.price + offset) or (ev.price - offset)
    local output = isUp and O.txtBisUp or O.txtBisDown
    safeTextSet(output, period, price, label)
    return true
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
            local repeatedInConsolidation = (not instance.parameters.bisallowrepeatinconsolidation) and ev.lastBisConsolidationId == con.id
            if canFireBis and not repeatedInConsolidation then
                con.active = false
                ev.bisFired = { id = con.id, bar = period, price = src.high[period], dir = "up" }
                ev.lastBisConsolidationId = con.id
            else
                con.active = false
                if not canFireBis then
                    st.bisBlockReason = "BIS_TIME_WINDOW"
                elseif repeatedInConsolidation then
                    st.bisBlockReason = "BIS_ONCE_PER_CONSOLIDATION"
                end
            end
        elseif brokeDown then
            local repeatedInConsolidation = (not instance.parameters.bisallowrepeatinconsolidation) and ev.lastBisConsolidationId == con.id
            if canFireBis and not repeatedInConsolidation then
                con.brokenDown = true
                con.active = false
                ev.bisFired = { id = con.id, bar = period, price = src.low[period], dir = "down" }
                ev.lastBisConsolidationId = con.id
            else
                con.active = false
                if not canFireBis then
                    st.bisBlockReason = "BIS_TIME_WINDOW"
                elseif repeatedInConsolidation then
                    st.bisBlockReason = "BIS_ONCE_PER_CONSOLIDATION"
                end
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
        sess.startBar = nil
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
    local con = st.consolidation
    local sess = st.session
    local ev = st.events
    local disp = st.display

    T.consolidationHigh[period] = nil
    T.consolidationLow[period] = nil
    T.consolidationHighBand[period] = nil
    T.consolidationLowBand[period] = nil
    T.sessionHigh[period] = nil
    T.sessionLow[period] = nil
    T.sessionMid[period] = nil

    local range = src.high[period] - src.low[period]
    local offset = range > 0 and range * 0.2 or src:pipSize() * 8

    if not canRender then
        if instance.parameters.debug then
            safeTextSet(O.txtDebug, period, src.low[period] - offset * 2, "GATE: WAIT_TRADE_DAY")
        end
        return
    end

    if disp.session == nil then
        disp.session = createSessionDisplay(instance.parameters)
    end

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

    if con.active and con.id ~= nil then
        if disp.setupId ~= con.id then
            disp.setupId = con.id
            disp.consShown = false
            disp.bisShown = false
            disp.sessionHighShown = false
            disp.sessionLowShown = false
        end
        disp.consStartBar = con.startBar
        disp.consEndBar = con.endBar or period
        disp.consHigh = con.high
        disp.consLow = con.low
    end

    if con.active and disp.consHigh ~= nil and disp.consLow ~= nil then
        T.consolidationHigh[period] = disp.consHigh
        T.consolidationLow[period] = disp.consLow
        T.consolidationHighBand[period] = disp.consHigh
        T.consolidationLowBand[period] = disp.consLow
    else
        T.consolidationHigh[period] = nil
        T.consolidationLow[period] = nil
        T.consolidationHighBand[period] = nil
        T.consolidationLowBand[period] = nil
    end

    if sess.active and sess.startBar ~= nil then
        disp.sessionStartBar = sess.startBar
        disp.sessionEndBar = period
        disp.session.high = sess.high
        disp.session.low = sess.low
        disp.session.bands.mid = (sess.high + sess.low) / 2

        local startBar = disp.sessionStartBar
        local endBar = disp.sessionEndBar
        for i = startBar, endBar do
            if disp.session.showSessionHigh then
                T.sessionHigh[i] = disp.session.high
            end
            if disp.session.showSessionLow then
                T.sessionLow[i] = disp.session.low
            end
            if disp.session.showSessionMid then
                T.sessionMid[i] = disp.session.bands.mid
            end
        end
    end

    if ev.consolidationCreated ~= nil and not disp.consShown then
        safeTextSet(O.txtConsolidation, ev.consolidationCreated.bar, ev.consolidationCreated.low - offset, "CONS ✓")
        disp.consShown = true
    end

    if ev.bisFired ~= nil and not disp.bisShown then
        renderBisLabel(ev.bisFired, ev.bisFired.bar, offset)
        disp.bisShown = true
    end

    if ev.sessionHighUpdated ~= nil and not disp.sessionHighShown and disp.session.showSessionLabels then
        safeTextSet(O.txtTarget, ev.sessionHighUpdated.bar, ev.sessionHighUpdated.price + offset, "HOS/HOD ✓")
        disp.sessionHighShown = true
    end

    if ev.sessionLowUpdated ~= nil and not disp.sessionLowShown and disp.session.showSessionLabels then
        safeTextSet(O.txtTarget, ev.sessionLowUpdated.bar, ev.sessionLowUpdated.price - offset, "LOS/LOD ✓")
        disp.sessionLowShown = true
    end

    if instance.parameters.debug then
        local reason = st.gate and st.gate.bisBlockReason or st.bisBlockReason or "PASS"
        local consState = con.active and "CONS: ACTIVE" or "CONS: IDLE"
        local consRange = ""
        if con.high ~= nil and con.low ~= nil then
            consRange = string.format(" [%.5f - %.5f]", con.low, con.high)
        end
        safeTextSet(O.txtDebug, period, src.low[period] - offset * 2, "GATE: " .. reason .. " | " .. consState .. consRange)
    end
end

function Init()
    local ind = indicator or instance
    if ind == nil then return end

    ind:name("SB Structure Engine (Simple)")
    ind:description("Simple Structure output: Consolidation -> BIS -> Session High/Low")
    ind:requiredSource(core.Bar)
    ind:type(core.Indicator)

    local p = ind.parameters
    p:addString("profile", "Profile", "", "Default")
    p:addStringAlternative("profile", "Default", "Default", "")
    p:addStringAlternative("profile", "Tight", "Tight", "")
    p:addStringAlternative("profile", "Loose", "Loose", "")

    p:addBoolean("requiretradeday", "Require Trade Day Gate", "", true)
    p:addBoolean("fallbackistradeday", "Fallback Is Trade Day", "", true)
    p:addBoolean("showsessionhigh", "Show Session High", "", true)
    p:addBoolean("showsessionlow", "Show Session Low", "", true)
    p:addBoolean("showsessionlabels", "Show Session Labels", "", true)
    p:addString("sessionlinestyle", "Session Line Style", "", "Solid")
    p:addStringAlternative("sessionlinestyle", "Solid", "Solid", "")
    p:addStringAlternative("sessionlinestyle", "Dash", "Dash", "")
    p:addStringAlternative("sessionlinestyle", "Dot", "Dot", "")
    p:addColor("sessioncolor", "Session Color", "", core.rgb(255, 215, 0))
    p:addInteger("sessionfillalpha", "Session Fill Alpha", "", 30)
    p:addColor("conscolor", "Consolidation Channel Color", "", core.rgb(138, 43, 226))
    p:addInteger("consfillalpha", "Consolidation Fill Alpha", "", 45)
    p:addBoolean("showsessionmid", "Show Session Mid", "", false)
    p:addBoolean("showbislabel", "Show BIS Label", "", true)
    p:addInteger("bislabelfontsize", "BIS Label Font Size", "", 9)
    p:addColor("bislabelcolor", "BIS Label Color", "", core.rgb(34, 139, 34))
    p:addString("bislabelalign", "BIS Label Align", "", "Center")
    p:addStringAlternative("bislabelalign", "Left", "Left", "")
    p:addStringAlternative("bislabelalign", "Center", "Center", "")
    p:addStringAlternative("bislabelalign", "Right", "Right", "")
    p:addBoolean("bisusetimewindow", "Use BIS Time Window", "", true)
    p:addInteger("biswindowstartmin", "BIS Window Start Minute", "", 0)
    p:addInteger("biswindowendmin", "BIS Window End Minute", "", 570)
    p:addBoolean("bisallowrepeatinconsolidation", "Allow Repeat BIS in Consolidation", "", false)
    p:addBoolean("debug", "Debug", "", false)
    if p.addSource ~= nil then
        p:addSource("daytype_trade_day_stream", "DayType is_trade_day stream", "")
        p:addSource("daytype_frd_event_stream", "DayType is_frd_event_day stream", "")
        p:addSource("daytype_fgd_event_stream", "DayType is_fgd_event_day stream", "")
        p:addSource("daytype_bias_stream", "DayType day_bias stream", "")
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

    T.consolidationHigh = instance:addStream("consolidation_high", core.Line, "Consolidation High", "", instance.parameters.conscolor, S.first)
    T.consolidationLow = instance:addStream("consolidation_low", core.Line, "Consolidation Low", "", instance.parameters.conscolor, S.first)
    T.consolidationHighBand = addInternalBandStream("consolidation_high_band", "Consolidation High Band", S.first, instance.parameters.conscolor)
    T.consolidationLowBand = addInternalBandStream("consolidation_low_band", "Consolidation Low Band", S.first, instance.parameters.conscolor)
    T.sessionHigh = instance:addStream("session_high", core.Line, "Session High", "", core.rgb(255, 215, 0), S.first)
    T.sessionLow = instance:addStream("session_low", core.Line, "Session Low", "", core.rgb(135, 206, 250), S.first)
    T.sessionMid = instance:addStream("session_mid", core.Line, "Session Mid", "", core.rgb(255, 255, 255), S.first)

    O.txtConsolidation = instance:createTextOutput("", "SB_CONSOLIDATION", "Arial", 8, core.H_Center, core.V_Top, core.rgb(210, 210, 210), 0)
    local bisAlign = resolveHorizontalAlign(instance.parameters.bislabelalign)
    local bisFontSize = math.max(6, instance.parameters.bislabelfontsize or 9)
    local bisColor = instance.parameters.bislabelcolor or core.rgb(34, 139, 34)
    O.txtBisUp = instance:createTextOutput("", "SB_BIS_UP", "Arial", bisFontSize, bisAlign, core.V_Bottom, bisColor, 0)
    O.txtBisDown = instance:createTextOutput("", "SB_BIS_DOWN", "Arial", bisFontSize, bisAlign, core.V_Top, core.rgb(220, 20, 60), 0)
    O.txtTarget = instance:createTextOutput("", "SB_TARGET", "Arial", 8, core.H_Center, core.V_Top, core.rgb(255, 215, 0), 0)
    O.txtDebug = instance:createTextOutput("", "SB_STRUCTURE_DEBUG", "Arial", 7, core.H_Left, core.V_Top, core.rgb(180, 180, 180), 0)

    S.state.display.session = createSessionDisplay(instance.parameters)
    O.consolidationChannel = createChannelGroup("SB_CONSOLIDATION_CHANNEL", instance.parameters.conscolor, instance.parameters.consfillalpha)
    bindChannelGroup(O.consolidationChannel, T.consolidationHighBand, T.consolidationLowBand)
    O.sessionChannel = createChannelGroup("SB_SESSION_CHANNEL", S.state.display.session.color, S.state.display.session.fillAlpha)
    bindChannelGroup(O.sessionChannel, T.sessionHigh, T.sessionLow)
end

function Update(period, mode)
    if S.source == nil or period < S.first then return end

    local st = S.state
    clearEvents(st.events)
    st.bisBlockReason = nil

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

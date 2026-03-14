local S = {
    source = nil,
    first = nil,
    upstream = {
        tradeDay = nil,
        frdEvent = nil,
        fgdEvent = nil,
        dayBias = nil,
        supportsSourceParams = false,
        warnedMissing = false
    },
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
            targetShown = false,
            consStartBar = nil,
            consEndBar = nil,
            consHigh = nil,
            consLow = nil
        },
        gate = {
            hasUpstream = false,
            upstreamTradeDay = nil
        }
    }
}

local T = {}
local O = {}

local function debugLog(msg)
    if not instance.parameters.debug then return end
    local ok = pcall(function()
        core.host:trace("[SB_Structure_Engine] " .. msg)
    end)
    if not ok then
        pcall(function() print("[SB_Structure_Engine] " .. msg) end)
    end
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

local function upstreamNumericValue(candidate, period)
    local candidateType = type(candidate)

    if candidateType == "number" then
        return candidate, true, false
    end
    if candidateType == "boolean" then
        return candidate and 1 or 0, true, false
    end

    if candidateType == "table" or candidateType == "userdata" then
        local ok, value = pcall(function() return candidate[period] end)
        if ok then
            local n = tonumber(value)
            return n or 0, true, true
        end
    end

    return nil, false, false
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
        endBar = period,
        bars = minBars,
        atr = atr,
        range = range
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

    local minBars = math.max(3, instance.parameters.consolidationminbars)
    local atrLen = math.max(2, instance.parameters.atrlen)
    local maxAtrMult = math.max(0.1, instance.parameters.maxconsolidationatrmult)
    local trendLimit = math.max(0.05, math.min(1.0, instance.parameters.maxdriftratio))

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
                ev.bisFired = { id = con.id, bar = period, price = src.high[period], sourceHigh = con.high, dir = "up" }
                ev.lastBisConsolidationId = con.id
            else
                con.active = false
            end
        elseif brokeDown then
            if canFireBis and ev.lastBisConsolidationId ~= con.id then
                con.brokenDown = true
                con.active = false
                ev.bisFired = { id = con.id, bar = period, price = src.low[period], sourceLow = con.low, dir = "down" }
                ev.lastBisConsolidationId = con.id
            else
                con.active = false
            end
        elseif candidate ~= nil then
            con.high = candidate.high
            con.low = candidate.low
            con.lastInsideBar = period
            con.endBar = period
        elseif period - con.lastInsideBar > math.max(1, instance.parameters.consolidationstalebars) then
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
    local con = st.consolidation
    local sess = st.session
    local ev = st.events
    local disp = st.display
    local isConfirmedTradeDay = st.day.isFrd or st.day.isFgd

    T.consolidationHigh[period] = nil
    T.consolidationLow[period] = nil
    T.sessionHigh[period] = nil
    T.sessionLow[period] = nil
    T.canRenderStructure[period] = canRender and 1 or 0
    T.gateRequireTradeDay[period] = instance.parameters.requiretradeday and 1 or 0
    T.gateUpstreamTradeDay[period] = st.gate.upstreamTradeDay
    T.gateFinalCanRender[period] = canRender and 1 or 0

    local range = src.high[period] - src.low[period]
    local offset = range > 0 and range * 0.2 or src:pipSize() * 8

    if not canRender then
        safeTextSet(O.txtGateWait, period, src.high[period] + offset, "WAIT_UPSTREAM_TRADE_DAY")
        return
    end

    if not isConfirmedTradeDay then
        return
    end

    if ev.consolidationCreated ~= nil then
        if disp.setupId ~= ev.consolidationCreated.id then
            disp.setupId = ev.consolidationCreated.id
            disp.consShown = false
            disp.bisShown = false
            disp.targetShown = false
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
        if st.day.isFrd and ev.bisFired.dir == "down" then
            safeTextSet(O.txtBis, ev.bisFired.bar, ev.bisFired.price - offset, "BIS down ✓")
            disp.bisShown = true
        elseif st.day.isFgd and ev.bisFired.dir == "up" then
            safeTextSet(O.txtBis, ev.bisFired.bar, ev.bisFired.price - offset, "BIS up ✓")
            disp.bisShown = true
        end
    end

    if st.day.isFrd and ev.sessionHighUpdated ~= nil and not disp.targetShown then
        safeTextSet(O.txtSessionHigh, ev.sessionHighUpdated.bar, ev.sessionHighUpdated.price + offset, "HOS/HOD ✓")
        disp.targetShown = true
    end

    if st.day.isFgd and ev.sessionLowUpdated ~= nil and not disp.targetShown then
        safeTextSet(O.txtSessionLow, ev.sessionLowUpdated.bar, ev.sessionLowUpdated.price - offset, "LOS/LOD ✓")
        disp.targetShown = true
    end

    if false and instance.parameters.debug then
        local debugText = "DBG con=" .. (con.active and "1" or "0") ..
            " id=" .. (con.id or 0) ..
            " low=" .. string.format("%.5f", con.low or 0) ..
            " bisSrc=" .. (st.events.lastBisConsolidationId or 0)
        safeTextSet(O.txtDebug, period, src.low[period] - offset * 2, debugText)
    end
end

function Init()
    indicator:name("SB Structure Engine")
    indicator:description("SB Structure Engine (Consolidation -> BIS -> Session High/Low)")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addInteger("consolidationminbars", "Consolidation Min Bars", "", 8)
    indicator.parameters:addInteger("consolidationstalebars", "Consolidation Stale Bars", "", 3)
    indicator.parameters:addInteger("atrlen", "ATR Length", "", 14)
    indicator.parameters:addDouble("maxconsolidationatrmult", "Max Consolidation Range ATR Mult", "", 1.0)
    indicator.parameters:addDouble("maxdriftratio", "Max Consolidation Drift Ratio", "", 0.45)

    indicator.parameters:addBoolean("requiretradeday", "Require Trade Day Gate", "", true)
    indicator.parameters:addBoolean("allow_render_when_upstream_missing", "Allow Render When Upstream Missing", "", false)
    indicator.parameters:addBoolean("manualoverride", "Manual Override DayType (Debug)", "", false)
    local supportsAddSource = type(indicator.parameters.addSource) == "function"
    if supportsAddSource then
        indicator.parameters:addSource("daytype_trade_day_stream", "DayType Stream: is_trade_day", "", "close")
        indicator.parameters:addSource("daytype_frd_event_stream", "DayType Stream: is_frd_event_day", "", "close")
        indicator.parameters:addSource("daytype_fgd_event_stream", "DayType Stream: is_fgd_event_day", "", "close")
        indicator.parameters:addSource("daytype_bias_stream", "DayType Stream: day_bias", "", "close")
    else
        indicator.parameters:addBoolean("daytype_trade_day_stream", "DayType Fallback: is_trade_day", "", false)
        indicator.parameters:addBoolean("daytype_frd_event_stream", "DayType Fallback: is_frd_event_day", "", false)
        indicator.parameters:addBoolean("daytype_fgd_event_stream", "DayType Fallback: is_fgd_event_day", "", false)
        indicator.parameters:addInteger("daytype_bias_stream", "DayType Fallback: day_bias", "", 0)
    end

    indicator.parameters:addBoolean("upstreamistradeday", "Upstream Is Trade Day", "", false)
    indicator.parameters:addBoolean("upstreamisfrd", "Upstream Is FRD", "", false)
    indicator.parameters:addBoolean("upstreamisfgd", "Upstream Is FGD", "", false)
    indicator.parameters:addInteger("upstreambias", "Upstream Bias", "", 0)

    indicator.parameters:addBoolean("debug", "Debug", "", false)
end

function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()

    instance:name(profile:id() .. "(" .. S.source:name() .. ")")
    if nameOnly then return end

    S.upstream.tradeDay = instance.parameters.daytype_trade_day_stream
    S.upstream.frdEvent = instance.parameters.daytype_frd_event_stream
    S.upstream.fgdEvent = instance.parameters.daytype_fgd_event_stream
    S.upstream.dayBias = instance.parameters.daytype_bias_stream
    S.upstream.supportsSourceParams = type(indicator.parameters.addSource) == "function"

    local missing = {}
    if not select(2, upstreamNumericValue(S.upstream.tradeDay, S.first)) then table.insert(missing, "is_trade_day") end
    if not select(2, upstreamNumericValue(S.upstream.frdEvent, S.first)) then table.insert(missing, "is_frd_event_day") end
    if not select(2, upstreamNumericValue(S.upstream.fgdEvent, S.first)) then table.insert(missing, "is_fgd_event_day") end
    if not select(2, upstreamNumericValue(S.upstream.dayBias, S.first)) then table.insert(missing, "day_bias") end
    if #missing > 0 then
        debugLog("DayType upstream sources not ready: " .. table.concat(missing, ", ") .. ". Enable manual override for fallback debugging.")
        S.upstream.warnedMissing = true
    elseif S.upstream.supportsSourceParams then
        debugLog("DayType upstream streams connected: is_trade_day/is_frd_event_day/is_fgd_event_day/day_bias")
    else
        debugLog("DayType upstream fallback parameters active: daytype_* values are consumed as manual numeric flags.")
    end

    T.consolidationHigh = instance:addStream("consolidation_high", core.Line, "Consolidation High", "", core.rgb(205, 205, 205), S.first)
    T.consolidationLow = instance:addStream("consolidation_low", core.Line, "Consolidation Low", "", core.rgb(205, 205, 205), S.first)
    T.sessionHigh = instance:addStream("session_high", core.Line, "Session High", "", core.rgb(255, 215, 0), S.first)
    T.sessionLow = instance:addStream("session_low", core.Line, "Session Low", "", core.rgb(135, 206, 250), S.first)
    T.canRenderStructure = instance:addStream("can_render_structure", core.Line, "Can Render Structure", "", core.rgb(169, 169, 169), S.first)
    T.gateRequireTradeDay = instance:addStream("gate_require_trade_day", core.Line, "Gate Require Trade Day", "", core.rgb(112, 128, 144), S.first)
    T.gateUpstreamTradeDay = instance:addStream("gate_upstream_trade_day", core.Line, "Gate Upstream Trade Day", "", core.rgb(143, 188, 143), S.first)
    T.gateFinalCanRender = instance:addStream("gate_final_can_render", core.Line, "Gate Final Can Render", "", core.rgb(255, 140, 0), S.first)

    O.txtConsolidation = instance:createTextOutput("", "SB_CONSOLIDATION", "Arial", 8, core.H_Center, core.V_Top, core.rgb(210, 210, 210), 0)
    O.txtBis = instance:createTextOutput("", "SB_BIS", "Arial", 9, core.H_Center, core.V_Top, core.rgb(220, 20, 60), 0)
    O.txtSessionHigh = instance:createTextOutput("", "SB_SESSION_HIGH", "Arial", 8, core.H_Center, core.V_Bottom, core.rgb(255, 215, 0), 0)
    O.txtSessionLow = instance:createTextOutput("", "SB_SESSION_LOW", "Arial", 8, core.H_Center, core.V_Top, core.rgb(135, 206, 250), 0)
    O.txtGateWait = instance:createTextOutput("", "SB_GATE_WAIT", "Arial", 8, core.H_Right, core.V_Top, core.rgb(255, 165, 0), 0)
    O.txtDebug = instance:createTextOutput("", "SB_STRUCTURE_DEBUG", "Arial", 7, core.H_Left, core.V_Top, core.rgb(180, 180, 180), 0)
end

function Update(period, mode)
    if S.source == nil or period < S.first then return end

    local st = S.state
    clearEvents(st.events)

    local gate = st.gate

    if instance.parameters.manualoverride then
        st.day.isTradeDay = instance.parameters.upstreamistradeday
        st.day.isFrd = instance.parameters.upstreamisfrd
        st.day.isFgd = instance.parameters.upstreamisfgd
        st.day.bias = instance.parameters.upstreambias
        gate.hasUpstream = true
        gate.upstreamTradeDay = st.day.isTradeDay and 1 or 0
    else
        local up = S.upstream
        local tradeDayValue, hasTradeDay = upstreamNumericValue(up.tradeDay, period)
        local frdValue, hasFrd = upstreamNumericValue(up.frdEvent, period)
        local fgdValue, hasFgd = upstreamNumericValue(up.fgdEvent, period)
        local biasValue, hasBias = upstreamNumericValue(up.dayBias, period)
        local hasUpstream = hasTradeDay and hasFrd and hasFgd and hasBias
        gate.hasUpstream = hasUpstream

        if hasUpstream then
            st.day.isTradeDay = tradeDayValue > 0
            st.day.isFrd = frdValue > 0
            st.day.isFgd = fgdValue > 0
            st.day.bias = math.floor(biasValue + 0.000001)
            gate.upstreamTradeDay = tradeDayValue
        else
            st.day.isTradeDay = false
            st.day.isFrd = false
            st.day.isFgd = false
            st.day.bias = 0
            gate.upstreamTradeDay = nil
            if not up.warnedMissing then
                debugLog("Missing DayType upstream values in Update(). Structure stays gated off until upstream streams/values are connected or manual override is enabled.")
                up.warnedMissing = true
            end
        end
    end

    local canRenderStructure =
        (not instance.parameters.requiretradeday) or
        st.day.isTradeDay or
        (instance.parameters.allow_render_when_upstream_missing and (not instance.parameters.manualoverride) and (not gate.hasUpstream))

    detectConsolidation(period, canRenderStructure)
    updateSession(period, canRenderStructure)
    render(period, canRenderStructure)
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

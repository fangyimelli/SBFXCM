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
        prev2230Box = {
            dayKey = nil,
            high = nil,
            low = nil,
            startTs = nil,
            endTs = nil,
            startBar = nil,
            endBar = nil,
            isReady = false
        },
        londonBox = {
            dayKey = nil,
            high = nil,
            low = nil,
            startTs = nil,
            endTs = nil,
            startBar = nil,
            endBar = nil,
            isReady = false
        },
        bis1 = {
            firedUp = false,
            firedDown = false,
            firedAny = false,
            fireBar = nil,
            firePrice = nil
        },
        bis2 = {
            firedUp = false,
            firedDown = false,
            firedAny = false,
            fireBar = nil,
            firePrice = nil
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
            bis1Fired = nil,
            bis2Fired = nil,
            sessionHighUpdated = nil,
            sessionLowUpdated = nil,
            lastBisConsolidationId = nil
        },
        display = {
            setupId = nil,
            consShown = false,
            bis1Shown = false,
            bis2Shown = false,
            sessionHighShown = false,
            sessionLowShown = false,
            consStartBar = nil,
            consEndBar = nil,
            consHigh = nil,
            consLow = nil,
            session = nil,
            sessionStartBar = nil,
            sessionEndBar = nil,
            sessionMid = nil,
            prev2230LabelDayKey = nil,
            londonLabelDayKey = nil
        },
        debug = {
            hasCandidate = false,
            candidateRange = nil,
            lastTextPeriod = nil,
            minBars = nil,
            staleBars = nil,
            atrLen = nil,
            maxAtrMult = nil,
            trendLimit = nil,
            atr = nil,
            range = nil,
            rangeLimit = nil,
            drift = nil,
            driftLimit = nil
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
    default = { consolidationminbars = 6, consolidationstalebars = 4, atrlen = 14, maxconsolidationatrmult = 1.35, maxdriftratio = 0.65 },
    tight = { consolidationminbars = 8, consolidationstalebars = 5, atrlen = 21, maxconsolidationatrmult = 1.0, maxdriftratio = 0.45 },
    loose = { consolidationminbars = 5, consolidationstalebars = 3, atrlen = 10, maxconsolidationatrmult = 1.5, maxdriftratio = 0.75 }
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

local function createChannelGroup(name, color, alpha, upper, lower)
    if instance == nil or type(instance.createChannelGroup) ~= "function" then return nil end

    local attempts = {
        function()
            return instance:createChannelGroup(name, name, upper, lower, color, alpha)
        end,
        function()
            return instance:createChannelGroup(name, color, alpha)
        end
    }

    for _, attempt in ipairs(attempts) do
        local ok, group = pcall(attempt)
        if ok and group ~= nil then return group end
    end

    return nil
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

local function isLastVisiblePeriod(period)
    if S.source ~= nil and type(S.source.size) == "function" then
        local last = S.source:size() - 1
        return period >= last
    end
    return true
end

local function shouldRenderDebug(period, mode)
    if not isLastVisiblePeriod(period) then return false end
    if core ~= nil then
        if core.UpdateLast ~= nil and mode == core.UpdateLast then return true end
        if core.UpdateCurrent ~= nil and mode == core.UpdateCurrent then return true end
        if core.UpdateNew ~= nil and mode == core.UpdateNew then return true end
    end
    return false
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

local function normalizeMinute(value)
    local n = math.floor(tonumber(value) or 0)
    if n < 0 then return 0 end
    if n > 1440 then return 1440 end
    return n
end

local function getDayKey(ts, shiftHours)
    if ts == nil then return nil end
    local shift = tonumber(shiftHours) or 0
    return math.floor(ts + shift / 24)
end

local function isInWindow(ts, startMin, endMin)
    local m = minuteOfDay(ts)
    if m == nil then return false end

    local startM = normalizeMinute(startMin)
    local endM = normalizeMinute(endMin)
    if startM == 1440 then startM = 0 end
    if endM == 1440 then endM = 0 end

    if startM == endM then return true end
    if startM < endM then
        return m >= startM and m < endM
    end
    return m >= startM or m < endM
end

local function resetBisEvent(bis)
    bis.firedUp = false
    bis.firedDown = false
    bis.firedAny = false
    bis.fireBar = nil
    bis.firePrice = nil
end

local function accumulateBox(box, period)
    if box == nil or period == nil then return end
    if period.dayKey == nil then return end

    if box.dayKey ~= period.dayKey then
        box.dayKey = period.dayKey
        box.high = nil
        box.low = nil
        box.startTs = nil
        box.endTs = nil
        box.startBar = nil
        box.endBar = nil
        box.isReady = false
    end

    if period.inWindow then
        if box.startTs == nil then
            box.startTs = period.ts
            box.startBar = period.bar
        end
        box.endTs = period.ts
        box.endBar = period.bar
        if box.high == nil or period.high > box.high then box.high = period.high end
        if box.low == nil or period.low < box.low then box.low = period.low end
    elseif period.windowEnded and box.startTs ~= nil and box.high ~= nil and box.low ~= nil then
        box.isReady = true
    end
end

local function tryFireBisFromBox(period, ts, src, box, bis, ev, bisName, evField)
    if not box.isReady then return end
    if not inBisWindow(ts) then return end
    if ev[evField] ~= nil then return end

    local oncePerBox = instance.parameters.bisonceperbox
    if src.high[period] > box.high and (not bis.firedUp) and (not oncePerBox or not bis.firedAny) then
        bis.firedUp = true
        bis.firedAny = true
        bis.fireBar = period
        bis.firePrice = src.high[period]
        ev[evField] = { bar = period, price = bis.firePrice, dir = "up", bis = bisName, sourceHigh = box.high, dayKey = box.dayKey }
    elseif src.low[period] < box.low and (not bis.firedDown) and (not oncePerBox or not bis.firedAny) then
        bis.firedDown = true
        bis.firedAny = true
        bis.fireBar = period
        bis.firePrice = src.low[period]
        ev[evField] = { bar = period, price = bis.firePrice, dir = "down", bis = bisName, sourceLow = box.low, dayKey = box.dayKey }
    end
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
    local bisPrefix = string.upper(tostring(ev.bis or "BIS"))
    local label = isUp and (bisPrefix .. " UP") or (bisPrefix .. " DOWN")
    local price = isUp and (ev.price + offset) or (ev.price - offset)
    local output = isUp and O.txtBisUp or O.txtBisDown
    safeTextSet(output, period, price, label)
    return true
end

local function formatBoxLabel(boxName, high, low)
    return string.format("%s H: %.5f L: %.5f", boxName, high, low)
end

local function clearEvents(ev)
    ev.consolidationCreated = nil
    ev.bis1Fired = nil
    ev.bis2Fired = nil
    ev.sessionHighUpdated = nil
    ev.sessionLowUpdated = nil
end

local function selectPrimaryBisEvent(ev)
    return ev.bis1Fired or ev.bis2Fired
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
    st.consolidation.active = false
    st.debug.hasCandidate = false
    st.debug.candidateRange = nil
end

local function updateBoxesAndBis(period, canRender)
    local st = S.state
    local ev = st.events
    local src = S.source

    if not canRender then return end

    local ts = src:date(period)
    local shift = instance.parameters.timezoneshifthours or 0
    local key = getDayKey(ts, shift)
    local prevStartMin = normalizeMinute(instance.parameters.prevboxstartmin or (22 * 60))
    local prevEndMin = normalizeMinute(instance.parameters.prevboxendmin or (24 * 60))
    local londonStartMin = normalizeMinute(instance.parameters.londonstartmin or (3 * 60))
    local londonEndMin = normalizeMinute(instance.parameters.londonendmin or (12 * 60))
    local minute = minuteOfDay(ts)

    if st.prev2230Box.dayKey ~= key then
        resetBisEvent(st.bis1)
    end
    if st.londonBox.dayKey ~= key then
        resetBisEvent(st.bis2)
    end

    local prevInWindow = isInWindow(ts, prevStartMin, prevEndMin)
    local prevOwnerDayKey = key
    if prevInWindow and prevStartMin > (prevEndMin == 1440 and 0 or prevEndMin) and minute ~= nil and minute < (prevEndMin == 1440 and 0 or prevEndMin) then
        prevOwnerDayKey = key - 1
    end
    local prevTargetDayKey = prevInWindow and (prevOwnerDayKey + 1) or key
    accumulateBox(st.prev2230Box, {
        dayKey = prevTargetDayKey,
        bar = period,
        ts = ts,
        high = src.high[period],
        low = src.low[period],
        inWindow = prevInWindow,
        windowEnded = (not prevInWindow) and key >= prevTargetDayKey
    })

    local londonInWindow = isInWindow(ts, londonStartMin, londonEndMin)
    local londonEndNorm = (londonEndMin == 1440) and 0 or londonEndMin
    local londonWindowEnded = (not londonInWindow) and (londonStartMin == londonEndNorm or minute == nil or minute >= londonEndNorm)
    accumulateBox(st.londonBox, {
        dayKey = key,
        bar = period,
        ts = ts,
        high = src.high[period],
        low = src.low[period],
        inWindow = londonInWindow,
        windowEnded = londonWindowEnded
    })

    if st.prev2230Box.dayKey == key then
        tryFireBisFromBox(period, ts, src, st.prev2230Box, st.bis1, ev, "bis1", "bis1Fired")
    end
    if st.londonBox.dayKey == key then
        tryFireBisFromBox(period, ts, src, st.londonBox, st.bis2, ev, "bis2", "bis2Fired")
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

    local primaryBis = selectPrimaryBisEvent(ev)
    if primaryBis ~= nil then
        sess.active = true
        sess.sourceConsolidationId = primaryBis.bis
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

local function render(period, canRender, mode)
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
    T.prev2230High[period] = nil
    T.prev2230Low[period] = nil
    T.prev2230HighBand[period] = nil
    T.prev2230LowBand[period] = nil
    T.prev2230Mid[period] = nil
    T.londonHigh[period] = nil
    T.londonLow[period] = nil
    T.londonHighBand[period] = nil
    T.londonLowBand[period] = nil
    T.londonMid[period] = nil
    T.bis1State[period] = 0
    T.bis2State[period] = 0

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
            disp.bis1Shown = false
            disp.bis2Shown = false
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
            disp.bis1Shown = false
            disp.bis2Shown = false
            disp.sessionHighShown = false
            disp.sessionLowShown = false
        end
        disp.consStartBar = con.startBar
        disp.consEndBar = con.endBar or period
        disp.consHigh = con.high
        disp.consLow = con.low
    end

    if con.active and disp.consHigh ~= nil and disp.consLow ~= nil and disp.consStartBar ~= nil then
        local boxStart = disp.consStartBar
        local boxEnd = period
        for i = boxStart, boxEnd do
            T.consolidationHigh[i] = disp.consHigh
            T.consolidationLow[i] = disp.consLow
            T.consolidationHighBand[i] = disp.consHigh
            T.consolidationLowBand[i] = disp.consLow
        end
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

    local ts = src:date(period)
    local minute = minuteOfDay(ts)
    local shift = instance.parameters.timezoneshifthours or 0
    local key = getDayKey(ts, shift)
    local londonStartMin = normalizeMinute(instance.parameters.londonstartmin or (3 * 60))
    local londonEndMin = normalizeMinute(instance.parameters.londonendmin or (12 * 60))
    local londonExtendMin = normalizeMinute(instance.parameters.londonextendmin or 1440)

    local prevBox = st.prev2230Box
    local showPrev2230 = instance.parameters.showprev2230box and prevBox ~= nil and prevBox.high ~= nil and prevBox.low ~= nil and prevBox.dayKey == key
    if showPrev2230 and minute ~= nil then
        T.prev2230High[period] = prevBox.high
        T.prev2230Low[period] = prevBox.low
        T.prev2230HighBand[period] = prevBox.high
        T.prev2230LowBand[period] = prevBox.low
        if instance.parameters.showboxmid then
            T.prev2230Mid[period] = (prevBox.high + prevBox.low) / 2
        end
        if instance.parameters.showboxlabels and disp.prev2230LabelDayKey ~= key then
            local labelBar = prevBox.startBar or period
            safeTextSet(O.txtPrev2230Box, labelBar, prevBox.high + offset, formatBoxLabel("Prev 22:00", prevBox.high, prevBox.low))
            disp.prev2230LabelDayKey = key
        end
    end

    local londonBox = st.londonBox
    local showLondon = instance.parameters.showlondonbox and londonBox ~= nil and londonBox.high ~= nil and londonBox.low ~= nil and londonBox.dayKey == key
    local londonVisible = false
    if showLondon and minute ~= nil then
        local inLondonWindow = isInWindow(ts, londonStartMin, londonEndMin)
        local inExtension = londonBox.isReady and minute >= normalizeMinute(londonEndMin) and minute < londonExtendMin
        londonVisible = inLondonWindow or inExtension
    end
    if londonVisible then
        T.londonHigh[period] = londonBox.high
        T.londonLow[period] = londonBox.low
        T.londonHighBand[period] = londonBox.high
        T.londonLowBand[period] = londonBox.low
        if instance.parameters.showboxmid then
            T.londonMid[period] = (londonBox.high + londonBox.low) / 2
        end
        if instance.parameters.showboxlabels and londonBox.isReady and disp.londonLabelDayKey ~= key then
            local labelBar = londonBox.startBar or period
            safeTextSet(O.txtLondonBox, labelBar, londonBox.high + offset, formatBoxLabel("London", londonBox.high, londonBox.low))
            disp.londonLabelDayKey = key
        end
    end

    if ev.consolidationCreated ~= nil and not disp.consShown then
        safeTextSet(O.txtConsolidation, ev.consolidationCreated.bar, ev.consolidationCreated.low - offset, "CONS ✓")
        disp.consShown = true
    end

    if ev.bis1Fired ~= nil and not disp.bis1Shown then
        renderBisLabel(ev.bis1Fired, ev.bis1Fired.bar, offset)
        disp.bis1Shown = true
    end

    if ev.bis2Fired ~= nil and not disp.bis2Shown then
        renderBisLabel(ev.bis2Fired, ev.bis2Fired.bar, offset)
        disp.bis2Shown = true
    end

    T.bis1State[period] = ev.bis1Fired ~= nil and (ev.bis1Fired.dir == "up" and 1 or -1) or T.bis1State[period]
    T.bis2State[period] = ev.bis2Fired ~= nil and (ev.bis2Fired.dir == "up" and 1 or -1) or T.bis2State[period]

    if ev.sessionHighUpdated ~= nil and not disp.sessionHighShown and disp.session.showSessionLabels then
        safeTextSet(O.txtTarget, ev.sessionHighUpdated.bar, ev.sessionHighUpdated.price + offset, "HOS/HOD ✓")
        disp.sessionHighShown = true
    end

    if ev.sessionLowUpdated ~= nil and not disp.sessionLowShown and disp.session.showSessionLabels then
        safeTextSet(O.txtTarget, ev.sessionLowUpdated.bar, ev.sessionLowUpdated.price - offset, "LOS/LOD ✓")
        disp.sessionLowShown = true
    end

    if instance.parameters.debug and shouldRenderDebug(period, mode) then
        local reason = st.gate and st.gate.bisBlockReason or st.bisBlockReason or "PASS"
        local consState = con.active and "CONS: ACTIVE" or "CONS: IDLE"
        local candidateState = st.debug.hasCandidate and "CAND: YES" or "CAND: NO"
        local consRange = ""
        if con.high ~= nil and con.low ~= nil then
            consRange = string.format(" [%.5f - %.5f]", con.low, con.high)
        end
        local candRange = ""
        if st.debug.candidateRange ~= nil then
            candRange = string.format(" | CAND_R: %.5f", st.debug.candidateRange)
        end
        if st.debug.lastTextPeriod ~= nil and st.debug.lastTextPeriod ~= period then
            local prevLow = src.low[st.debug.lastTextPeriod] or src.low[period]
            safeTextSet(O.txtDebug, st.debug.lastTextPeriod, prevLow - offset * 2, "")
        end
        local condCfg = string.format("CFG m:%d s:%d a:%d x:%.2f d:%.2f", st.debug.minBars or 0, st.debug.staleBars or 0, st.debug.atrLen or 0, st.debug.maxAtrMult or 0, st.debug.trendLimit or 0)
        local condVal = string.format("VAL rg:%s/%s dr:%s/%s", st.debug.range and string.format("%.5f", st.debug.range) or "na", st.debug.rangeLimit and string.format("%.5f", st.debug.rangeLimit) or "na", st.debug.drift and string.format("%.5f", st.debug.drift) or "na", st.debug.driftLimit and string.format("%.5f", st.debug.driftLimit) or "na")
        safeTextSet(O.txtDebug, period, src.low[period] - offset * 2, "GATE: " .. reason .. " | " .. consState .. consRange .. " | " .. candidateState .. candRange .. " | " .. condCfg .. " | " .. condVal)
        st.debug.lastTextPeriod = period
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

    p:addBoolean("requiretradeday", "Require Trade Day Gate", "", false)
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
    p:addBoolean("showprev2230box", "Show Prev 22:00 Box", "", true)
    p:addColor("prev2230color", "Prev 22:00 Box Color", "", core.rgb(255, 140, 0))
    p:addInteger("prev2230fillalpha", "Prev 22:00 Box Fill Alpha", "", 25)
    p:addBoolean("showlondonbox", "Show London Box", "", true)
    p:addColor("londoncolor", "London Box Color", "", core.rgb(30, 144, 255))
    p:addInteger("londonfillalpha", "London Box Fill Alpha", "", 25)
    p:addBoolean("showboxlabels", "Show Box Labels", "", true)
    p:addBoolean("showboxmid", "Show Box Mid Line", "", false)
    p:addInteger("bislabelfontsize", "BIS Label Font Size", "", 9)
    p:addColor("bislabelcolor", "BIS Label Color", "", core.rgb(34, 139, 34))
    p:addString("bislabelalign", "BIS Label Align", "", "Center")
    p:addStringAlternative("bislabelalign", "Left", "Left", "")
    p:addStringAlternative("bislabelalign", "Center", "Center", "")
    p:addStringAlternative("bislabelalign", "Right", "Right", "")
    p:addBoolean("bisusetimewindow", "Use BIS Time Window", "", true)
    p:addInteger("biswindowstartmin", "BIS Window Start Minute", "", 0)
    p:addInteger("biswindowendmin", "BIS Window End Minute", "", 570)
    p:addInteger("prevboxstartmin", "Prev Box Start Minute", "", 22 * 60)
    p:addInteger("prevboxendmin", "Prev Box End Minute", "", 24 * 60)
    p:addInteger("londonstartmin", "London Box Start Minute", "", 3 * 60)
    p:addInteger("londonendmin", "London Box End Minute", "", 12 * 60)
    p:addInteger("londonextendmin", "London Box Extend Until Minute", "", 24 * 60)
    p:addInteger("timezoneshifthours", "Timezone Shift Hours", "", 0)
    p:addBoolean("bisonceperbox", "BIS Once Per Box", "", false)
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
    T.bis1State = instance:addStream("bis1_state", core.Line, "BIS1 State (1=up,-1=down,0=idle)", "", core.rgb(46, 139, 87), S.first)
    T.bis2State = instance:addStream("bis2_state", core.Line, "BIS2 State (1=up,-1=down,0=idle)", "", core.rgb(30, 144, 255), S.first)
    T.prev2230High = instance:addStream("prev2230_high", core.Line, "Prev 22:00 Box High", "", instance.parameters.prev2230color, S.first)
    T.prev2230Low = instance:addStream("prev2230_low", core.Line, "Prev 22:00 Box Low", "", instance.parameters.prev2230color, S.first)
    T.prev2230HighBand = addInternalBandStream("prev2230_high_band", "Prev 22:00 High Band", S.first, instance.parameters.prev2230color)
    T.prev2230LowBand = addInternalBandStream("prev2230_low_band", "Prev 22:00 Low Band", S.first, instance.parameters.prev2230color)
    T.prev2230Mid = instance:addStream("prev2230_mid", core.Line, "Prev 22:00 Box Mid", "", instance.parameters.prev2230color, S.first)
    T.londonHigh = instance:addStream("london_high", core.Line, "London Box High", "", instance.parameters.londoncolor, S.first)
    T.londonLow = instance:addStream("london_low", core.Line, "London Box Low", "", instance.parameters.londoncolor, S.first)
    T.londonHighBand = addInternalBandStream("london_high_band", "London High Band", S.first, instance.parameters.londoncolor)
    T.londonLowBand = addInternalBandStream("london_low_band", "London Low Band", S.first, instance.parameters.londoncolor)
    T.londonMid = instance:addStream("london_mid", core.Line, "London Box Mid", "", instance.parameters.londoncolor, S.first)

    O.txtConsolidation = instance:createTextOutput("", "SB_CONSOLIDATION", "Arial", 8, core.H_Center, core.V_Top, core.rgb(210, 210, 210), 0)
    local bisAlign = resolveHorizontalAlign(instance.parameters.bislabelalign)
    local bisFontSize = math.max(6, instance.parameters.bislabelfontsize or 9)
    local bisColor = instance.parameters.bislabelcolor or core.rgb(34, 139, 34)
    O.txtBisUp = instance:createTextOutput("", "SB_BIS_UP", "Arial", bisFontSize, bisAlign, core.V_Bottom, bisColor, 0)
    O.txtBisDown = instance:createTextOutput("", "SB_BIS_DOWN", "Arial", bisFontSize, bisAlign, core.V_Top, core.rgb(220, 20, 60), 0)
    O.txtTarget = instance:createTextOutput("", "SB_TARGET", "Arial", 8, core.H_Center, core.V_Top, core.rgb(255, 215, 0), 0)
    O.txtPrev2230Box = instance:createTextOutput("", "SB_PREV2230_BOX", "Arial", 8, core.H_Left, core.V_Bottom, instance.parameters.prev2230color, 0)
    O.txtLondonBox = instance:createTextOutput("", "SB_LONDON_BOX", "Arial", 8, core.H_Left, core.V_Bottom, instance.parameters.londoncolor, 0)
    O.txtDebug = instance:createTextOutput("", "SB_STRUCTURE_DEBUG", "Arial", 7, core.H_Left, core.V_Top, core.rgb(180, 180, 180), 0)

    S.state.display.session = createSessionDisplay(instance.parameters)
    O.consolidationChannel = createChannelGroup("SB_CONSOLIDATION_CHANNEL", instance.parameters.conscolor, instance.parameters.consfillalpha, T.consolidationHighBand, T.consolidationLowBand)
    bindChannelGroup(O.consolidationChannel, T.consolidationHighBand, T.consolidationLowBand)
    O.sessionChannel = createChannelGroup("SB_SESSION_CHANNEL", S.state.display.session.color, S.state.display.session.fillAlpha, T.sessionHigh, T.sessionLow)
    bindChannelGroup(O.sessionChannel, T.sessionHigh, T.sessionLow)
    O.prev2230Channel = createChannelGroup("SB_PREV2230_CHANNEL", instance.parameters.prev2230color, instance.parameters.prev2230fillalpha, T.prev2230HighBand, T.prev2230LowBand)
    bindChannelGroup(O.prev2230Channel, T.prev2230HighBand, T.prev2230LowBand)
    O.londonChannel = createChannelGroup("SB_LONDON_CHANNEL", instance.parameters.londoncolor, instance.parameters.londonfillalpha, T.londonHighBand, T.londonLowBand)
    bindChannelGroup(O.londonChannel, T.londonHighBand, T.londonLowBand)
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

    -- User requirement: do not gate structure rendering by trade-day semantics.
    local canRenderStructure = true

    updateBoxesAndBis(period, canRenderStructure)
    detectConsolidation(period, canRenderStructure)
    updateSession(period, canRenderStructure)
    render(period, canRenderStructure, mode)
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

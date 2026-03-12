local state = {
    source = nil,
    first = nil,
    d1 = nil,
    dayatrlen = 14,
    dumppumpatrm = 1.0,
    showdaytypelabels = true,
    debug = false,
    biasStream = nil,
    tradeDayStream = nil,
    fgdLabelStream = nil,
    frdLabelStream = nil,
    tradeLabelStream = nil,
    hudDayTypeStream = nil,
    hudTradeDayStream = nil,
    hudBiasStream = nil,
    hudSummaryStream = nil,
    hudBlockedStream = nil,
    d1IndexByDateKey = {},
    dayMarks = {},
    lastDailyIndex = nil,
    hudDrawer = nil,
    hudCanDraw = nil,
    hudPrefix = "SB_DAYTYPE_HUD_"
}

local function trace(msg)
    if state ~= nil and state.debug == true and core ~= nil and core.host ~= nil and core.host.trace ~= nil then
        pcall(function()
            core.host:trace("SB_DayType_FRD_FGD " .. tostring(msg))
        end)
    end
end

local HUD_STRING_STYLE = core.String ~= nil and core.String or core.Line

local function deleteHudLabel(id)
    if core == nil or core.host == nil or id == nil then
        return
    end

    pcall(function() core.host:execute("removeLabel", id) end)
    pcall(function() core.host:execute("deleteLabel", id) end)
    pcall(function() core.host:execute("clearLabel", id) end)
end

local function drawHudLabel(id, text, row, color)
    if core == nil or core.host == nil then
        return false
    end

    local ok = false

    if not ok then
        ok = pcall(function()
            core.host:execute("drawLabel1", id, "TL", 8, 8 + row * 18, text, color)
        end)
    end

    if not ok then
        ok = pcall(function()
            core.host:execute("drawLabel", id, "TL", 8, 8 + row * 18, text, color)
        end)
    end

    if not ok then
        ok = pcall(function()
            core.host:execute("drawLabel1", id, text, "TL", row)
        end)
    end

    if not ok then
        ok = pcall(function()
            core.host:execute("drawLabel", id, text, "TL", row)
        end)
    end

    return ok
end

local function updateHudLabels(dayTypeText, tradeDayText, biasText)
    local dayTypeId = state.hudPrefix .. "DAYTYPE"
    local tradeDayId = state.hudPrefix .. "TRADEDAY"
    local biasId = state.hudPrefix .. "BIAS"

    deleteHudLabel(dayTypeId)
    deleteHudLabel(tradeDayId)
    deleteHudLabel(biasId)

    local ok1 = drawHudLabel(dayTypeId, dayTypeText, 0, core.rgb(240, 240, 240))
    local ok2 = drawHudLabel(tradeDayId, tradeDayText, 1, core.rgb(135, 206, 250))
    local ok3 = drawHudLabel(biasId, biasText, 2, core.rgb(255, 215, 0))

    state.hudCanDraw = ok1 and ok2 and ok3
end

function Init()
    indicator:name("SB DayType FRD FGD")
    indicator:description("SB DayType FRD FGD")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addInteger("dayatrlen", "Day ATR Length", "", 14)
    indicator.parameters:addDouble("dumppumpatrm", "Dump Pump ATR Mult", "", 1.0)
    indicator.parameters:addBoolean("showdaytypelabels", "Show DayType Labels", "", true)
    indicator.parameters:addBoolean("debug", "Debug", "", false)
end

local function dateKey(v)
    return math.floor(v)
end

local function drawTextCompat(context, x, y, text, color)
    if context == nil then
        return false
    end

    local ok = pcall(function()
        context:drawText(x, y, text, color)
    end)
    if ok then
        return true
    end

    ok = pcall(function()
        context:drawText(x, y, text)
    end)
    if ok then
        return true
    end

    ok = pcall(function()
        context:drawText(text, x, y, color)
    end)
    if ok then
        return true
    end

    ok = pcall(function()
        context:drawText(text, x, y)
    end)

    return ok
end

local function getVisibleRange(context)
    local firstVisible = nil
    local lastVisible = nil

    if context ~= nil then
        local okFirst, valueFirst = pcall(function() return context:firstBar() end)
        if okFirst then
            firstVisible = valueFirst
        end

        local okLast, valueLast = pcall(function() return context:lastBar() end)
        if okLast then
            lastVisible = valueLast
        end

        if firstVisible == nil then
            local okFirstVisible, valueFirstVisible = pcall(function() return context:firstVisibleBar() end)
            if okFirstVisible then
                firstVisible = valueFirstVisible
            end
        end

        if lastVisible == nil then
            local okLastVisible, valueLastVisible = pcall(function() return context:lastVisibleBar() end)
            if okLastVisible then
                lastVisible = valueLastVisible
            end
        end
    end

    if state.source ~= nil then
        if firstVisible == nil then
            firstVisible = state.source:first()
        end
        if lastVisible == nil then
            lastVisible = state.source:size() - 1
        end
    end

    return firstVisible, lastVisible
end

local function calcATR(d1, dailyIndex, len)
    if d1 == nil or dailyIndex == nil then
        return nil
    end

    local startIndex = dailyIndex - len + 1
    if startIndex < d1:first() + 1 then
        return nil
    end

    local sumTR = 0
    local count = 0
    local i = startIndex

    while i <= dailyIndex do
        local h = d1.high[i]
        local l = d1.low[i]
        local prevClose = d1.close[i - 1]
        local tr1 = h - l
        local tr2 = math.abs(h - prevClose)
        local tr3 = math.abs(l - prevClose)
        local tr = math.max(tr1, math.max(tr2, tr3))

        sumTR = sumTR + tr
        count = count + 1
        i = i + 1
    end

    if count == 0 then
        return nil
    end

    return sumTR / count
end

local function evaluateDayType(d1, dayIndex, atrLen, atrMult)
    if d1 == nil or dayIndex == nil then
        return nil
    end

    local y = dayIndex - 1
    local p = dayIndex - 2
    local pp = dayIndex - 3

    if pp < d1:first() then
        return nil
    end

    local day = {
        yOpen = d1.open[y],
        yHigh = d1.high[y],
        yLow = d1.low[y],
        yClose = d1.close[y],
        yRange = d1.high[y] - d1.low[y],

        pOpen = d1.open[p],
        pHigh = d1.high[p],
        pLow = d1.low[p],
        pClose = d1.close[p],
        pRange = d1.high[p] - d1.low[p],

        ppOpen = d1.open[pp],
        ppHigh = d1.high[pp],
        ppLow = d1.low[pp],
        ppClose = d1.close[pp],
        ppRange = d1.high[pp] - d1.low[pp],

        dOpen = d1.open[dayIndex],
        dClose = d1.close[dayIndex],
        dRange = d1.high[dayIndex] - d1.low[dayIndex],

        atr = calcATR(d1, y, atrLen)
    }

    if day.atr == nil or day.atr <= 0 then
        return nil
    end

    local threshold = day.atr * atrMult
    local yChange = day.yClose - day.pClose

    local dumpYesterday = yChange <= -threshold
    local pumpYesterday = yChange >= threshold

    local yFgd = pumpYesterday
    local yFrd = dumpYesterday

    local dFgd = dumpYesterday and (day.dClose > day.dOpen)
    local dFrd = pumpYesterday and (day.dClose < day.dOpen)

    local bias = 0
    if dFgd then
        bias = 1
    elseif dFrd then
        bias = -1
    end

    return {
        dumpYesterday = dumpYesterday,
        pumpYesterday = pumpYesterday,
        dFgd = dFgd,
        dFrd = dFrd,
        yFgd = yFgd,
        yFrd = yFrd,
        tradeDayToday = yFgd or yFrd,
        bias = bias
    }
end

local function findDailyIndexByTime(t)
    local key = dateKey(t)
    local idx = state.d1IndexByDateKey[key]
    if idx ~= nil then
        return idx
    end

    if state.d1 == nil then
        return nil
    end

    local i = state.d1:first()
    local last = state.d1:size() - 1
    while i <= last do
        local dkey = dateKey(state.d1:date(i))
        state.d1IndexByDateKey[dkey] = i
        if dkey == key then
            return i
        end
        i = i + 1
    end

    return nil
end

function Prepare(nameOnly)
    if instance == nil then
        return
    end

    state.debug = instance.parameters.debug
    trace("Prepare start")

    state.source = instance.source
    if state.source == nil then
        trace("source failed")
        return
    end

    trace("source ok")
    state.first = state.source:first()
    if state.first == nil then
        trace("first failed")
        return
    end

    local ownerDrawnOk = pcall(function()
        instance:ownerDrawn(true)
    end)
    if ownerDrawnOk then
        trace("ownerDrawn enabled")
    else
        trace("ownerDrawn enable failed")
    end

    local name = profile:id() .. "(" .. state.source:name() .. ")"
    instance:name(name)

    if nameOnly then
        return
    end

    state.dayatrlen = instance.parameters.dayatrlen
    state.dumppumpatrm = instance.parameters.dumppumpatrm
    state.showdaytypelabels = instance.parameters.showdaytypelabels
    state.debug = instance.parameters.debug
    trace("parameters ok")

    state.biasStream = instance:addStream("Bias", core.Line, "Bias", "", core.rgb(255, 215, 0), state.first)
    state.tradeDayStream = instance:addStream("TradeDay", core.Line, "Trade Day", "", core.rgb(30, 144, 255), state.first)
    state.fgdLabelStream = instance:addStream("FGD", core.Line, "FGD", "", core.rgb(0, 200, 0), state.first)
    state.frdLabelStream = instance:addStream("FRD", core.Line, "FRD", "", core.rgb(220, 20, 60), state.first)
    state.tradeLabelStream = instance:addStream("TRADE_DAY", core.Line, "TRADE DAY", "", core.rgb(255, 140, 0), state.first)

    state.hudDayTypeStream = instance:addStream("hud_daytype", HUD_STRING_STYLE, "DAYTYPE", "", core.rgb(240, 240, 240), state.first)
    state.hudTradeDayStream = instance:addStream("hud_tradeday", HUD_STRING_STYLE, "TRADE DAY", "", core.rgb(135, 206, 250), state.first)
    state.hudBiasStream = instance:addStream("hud_bias", HUD_STRING_STYLE, "BIAS", "", core.rgb(255, 215, 0), state.first)
    state.hudSummaryStream = instance:addStream("hud_summary", HUD_STRING_STYLE, "STATUS", "", core.rgb(255, 255, 255), state.first)
    state.hudBlockedStream = instance:addStream("hud_blocked", HUD_STRING_STYLE, "BLOCKED", "", core.rgb(255, 99, 71), state.first)

    local streamsOk = state.biasStream ~= nil and state.tradeDayStream ~= nil and state.fgdLabelStream ~= nil and
        state.frdLabelStream ~= nil and state.tradeLabelStream ~= nil and state.hudDayTypeStream ~= nil and
        state.hudTradeDayStream ~= nil and state.hudBiasStream ~= nil and state.hudSummaryStream ~= nil and
        state.hudBlockedStream ~= nil
    if streamsOk then
        trace("streams ok")
    else
        trace("streams failed")
    end

    local okHistory, history = pcall(function()
        return core.host:execute(
        "getSyncHistory",
        state.source:instrument(),
        "D1",
        state.source:isBid(),
        0,
        0
    )
    end)
    if okHistory then
        state.d1 = history
    else
        state.d1 = nil
    end

    if state.d1 ~= nil then
        trace("history ok")
    else
        trace("history failed")
    end

    trace("Prepare finish")
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

function Update(period, mode)
    trace("Update start")

    if state == nil or state.source == nil or state.first == nil then
        trace("missing source/first")
        return
    end

    if period < state.first then
        return
    end

    if state.d1 == nil then
        trace("missing H.d1")
        return
    end

    if state.dayKey == nil then
        state.dayKey = dateKey(state.source:date(period))
    elseif state.dayKey ~= dateKey(state.source:date(period)) then
        state.dayKey = dateKey(state.source:date(period))
        trace("day reset")
    end

    trace("core calculation start")
    local okDailyFirst, dailyFirst = pcall(function() return state.d1:first() end)
    if not okDailyFirst or dailyFirst == nil then
        trace("missing H.d1 first")
        return
    end

    local currentDateKey = dateKey(state.source:date(period))
    local dailyIndex = findDailyIndexByTime(state.source:date(period))
    if dailyIndex == nil then
        trace("dailyIndex not found")
        state.dayMarks[currentDateKey] = "NONE"
        trace("dayMarks[" .. tostring(currentDateKey) .. "] written")
        trace("mark = NONE")
        return
    end
    trace("dailyIndex found: " .. tostring(dailyIndex))

    local result = evaluateDayType(state.d1, dailyIndex, state.dayatrlen, state.dumppumpatrm)
    if result == nil then
        trace("result not found")
        state.dayMarks[currentDateKey] = "NONE"
        trace("dayMarks[" .. tostring(currentDateKey) .. "] written")
        trace("mark = NONE")
        trace("core calculation finish")
        return
    end
    trace("result found")

    local dayMark = "NONE"
    if result.yFrd then
        dayMark = "FRD"
    elseif result.yFgd then
        dayMark = "FGD"
    elseif result.tradeDayToday then
        dayMark = "TD"
    end
    state.dayMarks[currentDateKey] = dayMark
    trace("dayMarks[" .. tostring(currentDateKey) .. "] written")
    trace("mark = " .. dayMark)

    trace("core calculation finish")

    if state.biasStream ~= nil then
        state.biasStream[period] = result.bias
    else
        trace("missing bias stream")
    end
    if state.tradeDayStream ~= nil then
        state.tradeDayStream[period] = result.tradeDayToday and 1 or 0
    else
        trace("missing trade day stream")
    end

    local dayTypeText = "DAYTYPE: NONE"
    if result.yFgd then
        dayTypeText = "DAYTYPE: FGD"
    elseif result.yFrd then
        dayTypeText = "DAYTYPE: FRD"
    end

    local tradeDayText = result.tradeDayToday and "TRADE DAY: YES" or "TRADE DAY: NO"

    local biasText = "BIAS: NONE"
    if result.bias > 0 then
        biasText = "BIAS: BULL"
    elseif result.bias < 0 then
        biasText = "BIAS: BEAR"
    end

    local blockedText = result.tradeDayToday and "" or "BLOCKED: NOT TRADE DAY"
    local statusText = dayTypeText .. " | " .. tradeDayText .. " | " .. biasText

    updateHudLabels(dayTypeText, tradeDayText, biasText)

    writeHudStream(state.hudDayTypeStream, period, dayTypeText, result.dFgd and 1 or (result.dFrd and -1 or 0))
    writeHudStream(state.hudTradeDayStream, period, tradeDayText, result.tradeDayToday and 1 or 0)
    writeHudStream(state.hudBiasStream, period, biasText, result.bias)
    writeHudStream(state.hudSummaryStream, period, statusText, result.bias)
    writeHudStream(state.hudBlockedStream, period, blockedText, result.tradeDayToday and 0 or 1)

    if state.showdaytypelabels then
        if state.fgdLabelStream ~= nil then
            state.fgdLabelStream[period] = result.dFgd and state.source.close[period] or 0
        else
            trace("missing FGD label stream")
        end
        if state.frdLabelStream ~= nil then
            state.frdLabelStream[period] = result.dFrd and state.source.close[period] or 0
        else
            trace("missing FRD label stream")
        end
        if state.tradeLabelStream ~= nil then
            state.tradeLabelStream[period] = result.tradeDayToday and state.source.open[period] or 0
        else
            trace("missing trade label stream")
        end
    else
        if state.fgdLabelStream ~= nil then
            state.fgdLabelStream[period] = 0
        end
        if state.frdLabelStream ~= nil then
            state.frdLabelStream[period] = 0
        end
        if state.tradeLabelStream ~= nil then
            state.tradeLabelStream[period] = 0
        end
    end

    trace("stream write finish")
end

function Draw(stage, context)
    trace("Draw called stage=" .. tostring(stage))

    if stage ~= 2 then
        return
    end

    trace("Draw stage 2 entered")

    local firstVisible, lastVisible = getVisibleRange(context)
    trace("visible first bar = " .. tostring(firstVisible))
    trace("visible last bar = " .. tostring(lastVisible))

    local y = 8
    local drewHud = drawTextCompat(context, 8, y, "TEST HUD", core.rgb(255, 255, 0))
    if not drewHud then
        trace("TEST HUD draw failed")
    end

    if state.source == nil or firstVisible == nil or lastVisible == nil then
        return
    end

    if firstVisible < state.source:first() then
        firstVisible = state.source:first()
    end

    local sourceLast = state.source:size() - 1
    if lastVisible > sourceLast then
        lastVisible = sourceLast
    end

    local uniqueDates = {}
    local orderedDates = {}
    local i = firstVisible
    while i <= lastVisible do
        local key = dateKey(state.source:date(i))
        if uniqueDates[key] == nil then
            uniqueDates[key] = true
            table.insert(orderedDates, key)
        end
        i = i + 1
    end

    local foundEvent = false
    local maxRows = 14
    local row = 1
    local j = 1
    while j <= #orderedDates and row <= maxRows do
        local key = orderedDates[j]
        local mark = state.dayMarks[key]
        if mark == nil then
            mark = "NO MARK"
        end

        if mark == "FRD" or mark == "FGD" or mark == "TD" then
            foundEvent = true
        end

        drawTextCompat(context, 8, y + row * 16, tostring(key) .. " " .. mark, core.rgb(220, 220, 220))
        row = row + 1
        j = j + 1
    end

    if not foundEvent then
        drawTextCompat(context, 8, y + row * 16, "CURRENT VIEW: NO FRD/FGD/TD FOUND", core.rgb(255, 99, 71))
    end
end

function ReleaseInstance()
    deleteHudLabel(state.hudPrefix .. "DAYTYPE")
    deleteHudLabel(state.hudPrefix .. "TRADEDAY")
    deleteHudLabel(state.hudPrefix .. "BIAS")

    state.d1 = nil
    state.d1IndexByDateKey = {}
    state.dayMarks = {}
    state.lastDailyIndex = nil
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
end

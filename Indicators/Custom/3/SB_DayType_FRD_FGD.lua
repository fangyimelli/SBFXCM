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
    d1IndexByDateKey = {},
    dayMarks = {},
    dayOrder = {},
    drawFont = nil
}

local function trace(msg)
    if state ~= nil and state.debug == true and core ~= nil and core.host ~= nil and core.host.trace ~= nil then
        pcall(function()
            core.host:trace("SB_DayType_FRD_FGD " .. tostring(msg))
        end)
    end
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

local function ensureDayMark(period)
    local key = dateKey(state.source:date(period))
    local mark = state.dayMarks[key]
    if mark == nil then
        mark = {
            firstPeriod = period,
            isFgd = false,
            isFrd = false,
            isTradeDay = false
        }
        state.dayMarks[key] = mark
        state.dayOrder[#state.dayOrder + 1] = key
    elseif period < mark.firstPeriod then
        mark.firstPeriod = period
    end

    return mark
end

function Prepare(nameOnly)
    if instance == nil then
        return
    end

    state.debug = instance.parameters.debug
    state.source = instance.source
    if state.source == nil then
        return
    end

    state.first = state.source:first()
    if state.first == nil then
        return
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

    instance:ownerDrawn(true)

    state.biasStream = instance:addStream("Bias", core.Line, "Bias", "", core.rgb(255, 215, 0), state.first)
    state.tradeDayStream = instance:addStream("TradeDay", core.Line, "Trade Day", "", core.rgb(30, 144, 255), state.first)

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

    state.dayMarks = {}
    state.dayOrder = {}
    state.d1IndexByDateKey = {}
    state.drawFont = nil

    trace("Prepare finish")
end

function Update(period, mode)
    if state == nil or state.source == nil or state.first == nil or state.d1 == nil then
        return
    end

    if period < state.first then
        return
    end

    local dailyIndex = findDailyIndexByTime(state.source:date(period))
    if dailyIndex == nil then
        return
    end

    local result = evaluateDayType(state.d1, dailyIndex, state.dayatrlen, state.dumppumpatrm)
    if result == nil then
        return
    end

    if state.biasStream ~= nil then
        state.biasStream[period] = result.bias
    end

    if state.tradeDayStream ~= nil then
        state.tradeDayStream[period] = result.tradeDayToday and 1 or 0
    end

    local mark = ensureDayMark(period)
    mark.isFgd = mark.isFgd or result.dFgd
    mark.isFrd = mark.isFrd or result.dFrd
    mark.isTradeDay = mark.isTradeDay or result.tradeDayToday
end

local function drawDayLabel(context, font, x, y, text, color)
    local width, height = context:measureText(font, text, 0)
    local tx = x - math.floor(width / 2)
    context:drawText(font, text, color, -1, tx, y, width, height, 0)
end

function Draw(stage, context)
    if stage ~= 2 then
        return
    end

    if state.showdaytypelabels ~= true then
        return
    end

    if state.source == nil then
        return
    end

    if state.drawFont == nil then
        state.drawFont = context:createFont("Arial", 9, false, false)
    end

    local topY = context:top() + 4
    local lineHeight = 14

    local i = 1
    while i <= #state.dayOrder do
        local key = state.dayOrder[i]
        local mark = state.dayMarks[key]

        if mark ~= nil and mark.firstPeriod ~= nil then
            local x = state.source:position(mark.firstPeriod)
            if x ~= nil then
                local row = 0

                if mark.isFgd then
                    drawDayLabel(context, state.drawFont, x, topY + row * lineHeight, "FGD", core.rgb(0, 200, 0))
                    row = row + 1
                end

                if mark.isFrd then
                    drawDayLabel(context, state.drawFont, x, topY + row * lineHeight, "FRD", core.rgb(220, 20, 60))
                    row = row + 1
                end

                if mark.isTradeDay then
                    drawDayLabel(context, state.drawFont, x, topY + row * lineHeight, "Trade Day", core.rgb(255, 140, 0))
                end
            end
        end

        i = i + 1
    end
end

function ReleaseInstance()
    state.d1 = nil
    state.d1IndexByDateKey = {}
    state.dayMarks = {}
    state.dayOrder = {}
    state.drawFont = nil
end

-- SB DayType FRD/FGD (D1 only)
-- Standalone D1 bias/trade-day classifier.

local NAME = "SB DayType FRD FGD"

local source = nil
local biasstream = nil
local tradedaystream = nil

local state = {
    dayKey = nil,
    isTradeDay = false,
    bias = 0,
    dumpYesterday = false,
    pumpYesterday = false,
}

local function dbg(msg)
    if instance.parameters.debug then
        core.host:trace(NAME .. " | " .. msg)
    end
end

local function normalizeDir(v)
    if v == nil then
        return 0
    end
    if v > 0 then
        return 1
    end
    if v < 0 then
        return -1
    end
    return 0
end

local function getDayKey(ts)
    local d = core.dateToTable(ts)
    return (d.year * 10000) + (d.month * 100) + d.day
end

local function avgDayRange(period, len)
    local sum = 0
    local count = 0
    local idx = period - 1
    while idx >= source:first() and count < len do
        sum = sum + math.abs(source.close[idx] - source.open[idx])
        count = count + 1
        idx = idx - 1
    end
    if count == 0 then
        return 0
    end
    return sum / count
end

function Init()
    indicator:name(NAME)
    indicator:description("D1 FRD/FGD classifier with bias/trade-day streams")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Core")
    indicator.parameters:addInteger("dayatrlen", "dayatrlen", 14, 2, 200)
    indicator.parameters:addDouble("dumppumpatrm", "dumppumpatrm", 1.0, 0.1, 10.0)
    indicator.parameters:addBoolean("showdaytypelabels", "showdaytypelabels", true)
    indicator.parameters:addBoolean("debug", "debug", false)
    indicator.parameters:addBoolean("focusmode", "focusmode", false)
    indicator.parameters:addInteger("focusinput", "focusinput", 0, -1, 1)
end

function Prepare(nameOnly)
    source = instance.source
    instance:name(NAME)
    if nameOnly then
        return
    end

    local first = source:first()
    biasstream = instance:addStream("BIAS", core.Line, "biasstream", "biasstream", first)
    tradedaystream = instance:addStream("TRDAY", core.Line, "tradedaystream", "tradedaystream", first)
end

function Update(period, mode)
    if period < source:first() + 2 then
        return
    end

    local t = source:date(period)
    local key = getDayKey(t)
    if state.dayKey ~= key then
        state.dayKey = key
    end

    -- Core data (D1)
    local yOpen = source.open[period - 1]
    local yClose = source.close[period - 1]
    local yRange = math.abs(yClose - yOpen)

    local y2Open = source.open[period - 2]
    local y2Close = source.close[period - 2]
    local y2Range = math.abs(y2Close - y2Open)

    local dayATR = avgDayRange(period, instance.parameters.dayatrlen)

    -- Core judgements
    local dumpYesterday = (yOpen - yClose) >= (instance.parameters.dumppumpatrm * dayATR)
    local pumpYesterday = (yClose - yOpen) >= (instance.parameters.dumppumpatrm * dayATR)

    local yFgd = pumpYesterday and (yClose > y2Close) and (yRange >= y2Range)
    local yFrd = dumpYesterday and (yClose < y2Close) and (yRange >= y2Range)

    local dOpen = source.open[period]
    local dClose = source.close[period]
    local dFgd = yFrd and (dClose > dOpen)
    local dFrd = yFgd and (dClose < dOpen)

    local tradeDayToday = yFgd or yFrd or dFgd or dFrd

    local bias = 0
    if dFgd or yFgd then
        bias = 1
    elseif dFrd or yFrd then
        bias = -1
    end

    if instance.parameters.focusmode then
        bias = normalizeDir(instance.parameters.focusinput)
    end

    state.isTradeDay = tradeDayToday
    state.bias = normalizeDir(bias)
    state.dumpYesterday = dumpYesterday
    state.pumpYesterday = pumpYesterday

    biasstream[period] = state.bias
    tradedaystream[period] = state.isTradeDay and 1 or 0

    if instance.parameters.debug then
        dbg(string.format(
            "isTradeDay=%s, bias=%d, dumpYesterday=%s, pumpYesterday=%s",
            tostring(state.isTradeDay),
            state.bias,
            tostring(state.dumpYesterday),
            tostring(state.pumpYesterday)
        ))
    end

    if instance.parameters.showdaytypelabels and mode == core.UpdateLast then
        -- Stream-only module: label drawing intentionally omitted.
    end
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
    -- No async operations in this D1 stream-only module.
end

function ReleaseInstance()
    biasstream = nil
    tradedaystream = nil
    source = nil
end

-- SB Structure Engine
-- Keep only: 5m Asia range + 15m Sweep + 15m BOS, state capped at BOS.

local NAME = "SB Structure Engine"

local STAGE = {
    IDLE = 0,
    ASIAREADY = 1,
    SWEPT = 2,
    BOS = 3,
}

local source = nil
local outAsiaH, outAsiaL, outBos, outState, outSweepDir = nil, nil, nil, nil, nil

local state = {
    stage = STAGE.IDLE,
    asiaHigh = nil,
    asiaLow = nil,
    sweepDir = 0,
    bosDir = 0,
    bosLevel = nil,
    lastDayKey = nil,
}

local agg15 = {
    bucket = nil,
    o = nil,
    h = nil,
    l = nil,
    c = nil,
}

local last15 = nil

local function parseHHMM(hhmm)
    local digits = tostring(hhmm or "0000")
    if string.len(digits) < 4 then
        digits = string.rep("0", 4 - string.len(digits)) .. digits
    end
    local h = tonumber(string.sub(digits, 1, 2)) or 0
    local m = tonumber(string.sub(digits, 3, 4)) or 0
    h = math.min(23, math.max(0, h))
    m = math.min(59, math.max(0, m))
    return h, m
end

local function parseSession(sess)
    local a, b = string.match(tostring(sess or ""), "(%d%d%d%d)%-(%d%d%d%d)")
    return a or "0000", b or "2359"
end

local function inSession(ts, sess)
    local s1, s2 = parseSession(sess)
    local h1, m1 = parseHHMM(s1)
    local h2, m2 = parseHHMM(s2)
    local x = h1 * 60 + m1
    local y = h2 * 60 + m2
    local dt = core.dateToTable(ts)
    local v = dt.hour * 60 + dt.min
    if x <= y then
        return v >= x and v <= y
    end
    return v >= x or v <= y
end

local function dayKey(ts)
    local d = core.dateToTable(ts)
    return (d.year * 10000) + (d.month * 100) + d.day
end

local function resetDay()
    state.stage = STAGE.IDLE
    state.asiaHigh = nil
    state.asiaLow = nil
    state.sweepDir = 0
    state.bosDir = 0
    state.bosLevel = nil
    agg15.bucket, agg15.o, agg15.h, agg15.l, agg15.c = nil, nil, nil, nil, nil
    last15 = nil
end

local function onClosed15(bar)
    if state.asiaHigh ~= nil and state.asiaLow ~= nil and state.stage == STAGE.IDLE then
        state.stage = STAGE.ASIAREADY
    end

    if state.stage == STAGE.ASIAREADY and state.sweepDir == 0 then
        local upSweep = (bar.h > state.asiaHigh) and (bar.c < state.asiaHigh)
        local dnSweep = (bar.l < state.asiaLow) and (bar.c > state.asiaLow)
        if upSweep then
            state.sweepDir = 1
            state.stage = STAGE.SWEPT
        elseif dnSweep then
            state.sweepDir = -1
            state.stage = STAGE.SWEPT
        end
    end

    if state.stage == STAGE.SWEPT and last15 ~= nil and state.bosLevel == nil then
        if state.sweepDir == 1 and bar.l < last15.l and bar.c < last15.l then
            state.bosDir = -1
            state.bosLevel = last15.l
            state.stage = STAGE.BOS
        elseif state.sweepDir == -1 and bar.h > last15.h and bar.c > last15.h then
            state.bosDir = 1
            state.bosLevel = last15.h
            state.stage = STAGE.BOS
        end
    end

    last15 = bar
end

local function update15(ts, o, h, l, c)
    local bucket = math.floor(ts / (15 * 60))
    if agg15.bucket == nil then
        agg15.bucket, agg15.o, agg15.h, agg15.l, agg15.c = bucket, o, h, l, c
        return
    end
    if bucket ~= agg15.bucket then
        onClosed15({ o = agg15.o, h = agg15.h, l = agg15.l, c = agg15.c, ts = ts })
        agg15.bucket, agg15.o, agg15.h, agg15.l, agg15.c = bucket, o, h, l, c
        return
    end
    agg15.h = math.max(agg15.h, h)
    agg15.l = math.min(agg15.l, l)
    agg15.c = c
end

function Init()
    indicator:name(NAME)
    indicator:description("5m Asia range + 15m sweep/BOS only")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Sessions")
    indicator.parameters:addString("asiaSession", "Asia Session", "2000-0000")
end

function Prepare(nameOnly)
    source = instance.source
    instance:name(NAME)
    if nameOnly then return end

    local first = source:first()
    outAsiaH = instance:addStream("ASIAH", core.Line, "Asia High", "AsiaH", first)
    outAsiaL = instance:addStream("ASIAL", core.Line, "Asia Low", "AsiaL", first)
    outBos = instance:addStream("BOSLEVEL", core.Line, "BOS Level", "BOS", first)
    outState = instance:addStream("STATEDEBUG", core.Line, "State", "State", first)
    outSweepDir = instance:addStream("SWEEPDIR", core.Line, "Sweep Dir", "Sweep", first)
end

function Update(period, mode)
    if period < source:first() then return end

    local t = source:date(period)
    local o = source.open[period]
    local h = source.high[period]
    local l = source.low[period]
    local c = source.close[period]

    local dk = dayKey(t)
    if state.lastDayKey == nil then
        state.lastDayKey = dk
    elseif state.lastDayKey ~= dk then
        state.lastDayKey = dk
        resetDay()
    end

    if inSession(t, instance.parameters.asiaSession) then
        state.asiaHigh = (state.asiaHigh == nil) and h or math.max(state.asiaHigh, h)
        state.asiaLow = (state.asiaLow == nil) and l or math.min(state.asiaLow, l)
    end

    update15(t, o, h, l, c)

    outAsiaH[period] = state.asiaHigh
    outAsiaL[period] = state.asiaLow
    outBos[period] = state.bosLevel
    outState[period] = state.stage
    outSweepDir[period] = state.sweepDir
end

function ReleaseInstance()
    outAsiaH, outAsiaL, outBos, outState, outSweepDir = nil, nil, nil, nil, nil
    source = nil
end

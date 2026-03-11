-- SB Entry Qualifier
-- Keep only: 15m FVG, 5m mitigation, retest zone, Blue1/2/3, EMA20 gate/reclaim/reject/cooldown.

local NAME = "SB Entry Qualifier"

local source = nil
local outFvgU, outFvgL, outRetU, outRetL, outBlue1, outBlue2, outBlue3 = nil, nil, nil, nil, nil, nil, nil

local state = {
    sweepDir = 0,
    bosDir = 0,
    bosLevel = nil,
    fvgU = nil,
    fvgL = nil,
    mitigated = false,
    retU = nil,
    retL = nil,
    blue1Last = -1e12,
    blue2Last = -1e12,
    blue3Last = -1e12,
    blue1ArmedTs = nil,
    ema20 = nil,
    asiaHigh = nil,
    asiaLow = nil,
    lastDayKey = nil,
}

local agg15 = { bucket = nil, o = nil, h = nil, l = nil, c = nil }
local bars15 = {}

local function dayKey(ts)
    local d = core.dateToTable(ts)
    return (d.year * 10000) + (d.month * 100) + d.day
end

local function pipSize(symbol)
    local p = nil
    if instance ~= nil and instance.bid ~= nil and instance.bid:instrument() ~= nil then
        p = instance.bid:instrument():getPipSize()
    end
    if p ~= nil and p > 0 then return p end
    local symText = (type(symbol) == "string") and symbol or tostring(symbol or "")
    if string.find(string.upper(symText), "JPY", 1, true) ~= nil then return 0.01 end
    return 0.0001
end

local function wickReject(dir, o, h, l, c, wickMin, bodyMax)
    local body = math.abs(c - o)
    local range = h - l
    if range <= 0 then return false end
    local upperWick = h - math.max(o, c)
    local lowerWick = math.min(o, c) - l
    local wick = (dir == 1) and lowerWick or upperWick
    return (wick / range) >= wickMin and (body / range) <= bodyMax
end

local function emaStep(prev, x, len)
    if prev == nil then return x end
    local k = 2 / (len + 1)
    return prev + k * (x - prev)
end

local function resetDay()
    state.sweepDir = 0
    state.bosDir = 0
    state.bosLevel = nil
    state.fvgU = nil
    state.fvgL = nil
    state.mitigated = false
    state.retU = nil
    state.retL = nil
    state.blue1ArmedTs = nil
    state.asiaHigh = nil
    state.asiaLow = nil
    agg15 = { bucket = nil, o = nil, h = nil, l = nil, c = nil }
    bars15 = {}
end

local function push15(bar)
    table.insert(bars15, bar)
    if #bars15 > 6 then table.remove(bars15, 1) end

    local n = #bars15
    if n >= 2 and state.bosLevel == nil then
        local prev = bars15[n - 1]
        if state.sweepDir == 1 and bar.l < prev.l and bar.c < prev.l then
            state.bosDir = -1
            state.bosLevel = prev.l
        elseif state.sweepDir == -1 and bar.h > prev.h and bar.c > prev.h then
            state.bosDir = 1
            state.bosLevel = prev.h
        end
    end

    if state.sweepDir == 0 and state.bosLevel == nil and n >= 1 then
        local b = bars15[n]
        local upSweep = state.asiaHigh ~= nil and b.h > state.asiaHigh and b.c < state.asiaHigh
        local dnSweep = state.asiaLow ~= nil and b.l < state.asiaLow and b.c > state.asiaLow
        if upSweep then state.sweepDir = 1 end
        if dnSweep then state.sweepDir = -1 end
    end

    if state.bosLevel ~= nil and state.fvgU == nil and n >= 3 then
        local b0 = bars15[n]
        local b2 = bars15[n - 2]
        if state.bosDir == 1 and b0.l > b2.h then
            state.fvgL = b2.h
            state.fvgU = b0.l
        elseif state.bosDir == -1 and b0.h < b2.l then
            state.fvgL = b0.h
            state.fvgU = b2.l
        end
    end
end

local function update15(ts, o, h, l, c)
    local bucket = math.floor(ts / (15 * 60))
    if agg15.bucket == nil then
        agg15.bucket, agg15.o, agg15.h, agg15.l, agg15.c = bucket, o, h, l, c
        return
    end
    if bucket ~= agg15.bucket then
        push15({ o = agg15.o, h = agg15.h, l = agg15.l, c = agg15.c, ts = ts })
        agg15.bucket, agg15.o, agg15.h, agg15.l, agg15.c = bucket, o, h, l, c
        return
    end
    agg15.h = math.max(agg15.h, h)
    agg15.l = math.min(agg15.l, l)
    agg15.c = c
end

function Init()
    indicator:name(NAME)
    indicator:description("FVG/mitigation/retest/Blue1-3 only")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addGroup("Structure Seed")
    indicator.parameters:addString("asiaSession", "Asia Session", "2000-0000")

    indicator.parameters:addGroup("Retest/Gates")
    indicator.parameters:addDouble("retestBufferPips", "Retest Buffer (pips)", 2.0, 0.1, 50)
    indicator.parameters:addInteger("reactionWindowBars", "Blue2 Reaction Window (5m bars)", 6, 1, 50)
    indicator.parameters:addInteger("cooldownBlue1", "Cooldown Blue1 (min)", 15, 0, 240)
    indicator.parameters:addInteger("cooldownBlue2", "Cooldown Blue2 (min)", 15, 0, 240)
    indicator.parameters:addInteger("cooldownBlue3", "Cooldown Blue3 (min)", 30, 0, 480)
    indicator.parameters:addDouble("rejectWickRatioMin", "Reject Wick Ratio Min", 0.5, 0.0, 1.0)
    indicator.parameters:addDouble("rejectBodyRatioMax", "Reject Body Ratio Max", 0.5, 0.0, 1.0)
end

local function parseHHMM(hhmm)
    local digits = tostring(hhmm or "0000")
    if string.len(digits) < 4 then digits = string.rep("0", 4 - string.len(digits)) .. digits end
    local h = tonumber(string.sub(digits, 1, 2)) or 0
    local m = tonumber(string.sub(digits, 3, 4)) or 0
    return math.min(23, math.max(0, h)), math.min(59, math.max(0, m))
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
    if x <= y then return v >= x and v <= y end
    return v >= x or v <= y
end

function Prepare(nameOnly)
    source = instance.source
    instance:name(NAME)
    if nameOnly then return end

    local first = source:first()
    outFvgU = instance:addStream("FVGU", core.Line, "FVG Upper", "FVGU", first)
    outFvgL = instance:addStream("FVGL", core.Line, "FVG Lower", "FVGL", first)
    outRetU = instance:addStream("RETU", core.Line, "Retest Upper", "RetU", first)
    outRetL = instance:addStream("RETL", core.Line, "Retest Lower", "RetL", first)
    outBlue1 = instance:addStream("BLUE1", core.Line, "Blue1", "Blue1", first)
    outBlue2 = instance:addStream("BLUE2", core.Line, "Blue2", "Blue2", first)
    outBlue3 = instance:addStream("BLUE3", core.Dot, "Blue3", "Blue3", first)
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

    state.ema20 = emaStep(state.ema20, c, 20)

    if inSession(t, instance.parameters.asiaSession) then
        state.asiaHigh = (state.asiaHigh == nil) and h or math.max(state.asiaHigh, h)
        state.asiaLow = (state.asiaLow == nil) and l or math.min(state.asiaLow, l)
    end

    update15(t, o, h, l, c)

    local blue1, blue2, blue3 = false, false, false

    if state.fvgU ~= nil and not state.mitigated and h >= state.fvgL and l <= state.fvgU then
        state.mitigated = true
        local buff = instance.parameters.retestBufferPips * pipSize(source:instrument())
        if state.bosLevel ~= nil then
            state.retU = state.bosLevel + buff
            state.retL = state.bosLevel - buff
        end
    end

    if state.mitigated and state.retU ~= nil and state.retL ~= nil then
        local retHit = h >= state.retL and l <= state.retU
        if retHit and ((t - state.blue1Last) / 60) >= instance.parameters.cooldownBlue1 then
            blue1 = true
            state.blue1Last = t
            state.blue1ArmedTs = t
        end
    end

    if state.blue1ArmedTs ~= nil then
        local barsSinceBlue1 = (t - state.blue1ArmedTs) / 300
        local reclaim = (state.bosDir == 1 and c > state.bosLevel) or (state.bosDir == -1 and c < state.bosLevel)
        local rejectOk = wickReject(state.bosDir, o, h, l, c, instance.parameters.rejectWickRatioMin, instance.parameters.rejectBodyRatioMax)
        if barsSinceBlue1 <= instance.parameters.reactionWindowBars and reclaim and rejectOk and ((t - state.blue2Last) / 60) >= instance.parameters.cooldownBlue2 then
            blue2 = true
            state.blue2Last = t
        end

        local emaOk = (state.bosDir == 1 and c > state.ema20) or (state.bosDir == -1 and c < state.ema20)
        if emaOk and reclaim and ((t - state.blue3Last) / 60) >= instance.parameters.cooldownBlue3 then
            blue3 = true
            state.blue3Last = t
            state.blue1ArmedTs = nil
        end
    end

    outFvgU[period] = state.fvgU
    outFvgL[period] = state.fvgL
    outRetU[period] = state.retU
    outRetL[period] = state.retL
    outBlue1[period] = blue1 and 1 or 0
    outBlue2[period] = blue2 and 1 or 0
    outBlue3[period] = blue3 and c or nil
end

function ReleaseInstance()
    outFvgU, outFvgL, outRetU, outRetL, outBlue1, outBlue2, outBlue3 = nil, nil, nil, nil, nil, nil, nil
    source = nil
end

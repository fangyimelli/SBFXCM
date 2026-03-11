local IDLE = 0
local ASIAREADY = 1
local SWEPT = 2
local BOS = 3

local S = {}
local T = {}
local H = {}
local I = {}

local function trace(msg)
    if S.debug then
        pcall(function() core.host:trace("SB_Structure_Engine: " .. tostring(msg)) end)
    end
end

function Init()
    indicator:name("SB Structure Engine")
    indicator:description("SB Structure Engine")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addString("nysession", "NY Session", "", "0930-1600")
    indicator.parameters:addString("asiasession", "Asia Session", "", "2000-0300")
    indicator.parameters:addBoolean("prefilterlock", "Prefilter Lock", "", true)
    indicator.parameters:addBoolean("allowafterny", "Allow After NY", "", true)
    indicator.parameters:addBoolean("requiresbday", "Require SB Day", "", false)
    indicator.parameters:addInteger("sweepminticks", "Sweep Min Ticks", "", 3)
    indicator.parameters:addInteger("sweepatrlen", "Sweep ATR Len", "", 14)
    indicator.parameters:addDouble("sweepminatrm", "Sweep Min ATR Mult", "", 0.1)
    indicator.parameters:addInteger("sweepreclaimbars", "Sweep Reclaim Bars", "", 1)
    indicator.parameters:addInteger("bosleft", "BOS Pivot Left", "", 2)
    indicator.parameters:addInteger("bosright", "BOS Pivot Right", "", 2)
    indicator.parameters:addInteger("bosconfirmbars", "BOS Confirm Bars", "", 1)
    indicator.parameters:addDouble("bosminatra", "BOS Min ATR", "", 0.0)
    indicator.parameters:addDouble("bosminatraP", "BOS Min ATR Percent", "", 0.0)
    indicator.parameters:addBoolean("debug", "Debug", "", false)

    indicator.parameters:addInteger("dayatrlen", "Day ATR Length", "", 14)
    indicator.parameters:addDouble("dumppumpatrm", "Dump Pump ATR Mult", "", 1.0)
end

local function dayKey(ts)
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
    if sess == nil or sess == "" then
        return false
    end

    local nowMin = minuteOfDay(ts)
    for token in string.gmatch(sess, "[^,]+") do
        local a, b = string.match(token, "^%s*(%d%d?:?%d%d)%s*%-%s*(%d%d?:?%d%d)%s*$")
        if a ~= nil and b ~= nil then
            local s = parseHHMM(a)
            local e = parseHHMM(b)
            if s ~= nil and e ~= nil then
                if s <= e then
                    if nowMin >= s and nowMin <= e then
                        return true
                    end
                else
                    if nowMin >= s or nowMin <= e then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function pipSize(symbol)
    if type(symbol) == "table" then
        if symbol.pipSize ~= nil then
            local ok, v = pcall(function() return symbol:pipSize() end)
            if ok and v ~= nil then
                return v
            end
        end
        local okPoint, point = pcall(function() return symbol:pointSize() end)
        if okPoint and point ~= nil and point > 0 then
            return point * 10
        end
        local okInstr, name = pcall(function() return symbol:name() end)
        if okInstr and name ~= nil then
            symbol = name
        else
            symbol = ""
        end
    end

    local s = string.upper(tostring(symbol or ""))
    if string.find(s, "JPY", 1, true) ~= nil then
        return 0.01
    end
    if string.find(s, "XAU", 1, true) ~= nil or string.find(s, "XAG", 1, true) ~= nil then
        return 0.1
    end
    return 0.0001
end

local function pivotHigh(stream, p, left, right)
    if stream == nil or p == nil then
        return nil
    end
    local start = p - left
    local stop = p + right
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
    local start = p - left
    local stop = p + right
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
        trace("getSyncHistory failed for " .. tostring(timeframe))
        return nil
    end

    return history
end

local function safeGetPriceStream(history, field)
    if history == nil then
        return nil
    end
    local ok, stream = pcall(function() return history[field] end)
    if ok then
        return stream
    end
    return nil
end

local function safeAddStream(id, style, label, color, first)
    local ok, stream = pcall(function()
        return instance:addStream(id, style, label, "", color, first)
    end)
    if not ok then
        trace("addStream failed for " .. tostring(id))
        return nil
    end
    return stream
end

local function findHistoryIndexByTime(history, ts)
    if history == nil or ts == nil then
        return nil
    end

    local target = dayKey(ts)
    local i = history:first()
    local last = history:size() - 1
    local found = nil
    while i <= last do
        local d = history:date(i)
        local k = dayKey(d)
        if k > target then
            break
        end
        if d <= ts then
            found = i
        else
            break
        end
        i = i + 1
    end
    return found
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

local function resetForNewDay(ts)
    S.dayKey = dayKey(ts)
    S.state = IDLE
    S.asiaHigh = nil
    S.asiaLow = nil
    S.sweepDir = 0
    S.sweepTime = nil
    S.sweepUsed = false
    S.swingHigh = nil
    S.swingLow = nil
    S.bosDir = 0
    S.bosLevel = nil
    S.bosTime = nil
    S.blockedReason = ""
    S.bias = 0
    S.isTradeDay = true
end

local function updateDayReset(period)
    local ts = S.source:date(period)
    local k = dayKey(ts)
    if S.dayKey == nil or S.dayKey ~= k then
        resetForNewDay(ts)
    end
end

local function updateDayType(period)
    S.bias = 0
    S.isTradeDay = true

    if H.d1 == nil then
        if S.requiresbday then
            S.isTradeDay = false
            S.blockedReason = "no-d1"
        end
        return
    end

    local d1idx = findHistoryIndexByTime(H.d1, S.source:date(period))
    if d1idx == nil then
        if S.requiresbday then
            S.isTradeDay = false
            S.blockedReason = "no-d1idx"
        end
        return
    end

    local y = d1idx - 1
    if y < H.d1:first() + 1 then
        return
    end

    local atr = calcATR(H.d1, y, S.dayatrlen)
    if atr == nil or atr <= 0 then
        return
    end

    local delta = H.d1.close[y] - H.d1.close[y - 1]
    local thr = atr * S.dumppumpatrm
    if delta >= thr then
        S.bias = 1
    elseif delta <= -thr then
        S.bias = -1
    else
        S.bias = 0
    end

    if S.requiresbday and S.bias == 0 then
        S.isTradeDay = false
        S.blockedReason = "bias0"
    end
end

local function updateAsiaRange(period)
    local ts = S.source:date(period)
    local inAsia = inSession(ts, S.asiasession)
    local inNY = inSession(ts, S.nysession)

    if inAsia then
        local h = S.source.high[period]
        local l = S.source.low[period]
        if S.asiaHigh == nil or h > S.asiaHigh then
            S.asiaHigh = h
        end
        if S.asiaLow == nil or l < S.asiaLow then
            S.asiaLow = l
        end
    end

    if S.asiaHigh ~= nil and S.asiaLow ~= nil then
        if (not inAsia and S.state == IDLE) or (S.prefilterlock and inNY and S.state == IDLE) then
            S.state = ASIAREADY
        end
    end
end

local function updateSweep(period)
    if S.state < ASIAREADY or S.sweepUsed then
        return
    end
    if not S.allowafterny and not inSession(S.source:date(period), S.nysession) then
        return
    end
    if not S.isTradeDay then
        return
    end
    if H.m15 == nil or S.asiaHigh == nil or S.asiaLow == nil then
        return
    end

    local idx = findHistoryIndexByTime(H.m15, S.source:date(period))
    if idx == nil or idx <= H.m15:first() then
        return
    end
    if S.lastM15SweepIdx ~= nil and idx <= S.lastM15SweepIdx then
        return
    end
    S.lastM15SweepIdx = idx

    local atr15 = calcATR(H.m15, idx - 1, S.sweepatrlen)
    local instrumentPip = pipSize(S.source:instrument())
    local tickFloor = S.sweepminticks * instrumentPip
    local atrFloor = 0
    if atr15 ~= nil then
        atrFloor = atr15 * S.sweepminatrm
    end
    local threshold = math.max(tickFloor, atrFloor)

    local h = H.m15.high[idx]
    local l = H.m15.low[idx]
    local c = H.m15.close[idx]

    local upSweep = (h >= S.asiaHigh + threshold) and (c < S.asiaHigh)
    local downSweep = (l <= S.asiaLow - threshold) and (c > S.asiaLow)

    -- TODO: A+ (close reclaim across configurable reclaim bars) can be expanded later.
    if upSweep then
        S.sweepDir = 1
        S.sweepTime = H.m15:date(idx)
        S.sweepUsed = true
        S.state = SWEPT
        S.swingLow = nil
        S.swingHigh = nil
    elseif downSweep then
        S.sweepDir = -1
        S.sweepTime = H.m15:date(idx)
        S.sweepUsed = true
        S.state = SWEPT
        S.swingLow = nil
        S.swingHigh = nil
    end
end

local function checkBosBreak(idx, level, dir)
    if idx == nil or level == nil or dir == nil then
        return false
    end

    local confirms = math.max(1, S.bosconfirmbars)
    local i = 0
    while i < confirms do
        local k = idx - i
        if k < H.m15:first() then
            return false
        end
        if dir > 0 and H.m15.close[k] <= level then
            return false
        end
        if dir < 0 and H.m15.close[k] >= level then
            return false
        end
        i = i + 1
    end

    return true
end

local function updateBos(period)
    if S.state < SWEPT or S.bosDir ~= 0 or H.m15 == nil then
        return
    end

    local idx = findHistoryIndexByTime(H.m15, S.source:date(period))
    if idx == nil then
        return
    end
    if S.lastM15BosIdx ~= nil and idx <= S.lastM15BosIdx then
        return
    end
    S.lastM15BosIdx = idx

    local p = idx - S.bosright
    if p == nil or p < H.m15:first() + S.bosleft then
        return
    end

    local atr15 = calcATR(H.m15, idx - 1, S.sweepatrlen)

    if S.sweepDir > 0 then
        local pl = pivotLow(H.m15, p, S.bosleft, S.bosright)
        if pl ~= nil then
            S.swingLow = pl
        end

        local level = S.swingLow
        if level ~= nil and H.m15.close[idx] < level and checkBosBreak(idx, level, -1) then
            local dist = level - H.m15.close[idx]
            local minMove = S.bosminatra
            if atr15 ~= nil then
                minMove = math.max(minMove, atr15 * S.bosminatraP)
            end
            if dist >= minMove then
                S.bosDir = -1
                S.bosLevel = level
                S.bosTime = H.m15:date(idx)
                S.state = BOS
            end
        end
    elseif S.sweepDir < 0 then
        local ph = pivotHigh(H.m15, p, S.bosleft, S.bosright)
        if ph ~= nil then
            S.swingHigh = ph
        end

        local level = S.swingHigh
        if level ~= nil and H.m15.close[idx] > level and checkBosBreak(idx, level, 1) then
            local dist = H.m15.close[idx] - level
            local minMove = S.bosminatra
            if atr15 ~= nil then
                minMove = math.max(minMove, atr15 * S.bosminatraP)
            end
            if dist >= minMove then
                S.bosDir = 1
                S.bosLevel = level
                S.bosTime = H.m15:date(idx)
                S.state = BOS
            end
        end
    end
end

local function writeStructureStreams(period)
    if T.asiah ~= nil then
        T.asiah[period] = S.asiaHigh
    end
    if T.asial ~= nil then
        T.asial[period] = S.asiaLow
    end
    if T.boslevel ~= nil then
        T.boslevel[period] = S.bosLevel
    end
    if T.statedebug ~= nil then
        T.statedebug[period] = S.state
    end
    if T.sweepdir ~= nil then
        T.sweepdir[period] = S.sweepDir
    end
end

function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()
    instance:name(profile:id() .. "(" .. S.source:name() .. ")")

    if nameOnly then
        return
    end

    S.nysession = instance.parameters.nysession
    S.asiasession = instance.parameters.asiasession
    S.prefilterlock = instance.parameters.prefilterlock
    S.allowafterny = instance.parameters.allowafterny
    S.requiresbday = instance.parameters.requiresbday
    S.sweepminticks = instance.parameters.sweepminticks
    S.sweepatrlen = instance.parameters.sweepatrlen
    S.sweepminatrm = instance.parameters.sweepminatrm
    S.sweepreclaimbars = instance.parameters.sweepreclaimbars
    S.bosleft = instance.parameters.bosleft
    S.bosright = instance.parameters.bosright
    S.bosconfirmbars = instance.parameters.bosconfirmbars
    S.bosminatra = instance.parameters.bosminatra
    S.bosminatraP = instance.parameters.bosminatraP
    S.debug = instance.parameters.debug
    S.dayatrlen = instance.parameters.dayatrlen
    S.dumppumpatrm = instance.parameters.dumppumpatrm

    T.asiah = safeAddStream("asiah", core.Line, "Asia High", core.rgb(255, 140, 0), S.first)
    T.asial = safeAddStream("asial", core.Line, "Asia Low", core.rgb(30, 144, 255), S.first)
    T.boslevel = safeAddStream("boslevel", core.Line, "BOS Level", core.rgb(220, 20, 60), S.first)
    T.statedebug = safeAddStream("statedebug", core.Line, "State", core.rgb(138, 43, 226), S.first)
    T.sweepdir = safeAddStream("sweepdir", core.Line, "Sweep Dir", core.rgb(0, 191, 99), S.first)

    H.m5 = safeGetHistory(S.source:instrument(), "m5", S.source:isBid())
    H.m15 = safeGetHistory(S.source:instrument(), "m15", S.source:isBid())
    H.d1 = safeGetHistory(S.source:instrument(), "D1", S.source:isBid())

    I.m15close = safeGetPriceStream(H.m15, "close")

    resetForNewDay(S.source:date(S.first))
end

function Update(period, mode)
    if period < S.first then
        return
    end

    updateDayReset(period)
    updateDayType(period)
    updateAsiaRange(period)
    updateSweep(period)
    updateBos(period)
    writeStructureStreams(period)
end

function ReleaseInstance()
    H.m5 = nil
    H.m15 = nil
    H.d1 = nil
    I.m15close = nil
end

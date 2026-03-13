local okShared, shared = pcall(dofile, "Indicators/Custom/3/SB_Playbook_Shared.lua")
if not okShared then shared = nil end

local S = {
    source = nil,
    first = nil,
    m15 = nil,
    d1 = nil,
    day_cache = {},
    state = {
        structure = {
            trend = "none",
            lastSwingHigh = nil,
            lastSwingLow = nil,
            prevSwingHigh = nil,
            prevSwingLow = nil,
            bosUp = false,
            bosDown = false,
            chochUp = false,
            chochDown = false,
            structureQualified = false
        }
    },
    day = {
        isTradeDay = false,
        bias = 0
    }
}

local T = {}
local O = {}

function Init()
    indicator:name("SB Structure Engine")
    indicator:description("Structure-only SSOT engine (Swing/BOS/CHoCH/Trend) gated by DayType")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addInteger("bosleft", "BOS Left", "", 2)
    indicator.parameters:addInteger("bosright", "BOS Right", "", 2)
    indicator.parameters:addBoolean("usecloseforbos", "Use Close For BOS", "", true)
    indicator.parameters:addBoolean("enablechoch", "Enable CHoCH", "", true)
    indicator.parameters:addBoolean("requiretradeday", "Require Trade Day", "", true)
    indicator.parameters:addBoolean("requirebiasmatch", "Require Bias Match", "", true)
    indicator.parameters:addBoolean("ignorecounterbiasbreak", "Ignore Counter Bias Break", "", true)
    indicator.parameters:addBoolean("showswinglevels", "Show Swing Levels", "", true)
    indicator.parameters:addBoolean("showbostext", "Show BOS Text", "", true)
    indicator.parameters:addBoolean("showchochtext", "Show CHoCH Text", "", true)
    indicator.parameters:addBoolean("showtrendtext", "Show Trend Text", "", true)
    indicator.parameters:addBoolean("debug", "Debug", "", false)
end

local function getHistory(i, tf, b)
    local ok, h = pcall(function() return core.host:execute("getSyncHistory", i, tf, b, 0, 0) end)
    if ok then return h end
    return nil
end

local function daytype(idx)
    if shared == nil or S.d1 == nil or S.m15 == nil or idx == nil then return nil end
    return shared.build_daytype_record(S.d1, S.m15, idx, {
        rectangle_lookback_bars = 8,
        rectangle_min_contained_closes = 6,
        max_rectangle_height_atr = 1.2,
        dayatrlen = 14
    }, S.day_cache)
end

local function mapTrendToCode(trend)
    if trend == "up" then return 1 end
    if trend == "down" then return -1 end
    return 0
end

local function isBiasMatch(dayBias, trend)
    if dayBias == nil or trend == "none" then return false end
    if dayBias > 0 then return trend == "up" end
    if dayBias < 0 then return trend == "down" end
    return false
end

local function pivotHigh(stream, p, l, r)
    if stream == nil or p == nil then return nil end
    if p < stream:first() + l or p + r > stream:size() - 1 then return nil end
    local v = stream.high[p]
    for i = p - l, p + r do
        if i ~= p and stream.high[i] >= v then return nil end
    end
    return v
end

local function pivotLow(stream, p, l, r)
    if stream == nil or p == nil then return nil end
    if p < stream:first() + l or p + r > stream:size() - 1 then return nil end
    local v = stream.low[p]
    for i = p - l, p + r do
        if i ~= p and stream.low[i] <= v then return nil end
    end
    return v
end

local function safeTextSet(out, period, price, text)
    if out == nil or period == nil or price == nil or text == nil then return end
    out:set(period, price, text)
end

function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()
    instance:name(profile:id() .. "(" .. S.source:name() .. ")")
    if nameOnly then return end

    S.m15 = getHistory(S.source:instrument(), "m15", S.source:isBid())
    S.d1 = getHistory(S.source:instrument(), "D1", S.source:isBid())

    T.trend = instance:addStream("trend", core.Line, "Trend", "", core.rgb(173, 216, 230), S.first)
    T.lastSwingHigh = instance:addStream("last_swing_high", core.Line, "Last Swing High", "", core.rgb(255, 140, 0), S.first)
    T.lastSwingLow = instance:addStream("last_swing_low", core.Line, "Last Swing Low", "", core.rgb(0, 191, 255), S.first)
    T.bosUp = instance:addStream("bos_up", core.Line, "BOS Up", "", core.rgb(0, 200, 0), S.first)
    T.bosDown = instance:addStream("bos_down", core.Line, "BOS Down", "", core.rgb(220, 20, 60), S.first)
    T.chochUp = instance:addStream("choch_up", core.Line, "CHoCH Up", "", core.rgb(152, 251, 152), S.first)
    T.chochDown = instance:addStream("choch_down", core.Line, "CHoCH Down", "", core.rgb(255, 160, 122), S.first)
    T.structureQualified = instance:addStream("structure_qualified", core.Line, "Structure Qualified", "", core.rgb(255, 215, 0), S.first)

    O.txtBosUp = instance:createTextOutput("", "SB_BOS_UP", "Arial", 8, core.H_Center, core.V_Bottom, core.rgb(0, 200, 0), 0)
    O.txtBosDown = instance:createTextOutput("", "SB_BOS_DOWN", "Arial", 8, core.H_Center, core.V_Top, core.rgb(220, 20, 60), 0)
    O.txtChochUp = instance:createTextOutput("", "SB_CHOCH_UP", "Arial", 8, core.H_Center, core.V_Bottom, core.rgb(0, 120, 0), 0)
    O.txtChochDown = instance:createTextOutput("", "SB_CHOCH_DOWN", "Arial", 8, core.H_Center, core.V_Top, core.rgb(178, 34, 34), 0)
    O.txtTrend = instance:createTextOutput("", "SB_TREND", "Arial", 9, core.H_Right, core.V_Top, core.rgb(230, 230, 250), 0)
end

function Update(period, mode)
    if S.source == nil or period < S.first then return end

    local d = nil
    if shared ~= nil and S.m15 ~= nil and S.d1 ~= nil then
        local ts = S.source:date(period)
        local d1idx = shared.find_history_index_by_time(S.d1, ts)
        d = daytype(d1idx)
    end

    S.day.isTradeDay = d ~= nil and d.is_trade_day or false
    S.day.bias = d and (d.day_bias or d.bias) or 0

    local st = S.state.structure
    st.bosUp = false
    st.bosDown = false
    st.chochUp = false
    st.chochDown = false
    st.structureQualified = false

    local bosLeft = math.max(1, instance.parameters.bosleft)
    local bosRight = math.max(1, instance.parameters.bosright)
    local pivotPos = period - bosRight

    local ph = pivotHigh(S.source, pivotPos, bosLeft, bosRight)
    if ph ~= nil then
        st.prevSwingHigh = st.lastSwingHigh
        st.lastSwingHigh = ph
    end

    local pl = pivotLow(S.source, pivotPos, bosLeft, bosRight)
    if pl ~= nil then
        st.prevSwingLow = st.lastSwingLow
        st.lastSwingLow = pl
    end

    local breakHighPrice = instance.parameters.usecloseforbos and S.source.close[period] or S.source.high[period]
    local breakLowPrice = instance.parameters.usecloseforbos and S.source.close[period] or S.source.low[period]
    local prevBreakHigh = (period > S.first) and (instance.parameters.usecloseforbos and S.source.close[period - 1] or S.source.high[period - 1]) or nil
    local prevBreakLow = (period > S.first) and (instance.parameters.usecloseforbos and S.source.close[period - 1] or S.source.low[period - 1]) or nil

    local rawBosUp = st.lastSwingHigh ~= nil and breakHighPrice > st.lastSwingHigh and (period == S.first or prevBreakHigh <= st.lastSwingHigh)
    local rawBosDown = st.lastSwingLow ~= nil and breakLowPrice < st.lastSwingLow and (period == S.first or prevBreakLow >= st.lastSwingLow)

    if instance.parameters.ignorecounterbiasbreak and S.day.bias ~= 0 then
        if S.day.bias > 0 then rawBosDown = false end
        if S.day.bias < 0 then rawBosUp = false end
    end

    local previousTrend = st.trend
    if rawBosUp then
        st.bosUp = true
        if instance.parameters.enablechoch and previousTrend == "down" then st.chochUp = true end
        st.trend = "up"
    end
    if rawBosDown then
        st.bosDown = true
        if instance.parameters.enablechoch and previousTrend == "up" then st.chochDown = true end
        st.trend = "down"
    end

    local tradeDayGateOk = (not instance.parameters.requiretradeday) or S.day.isTradeDay
    local biasGateOk = (not instance.parameters.requirebiasmatch) or isBiasMatch(S.day.bias, st.trend)

    if tradeDayGateOk and biasGateOk and (st.bosUp or st.bosDown or st.chochUp or st.chochDown) then
        st.structureQualified = true
    end

    T.trend[period] = mapTrendToCode(st.trend)
    T.lastSwingHigh[period] = instance.parameters.showswinglevels and st.lastSwingHigh or nil
    T.lastSwingLow[period] = instance.parameters.showswinglevels and st.lastSwingLow or nil
    T.bosUp[period] = st.bosUp and 1 or 0
    T.bosDown[period] = st.bosDown and 1 or 0
    T.chochUp[period] = st.chochUp and 1 or 0
    T.chochDown[period] = st.chochDown and 1 or 0
    T.structureQualified[period] = st.structureQualified and 1 or 0

    local range = (S.source.high[period] - S.source.low[period])
    local offset = range > 0 and range * 0.2 or S.source:pipSize() * 10

    if instance.parameters.showbostext then
        if st.bosUp then safeTextSet(O.txtBosUp, period, S.source.high[period] + offset, "BOS↑") end
        if st.bosDown then safeTextSet(O.txtBosDown, period, S.source.low[period] - offset, "BOS↓") end
    end

    if instance.parameters.showchochtext then
        if st.chochUp then safeTextSet(O.txtChochUp, period, S.source.high[period] + offset * 1.5, "CHoCH↑") end
        if st.chochDown then safeTextSet(O.txtChochDown, period, S.source.low[period] - offset * 1.5, "CHoCH↓") end
    end

    if instance.parameters.showtrendtext then
        local trendText = "TREND NONE"
        if st.trend == "up" then trendText = "TREND UP" end
        if st.trend == "down" then trendText = "TREND DOWN" end
        local trendPrice = st.trend == "down" and (S.source.low[period] - offset * 2) or (S.source.high[period] + offset * 2)
        safeTextSet(O.txtTrend, period, trendPrice, trendText)
    end
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

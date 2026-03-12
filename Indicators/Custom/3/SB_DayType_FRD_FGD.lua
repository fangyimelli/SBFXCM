local okShared, shared = pcall(dofile, "Indicators/Custom/3/SB_Playbook_Shared.lua")
if not okShared then shared = nil end

local S = {source=nil, first=nil, d1=nil, m15=nil, day_cache={}}
local T = {}

function Init()
    indicator:name("SB DayType FRD FGD")
    indicator:description("Day-level Pump/Dump + FRD/FGD event/trade-day definitions")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addInteger("rectangle_lookback_bars", "Rectangle Lookback Bars", "", 8)
    indicator.parameters:addInteger("rectangle_min_contained_closes", "Rectangle Min Contained Closes", "", 6)
    indicator.parameters:addDouble("max_rectangle_height_atr", "Max Rectangle Height ATR", "", 1.2)
    indicator.parameters:addInteger("dayatrlen", "Day ATR Length", "", 14)
    indicator.parameters:addBoolean("debug", "Debug", "", false)
end

local function getHistory(instrument, tf, isBid)
    local ok, h = pcall(function() return core.host:execute("getSyncHistory", instrument, tf, isBid, 0, 0) end)
    if ok then return h end
    return nil
end

local function eval_rectangle(d1Idx)
    if S.m15 == nil or S.d1 == nil or shared == nil then return {valid=false, bar_count=0} end
    local dayStart = shared.day_key(S.d1:date(d1Idx))
    local bars = {}
    local i = S.m15:first()
    local last = S.m15:size() - 1
    while i <= last do
        if shared.day_key(S.m15:date(i)) == dayStart then table.insert(bars, i) end
        i = i + 1
    end
    local lookback = math.max(1, instance.parameters.rectangle_lookback_bars)
    if #bars < lookback then return {valid=false, bar_count=#bars} end

    local startPos = #bars - lookback + 1
    local hi, lo = nil, nil
    local contained = 0
    for j = startPos, #bars do
        local bi = bars[j]
        local h, l, c = S.m15.high[bi], S.m15.low[bi], S.m15.close[bi]
        if hi == nil or h > hi then hi = h end
        if lo == nil or l < lo then lo = l end
    end
    for j = startPos, #bars do
        local c = S.m15.close[bars[j]]
        if c <= hi and c >= lo then contained = contained + 1 end
    end

    local atr = shared.calc_atr(S.d1, d1Idx, instance.parameters.dayatrlen)
    local height = hi - lo
    local atrOk = atr ~= nil and atr > 0 and height <= atr * instance.parameters.max_rectangle_height_atr

    local last4expand = false
    if #bars >= 4 then
        local a = bars[#bars-3]
        local b = bars[#bars]
        last4expand = math.abs(S.m15.close[b] - S.m15.open[a]) > (height * 0.8)
    end

    return {
        valid = atrOk and (contained >= instance.parameters.rectangle_min_contained_closes) and (not last4expand),
        high = hi, low = lo, height = height, bar_count = lookback,
        start_time = S.m15:date(bars[startPos]), end_time = S.m15:date(bars[#bars]),
        contained = contained
    }
end

local function build_day_record(dayIdx)
    local base = shared and shared.evaluate_daytype(S.d1, dayIdx) or nil
    if base == nil then return nil end
    local rect = eval_rectangle(dayIdx)

    local prevBase = shared.evaluate_daytype(S.d1, dayIdx - 1)
    local prevRect = eval_rectangle(dayIdx - 1)
    local todayOpen, todayClose = S.d1.open[dayIdx], S.d1.close[dayIdx]

    local isFrdEvent = prevBase ~= nil and prevBase.is_pump_day and todayClose < todayOpen and rect.valid
    local isFgdEvent = prevBase ~= nil and prevBase.is_dump_day and todayClose > todayOpen and rect.valid

    local isFrdTradeCandidate = S.day_cache[dayIdx - 1] ~= nil and S.day_cache[dayIdx - 1].is_frd_event_day and S.day_cache[dayIdx - 1].has_valid_rectangle
    local isFgdTradeCandidate = S.day_cache[dayIdx - 1] ~= nil and S.day_cache[dayIdx - 1].is_fgd_event_day and S.day_cache[dayIdx - 1].has_valid_rectangle

    local consolidationScore = rect.valid and ((rect.contained >= 7 and rect.height <= (shared.calc_atr(S.d1, dayIdx, instance.parameters.dayatrlen) or 999)) and 2 or 1) or 0
    local threeLevels = 0
    if dayIdx - 5 >= S.d1:first() then
        local wkHigh, wkLow = S.d1.high[dayIdx - 5], S.d1.low[dayIdx - 5]
        if S.d1.high[dayIdx] > wkHigh or S.d1.low[dayIdx] < wkLow then threeLevels = 1 end
        if (S.d1.high[dayIdx] > wkHigh and todayClose < todayOpen) or (S.d1.low[dayIdx] < wkLow and todayClose > todayOpen) then threeLevels = 2 end
    end

    return {
        is_pump_day = base.is_pump_day,
        is_dump_day = base.is_dump_day,
        is_frd_event_day = isFrdEvent,
        is_fgd_event_day = isFgdEvent,
        is_frd_trade_day_candidate = isFrdTradeCandidate,
        is_fgd_trade_day_candidate = isFgdTradeCandidate,
        has_valid_rectangle = rect.valid,
        rectangle_high = rect.high, rectangle_low = rect.low, rectangle_height = rect.height,
        rectangle_bar_count = rect.bar_count, rectangle_start_time = rect.start_time, rectangle_end_time = rect.end_time,
        bias = base.bias,
        repeated_pump_score = base.is_pump_day and 1 or 0,
        repeated_dump_score = base.is_dump_day and 1 or 0,
        consolidation_score = consolidationScore,
        three_levels_score = threeLevels,
        event_score = consolidationScore + threeLevels,
        trade_day_score = (isFrdTradeCandidate or isFgdTradeCandidate) and (consolidationScore + 1) or 0
    }
end

function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()
    instance:name(profile:id() .. "(" .. S.source:name() .. ")")
    if nameOnly then return end

    S.d1 = getHistory(S.source:instrument(), "D1", S.source:isBid())
    S.m15 = getHistory(S.source:instrument(), "m15", S.source:isBid())

    T.pump = instance:addStream("is_pump_day", core.Line, "Pump Day", "", core.rgb(30,160,30), S.first)
    T.dump = instance:addStream("is_dump_day", core.Line, "Dump Day", "", core.rgb(200,60,60), S.first)
    T.frdEvent = instance:addStream("is_frd_event_day", core.Line, "FRD Event", "", core.rgb(220,20,60), S.first)
    T.fgdEvent = instance:addStream("is_fgd_event_day", core.Line, "FGD Event", "", core.rgb(0,180,0), S.first)
    T.frdTrade = instance:addStream("is_frd_trade_day_candidate", core.Line, "FRD Trade Candidate", "", core.rgb(255,140,0), S.first)
    T.fgdTrade = instance:addStream("is_fgd_trade_day_candidate", core.Line, "FGD Trade Candidate", "", core.rgb(255,200,0), S.first)
    T.rectValid = instance:addStream("has_valid_rectangle", core.Line, "Rectangle Valid", "", core.rgb(135,206,250), S.first)
    T.rectHigh = instance:addStream("rectangle_high", core.Line, "Rectangle High", "", core.rgb(255,255,255), S.first)
    T.rectLow = instance:addStream("rectangle_low", core.Line, "Rectangle Low", "", core.rgb(180,180,180), S.first)
    T.bias = instance:addStream("bias", core.Line, "Bias", "", core.rgb(255,215,0), S.first)
    T.eventScore = instance:addStream("event_day_score", core.Line, "Event Score", "", core.rgb(173,216,230), S.first)
    T.tradeScore = instance:addStream("trade_day_score", core.Line, "Trade Day Score", "", core.rgb(255,182,193), S.first)
end

function Update(period, mode)
    if S.source == nil or S.d1 == nil or shared == nil or period < S.first then return end
    local d1Idx = shared.find_history_index_by_time(S.d1, S.source:date(period))
    if d1Idx == nil or d1Idx <= S.d1:first() + 1 then return end

    if S.day_cache[d1Idx] == nil then
        S.day_cache[d1Idx] = build_day_record(d1Idx)
    end
    local d = S.day_cache[d1Idx]
    if d == nil then return end

    T.pump[period] = d.is_pump_day and 1 or 0
    T.dump[period] = d.is_dump_day and 1 or 0
    T.frdEvent[period] = d.is_frd_event_day and 1 or 0
    T.fgdEvent[period] = d.is_fgd_event_day and 1 or 0
    T.frdTrade[period] = d.is_frd_trade_day_candidate and 1 or 0
    T.fgdTrade[period] = d.is_fgd_trade_day_candidate and 1 or 0
    T.rectValid[period] = d.has_valid_rectangle and 1 or 0
    T.rectHigh[period] = d.rectangle_high
    T.rectLow[period] = d.rectangle_low
    T.bias[period] = d.bias
    T.eventScore[period] = d.event_score
    T.tradeScore[period] = d.trade_day_score
end

function ReleaseInstance()
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
end

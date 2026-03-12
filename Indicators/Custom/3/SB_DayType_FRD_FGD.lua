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

local function build_day_record(dayIdx)
    return shared and shared.build_daytype_record(S.d1, S.m15, dayIdx, {
        rectangle_lookback_bars = instance.parameters.rectangle_lookback_bars,
        rectangle_min_contained_closes = instance.parameters.rectangle_min_contained_closes,
        max_rectangle_height_atr = instance.parameters.max_rectangle_height_atr,
        dayatrlen = instance.parameters.dayatrlen
    }, S.day_cache) or nil
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

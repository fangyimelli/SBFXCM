local okShared, shared = pcall(dofile, "Indicators/Custom/3/SB_Playbook_Shared.lua")
if not okShared then shared = nil end

local S={source=nil,first=nil,d1=nil,m15=nil,day_cache={},asia_high=nil,asia_low=nil,day_key=nil,ema=nil}
local T={}

local function getHistory(i,tf,b)
    local ok,h=pcall(function() return core.host:execute("getSyncHistory",i,tf,b,0,0) end)
    if ok then return h end
    return nil
end

function Init()
    indicator:name("SB Trade Manager HUD")
    indicator:description("Display-only HUD for DayType/Structure/Entry wiring and score summary")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)
end

local function writeText(stream, period, text, fallback)
    if stream == nil then return end
    local ok = pcall(function() stream[period] = text end)
    if not ok then stream[period] = fallback end
end

local function btxt(v, yes, no)
    if v then return yes else return no end
end

function Prepare(nameOnly)
    S.source=instance.source
    S.first=S.source:first()
    instance:name(profile:id().."("..S.source:name()..")")
    if nameOnly then return end

    S.d1=getHistory(S.source:instrument(),"D1",S.source:isBid())
    S.m15=getHistory(S.source:instrument(),"m15",S.source:isBid())
    local ok,ema=pcall(function() return core.indicators:create("EMA", S.source.close, 20) end)
    if ok then S.ema=ema end

    local ST=core.String~=nil and core.String or core.Line
    T.wire_daytype=instance:addStream("hud_daytype_wired",ST,"DayType Wired","",core.rgb(240,240,240),S.first)
    T.wire_structure=instance:addStream("hud_structure_wired",ST,"Structure Wired","",core.rgb(240,240,240),S.first)
    T.wire_entry=instance:addStream("hud_entry_wired",ST,"Entry Wired","",core.rgb(240,240,240),S.first)
    T.setup=instance:addStream("hud_setup_state",ST,"Setup State","",core.rgb(135,206,250),S.first)
    T.structure=instance:addStream("hud_structure_state",ST,"Structure State","",core.rgb(255,215,0),S.first)
    T.entry=instance:addStream("hud_entry_state",ST,"Entry State","",core.rgb(255,160,122),S.first)
    T.scores=instance:addStream("hud_scores",ST,"Scores","",core.rgb(144,238,144),S.first)
    T.sources=instance:addStream("hud_score_sources",ST,"Score Sources","",core.rgb(221,160,221),S.first)
    T.impl=instance:addStream("hud_implementation_status",ST,"Implementation Status","",core.rgb(255,99,71),S.first)
end

function Update(period, mode)
    if S.source==nil or period<S.first then return end
    if S.ema~=nil then S.ema:update(mode) end

    local wiredDaytype = shared~=nil and S.d1~=nil and S.m15~=nil
    local wiredStructure = wiredDaytype
    local wiredEntry = wiredDaytype and S.ema~=nil

    local d1idx = wiredDaytype and shared.find_history_index_by_time(S.d1, S.source:date(period)) or nil
    local d = nil
    if d1idx~=nil then
        d = shared.build_daytype_record(S.d1, S.m15, d1idx, {
            rectangle_lookback_bars=8,
            rectangle_min_contained_closes=6,
            max_rectangle_height_atr=1.2,
            dayatrlen=14
        }, S.day_cache)
    end

    local ts = S.source:date(period)
    local k = shared and shared.day_key(ts) or nil
    if k~=nil and (S.day_key==nil or S.day_key~=k) then
        S.day_key=k
        S.asia_high=nil
        S.asia_low=nil
    end
    local inAsia = shared and shared.is_in_asia_window(ts) or false
    if inAsia then
        local h,l=S.source.high[period],S.source.low[period]
        if S.asia_high==nil or h>S.asia_high then S.asia_high=h end
        if S.asia_low==nil or l<S.asia_low then S.asia_low=l end
    end
    local hasAsia=S.asia_high~=nil and S.asia_low~=nil
    local sweepUp=hasAsia and S.source.high[period]>S.asia_high and S.source.close[period]<S.asia_high
    local sweepDown=hasAsia and S.source.low[period]<S.asia_low and S.source.close[period]>S.asia_low

    local rectHigh = d and d.rectangle_high or nil
    local rectLow = d and d.rectangle_low or nil
    local hasBos = false
    local bearBis = rectLow~=nil and S.source.close[period]<rectLow and hasBos
    local bullBis = rectHigh~=nil and S.source.close[period]>rectHigh and hasBos

    local ema20=S.ema and S.ema.DATA and S.ema.DATA[period] or nil
    local inWindow=shared and shared.is_in_any_timing_window(ts) or false
    local okTf, tf = pcall(function() return S.source:barSize() end)
    local on5=okTf and tf==5
    local frdReady=d~=nil and d.is_frd_trade_day_candidate and on5 and inWindow
    local fgdReady=d~=nil and d.is_fgd_trade_day_candidate and on5 and inWindow
    local bearishCloseBackInside=false
    local bullishCloseBackInside=false
    if period>S.first and ema20~=nil then
        bearishCloseBackInside = S.source.high[period] > ema20 and S.source.close[period] < ema20 and S.source.close[period] < S.source.open[period]
        bullishCloseBackInside = S.source.low[period] < ema20 and S.source.close[period] > ema20 and S.source.close[period] > S.source.open[period]
    end
    local frdTrig=frdReady and bearishCloseBackInside
    local fgdTrig=fgdReady and bullishCloseBackInside

    writeText(T.wire_daytype, period, "DayType upstream: "..btxt(wiredDaytype,"wired","not wired"), 0)
    writeText(T.wire_structure, period, "Structure upstream: "..btxt(wiredStructure,"wired","not wired"), 0)
    writeText(T.wire_entry, period, "Entry upstream: "..btxt(wiredEntry,"wired","not wired"), 0)

    local setupTxt = string.format(
        "FRD event=%s | FGD event=%s | FRD trade candidate=%s | FGD trade candidate=%s | rectangle=%s high=%s low=%s",
        btxt(d and d.is_frd_event_day, "true", "false"),
        btxt(d and d.is_fgd_event_day, "true", "false"),
        btxt(d and d.is_frd_trade_day_candidate, "true", "false"),
        btxt(d and d.is_fgd_trade_day_candidate, "true", "false"),
        btxt(d and d.has_valid_rectangle, "valid", "invalid"),
        rectHigh~=nil and tostring(rectHigh) or "not available",
        rectLow~=nil and tostring(rectLow) or "not available"
    )

    local structTxt = string.format(
        "asia range=%s | sweep up=%s | sweep down=%s | BOS=%s(inactive) | bear BIS=%s | bull BIS=%s",
        btxt(hasAsia,"true","false"),
        btxt(sweepUp,"true","false"),
        btxt(sweepDown,"true","false"),
        btxt(hasBos,"true","false"),
        btxt(bearBis,"true","false"),
        btxt(bullBis,"true","false")
    )

    local entryTxt = string.format(
        "FRD ready=%s triggered=%s | FGD ready=%s triggered=%s | EMA20=%s",
        btxt(frdReady,"true","false"),
        btxt(frdTrig,"true","false"),
        btxt(fgdReady,"true","false"),
        btxt(fgdTrig,"true","false"),
        ema20~=nil and "available" or "not available"
    )

    local scoreTxt = string.format(
        "DayType: repeatedPump=%s repeatedDump=%s consolidation=%s threeLevels=%s event=%s trade=%s | Structure: frontback=%s trappedLongs=%s trappedShorts=%s | Entry: followThrough=inactive",
        d and tostring(d.repeated_pump_score) or "0",
        d and tostring(d.repeated_dump_score) or "0",
        d and tostring(d.consolidation_score) or "0",
        d and tostring(d.three_levels_score) or "0",
        d and tostring(d.event_score) or "0",
        d and tostring(d.trade_day_score) or "0",
        hasBos and "1" or "0",
        (sweepUp and 1 or 0),
        (sweepDown and 1 or 0)
    )

    writeText(T.setup, period, setupTxt, 0)
    writeText(T.structure, period, structTxt, 0)
    writeText(T.entry, period, entryTxt, 0)
    writeText(T.scores, period, scoreTxt, 0)
    writeText(T.sources, period, "DayType score source=DayType layer | Structure source=Structure layer | Entry source=Entry layer", 0)
    writeText(T.impl, period, "DayType=implemented | Structure=partially implemented | Entry=implemented | HUD=implemented", 0)
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

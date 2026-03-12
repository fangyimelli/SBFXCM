local okShared, shared = pcall(dofile, "Indicators/Custom/3/SB_Playbook_Shared.lua")
if not okShared then shared = nil end

local S={source=nil,first=nil,d1=nil,m15=nil,day_cache={},structure_runtime={day_key=nil,asia_high=nil,asia_low=nil}}
local T={}

local function getHistory(i,tf,b)
    local ok,h=pcall(function() return core.host:execute("getSyncHistory",i,tf,b,0,0) end)
    if ok then return h end
    return nil
end

function Init()
    indicator:name("SB Trade Manager HUD")
    indicator:description("HUD-only display of upstream DayType/Structure/Entry status")
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

    local ST=core.String~=nil and core.String or core.Line
    T.flow=instance:addStream("hud_flow",ST,"Data Flow","",core.rgb(240,240,240),S.first)
    T.daytype=instance:addStream("hud_daytype_state",ST,"DayType State","",core.rgb(135,206,250),S.first)
    T.structure=instance:addStream("hud_structure_state",ST,"Structure State","",core.rgb(255,215,0),S.first)
    T.entry=instance:addStream("hud_entry_state",ST,"Entry State","",core.rgb(255,160,122),S.first)
    T.score=instance:addStream("hud_score_state",ST,"Score State","",core.rgb(144,238,144),S.first)
    T.impl=instance:addStream("hud_implementation_status",ST,"Implementation Status","",core.rgb(255,99,71),S.first)
end

function Update(period, mode)
    if shared==nil or S.source==nil or S.d1==nil or S.m15==nil or period<S.first then return end

    local ts=S.source:date(period)
    local d1idx=shared.find_history_index_by_time(S.d1, ts)
    local d=nil
    if d1idx~=nil then
        d=shared.build_daytype_record(S.d1, S.m15, d1idx, {
            rectangle_lookback_bars=8,
            rectangle_min_contained_closes=6,
            max_rectangle_height_atr=1.2,
            dayatrlen=14
        }, S.day_cache)
    end

    local structure=shared.update_structure_state(S.structure_runtime, S.source, S.m15, period, {bosleft=2, bosright=2})
    local inWindow=shared.is_in_any_timing_window(ts)
    local okTf, tf = pcall(function() return S.source:barSize() end)
    local on5=okTf and tf==5

    local frdReady=d~=nil and d.is_frd_trade_day_candidate and on5 and inWindow
    local fgdReady=d~=nil and d.is_fgd_trade_day_candidate and on5 and inWindow

    writeText(T.flow, period, "Flow: DayType -> Structure -> Entry -> HUD (HUD display-only)", 0)

    local dayTypeTxt=string.format(
        "DayType SSOT: FRD=%s FGD=%s TradeDay=%s Bias=%s RectValid=%s",
        btxt(d and d.is_frd_event_day,"true","false"),
        btxt(d and d.is_fgd_event_day,"true","false"),
        btxt(d and d.is_trade_day,"true","false"),
        d and tostring(d.day_bias) or "n/a",
        btxt(d and d.rectangle_valid,"true","false")
    )

    local structureTxt=string.format(
        "Structure consume-only: asia=%s sweep=%s bos=%s bias=%s",
        btxt(structure and structure.has_asia_range,"true","false"),
        btxt(structure and structure.has_session_sweep,"true","false"),
        btxt(structure and structure.has_bos,"true","false"),
        (structure and ((structure.has_bos and 1) or 0)) or 0
    )

    local entryTxt=string.format(
        "Entry consume-only: FRD ready=%s | FGD ready=%s | trigger logic owned by Entry indicator",
        btxt(frdReady,"true","false"),
        btxt(fgdReady,"true","false")
    )

    local scoreTxt=string.format(
        "Score source visibility: DayType event=%s trade=%s | Structure frontback=%s | Entry follow-through=see Entry stream",
        d and tostring((d.consolidation_score or 0) + (d.three_levels_score or 0)) or "0",
        d and tostring(d.trade_day_score or 0) or "0",
        structure and tostring((structure.has_bos and 1 or 0)) or "0"
    )

    local implTxt="Upstream status: DayType=implemented, Structure=implemented (consume DayType), Entry=implemented (EMA20 trade-day rules), HUD=display-only"

    writeText(T.daytype, period, dayTypeTxt, 0)
    writeText(T.structure, period, structureTxt, 0)
    writeText(T.entry, period, entryTxt, 0)
    writeText(T.score, period, scoreTxt, 0)
    writeText(T.impl, period, implTxt, 0)
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

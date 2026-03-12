local okShared, shared = pcall(dofile, "Indicators/Custom/3/SB_Playbook_Shared.lua")
if not okShared then shared = nil end

local S={source=nil,first=nil,m5=nil,m15=nil,d1=nil,ema=nil,last_day=nil,day_cache={},frd_triggered=false,fgd_triggered=false,frd_entry_idx=nil,fgd_entry_idx=nil}
local T={}

function Init()
    indicator:name("SB Entry Qualifier")
    indicator:description("FRD/FGD EMA20 close-back-inside entry qualifiers on 5m close")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)
    indicator.parameters:addInteger("followthrough_bars", "Follow Through Bars", "", 3)
end

local function getHistory(i,tf,b) local ok,h=pcall(function() return core.host:execute("getSyncHistory",i,tf,b,0,0) end); if ok then return h end return nil end

local function is5m(source)
    local ok, tf = pcall(function() return source:barSize() end)
    return ok and tf == 5
end

local function dayrecord(idx)
    if shared==nil or S.d1==nil or idx==nil then return nil end
    return shared.build_daytype_record(S.d1, S.m15, idx, {
        rectangle_lookback_bars=8,
        rectangle_min_contained_closes=6,
        max_rectangle_height_atr=1.2,
        dayatrlen=14
    }, S.day_cache)
end

function Prepare(nameOnly)
    S.source=instance.source; S.first=S.source:first(); instance:name(profile:id().."("..S.source:name()..")"); if nameOnly then return end
    S.m5=getHistory(S.source:instrument(),"m5",S.source:isBid())
    S.d1=getHistory(S.source:instrument(),"D1",S.source:isBid())
    S.m15=getHistory(S.source:instrument(),"m15",S.source:isBid())
    local ok,ema=pcall(function() return core.indicators:create("EMA", S.source.close, 20) end)
    if ok then S.ema=ema end

    T.frd_ready=instance:addStream("frd_entry_ready",core.Line,"FRD Entry Ready","",core.rgb(255,165,0),S.first)
    T.frd_trigger=instance:addStream("frd_entry_triggered",core.Line,"FRD Triggered","",core.rgb(220,20,60),S.first)
    T.frd_price=instance:addStream("frd_entry_price",core.Line,"FRD Entry Price","",core.rgb(220,20,60),S.first)
    T.fgd_ready=instance:addStream("fgd_entry_ready",core.Line,"FGD Entry Ready","",core.rgb(255,215,0),S.first)
    T.fgd_trigger=instance:addStream("fgd_entry_triggered",core.Line,"FGD Triggered","",core.rgb(0,200,0),S.first)
    T.fgd_price=instance:addStream("fgd_entry_price",core.Line,"FGD Entry Price","",core.rgb(0,200,0),S.first)
    T.follow_score=instance:addStream("follow_through_score",core.Line,"FollowThroughScore","",core.rgb(135,206,250),S.first)
    T.follow_status=instance:addStream("follow_through_status",core.Line,"FollowThroughStatus","",core.rgb(240,240,240),S.first)
end

function Update(period, mode)
    if shared==nil or S.source==nil or period<S.first then return end
    if S.ema~=nil then S.ema:update(mode) end

    local ts=S.source:date(period)
    local d1idx=shared.find_history_index_by_time(S.d1, ts)
    local d=dayrecord(d1idx)
    local ema20=S.ema and S.ema.DATA and S.ema.DATA[period] or nil
    local inWindow=shared.is_in_any_timing_window(ts)
    local on5=is5m(S.source)

    local frdReady=d~=nil and d.is_frd_trade_day_candidate and on5 and inWindow
    local fgdReady=d~=nil and d.is_fgd_trade_day_candidate and on5 and inWindow

    local bearishCloseBackInside=false
    local bullishCloseBackInside=false
    if period>S.first and ema20~=nil then
        bearishCloseBackInside = S.source.high[period] > ema20 and S.source.close[period] < ema20 and S.source.close[period] < S.source.open[period]
        bullishCloseBackInside = S.source.low[period] < ema20 and S.source.close[period] > ema20 and S.source.close[period] > S.source.open[period]
    end

    local frdTrig = frdReady and bearishCloseBackInside
    local fgdTrig = fgdReady and bullishCloseBackInside
    if frdTrig then S.frd_entry_idx=period end
    if fgdTrig then S.fgd_entry_idx=period end

    local follow=0
    local status=0
    if S.frd_entry_idx~=nil and period>S.frd_entry_idx and period<=S.frd_entry_idx+instance.parameters.followthrough_bars then
        local move=(S.source.close[S.frd_entry_idx]-S.source.close[period])
        if move>0 then follow=1; if move>(S.source.high[S.frd_entry_idx]-S.source.low[S.frd_entry_idx]) then follow=2 end end
    elseif S.fgd_entry_idx~=nil and period>S.fgd_entry_idx and period<=S.fgd_entry_idx+instance.parameters.followthrough_bars then
        local move=(S.source.close[period]-S.source.close[S.fgd_entry_idx])
        if move>0 then follow=1; if move>(S.source.high[S.fgd_entry_idx]-S.source.low[S.fgd_entry_idx]) then follow=2 end end
    end
    if follow==2 then status=2 elseif follow==1 then status=1 else status=0 end

    T.frd_ready[period]=frdReady and 1 or 0
    T.frd_trigger[period]=frdTrig and 1 or 0
    T.frd_price[period]=frdTrig and S.source.close[period] or nil
    T.fgd_ready[period]=fgdReady and 1 or 0
    T.fgd_trigger[period]=fgdTrig and 1 or 0
    T.fgd_price[period]=fgdTrig and S.source.close[period] or nil
    T.follow_score[period]=follow
    T.follow_status[period]=status
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

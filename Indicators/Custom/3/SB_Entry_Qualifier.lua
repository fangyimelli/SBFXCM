local shared=nil
local shared_load_error="not_loaded"
local shared_load_path=nil

local function try_load_shared(path)
    local ok, result = pcall(dofile, path)
    if ok then
        shared = result
        shared_load_error = nil
        shared_load_path = path
        return true
    end
    shared = nil
    shared_load_error = result
    return false
end

local function build_shared_candidates()
    local c={"Indicators/Custom/3/SB_Playbook_Shared.lua"}
    local okInfo, info = pcall(debug.getinfo, 1, "S")
    if okInfo and info and info.source and string.sub(info.source,1,1)=="@" then
        local scriptPath=string.sub(info.source,2)
        local normalized=string.gsub(scriptPath,"\\","/")
        local dir=string.match(normalized,"^(.*)/")
        if dir~=nil then
            c[#c+1]=dir.."/SB_Playbook_Shared.lua"
        end
    end
    return c
end

local function load_shared_with_fallbacks()
    local candidates=build_shared_candidates()
    local lastErr=nil
    for i=1,#candidates do
        if try_load_shared(candidates[i]) then return end
        lastErr=shared_load_error
    end
    shared=nil
    shared_load_error=lastErr or "shared load failed"
    shared_load_path=nil
end

load_shared_with_fallbacks()

local S={source=nil,first=nil,m15=nil,d1=nil,ema=nil,day_cache={},structure_runtime={day_key=nil,asia_high=nil,asia_low=nil},frd_entry_idx=nil,fgd_entry_idx=nil}
local T={}

function Init()
    indicator:name("SB Entry Qualifier")
    indicator:description("Entry-only qualifier: FRD/FGD trade-day EMA20 close-back-inside")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)
    indicator.parameters:addInteger("followthrough_bars", "Follow Through Bars", "", 3)
end

local function getHistory(i,tf,b)
    local ok,h=pcall(function() return core.host:execute("getSyncHistory",i,tf,b,0,0) end)
    if ok then return h end
    return nil
end

local function is5m(source)
    local ok, tf = pcall(function() return source:barSize() end)
    return ok and tf == 5
end

local function dayrecord(idx)
    if shared==nil or S.d1==nil or S.m15==nil or idx==nil then return nil end
    return shared.build_daytype_record(S.d1, S.m15, idx, {
        rectangle_lookback_bars=8,
        rectangle_min_contained_closes=6,
        max_rectangle_height_atr=1.2,
        dayatrlen=14
    }, S.day_cache)
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

    T.consume_trade_day=instance:addStream("entry_consumed_trade_day",core.Line,"Consumed Trade Day","",core.rgb(255,215,0),S.first)
    T.consume_bias=instance:addStream("entry_consumed_day_bias",core.Line,"Consumed Day Bias","",core.rgb(173,216,230),S.first)
    T.consume_rect_valid=instance:addStream("entry_consumed_rectangle_valid",core.Line,"Consumed Rectangle Valid","",core.rgb(135,206,250),S.first)
    T.consume_has_bos=instance:addStream("entry_consumed_structure_has_bos",core.Line,"Consumed Structure BOS","",core.rgb(199,21,133),S.first)
    T.consume_session_sweep=instance:addStream("entry_consumed_structure_session_sweep",core.Line,"Consumed Structure Sweep","",core.rgb(255,140,0),S.first)

    T.frd_ready=instance:addStream("frd_entry_ready",core.Line,"FRD Entry Ready","",core.rgb(255,165,0),S.first)
    T.frd_trigger=instance:addStream("frd_entry_triggered",core.Line,"FRD Triggered","",core.rgb(220,20,60),S.first)
    T.frd_price=instance:addStream("frd_entry_price",core.Line,"FRD Entry Price","",core.rgb(220,20,60),S.first)
    T.fgd_ready=instance:addStream("fgd_entry_ready",core.Line,"FGD Entry Ready","",core.rgb(255,215,0),S.first)
    T.fgd_trigger=instance:addStream("fgd_entry_triggered",core.Line,"FGD Triggered","",core.rgb(0,200,0),S.first)
    T.fgd_price=instance:addStream("fgd_entry_price",core.Line,"FGD Entry Price","",core.rgb(0,200,0),S.first)
    T.follow_score=instance:addStream("follow_through_score",core.Line,"FollowThroughScore","",core.rgb(135,206,250),S.first)
    T.follow_status=instance:addStream("follow_through_status",core.Line,"FollowThroughStatus","",core.rgb(240,240,240),S.first)
    local ST=core.String~=nil and core.String or core.Line
    T.shared_load_status=instance:addStream("shared_load_status",ST,"Shared Load Status","",core.rgb(255,255,255),S.first)
    T.shared_error_flag=instance:addStream("shared_load_error_flag",core.Line,"Shared Load Error Flag","",core.rgb(255,0,0),S.first)

end

function Update(period, mode)
    if S.source==nil or period<S.first then return end

    if shared==nil then
        if T.shared_load_status~=nil then
            local loadStatus="shared load failed"
            if shared_load_path~=nil then loadStatus=loadStatus.." path="..shared_load_path end
            if shared_load_error~=nil then loadStatus=loadStatus.." error="..tostring(shared_load_error) end
            local okStatus=pcall(function() T.shared_load_status[period]=loadStatus end)
            if not okStatus then T.shared_load_status[period]=-1 end
        end
        if T.shared_error_flag~=nil then T.shared_error_flag[period]=1 end
        return
    end

    if T.shared_load_status~=nil then
        local okText="shared loaded"
        if shared_load_path~=nil then okText=okText.." path="..shared_load_path end
        local okStatus=pcall(function() T.shared_load_status[period]=okText end)
        if not okStatus then T.shared_load_status[period]=1 end
    end
    if T.shared_error_flag~=nil then T.shared_error_flag[period]=0 end

    if S.d1==nil or S.m15==nil then return end
    if S.ema~=nil then S.ema:update(mode) end

    local ts=S.source:date(period)
    local d1idx=shared.find_history_index_by_time(S.d1, ts)
    local d=dayrecord(d1idx)
    local structure=shared.update_structure_state(S.structure_runtime, S.source, S.m15, period, {bosleft=2, bosright=2})

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
    if S.frd_entry_idx~=nil and period>S.frd_entry_idx and period<=S.frd_entry_idx+instance.parameters.followthrough_bars then
        local move=(S.source.close[S.frd_entry_idx]-S.source.close[period])
        if move>0 then
            follow=1
            if move>(S.source.high[S.frd_entry_idx]-S.source.low[S.frd_entry_idx]) then follow=2 end
        end
    elseif S.fgd_entry_idx~=nil and period>S.fgd_entry_idx and period<=S.fgd_entry_idx+instance.parameters.followthrough_bars then
        local move=(S.source.close[period]-S.source.close[S.fgd_entry_idx])
        if move>0 then
            follow=1
            if move>(S.source.high[S.fgd_entry_idx]-S.source.low[S.fgd_entry_idx]) then follow=2 end
        end
    end
    local status = (follow==2 and 2) or (follow==1 and 1) or 0

    T.consume_trade_day[period]=(d and d.is_trade_day) and 1 or 0
    T.consume_bias[period]=(d and d.day_bias) or 0
    T.consume_rect_valid[period]=(d and d.rectangle_valid) and 1 or 0
    T.consume_has_bos[period]=(structure and structure.has_bos) and 1 or 0
    T.consume_session_sweep[period]=(structure and structure.has_session_sweep) and 1 or 0

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

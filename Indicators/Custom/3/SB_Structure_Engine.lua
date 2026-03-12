local okShared, shared = pcall(dofile, "Indicators/Custom/3/SB_Playbook_Shared.lua")
if not okShared then shared = nil end

local S={source=nil,first=nil,m15=nil,d1=nil,day_cache={},asia_high=nil,asia_low=nil,day_key=nil}
local T={}

function Init()
 indicator:name("SB Structure Engine")
 indicator:description("Structure confirmation only: Asia/Sweep/BOS/BIS")
 indicator:requiredSource(core.Bar)
 indicator:type(core.Indicator)
 indicator.parameters:addInteger("bosleft", "BOS Left", "", 2)
 indicator.parameters:addInteger("bosright", "BOS Right", "", 2)
 indicator.parameters:addBoolean("debug", "Debug", "", false)
end

local function getHistory(i,tf,b) local ok,h=pcall(function() return core.host:execute("getSyncHistory",i,tf,b,0,0) end); if ok then return h end return nil end
local function pivotHigh(stream,p,l,r) if p<stream:first()+l or p+r>stream:size()-1 then return nil end local v=stream.high[p] for i=p-l,p+r do if i~=p and stream.high[i]>=v then return nil end end return v end
local function pivotLow(stream,p,l,r) if p<stream:first()+l or p+r>stream:size()-1 then return nil end local v=stream.low[p] for i=p-l,p+r do if i~=p and stream.low[i]<=v then return nil end end return v end

local function daytype(idx)
 if S.day_cache[idx]~=nil then return S.day_cache[idx] end
 local base = shared and shared.evaluate_daytype(S.d1, idx) or nil
 if base==nil then return nil end
 local rec = {is_frd_trade_day_candidate=false,is_fgd_trade_day_candidate=false,is_frd_event_day=false,is_fgd_event_day=false,bias=base.bias,rectangle_high=nil,rectangle_low=nil}
 S.day_cache[idx]=rec
 return rec
end

function Prepare(nameOnly)
 S.source=instance.source; S.first=S.source:first(); instance:name(profile:id().."("..S.source:name()..")"); if nameOnly then return end
 S.m15=getHistory(S.source:instrument(),"m15",S.source:isBid())
 S.d1=getHistory(S.source:instrument(),"D1",S.source:isBid())
 T.has_asia_range=instance:addStream("has_asia_range",core.Line,"Has Asia Range","",core.rgb(255,165,0),S.first)
 T.sweep_up=instance:addStream("has_asia_range_sweep_up",core.Line,"Sweep Up","",core.rgb(0,191,255),S.first)
 T.sweep_down=instance:addStream("has_asia_range_sweep_down",core.Line,"Sweep Down","",core.rgb(255,99,71),S.first)
 T.has_bos=instance:addStream("has_bos",core.Line,"Has BOS","",core.rgb(138,43,226),S.first)
 T.bear_bis=instance:addStream("has_bearish_bis_below_rectangle",core.Line,"Bearish BIS","",core.rgb(220,20,60),S.first)
 T.bull_bis=instance:addStream("has_bullish_bis_above_rectangle",core.Line,"Bullish BIS","",core.rgb(0,200,0),S.first)
 T.has_session_sweep=instance:addStream("has_session_sweep",core.Line,"Session Sweep","",core.rgb(255,215,0),S.first)
 T.structure_state=instance:addStream("structure_state",core.Line,"Structure State","",core.rgb(240,240,240),S.first)
 T.structure_bias=instance:addStream("structure_bias",core.Line,"Structure Bias","",core.rgb(173,216,230),S.first)
 T.frontback=instance:addStream("frontside_backside_score",core.Line,"FrontsideBacksideScore","",core.rgb(135,206,235),S.first)
 T.trapped_longs=instance:addStream("trapped_longs_score",core.Line,"TrappedLongsScore","",core.rgb(250,128,114),S.first)
 T.trapped_shorts=instance:addStream("trapped_shorts_score",core.Line,"TrappedShortsScore","",core.rgb(144,238,144),S.first)
end

function Update(period, mode)
 if shared==nil or S.m15==nil or S.d1==nil or period<S.first then return end
 local ts=S.source:date(period)
 local k=shared.day_key(ts)
 if S.day_key==nil or k~=S.day_key then S.day_key=k; S.asia_high=nil; S.asia_low=nil end

 local inAsia=shared.is_in_asia_window(ts)
 if inAsia then
   local h,l=S.source.high[period],S.source.low[period]
   if S.asia_high==nil or h>S.asia_high then S.asia_high=h end
   if S.asia_low==nil or l<S.asia_low then S.asia_low=l end
 end
 local hasAsia=S.asia_high~=nil and S.asia_low~=nil
 local sweepUp=hasAsia and S.source.high[period]>S.asia_high and S.source.close[period]<S.asia_high
 local sweepDown=hasAsia and S.source.low[period]<S.asia_low and S.source.close[period]>S.asia_low

 local idx15=shared.find_history_index_by_time(S.m15, ts)
 local hasBos=false
 if idx15~=nil then
   local p=idx15-2
   local ph=pivotHigh(S.m15,p,instance.parameters.bosleft,instance.parameters.bosright)
   local pl=pivotLow(S.m15,p,instance.parameters.bosleft,instance.parameters.bosright)
   if ph~=nil and S.m15.close[idx15]>ph then hasBos=true end
   if pl~=nil and S.m15.close[idx15]<pl then hasBos=true end
 end

 local d1idx=shared.find_history_index_by_time(S.d1, ts)
 local d=daytype(d1idx)
 local rectHigh = d and d.rectangle_high or nil
 local rectLow = d and d.rectangle_low or nil
 local bearBis = rectLow~=nil and S.source.close[period]<rectLow and hasBos
 local bullBis = rectHigh~=nil and S.source.close[period]>rectHigh and hasBos

 local fbScore=0
 if hasBos then fbScore=1 end
 if bearBis or bullBis then fbScore=2 end
 local trappedLongs=(sweepUp and bearBis) and 2 or (sweepUp and 1 or 0)
 local trappedShorts=(sweepDown and bullBis) and 2 or (sweepDown and 1 or 0)

 T.has_asia_range[period]=hasAsia and 1 or 0
 T.sweep_up[period]=sweepUp and 1 or 0
 T.sweep_down[period]=sweepDown and 1 or 0
 T.has_bos[period]=hasBos and 1 or 0
 T.bear_bis[period]=bearBis and 1 or 0
 T.bull_bis[period]=bullBis and 1 or 0
 T.has_session_sweep[period]=(sweepUp or sweepDown) and 1 or 0
 T.structure_state[period]=fbScore
 T.structure_bias[period]=(bullBis and 1) or (bearBis and -1) or 0
 T.frontback[period]=fbScore
 T.trapped_longs[period]=trappedLongs
 T.trapped_shorts[period]=trappedShorts
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

local okShared, shared = pcall(dofile, "Indicators/Custom/3/SB_Playbook_Shared.lua")
if not okShared then shared = nil end

local S={source=nil,first=nil}
local T={}

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

function Prepare(nameOnly)
    S.source=instance.source
    S.first=S.source:first()
    instance:name(profile:id().."("..S.source:name()..")")
    if nameOnly then return end

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
    writeText(T.wire_daytype, period, "DayType: not wired", 0)
    writeText(T.wire_structure, period, "Structure: not wired", 0)
    writeText(T.wire_entry, period, "Entry: not wired", 0)

    local setupTxt = "Pump/Dump/event/trade-candidate: upstream not wired"
    local structTxt = "Asia/Sweep/BOS/BIS: upstream not wired"
    local entryTxt = "Entry ready/triggered: upstream not wired"
    local scoreTxt = "Repeated/Consolidation/3Levels/FrontBack/Trapped/FollowThrough: not wired"

    writeText(T.setup, period, setupTxt, 0)
    writeText(T.structure, period, structTxt, 0)
    writeText(T.entry, period, entryTxt, 0)
    writeText(T.scores, period, scoreTxt, 0)
    writeText(T.sources, period, "DayType/Structure/Entry/HUD(display only)", 0)
    writeText(T.impl, period, "display only, not logic source | not implemented", 0)
end

function ReleaseInstance() end
function AsyncOperationFinished(cookie, success, message, message1, message2) end

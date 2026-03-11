-- SB Full Manual Workflow (FXCM / Indicore Lua)
-- Minimal import-safe version for Trading Station / Marketscope 2.0

function Init()
    indicator:name("SB Full Manual Workflow FXCM")
    indicator:description("SB Full Manual Workflow FXCM")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addBoolean("debug", "Debug", "", false)
    indicator.parameters:addInteger("dayatrlen", "Day ATR Length", "", 14)
    indicator.parameters:addDouble("dumppumpatrm", "Dump Pump ATR Mult", "", 1.0)
end

local source = nil
local first = nil
local S = {
    debug = false,
    dayatrlen = 14,
    dumppumpatrm = 1.0,
    gate = "ready",
    cananswer = true,
    lastrule = "init",
}
local T = {}
local H = {}
local I = {}

function Prepare(nameOnly)
    source = instance.source
    first = source:first()

    S.debug = instance.parameters.debug
    S.dayatrlen = instance.parameters.dayatrlen
    S.dumppumpatrm = instance.parameters.dumppumpatrm
    S.lastrule = "prepare"

    if nameOnly then
        instance:name("SB Full Manual Workflow FXCM")
        return
    end

    instance:name(profile:id() .. "(" .. source:name() .. ")")
end

function Update(period, mode)
    if period < first then
        return
    end

    S.lastrule = "update"
end

function ReleaseInstance()
end

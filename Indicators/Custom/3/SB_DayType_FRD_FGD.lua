function Init()
    indicator:name("SB DayType FRD FGD")
    indicator:description("SB DayType FRD FGD")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addInteger("dayatrlen", "Day ATR Length", "", 14)
    indicator.parameters:addDouble("dumppumpatrm", "Dump Pump ATR Mult", "", 1.0)
    indicator.parameters:addBoolean("debug", "Debug", "", false)
end

local source = nil
local first = nil

function Prepare(nameOnly)
    source = instance.source
    first = source:first()
    instance:name(profile:id() .. "(" .. source:name() .. ")")
end

function Update(period, mode)
    if period < first then
        return
    end
end

function ReleaseInstance()
end

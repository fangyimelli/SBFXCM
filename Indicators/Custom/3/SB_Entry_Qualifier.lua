function Init()
    indicator:name("SB Entry Qualifier")
    indicator:description("SB Entry Qualifier")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addBoolean("usefvg", "Use FVG", "Enable fair value gap filter", true)
    indicator.parameters:addInteger("fvglookback", "FVG Lookback", "Bars to scan for fair value gaps", 20)
    indicator.parameters:addInteger("fvgexpire", "FVG Expire", "Bars before a fair value gap expires", 10)
    indicator.parameters:addDouble("fvgminatra", "FVG Min ATR", "Minimum ATR multiple for fair value gap size", 1.0)
    indicator.parameters:addDouble("fvgminatraP", "FVG Min ATR Percent", "Minimum ATR ratio percent threshold for fair value gap size", 100.0)
    indicator.parameters:addString("retestmode", "Retest Mode", "Retest mode selector", "close")
    indicator.parameters:addDouble("retbufa", "Retest Buffer ATR", "Retest buffer in ATR units", 0.1)
    indicator.parameters:addDouble("retbufaP", "Retest Buffer ATR Percent", "Retest buffer ATR percent", 10.0)
    indicator.parameters:addInteger("entryexp", "Entry Expire", "Bars before entry signal expires", 3)
    indicator.parameters:addBoolean("usebluelights", "Use Blue Lights", "Enable blue lights gating", true)
    indicator.parameters:addInteger("reactbars", "React Bars", "Maximum bars allowed for reaction", 2)
    indicator.parameters:addBoolean("requirereclaimb2", "Require Reclaim B2", "Require reclaim confirmation on blue light stage two", false)
    indicator.parameters:addBoolean("enablerejectb2", "Enable Reject B2", "Enable rejection filter on blue light stage two", true)
    indicator.parameters:addDouble("rejectwickmin", "Reject Wick Min", "Minimum wick ratio for rejection filter", 0.5)
    indicator.parameters:addDouble("rejectbodymax", "Reject Body Max", "Maximum body ratio for rejection filter", 0.5)
    indicator.parameters:addInteger("cdblue1", "Cooldown Blue 1", "Cooldown bars for blue light stage one", 0)
    indicator.parameters:addInteger("cdblue2", "Cooldown Blue 2", "Cooldown bars for blue light stage two", 0)
    indicator.parameters:addInteger("cdblue3", "Cooldown Blue 3", "Cooldown bars for blue light stage three", 0)
    indicator.parameters:addBoolean("reqema20b3", "Require EMA20 B3", "Require EMA20 alignment for blue light stage three", false)
    indicator.parameters:addBoolean("debug", "Debug", "Enable debug traces", false)
end

local source = nil
local first = nil
local T = {}

local function trace(message)
    if not T.debug then
        return
    end

    local text = "[SB_Entry_Qualifier] " .. tostring(message)
    if terminal ~= nil and terminal:alertMessage ~= nil then
        terminal:alertMessage(text, core.now())
    elseif core ~= nil and core.host ~= nil and core.host:trace ~= nil then
        core.host:trace(text)
    end
end

local function getParam(id, defaultValue)
    local value = instance.parameters[id]
    if value == nil then
        trace("missing parameter '" .. tostring(id) .. "', fallback to " .. tostring(defaultValue))
        return defaultValue
    end
    return value
end

function Prepare(nameOnly)
    source = instance.source
    first = source:first()

    T.debug = instance.parameters.debug == true
    T.usefvg = getParam("usefvg", true)
    T.fvglookback = getParam("fvglookback", 20)
    T.fvgexpire = getParam("fvgexpire", 10)
    T.fvgminatra = getParam("fvgminatra", 1.0)
    T.fvgminatraP = getParam("fvgminatraP", 100.0)
    T.retestmode = getParam("retestmode", "close")
    T.retbufa = getParam("retbufa", 0.1)
    T.retbufaP = getParam("retbufaP", 10.0)
    T.entryexp = getParam("entryexp", 3)
    T.usebluelights = getParam("usebluelights", true)
    T.reactbars = getParam("reactbars", 2)
    T.requirereclaimb2 = getParam("requirereclaimb2", false)
    T.enablerejectb2 = getParam("enablerejectb2", true)
    T.rejectwickmin = getParam("rejectwickmin", 0.5)
    T.rejectbodymax = getParam("rejectbodymax", 0.5)
    T.cdblue1 = getParam("cdblue1", 0)
    T.cdblue2 = getParam("cdblue2", 0)
    T.cdblue3 = getParam("cdblue3", 0)
    T.reqema20b3 = getParam("reqema20b3", false)

    instance:name(profile:id() .. "(" .. source:name() .. ")")
end

function Update(period, mode)
    if period < first then
        return
    end
end

function ReleaseInstance()
end

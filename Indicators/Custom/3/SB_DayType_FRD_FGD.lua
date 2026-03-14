local FONT_WEEKDAY = 10
local FONT_DAYTYPE = 11
local FONT_DEBUG = 12
local PEN_NEUTRAL = 20
local PEN_RECT_HIGH = 21
local PEN_RECT_LOW = 22
local PEN_DAY_DIVIDER = 23
local PEN_WEEKEND_DAY_DIVIDER = 24

local S = {source=nil, first=nil, d1=nil, m15=nil, day_cache={}, day_cache_meta={}, dayMarks={}, lastFullAuditDayKey=nil, symmetryAudit=nil, draw={initialized=false, weekdayFont=FONT_WEEKDAY, dayTypeFont=FONT_DAYTYPE, debugFont=FONT_DEBUG, neutralPen=PEN_NEUTRAL, rectHighPen=PEN_RECT_HIGH, rectLowPen=PEN_RECT_LOW, dayDividerPen=PEN_DAY_DIVIDER, weekendDayDividerPen=PEN_WEEKEND_DAY_DIVIDER, refreshThrottleMs=300, lastRefreshClockMs=0, lastRefreshDateKey=nil, inRefreshRequest=false}}
local T = {}

function Init()
    indicator:name("SB DayType FRD FGD")
    indicator:description("Day-level Pump/Dump + FRD/FGD event/trade-day definitions")
    indicator:requiredSource(core.Bar)
    indicator:type(core.Indicator)

    indicator.parameters:addInteger("rectangle_lookback_bars", "Rectangle Lookback Bars", "", 8)
    indicator.parameters:addInteger("rectangle_min_contained_closes", "Rectangle Min Contained Closes", "", 6)
    indicator.parameters:addDouble("max_rectangle_height_atr", "Max Rectangle Height ATR", "", 1.2)
    indicator.parameters:addDouble("atr_mult", "Pump/Dump ATR Mult", "", 1.0)
    indicator.parameters:addInteger("dayatrlen", "Day ATR Length", "", 14)
    indicator.parameters:addInteger("analysislookbackdays", "Analysis Lookback Trading Days", "", 7)
    indicator.parameters:addBoolean("enablequality", "Enable Quality Filter", "", true)
    indicator.parameters:addDouble("impulseAtrMult", "Impulse ATR Mult", "", 1.3)
    indicator.parameters:addDouble("impulseCloseExtreme", "Impulse Close Extreme", "", 0.7)
    indicator.parameters:addDouble("impulseBodyRatioMin", "Impulse Body Ratio Min", "", 0.5)
    indicator.parameters:addDouble("eventAtrMult", "Event ATR Mult", "", 0.6)
    indicator.parameters:addDouble("eventCloseExtreme", "Event Close Extreme", "", 0.7)
    indicator.parameters:addDouble("reclaimRatioMin", "Reclaim Ratio Min", "", 0.5)
    indicator.parameters:addBoolean("reportdailyonly", "Report Daily Only (first bar)", "", true)
    indicator.parameters:addInteger("qualityscoremin", "Quality Min Score For +", "", 4)
    indicator.parameters:addBoolean("showqualityaudit", "Show Quality Audit", "", false)
    indicator.parameters:addBoolean("showauditpanel", "Show Audit Panel", "", false)
    indicator.parameters:addInteger("auditpanellookback", "Audit Panel Lookback Days", "", 8)
    indicator.parameters:addBoolean("fullaudit", "Full Audit Trace", "", false)
    indicator.parameters:addInteger("auditlookbackdays", "Full Audit Lookback Days", "", 30)
    indicator.parameters:addBoolean("ShowWeekdayLabels", "Show Weekday Labels", "", true)
    indicator.parameters:addBoolean("ShowDayTypeLabels", "Show DayType Labels", "", true)
    indicator.parameters:addBoolean("ShowNearMissLabels", "Show Near-Miss Labels", "", true)
    indicator.parameters:addBoolean("ShowNearMissReasons", "Show Near-Miss Reasons", "", true)
    indicator.parameters:addInteger("WeekdayFontSize", "Weekday Font Size", "", 10)
    indicator.parameters:addInteger("DayTypeFontSize", "DayType Font Size", "", 10)
    indicator.parameters:addColor("WeekdayTextColor", "Weekday Text Color", "", core.rgb(180, 180, 180))
    indicator.parameters:addColor("FRDTextColor", "FRD Text Color", "", core.rgb(220, 20, 60))
    indicator.parameters:addColor("FGDTextColor", "FGD Text Color", "", core.rgb(0, 180, 0))
    indicator.parameters:addColor("FRDPlusColor", "FRD+ Text Color", "", core.rgb(255, 64, 64))
    indicator.parameters:addColor("FGDPlusColor", "FGD+ Text Color", "", core.rgb(0, 230, 140))
    indicator.parameters:addColor("TradeDayTextColor", "Trade Day Text Color", "", core.rgb(255, 200, 0))
    indicator.parameters:addColor("InactiveTextColor", "Inactive Text Color", "", core.rgb(120, 120, 120))
    indicator.parameters:addColor("RectangleHighDebugColor", "Rectangle High Debug Color", "", core.rgb(255, 255, 255))
    indicator.parameters:addColor("RectangleLowDebugColor", "Rectangle Low Debug Color", "", core.rgb(135, 206, 250))
    indicator.parameters:addBoolean("ShowDayDivider", "Show Day Divider", "", true)
    indicator.parameters:addColor("DayDividerColor", "Day Divider Color", "", core.rgb(120, 120, 120))
    indicator.parameters:addInteger("DayDividerWidth", "Day Divider Width", "", 1)
    indicator.parameters:addColor("WeekendDayDividerColor", "Weekend Day Divider Color", "", core.rgb(90, 90, 90))
    indicator.parameters:addInteger("WeekendDayDividerWidth", "Weekend Day Divider Width", "", 1)
    indicator.parameters:addBoolean("debug", "Debug", "", false)
end

local function safe_method(obj, name, ...)
    if obj == nil then return false, nil end
    local fn = obj[name]
    if type(fn) ~= "function" then return false, nil end
    local ok, result = pcall(fn, obj, ...)
    if not ok then return false, nil end
    return true, result
end

local function safe_value(obj, name, ...)
    local ok, result = safe_method(obj, name, ...)
    if ok then return result end
    return nil
end

local function debug_output(msg)
    if instance == nil or instance.parameters == nil or not instance.parameters.debug or msg == nil then return end
    if core == nil or core.host == nil then return end
    local text = "[SB_DayType_FRD_FGD] " .. tostring(msg)
    local ok = safe_method(core.host, "trace", text)
    if ok then return end
    safe_method(core.host, "execute", "alertMessage", text)
end

local function now_clock_millis()
    if core ~= nil and core.host ~= nil then
        local serverTime = safe_value(core.host, "execute", "getServerTime")
        if type(serverTime) == "number" then
            return math.floor(serverTime * 24 * 60 * 60 * 1000)
        end
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return math.floor(os.clock() * 1000)
    end
    return 0
end

local function should_force_refresh_for_active_day(dayRecord)
    if dayRecord == nil or dayRecord.dateKey == nil or S.d1 == nil then return false end
    local lastIdx = S.d1:size() - 1
    if lastIdx < S.d1:first() then return false end
    local lastTs = S.d1:date(lastIdx)
    if lastTs == nil then return false end
    local lastDateKey = math.floor(lastTs)
    return dayRecord.dateKey == lastDateKey
end

local function day_ohlc_signature(dayRecord)
    if dayRecord == nil then return nil end

    local o = tonumber(dayRecord.eventOpen)
    local h = tonumber(dayRecord.eventHigh)
    local l = tonumber(dayRecord.eventLow)
    local c = tonumber(dayRecord.eventClose)
    local dateKey = tonumber(dayRecord.dateKey)

    if dateKey == nil or o == nil or h == nil or l == nil or c == nil then
        return nil
    end

    return string.format("%d|%.10f|%.10f|%.10f|%.10f", dateKey, o, h, l, c)
end

local function request_owner_draw_refresh(period, dayRecord)
    if instance == nil or instance.parameters == nil then return end
    if not instance.parameters.debug and not instance.parameters.ShowDayTypeLabels then return end

    if S.draw.inRefreshRequest then
        if instance.parameters.debug then
            debug_output("refresh skipped (reentrant)")
        end
        return
    end

    local d = dayRecord
    local isNewDay = IsNewTradingDay(period)
    local dayChanged = d ~= nil and d.dateKey ~= nil and d.dateKey ~= S.draw.lastRefreshDateKey
    local currDateKey = d ~= nil and d.dateKey or nil
    local currOhlcSig = day_ohlc_signature(d)
    local sameSeenDay = currDateKey ~= nil and currDateKey == S.draw.lastSeenDateKey
    local dayRecalculated = sameSeenDay and currOhlcSig ~= nil and currOhlcSig ~= S.draw.lastSeenOhlcSig

    S.draw.lastSeenDateKey = currDateKey
    S.draw.lastSeenOhlcSig = currOhlcSig

    local nowMs = now_clock_millis()
    local throttleMs = tonumber(S.draw.refreshThrottleMs) or 300
    local throttledReady = (nowMs - (S.draw.lastRefreshClockMs or 0)) >= throttleMs
    local forceRefresh = should_force_refresh_for_active_day(d)
    if not forceRefresh and not isNewDay and not dayChanged and not throttledReady then return end

    -- ownerDrawn refresh: owner-drawn labels rely on Draw(), so Update() should proactively request repaint/invalidate.
    local requested = false
    local ok = nil
    S.draw.inRefreshRequest = true
    if core ~= nil and core.host ~= nil then
        ok = safe_method(core.host, "execute", "invalidate")
        if ok then requested = true end
    end
    if not requested and core ~= nil and core.host ~= nil then
        ok = safe_method(core.host, "execute", "repaint")
        if ok then requested = true end
    end

    S.draw.inRefreshRequest = false

    if eventDriven and not requested then
        S.draw.pendingForcedRefresh = true
    elseif requested then
        S.draw.pendingForcedRefresh = false
    end

    if requested then
        S.draw.lastRefreshClockMs = nowMs
        if d ~= nil then
            S.draw.lastRefreshDateKey = d.dateKey
        end
        if instance.parameters.debug then
            debug_output(string.format(
                "refresh requested (invalidate/repaint) newDay=%s dayChanged=%s throttled=%s force=%s",
                tostring(isNewDay), tostring(dayChanged), tostring(throttledReady), tostring(forceRefresh)
            ))
        end
    elseif instance.parameters.debug then
        debug_output(string.format(
            "refresh failed newDay=%s dayChanged=%s throttled=%s force=%s",
            tostring(isNewDay), tostring(dayChanged), tostring(throttledReady), tostring(forceRefresh)
        ))
    end
end

local function safe_div(num, den)
    local n = tonumber(num)
    local d = tonumber(den)
    if n == nil or d == nil or d == 0 then return 0 end
    return n / d
end

local function clamp_positive(v, fallback)
    local n = tonumber(v)
    if n == nil or n <= 0 then return fallback end
    return math.floor(n)
end

local function get_analysis_first_day_idx()
    if S.d1 == nil then return nil end
    local lookback = math.max(1, clamp_positive(instance.parameters.analysislookbackdays, 7))
    local last = S.d1:size() - 1
    return math.max(S.d1:first() + 1, last - lookback + 1)
end

local function is_in_analysis_window(day_idx)
    if day_idx == nil then return false end
    local firstDayIdx = get_analysis_first_day_idx()
    if firstDayIdx == nil then return false end
    return day_idx >= firstDayIdx
end

local function weekday_label_from_ts(ts)
    if ts == nil then return "" end
    local t = nil
    if core ~= nil and type(core.dateToTable) == "function" then
        local ok, result = pcall(core.dateToTable, ts)
        if ok then t = result end
    end
    if type(t) == "table" and t.wday ~= nil then
        local names = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
        return names[t.wday] or ""
    end
    return ""
end

function IsNewTradingDay(period)
    if S.source == nil or period == nil then return false end
    local ts = S.source:date(period)
    if ts == nil then return false end
    if period <= (S.first or 0) then return true end

    local prev_ts = S.source:date(period - 1)
    if prev_ts == nil then return true end
    return math.floor(ts) ~= math.floor(prev_ts)
end

function GetWeekdayLabel(period)
    if S.source == nil or period == nil then return "" end
    return weekday_label_from_ts(S.source:date(period))
end

function GetDayTypeLabels(period, dayRecord)
    if period == nil or dayRecord == nil then return {} end
    local rec = dayRecord

    local function join_reason(parts)
        if parts == nil or #parts == 0 then return nil end
        local text = parts[1]
        for i = 2, #parts do
            text = text .. "/" .. parts[i]
        end
        return text
    end

    local function near_miss_reason(prefix)
        if not instance.parameters.ShowNearMissReasons then return prefix end
        if rec.failReasons == nil then return prefix end

        local reasons = {}
        if prefix == "FRD?" then
            local frdBasic = rec.failReasons.basic ~= nil and rec.failReasons.basic.frd or nil
            local frdQualified = rec.failReasons.qualified ~= nil and rec.failReasons.qualified.frd or nil
            if frdBasic ~= nil and frdBasic.eventRangeFail then reasons[#reasons + 1] = "Range" end
            if frdBasic ~= nil and frdBasic.eventClvFail then reasons[#reasons + 1] = "CLV" end
            if frdQualified ~= nil and frdQualified.reclaimFail then reasons[#reasons + 1] = "Reclaim" end
            if frdQualified ~= nil and frdQualified.qualityFail then reasons[#reasons + 1] = "Quality" end
        elseif prefix == "FGD?" then
            local fgdBasic = rec.failReasons.basic ~= nil and rec.failReasons.basic.fgd or nil
            local fgdQualified = rec.failReasons.qualified ~= nil and rec.failReasons.qualified.fgd or nil
            if fgdBasic ~= nil and fgdBasic.eventRangeFail then reasons[#reasons + 1] = "Range" end
            if fgdBasic ~= nil and fgdBasic.eventClvFail then reasons[#reasons + 1] = "CLV" end
            if fgdQualified ~= nil and fgdQualified.reclaimFail then reasons[#reasons + 1] = "Reclaim" end
            if fgdQualified ~= nil and fgdQualified.qualityFail then reasons[#reasons + 1] = "Quality" end
        end

        local reasonText = join_reason(reasons)
        if reasonText == nil then return prefix end
        return string.format("%s(%s)", prefix, reasonText)
    end

    local labels = {}
    local isFrdEvent = rec.isFrd or rec.is_frd_event_day
    local isFgdEvent = rec.isFgd or rec.is_fgd_event_day
    local showProvisionalTradeDay = rec.isActiveDay and rec.prevWasEvent

    if showProvisionalTradeDay then
        labels[#labels + 1] = "Trade Day"
    elseif isFgdEvent then
        labels[#labels + 1] = rec.isHighQualityFgd and "FGD+" or "FGD"
    elseif isFrdEvent then
        labels[#labels + 1] = rec.isHighQualityFrd and "FRD+" or "FRD"
    elseif rec.isTradeDay then
        labels[#labels + 1] = "Trade Day"
    elseif instance.parameters.ShowNearMissLabels and rec.nearMissFrd then
        labels[#labels + 1] = near_miss_reason("FRD?")
    elseif instance.parameters.ShowNearMissLabels and rec.nearMissFgd then
        labels[#labels + 1] = near_miss_reason("FGD?")
    end

    return labels
end

local function get_day_mark_by_idx(day_idx)
    if S.d1 == nil or day_idx == nil then return nil end
    local ts = S.d1:date(day_idx)
    if ts == nil then return nil end
    local dateKey = math.floor(ts)
    if dateKey == nil then return nil end
    return S.dayMarks[dateKey]
end

local build_day_record

local function get_or_build_day_mark(day_idx)
    if day_idx == nil then return nil end
    local rec = get_day_mark_by_idx(day_idx)
    if rec ~= nil then return rec end
    return build_day_record(day_idx)
end

local function build_audit_lines(day_idx, dayRecord)
    local rec = dayRecord or get_day_mark_by_idx(day_idx)
    if rec == nil then return {} end
    if not instance.parameters.debug then return {} end

    if rec.isTradeDay then
        return {"From:" .. tostring(rec.tradeFromRule or "N/A")}
    end

    if not (rec.isFrd or rec.isFgd or rec.nearMissFrd or rec.nearMissFgd) then return {} end

    local prevText = rec.prevIsPump and "Pump" or (rec.prevIsDump and "Dump" or "Neutral")
    local eventText = rec.eventDown and "Down" or (rec.eventUp and "Up" or "Flat")
    local ruleText = rec.isFrd and "FRD" or (rec.isFgd and "FGD" or "Near")
    local lines = {"Prev:" .. prevText, "Event:" .. eventText, "Rule:" .. ruleText, string.format("Q:%d(%s)", tonumber(rec.qualityScore) or 0, rec.qualityGrade or "")}
    if rec.nearMissBasicFrd then lines[#lines + 1] = "Near FRD(Basic)" end
    if rec.nearMissQualifiedFrd then lines[#lines + 1] = "Near FRD(+)" end
    if rec.nearMissBasicFgd then lines[#lines + 1] = "Near FGD(Basic)" end
    if rec.nearMissQualifiedFgd then lines[#lines + 1] = "Near FGD(+)" end
    return lines
end

local function build_audit_panel_lines(lastDayIdx)
    if not instance.parameters.debug or not instance.parameters.showauditpanel then return {} end
    if lastDayIdx == nil or S.d1 == nil then return {} end

    local lookback = math.max(1, clamp_positive(instance.parameters.auditpanellookback, 8))
    local first = math.max(S.d1:first() + 2, lastDayIdx - lookback + 1)
    local lines = {}
    local yn = function(v) return v and "Y" or "N" end
    for i = first, lastDayIdx do
        local rec = get_day_mark_by_idx(i)
        if rec ~= nil and rec.dateLabel ~= nil then
            lines[#lines + 1] = rec.dateLabel
            lines[#lines + 1] = string.format("PrevPump=%s PrevDump=%s", yn(rec.prevIsPump), yn(rec.prevIsDump))
            lines[#lines + 1] = string.format("EventUp=%s EventDown=%s", yn(rec.eventUp), yn(rec.eventDown))
            lines[#lines + 1] = string.format("FRD=%s FGD=%s", yn(rec.isFrd), yn(rec.isFgd))
            if rec.isTradeDay then
                lines[#lines + 1] = string.format("TradeDay=Y (from %s)", tostring(rec.tradeFromRule or "N/A"))
            else
                lines[#lines + 1] = "TradeDay=N"
            end
            lines[#lines + 1] = string.format("Q=%d(%s)", tonumber(rec.qualityScore) or 0, rec.qualityGrade or "")
            lines[#lines + 1] = ""
        end
    end
    return lines
end

local function yn(v)
    return v and "Y" or "N"
end

local function build_symmetry_rule_spec()
    return {
        FRD = {
            gates = {
                atr = {
                    name = "ATR gate",
                    expression = "eventRange >= eventAtr * eventAtrMult",
                    operator = ">=",
                    lhs = "eventRange",
                    rhs = "eventAtr * eventAtrMult",
                    thresholdSource = "eventAtrMult"
                },
                clv = {
                    name = "CLV gate",
                    expression = "eventClvLowPass",
                    operator = "<=",
                    lhs = "eventClv",
                    rhs = "1 - eventCloseExtreme",
                    thresholdSource = "eventCloseExtreme"
                },
                reclaim = {
                    name = "reclaim gate",
                    expression = "reclaimRatioFrd >= reclaimRatioMin",
                    operator = ">=",
                    lhs = "reclaimRatioFrd",
                    rhs = "reclaimRatioMin",
                    thresholdSource = "reclaimRatioMin"
                }
            },
            qualityScore = {
                {key = "prevRangePass", weight = 1},
                {key = "prevClvHighPass", weight = 1},
                {key = "prevBodyRatioPass", weight = 1},
                {key = "eventRangePass", weight = 1},
                {key = "eventClvLowPass", weight = 1},
                {key = "reclaimPassFrd", weight = 1}
            }
        },
        FGD = {
            gates = {
                atr = {
                    name = "ATR gate",
                    expression = "eventRange >= eventAtr * eventAtrMult",
                    operator = ">=",
                    lhs = "eventRange",
                    rhs = "eventAtr * eventAtrMult",
                    thresholdSource = "eventAtrMult"
                },
                clv = {
                    name = "CLV gate",
                    expression = "eventClvHighPass",
                    operator = ">=",
                    lhs = "eventClv",
                    rhs = "eventCloseExtreme",
                    thresholdSource = "eventCloseExtreme"
                },
                reclaim = {
                    name = "reclaim gate",
                    expression = "reclaimRatioFgd >= reclaimRatioMin",
                    operator = ">=",
                    lhs = "reclaimRatioFgd",
                    rhs = "reclaimRatioMin",
                    thresholdSource = "reclaimRatioMin"
                }
            },
            qualityScore = {
                {key = "prevRangePass", weight = 1},
                {key = "prevClvLowPass", weight = 1},
                {key = "prevBodyRatioPass", weight = 1},
                {key = "eventRangePass", weight = 1},
                {key = "eventClvHighPass", weight = 1},
                {key = "reclaimPassFgd", weight = 1}
            }
        }
    }
end

local function auditSymmetry()
    local spec = build_symmetry_rule_spec()
    local frd = spec.FRD or {}
    local fgd = spec.FGD or {}
    local frdGates = frd.gates or {}
    local fgdGates = fgd.gates or {}

    local mismatchKeys = {}
    local function add_mismatch(key, detail)
        mismatchKeys[#mismatchKeys + 1] = {key = key, detail = detail}
    end

    local gateKeys = {"atr", "clv", "reclaim"}
    for _, gateKey in ipairs(gateKeys) do
        local frdGate = frdGates[gateKey]
        local fgdGate = fgdGates[gateKey]
        if frdGate == nil or fgdGate == nil then
            add_mismatch("gate." .. gateKey .. ".missing", "missing gate definition")
        else
            if frdGate.name ~= fgdGate.name then
                add_mismatch("gate." .. gateKey .. ".name", string.format("FRD=%s FGD=%s", tostring(frdGate.name), tostring(fgdGate.name)))
            end
            if frdGate.thresholdSource ~= fgdGate.thresholdSource then
                add_mismatch("gate." .. gateKey .. ".thresholdSource", string.format("FRD=%s FGD=%s", tostring(frdGate.thresholdSource), tostring(fgdGate.thresholdSource)))
            end
            if gateKey == "atr" then
                if frdGate.operator ~= fgdGate.operator or frdGate.lhs ~= fgdGate.lhs or frdGate.rhs ~= fgdGate.rhs then
                    add_mismatch("gate.atr.expression", string.format("FRD=%s %s %s FGD=%s %s %s",
                        tostring(frdGate.lhs), tostring(frdGate.operator), tostring(frdGate.rhs),
                        tostring(fgdGate.lhs), tostring(fgdGate.operator), tostring(fgdGate.rhs)))
                end
            elseif gateKey == "clv" then
                local mirrored = (frdGate.operator == "<=" and fgdGate.operator == ">=")
                    and (frdGate.lhs == fgdGate.lhs)
                    and (frdGate.thresholdSource == fgdGate.thresholdSource)
                if not mirrored then
                    add_mismatch("gate.clv.direction", string.format("FRD=%s %s %s FGD=%s %s %s",
                        tostring(frdGate.lhs), tostring(frdGate.operator), tostring(frdGate.rhs),
                        tostring(fgdGate.lhs), tostring(fgdGate.operator), tostring(fgdGate.rhs)))
                end
            elseif gateKey == "reclaim" then
                local mirrored = (frdGate.operator == fgdGate.operator)
                    and (frdGate.rhs == fgdGate.rhs)
                    and (frdGate.lhs ~= fgdGate.lhs)
                if not mirrored then
                    add_mismatch("gate.reclaim.direction", string.format("FRD=%s %s %s FGD=%s %s %s",
                        tostring(frdGate.lhs), tostring(frdGate.operator), tostring(frdGate.rhs),
                        tostring(fgdGate.lhs), tostring(fgdGate.operator), tostring(fgdGate.rhs)))
                end
            end
        end
    end

    local frdScore = frd.qualityScore or {}
    local fgdScore = fgd.qualityScore or {}
    if #frdScore ~= #fgdScore then
        add_mismatch("qualityScore.length", string.format("FRD=%d FGD=%d", #frdScore, #fgdScore))
    else
        local expectedPairs = {
            prevRangePass = "prevRangePass",
            prevClvHighPass = "prevClvLowPass",
            prevBodyRatioPass = "prevBodyRatioPass",
            eventRangePass = "eventRangePass",
            eventClvLowPass = "eventClvHighPass",
            reclaimPassFrd = "reclaimPassFgd"
        }
        for idx = 1, #frdScore do
            local frdItem = frdScore[idx]
            local fgdItem = fgdScore[idx]
            if frdItem == nil or fgdItem == nil then
                add_mismatch("qualityScore.item." .. idx, "missing quality score item")
            else
                local expectedKey = expectedPairs[frdItem.key]
                if expectedKey ~= fgdItem.key then
                    add_mismatch("qualityScore.item." .. idx .. ".key", string.format("FRD=%s expectedFGD=%s actualFGD=%s",
                        tostring(frdItem.key), tostring(expectedKey), tostring(fgdItem.key)))
                end
                if frdItem.weight ~= fgdItem.weight then
                    add_mismatch("qualityScore.item." .. idx .. ".weight", string.format("FRD=%s FGD=%s",
                        tostring(frdItem.weight), tostring(fgdItem.weight)))
                end
            end
        end
    end

    local audit = {
        ruleSpec = spec,
        gateKeys = gateKeys,
        mismatchKeys = mismatchKeys,
        atrThresholdSymmetric = true,
        clvDirectionSymmetric = true,
        reclaimSymmetric = true,
        scoreSymmetric = true
    }

    for _, mismatch in ipairs(mismatchKeys) do
        if mismatch.key ~= nil then
            if string.find(mismatch.key, "gate%.atr") == 1 then audit.atrThresholdSymmetric = false end
            if string.find(mismatch.key, "gate%.clv") == 1 then audit.clvDirectionSymmetric = false end
            if string.find(mismatch.key, "gate%.reclaim") == 1 then audit.reclaimSymmetric = false end
            if string.find(mismatch.key, "qualityScore") == 1 then audit.scoreSymmetric = false end
        end
    end

    audit.ok = (#mismatchKeys == 0)
    S.symmetryAudit = audit

    if instance.parameters.debug then
        if audit.ok then
            debug_output("AUDIT OK: FRD/FGD rule structures are symmetric")
        else
            debug_output("AUDIT WARNING: FRD/FGD asymmetry detected in rule structures")
            for _, mismatch in ipairs(mismatchKeys) do
                debug_output(string.format("AUDIT DIFF %s -> %s", tostring(mismatch.key), tostring(mismatch.detail)))
            end
        end
    end
    return audit
end

local function audit_symmetry()
    return auditSymmetry()
end

local function build_audit_stats(lastDayIdx, lookback)
    local stats = {
        totalBasicFgd = 0,
        totalBasicFrd = 0,
        totalQualifiedFgd = 0,
        totalQualifiedFrd = 0,
        totalHighQualityFgd = 0,
        totalHighQualityFrd = 0,
        failPrevRangeCount = 0,
        failPrevClvCount = 0,
        failEventRangeCount = 0,
        failEventClvCount = 0,
        failReclaimCount = 0
    }
    if S.d1 == nil or lastDayIdx == nil then return stats end

    local first = math.max(S.d1:first() + 2, lastDayIdx - lookback + 1)
    for i = first, lastDayIdx do
        local rec = build_day_record(i)
        if rec ~= nil then
            if rec.basicFgd then stats.totalBasicFgd = stats.totalBasicFgd + 1 end
            if rec.basicFrd then stats.totalBasicFrd = stats.totalBasicFrd + 1 end
            if rec.isFgd then stats.totalQualifiedFgd = stats.totalQualifiedFgd + 1 end
            if rec.isFrd then stats.totalQualifiedFrd = stats.totalQualifiedFrd + 1 end
            if rec.isHighQualityFgd then stats.totalHighQualityFgd = stats.totalHighQualityFgd + 1 end
            if rec.isHighQualityFrd then stats.totalHighQualityFrd = stats.totalHighQualityFrd + 1 end

            if rec.basicFgd or rec.basicFrd then
                if not rec.prevRangePass then stats.failPrevRangeCount = stats.failPrevRangeCount + 1 end
                if not rec.prevClvPass then stats.failPrevClvCount = stats.failPrevClvCount + 1 end
                if not rec.eventRangePass then stats.failEventRangeCount = stats.failEventRangeCount + 1 end
                if not rec.eventClvPass then stats.failEventClvCount = stats.failEventClvCount + 1 end
                if not rec.reclaimPass then stats.failReclaimCount = stats.failReclaimCount + 1 end
            end
        end
    end
    return stats
end

local function emit_full_audit(lastDayIdx)
    if not instance.parameters.fullaudit or S.d1 == nil or lastDayIdx == nil then return end
    local lookback = math.max(1, clamp_positive(instance.parameters.auditlookbackdays, 30))
    local first = math.max(S.d1:first() + 2, lastDayIdx - lookback + 1)

    for i = first, lastDayIdx do
        local rec = build_day_record(i)
        if rec ~= nil then
            debug_output(rec.dateLabel)
            debug_output("PrevPump=" .. yn(rec.prevIsPump))
            debug_output("PrevDump=" .. yn(rec.prevIsDump))
            debug_output("EventUp=" .. yn(rec.eventUp))
            debug_output("EventDown=" .. yn(rec.eventDown))
            debug_output("BasicFRD=" .. yn(rec.basicFrd))
            debug_output("BasicFGD=" .. yn(rec.basicFgd))
            debug_output("QualifiedFRD=" .. yn(rec.isFrd))
            debug_output("QualifiedFGD=" .. yn(rec.isFgd))
            debug_output(string.format("Q=%d(%s)", tonumber(rec.qualityScore) or 0, rec.qualityGrade or ""))
            if rec.isTradeDay then
                debug_output(rec.dateLabel)
                debug_output("TradeDay=Y")
                debug_output("From=" .. tostring(rec.tradeFromRule or "N/A"))
            end
        end
    end

    local stats = build_audit_stats(lastDayIdx, lookback)
    debug_output(string.format(
        "AuditStats L=%d basic(FGD=%d,FRD=%d) qualified(FGD=%d,FRD=%d) HQ(FGD=%d,FRD=%d) fail(prevRange=%d,prevClv=%d,eventRange=%d,eventClv=%d,reclaim=%d)",
        lookback,
        stats.totalBasicFgd,
        stats.totalBasicFrd,
        stats.totalQualifiedFgd,
        stats.totalQualifiedFrd,
        stats.totalHighQualityFgd,
        stats.totalHighQualityFrd,
        stats.failPrevRangeCount,
        stats.failPrevClvCount,
        stats.failEventRangeCount,
        stats.failEventClvCount,
        stats.failReclaimCount
    ))
end

local function get_day_type_color(label)
    if label == "FRD+" then
        return instance.parameters.FRDPlusColor
    elseif label == "FGD+" then
        return instance.parameters.FGDPlusColor
    elseif label == "FRD" then
        return instance.parameters.FRDTextColor
    elseif label == "FGD" then
        return instance.parameters.FGDTextColor
    elseif label == "Trade Day" then
        return instance.parameters.TradeDayTextColor
    elseif string.sub(label, 1, 4) == "FRD?" then
        return instance.parameters.InactiveTextColor
    elseif string.sub(label, 1, 4) == "FGD?" then
        return instance.parameters.InactiveTextColor
    end
    return instance.parameters.InactiveTextColor
end

local function is_frd_fgd_label(label)
    if label == nil then return false end
    return label == "FRD" or label == "FRD+" or label == "FGD" or label == "FGD+"
end

local function draw_text(context, fontId, text, color, x, y)
    if context == nil or fontId == nil or text == nil or text == "" or x == nil or y == nil then return end

    local fontSize = clamp_positive(instance.parameters.DayTypeFontSize, 10)
    local fallbackW = math.max(1, #tostring(text) * fontSize)
    local fallbackH = math.max(1, fontSize)
    local okMeasure, w, h = pcall(function()
        return context:measureText(fontId, text, 0)
    end)

    if not okMeasure then
        w = fallbackW
        h = fallbackH
    end

    w = math.max(1, tonumber(w) or fallbackW)
    h = math.max(1, tonumber(h) or fallbackH)
    safe_method(context, "drawText", fontId, text, color, -1, x, y, x + w, y + h, 0)
end

local function get_x_for_time(context, ts)
    if context == nil or ts == nil then return nil end
    local x = safe_value(context, "positionOfDate", ts)
    if x ~= nil then return x end
    return safe_value(context, "positionOfTime", ts)
end

local function get_y_for_price(context, price)
    if context == nil or price == nil then return nil end
    local y = safe_value(context, "positionOfPrice", price)
    if y ~= nil then return y end
    local pt = safe_value(context, "pointOfPrice", price)
    if type(pt) == "table" then return pt.y end
    return nil
end

local function draw_line(context, penId, x1, y1, x2, y2)
    if context == nil or penId == nil or x1 == nil or y1 == nil or x2 == nil or y2 == nil then return end
    local ok = safe_method(context, "drawLine", penId, x1, y1, x2, y2)
    if not ok then
        safe_method(context, "drawLine", S.draw.neutralPen, x1, y1, x2, y2)
    end
end

local function measure_text(context, font, text)
    if context == nil or font == nil or text == nil then return nil, nil end
    local m = safe_method(context, "measureText", font, text)
    if type(m) == "table" then
        return m.width or m.cx or m.x, m.height or m.cy or m.y
    end
    return nil, nil
end

local function find_source_period_by_time(ts)
    if S.source == nil or ts == nil then return nil end
    local first = S.source:first()
    local last = S.source:size() - 1
    local found = nil
    for i = first, last do
        if S.source:date(i) <= ts then
            found = i
        else
            break
        end
    end
    return found
end

local function ensure_draw_resources(context)
    if S.draw.initialized then return end
    local weekdaySize = clamp_positive(instance.parameters.WeekdayFontSize, 10)
    local dayTypeSize = clamp_positive(instance.parameters.DayTypeFontSize, 10)
    local debugSize = math.max(8, clamp_positive(instance.parameters.DayTypeFontSize, 10) - 1)
    local weekdayPx = safe_value(context, "pointsToPixels", weekdaySize) or weekdaySize
    local dayTypePx = safe_value(context, "pointsToPixels", dayTypeSize) or dayTypeSize
    local debugPx = safe_value(context, "pointsToPixels", debugSize) or debugSize
    local penWidth = safe_value(context, "pointsToPixels", 1) or 1
    local dayDividerWidth = clamp_positive(instance.parameters.DayDividerWidth, 1)
    local dayDividerPenWidth = safe_value(context, "pointsToPixels", dayDividerWidth) or dayDividerWidth
    local weekendDividerWidth = clamp_positive(instance.parameters.WeekendDayDividerWidth, dayDividerWidth)
    local weekendDividerPenWidth = safe_value(context, "pointsToPixels", weekendDividerWidth) or weekendDividerWidth
    local solidStyle = safe_value(context, "convertPenStyle", core.LINE_SOLID) or core.LINE_SOLID

    local okWeekdayFont = safe_method(context, "createFont", FONT_WEEKDAY, "Arial", weekdayPx, weekdayPx, 0)
    local okDayTypeFont = safe_method(context, "createFont", FONT_DAYTYPE, "Arial", dayTypePx, dayTypePx, core.FONT_BOLD or 0)
    local okDebugFont = safe_method(context, "createFont", FONT_DEBUG, "Arial", debugPx, debugPx, 0)

    local okNeutralPen = safe_method(context, "createPen", PEN_NEUTRAL, solidStyle, penWidth, instance.parameters.InactiveTextColor)
    local okRectHighPen = safe_method(context, "createPen", PEN_RECT_HIGH, solidStyle, penWidth, instance.parameters.RectangleHighDebugColor)
    local okRectLowPen = safe_method(context, "createPen", PEN_RECT_LOW, solidStyle, penWidth, instance.parameters.RectangleLowDebugColor)
    local okDayDividerPen = safe_method(context, "createPen", PEN_DAY_DIVIDER, solidStyle, dayDividerPenWidth, instance.parameters.DayDividerColor)
    local okWeekendDayDividerPen = safe_method(context, "createPen", PEN_WEEKEND_DAY_DIVIDER, solidStyle, weekendDividerPenWidth, instance.parameters.WeekendDayDividerColor)

    if okDayDividerPen then
        S.draw.dayDividerPen = PEN_DAY_DIVIDER
    else
        S.draw.dayDividerPen = S.draw.neutralPen
    end

    if okWeekendDayDividerPen then
        S.draw.weekendDayDividerPen = PEN_WEEKEND_DAY_DIVIDER
    else
        S.draw.weekendDayDividerPen = S.draw.dayDividerPen
    end

    local fontsReady = okWeekdayFont and okDayTypeFont and okDebugFont
    local pensReady = okNeutralPen and okRectHighPen and okRectLowPen
    S.draw.initialized = fontsReady and pensReady

    if not S.draw.initialized then
        debug_output(string.format(
            "draw resource init failed (fonts: weekday=%s dayType=%s debug=%s; pens: neutral=%s rectHigh=%s rectLow=%s)",
            tostring(okWeekdayFont), tostring(okDayTypeFont), tostring(okDebugFont),
            tostring(okNeutralPen), tostring(okRectHighPen), tostring(okRectLowPen)
        ))
    end

    if not okDayDividerPen then
        debug_output("day divider pen init failed, fallback to neutral pen")
    end
    if not okWeekendDayDividerPen then
        debug_output("weekend day divider pen init failed, fallback to day divider pen")
    end
end

local function is_weekend_ts(ts)
    if ts == nil then return false end
    if core ~= nil and type(core.dateToTable) == "function" then
        local ok, t = pcall(core.dateToTable, ts)
        if ok and type(t) == "table" and t.wday ~= nil then
            return t.wday == 1 or t.wday == 7
        end
    end
    return false
end

local function getHistory(instrument, tf, isBid)
    local ok, h = pcall(function() return core.host:execute("getSyncHistory", instrument, tf, isBid, 0, 0) end)
    if ok then return h end
    return nil
end

local function find_history_index_by_time(history, ts)
    if history == nil or ts == nil then return nil end
    local i = history:first()
    local last = history:size() - 1
    local found = nil
    while i <= last do
        local d = history:date(i)
        if d <= ts then found = i else break end
        i = i + 1
    end
    return found
end

local function day_key(ts)
    if ts == nil then return nil end
    return math.floor(ts)
end

local function format_date_key(dateKey)
    if dateKey == nil then return "N/A" end
    local t = nil
    if core ~= nil and type(core.dateToTable) == "function" then
        local ok, result = pcall(core.dateToTable, dateKey)
        if ok then t = result end
    end
    if type(t) == "table" and t.year and t.month and t.day then
        return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
    end
    return tostring(dateKey)
end

local function is_weekend_timestamp(ts)
    if ts == nil or core == nil or type(core.dateToTable) ~= "function" then return false end
    local ok, t = pcall(core.dateToTable, ts)
    if not ok or type(t) ~= "table" then return false end
    return t.wday == 1 or t.wday == 7
end

local function find_prev_effective_trading_day_idx(day_idx)
    if S.d1 == nil or day_idx == nil then return nil end
    local first = S.d1:first()
    local idx = day_idx - 1
    while idx >= first do
        local ts = S.d1:date(idx)
        if ts ~= nil and not is_weekend_timestamp(ts) then
            return idx
        end
        idx = idx - 1
    end
    return nil
end

local function calc_atr(history, idx, len)
    if history == nil or idx == nil or len == nil or len <= 0 then return nil end
    local start = idx - len + 1
    if start < history:first() + 1 then return nil end

    local sum, count = 0, 0
    for i = start, idx do
        local h = history.high[i]
        local l = history.low[i]
        local c1 = history.close[i - 1]
        local tr = math.max(h - l, math.max(math.abs(h - c1), math.abs(l - c1)))
        sum = sum + tr
        count = count + 1
    end
    if count == 0 then return nil end
    return sum / count
end

local function evaluate_pump_dump(d1, day_idx)
    if d1 == nil or day_idx == nil then return nil end
    local prev = day_idx - 1
    if prev < d1:first() then return nil end

    local h, l, o, c = d1.high[day_idx], d1.low[day_idx], d1.open[day_idx], d1.close[day_idx]
    local ph, pl = d1.high[prev], d1.low[prev]
    local r = h - l
    if r <= 0 then
        return {
            is_pump_day = false,
            is_dump_day = false,
            daytype_bias = 0
        }
    end

    local inside = h <= ph and l >= pl
    local close_upper = c >= (l + r * 0.5)
    local close_lower = c <= (l + r * 0.5)

    local is_pump = (h > ph) and close_upper and (c > o) and (not inside)
    local is_dump = (l < pl) and close_lower and (c < o) and (not inside)

    return {
        is_pump_day = is_pump,
        is_dump_day = is_dump,
        daytype_bias = is_pump and 1 or (is_dump and -1 or 0)
    }
end

local function eval_rectangle(d1, m15, d1_idx)
    local lookback = math.max(1, instance.parameters.rectangle_lookback_bars)
    local min_contained = math.max(1, instance.parameters.rectangle_min_contained_closes)
    local max_height_atr = instance.parameters.max_rectangle_height_atr
    local dayatrlen = instance.parameters.dayatrlen

    if d1 == nil or m15 == nil or d1_idx == nil then
        return {valid=false, bar_count=0}
    end

    local target_day = day_key(d1:date(d1_idx))
    local bars = {}
    local day_ts = d1:date(d1_idx)
    local next_day_ts = d1_idx + 1 <= (d1:size() - 1) and d1:date(d1_idx + 1) or nil
    for i = m15:first(), m15:size() - 1 do
        local bar_ts = m15:date(i)
        local in_target_day = day_key(bar_ts) == target_day
        local before_next_day = next_day_ts == nil or bar_ts < next_day_ts
        if in_target_day and before_next_day and bar_ts <= day_ts + 0.99999 then
            bars[#bars + 1] = i
        end
    end

    if #bars < lookback then
        return {valid=false, bar_count=#bars}
    end

    local start_pos = #bars - lookback + 1
    local hi, lo = nil, nil
    for p = start_pos, #bars do
        local bi = bars[p]
        local bh = m15.high[bi]
        local bl = m15.low[bi]
        if hi == nil or bh > hi then hi = bh end
        if lo == nil or bl < lo then lo = bl end
    end

    local contained = 0
    for p = start_pos, #bars do
        local c = m15.close[bars[p]]
        if c >= lo and c <= hi then
            contained = contained + 1
        end
    end

    local height = (hi ~= nil and lo ~= nil) and (hi - lo) or nil
    local atr = calc_atr(d1, d1_idx, dayatrlen)
    local atr_ok = atr ~= nil and atr > 0 and height ~= nil and height <= atr * max_height_atr

    local last4_expanding = false
    if #bars >= 4 and height ~= nil and height > 0 then
        local a = bars[#bars - 3]
        local b = bars[#bars]
        local directional_move = math.abs(m15.close[b] - m15.open[a])
        last4_expanding = directional_move > (height * 0.8)
    end

    return {
        valid = atr_ok and (contained >= min_contained) and (not last4_expanding),
        high = hi,
        low = lo,
        height = height,
        bar_count = lookback,
        start_time = m15:date(bars[start_pos]),
        end_time = m15:date(bars[#bars]),
        contained = contained,
        near_close = true,
        rejected_by_expansion = last4_expanding,
        rejected_by_atr = not atr_ok,
        rejected_by_contained = contained < min_contained
    }
end

build_day_record = function(day_idx)
    if day_idx == nil or day_idx <= S.d1:first() + 1 then return nil end
    local lastIdx = S.d1:size() - 1
    local isActiveDay = day_idx == lastIdx
    local cachedRec = S.day_cache[day_idx]
    local cachedMeta = S.day_cache_meta[day_idx]

    if cachedRec ~= nil and not isActiveDay then
        return cachedRec
    end

    if cachedRec ~= nil and isActiveDay then
        local sameAsCache = cachedMeta ~= nil
            and cachedMeta.open == S.d1.open[day_idx]
            and cachedMeta.high == S.d1.high[day_idx]
            and cachedMeta.low == S.d1.low[day_idx]
            and cachedMeta.close == S.d1.close[day_idx]
            and cachedMeta.ts == S.d1:date(day_idx)
        if sameAsCache then
            return cachedRec
        end
        if instance.parameters.debug then
            debug_output(string.format("active day changed -> recalc date=%s", tostring(day_key(S.d1:date(day_idx)))))
        end
    end

    local rect = eval_rectangle(S.d1, S.m15, day_idx)
    local epsilon = 0.0000001
    local atrLen = math.max(1, clamp_positive(instance.parameters.dayatrlen, 14))
    local qualityScoreMin = math.max(1, clamp_positive(instance.parameters.qualityscoremin, 4))

    local impulseAtrMult = tonumber(instance.parameters.impulseAtrMult) or 1.3
    local impulseCloseExtreme = tonumber(instance.parameters.impulseCloseExtreme) or 0.7
    local impulseBodyRatioMin = tonumber(instance.parameters.impulseBodyRatioMin) or 0.5
    local eventAtrMult = tonumber(instance.parameters.eventAtrMult) or 0.6
    local eventCloseExtreme = tonumber(instance.parameters.eventCloseExtreme) or 0.7
    local reclaimRatioMin = tonumber(instance.parameters.reclaimRatioMin) or 0.5

    local prev_idx = find_prev_effective_trading_day_idx(day_idx)
    if prev_idx == nil then return nil end
    local eventOpen, eventHigh, eventLow, eventClose = S.d1.open[day_idx], S.d1.high[day_idx], S.d1.low[day_idx], S.d1.close[day_idx]
    local prevOpen, prevHigh, prevLow, prevClose = S.d1.open[prev_idx], S.d1.high[prev_idx], S.d1.low[prev_idx], S.d1.close[prev_idx]

    local prevRange = (prevHigh or 0) - (prevLow or 0)
    local prevAtr = calc_atr(S.d1, prev_idx, atrLen)
    local prevClv = (prevClose - prevLow) / math.max(prevRange, epsilon)
    local prevBody = math.abs(prevClose - prevOpen)
    local prevBodyRatio = prevBody / math.max(prevRange, epsilon)

    local eventRange = (eventHigh or 0) - (eventLow or 0)
    local eventAtr = calc_atr(S.d1, day_idx, atrLen)
    local eventClv = (eventClose - eventLow) / math.max(eventRange, epsilon)

    -- Layer A: Previous Day Impulse Classification
    local prevRangePass = prevAtr ~= nil and prevAtr > 0 and prevRange >= (prevAtr * impulseAtrMult)
    local prevClvHighPass = prevClv >= impulseCloseExtreme
    local prevClvLowPass = prevClv <= (1 - impulseCloseExtreme)
    local prevBodyRatioPass = prevBodyRatio >= impulseBodyRatioMin
    local prevIsPump = (prevClose > prevOpen) and prevRangePass and prevClvHighPass and prevBodyRatioPass
    local prevIsDump = (prevClose < prevOpen) and prevRangePass and prevClvLowPass and prevBodyRatioPass

    -- Layer B: Event Day Reversal Classification
    local eventUp = eventClose > eventOpen
    local eventDown = eventClose < eventOpen
    local eventRangePass = eventAtr ~= nil and eventAtr > 0 and eventRange >= (eventAtr * eventAtrMult)
    local eventClvHighPass = eventClv >= eventCloseExtreme
    local eventClvLowPass = eventClv <= (1 - eventCloseExtreme)

    local prevBodyHigh = math.max(prevOpen, prevClose)
    local prevBodyLow = math.min(prevOpen, prevClose)
    local prevBodySize = math.max(prevBodyHigh - prevBodyLow, epsilon)
    local reclaimRatioFgd = (eventClose - prevBodyLow) / prevBodySize
    local reclaimRatioFrd = (prevBodyHigh - eventClose) / prevBodySize
    local reclaimPassFgd = reclaimRatioFgd >= reclaimRatioMin
    local reclaimPassFrd = reclaimRatioFrd >= reclaimRatioMin

    local basicFgd = prevIsDump and eventUp and eventRangePass and eventClvHighPass
    local basicFrd = prevIsPump and eventDown and eventRangePass and eventClvLowPass

    local qualityScoreFgd = 0
    if prevRangePass then qualityScoreFgd = qualityScoreFgd + 1 end
    if prevClvLowPass then qualityScoreFgd = qualityScoreFgd + 1 end
    if prevBodyRatioPass then qualityScoreFgd = qualityScoreFgd + 1 end
    if eventRangePass then qualityScoreFgd = qualityScoreFgd + 1 end
    if eventClvHighPass then qualityScoreFgd = qualityScoreFgd + 1 end
    if reclaimPassFgd then qualityScoreFgd = qualityScoreFgd + 1 end

    local qualityScoreFrd = 0
    if prevRangePass then qualityScoreFrd = qualityScoreFrd + 1 end
    if prevClvHighPass then qualityScoreFrd = qualityScoreFrd + 1 end
    if prevBodyRatioPass then qualityScoreFrd = qualityScoreFrd + 1 end
    if eventRangePass then qualityScoreFrd = qualityScoreFrd + 1 end
    if eventClvLowPass then qualityScoreFrd = qualityScoreFrd + 1 end
    if reclaimPassFrd then qualityScoreFrd = qualityScoreFrd + 1 end

    local qualityGradeFgd = qualityScoreFgd >= 6 and "A" or (qualityScoreFgd >= 5 and "B" or (qualityScoreFgd >= 4 and "C" or ""))
    local qualityGradeFrd = qualityScoreFrd >= 6 and "A" or (qualityScoreFrd >= 5 and "B" or (qualityScoreFrd >= 4 and "C" or ""))

    -- Layer C: Qualified SB Event
    local qualifiedFgd = basicFgd and reclaimPassFgd and qualityScoreFgd >= qualityScoreMin
    local qualifiedFrd = basicFrd and reclaimPassFrd and qualityScoreFrd >= qualityScoreMin

    local isFgdEvent = basicFgd
    local isFrdEvent = basicFrd

    -- Layer D: Next Trading Day Trade Day (weekend/non-effective D1 rows are skipped)
    local prev_rec = prev_idx ~= nil and build_day_record(prev_idx) or nil
    local prevWasEvent = prev_rec ~= nil and (prev_rec.basicFrd or prev_rec.basicFgd)
    local isTradeDay = (not isFrdEvent) and (not isFgdEvent) and prevWasEvent
    local isFrdTradeCandidate = isTradeDay and prev_rec ~= nil and prev_rec.basicFrd
    local isFgdTradeCandidate = isTradeDay and prev_rec ~= nil and prev_rec.basicFgd
    local tradeFromRule = isFrdTradeCandidate and "FRD" or (isFgdTradeCandidate and "FGD" or nil)

    local nearMissBasicFrd = false
    local nearMissQualifiedFrd = false
    local nearMissBasicFgd = false
    local nearMissQualifiedFgd = false
    if prevIsPump and eventDown then
        -- Directionally-correct FRD days should still surface as near-miss even when
        -- more than one gate fails, so users can see why FRD wasn't confirmed.
        nearMissBasicFrd = (not basicFrd) and ((not eventRangePass) or (not eventClvLowPass))

        local qualifiedMissFrd = 0
        if not reclaimPassFrd then qualifiedMissFrd = qualifiedMissFrd + 1 end
        if qualityScoreFrd < qualityScoreMin then qualifiedMissFrd = qualifiedMissFrd + 1 end
        nearMissQualifiedFrd = basicFrd and (not qualifiedFrd) and (qualifiedMissFrd == 1)
    end
    if prevIsDump and eventUp then
        -- Directionally-correct FGD days should still surface as near-miss even when
        -- more than one gate fails, so users can see why FGD wasn't confirmed.
        nearMissBasicFgd = (not basicFgd) and ((not eventRangePass) or (not eventClvHighPass))

        local qualifiedMissFgd = 0
        if not reclaimPassFgd then qualifiedMissFgd = qualifiedMissFgd + 1 end
        if qualityScoreFgd < qualityScoreMin then qualifiedMissFgd = qualifiedMissFgd + 1 end
        nearMissQualifiedFgd = basicFgd and (not qualifiedFgd) and (qualifiedMissFgd == 1)
    end
    local nearMissFrd = nearMissBasicFrd or nearMissQualifiedFrd
    local nearMissFgd = nearMissBasicFgd or nearMissQualifiedFgd

    local rec = {
        sourceDate = S.d1:date(day_idx),
        dateKey = day_key(S.d1:date(day_idx)),
        prevDateKey = day_key(S.d1:date(prev_idx)),
        nextDateKey = day_idx + 1 <= S.d1:size() - 1 and day_key(S.d1:date(day_idx + 1)) or nil,
        dateLabel = format_date_key(day_key(S.d1:date(day_idx))),

        prevOpen = prevOpen, prevHigh = prevHigh, prevLow = prevLow, prevClose = prevClose,
        prevRange = prevRange, prevAtr = prevAtr, prevClv = prevClv, prevBodyRatio = prevBodyRatio,
        eventOpen = eventOpen, eventHigh = eventHigh, eventLow = eventLow, eventClose = eventClose,
        eventRange = eventRange, eventAtr = eventAtr, eventClv = eventClv,

        prevIsPump = prevIsPump, prevIsDump = prevIsDump,
        basicFrd = basicFrd, basicFgd = basicFgd,
        qualifiedFrd = qualifiedFrd, qualifiedFgd = qualifiedFgd,
        prevWasEvent = prevWasEvent,
        isActiveDay = isActiveDay,
        isTradeDay = isTradeDay,

        reclaimRatioFrd = reclaimRatioFrd, reclaimRatioFgd = reclaimRatioFgd,
        qualityScoreFrd = qualityScoreFrd, qualityScoreFgd = qualityScoreFgd,
        qualityGradeFrd = qualityGradeFrd, qualityGradeFgd = qualityGradeFgd,

        eventUp = eventUp, eventDown = eventDown,
        eventRangePass = eventRangePass, eventClvHighPass = eventClvHighPass, eventClvLowPass = eventClvLowPass,
        prevRangePass = prevRangePass, prevBodyRatioPass = prevBodyRatioPass, prevClvHighPass = prevClvHighPass, prevClvLowPass = prevClvLowPass,
        reclaimPassFrd = reclaimPassFrd, reclaimPassFgd = reclaimPassFgd,
        prevClvPass = (basicFrd and prevClvHighPass) or (basicFgd and prevClvLowPass) or false,
        reclaimPass = (basicFrd and reclaimPassFrd) or (basicFgd and reclaimPassFgd) or false,

        nearMissBasicFrd = nearMissBasicFrd, nearMissBasicFgd = nearMissBasicFgd,
        nearMissQualifiedFrd = nearMissQualifiedFrd, nearMissQualifiedFgd = nearMissQualifiedFgd,
        nearMissFrd = nearMissFrd, nearMissFgd = nearMissFgd,
        isFrd = isFrdEvent, isFgd = isFgdEvent,
        isHighQualityFrd = qualifiedFrd, isHighQualityFgd = qualifiedFgd,
        is_pump_day = prevIsPump, is_dump_day = prevIsDump,
        is_frd_event_day = isFrdEvent, is_fgd_event_day = isFgdEvent,
        is_frd_trade_day_candidate = isFrdTradeCandidate, is_fgd_trade_day_candidate = isFgdTradeCandidate,
        tradeFromRule = tradeFromRule,
        qualityScore = isFrdEvent and qualityScoreFrd or (isFgdEvent and qualityScoreFgd or 0),
        qualityGrade = isFrdEvent and qualityGradeFrd or (isFgdEvent and qualityGradeFgd or ""),

        has_valid_rectangle = rect.valid, rectangle_high = rect.high, rectangle_low = rect.low,
        rectangle_height = rect.height, rectangle_bar_count = rect.bar_count, rectangle_start_time = rect.start_time, rectangle_end_time = rect.end_time,
        daytype_bias = prevIsPump and 1 or (prevIsDump and -1 or 0),
        event_day_type = isFrdEvent and -1 or (isFgdEvent and 1 or 0),
        repeated_pump_score = prevIsPump and 1 or 0, repeated_dump_score = prevIsDump and 1 or 0, consolidation_score = rect.valid and 1 or 0, three_levels_score = 0,

        supersededByOpposite = false,

        failReasons = {
            basic = {
                prevRangeFail = not prevRangePass,
                prevClvFail = (prevClose > prevOpen and not prevClvHighPass) or (prevClose < prevOpen and not prevClvLowPass),
                prevBodyFail = not prevBodyRatioPass,
                frd = {
                    eventRangeFail = prevIsPump and eventDown and not eventRangePass,
                    eventClvFail = prevIsPump and eventDown and not eventClvLowPass
                },
                fgd = {
                    eventRangeFail = prevIsDump and eventUp and not eventRangePass,
                    eventClvFail = prevIsDump and eventUp and not eventClvHighPass
                }
            },
            qualified = {
                frd = {
                    reclaimFail = prevIsPump and eventDown and not reclaimPassFrd,
                    qualityFail = prevIsPump and eventDown and qualityScoreFrd < qualityScoreMin
                },
                fgd = {
                    reclaimFail = prevIsDump and eventUp and not reclaimPassFgd,
                    qualityFail = prevIsDump and eventUp and qualityScoreFgd < qualityScoreMin
                }
            }
        }
    }

    if prev_rec ~= nil then
        local supersededPrev = (isFrdEvent and prev_rec.isFgd) or (isFgdEvent and prev_rec.isFrd)
        if supersededPrev then
            prev_rec.supersededByOpposite = true
            if prev_rec.dateKey ~= nil then
                S.dayMarks[prev_rec.dateKey] = prev_rec
            end
        end
    end

    local dateKey = rec.dateKey
    if dateKey ~= nil then
        S.dayMarks[dateKey] = rec

        if instance.parameters.debug and (rec.nearMissFrd or rec.nearMissFgd) then
            debug_output(string.format("%s near-miss FRD(Basic=%s,+=%s) FGD(Basic=%s,+=%s)",
                rec.dateLabel,
                tostring(rec.nearMissBasicFrd), tostring(rec.nearMissQualifiedFrd),
                tostring(rec.nearMissBasicFgd), tostring(rec.nearMissQualifiedFgd)))
            debug_output(string.format("%s fail basic(FRD range=%s clv=%s; FGD range=%s clv=%s) qualified(FRD reclaim=%s quality=%s; FGD reclaim=%s quality=%s)",
                rec.dateLabel,
                tostring(rec.failReasons.basic.frd.eventRangeFail), tostring(rec.failReasons.basic.frd.eventClvFail),
                tostring(rec.failReasons.basic.fgd.eventRangeFail), tostring(rec.failReasons.basic.fgd.eventClvFail),
                tostring(rec.failReasons.qualified.frd.reclaimFail), tostring(rec.failReasons.qualified.frd.qualityFail),
                tostring(rec.failReasons.qualified.fgd.reclaimFail), tostring(rec.failReasons.qualified.fgd.qualityFail)))
        end
        if instance.parameters.debug then
            debug_output(string.format("day mark upsert date=%s source=SSOT", tostring(dateKey)))
        end
    end

    S.day_cache[day_idx] = rec
    S.day_cache_meta[day_idx] = {
        ts = S.d1:date(day_idx),
        open = S.d1.open[day_idx],
        high = S.d1.high[day_idx],
        low = S.d1.low[day_idx],
        close = S.d1.close[day_idx]
    }
    return rec
end


function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()
    instance:name(profile:id() .. "(" .. S.source:name() .. ")")
    if nameOnly then return end
    instance:ownerDrawn(true)
    S.day_cache = {}
    S.day_cache_meta = {}
    S.dayMarks = {}
    S.draw.lastRefreshClockMs = 0
    S.draw.lastRefreshDateKey = nil
    S.draw.inRefreshRequest = false
    S.lastFullAuditDayKey = nil
    S.symmetryAudit = audit_symmetry()

    S.d1 = getHistory(S.source:instrument(), "D1", S.source:isBid())
    S.m15 = getHistory(S.source:instrument(), "m15", S.source:isBid())

    T.pump = instance:addStream("is_pump_day", core.Line, "Pump Day", "", core.rgb(30,160,30), S.first)
    T.dump = instance:addStream("is_dump_day", core.Line, "Dump Day", "", core.rgb(200,60,60), S.first)
    T.frdEvent = instance:addStream("is_frd_event_day", core.Line, "FRD Event", "", core.rgb(220,20,60), S.first)
    T.fgdEvent = instance:addStream("is_fgd_event_day", core.Line, "FGD Event", "", core.rgb(0,180,0), S.first)
    T.frdTrade = instance:addStream("is_frd_trade_day_candidate", core.Line, "FRD Trade Candidate", "", core.rgb(255,140,0), S.first)
    T.fgdTrade = instance:addStream("is_fgd_trade_day_candidate", core.Line, "FGD Trade Candidate", "", core.rgb(255,200,0), S.first)
    T.tradeDay = instance:addStream("is_trade_day", core.Line, "Trade Day", "", core.rgb(255,215,0), S.first)

    T.rectValid = instance:addStream("has_valid_rectangle", core.Line, "Rectangle Valid", "", core.rgb(135,206,250), S.first)
    T.rectHigh = instance:addStream("rectangle_high", core.Line, "Rectangle High", "", core.rgb(255,255,255), S.first)
    T.rectLow = instance:addStream("rectangle_low", core.Line, "Rectangle Low", "", core.rgb(180,180,180), S.first)
    T.rectHeight = instance:addStream("rectangle_height", core.Line, "Rectangle Height", "", core.rgb(130,130,255), S.first)
    T.rectBars = instance:addStream("rectangle_bar_count", core.Line, "Rectangle Bar Count", "", core.rgb(120,120,120), S.first)
    T.rectStart = instance:addStream("rectangle_start_time", core.Line, "Rectangle Start Time", "", core.rgb(100,149,237), S.first)
    T.rectEnd = instance:addStream("rectangle_end_time", core.Line, "Rectangle End Time", "", core.rgb(72,61,139), S.first)

    T.daytypeBias = instance:addStream("daytype_bias", core.Line, "DayType Bias", "", core.rgb(255,215,0), S.first)
    T.dayBias = instance:addStream("day_bias", core.Line, "Day Bias", "", core.rgb(255,255,153), S.first)
    T.eventDayType = instance:addStream("event_day_type", core.Line, "Event Day Type", "", core.rgb(238,130,238), S.first)
    T.dayTypeCode = instance:addStream("day_type_code", core.Line, "Day Type Code", "", core.rgb(199,21,133), S.first)

    T.repeatedPumpScore = instance:addStream("repeated_pump_score", core.Line, "Repeated Pump Score", "", core.rgb(60,179,113), S.first)
    T.repeatedDumpScore = instance:addStream("repeated_dump_score", core.Line, "Repeated Dump Score", "", core.rgb(205,92,92), S.first)
    T.consolidationScore = instance:addStream("consolidation_score", core.Line, "Consolidation Score", "", core.rgb(100,149,237), S.first)
    T.threeLevelsScore = instance:addStream("three_levels_score", core.Line, "Three Levels Score", "", core.rgb(255,160,122), S.first)

    -- Full report streams for CSV/Excel export (daily date/event flags + parameter snapshot).
    T.reportDateKey = instance:addStream("report_date_key", core.Line, "Report Date Key", "", core.rgb(176,196,222), S.first)
    T.reportFrd = instance:addStream("report_is_frd", core.Line, "Report FRD", "", core.rgb(220,20,60), S.first)
    T.reportFgd = instance:addStream("report_is_fgd", core.Line, "Report FGD", "", core.rgb(0,180,0), S.first)
    T.reportTradeDay = instance:addStream("report_is_trade_day", core.Line, "Report Trade Day", "", core.rgb(255,215,0), S.first)
    T.reportMaxRectAtr = instance:addStream("report_max_rectangle_height_atr", core.Line, "Report Max Rectangle Height ATR", "", core.rgb(135,206,250), S.first)
    T.reportPumpDumpAtr = instance:addStream("report_pump_dump_atr_mult", core.Line, "Report Pump Dump ATR Mult", "", core.rgb(30,160,30), S.first)
    T.reportImpulseAtr = instance:addStream("report_impulse_atr_mult", core.Line, "Report Impulse ATR Mult", "", core.rgb(123,104,238), S.first)
    T.reportImpulseCloseExtreme = instance:addStream("report_impulse_close_extreme", core.Line, "Report Impulse Close Extreme", "", core.rgb(72,61,139), S.first)
    T.reportImpulseBodyRatioMin = instance:addStream("report_impulse_body_ratio_min", core.Line, "Report Impulse Body Ratio Min", "", core.rgb(65,105,225), S.first)
    T.reportEventAtr = instance:addStream("report_event_atr_mult", core.Line, "Report Event ATR Mult", "", core.rgb(218,112,214), S.first)
    T.reportEventCloseExtreme = instance:addStream("report_event_close_extreme", core.Line, "Report Event Close Extreme", "", core.rgb(199,21,133), S.first)
    T.reportReclaimRatioMin = instance:addStream("report_reclaim_ratio_min", core.Line, "Report Reclaim Ratio Min", "", core.rgb(255,140,0), S.first)
end

function Draw(stage, context)
    if stage ~= 2 or context == nil or S.source == nil or S.d1 == nil then return end

    ensure_draw_resources(context)

    local firstVisible = safe_value(context, "firstBar")
    local lastVisible = safe_value(context, "lastBar")
    local from = math.max(S.first or 0, firstVisible or (S.first or 0))
    local to = lastVisible or (S.source:size() - 1)
    local top = safe_value(context, "top") or 10
    local baseYOffset = 8
    local linePadding = 2
    local _, weekdayMeasuredH = measure_text(context, S.draw.weekdayFont, "Wed")
    local _, dayTypeMeasuredH = measure_text(context, S.draw.dayTypeFont, "Trade Day")
    local weekdayLineHeight = (weekdayMeasuredH or clamp_positive(instance.parameters.WeekdayFontSize, 10)) + linePadding
    local dayTypeLineHeight = (dayTypeMeasuredH or clamp_positive(instance.parameters.DayTypeFontSize, 10)) + linePadding
    local analysisFirstDayIdx = get_analysis_first_day_idx()

    for period = from, to do
        if IsNewTradingDay(period) then
            local d1_idx = find_history_index_by_time(S.d1, S.source:date(period))
            if d1_idx ~= nil and (analysisFirstDayIdx == nil or d1_idx >= analysisFirstDayIdx) then
                local d = get_or_build_day_mark(d1_idx)
                if d ~= nil then
                if instance.parameters.debug then
                    debug_output(string.format("draw fetch date=%s source=SSOT", tostring(d.dateKey)))
                end
                local x = safe_value(context, "positionOfBar", period)
                if x == nil then
                    x = safe_value(context, "positionOfDate", S.source:date(period))
                end

                if x ~= nil then
                    if instance.parameters.ShowDayDivider then
                        local dividerX = x - 1
                        local topY = safe_value(context, "top")
                        local bottomY = safe_value(context, "bottom")
                        local dividerPen = is_weekend_ts(S.source:date(period)) and (S.draw.weekendDayDividerPen or S.draw.dayDividerPen) or S.draw.dayDividerPen
                        draw_line(context, dividerPen or S.draw.neutralPen, dividerX, topY, dividerX, bottomY)
                    end

                    local y1 = top + baseYOffset
                    local weekdayColor = instance.parameters.ShowWeekdayLabels and instance.parameters.WeekdayTextColor or instance.parameters.InactiveTextColor
                    draw_text(context, S.draw.weekdayFont, GetWeekdayLabel(period), weekdayColor, x, y1)

                    if instance.parameters.ShowDayTypeLabels then
                        local labels = GetDayTypeLabels(period, d)
                        for i = 1, #labels do
                            local label = labels[i]
                            local y = y1 + weekdayLineHeight + ((i - 1) * dayTypeLineHeight)
                            local labelColor = get_day_type_color(label)
                            local shouldStrike = d.supersededByOpposite and is_frd_fgd_label(label)
                            if shouldStrike then
                                labelColor = instance.parameters.InactiveTextColor or labelColor
                            end
                            draw_text(context, S.draw.dayTypeFont, label, labelColor, x, y)

                            if shouldStrike then
                                local textW, textH = measure_text(context, S.draw.dayTypeFont, label)
                                local fallbackW = math.max(1, #tostring(label) * clamp_positive(instance.parameters.DayTypeFontSize, 10))
                                local fallbackH = math.max(1, clamp_positive(instance.parameters.DayTypeFontSize, 10))
                                local strikeW = math.max(1, tonumber(textW) or fallbackW)
                                local strikeH = math.max(1, tonumber(textH) or fallbackH)
                                local strikeY = y + math.floor(strikeH * 0.55)
                                draw_line(context, S.draw.neutralPen, x, strikeY, x + strikeW, strikeY)
                            end
                        end

                        local auditLines = build_audit_lines(d1_idx, d)
                        for i = 1, #auditLines do
                            local y = y1 + weekdayLineHeight + (#labels * dayTypeLineHeight) + ((i - 1) * dayTypeLineHeight)
                            draw_text(context, S.draw.debugFont or S.draw.dayTypeFont, auditLines[i], instance.parameters.InactiveTextColor, x, y)
                        end
                    end

                    if instance.parameters.debug and instance.parameters.showauditpanel then
                        local panelLines = build_audit_panel_lines(d1_idx)
                        for i = 1, #panelLines do
                            local panelY = y1 + weekdayLineHeight + (9 * dayTypeLineHeight) + ((i - 1) * dayTypeLineHeight)
                            draw_text(context, S.draw.debugFont or S.draw.dayTypeFont, panelLines[i], instance.parameters.InactiveTextColor, x + 120, panelY)
                        end
                    end

                    if d.rectangle_high ~= nil and d.rectangle_low ~= nil then
                        local startPeriod = find_source_period_by_time(d.rectangle_start_time)
                        local endPeriod = find_source_period_by_time(d.rectangle_end_time)
                        local startX = startPeriod ~= nil and safe_method(context, "positionOfBar", startPeriod) or x
                        local endX = endPeriod ~= nil and safe_method(context, "positionOfBar", endPeriod) or x
                        local hiY = get_y_for_price(context, d.rectangle_high)
                        local loY = get_y_for_price(context, d.rectangle_low)

                        if startX ~= nil and endX ~= nil and hiY ~= nil and loY ~= nil then
                            if startX > endX then startX, endX = endX, startX end
                            draw_line(context, S.draw.rectHighPen or S.draw.neutralPen, startX, hiY, endX, hiY)
                            draw_line(context, S.draw.rectLowPen or S.draw.neutralPen, startX, loY, endX, loY)
                            if instance.parameters.debug then
                                draw_line(context, S.draw.neutralPen, startX, hiY, startX, loY)
                                draw_line(context, S.draw.neutralPen, endX, hiY, endX, loY)
                                draw_text(context, S.draw.debugFont or S.draw.dayTypeFont, "rectangleHigh", instance.parameters.RectangleHighDebugColor, startX, hiY)
                                draw_text(context, S.draw.debugFont or S.draw.dayTypeFont, "rectangleLow", instance.parameters.RectangleLowDebugColor, startX, loY)
                            end
                        end
                    end
                end
            end
        end
    end
end

end

function Update(period, mode)
    if S.source == nil or S.d1 == nil or S.m15 == nil or period < S.first then return end

    local d1_idx = find_history_index_by_time(S.d1, S.source:date(period))
    if d1_idx == nil or d1_idx <= S.d1:first() + 1 then return end

    if not is_in_analysis_window(d1_idx) then
        T.pump[period] = 0
        T.dump[period] = 0
        T.frdEvent[period] = 0
        T.fgdEvent[period] = 0
        T.frdTrade[period] = 0
        T.fgdTrade[period] = 0
        T.tradeDay[period] = 0
        T.rectValid[period] = 0
        T.rectHigh[period] = 0
        T.rectLow[period] = 0
        T.rectHeight[period] = 0
        T.rectBars[period] = 0
        T.rectStart[period] = 0
        T.rectEnd[period] = 0
        T.daytypeBias[period] = 0
        T.dayBias[period] = 0
        T.eventDayType[period] = 0
        T.dayTypeCode[period] = 0
        T.repeatedPumpScore[period] = 0
        T.repeatedDumpScore[period] = 0
        T.consolidationScore[period] = 0
        T.threeLevelsScore[period] = 0
        T.reportDateKey[period] = 0
        T.reportFrd[period] = 0
        T.reportFgd[period] = 0
        T.reportTradeDay[period] = 0
        T.reportMaxRectAtr[period] = 0
        T.reportPumpDumpAtr[period] = 0
        T.reportImpulseAtr[period] = 0
        T.reportImpulseCloseExtreme[period] = 0
        T.reportImpulseBodyRatioMin[period] = 0
        T.reportEventAtr[period] = 0
        T.reportEventCloseExtreme[period] = 0
        T.reportReclaimRatioMin[period] = 0
        return
    end

    build_day_record(d1_idx)
    if d1_idx - 1 >= S.d1:first() + 1 then
        build_day_record(d1_idx - 1)
    end

    local d = get_day_mark_by_idx(d1_idx)
    if d == nil then return end

    if instance.parameters.debug then
        debug_output(string.format("update fetch date=%s source=SSOT", tostring(d.dateKey)))
    end

    T.pump[period] = d.is_pump_day and 1 or 0
    T.dump[period] = d.is_dump_day and 1 or 0
    T.frdEvent[period] = d.is_frd_event_day and 1 or 0
    T.fgdEvent[period] = d.is_fgd_event_day and 1 or 0
    T.frdTrade[period] = d.is_frd_trade_day_candidate and 1 or 0
    T.fgdTrade[period] = d.is_fgd_trade_day_candidate and 1 or 0
    T.tradeDay[period] = d.isTradeDay and 1 or 0

    T.rectValid[period] = d.has_valid_rectangle and 1 or 0
    T.rectHigh[period] = d.rectangle_high or 0
    T.rectLow[period] = d.rectangle_low or 0
    T.rectHeight[period] = d.rectangle_height or 0
    T.rectBars[period] = d.rectangle_bar_count or 0
    T.rectStart[period] = d.rectangle_start_time or 0
    T.rectEnd[period] = d.rectangle_end_time or 0

    T.daytypeBias[period] = d.daytype_bias or 0
    T.dayBias[period] = d.daytype_bias or 0
    T.eventDayType[period] = d.event_day_type or 0
    T.dayTypeCode[period] = (d.isFrd and -1) or (d.isFgd and 1) or ((d.is_frd_trade_day_candidate and -2) or (d.is_fgd_trade_day_candidate and 2) or 0)

    T.repeatedPumpScore[period] = d.repeated_pump_score or 0
    T.repeatedDumpScore[period] = d.repeated_dump_score or 0
    T.consolidationScore[period] = d.consolidation_score or 0
    T.threeLevelsScore[period] = d.three_levels_score or 0

    local reportMaxRectAtr = safe_div(d.rectangle_height, d.eventAtr)
    local reportPrevRangeAtr = safe_div(d.prevRange, d.prevAtr)
    local reportEventRangeAtr = safe_div(d.eventRange, d.eventAtr)

    local reclaimRatioSelected = 0
    if d.isFrd or d.basicFrd or (d.prevIsPump and d.eventDown) then
        reclaimRatioSelected = d.reclaimRatioFrd or 0
    elseif d.isFgd or d.basicFgd or (d.prevIsDump and d.eventUp) then
        reclaimRatioSelected = d.reclaimRatioFgd or 0
    end

    local shouldEmitReport = true
    if instance.parameters.reportdailyonly then
        shouldEmitReport = IsNewTradingDay(period)
    end

    T.reportDateKey[period] = shouldEmitReport and (d.dateKey or 0) or 0
    T.reportFrd[period] = shouldEmitReport and (d.isFrd and 1 or 0) or 0
    T.reportFgd[period] = shouldEmitReport and (d.isFgd and 1 or 0) or 0
    T.reportTradeDay[period] = shouldEmitReport and (d.isTradeDay and 1 or 0) or 0
    T.reportMaxRectAtr[period] = shouldEmitReport and reportMaxRectAtr or 0
    T.reportPumpDumpAtr[period] = shouldEmitReport and reportPrevRangeAtr or 0
    T.reportImpulseAtr[period] = shouldEmitReport and reportPrevRangeAtr or 0
    T.reportImpulseCloseExtreme[period] = shouldEmitReport and (d.prevClv or 0) or 0
    T.reportImpulseBodyRatioMin[period] = shouldEmitReport and (d.prevBodyRatio or 0) or 0
    T.reportEventAtr[period] = shouldEmitReport and reportEventRangeAtr or 0
    T.reportEventCloseExtreme[period] = shouldEmitReport and (d.eventClv or 0) or 0
    T.reportReclaimRatioMin[period] = shouldEmitReport and (reclaimRatioSelected or 0) or 0

    if instance.parameters.fullaudit and d.dateKey ~= nil and d.dateKey ~= S.lastFullAuditDayKey then
        emit_full_audit(d1_idx)
        S.lastFullAuditDayKey = d.dateKey
    end

    request_owner_draw_refresh(period, d)
end

function ReleaseInstance()
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
end

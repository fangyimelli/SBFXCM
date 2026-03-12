local FONT_WEEKDAY = 10
local FONT_DAYTYPE = 11
local FONT_DEBUG = 12
local PEN_NEUTRAL = 20
local PEN_RECT_HIGH = 21
local PEN_RECT_LOW = 22

local S = {source=nil, first=nil, d1=nil, m15=nil, day_cache={}, dayMarks={}, draw={initialized=false, weekdayFont=FONT_WEEKDAY, dayTypeFont=FONT_DAYTYPE, debugFont=FONT_DEBUG, neutralPen=PEN_NEUTRAL, rectHighPen=PEN_RECT_HIGH, rectLowPen=PEN_RECT_LOW}}
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
    indicator.parameters:addBoolean("enablequality", "Enable Quality Filter", "", true)
    indicator.parameters:addDouble("qualityatrmult", "Quality Prev Day ATR Mult", "", 1.3)
    indicator.parameters:addDouble("qualityeventatrmult", "Quality Event Day ATR Mult", "", 0.6)
    indicator.parameters:addDouble("qualitycloseextreme", "Quality Close Extreme Ratio", "", 0.7)
    indicator.parameters:addDouble("qualityreclaimratio", "Quality Reclaim Ratio", "", 0.5)
    indicator.parameters:addInteger("qualityscoremin", "Quality Min Score For +", "", 4)
    indicator.parameters:addBoolean("showqualityaudit", "Show Quality Audit", "", false)
    indicator.parameters:addBoolean("ShowWeekdayLabels", "Show Weekday Labels", "", true)
    indicator.parameters:addBoolean("ShowDayTypeLabels", "Show DayType Labels", "", true)
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

local function clamp_positive(v, fallback)
    local n = tonumber(v)
    if n == nil or n <= 0 then return fallback end
    return math.floor(n)
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

    local labels = {}
    if dayRecord.isTradeDay or dayRecord.is_frd_trade_day_candidate or dayRecord.is_fgd_trade_day_candidate then
        labels[#labels + 1] = "Trade Day"
        return labels
    end

    if dayRecord.isFgd or dayRecord.is_fgd_event_day then
        labels[#labels + 1] = dayRecord.isHighQualityFgd and "FGD+" or "FGD"
    elseif dayRecord.isFrd or dayRecord.is_frd_event_day then
        labels[#labels + 1] = dayRecord.isHighQualityFrd and "FRD+" or "FRD"
    end

    return labels
end

local function build_audit_lines(dayRecord)
    if dayRecord == nil or dayRecord.audit == nil then return {} end
    if not instance.parameters.debug then return {} end
    if not (dayRecord.audit.isReversalAttempt or dayRecord.isFgd or dayRecord.is_fgd_event_day or dayRecord.isFrd or dayRecord.is_frd_event_day) then return {} end

    local audit = dayRecord.audit
    local yn = function(v) return v and "Y" or "N" end

    local failed = {}
    if not audit.strongPrevDay then failed[#failed + 1] = "NoPrevATR" end
    if not audit.extremePrevClose then failed[#failed + 1] = "NoPrevCLV" end
    if not audit.strongEventDay then failed[#failed + 1] = "NoEventATR" end
    if not audit.extremeEventClose then failed[#failed + 1] = "NoEventCLV" end
    if not audit.reclaimEnough then failed[#failed + 1] = "NoReclaim" end

    local lines = {
        string.format("PrevATR:%s PrevCLV:%s", yn(audit.strongPrevDay), yn(audit.extremePrevClose)),
        string.format("EventATR:%s EventCLV:%s", yn(audit.strongEventDay), yn(audit.extremeEventClose)),
        string.format("Reclaim:%s Q=%d(%s)", yn(audit.reclaimEnough), tonumber(dayRecord.qualityScore) or 0, dayRecord.qualityGrade or "")
    }

    if #failed > 0 and not (dayRecord.isFgd or dayRecord.is_fgd_event_day or dayRecord.isFrd or dayRecord.is_frd_event_day) then
        lines[#lines + 1] = table.concat(failed, ",")
    end

    return lines
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
    end
    return instance.parameters.InactiveTextColor
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
    local solidStyle = safe_value(context, "convertPenStyle", core.LINE_SOLID) or core.LINE_SOLID

    local okWeekdayFont = safe_method(context, "createFont", FONT_WEEKDAY, "Arial", weekdayPx, weekdayPx, 0)
    local okDayTypeFont = safe_method(context, "createFont", FONT_DAYTYPE, "Arial", dayTypePx, dayTypePx, core.FONT_BOLD or 0)
    local okDebugFont = safe_method(context, "createFont", FONT_DEBUG, "Arial", debugPx, debugPx, 0)

    local okNeutralPen = safe_method(context, "createPen", PEN_NEUTRAL, solidStyle, penWidth, instance.parameters.InactiveTextColor)
    local okRectHighPen = safe_method(context, "createPen", PEN_RECT_HIGH, solidStyle, penWidth, instance.parameters.RectangleHighDebugColor)
    local okRectLowPen = safe_method(context, "createPen", PEN_RECT_LOW, solidStyle, penWidth, instance.parameters.RectangleLowDebugColor)

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

local function build_day_record(day_idx)
    if day_idx == nil or day_idx <= S.d1:first() + 1 then return nil end
    if S.day_cache[day_idx] ~= nil then return S.day_cache[day_idx] end

    local base = evaluate_pump_dump(S.d1, day_idx)
    if base == nil then return nil end

    local rect = eval_rectangle(S.d1, S.m15, day_idx)

    local today_open, today_close = S.d1.open[day_idx], S.d1.close[day_idx]
    local today_high, today_low = S.d1.high[day_idx], S.d1.low[day_idx]

    local atrLen = math.max(1, clamp_positive(instance.parameters.dayatrlen, 14))
    local atrMult = tonumber(instance.parameters.atr_mult) or 1.0
    if atrMult <= 0 then atrMult = 1.0 end

    local enableQuality = instance.parameters.enablequality
    local qualityAtrMult = tonumber(instance.parameters.qualityatrmult) or 1.3
    local qualityEventAtrMult = tonumber(instance.parameters.qualityeventatrmult) or 0.6
    local qualityCloseExtreme = tonumber(instance.parameters.qualitycloseextreme) or 0.7
    local qualityReclaimRatio = tonumber(instance.parameters.qualityreclaimratio) or 0.5
    local qualityScoreMin = math.max(1, clamp_positive(instance.parameters.qualityscoremin, 4))
    local epsilon = 0.0000001

    local yesterday_idx = day_idx - 1
    local yOpen = S.d1.open[yesterday_idx]
    local yClose = S.d1.close[yesterday_idx]
    local yHigh = S.d1.high[yesterday_idx]
    local yLow = S.d1.low[yesterday_idx]
    local yRange = (yHigh or 0) - (yLow or 0)
    local yAtr = calc_atr(S.d1, yesterday_idx, atrLen)
    local threshold = (yAtr or 0) * atrMult
    local rangePass = yAtr ~= nil and yAtr > 0 and yRange >= threshold

    local todayUp = today_close > today_open
    local todayDown = today_close < today_open

    local prev_rec = nil
    if day_idx - 1 >= S.d1:first() then
        prev_rec = build_day_record(day_idx - 1)
    end

    local prevRange = yRange
    local prevAtr = yAtr or 0
    local prevCloseLocation = (yClose - yLow) / math.max((yHigh - yLow), epsilon)
    local eventRange = (today_high or 0) - (today_low or 0)
    local eventAtr = calc_atr(S.d1, day_idx, atrLen) or 0
    local eventCloseLocation = (today_close - today_low) / math.max((today_high - today_low), epsilon)
    local bodyHigh = math.max(yOpen, yClose)
    local bodyLow = math.min(yOpen, yClose)
    local bodySize = math.max(bodyHigh - bodyLow, epsilon)

    local strongPrevDay = false
    local extremePrevClose = false
    local strongEventDay = false
    local extremeEventClose = false
    local reclaimEnough = false
    local reclaimRatio = 0
    local prevPumpByQuality = false
    local prevDumpByQuality = false

    strongPrevDay = prevAtr > 0 and prevRange >= (prevAtr * qualityAtrMult)
    prevPumpByQuality = (yClose > yOpen) and (prevCloseLocation >= qualityCloseExtreme) and strongPrevDay
    prevDumpByQuality = (yClose < yOpen) and (prevCloseLocation <= (1 - qualityCloseExtreme)) and strongPrevDay
    extremePrevClose = prevPumpByQuality or prevDumpByQuality

    local is_fgd_event = prevDumpByQuality and todayUp
    local is_frd_event = prevPumpByQuality and todayDown
    local is_reversal_attempt = (prevDumpByQuality and todayUp) or (prevPumpByQuality and todayDown) or (rangePass and ((yClose < yOpen and todayUp) or (yClose > yOpen and todayDown)))

    if is_fgd_event or is_frd_event then
        strongEventDay = eventAtr > 0 and eventRange >= (eventAtr * qualityEventAtrMult)

        if is_fgd_event then
            extremeEventClose = eventCloseLocation >= qualityCloseExtreme
            reclaimRatio = (today_close - bodyLow) / bodySize
        else
            extremeEventClose = eventCloseLocation <= (1 - qualityCloseExtreme)
            reclaimRatio = (bodyHigh - today_close) / bodySize
        end

        reclaimEnough = reclaimRatio >= qualityReclaimRatio
    end

    local basicEventPass = (is_fgd_event or is_frd_event) and strongPrevDay and extremePrevClose and strongEventDay and extremeEventClose and reclaimEnough
    if not basicEventPass then
        is_fgd_event = false
        is_frd_event = false
    end

    local from_prev_event = prev_rec ~= nil and (prev_rec.isFrd or prev_rec.isFgd or prev_rec.is_frd_event_day or prev_rec.is_fgd_event_day)
    local is_trade_day = (not (is_frd_event or is_fgd_event)) and from_prev_event
    local is_frd_trade_candidate = is_trade_day and prev_rec ~= nil and (prev_rec.isFrd or prev_rec.is_frd_event_day)
    local is_fgd_trade_candidate = is_trade_day and prev_rec ~= nil and (prev_rec.isFgd or prev_rec.is_fgd_event_day)

    local event_day_type = 0
    if is_frd_event then
        event_day_type = -1
    elseif is_fgd_event then
        event_day_type = 1
    end

    local qualityScore = 0
    if strongPrevDay then qualityScore = qualityScore + 1 end
    if extremePrevClose then qualityScore = qualityScore + 1 end
    if strongEventDay then qualityScore = qualityScore + 1 end
    if extremeEventClose then qualityScore = qualityScore + 1 end
    if reclaimEnough then qualityScore = qualityScore + 1 end

    local qualityGrade = ""
    if qualityScore >= 5 then
        qualityGrade = "A"
    elseif qualityScore == 4 then
        qualityGrade = "B"
    elseif qualityScore == 3 then
        qualityGrade = "C"
    end

    local isHighQualityFgd = enableQuality and is_fgd_event and qualityScore >= qualityScoreMin
    local isHighQualityFrd = enableQuality and is_frd_event and qualityScore >= qualityScoreMin

    local repeated_pump_score = base.is_pump_day and 1 or 0
    local repeated_dump_score = base.is_dump_day and 1 or 0

    local consolidation_score = 0
    if rect.valid then
        consolidation_score = rect.contained >= (instance.parameters.rectangle_min_contained_closes + 1) and 2 or 1
    end

    local three_levels_score = 0
    if day_idx - 5 >= S.d1:first() then
        local wk_h = S.d1.high[day_idx - 5]
        local wk_l = S.d1.low[day_idx - 5]
        if S.d1.high[day_idx] > wk_h or S.d1.low[day_idx] < wk_l then
            three_levels_score = 1
        end
        if (S.d1.high[day_idx] > wk_h and today_close < today_open) or (S.d1.low[day_idx] < wk_l and today_close > today_open) then
            three_levels_score = 2
        end
    end

    local rec = {
        is_pump_day = base.is_pump_day,
        is_dump_day = base.is_dump_day,
        is_frd_event_day = is_frd_event,
        is_fgd_event_day = is_fgd_event,
        isFrd = is_frd_event,
        isFgd = is_fgd_event,
        isTradeDay = is_trade_day,
        is_trade_day = is_trade_day,
        is_frd_trade_day_candidate = is_frd_trade_candidate,
        is_fgd_trade_day_candidate = is_fgd_trade_candidate,
        isHighQualityFgd = isHighQualityFgd,
        isHighQualityFrd = isHighQualityFrd,
        qualityScore = qualityScore,
        qualityGrade = qualityGrade,
        has_valid_rectangle = rect.valid,
        rectangle_high = rect.high,
        rectangle_low = rect.low,
        rectangle_height = rect.height,
        rectangle_bar_count = rect.bar_count,
        rectangle_start_time = rect.start_time,
        rectangle_end_time = rect.end_time,
        rectangle_contained_closes = rect.contained,
        daytype_bias = base.daytype_bias,
        event_day_type = event_day_type,
        repeated_pump_score = repeated_pump_score,
        repeated_dump_score = repeated_dump_score,
        consolidation_score = consolidation_score,
        three_levels_score = three_levels_score,
        audit = {
            prevDump = prevDumpByQuality,
            prevPump = prevPumpByQuality,
            todayUp = todayUp,
            todayDown = todayDown,
            isReversalAttempt = is_reversal_attempt,
            prevRange = prevRange,
            prevAtr = prevAtr,
            prevCloseLocation = prevCloseLocation,
            eventRange = eventRange,
            eventAtr = eventAtr,
            eventCloseLocation = eventCloseLocation,
            reclaimRatio = reclaimRatio,
            strongPrevDay = strongPrevDay,
            extremePrevClose = extremePrevClose,
            strongEventDay = strongEventDay,
            extremeEventClose = extremeEventClose,
            reclaimEnough = reclaimEnough,
            fromPrevEvent = from_prev_event
        }
    }

    local dateKey = day_key(S.d1:date(day_idx))
    if dateKey ~= nil then
        S.dayMarks[dateKey] = {
            isFrd = rec.isFrd,
            isFgd = rec.isFgd,
            isTradeDay = rec.isTradeDay,
            qualityScore = rec.qualityScore,
            qualityGrade = rec.qualityGrade,
            isHighQualityFgd = rec.isHighQualityFgd,
            isHighQualityFrd = rec.isHighQualityFrd,
            audit = {
                prevDump = rec.audit.prevDump,
                prevPump = rec.audit.prevPump,
                todayUp = rec.audit.todayUp,
                todayDown = rec.audit.todayDown,
                prevRange = rec.audit.prevRange,
                prevAtr = rec.audit.prevAtr,
                prevCloseLocation = rec.audit.prevCloseLocation,
                eventRange = rec.audit.eventRange,
                eventAtr = rec.audit.eventAtr,
                eventCloseLocation = rec.audit.eventCloseLocation,
                reclaimRatio = rec.audit.reclaimRatio
            }
        }
    end

    S.day_cache[day_idx] = rec
    return rec
end

function Prepare(nameOnly)
    S.source = instance.source
    S.first = S.source:first()
    instance:name(profile:id() .. "(" .. S.source:name() .. ")")
    if nameOnly then return end
    instance:ownerDrawn(true)
    S.day_cache = {}
    S.dayMarks = {}

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

    for period = from, to do
        if IsNewTradingDay(period) then
            local d1_idx = find_history_index_by_time(S.d1, S.source:date(period))
            local d = build_day_record(d1_idx)
            if d ~= nil then
                local x = safe_value(context, "positionOfBar", period)
                if x == nil then
                    x = safe_value(context, "positionOfDate", S.source:date(period))
                end

                if x ~= nil then
                    local y1 = top + baseYOffset
                    local weekdayColor = instance.parameters.ShowWeekdayLabels and instance.parameters.WeekdayTextColor or instance.parameters.InactiveTextColor
                    draw_text(context, S.draw.weekdayFont, GetWeekdayLabel(period), weekdayColor, x, y1)

                    if instance.parameters.ShowDayTypeLabels then
                        local labels = GetDayTypeLabels(period, d)
                        for i = 1, #labels do
                            local label = labels[i]
                            local y = y1 + weekdayLineHeight + ((i - 1) * dayTypeLineHeight)
                            draw_text(context, S.draw.dayTypeFont, label, get_day_type_color(label), x, y)
                        end

                        local auditLines = build_audit_lines(d)
                        for i = 1, #auditLines do
                            local y = y1 + weekdayLineHeight + (#labels * dayTypeLineHeight) + ((i - 1) * dayTypeLineHeight)
                            draw_text(context, S.draw.debugFont or S.draw.dayTypeFont, auditLines[i], instance.parameters.InactiveTextColor, x, y)
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

function Update(period, mode)
    if S.source == nil or S.d1 == nil or S.m15 == nil or period < S.first then return end

    local d1_idx = find_history_index_by_time(S.d1, S.source:date(period))
    if d1_idx == nil or d1_idx <= S.d1:first() + 1 then return end

    local d = build_day_record(d1_idx)
    if d == nil then return end

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
end

function ReleaseInstance()
end

function AsyncOperationFinished(cookie, success, message, message1, message2)
end

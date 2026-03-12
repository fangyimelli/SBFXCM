local M = {}

function M.day_key(ts)
    if ts == nil then return nil end
    return math.floor(ts)
end

function M.minute_of_day(ts)
    local f = ts - math.floor(ts)
    if f < 0 then f = f + 1 end
    local m = math.floor(f * 1440 + 0.000001)
    if m < 0 then m = 0 elseif m > 1439 then m = 1439 end
    return m
end

function M.in_window(ts, start_min, finish_min)
    local m = M.minute_of_day(ts)
    if start_min <= finish_min then
        return m >= start_min and m < finish_min
    end
    return m >= start_min or m < finish_min
end

M.NY_ASIA_START = 19 * 60
M.NY_ASIA_END = 23 * 60
M.NY_LONDON_START = 1 * 60
M.NY_LONDON_END = 5 * 60
M.NY_NEWYORK_START = 7 * 60
M.NY_NEWYORK_END = 11 * 60

function M.is_in_asia_window(ts) return M.in_window(ts, M.NY_ASIA_START, M.NY_ASIA_END) end
function M.is_in_london_window(ts) return M.in_window(ts, M.NY_LONDON_START, M.NY_LONDON_END) end
function M.is_in_newyork_window(ts) return M.in_window(ts, M.NY_NEWYORK_START, M.NY_NEWYORK_END) end
function M.is_in_any_timing_window(ts)
    return M.is_in_asia_window(ts) or M.is_in_london_window(ts) or M.is_in_newyork_window(ts)
end

function M.is_near_window_open(ts, timeframe_minutes)
    local tf = timeframe_minutes or 5
    local threshold = math.max(15, tf * 3)
    local m = M.minute_of_day(ts)
    local starts = {M.NY_ASIA_START, M.NY_LONDON_START, M.NY_NEWYORK_START}
    for i = 1, #starts do
        local d = m - starts[i]
        if d < 0 then d = d + 1440 end
        if d >= 0 and d < threshold then return true end
    end
    return false
end

function M.find_history_index_by_time(history, ts)
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

function M.calc_atr(history, idx, len)
    if history == nil or idx == nil or len == nil or len <= 0 then return nil end
    local start = idx - len + 1
    if start < history:first() + 1 then return nil end
    local sum, count = 0, 0
    for i = start, idx do
        local h, l, c1 = history.high[i], history.low[i], history.close[i - 1]
        local tr = math.max(h - l, math.max(math.abs(h - c1), math.abs(l - c1)))
        sum = sum + tr
        count = count + 1
    end
    if count == 0 then return nil end
    return sum / count
end

function M.evaluate_daytype(d1, day_idx)
    if d1 == nil or day_idx == nil then return nil end
    local y = day_idx - 1
    local py = day_idx - 2
    if py < d1:first() then return nil end

    local yH,yL,yO,yC = d1.high[y], d1.low[y], d1.open[y], d1.close[y]
    local pyH,pyL = d1.high[py], d1.low[py]
    local yR = yH - yL
    if yR <= 0 then return nil end

    local inside = yH <= pyH and yL >= pyL
    local closeUpper = yC >= (yL + yR * 0.5)
    local closeLower = yC <= (yL + yR * 0.5)
    local pump = (yH > pyH) and closeUpper and (yC > yO) and (not inside)
    local dump = (yL < pyL) and closeLower and (yC < yO) and (not inside)

    return {
        is_pump_day = pump,
        is_dump_day = dump,
        bias = pump and 1 or (dump and -1 or 0),
        yesterday_index = y
    }
end

function M.eval_rectangle(d1, m15, d1_idx, params)
    if d1 == nil or m15 == nil or d1_idx == nil then return {valid=false, bar_count=0} end
    local p = params or {}
    local lookback = math.max(1, p.rectangle_lookback_bars or 8)
    local minContained = p.rectangle_min_contained_closes or 6
    local maxHeightAtr = p.max_rectangle_height_atr or 1.2
    local dayatrlen = p.dayatrlen or 14

    local dayStart = M.day_key(d1:date(d1_idx))
    local bars = {}
    local i = m15:first()
    local last = m15:size() - 1
    while i <= last do
        if M.day_key(m15:date(i)) == dayStart then table.insert(bars, i) end
        i = i + 1
    end

    if #bars < lookback then return {valid=false, bar_count=#bars} end
    local startPos = #bars - lookback + 1
    local hi, lo = nil, nil
    for j = startPos, #bars do
        local bi = bars[j]
        local h, l = m15.high[bi], m15.low[bi]
        if hi == nil or h > hi then hi = h end
        if lo == nil or l < lo then lo = l end
    end

    local contained = 0
    for j = startPos, #bars do
        local c = m15.close[bars[j]]
        if c <= hi and c >= lo then contained = contained + 1 end
    end

    local atr = M.calc_atr(d1, d1_idx, dayatrlen)
    local height = hi - lo
    local atrOk = atr ~= nil and atr > 0 and height <= atr * maxHeightAtr

    local last4expand = false
    if #bars >= 4 then
        local a = bars[#bars - 3]
        local b = bars[#bars]
        last4expand = math.abs(m15.close[b] - m15.open[a]) > (height * 0.8)
    end

    return {
        valid = atrOk and (contained >= minContained) and (not last4expand),
        high = hi,
        low = lo,
        height = height,
        bar_count = lookback,
        start_time = m15:date(bars[startPos]),
        end_time = m15:date(bars[#bars]),
        contained = contained
    }
end

function M.build_daytype_record(d1, m15, day_idx, params, day_cache)
    if d1 == nil or day_idx == nil then return nil end
    local cache = day_cache or {}
    if cache[day_idx] ~= nil then return cache[day_idx] end

    local base = M.evaluate_daytype(d1, day_idx)
    if base == nil then return nil end
    local p = params or {}
    local rect = M.eval_rectangle(d1, m15, day_idx, p)

    local prevBase = M.evaluate_daytype(d1, day_idx - 1)
    local todayOpen, todayClose = d1.open[day_idx], d1.close[day_idx]
    local isFrdEvent = prevBase ~= nil and prevBase.is_pump_day and todayClose < todayOpen and rect.valid
    local isFgdEvent = prevBase ~= nil and prevBase.is_dump_day and todayClose > todayOpen and rect.valid

    local prev = cache[day_idx - 1]
    if prev == nil and day_idx - 1 >= d1:first() then
        prev = M.build_daytype_record(d1, m15, day_idx - 1, p, cache)
    end
    local isFrdTradeCandidate = prev ~= nil and prev.is_frd_event_day and prev.has_valid_rectangle
    local isFgdTradeCandidate = prev ~= nil and prev.is_fgd_event_day and prev.has_valid_rectangle

    local atr = M.calc_atr(d1, day_idx, p.dayatrlen or 14) or 999
    local consolidationScore = rect.valid and ((rect.contained >= 7 and rect.height <= atr) and 2 or 1) or 0
    local threeLevels = 0
    if day_idx - 5 >= d1:first() then
        local wkHigh, wkLow = d1.high[day_idx - 5], d1.low[day_idx - 5]
        if d1.high[day_idx] > wkHigh or d1.low[day_idx] < wkLow then threeLevels = 1 end
        if (d1.high[day_idx] > wkHigh and todayClose < todayOpen) or (d1.low[day_idx] < wkLow and todayClose > todayOpen) then threeLevels = 2 end
    end

    local rec = {
        is_pump_day = base.is_pump_day,
        is_dump_day = base.is_dump_day,
        is_frd_event_day = isFrdEvent,
        is_fgd_event_day = isFgdEvent,
        is_frd_trade_day_candidate = isFrdTradeCandidate,
        is_fgd_trade_day_candidate = isFgdTradeCandidate,
        has_valid_rectangle = rect.valid,
        rectangle_high = rect.high,
        rectangle_low = rect.low,
        rectangle_height = rect.height,
        rectangle_bar_count = rect.bar_count,
        rectangle_start_time = rect.start_time,
        rectangle_end_time = rect.end_time,
        bias = base.bias,
        repeated_pump_score = base.is_pump_day and 1 or 0,
        repeated_dump_score = base.is_dump_day and 1 or 0,
        consolidation_score = consolidationScore,
        three_levels_score = threeLevels,
        event_score = consolidationScore + threeLevels,
        trade_day_score = (isFrdTradeCandidate or isFgdTradeCandidate) and (consolidationScore + 1) or 0
    }

    cache[day_idx] = rec
    return rec
end

return M

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

function M.find_history_index_by_time(history, ts, cache)
    if history == nil or ts == nil then return nil end
    local first = history:first()
    local last = history:size() - 1
    if first > last then return nil end

    if cache ~= nil then
        if cache.history ~= history or cache.first ~= first or cache.last_size ~= history:size() then
            cache.last_index = nil
            cache.last_ts = nil
            cache.history = history
            cache.first = first
            cache.last_size = history:size()
        end
    end

    local i = first
    local steps = 0
    if cache ~= nil and cache.last_index ~= nil then
        i = cache.last_index
        if i < first then i = first end
        if i > last then i = last end
    end

    if history:date(i) <= ts then
        while i < last and history:date(i + 1) <= ts do
            i = i + 1
            steps = steps + 1
        end
        if cache ~= nil then
            cache.last_index = i
            cache.last_ts = ts
            cache.calls = (cache.calls or 0) + 1
            cache.scan_bars = (cache.scan_bars or 0) + steps
        end
        return i
    end

    while i >= first and history:date(i) > ts do
        i = i - 1
        steps = steps + 1
    end
    if i < first then
        if cache ~= nil then
            cache.last_index = first
            cache.last_ts = ts
            cache.calls = (cache.calls or 0) + 1
            cache.scan_bars = (cache.scan_bars or 0) + steps
        end
        return nil
    end

    if cache ~= nil then
        cache.last_index = i
        cache.last_ts = ts
        cache.calls = (cache.calls or 0) + 1
        cache.scan_bars = (cache.scan_bars or 0) + steps
    end
    return i
end


function M.weekday_from_timestamp(ts)
    if ts == nil or core == nil or type(core.dateToTable) ~= "function" then return nil end
    local ok, t = pcall(core.dateToTable, ts)
    if not ok or type(t) ~= "table" then return nil end
    return t.wday
end

function M.is_weekend_timestamp(ts)
    local wday = M.weekday_from_timestamp(ts)
    return wday == 1 or wday == 7
end

function M.is_effective_trading_day_idx(d1, idx)
    if d1 == nil or idx == nil then return false end

    local ts = d1:date(idx)
    local wday = M.weekday_from_timestamp(ts)
    if wday == nil then return false end

    if wday == 7 then
        return false
    end

    -- Sunday-stamped bars may represent Monday sessions on many FX feeds,
    -- so only Saturday is treated as non-effective here.
    return true
end

function M.find_prev_effective_trading_day_idx(d1, day_idx)
    if d1 == nil or day_idx == nil then return nil end
    local first = d1:first()
    local idx = day_idx - 1
    while idx >= first do
        if M.is_effective_trading_day_idx(d1, idx) then
            return idx
        end
        idx = idx - 1
    end
    return nil
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

function M.eval_rectangle(d1, m15, d1_idx, params, runtime_cache)
    if d1 == nil or m15 == nil or d1_idx == nil then return {valid=false, bar_count=0} end
    local p = params or {}
    local lookback = math.max(1, p.rectangle_lookback_bars or 8)
    local minContained = p.rectangle_min_contained_closes or 6
    local maxHeightAtr = p.max_rectangle_height_atr or 1.2
    local dayatrlen = p.dayatrlen or 14

    local dayStart = M.day_key(d1:date(d1_idx))
    local cache = runtime_cache
    if cache ~= nil and (cache.history ~= m15 or cache.first ~= m15:first()) then
        cache.history = m15
        cache.first = m15:first()
        cache.scanned_until = nil
        cache.bars_by_day = {}
    end

    local bars = nil
    if cache == nil then
        bars = {}
        local i = m15:first()
        local last = m15:size() - 1
        while i <= last do
            if M.day_key(m15:date(i)) == dayStart then table.insert(bars, i) end
            i = i + 1
        end
    else
        if cache.bars_by_day == nil then cache.bars_by_day = {} end
        local last = m15:size() - 1
        local i = cache.scanned_until ~= nil and (cache.scanned_until + 1) or m15:first()
        if i < m15:first() then i = m15:first() end
        while i <= last do
            local k = M.day_key(m15:date(i))
            local dayBars = cache.bars_by_day[k]
            if dayBars == nil then
                dayBars = {}
                cache.bars_by_day[k] = dayBars
            end
            dayBars[#dayBars + 1] = i
            cache.rect_scan_bars = (cache.rect_scan_bars or 0) + 1
            i = i + 1
        end
        cache.scanned_until = last
        cache.rect_calls = (cache.rect_calls or 0) + 1
        bars = cache.bars_by_day[dayStart] or {}
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

function M.build_daytype_record(d1, m15, day_idx, params, day_cache, runtime_cache)
    if d1 == nil or day_idx == nil then return nil end
    local cache = day_cache or {}
    if cache[day_idx] ~= nil then return cache[day_idx] end

    local base = M.evaluate_daytype(d1, day_idx)
    if base == nil then return nil end
    local p = params or {}
    local rect = M.eval_rectangle(d1, m15, day_idx, p, runtime_cache and runtime_cache.rectangle)

    local prev_idx = M.find_prev_effective_trading_day_idx(d1, day_idx)
    local prevBase = prev_idx ~= nil and M.evaluate_daytype(d1, prev_idx) or nil
    local todayOpen, todayClose = d1.open[day_idx], d1.close[day_idx]
    -- Phase-1 SSOT: rectangle stays debug/output only, not a hard event gate.
    local isFrdEvent = prevBase ~= nil and prevBase.is_pump_day and todayClose < todayOpen
    local isFgdEvent = prevBase ~= nil and prevBase.is_dump_day and todayClose > todayOpen

    local prev = prev_idx ~= nil and cache[prev_idx] or nil
    if prev == nil and prev_idx ~= nil and prev_idx >= d1:first() then
        prev = M.build_daytype_record(d1, m15, prev_idx, p, cache, runtime_cache)
    end
    local trendContinuation = prev ~= nil
        and base.bias ~= nil
        and prev.day_bias ~= nil
        and base.bias ~= 0
        and base.bias == prev.day_bias

    local isFrdTradeCandidate = prev ~= nil and prev.is_frd_event_day
    local isFgdTradeCandidate = prev ~= nil and prev.is_fgd_event_day
    local isTradeDay = isFrdTradeCandidate or isFgdTradeCandidate
    local prevIsEventDay = prev ~= nil and (prev.is_frd_event_day or prev.is_fgd_event_day)
    local trendContinuationFlag = prevIsEventDay and trendContinuation

    local eventType = "none"
    local dayTypeCode = 0
    if isFrdEvent then
        eventType = "FRD"
        dayTypeCode = -1
    elseif isFgdEvent then
        eventType = "FGD"
        dayTypeCode = 1
    elseif isFrdTradeCandidate then
        eventType = "FRD_TRADE_DAY"
        dayTypeCode = -2
    elseif isFgdTradeCandidate then
        eventType = "FGD_TRADE_DAY"
        dayTypeCode = 2
    end

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
        is_trade_day = isTradeDay,
        trend_continuation = trendContinuationFlag,
        has_valid_rectangle = rect.valid,
        rectangle_valid = rect.valid,
        rectangle_high = rect.high,
        rectangle_low = rect.low,
        rectangle_height = rect.height,
        rectangle_bar_count = rect.bar_count,
        rectangle_start_time = rect.start_time,
        rectangle_end_time = rect.end_time,
        bias = base.bias,
        day_bias = base.bias,
        daytype_bias = base.bias,
        event_type = eventType,
        day_type_code = dayTypeCode,
        event_day_type = (isFrdEvent and -1) or (isFgdEvent and 1) or 0,
        repeated_pump_score = base.is_pump_day and 1 or 0,
        repeated_dump_score = base.is_dump_day and 1 or 0,
        consolidation_score = consolidationScore,
        three_levels_score = threeLevels,
        event_score = consolidationScore + threeLevels,
        trade_day_score = (isFrdTradeCandidate or isFgdTradeCandidate) and (consolidationScore + 1) or 0,
        debug_index_calls = (runtime_cache and runtime_cache.index and runtime_cache.index.calls) or 0,
        debug_index_scan_bars = (runtime_cache and runtime_cache.index and runtime_cache.index.scan_bars) or 0,
        debug_rectangle_calls = (runtime_cache and runtime_cache.rectangle and runtime_cache.rectangle.rect_calls) or 0,
        debug_rectangle_scan_bars = (runtime_cache and runtime_cache.rectangle and runtime_cache.rectangle.rect_scan_bars) or 0
    }

    cache[day_idx] = rec
    return rec
end

local function pivotHigh(stream, p, l, r)
    if stream == nil or p == nil then return nil end
    if p < stream:first() + l or p + r > stream:size() - 1 then return nil end
    local v = stream.high[p]
    for i = p - l, p + r do
        if i ~= p and stream.high[i] >= v then return nil end
    end
    return v
end

local function pivotLow(stream, p, l, r)
    if stream == nil or p == nil then return nil end
    if p < stream:first() + l or p + r > stream:size() - 1 then return nil end
    local v = stream.low[p]
    for i = p - l, p + r do
        if i ~= p and stream.low[i] <= v then return nil end
    end
    return v
end

function M.update_structure_state(runtime, source, m15, period, params)
    if runtime == nil or source == nil or m15 == nil or period == nil then return nil end
    local p = params or {}
    local bosLeft = p.bosleft or 2
    local bosRight = p.bosright or 2

    local ts = source:date(period)
    local k = M.day_key(ts)
    if runtime.day_key == nil or runtime.day_key ~= k then
        runtime.day_key = k
        runtime.asia_high = nil
        runtime.asia_low = nil
        runtime.index_cache = {}
    end

    if M.is_in_asia_window(ts) then
        local h, l = source.high[period], source.low[period]
        if runtime.asia_high == nil or h > runtime.asia_high then runtime.asia_high = h end
        if runtime.asia_low == nil or l < runtime.asia_low then runtime.asia_low = l end
    end

    local hasAsia = runtime.asia_high ~= nil and runtime.asia_low ~= nil
    local sweepUp = hasAsia and source.high[period] > runtime.asia_high and source.close[period] < runtime.asia_high
    local sweepDown = hasAsia and source.low[period] < runtime.asia_low and source.close[period] > runtime.asia_low

    if runtime.index_cache == nil then runtime.index_cache = {} end
    local idx15 = M.find_history_index_by_time(m15, ts, runtime.index_cache)
    local hasBos = false
    if idx15 ~= nil then
        local pivotPos = idx15 - 2
        local ph = pivotHigh(m15, pivotPos, bosLeft, bosRight)
        local pl = pivotLow(m15, pivotPos, bosLeft, bosRight)
        if ph ~= nil and m15.close[idx15] > ph then hasBos = true end
        if pl ~= nil and m15.close[idx15] < pl then hasBos = true end
    end

    return {
        has_asia_range = hasAsia,
        sweep_up = sweepUp,
        sweep_down = sweepDown,
        has_session_sweep = sweepUp or sweepDown,
        has_bos = hasBos
    }
end

function M.handle_day_rollover(runtime, ts)
    if runtime == nil or ts == nil then return end
    local day = M.day_key(ts)
    if runtime.day_key == nil or runtime.day_key ~= day then
        runtime.day_key = day
        runtime.index_cache = {}
        runtime.rectangle = {}
    end
end

return M

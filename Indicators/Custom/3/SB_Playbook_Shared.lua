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

return M

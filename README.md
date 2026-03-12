# SB_DayType_FRD_FGD 現況說明（本輪）

> 本文件本輪只更新 `SB_DayType_FRD_FGD.lua` 的真實現況。
> 以下定義屬於**目前程式化代理定義**，不是 playbook 唯一數學公式。

## 1) 責任邊界（DayType only）
`SB_DayType_FRD_FGD.lua` 目前只負責：
- Pump Day / Dump Day（日級）
- FRD / FGD event day（日級）
- FRD / FGD trade-day candidate（僅候選標記）
- consolidation rectangle（日級 + m15，**目前僅 debug display**）
- DayType 圖上 label（`weekday`、`FRD`、`FGD`、`Trade Day`）
- daytype_bias、event_day_type

本輪**未在 DayType 實作**：
- BOS / BIS / Asia range / sweep / structure state machine
- Entry rule（例如 5m EMA20 entry）
- 正式 scoring 規則（目前分數欄位僅保留為開發中/參考值）
- HUD 顯示管理

## 2) 正式定義（目前程式版）
### Pump Day
同時滿足：
- 當日 `high > 前一日 high`
- 當日 `close` 在當日 range 上半部
- 當日偏多（`close > open`）
- 非 inside day

### Dump Day
同時滿足：
- 當日 `low < 前一日 low`
- 當日 `close` 在當日 range 下半部
- 當日偏空（`close < open`）
- 非 inside day

### FRD event day
同時滿足：
- 前一日是 Pump Day
- 當日 `close < open`
- **本階段不使用 rectangle 當 gating 條件**（rectangle 僅 debug 顯示）

### FGD event day
同時滿足：
- 前一日是 Dump Day
- 當日 `close > open`
- **本階段不使用 rectangle 當 gating 條件**（rectangle 僅 debug 顯示）

### FRD trade-day candidate
同時滿足：
- 前一交易日 `is_frd_event_day = true`
- 本日僅標記候選，等待下游 Entry consume

### FGD trade-day candidate
同時滿足：
- 前一交易日 `is_fgd_event_day = true`
- 本日僅標記候選，等待下游 Entry consume

## 3) consolidation rectangle（程式化定義）
- rectangle **不使用整天 high/low**；改為「close 前 consolidation」區間。
- 先取當日 close 前最後 `rectangle_lookback_bars` 根 15m bar（預設 8）
- 若當日 15m bars 不足 lookback，`has_valid_rectangle = false`
- `rectangle_high` / `rectangle_low`：由上述 lookback 內最高/最低形成
- 至少 `rectangle_min_contained_closes` 根 close 落在區間（預設 6）
- 區間高度限制：`rectangle_height <= ATR(dayatrlen) * max_rectangle_height_atr`（預設 1.2）
- 若最後 4 根出現明顯單邊擴張（位移 > rectangle_height * 0.8），判 invalid
- rectangle 目前只做 debug：
  - stream debug（`has_valid_rectangle`、`rectangle_high`、`rectangle_low`...）
  - 圖上 debug rectangle（`rectangleHigh` / `rectangleLow` 線與框）
- **不作為 FRD/FGD event 或 trade-day candidate gating 條件**

## 4) 對外輸出欄位（可供下游 consume）
- `is_pump_day`
- `is_dump_day`
- `is_frd_event_day`
- `is_fgd_event_day`
- `is_frd_trade_day_candidate`
- `is_fgd_trade_day_candidate`
- `has_valid_rectangle`
- `rectangle_high`
- `rectangle_low`
- `rectangle_height`
- `rectangle_bar_count`
- `rectangle_start_time`
- `rectangle_end_time`
- `daytype_bias`
- `event_day_type`

## 4.1) DayType 可視化輸出（顯示層規格）
- 第一行固定顯示：`weekday`
- 第二行/第三行可顯示：`FRD` / `FGD` / `Trade Day`（同一交易日可同時出現多行）
- 即使當日沒有 FRD / FGD / Trade Day setup，仍需顯示 `weekday`
- 開啟 `debug=true` 時，會額外顯示 rectangle debug：
  - `rectangleHigh`
  - `rectangleLow`

顯示層只 consume `SB_DayType_FRD_FGD.lua` 的正式欄位：
- `is_frd_event_day`
- `is_fgd_event_day`
- `is_frd_trade_day_candidate`
- `is_fgd_trade_day_candidate`

以上僅作為 DayType 顯示來源，**不是第二套邏輯來源**（不得在顯示層重算事件/候選邏輯）。

## 5) 已實作 / 未實作
### 已實作
- Pump Day / Dump Day 判定
- FRD / FGD event day 判定（僅 Pump/Dump + next day close color，不受 rectangle gating）
- FRD / FGD trade-day candidate（僅由前一日 event 轉出）
- rectangle valid / high / low / height / bar_count / start/end time
- DayType 圖上 label：`FRD` / `FGD` / `Trade Day`
- DayType rectangle debug display：`rectangleHigh` / `rectangleLow`

### 未實作（或尚未定版）
- Entry rule（例如 5m EMA20）
- 正式 scoring 規則（目前 `repeated_* / consolidation / three_levels` 僅供開發中參考）
- Structure 層訊號（BOS/BIS/sweep）
- HUD 管理

## 6) 驗證方式（圖上直接可見）
在 DayType indicator 觀察下列 stream：
1. Pump / Dump：
   - `is_pump_day`（1=true, 0=false）
   - `is_dump_day`（1=true, 0=false）
2. Event day：
   - `is_frd_event_day`
   - `is_fgd_event_day`
3. Trade-day candidate：
   - `is_frd_trade_day_candidate`
   - `is_fgd_trade_day_candidate`
4. Rectangle debug：
   - `has_valid_rectangle`
   - `rectangle_high`
   - `rectangle_low`
   - `rectangle_height`
   - `rectangle_bar_count`
   - `rectangle_start_time` / `rectangle_end_time`

另可在圖上按下列步驟檢查 DayType 可視化輸出：
1. 新交易日起始 bar 可見 `weekday`。
2. 有 setup 時，`weekday` 下方可見 `FRD` / `FGD` / `Trade Day`（可多行同日出現）。
3. 開啟 `debug=true` 時，可見 `rectangleHigh` / `rectangleLow` 對應的 rectangle debug 線框。
4. 無 setup 日時，僅 `weekday` 仍持續可見（不應空白）。

以上 stream 在 false 狀態也會輸出 `0`，不會整塊空白，便於直接驗證。

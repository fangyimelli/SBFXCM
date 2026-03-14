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
- DayType 圖上 near-miss label（`FRD?`、`FGD?`，可選擇顯示 fail reason）
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
  - 圖上 debug 可視化（至少 `rectangleHigh` / `rectangleLow` 水平線；debug 模式可額外畫框與標註）
- **不作為 FRD/FGD event 或 trade-day candidate gating 條件，也不作為文字顯示 gating 條件**

## 4) 對外輸出欄位（可供下游 consume）
- `is_pump_day`
- `is_dump_day`
- `is_frd_event_day`
- `is_fgd_event_day`
- `is_frd_trade_day_candidate`
- `is_fgd_trade_day_candidate`
- `is_trade_day`
- `daytype_bias` / `day_bias`
- `event_day_type` / `day_type_code`
- `has_valid_rectangle`（=`rectangle_valid` 概念）
- `rectangle_high`
- `rectangle_low`
- `rectangle_height`
- `rectangle_bar_count`
- `rectangle_start_time`
- `rectangle_end_time`
- `daytype_bias`
- `event_day_type`

## 4.1) DayType 可視化輸出（顯示層規格）
- 顯示層已改為 owner-draw（`Prepare()` 內 `instance:ownerDrawn(true)`，`Draw(stage, context)` 在 `stage == 2` 繪製）
- 第一行固定顯示：`weekday`
- 第二行/第三行可顯示：`FRD` / `FGD` / `Trade Day`（同一交易日可同時出現多行）
- 即使當日沒有 FRD / FGD / Trade Day setup，仍需顯示 `weekday`
- stream 與圖上文字分離：stream 持續輸出供 debug / 下游 consume；圖上文字由 owner-draw 的 `drawText` 直接繪製
- rectangle debug 可視化目前會畫 `rectangleHigh` / `rectangleLow` 水平線；僅作 debug，不作為 FRD/FGD/Trade Day 顯示 gating

顯示層只 consume `SB_DayType_FRD_FGD.lua` 的正式欄位：
- `is_frd_event_day`
- `is_fgd_event_day`
- `is_frd_trade_day_candidate`
- `is_fgd_trade_day_candidate`

Label 顯示：
- `FRD`
- `FGD`
- `Trade Day`
- `FRD?` / `FGD?`（當 near-miss 成立且 `ShowNearMissLabels=true`）

Near-miss 可視化控制參數：
- `ShowNearMissLabels`：是否顯示 `FRD?` / `FGD?`
- `ShowNearMissReasons`：是否在 near-miss 後加上失敗原因，例如 `FRD?(Range)`、`FGD?(CLV/Reclaim)`

---

## 4) 哪些功能屬於 Structure

Structure 目前負責：
- `has_asia_range`
- `has_asia_range_sweep_up`
- `has_asia_range_sweep_down`
- `has_session_sweep`
- `has_bos`
- `has_bearish_bis_below_rectangle`
- `has_bullish_bis_above_rectangle`
- `structure_state`
- `structure_bias`

以及把 DayType SSOT 結果轉成「structure_seen_*」可觀察 stream（只轉述，不重判 day/event）。

---

## 5) 哪些功能屬於 Entry

Entry 層目前正式落地：
- **FRD trade-day**：bearish close back inside EMA20
- **FGD trade-day**：bullish close back inside EMA20

並輸出：
- `frd_entry_ready` / `frd_entry_triggered` / `frd_entry_price`
- `fgd_entry_ready` / `fgd_entry_triggered` / `fgd_entry_price`
- `follow_through_score` / `follow_through_status`

另外有 consume-only stream 用來確認 Entry 正在吃上游：
- `entry_consumed_trade_day`
- `entry_consumed_day_bias`
- `entry_consumed_rectangle_valid`
- `entry_consumed_structure_has_bos`
- `entry_consumed_structure_session_sweep`

---

## 6) 哪些功能只屬於 HUD

HUD 只做文字化狀態展示：
- `hud_flow`
- `hud_daytype_state`
- `hud_structure_state`
- `hud_entry_state`
- `hud_score_state`
- `hud_implementation_status`

用途是讓交易圖上直接看到：
- 現在資料流是否維持 DayType→Structure→Entry→HUD
- 各層目前「已提供 / 部分提供 / 需看上游」

---

## 7) 哪些邏輯禁止放錯地方

- Day/event 定義只能在 **DayType**
- Structure 不可重定義 FRD/FGD/Trade Day
- Entry 不可自己重建 day/event
- HUD 不可重判上游邏輯、不可假裝 entry 已實作

---

## 8) 目前已落地 / 部分落地 / 未落地

### 已落地
- DayType SSOT（Pump/Dump/FRD/FGD/Trade Day + bias + rectangle 輸出）
- DayType label（FRD/FGD/Trade Day）
- rectangle debug 線框與 stream
- Structure 以 DayType 四個輸出 stream 直接串接（`is_trade_day` / `is_frd_event_day` / `is_fgd_event_day` / `day_bias`）並輸出 structure stream
- Entry 的 FRD/FGD trade-day EMA20 entry 規則
- HUD 改為 display-only

### 部分落地
- scoring 仍以可視化/觀察為主，尚未是完整交易管理打分框架

### 未落地
- 完整 TP/SL/trade count/daily slot 的策略管理閉環（目前 HUD 仍偏資訊看板）

---

## 9) 目前 DayType 是否已成為唯一 SSOT

**是。**

目前 FRD/FGD/event/trade-day/day-bias/day-type-code 都由 DayType 生成，
Structure / Entry / HUD 均以 consume 為主，不再各自重建 day/event 定義。

---

## 10) 後續維護規則（強制）

後續只要修改任一 indicator，README 必須同步更新：
- 實際新增了什麼
- 放在哪一層
- 是否違反責任邊界
- 驗證方式如何在圖上看到

---

## 可驗證結果（圖上檢查）

1. **FRD/FGD/Trade Day label**
   - 掛上 `SB_DayType_FRD_FGD.lua`
   - 每個新交易日先看 weekday
   - 有 setup 時可見 `FRD` / `FGD` / `Trade Day`

2. **rectangle debug 可視化**
   - 在 DayType 開啟 `debug=true`
   - 可看到 `rectangleHigh` / `rectangleLow` 文字與線框
   - 同時可看 stream：`has_valid_rectangle`、`rectangle_high`、`rectangle_low`

3. **確認下游不再重判 day/event**
   - Structure 只看 `structure_seen_*` 與 DayType consume 結果
   - Entry 的 ready/trigger 直接依 DayType trade-day + 上游結構狀態
   - HUD 文案明確標示為 display-only

4. **從 README 看責任邊界**
   - 直接對照本檔第 2~7 章
   - 每層「該做/不該做」皆已列出

5. **Structure gate 故障排查（upstream 擋住）**
   - 在 `SB_Structure_Engine.lua` 先看 stream `can_render_structure` 是否為 `0`
   - 若為 `0`，再看 `gate_upstream_trade_day` 是否有值（nil/空值通常代表 upstream DayType 未接線）
   - 同步看 `gate_require_trade_day` 與 `gate_final_can_render`，快速定位是「require gate」還是「upstream 缺失」造成阻擋
   - 若 upstream 暫時未接線，可開啟參數 `allow_render_when_upstream_missing=true` 作為 fallback，避免結構畫面全空

---

6. **shared 載入失敗排查（Entry / HUD）**
   - `SB_Entry_Qualifier.lua` 與 `SB_Trade_Manager_HUD.lua` 都新增 `shared_load_status` 與 `shared_load_error_flag`
   - 正常載入時：
     - `shared_load_error_flag = 0`
     - `shared_load_status` 會顯示 `shared loaded path=...`
   - 載入失敗時：
     - `shared_load_error_flag = 1`
     - `shared_load_status` 會顯示 `shared load failed ... error=...`（保留 Lua 原始錯誤字串）
   - 兩者會先嘗試既有路徑 `Indicators/Custom/3/SB_Playbook_Shared.lua`，再嘗試以腳本自身路徑組出的相對 fallback，降低工作目錄依賴。

---

## 11) 本輪（sandbox only）FRD/FGD 全面重構重點

本輪僅修改 `Indicators/Custom/3/SB_DayType_FRD_FGD.lua`，classic mode / Structure / Entry / HUD 未改。\
核心改動是把 FRD/FGD 拆成四層 SSOT：

- Layer A: Previous Day Impulse Classification  
  `prevIsPump` / `prevIsDump` 由方向 + ATR impulse + CLV 極端 + body ratio 共同決定
- Layer B: Event Day Reversal Classification  
  `basicFrd` / `basicFgd` 由 reversal 當日方向 + event ATR + event CLV 決定
- Layer C: Qualified SB Event  
  `qualifiedFrd` / `qualifiedFgd` 用 reclaim + qualityScore 決定是否加 `+`
- Layer D: Next Day Trade Day  
  `isTradeDay` 僅由前一日是否為 FRD/FGD event 對位，且當日若是 event 不畫 Trade Day

### 新增/調整參數（DayType）
- `impulseAtrMult`（default 1.3）
- `impulseCloseExtreme`（default 0.7）
- `impulseBodyRatioMin`（default 0.5）
- `eventAtrMult`（default 0.6）
- `eventCloseExtreme`（default 0.7）
- `reclaimRatioMin`（default 0.5）
- `qualityscoremin`（延用，僅控制 `+`）

### 顯示與審計
- 正式 label：`FRD` / `FRD+` / `FGD` / `FGD+` / `Trade Day`
- `debug=true` 時增加 near-miss 訊號：`Near FRD` / `Near FGD`
- `state.dayMarks[dateKey]` 追加完整欄位（prev/event 指標、basic/qualified、trade、quality、failReasons）
- 新增 `auditSymmetry()`，debug 下若不對稱會 trace：
  `AUDIT WARNING: FRD/FGD asymmetry detected`

### 可驗證結果（靜態檢查）
1. `basicFrd/basicFgd` 與 `qualifiedFrd/qualifiedFgd` 已分離，quality 不再吞掉 basic event。  
2. `Trade Day` 由 `D` 日 event 對位到 `D+1`，且與 event label 互斥。  
3. FRD/FGD 條件使用對稱 gate（ATR、CLV、reclaim、score 維度一致）。

---

## 11) Structure Engine（本輪更新：SB_Structure_Engine.lua）

### 責任定義（Structure only）
- swing high / swing low 辨識
- BOS up / BOS down 辨識
- CHoCH up / CHoCH down 辨識
- trend state 維護
- 依 DayType gate（Trade Day + Bias Match）過濾有效 structure

### Structure SSOT
`state.structure` 單一真實來源：
- trend
- lastSwingHigh / lastSwingLow
- prevSwingHigh / prevSwingLow
- bosUp / bosDown
- chochUp / chochDown
- structureQualified

顯示層（stream/text）只讀上述 SSOT，不再額外建立「決定行為」的隱藏狀態。

### 參數預設（掛上即用）
- BOS Left = 2
- BOS Right = 2
- Use Close For BOS = Yes
- Enable CHoCH = Yes
- Require Trade Day = Yes
- Require Bias Match = Yes
- Ignore Counter Bias Break = Yes
- Show Swing Levels = Yes
- Show BOS Text = Yes
- Show CHoCH Text = Yes
- Show Trend Text = Yes
- Debug = No

### 顯示方式（FXCM 可見）
- Swing levels：`lastSwingHigh` / `lastSwingLow` line stream
- BOS/CHoCH/TREND：採 `instance:createTextOutput(...)` + `TextOutput:set(...)`
- BOS↑：事件 bar 上方
- BOS↓：事件 bar 下方
- CHoCH↑：事件 bar 上方
- CHoCH↓：事件 bar 下方
- TREND UP/DOWN：最新 bar 附近（上/下方）

### 可驗證結果
- 掛上 `SB_Structure_Engine.lua` 後，不需手動調參即可直接顯示 swing level + BOS/CHoCH/TREND 文字。
- 文字會綁定事件 bar 價格附近，不會固定擠在左上角。

## 2026-03-13 結構引擎（Structure Engine）正式輸出收斂

`SB_Structure_Engine.lua` 已改為只輸出三種正式資訊（且必須經過 trade-day gate）：
1. `Consolidation`
2. `BIS`（只限向下跌破 consolidation low）
3. `Session High / Session Low`

### Structure Engine 責任邊界（本輪）
- Structure 不再輸出 `BOS/CHoCH/swing/trend/bias` 等正式文字。
- Structure 不自行重建 Trade Day；改為直接 consume DayType output stream：
  - `daytype_trade_day_stream`（接 `is_trade_day`）
  - `daytype_frd_event_stream`（接 `is_frd_event_day`）
  - `daytype_fgd_event_stream`（接 `is_fgd_event_day`）
  - `daytype_bias_stream`（接 `day_bias`）
- 預設主流程是 upstream stream；`manualoverride=true` 僅供除錯，才會使用手動參數：
  - `upstreamistradeday` / `upstreamisfrd` / `upstreamisfgd` / `upstreambias`
- 正式渲染統一走單一 gate：`canRenderStructure = isTradeDay`。

### Consolidation 判定（程式化）
- 建立最小 bars 視窗（預設 8）
- 區間寬度需滿足：
  - `consolidationRange <= ATR(14) * maxconsolidationatrmult`（預設 1.0）
- 區間漂移需受限（避免趨勢段誤判）：
  - `abs(close_now - close_start) <= consolidationRange * maxdriftratio`（預設 0.45）
- 成立後進入 active consolidation state（含 id/high/low/start/lastInside/active/brokenDown）。

### BIS 判定（單次事件）
- 觸發條件採用穩定版本：`close < consolidationLow`。
- 只允許向下 break（不做向上 break 顯示）。
- 同一 consolidation id 只觸發一次，內建去重：`lastBisConsolidationId`。

### Session High / Session Low
- 在 BIS 觸發後啟動 session state。
- 後續只維護目前有效的一組 `session high / session low`。
- 圖上只標必要更新，不把所有歷史 session levels 全塞滿。

### 可驗證（圖上）
- Trade Day = false：正式圖面不顯示 Consolidation/BIS/Session High/Low。
- Trade Day = true 且進入箱型：只見 consolidation 邊界與單一 `Consolidation` 文字。
- 向下有效破位：只在觸發 K 棒看到一次 `BIS`。
- BIS 之後：可持續看到 `Session High / Session Low` 更新。


### 平台相容策略（Structure upstream 參數）
- `SB_Structure_Engine.lua` 在 `Init()` 會先檢查 `indicator.parameters.addSource` 是否可用：
  - 可用：註冊 `daytype_trade_day_stream/daytype_frd_event_stream/daytype_fgd_event_stream/daytype_bias_stream`（stream 直連模式）。
  - 不可用：不註冊 `addSource` 類型參數，改走既有手動參數作為 fallback。
- `Prepare()` 與 `Update()` 不再假設 upstream 一定是 stream handle，會先做型態/可索引檢查。
- 若 upstream 不是可索引 stream（例如平台只提供基本參數型態），會自動 fallback 到：
  - `upstreamistradeday`
  - `upstreamisfrd`
  - `upstreamisfgd`
  - `upstreambias`
- `manualoverride=true` 仍保留原本語意（強制手動值）；`manualoverride=false` 時若 stream 不可用，會自動採用 fallback 手動參數（平台相容模式）。

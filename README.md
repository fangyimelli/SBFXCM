# SB FXCM 四層架構（目前真實狀態）

本專案目前把 4 隻 indicator 的資料流固定成單一路徑：

`SB_DayType_FRD_FGD.lua -> SB_Structure_Engine.lua -> SB_Entry_Qualifier.lua -> SB_Trade_Manager_HUD.lua`

這份 README 只描述「現在程式真的在做的事」，不寫理想藍圖。

---

## 1) 系統資料流總覽

1. **DayType** 先產生 day/event 定義（唯一來源，SSOT）
2. **Structure** 只吃 DayType 的結果，再加上自身的 Asia/Sweep/BOS 狀態
3. **Entry** 只吃 DayType + Structure，做進場限定規則
4. **HUD** 只做顯示，不代管上游判定

---

## 2) 四隻 indicator 的責任分工

### A. `Indicators/Custom/3/SB_DayType_FRD_FGD.lua`
唯一責任：
- Pump Day / Dump Day
- FRD / FGD event day
- Trade Day（由前一日 event 轉出）
- day bias / day type code
- rectangle（目前 debug + 輸出，不做 hard gate）
- Day-level label / stream / debug

### B. `Indicators/Custom/3/SB_Structure_Engine.lua`
唯一責任：
- Asia range
- sweep
- BOS
- BIS 與 structure state stream

並且只 consume DayType 結果（FRD/FGD/trade-day/bias/rectangle），不重建 day/event 定義。

### C. `Indicators/Custom/3/SB_Entry_Qualifier.lua`
唯一責任：
- entry qualifier
- FRD/FGD trade-day EMA20 close-back-inside 觸發
- follow-through stream

只 consume 上游 DayType + Structure，不另建 day/event。

### D. `Indicators/Custom/3/SB_Trade_Manager_HUD.lua`
唯一責任：
- HUD 顯示
- 彙整「上游提供了什麼、目前哪層已接線」

不做 FRD/FGD 重判、不做 structure 重判、不代管 entry trigger。

---

## 3) 哪些功能屬於 DayType

目前 DayType 正式輸出（供下游消費）：
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

Label 顯示：
- `FRD`
- `FGD`
- `Trade Day`

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
- Structure consume DayType 並輸出 structure stream
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

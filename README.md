# SB FRD/FGD 四層整合（現況版）

> 本 README 只描述「目前程式真的有做的事」。
> 資料流固定為 **DayType -> Structure -> Entry -> HUD**，HUD 僅顯示。

## 1) 四隻 indicator 總覽
- `SB_DayType_FRD_FGD.lua`：日級定義（Pump/Dump、FRD/FGD event day、trade-day candidate、rectangle、day/event score）。
- `SB_Structure_Engine.lua`：結構確認（Asia range、session sweep、BOS、BIS、structure score）。
- `SB_Entry_Qualifier.lua`：5m 進場條件（FRD/FGD EMA20 close back inside + follow-through score）。
- `SB_Trade_Manager_HUD.lua`：純顯示與彙整（wired/not wired、implemented/not implemented）。

## 2) 責任分工（強制邊界）
- DayType 不做 BOS/BIS/entry/HUD。
- Structure 不重定義 Pump/Dump/FRD/FGD/trade-day。
- Entry 不重建 day-type 或 rectangle。
- HUD 不做判定，只做 display。

## 3) 每隻 indicator 目前在做什麼
### DayType
- 以 D1 定義 Pump Day / Dump Day。
- 以 D1 + m15 定義 FRD/FGD event day 與 rectangle。
- 輸出 trade-day candidate（以前一日 event day 為基礎）。
- 輸出 day/event score。

### Structure
- 只做 Asia range、sweep、BOS、BIS。
- 目前有 score（FrontsideBackside、TrappedLongs、TrappedShorts）。
- 目前未直接讀取 DayType stream（屬部分接線）。

### Entry
- 僅在 5m close 判定。
- FRD：bearish close back inside EMA20。
- FGD：bullish close back inside EMA20。
- 輸出 ready/triggered/price/follow-through score。

### HUD
- 僅顯示接線狀態與落地狀態。
- 目前明確顯示 `not wired / not implemented / display only`。

## 4) 每隻 indicator 的輸入 / 輸出 / 依賴
- DayType：輸入 `source + D1 + m15`；輸出 Pump/Dump、event/trade candidate、rectangle、bias、score；依賴 `SB_Playbook_Shared.lua`。
- Structure：輸入 `source + m15 + D1`；輸出 Asia/Sweep/BOS/BIS/structure score；依賴 `SB_Playbook_Shared.lua`。
- Entry：輸入 `source + D1 + EMA20`；輸出 FRD/FGD entry ready/triggered + follow-through；依賴 `SB_Playbook_Shared.lua`。
- HUD：輸入 `source`；輸出字串 HUD stream；依賴 `SB_Playbook_Shared.lua`（目前只做顯示狀態）。

## 5) 正式定義（目前程式版）
- Pump Day：`high > 前一日 high`、`close 在當日 range 上半`、`close > open`、且不是 inside day。
- Dump Day：`low < 前一日 low`、`close 在當日 range 下半`、`close < open`、且不是 inside day。
- FRD event day：前一日 Pump Day + 當日紅K + 有效 rectangle。
- FGD event day：前一日 Dump Day + 當日綠K + 有效 rectangle。
- FRD trade-day candidate：前一日 FRD event day。
- FGD trade-day candidate：前一日 FGD event day。

## 6) consolidation rectangle 程式定義
- 偵測窗：event day 最後 `8` 根 15m。
- 至少 `6` 根 close 落在區間內。
- 區間高度需小於 `ATR * 1.2`。
- 若最後 4 根呈現明顯單邊擴張則視為無效。
- 參數：
  - `rectangle_lookback_bars=8`
  - `rectangle_min_contained_closes=6`
  - `max_rectangle_height_atr=1.2`

## 7) 功能分佈（放在哪一層）
- DayType：Pump/Dump、event day、trade-day candidate、rectangle、day/event score。
- Structure：Asia/sweep/BOS/BIS、FrontsideBackside、Trapped score。
- Entry：FRD/FGD EMA20 entry、FollowThroughScore。
- HUD：顯示與狀態標籤。

## 8) 尚未完整落地
- Structure 尚未直接 consume DayType stream（目前為部分落地）。
- HUD 尚未接到上游 stream（故明確顯示 `not wired`）。
- DayType 的 repeated push / three-level 為簡化代理。

## 9) 不能放錯 indicator 的功能
- 不能把 entry gate 寫到 HUD。
- 不能把 day-type 定義寫到 Structure/Entry/HUD。
- 不能把結構判定寫到 Entry。

## 10) 修改前 FRD/FGD 過多的原因
- 舊版在 Structure/Entry/HUD 各自存在重複或替代邏輯（多點重算、語意混雜）。

## 11) 修改後改善
- DayType 統一定義日級語意。
- Entry 改為專職 FRD/FGD 的 EMA20 5m close entry。
- HUD 改為只顯示，不再冒充邏輯來源。

## 12) 驗證方式
1. DayType：看 `is_pump_day / is_dump_day / is_frd_event_day / is_fgd_event_day / is_frd_trade_day_candidate / is_fgd_trade_day_candidate / has_valid_rectangle / rectangle_high / rectangle_low`。
2. Structure：看 `has_asia_range / has_asia_range_sweep_up / has_asia_range_sweep_down / has_bos / has_bearish_bis_below_rectangle / has_bullish_bis_above_rectangle`。
3. Entry：看 `frd_entry_ready + frd_entry_triggered`（bearish close back inside EMA20）與 `fgd_entry_ready + fgd_entry_triggered`（bullish close back inside EMA20）。
4. HUD：看 `wired/not wired`、`implemented/not implemented`、`display only`。

## 13) 後續維護規則
- 未來只要改動四隻 indicator 任一層，README 必須同步更新且以實作現況為準。

---

## 統一時間窗（NY）
由 `SB_Playbook_Shared.lua` 提供統一函式：
- `is_in_asia_window`：19:00-23:00
- `is_in_london_window`：01:00-05:00
- `is_in_newyork_window`：07:00-11:00
- `is_in_any_timing_window`
- `is_near_window_open`：開窗後 15 分鐘或前 3 根 5m

## Playbook 明文 vs 程式近似
- 明文規則：責任分層、DayType->Structure->Entry->HUD、5m close 才可 entry、session 視窗。
- 程式近似：Pump/Dump 數學條件、rectangle 數學條件、three-level/strike-zone、trapped/frontside-backside 打分。

## 限制（必讀）
- rectangle 為程式化近似，不是 playbook 唯一官方公式。
- Pump/Dump 為程式化近似，不是 playbook 唯一官方公式。
- three levels / strike zone 是程式化代理條件。
- trapped traders / frontside-backside 是程式化代理條件。

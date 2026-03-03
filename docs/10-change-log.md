# 10-change-log

## 2026-03-03
- 新增 FXCM Indicore 單檔指標：`Indicators/Custom/3/SB_Full_Manual_Workflow_FXCM.lua`。
- 完成平台相容性修正：
  - `getHistory` 改為固定參數順序呼叫。
  - `addStream` 第 5 參數固定為 `firstPeriod(number)`。
  - Stream/Parameter ID 全改用英數字。
- 建立 5m/15m/D1 timestamp 對齊 map，避免跨週期 index 錯位。
- 實作 Focus mode（`focusdate` + NY 09:30 anchor）與 debug stream。
- 實作 DayType bias（FGD/FRD/TradeDay）與核心狀態機：Asia->Sweep->BOS->FVG->Retest->Blue1/2/3。
- 補上 EMA/ATR fallback（避免 built-in 或 history 欄位不一致導致失敗）。

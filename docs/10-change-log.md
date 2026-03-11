# 10-change-log

## 2026-03-11
- 文件層級完成四檔拆分規格（DayType / Structure / Entry / HUD），並補齊建議載入順序與欄位責任邊界。
- 狀態機敘述統一為單一路徑：`DayType -> Structure -> Entry`；HUD 僅做顯示與診斷，不再承擔 gate 決策。
- gate 決策文件化整併：
  - 優先順序統一為 `focus 視窗 -> trade day -> session/structure -> entry/score -> daily max trades`。
  - `DEBUG` 編碼語義固定（0/-1/-2/-9），避免多處覆寫造成診斷不一致。
- focus 對齊規則補充：
  - 以 NY 09:30 為 anchor。
  - 加入跨週期 map（5m/15m/D1）對齊時的驗證步驟與失敗判讀。
- 新增回歸規則文件 `docs/11-regression-rules.md`，要求每一個 bug fix 對應一條可重跑規則。

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

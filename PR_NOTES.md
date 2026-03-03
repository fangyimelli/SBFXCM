# PR Notes

## Completed
- [x] 建立可載入的單檔 FXCM 指標實作。
- [x] 修正平台相容性問題（getHistory/addStream/id 規則）。
- [x] 新增跨週期 timestamp 對齊工具（5m/15m/D1）。
- [x] 實作 DayType bias 與 Focus mode 主要流程。
- [x] 實作 Asia/Sweep/BOS/FVG/Retest/Blue1/2/3 狀態機。
- [x] 實作 score gating、dailyMaxTrades、HUD/debug streams。
- [x] 更新 README 與 changelog。

## TODO / Follow-ups
- [ ] `liveGradeMode=Auto` 目前為保留參數，尚未完整自動降級細則。
- [ ] `allowEntryAfterSession`、`mrnBlock` 目前保留參數，尚未加上完整交易時段阻擋策略。
- [ ] `lineLifecycle` 僅保留輸入；尚未做多策略線段生命週期裁切。
- [ ] Pine label/box 視覺元素以 FXCM streams 等價，不提供原生 label/box。

## Known Limits
- Focus mode 為單日 anchor 視窗，需先載入足夠歷史資料。
- 部分 Pine 細節（例如 reclaimBars 的更細粒度）以 FXCM 可行邏輯近似。

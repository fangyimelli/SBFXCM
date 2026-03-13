# Summary
- 重構 `Indicators/Custom/3/SB_Structure_Engine.lua`，正式輸出收斂為 `Consolidation -> BIS -> Session High/Session Low`。
- 移除正式圖面舊結構標示（BOS/CHoCH/swing/trend/bias/Break in Structure 全名）。
- 建立 consolidation SSOT state，並把 BIS 改為僅限「向下跌破 consolidation low」且同一 consolidation 只觸發一次。
- 導入單一 trade-day 渲染 gate：`canRenderStructure = isTradeDay`，所有正式 render 都必須通過。
- 新增上游 day type 串接 stub input（`upstreamistradeday/isfrd/isfgd/bias`），避免 structure 自行重建 Trade Day 判定。

# Validation
- [x] `rg -n "BOS|CHoCH|Break in Structure|swing|TREND" Indicators/Custom/3/SB_Structure_Engine.lua`
- [x] `lua -p Indicators/Custom/3/SB_Structure_Engine.lua`
- [x] `git diff -- Indicators/Custom/3/SB_Structure_Engine.lua README.md docs/10-change-log.md PR_NOTES.md`

# Notes
- 目前 FXCM Indicore 無直接 cross-indicator runtime 讀值介面，故先以上游 stub input 串接 `isTradeDay/isFrd/isFgd/bias`；後續可改成正式共享資料管線（仍維持 SSOT 在 DayType）。

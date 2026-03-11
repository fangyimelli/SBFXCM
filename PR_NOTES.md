# Summary
- 修正 `SB_Full_Manual_Workflow_FXCM.lua` 在 FXCM Trading Station / Marketscope 2.0 的兩個匯入錯誤：參數 id 不存在與 Init 外呼叫 `indicator`。
- 依需求退回最小可載入結構，只保留 `Init()/Prepare()/Update()/ReleaseInstance()` 與 3 個基礎參數。
- 建立最小 state/gate SSOT：`S.gate`、`S.cananswer`、`S.lastrule`，讓可回應狀態由明確 state 決定。

# Validation
- [x] `rg -n "indicator\.|instance.parameters\.|profile.parameters\." Indicators/Custom/3/SB_Full_Manual_Workflow_FXCM.lua`
- [x] `lua -p Indicators/Custom/3/SB_Full_Manual_Workflow_FXCM.lua`
- [x] `git diff -- Indicators/Custom/3/SB_Full_Manual_Workflow_FXCM.lua README.md docs/10-change-log.md docs/11-regression-rules.md PR_NOTES.md`

# Notes
- 本次未擴充策略邏輯；目標為語法與結構修正，先確保可匯入。

# SB Full Manual Workflow (FXCM Indicore Lua)

## 檔案與安裝位置
- 指標檔案：`Indicators/Custom/3/SB_Full_Manual_Workflow_FXCM.lua`
- 建議安裝到 Marketscope 使用者指標資料夾（Custom/3 分層可自訂）：
  - `%APPDATA%\Candleworks\FXTS2\Profiles\Default\Indicators\Custom\3\`

## 載入步驟
1. 開啟 Marketscope 2.0 圖表。
2. `Add Indicator` -> 找到 `SB Full Manual Workflow FXCM`。
3. 建議先在 `m5` 圖上使用，並保持足夠歷史資料（至少近 30 天）。

## 時區建議
- Focus mode 與 DayType 是用 **NY 09:30 anchor** 設計。
- 建議圖表時區以 New York / EST-EDT 為準，避免日期偏移。

## Focus Mode 用法
- 開啟 `focusmode`。
- 在 `focusdate` 輸入 `YYYY-MM-DD`（例：`2025-01-19`）。
- 指標會只顯示該日期區間（以該日 09:30 為錨點開始）之 HUD 與狀態輸出。
- 若該日資料不足，請增加歷史資料範圍並重新載入指標。

## Pine -> FXCM 參數對照
- Session: `nySession`, `asiaSession`, `prefilterLock`, `allowEntryAfterSession`
- Grade: `liveGradeMode`, `manualGrade`
- DayType: `requireSbDayType`, `dayMoveAtrLen`, `dumpPumpMinAtrMult`, `tradeDayOnly`
- Sweep: `sweepMinTicks`, `sweepAtrLen`, `sweepMinAtrMult`, `sweepReclaimBars`
- BOS: `bosSwingLeft`, `bosSwingRight`, `bosConfirmBars`, `bosMinAtrMultA`, `bosMinAtrMultAplus`
- FVG: `useFvg`, `fvgLookbackBars`, `fvgExpireMinutes`, `fvgMinAtrMultA`, `fvgMinAtrMultAplus`
- Retest: `retestMode`, `retestBufferAtrMultA`, `retestBufferAtrMultAplus`, `entryExpireMinutes`
- Blue: `requireEma20ForBlue3`, `reactionWindowBars`, `requireReclaimForBlue2`, `enableRejectForBlue2`, `rejectWickRatioMin`, `rejectBodyRatioMax`, `cooldownBlue1`, `cooldownBlue2`, `cooldownBlue3`, `consumeSlotOn`
- Targets/Risk: `drawTargetLines`, `targetPips`, `slMode`, `slPipsDefault`, `slPipsMaxHint`, `slBufferPips`, `lineLifecycle`
- Score/Display: `scoreEnabled`, `scoreThresholdA`, `scoreThresholdAplus`, `dailyMaxTrades`, `minScoreToDisplay`
- HUD/Debug: `showhud`, `debugMode`, `showDaytypeLabels`

## 已知平台相容性處理
- `host:execute("getHistory", instrument, timeframe, first, count)` 使用固定參數順序。
- `instance:addStream(id, type, name, shortName, firstPeriod)` 第 5 參數固定為 number。
- stream id 與 parameter id 全部採英數字（避免底線/符號）以提升解析相容性。
- 增加 safe stream getter + EMA/ATR fallback 計算，降低不同 history 欄位命名造成的失敗。

## README Removed/Deprecated Log
- 本次無移除檔案；無 deprecated API 對外介面。

## Debug / SSOT 變更紀錄
- SSOT: `Indicators/Custom/3/SB_Full_Manual_Workflow_FXCM.lua` 作為唯一交易狀態機實作來源。
- Debug: 透過 `DEBUG` stream（0/-1/-2/-9）與 `debugMode` alert message 輸出 focus/day-limit/block 訊息。

## 常見錯誤排查
1. **Add Indicator 時跳錯**：確認檔案路徑與檔名正確，並重啟 Marketscope。
2. **Focus day 顯示不到資料**：提高圖表載入歷史資料筆數，或確認輸入日期格式 `YYYY-MM-DD`。
3. **訊號過少**：降低 `minScoreToDisplay`、關閉 `requireSbDayType` 或放寬 `scoreThreshold`。
4. **日內兩筆後無訊號**：可能已達 `dailyMaxTrades`，請看 HUD `DEBUG=-1`。

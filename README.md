# SB Full Manual Workflow (FXCM Indicore Lua)

## 四檔拆分與安裝路徑
> 本專案以 `SB_Full_Manual_Workflow_FXCM.lua` 為 SSOT；四檔為部署與維護層級規劃，用於文件化拆分責任、載入順序與回歸驗證。

| 檔名 | 角色 | 建議安裝路徑 |
|---|---|---|
| `SB_DayType_FXCM.lua` | DayType / bias / trade-day gating | `%APPDATA%\\Candleworks\\FXTS2\\Profiles\\Default\\Indicators\\Custom\\3\\` |
| `SB_Structure_FXCM.lua` | Asia / Sweep / BOS / FVG 結構層 | `%APPDATA%\\Candleworks\\FXTS2\\Profiles\\Default\\Indicators\\Custom\\3\\` |
| `SB_Entry_FXCM.lua` | Retest / Blue1-3 / score / slot 消耗 | `%APPDATA%\\Candleworks\\FXTS2\\Profiles\\Default\\Indicators\\Custom\\3\\` |
| `SB_HUD_FXCM.lua` | HUD / debug / overlay stream 呈現 | `%APPDATA%\\Candleworks\\FXTS2\\Profiles\\Default\\Indicators\\Custom\\3\\` |

## 建議載入順序（必照）
1. `DayType`
2. `Structure`
3. `Entry`
4. `HUD`

> 依序載入可避免下游模組讀取到未初始化 stream/state 的情況（尤其在 focus mode 與跨週期 map 初始化時）。

## 每檔欄位對照（parameters / streams / state）

### 1) DayType
- **Parameters**
  - `requireSbDayType`, `dayMoveAtrLen`, `dumpPumpMinAtrMult`, `mrnBlock`, `tradeDayOnly`
- **Streams**
  - `TRADEDAY`, `INNY`, `DEBUG`
- **State**
  - `currentDayKey`, `blockedReason`, `focusStart`, `focusEnd`, `focusKey`

### 2) Structure
- **Parameters**
  - `asiaSession`, `prefilterLock`, `sweepMinTicks`, `sweepAtrLen`, `sweepMinAtrMult`, `sweepReclaimBars`
  - `bosSwingLeft`, `bosSwingRight`, `bosConfirmBars`, `bosMinAtrMultA`, `bosMinAtrMultAplus`
  - `useFvg`, `fvgLookbackBars`, `fvgExpireMinutes`, `fvgMinAtrMultA`, `fvgMinAtrMultAplus`
- **Streams**
  - `ASIAH`, `ASIAL`, `BOSLV`, `FVGU`, `FVGL`, `HASBOS`, `FVGMIT`
- **State**
  - `sessionState(0~5)`, `asiaHigh`, `asiaLow`, `sweepUsed`, `sweepDir`, `sweepTime`
  - `bosDir`, `bosLevel`, `bosTime`, `fvgU`, `fvgL`, `fvgTime`, `fvgMit`

### 3) Entry
- **Parameters**
  - `retestMode`, `retestBufferAtrMultA`, `retestBufferAtrMultAplus`, `entryExpireMinutes`
  - `requireEma20ForBlue3`, `reactionWindowBars`, `requireReclaimForBlue2`, `enableRejectForBlue2`
  - `rejectWickRatioMin`, `rejectBodyRatioMax`, `cooldownBlue1`, `cooldownBlue2`, `cooldownBlue3`, `consumeSlotOn`
  - `scoreEnabled`, `scoreThresholdA`, `scoreThresholdAplus`, `weightNy`, `weightSweep`, `weightBos`, `weightFvg`, `weightEntry`, `dailyMaxTrades`, `minScoreToDisplay`
- **Streams**
  - `RETU`, `RETL`, `ENTRY`, `TP`, `SL`, `BLUE1`, `BLUE2`, `BLUE3`, `BLUE3S`, `SCORE`
- **State**
  - `retU`, `retL`, `retTime`, `dailyTrades`, `blue1Last`, `blue2Last`, `blue3Last`

### 4) HUD
- **Parameters**
  - `showhud`, `debugMode`, `showDaytypeLabels`, `focusmode`, `focusdate`
- **Streams**
  - `DEBUG`（0/-1/-2/-9）與必要代理資訊 stream
- **State**
  - `inited`, `map5to15`, `map5toD`（時間對齊）

## Removed / Deprecated Log
- `SB_Full_Manual_Workflow_FXCM.lua`（舊單檔部署形式）標記為 **legacy-compatible**，文件層級改以四檔流程管理。
- 舊邏輯中重複 gate 判斷路徑已合併為單一路徑（DayType -> Structure -> Entry），避免互斥條件在不同區塊重複覆寫。
- `lineLifecycle` 仍保留為相容參數，但目前僅作設定保留，不作策略線段回收控制（deprecated behavior）。

## SSOT 與 debug 欄位變更紀錄
- **SSOT 政策**：交易狀態機規則以單一流程定義（DayType -> Structure -> Entry），HUD 僅消費上游結果，不回寫策略狀態。
- **Debug 欄位**：
  - `DEBUG = 0`：可評估/可交易
  - `DEBUG = -1`：達到 `dailyMaxTrades`
  - `DEBUG = -2`：gate block（非交易日、focus 不匹配或其他阻擋）
  - `DEBUG = -9`：focus mode 視窗外
- `debugMode` alert 訊息對齊為 gate/block 優先，避免同 bar 多訊息互相覆蓋。

## 載入驗證步驟
1. 將四檔放入同一路徑 `%APPDATA%\\Candleworks\\FXTS2\\Profiles\\Default\\Indicators\\Custom\\3\\`。
2. 重啟 Marketscope 2.0，依序加入 `DayType -> Structure -> Entry -> HUD`。
3. 在 m5 圖確認 `TRADEDAY/INNY/HASBOS/SCORE/DEBUG` streams 有輸出。
4. 開啟 `focusmode=true` 並指定 `focusdate=YYYY-MM-DD`，確認視窗外 `DEBUG=-9`。
5. 連續模擬訊號直到達 `dailyMaxTrades`，確認 `DEBUG=-1` 且不再新增 Blue3。
6. 關閉 `requireSbDayType` 重新比對訊號數，確認 gate 解除後僅由結構與入場條件決策。

## 已知限制
- `liveGradeMode=Auto` 仍為保留參數，未完成完整自動降級細則。
- `allowEntryAfterSession`、`mrnBlock` 僅部分接線，尚未覆蓋完整時段封鎖策略。
- `lineLifecycle` 僅保留輸入，未落實 NextBlue3/SessionEnd/DayEnd 線段回收。
- Pine 的 label/box 視覺元素以 FXCM streams 替代，不提供 1:1 圖元渲染。
- Focus mode 依賴足夠歷史資料；資料不足時可能誤判為無訊號日。

## 回歸規則（摘要）
完整清單見 `docs/11-regression-rules.md`，每次修正 bug 需新增「Bug-ID -> 規則 -> 驗證命令/步驟 -> 預期結果」一條對應。

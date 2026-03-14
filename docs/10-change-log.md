# 10-change-log

## 2026-03-14
- 新增 `Indicators/Custom/3/SB_Structure_Engine_Simple.lua` 作為 Simple 入口：僅暴露少量參數（`profile` + trade-day gate/fallback），正式輸出維持 `Consolidation`、`BIS`、`Session High/Low`。
- Simple 版 upstream 策略固定為「優先讀 DayType stream，stream 不可用時自動 fallback」，不要求手動填 upstream*。
- `Indicators/Custom/3/SB_Structure_Engine.lua` 保留為 Engineering/Debug 入口，維持完整參數供診斷與平台相容驗證。
- README 載入指引改為「一般使用者先用 Simple、診斷才用 Engineering」，並明確寫入責任邊界：debug 參數不得回加到 Simple 版。


## 2026-03-14
- `Indicators/Custom/3/SB_Structure_Engine.lua` 移除 upstream 參數與 stream 連線流程（`daytype_*_stream`、`manualoverride`、`upstream*`）。
- Structure DayType 控制簡化為本地單次設定：`istradeday` + `daymode(-1=FRD,1=FGD)`。
- `Update()` gate 改為只依賴 `requiretradeday` 與 `istradeday`，不再做 upstream 相容分支。
- `Indicators/Custom/3/SB_Structure_Engine.lua` 新增 upstream 參數相容層：`Init()` 先檢查 `indicator.parameters.addSource` 是否存在，存在才註冊 `daytype_*_stream`。
- `Prepare()` 新增 stream-like 檢查，避免把非 stream 型態誤判為可讀 upstream handle。
- `Update()` upstream 讀值改為安全讀取 + 型態判斷，避免對非 stream 直接做 `up.xxx[period]` 索引。
- 當平台不支援 `addSource` 或 upstream 不是 stream 時，`manualoverride=false` 也會自動 fallback 到 `upstreamistradeday/upstreamisfrd/upstreamisfgd/upstreambias`。
- README 補充「平台相容策略（Structure upstream 參數）」說明，明確定義 stream 模式與 fallback 模式的切換規則。

## 2026-03-11
- 修正 `SB_Full_Manual_Workflow_FXCM.lua` 匯入錯誤：`function at line XXX has more than 60 upvalues`。
- 結構重整為單一真實來源（SSOT）容器：
  - `S`：策略 state（asia/sweep/bos/fvg/retest/blue/score/block/trade count/entry-tp-sl）
  - `H`：history + map + focus
  - `T`：stream handles
  - `I`：EMA/ATR cache
- `Update()` 改為 table-based state 存取，移除大量獨立 local strategy state upvalue 捕捉。
- 新增判定紀錄欄位 `S.judgeTrace` 與 HUD/debug 對齊顯示（可回答/阻擋狀態）。
- 補充狀態機狀態表到 README，明確由 state/gate 決定行為，避免 UI 直接決定系統行為。
- 新增回歸規則 `RG-009`（上值限制）確保後續不回歸。
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

## 2026-03-11 - FXCM indicator 載入錯誤修正（最小可載入版）
- 修正 `SB_Full_Manual_Workflow_FXCM.lua` 的結構，保留單一 `Init()`，且 `indicator.*` 呼叫全部限制於 `Init()` 內。
- 參數 SSOT 統一為 `debug/dayatrlen/dumppumpatrm`，`Prepare()` 讀取 id 與 `Init()` 宣告完全一致。
- 移除與本次目標無關之策略邏輯（getHistory/addStream/EMA/ATR/FVG/Blue/score/focus 等），避免匯入時參數與平台 API 互斥。
- 新增最小狀態表欄位：`S.gate`、`S.cananswer`、`S.lastrule`，用於顯式 gate 狀態與每次輸入判定紀錄。

## 2026-03-13
- 修正 `SB_DayType_FRD_FGD.lua` 當日 D1 快取凍結問題：最後一個 D1 交易日改為「OHLC/時間戳變動即重算」，避免 FRD/FGD 標籤不更新或消失。
- 新增 `day_cache_meta`（open/high/low/close/ts）以判斷 active day 是否需重建 `day_record`。
- 強化 owner-draw 重繪機制：
  - `now_clock_millis()` 優先使用 `getServerTime`（可用時），降低 `os.clock()` 對 UI 節流不穩定的影響。
  - active day 期間加入 `forceRefresh` 條件，避免僅靠節流造成標籤刷新延遲。
  - debug 模式新增 refresh 觸發與失敗原因輸出（newDay/dayChanged/throttled/force）。
- 重構 `Indicators/Custom/3/SB_Structure_Engine.lua` 正式輸出主線為 `Consolidation -> BIS -> Session High/Session Low`。
- 正式圖面移除所有舊結構術語輸出：`BOS`、`CHoCH`、`Break in Structure`、`swing`、`trend`、`bias` 等 label。
- 新增 consolidation state SSOT（`id/high/low/startBar/lastInsideBar/active/brokenDown`），並以此作為 BIS 唯一來源。
- BIS 改為僅支援「向下跌破 consolidation low」且單次觸發去重（同一 consolidation id 只觸發一次）。
- 新增 trade-day 統一 gate：`canRenderStructure = isTradeDay`（由 DayType upstream stream `is_trade_day` 決定），所有正式渲染皆經過同一 gate。
- 新增 DayType upstream 直連參數：`daytype_trade_day_stream`、`daytype_frd_event_stream`、`daytype_fgd_event_stream`、`daytype_bias_stream`，直接讀取 `is_trade_day/is_frd_event_day/is_fgd_event_day/day_bias`。
- 新增 `manualoverride`（debug only）：僅在手動除錯時才回退到 `upstreamistradeday/upstreamisfrd/upstreamisfgd/upstreambias`，避免誤認為已自動串接。
- Session High/Low 改為 BIS 後第二層輔助標示，維持低噪音（只顯示目前有效 session levels 與更新事件）。
- debug mode 保留（預設關閉），僅觀察內部狀態，不繞過正式渲染 gate。

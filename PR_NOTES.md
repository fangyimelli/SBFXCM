# PR Notes

## 衝突邏輯整併 / 淘汰決策

### 1) Gate 判斷多點覆寫 -> 保留單一路徑
- **決策**：保留單一路徑 `DayType -> Structure -> Entry`，移除（淘汰）文件中「HUD 可再次判斷可交易」的暗示。
- **理由**：HUD 若介入策略決策，會產生同一根 bar 出現互斥結論的問題，不利除錯與回歸。

### 2) Focus 與 TradeDay 互相覆蓋 -> 保留 focus 優先
- **決策**：focus 視窗外直接 `DEBUG=-9`，不再下探 tradeDay/session。
- **理由**：可快速區分「資料/日期問題」與「策略條件問題」，減少誤判。

### 3) 重複 score/gate 檢查 -> 合併為 Entry 端最終裁決
- **決策**：保留 Entry 端最終 score 與日內次數判斷；上游僅提供結構事實（BOS/FVG/Retest）。
- **理由**：避免分散在多段的 threshold 不一致造成回測偏差。

### 4) Legacy 單檔 vs 四檔文檔 -> 保留 SSOT、淘汰單檔敘事
- **決策**：保留單檔作為相容部署與 SSOT；淘汰 README 的「只需單檔」說明，改為四檔載入流程規格。
- **理由**：實務維護需模組責任清楚，同時保留現有部署不破壞。

## 可驗證結果清單與驗證方式
1. **載入順序正確時，stream 初始化完整**
   - 方法：依序載入 DayType -> Structure -> Entry -> HUD。
   - 驗證：可看到 `TRADEDAY/INNY/HASBOS/SCORE/DEBUG` 連續輸出。
2. **Focus 視窗外阻擋優先**
   - 方法：`focusmode=true`、`focusdate` 設為非目前交易日。
   - 驗證：`DEBUG=-9`，且不進入 Blue3。
3. **達到日內上限會鎖單**
   - 方法：降低條件促成連續訊號至 `dailyMaxTrades`。
   - 驗證：達上限後 `DEBUG=-1`，無新 `BLUE3`。
4. **關閉 DayType gate 可放寬訊號**
   - 方法：`requireSbDayType` 由 true 改 false。
   - 驗證：在相同資料區間內，訊號不再受 TradeDay gate 阻擋。
5. **結構與入場拆層後判斷一致**
   - 方法：比對 `HASBOS/FVGMIT/RETU/RETL` 與 `BLUE1/2/3` 先後。
   - 驗證：先有結構、後有入場，不出現倒序觸發。

## 已知限制
- `liveGradeMode=Auto` 仍是保留參數，尚未實作完整自動降級規則。
- `allowEntryAfterSession`、`mrnBlock` 尚未覆蓋完整時段阻擋細節。
- `lineLifecycle` 僅保留輸入，未實作完整線段生命週期管理。
- 視覺元素以 streams 代理，不提供 Pine label/box 逐像素等價。

## 後續事項
- 補齊 `Auto grade` 降級條件的規則矩陣與測試案例。
- 將 `allowEntryAfterSession`/`mrnBlock` 的阻擋策略納入同一 gate 評估表。
- 建立半自動回歸腳本（至少覆蓋 `docs/11-regression-rules.md` 的前 5 條）。

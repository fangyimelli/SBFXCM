# 11-regression-rules

> 規則格式：`Bug-ID | 問題摘要 | 回歸規則 | 驗證方式 | 預期結果`
> 原則：每修一個 bug，必須新增一條規則，且可重跑、可觀察、可判定。

## 核心 5 大驗證案例（必覆蓋）

1. **RG-001 | 載入順序錯置導致下游讀取 nil**
   - 回歸規則：僅接受 `DayType -> Structure -> Entry -> HUD` 順序。
   - 驗證方式：先故意錯序（例如 HUD 先載），再按正序載入重試。
   - 預期結果：錯序時 HUD/DEBUG 不完整；正序時 `TRADEDAY/INNY/HASBOS/SCORE/DEBUG` 正常連續。

2. **RG-002 | focus 與其他 gate 判斷互相覆蓋**
   - 回歸規則：focus 視窗外優先回傳 `DEBUG=-9`。
   - 驗證方式：`focusmode=true`，`focusdate` 設為非目前交易日。
   - 預期結果：即使其他條件成立，仍以 `-9` 為唯一阻擋訊號。

3. **RG-003 | 日內交易次數未正確鎖單**
   - 回歸規則：達 `dailyMaxTrades` 後不得新增 `BLUE3`。
   - 驗證方式：降低門檻促成連續入場，觀察達上限後輸出。
   - 預期結果：`DEBUG=-1`，`BLUE3` 不再出現新點。

4. **RG-004 | DayType gate 關閉後仍被擋單**
   - 回歸規則：`requireSbDayType=false` 時，不以 TradeDay 作硬性阻擋。
   - 驗證方式：同一資料區間切換參數 true/false 比對。
   - 預期結果：關閉後訊號數不低於開啟時，且阻擋原因不再顯示 DayType block。

5. **RG-005 | 結構/入場先後錯亂**
   - 回歸規則：必須先有 `HASBOS/FVGMIT/RETU/RETL`，才可觸發 `BLUE1/2/3`。
   - 驗證方式：逐段對照 stream 時序。
   - 預期結果：不允許 `BLUE3` 出現在 `HASBOS=0` 或 retest 區尚未建立時。

## 擴充規則（建議）

6. **RG-006 | DEBUG 編碼語義漂移**
   - 回歸規則：`0/-1/-2/-9` 語義固定，不得任意重用。
   - 驗證方式：逐一製造場景驗證每個代碼。
   - 預期結果：同場景同代碼，跨版本不漂移。

7. **RG-007 | 跨週期 map 對齊偏移**
   - 回歸規則：5m 對 15m / D1 的 index map 必須單調且不逆跳。
   - 驗證方式：抽查開盤、跨日、跨週資料點。
   - 預期結果：結構判斷不出現因 index 錯位造成的假 BOS/FVG。

8. **RG-008 | 平台相容性呼叫退化**
   - 回歸規則：`getHistory` 固定參數順序、`addStream` 第五參數為 number。
   - 驗證方式：在目標平台重新編譯/載入。
   - 預期結果：無 Add Indicator 參數錯誤。

9. **RG-009 | Update upvalues 超過 Lua 限制導致匯入失敗**
   - 回歸規則：策略狀態必須集中在 `S`，不得恢復大量分散 local state 讓 `Update()` 捕捉 >60 upvalues。
   - 驗證方式：在 FXCM Trading Station / Marketscope 2.0 重新匯入 `SB_Full_Manual_Workflow_FXCM.lua`。
   - 預期結果：匯入成功，且不再出現 `function at line XXX has more than 60 upvalues`。

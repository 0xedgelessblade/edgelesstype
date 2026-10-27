# Compatibility and evidence / 相容性與驗證範圍

This is an evidence ledger, not a claim that every field in an application is supported.

## What has been observed

| 目標或層次 | 證據 | 可得出的結論 | 不能推論的範圍 |
|---|---|---|---|
| 文字編輯器 TextEdit | 開發階段固定句插入及單次插入比對 | 當時的原生文字欄位路徑可用 | 所有原生 App 均可用 |
| Hermes 對話欄 | 開發階段貼入測試與焦點排查 | 該輸入欄當時可貼入；AX setter 成功不能代替結果確認 | Hermes 每個版本或每種編輯元件 |
| Chrome 的 Google 搜尋欄 | 開發階段實測 | 當時指定搜尋欄可貼入 | 所有 Chrome 網頁及 contenteditable |
| Muse 訊息欄 | 解析 wrapper focus；測自動、⌘V、Ctrl+V、選取取代與 exact-once | 該欄位的已測情境可用 | 元件重構後仍保證可用 |
| Grok Bot 對話欄 | 使用者回報自動貼入一次且預覽收起；另有不透明焦點的合成測試 | 被回報的欄位當時可用 | 自動化原生回歸或所有版本認證 |
| Codex 對話欄 | 使用者回報文字已貼入、提示框消失 | 一次實際使用結果 | 自動化回歸或所有版本認證 |
| 純邏輯、API fixtures、設定與加密 | 本機測試，無真實雲端金鑰 | 被測程式邏輯與固定協定回覆符合預期 | 所有服務商帳戶與真實線路均已測過 |

上列 App 版本沒有全部留存，不應轉寫成正式的版本相容矩陣。後續 issue／PR 請補上 macOS、App 版本、輸入欄類型與固定測試句；不要附私人聊天。

## Current validation snapshot

文件整理日期：2026-10-13。支援範圍為 Apple silicon、macOS 26 以上；不公開個別使用者的機器識別或私人操作紀錄。下列歷史測試各有自己的驗證範圍。

- 132 個 Core 測試通過；範圍包含事件決策、插入證據、字典、API 格式與回覆、加密紀錄、空白內容、提示音設定、Gemini 音訊請求／回覆固定案例、雲端音訊等待上限、失敗原因紀錄、自動重送條件與改用本機的時機，另涵蓋長文分段完整性、校正結果短標籤、離線與略過雲端後只貼一次，以及 9 秒校正回覆等待。
- 先前延後收音版本：本機 Small／Turbo 人聲偵測合成測試共 18 項通過，含保留短字與小聲語句；兩種輸入模式的無人聲路徑皆未碰剪貼簿或雲端。此測試不使用真實麥克風。另由使用者在喇叭播放提示音的實際環境確認：不說話時不貼字且提示框消失，真正說「謝謝」仍能貼入。
- 獨立解壓公開來源 ZIP 後，測試和 App 建置通過。
- 重新建置的本機引擎以 Small 與 Turbo 轉寫公開測試音檔成功。
- 隔離 UI 測試驗證金鑰新增、切換、刪除，以及三種提示音選單；未使用私人資料當 UI 測試值。
- 字典版面改用 Auto Layout；隔離固定詞彙視窗實測搜尋、新增、刪除，以及一般／窄視窗三欄與兩欄排列。原生預覽入口為 `dictionary-preview`，不讀寫私人字典或金鑰。另已檢查主畫面的快捷鍵提示和「操作指南」開關，內容與 `Hotkey.decide` 的開始／結束規則一致。
- 先前版本的一輪 xAI 固定上下文校正案例為 21/21；這是特定範例集的一次實測，不是準確率估計。
- 標點修正的 xAI 固定句實測為 5/5：含長句分句、問句、中英夾雜與保留既有標點。該輪提示詞為 540 字元，仍小於 550 上限。
- 同一輪對照中，原版與補標點版的同音案例均為 19/21，未通過的是「全選…應用程式的全線」與「提示框…自己推出」。此前 21/21 不應視為穩定保證；未驗證的改寫仍退回原轉寫。
- Google、Claude、OpenAI 使用官方協定與本機 fixtures／傳輸測試；沒有在此宣稱三家真實付費帳戶都已實測。
- [GitHub Actions 首次 hosted run 已通過](https://github.com/0xedgelessblade/edgelesstype/actions/runs/38074581080)，對應提交 `0404b87efbadb02b445c62cd37d21e851c633d67`。範圍為 Core、文件參照、App 建置、自測與公開檢查；不包含真實麥克風、Metal 語音推論或目標輸入框操作。

來源依據是本專案開發時的實測紀錄與可重跑測試。若下一次實測不同，應更新這份紀錄，而不是保留過時的成功宣稱。

## Repeatable checks

```sh
python3 Scripts/test-core.py
python3 Scripts/test-paste-flow.py
python3 Scripts/check-docs.py
bash Scripts/pack-app.sh
./edgelesstype.app/Contents/MacOS/edgelesstype self-check
python3 Scripts/public-check.py --app-only
```

安裝模型與引擎後，可再執行 `public-check.py --binaries` 檢查兩個二進位檔。貼入實測需有允許輔助使用的 App、前景目標與由測試者放好的游標。

## Known boundaries

- 不支援 Intel Mac、Windows 或 Linux。
- AX text-marker runtime symbols 和目標 App 的可及性樹可能改變。
- 若 AX value 不可讀，無法以讀回確認插入。Codex／Grok Bot 的精確白名單替代路徑會在單次按鍵投遞後收框並保留剪貼簿，但不將其記錄為已確認插入。
- 缺少選取範圍時的出現次數比對是較弱證據，不能證明完全正確的位置或沒有額外文字。
- 主動 focus 變動、剪貼簿被其他操作更換、權限不足時，不應自動重試貼入。
- Core CI 不會錄音、替使用者點擊輸入框、測試完整桌面 App，或消耗私人 API 額度。

- Luna 同音短句小量對照：原提示詞／不推理為 1/3，新提示詞／不推理為 2/3，新提示詞／低推理為 3/3；涵蓋重複的標點名稱誤字與保留「豆豆、豆子」。最慢樣本約 5.7 秒，因此當時 OpenAI 校正改為低推理、等待上限 8 秒；此為歷史測試，2026-10-11 已移除校正短期限；翻譯推理設定維持不變。新提示詞 537 字元，仍低於 550 上限。這是單輪文字測試，不代表一般準確率或錄音品質。
- 同一修改另以正式請求參數（低推理、8 秒 timeout）測試 4 個固定回歸句：同音詞位置、中英夾雜成語、網址／程式碼保留、合法「推出」均通過，約 1.8～3.6 秒；不代表一般品質或延遲保證。

- 本版改用 Fn 立即啟動的原生錄音，取消等待提示音與回音消除流程。第一段音訊寫入後才播開始音；提示音可能入錄，無雜訊幻覺不是本版承諾。先前回音消除實驗的連續無人聲驗證未通過，不得把單次或合成通過宣稱為全面解決。

- 即時收音版：33 項本機合成／串流轉換測試通過，含 16／44.1／48 kHz 首尾取樣、兩模型六組提示音重疊開頭詞測試，以及空白提示框路徑。8 項隔離剪貼簿測試通過；同一程序三次實體錄音啟停通過，第一個緩衝約 178～260 ms，均先收音再播提示音。啟停測試沒有執行 ASR，不能當成真人辨識或雜音抑制已通過。

- 目前正常校正採用完整文字回覆；先前 88 項 Core 測試快照包含新的全文接收路徑，以及保留作為歷史參考的舊式結構化校正案例。舊式內容拒絕測試不代表正式流程仍執行那些限制。

- OpenAI transcription option: local-default/consent gating, multipart construction, size limits, sanitized errors, Traditional conversion and mocked transport tested locally. Native isolated UI verified local default, refusal to save without consent, and persistence after consent. No real account or private audio was used; actual account/model access remains user-dependent.

## Signed updates and latency work

- Fixed local signing was checked with two different synthetic executables against one certificate-backed requirement. A subsequent native local update satisfied the previous requirement and the app reported successful event-tap creation. These are bounded results, not a guarantee against future OS-policy changes or certificate replacement.
- Local signing-profile and updater tests use synthetic metadata/files, preserve private sentinel files, reject signer changes and verify rollback behavior. No signing key is required in CI.
- Processing UI was rendered from native view code with fixed values. Session-reuse routing, combined translation policy and upload progress have local tests; real network speed and translation quality after the optimization require separate non-private live evaluation.
- Detailed diagnosis and failed approaches: [engineering lessons](ENGINEERING-LESSONS.md).

### 主動取消處理

上傳、辨識、校正與翻譯狀態提供「取消處理」按鈕。取消後關閉面板並中止目前請求；每筆處理保留獨立身分，延遲回覆不可重新顯示或貼上。Core 合成測試涵蓋雲端等待取消及取消身分隔離，未使用私人錄音。取消網路請求不代表服務端已收到的工作或費用一定撤銷。

### 選用錄音上下文

主開關與 OpenAI 傳送同意分開保存，預設皆關閉。Core 合成測試涵蓋舊設定預設值、同意組合、範圍限制、取消後拒收晚到結果，以及未同意時雲端請求不含上下文。原生設定頁以隔離資料渲染驗證；`Scripts/test-context-ui.py` 驗證開關顯示、儲存、撤銷及重新載入。未使用私人畫面或錄音測試；不保證所有 App 提供可讀的游標附近文字，也不保證辨識準確度提升。

### AI 首次安裝流程

首次私人目錄初始化使用明確允許清單；`Scripts/test-private-runtime.py` 以合成檔案檢查不複製私人設定／錄音、拒絕既有目錄與符號連結、模型雜湊失敗、簽章驗證失敗及複製失敗清理。簽章呼叫在此測試中為模擬，不能據此宣稱新 Mac 的實際鑰匙圈授權、下載或完整首次安裝已驗證。日常使用前先完成本機固定簽署；公開建置副本只供測試。

### 同音與詞界校正

整句校正與舊潤飾路徑共用語意／句法／發音提示；啟用校正的翻譯路徑使用相同原則。沒有新增固定替換、語意過濾器或額外模型呼叫。離線測試驗證提示接入、原文作為資料送入、合理原句可原樣返回；這些測試不代表模型實際準確率。舊潤飾成功時也會標記 corrected/unchanged 狀態，避免誤報 not_requested。無原始錄音與中間文字時，不能回溯判定歷史個案是辨識錯、校正漏改或校正改錯。

一次獨立人工案例比較共 8 筆文字請求，四句各比較舊／新提示；忽略標點與空白後皆符合四句預期。沒有重現先前使用者個案，不能宣稱準確率提高；未測試真實錄音辨識，未保存模型回覆或私人內容。

### Chrome 輔助使用延遲恢復

近期無文字內容的流程狀態顯示找不到編輯焦點、隨後手動貼上可執行。修正加入 Chrome 專用的一次完整輔助使用資訊請求與限次重查；正常可讀取欄位不要求此恢復。記憶體 OS 測試涵蓋延遲成功、失敗不盲貼、取消、手動補貼不重複與背景程序排除。尚不能由此認定 Google 或 Threads 所有欄位皆相容。

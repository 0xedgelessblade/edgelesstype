# Compatibility and evidence / 相容性與驗證範圍

This is an evidence ledger, not a claim that every field in an application is supported.

## What has been observed

| 目標或層次 | 證據 | 可得出的結論 | 不能推論的範圍 |
|---|---|---|---|
| 文字編輯器 TextEdit | 開發階段固定句插入及單次插入比對 | 當時的原生文字欄位路徑可用 | 所有原生 App 均可用 |
| Hermes 對話欄 | 開發階段貼入測試與焦點排查 | 該輸入欄當時可貼入；AX setter 成功不能代替結果確認 | Hermes 每個版本或每種編輯元件 |
| Chrome 的 Google 搜尋欄 | 開發階段實測 | 當時指定搜尋欄可貼入 | 所有 Chrome 網頁及 contenteditable |
| Muse 訊息欄 | 解析 wrapper focus；測自動、⌘V、Ctrl+V、選取取代與 exact-once | 該欄位的已測情境可用 | 元件重構後仍保證可用 |
| Codex 對話欄 | 使用者回報文字已貼入、提示框消失 | 一次實際使用結果 | 自動化回歸或所有版本認證 |
| 純邏輯、API fixtures、設定與加密 | 本機測試，無真實雲端金鑰 | 被測程式邏輯與固定協定回覆符合預期 | 所有服務商帳戶與真實線路均已測過 |

上列 App 版本沒有全部留存，不應轉寫成正式的版本相容矩陣。後續 issue／PR 請補上 macOS、App 版本、輸入欄類型與固定測試句；不要附私人聊天。

## Current validation snapshot

文件整理日期：2026-10-10。當前開發驗證機為 Apple Silicon、macOS 26.5.2。

- 60 個 Core 測試通過；範圍包含事件決策、插入證據、字典、API 格式與回覆、加密紀錄、空白內容及提示音設定。
- 獨立解壓公開來源 ZIP 後，測試和 App 建置通過。
- 重新建置的本機引擎以 Small 與 Turbo 轉寫公開測試音檔成功。
- 隔離 UI 測試驗證金鑰新增、切換、刪除，以及三種提示音選單；未使用私人資料當 UI 測試值。
- 字典版面改用 Auto Layout；隔離固定詞彙視窗實測搜尋、新增、刪除，以及一般／窄視窗三欄與兩欄排列。原生預覽入口為 `dictionary-preview`，不讀寫私人字典或金鑰。另已檢查主畫面的快捷鍵提示和「操作指南」開關，內容與 `Hotkey.decide` 的開始／結束規則一致。
- 先前版本的一輪 xAI 固定上下文校正案例為 21/21；這是特定範例集的一次實測，不是準確率估計。
- 標點修正的 xAI 固定句實測為 5/5：含長句分句、問句、中英夾雜與保留既有標點。最終提示詞為 540 字元，仍小於 550 上限。
- 同一輪對照中，原版與補標點版的同音案例均為 19/21，未通過的是「全選…應用程式的全線」與「提示框…自己推出」。此前 21/21 不應視為穩定保證；未驗證的改寫仍退回原轉寫。
- Google、Claude、OpenAI 使用官方協定與本機 fixtures／傳輸測試；沒有在此宣稱三家真實付費帳戶都已實測。
- [GitHub Actions 首次 hosted run 已通過](https://github.com/0xedgelessblade/edgelesstype/actions/runs/38074581080)，對應提交 `0404b87efbadb02b445c62cd37d21e851c633d67`。範圍為 Core、文件參照、App 建置、自測與公開檢查；不包含真實麥克風、Metal 語音推論或目標輸入框操作。

來源依據是本專案開發時的實測紀錄與可重跑測試。若下一次實測不同，應更新這份紀錄，而不是保留過時的成功宣稱。

## Repeatable checks

```sh
python3 Scripts/test-core.py
python3 Scripts/check-docs.py
bash Scripts/pack-app.sh
./edgelesstype.app/Contents/MacOS/edgelesstype self-check
python3 Scripts/public-check.py --app-only
```

安裝模型與引擎後，可再執行 `public-check.py --binaries` 檢查兩個二進位檔。貼入實測需有允許輔助使用的 App、前景目標與由測試者放好的游標。

## Known boundaries

- 不支援 Intel Mac、Windows 或 Linux。
- AX text-marker runtime symbols 和目標 App 的可及性樹可能改變。
- 若 AX value 不可讀，實際貼入可能成功而提示框仍未得到足夠證據。
- 缺少選取範圍時的出現次數比對是較弱證據，不能證明完全正確的位置或沒有額外文字。
- 主動 focus 變動、剪貼簿被其他操作更換、權限不足時，不應自動重試貼入。
- Core CI 不會錄音、替使用者點擊輸入框、測試完整桌面 App，或消耗私人 API 額度。

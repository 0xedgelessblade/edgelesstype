# edgelesstype

<img src="Resources/AppIcon-source.png" width="96" alt="edgelesstype app icon">

**Open-source voice dictation for Apple silicon Macs.** Local Whisper recognition, optional text-only LLM correction, and verified insertion into supported input fields.

公開作者：[edgelessblade](https://github.com/0xedgelessblade) · [MIT License](LICENSE) · [引用資訊](CITATION.cff)

給 **Apple Silicon M 系列 Mac、macOS 26 以上**使用的開源語音輸入 App。
錄音與 Whisper 語音辨識留在本機；可選擇自己的 API 金鑰，做上下文校正和中翻英。

## 閱讀入口 / Start here

| 想做什麼 | 從哪裡開始 |
|---|---|
| 安裝與使用 | 下方的使用方式、原始碼安裝與 API 設定 |
| 了解設計與資料流 | [Architecture](docs/ARCHITECTURE.md) |
| 找到類似問題的答案 | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| 讓自己的 LLM 研究或改造 | [AI guide](docs/AI-GUIDE.md)、[machine-readable index](docs/knowledge-index.json) |
| 換模型或新增 API | [Development guide](DEVELOPMENT.md) |
| 看哪些結果已被驗證 | [Compatibility and evidence](docs/COMPATIBILITY.md) |
| 提出修正 | [Contributing](CONTRIBUTING.md) |

## 工程重點

這個專案的重點包含：辨認被 wrapper 隱藏的游標、用輸入框內容確認貼入、避免自動重試造成重複文字，以及讓空白錄音不產生句點。每個案例都連到實作、測試與限制，方便其他開發者判斷自己的情況是否適用。

[疑難排解](docs/TROUBLESHOOTING.md) 記錄失敗徵兆和最後的設計選擇；[驗證紀錄](docs/COMPATIBILITY.md) 區分純程式測試、真實 App 操作及使用者回報，不把它們混成全面相容的宣稱。

## 使用方式

- 點進任意文字輸入框，短按 Fn 開始說話，再短按 Fn 結束並貼入。
- 按住 Shift 再短按 Fn 開始中翻英，隨即放開 Shift；說完只短按 Fn 結束。
- 字典主畫面有快捷鍵提示與「操作指南」。Small／Turbo 負責本機辨識；翻譯使用「API 設定」目前選用的雲端服務與自己的金鑰。
- 自動貼入未出現時，可按 ⌘V 或 Ctrl+V 補貼；確認輸入框收到文字後，提示框才收起。
- 沒有辨識出文字、太短的錄音或只有句點等標點時，提示框直接收起，不貼入、不更動剪貼簿。
- App 不會自動按 Enter 或傳送訊息。
- 點 Dock 圖示打開字典；可以新增、搜尋、刪除詞條。
- 字典或選單列的「提示音…」提供精修提示音（預設）、柔和雙音（B）、低沉短音（C），可試聽並自動記住選擇；下次錄音生效。
- 選單列可切換 Large-v3 Turbo 與較快的 Small；兩者都使用這台 Mac 的 Metal GPU。

不支援 Intel Mac、Windows、Linux 或 CPU-only 模式。

## 從原始碼安裝

需要 Xcode Command Line Tools、Homebrew，以及 `cmake`、`ffmpeg`、`python3`。
所有命令在這個專案資料夾執行：

```sh
git clone https://github.com/0xedgelessblade/edgelesstype.git
cd edgelesstype
brew install cmake ffmpeg python3
bash Scripts/bootstrap.sh
bash Scripts/pack-app.sh
open edgelesstype.app
```

`bootstrap.sh` 會下載固定版本的 whisper.cpp，套用本機服務保護修補，建置 Apple Silicon 引擎，並下載、驗證兩個模型。模型合計約 2.1 GB，只需準備一次。

第一次啟動依提示允許麥克風、輔助使用和輸入監控。開啟權限後如 Fn 尚未啟用，退出 App 再開一次。預設是自行簽署的本地 App，未經 Apple 公證；不需要關閉系統安全保護。

請保留 App、`Config`、`Models`、`Engine` 在同一份專案資料夾。個人設定第一次安裝時建立，不會加入 Git。

## 在 App 設定自己的 API

1. 打開「API 設定…」。
2. 選服務商，貼上自己的金鑰，按「儲存並使用」。
3. 按「測試連線」。只送固定測試句，會使用少量 API 額度。
4. 在字典視窗勾選「根據整句上下文校正」。

各家金鑰分開儲存；切換不會覆蓋其他家的金鑰。「刪除金鑰」只移除所選服務商的本機紀錄。刪除後本機語音辨識仍可用，但該服務商的校正／翻譯無法使用。

金鑰以 AES-256-GCM 加密，不顯示已儲存的原文。ChatGPT、Claude、Gemini 的聊天訂閱不等於這個 App 的 API 金鑰；使用自己的開發者帳戶設定。

| 服務商 | 預設校正／翻譯模型 | 金鑰入口 |
|---|---|---|
| xAI | 校正 `grok-4.3`；翻譯 `grok-4.7` | [xAI Console](https://console.x.ai/) |
| Google | `gemini-3.8-flash` | [Google AI Studio](https://aistudio.google.com/api-keys) |
| Claude | `claude-haiku-5-5` | [Claude Platform](https://platform.claude.com/settings/keys) |
| OpenAI | `gpt-5.4-mini` | [OpenAI Platform](https://platform.openai.com/api-keys) |

xAI 已於 2026-05-15 將舊的 Grok 4.1 Fast API 名稱轉向 Grok 4.3 並按新模型計費。本專案直接指定 `grok-4.3`、校正使用 `reasoning_effort: none`，避免舊名稱與實際費率不一致。詳見 [官方遷移說明](https://docs.x.ai/developers/migration/may-15-retirement)。

目前 xAI 的校正與翻譯使用不同預設模型；其他三家暫用同一模型處理兩項任務，尚未完成各自的分工選型比較。程式支援分別指定兩種用途。

UI 刻意只提供四家服務商，不做大型模型目錄。模型可用性與額度由各家帳戶決定；自己的金鑰應先用 UI 測試。API 適配有本機請求／回覆測試，不代表每個使用者的付費帳戶均已實測。

## 想請自己的 Codex 換模型？

可以直接給 Codex 這樣的要求：

> 請讀 AGENTS.md，把 OpenAI 的預設模型換成我指定的模型。查核該模型的官方 API 參數，更新測試，保持 UI 簡單，不要讀取或輸出我的金鑰。

模型名稱集中在 `Sources/OpenTypelessCore/CloudProvider.swift` 的 `model(for:)`。同檔的 `CloudWire` 處理各家的請求與回覆，UI 不需要跟著重寫。完整修改步驟見 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 字典、提示音與隱私

公開預設字典只含 `Config/dictionary-seed.json` 中的英文項目。首次啟動建立個人字典，之後自行新增的中文或英文詞條都可以正常保存。中文同音詞與成語校正由上下文處理，不需要全部塞進字典。

開始／結束提示音是本專案生成的低音量柔和音色，沒有外部採樣；可用 `python3 Scripts/make-sounds.py` 重建。

每位使用者的金鑰密文儲存在自己專案的 `private/store.encrypted.json`；解密鑰匙在自己 Mac 的 `~/.config/codex-secrets/open-typeless-keyring.json`。後者是沿用的本機目錄名稱，不是 Codex 雲端。兩者都不公開；呼叫 API 時才以 HTTPS 向所選服務商提供金鑰認證。詳見 [安全說明](SECURITY.md)。

公開版不含開發者的金鑰、個人設定、使用紀錄、錄音、編譯 App 或私人字典。開啟雲端功能時只送轉寫文字和字典；不送錄音、其他視窗內容或剪貼簿驗證資料。OpenAI 請求設定 `store: false`。服務商自身的資料政策另依其規定。

## 測試與公開來源包

```sh
python3 Scripts/test-core.py
python3 Scripts/check-docs.py
python3 Scripts/public-check.py
python3 Scripts/public-check.py dist/edgelesstype-source.zip
```

[GitHub Actions 工作流程](.github/workflows/ci.yml) 使用 macOS arm64 runner，檢查 Core、文件、App 建置與公開來源；不下載語音模型、不操作目標 App，也不需要 API 金鑰。[首次 hosted run 已通過](https://github.com/0xedgelessblade/edgelesstype/actions/runs/38074581080)；這驗證來源測試與建置，不代表所有 Mac 的麥克風、權限與輸入框都已實測。

測試使用固定範例與假的測試金鑰，不需要雲端帳戶。來源包使用明確檔案清單，不包含 `.git`、本機設定、密文、模型或二進位檔。

App 建置會重映射 Swift 原始碼路徑；引擎也會重映射 C/C++ 路徑。若自行發布 App，仍須額外檢查二進位檔、簽署資訊與第三方授權，不能把自用資料夾直接上傳。

## 授權與來源

本專案程式碼、原創提示音採 [MIT License](LICENSE)，公開作者為 **edgelessblade**。
語音引擎使用 [whisper.cpp v1.8.1](https://github.com/ggml-org/whisper.cpp/tree/a91dd3be72f70dd1b3cb6e252f35fa17b93f596c)，模型來自 [Whisper](https://huggingface.co/ggerganov/whisper.cpp)，錄音工具為 [FFmpeg](https://ffmpeg.org/)。第三方元件各自的授權仍適用；本來源包不重新分發其二進位檔。

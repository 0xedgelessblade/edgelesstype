# edgelesstype

<img src="Resources/AppIcon-source.png" width="96" alt="edgelesstype app icon">

**Open-source voice dictation for Apple silicon Macs.** Local Whisper or opt-in OpenAI transcription, optional text correction, and evidence-based insertion into supported input fields.

公開作者：[edgelessblade](https://github.com/0xedgelessblade) · [MIT License](LICENSE) · [引用資訊](CITATION.cff) · [更新日誌 / Changelog](CHANGELOG.md)

給 **Apple Silicon M 系列 Mac、macOS 26 以上**使用的開源語音輸入 App。
預設使用本機 Whisper；也可在「語音辨識」明確選用 OpenAI GPT Transcribe，上傳錄音轉成文字。後續上下文校正與中翻英服務可分開設定。

## 不會 CLI？交給你的 AI 安裝

**目前提供原始碼安裝，暫不提供 DMG。** 你不必自己學會終端機指令，但需要一個**已獲你授權、能在你的 Mac 操作終端機與檔案的 coding assistant**；普通聊天視窗只能給建議，不能代替你安裝。

把專案網址交給它並說「請幫我安裝」，或直接複製下方整段：

> 請幫我在這台 Mac 安裝 https://github.com/0xedgelessblade/edgelesstype 。先讀 README、AGENTS.md、SECURITY.md 和 docs/INSTALL_WITH_AI.md，按指南完成相容性檢查、安裝必要工具、下載並驗證模型、建置和開啟 App。使用我指定的安裝位置；未指定時先問我一次。若不符合 Apple M 系列與 macOS 26 以上的要求，請停止並說明原因。
>
> 個資與金鑰保護優先：不要讀取既有秘密檔案，不要要求我在聊天貼金鑰或系統密碼，不要覆寫私人設定、關閉系統安全防護或上傳日誌。API 金鑰由我在 App 裡自行輸入；不要代我啟用雲端功能。需要系統權限時告訴我如何操作。最後引導我測試錄音和貼入，分別回報哪些已驗證、哪些仍需我確認；不要把建置成功當成全部功能都已通過。

**你仍需親自處理的部分：**必要的系統密碼／安裝確認、麥克風等權限，以及自己的 API 金鑰。一般本機聽寫不需要金鑰；雲端校正和中翻英才需要。第一次安裝會下載約 2.1 GB 語音模型，另外需要工具與建置空間。

**給接手安裝的 LLM：**請從 [逐步安裝指南](docs/INSTALL_WITH_AI.md) 開始。指南包含缺少工具時的處理、既有安裝的保護、失敗時的排查、權限交接與完成標準；它不會授予超出使用者或工具規則的權限。本專案不提供作者的金鑰，也沒有自動診斷上傳功能。使用雲端 coding assistant 的資料處理，另依該工具的政策與使用者授權。

## 閱讀入口 / Start here

| 想做什麼 | 從哪裡開始 |
|---|---|
| 交給 AI 安裝 | [逐步安裝指南](docs/INSTALL_WITH_AI.md) |
| 自己安裝與使用 | 下方的使用方式、原始碼安裝與 API 設定 |
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

- 點進任意文字輸入框，短按 Fn，聽到提示音即可開始說話，再短按 Fn 結束並貼入。
- 按住 Shift 再短按 Fn 開始中翻英，隨即放開 Shift；說完只短按 Fn 結束。
- 字典主畫面有快捷鍵提示與「操作指南」。Small／Turbo 負責本機辨識；翻譯使用「API 設定」目前選用的雲端服務與自己的金鑰。
- 自動貼入未出現時，可按 ⌘V 或 Ctrl+V 補貼；確認輸入框收到文字後，提示框才收起。
- 按 Fn 就啟動原生收音，第一段音訊寫入後播放開始音；不等音效結束，也不裁掉開頭。開始音可能被麥克風收到，本版未啟用回音消除。錄音仍經本機人聲偵測；沒有有效文字或只有標點時不貼入。
- 確認貼入成功後還原先前剪貼簿；若期間複製了新內容，就保留新內容。無法確認或取消時，語音文字留在剪貼簿，供手動補貼。
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

`bootstrap.sh` 會下載固定版本的 whisper.cpp，套用本機服務保護修補，建置 Apple Silicon 引擎，並下載、驗證兩個辨識模型與約 0.9 MB 的 Silero 人聲偵測模型。模型合計約 2.1 GB，只需準備一次。

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
| Claude | `claude-haiku-5-5`；校正與翻譯皆關閉推理 | [Claude Platform](https://platform.claude.com/settings/keys) |
| OpenAI | `gpt-6-luna` | [OpenAI Platform](https://platform.openai.com/api-keys) |

xAI 已於 2026-05-15 將舊的 Grok 4.1 Fast API 名稱轉向 Grok 4.3 並按新模型計費。本專案直接指定 `grok-4.3`、校正使用 `reasoning_effort: none`，避免舊名稱與實際費率不一致。詳見 [官方遷移說明](https://docs.x.ai/developers/migration/may-15-retirement)。

Claude 明確送出 `thinking: {"type": "disabled"}`，搭配 `output_config.effort: "low"`；只設 low 並不等於關閉推理。[官方說明](https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5)

目前 xAI 的校正與翻譯使用不同預設模型；其他三家暫用同一模型處理兩項任務，尚未完成各自的分工選型比較。程式支援分別指定兩種用途。

API 設定會分別顯示校正與翻譯最近成功回覆的模型名稱；尚無回覆或服務商沒有提供名稱時，顯示請求設定，滑鼠提示會說明來源。這項顯示只保留在本次啟動的記憶體，不保存轉寫，也不額外呼叫 API。

UI 刻意只提供四家服務商，不做大型模型目錄。模型可用性與額度由各家帳戶決定；自己的金鑰應先用 UI 測試。API 適配有本機請求／回覆測試，不代表每個使用者的付費帳戶均已實測。

## 想請自己的 Codex 換模型？

可以直接給 Codex 這樣的要求：

> 請讀 AGENTS.md，把 OpenAI 的預設模型換成我指定的模型。查核該模型的官方 API 參數，更新測試，保持 UI 簡單，不要讀取或輸出我的金鑰。

模型名稱集中在 `Sources/OpenTypelessCore/CloudProvider.swift` 的 `model(for:)`。同檔的 `CloudWire` 處理各家的請求與回覆，UI 不需要跟著重寫。完整修改步驟見 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 字典、提示音與隱私

公開預設字典只含 `Config/dictionary-seed.json` 中的英文項目。首次啟動建立個人字典，之後自行新增的中文或英文詞條都可以正常保存。中文同音詞與成語校正由上下文處理，不需要全部塞進字典。校正直接採用模型完整回覆，只檢查請求成功、回覆完整且非空白，輸出前在本機轉為繁體中文。

開始／結束提示音是本專案生成的低音量柔和音色，沒有外部採樣；可用 `python3 Scripts/make-sounds.py` 重建。

每位使用者的金鑰密文儲存在自己專案的 `private/store.encrypted.json`；解密鑰匙在自己 Mac 的 `~/.config/codex-secrets/open-typeless-keyring.json`。後者是沿用的本機目錄名稱，不是 Codex 雲端。兩者都不公開；呼叫 API 時才以 HTTPS 向所選服務商提供金鑰認證。詳見 [安全說明](SECURITY.md)。

公開版不含開發者的金鑰、個人設定、使用紀錄、錄音、編譯 App 或私人字典。文字校正／翻譯送出轉寫文字與字典；只有明確選用 OpenAI 雲端語音辨識並同意後，才傳送錄音。其他視窗內容與剪貼簿驗證資料不上傳。OpenAI Responses 文字請求設定 `store: false`；音訊 API 不沿用該參數。服務商自身的資料政策另依其規定。

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
語音引擎使用 [whisper.cpp v1.8.1](https://github.com/ggml-org/whisper.cpp/tree/a91dd3be72f70dd1b3cb6e252f35fa17b93f596c)，模型來自 [Whisper](https://huggingface.co/ggerganov/whisper.cpp)，錄音使用 macOS 原生音訊引擎；[FFmpeg](https://ffmpeg.org/) 保留供音訊工具與測試使用。第三方元件各自的授權仍適用；本來源包不重新分發其二進位檔。

## 選擇第一階段語音辨識

從字典視窗或 App 選單開啟「語音辨識…」：

- **Whisper（本機）**：預設選項；Small／Large-v3 Turbo 在本機辨識，不傳送錄音。
- **GPT Transcribe（OpenAI 雲端）**：固定使用 `gpt-transcribe`。需勾選錄音上傳同意並儲存；之後每次結束錄音才傳送該次音訊，需要網路、OpenAI 金鑰與 API 額度。

「OpenAI 金鑰設定」沿用加密保存的 OpenAI 紀錄，不更改文字校正服務商。雲端單次錄音上限 25 MB；過大時會提示分段錄製或切回本機，不會自動切換辨識服務。API 回覆仍在本機轉為繁體。

介面切換與隔離傳輸測試已驗證；沒有使用真實帳戶金鑰或上傳私人錄音作測試。官方介面：[File transcription](https://developers.openai.com/api/docs/guides/speech-to-text)。

## Separate public source and private local installation

Maintain code in one Git checkout. Keep the daily app, personal settings, dictionary, models and credentials in a separate private runtime directory. A local app may be named **Local Edgeless Type.app** without changing the public product name. Both names use the same source code.

After reviewing changes and quitting the local app, build and update from this repository:

```sh
bash Scripts/pack-app.sh
python3 Scripts/update-local-app.py --target "/path/to/Local Edgeless Type"
```

The target must already contain `Config/app.json` and `Local Edgeless Type.app`. This is an updater, not a first-install or folder-migration tool. It copies only the executable, app metadata and fixed public sound/icon assets. It preserves private settings, dictionary, models, credential files and bundled configuration; it never copies local data back into the repository. Code-only backups are non-app files, and `LOCAL-BUILD.json` in the private installation records the source and binary hash. Do not publish this local receipt.

Do not rebuild stale source left inside a private runtime directory. Use the canonical Git checkout and this updater. macOS may require the user to reapprove permissions after a rebuild or rename; the updater does not change system permissions. Real dictation and destination insertion must still be checked locally.

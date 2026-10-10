# 修改模型與 API

只支援 Apple Silicon M 系列、macOS 26 以上。先讀 `AGENTS.md`。

## 換成同一家的另一個模型

1. 修改 `Sources/OpenTypelessCore/CloudProvider.swift` → `CloudProvider.model(for:)`。可以分開指定校正與翻譯。
2. 查該模型官方文件，檢查 `CloudWire.request` 中的推理、溫度、輸出長度與 JSON Schema 參數；不能只假設所有模型都接受相同參數。
3. 更新 `CloudProviderTests.swift` 對模型與請求格式的斷言。
4. 執行 `python3 Scripts/test-core.py`、`bash Scripts/pack-app.sh`。
5. 用自己的金鑰在 UI「測試連線」，再實測一段中英夾雜短句與翻譯。不得把金鑰寫進程式或測試。

## Claude 的預設推理設定

Claude 校正與翻譯目前都用 `claude-haiku-5-5`，請求明確設定 `thinking.type = disabled`，並保留 `output_config.effort = low`。Haiku 5.5 預設是 adaptive thinking，僅設 low 不代表關閉；官方允許在 high 或以下停用 thinking。此設定優先考量短句互動，不代表已完成真實帳戶的速度／翻譯品質比較。換模型時須重新核對該模型是否允許停用 thinking，不能直接沿用其他服務商的 `reasoning_effort` 欄位。參考 [Haiku 5.5 官方說明](https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5)。

## 加入另一家或自己的 LLM API

- `CloudProvider`：服務商顯示名、固定 endpoint、模型與金鑰入口。
- `CloudWire.request`：認證標頭及模型請求格式。
- `CloudWire.parse`：成功結果、拒絕、截斷與錯誤處理。只回傳完整文字，不可把 thinking 或 error 當作可貼入內容。
- `CloudProviderTests`：加入固定成功／失敗回覆，以及認證資訊不進 URL 或日誌的測試。
- `APISettingsWindow` 以 `CloudProvider.allCases` 建立選單；既有選擇、儲存、測試及刪除流程可沿用。
- `CloudAccess` 依 provider 的穩定 raw value 讀取加密紀錄。不要讓兩家共用同一個紀錄代號。

正式版只允許固定的 HTTPS 服務商，且不跟隨重新導向，避免金鑰被送去其他站。若要接自己的本機 HTTP 模型，請新增專用 adapter 與只接受 loopback 的檢查，不要全面取消 HTTPS 或允許任意轉址。

## 校正資料格式

校正回傳 `{"corrections":[{"from":"原詞","to":"正確詞","occurrence":1}],"punctuated":"校正後補標點的全文"}`。原生 JSON schema 要求兩個欄位；`punctuated` 可為 null，本機解析也相容舊回覆缺欄位。

四家服務共用 `ContextCorrection.draft` 的提示詞；`CloudWire` 只適配不同協定。先驗證詞語替換，再由 `SentencePunctuation` 驗證只插入標點、保留原文字和空白。勿因換模型而複製四套校正规則。
`ContextCorrection.validatedApply` 是最後一道語意檢查：保留中英夾雜、限定原文位置、拒絕改寫全文。更換 API 不應繞過它。

錄音永遠交給本機 Whisper。雲端只有轉寫文字、字典和固定系統提示。

## 官方介面依據

- [OpenAI Responses](https://developers.openai.com/api/reference/python/resources/responses/methods/create)
- [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)
- [Google GenerateContent](https://ai.google.dev/api/generate-content)
- [Claude Messages](https://platform.claude.com/docs/en/api/messages/create)
- [Claude Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/overview)

模型是容易替換的預設值，不是不可更改的承諾。更新時查核當時的官方文件與自己帳戶的權限。

## 提示詞大小與診斷

校正提示詞保持在 550 字元以內，通用規則優先。新錯字通常加入測試，避免把整個測試集塞進提示詞；送到模型的字典不含內部 UUID 或空白欄位。

`Config/last-latency.json` 可記錄校正是 corrected、unchanged、rejected、timeout 等狀態，只有狀態與計時，沒有錄音或文字。此檔不公開。

`correction-probe` 是可選的真實 API 測試，會用目前選用服務商與已儲存金鑰，送出程式內固定範例與字典並消耗額度；不要在沒有使用者授權時執行。一般回歸測試不會連線。

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

目前四家服務皆要求一般文字回覆：模型直接輸出完整校正文字，不再要求 corrections／punctuated JSON。輸入仍以 JSON 包裝 transcript 與字典資料，與回覆格式無關。

正式路徑為 `ContextCorrection.draft` → `CloudWire.parse` → `ContextCorrection.acceptFullText`。只確認 HTTP 請求成功、服務端標記完整完成、文字非空白，再透過 `OutputPolicy.traditional` 本機轉繁體。不比對同音、字典、原詞位置、修改數量、詞長、標點或句意。字典與保留原意要求只作為提示詞引導，不作拒絕回覆的規則。完成上下文校正後不再執行第二輪潤飾。

`validatedApply`、`validatedResult` 與 `SentencePunctuation` 僅保留給歷史固定案例，不在正常校正或貼上流程中使用。勿將歷史驗證器重新接回正式路徑。

一般文字輸出依據：[OpenAI Text generation](https://developers.openai.com/api/docs/guides/text)、[xAI output formats](https://docs.x.ai/developers/model-capabilities/text/structured-outputs)、[Claude Messages](https://platform.claude.com/docs/en/api/messages/create)、[Gemini output formats](https://ai.google.dev/gemini-api/docs/structured-output)。

預設錄音交給本機 Whisper；明確同意後可選 OpenAI 音訊轉寫。文字校正與翻譯仍只接收文字、字典和固定提示。

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

## 長文校正與等待

校正 draft 使用 `TimeInterval.infinity` 表示沒有應用程式期限；CloudClient 不對此模式執行有期限的 semaphore wait，且以大的有限值設定 URLSession 的 request/resource timeout，避免把 infinity 直接交給網路框架。翻譯與固定連線測試仍保留各自期限。

`ContextCorrection.correctingChunks` 依序處理全文，保留段首尾空白與原文順序，每段都直接採用模型完整文字並執行非空白檢查與繁體轉換；總長度不截斷。不可拆分的程式碼／網址可能超過一般分段大小。純測試涵蓋 9 秒回覆、長文完整性、技術片段、逗號加入及後段失敗；這不是雲端帳戶成功或標點品質保證。

## Optional first-stage transcription

`TranscriptionPreferences` defaults to local Whisper and validates explicit consent before any OpenAI route. `TranscriptionRouter` chooses exactly one backend; it never silently falls back to another provider. The OpenAI audio adapter sends `model=gpt-transcribe`, a fixed Traditional-Chinese prompt and a WAV file to `/v1/audio/transcriptions`. It uses the default JSON response with `text`, without legacy singular language hints or Responses-only parameters.

The main controller snapshots the choice at recording start and uses it through processing. Cloud selection skips local model warm-up; both results enter the same full-text correction, Traditional conversion and paste pipeline. Use [official file-transcription docs](https://developers.openai.com/api/docs/guides/speech-to-text) when changing the model or multipart fields.

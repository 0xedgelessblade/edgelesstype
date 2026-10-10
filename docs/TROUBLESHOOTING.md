# Troubleshooting / 從症狀找答案

For coding assistants: find the matching symptom, inspect the linked code, and run the listed test. These are scoped engineering findings, not universal fixes for every editor. Machine-readable lookup: [knowledge-index.json](knowledge-index.json).

## Paste: AX setter false success

**症狀 / search terms：** `AXSelectedText succeeds but no text appears`、AX 寫入回傳成功但文字沒進去、Hermes 自動貼入失敗。

**判斷：** 寫入 API 回傳成功，只能代表呼叫被接受。開發階段曾在目標輸入框看到回傳成功、實際文字卻未改變。先比對目標的文字及選取範圍，不要先假設辨識或剪貼簿壞了。

**本專案解法：** 正常路徑改用實際剪貼簿文字與按鍵貼入，再讀回目標內容；不以 `AXSelectedText` setter 成功作為退出提示框的依據。

**程式與驗證：** [Paster.offer](../Sources/OpenTypeless/Paster.swift)、[PasteConfirmationTests](../Tests/OpenTypelessTests/PasteConfirmationTests.swift) 的 `testWebSetterFalseSuccessDoesNotDismiss`。純政策測試可重現「內容沒變，不能判成功」；真實目標仍須另測。

## Paste: clipboard read not proof

**症狀 / search terms：** `clipboard read but paste did not happen`、剪貼簿已被讀取但框內沒有文字、提示框提早消失。

**判斷：** 讀取剪貼簿與完成插入是兩件事。目標或其他程序可能先查看剪貼簿；這不足以證明游標處收到文字。

**本專案解法：** 先實際發布字串，不依賴延遲供應；以目標快照確認插入。記錄 `changeCount` 用來避免接管使用者後來複製的內容，不把它當成功訊號。取消或成功後不自動恢復舊剪貼簿。

**程式與驗證：** [Paster](../Sources/OpenTypeless/Paster.swift)、[PasteConfirmation](../Sources/OpenTypelessCore/PasteConfirmation.swift)。輸入框原文未改變時不得收起提示框。這項原則本身不會解決失焦或不相容的按鍵投遞。

## Paste: wrapper focus

**症狀 / search terms：** `AXFocusedUIElement AXButton contenteditable`、`AXSelectedTextMarkerRange`、Muse 輸入框被回報成按鈕。

**判斷：** 在開發時觀察到，游標明明位於 Muse 訊息欄，焦點 AX 物件卻是 `AXButton`，其 value 也不是實際草稿。只接受 `AXTextArea` 的程式會找不到目標。不能因為 wrapper 帶有「傳送」名稱就去執行按鈕動作。

**本專案解法：** 依序檢查直接可編輯元件、editable ancestor，再嘗試以選取文字標記找出游標所在元件和其可編輯祖先。正常路徑不掃描整段聊天，不點傳送按鈕，不直接寫 AX 選取文字。

**程式與驗證：** [WebKitFocus](../Sources/OpenTypeless/WebKitFocus.swift)、[Paster.focusedElement](../Sources/OpenTypeless/Paster.swift)。手動把游標放在可丟棄的空白輸入欄後，執行 `focus-probe <bundle-id> --summary`，只觀察是否解析出 editor 和字數。

**限制：** 部分 text-marker symbols 不是穩定的公開 SDK 契約。程式以 `dlsym` 和型別檢查選用；無法取得時返回失敗，而不是假裝支援。OS 或目標 App 更新後需重測。可參考 [Hammerspoon 的 text-marker 實作](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/axuielement/axtextmarker.m)，但不要把別人的支援範圍直接當成自己的測試結果。

## Paste: duplicate insertion

**症狀 / search terms：** `CGEvent paste twice`、`Electron paste duplicate`、一次語音貼入兩次。

**判斷：** 開發時的全域 HID 路徑，在 Muse 和文字編輯器測試中曾產生兩份相同文字。「包含測試句」會漏掉這種錯誤；測試必須比對預期的完整插入結果。

**本專案解法：** 在確認前景 PID 和焦點仍相同後，使用 `postToPid` 投遞一組 Command/V 按下與放開事件。放鍵採非阻塞排程；即使取消這次輸入也仍釋放按鍵。不因確認逾時就自動重送。

**程式與驗證：** [Paster.sendPasteChord](../Sources/OpenTypeless/Paster.swift)、[PasteProbe](../Sources/OpenTypeless/PasteProbe.swift) 的 `exactlyOnce` 比對。測空白欄位、已有文字、選取取代和手動補貼。

**限制：** 這是當次測試有效的投遞方式，不證明每個重複貼上問題都源自 HID，也不代表每個 App 都接受相同方式。

## Paste: manual recovery

**症狀 / search terms：** `manual Cmd-V succeeds overlay stays`、Ctrl+V 貼完提示框不消失、event tap hangs during accessibility query。

**判斷：** 手動按鍵和自動貼入若走兩條不同的確認路徑，提示框可能不知道文字已進去。另一個陷阱是在 event-tap callback 裡同步等待 AX 查詢，阻擋了目標處理同一個事件所需的流程。

**本專案解法：** callback 只做必要判斷並迅速返回；延後到主佇列重新解析焦點、取得快照、投遞貼上與驗證。以事件標記排除自己送出的鍵，並確認剪貼簿尚未被使用者換成別的內容。

**程式與驗證：** [HotkeyMonitor](../Sources/OpenTypeless/main.swift)、[Paster.notePasteKey](../Sources/OpenTypeless/Paster.swift)。開發測試命令有 `paste-probe <bundle-id> manual-command` 和 `manual-control`，只貼固定句、不按 Enter。輸入欄應由測試者先聚焦；不要自動點疑似傳送按鈕。

## Paste: UTF-16 offsets

**症狀 / search terms：** `AXSelectedTextRange emoji offset`、Swift String count 與 NSRange 不一致、emoji 後貼入位置錯誤。

**本專案解法：** AX 選取範圍使用 UTF-16。計算預期插入結果時，用 `NSString` 的長度及 range 操作，不把 Swift 的使用者可見字元數直接當偏移。先驗證 location/length 合法，保留周圍文字。

**程式與驗證：** [PasteConfirmation](../Sources/OpenTypelessCore/PasteConfirmation.swift)、[PasteConfirmationTests](../Tests/OpenTypelessTests/PasteConfirmationTests.swift) 的 `testChineseInsertedAtUTF16CursorAfterEmoji` 及無效範圍測試。

**限制：** 有些目標根本不提供選取範圍，不能憑空合成一個精確游標位置。

## UI: overlay steals focus

**症狀 / search terms：** `NSPanel steals focus dictation`、浮動提示框搶走輸入焦點、貼上跑到語音 App。

**本專案解法：** 錄音／轉寫提示框使用 nonactivating panel，明確禁止成為 key 或 main window。貼入前仍要檢查前景程序與實際焦點；不能只相信錄音開始時捕捉的目標。

**程式與驗證：** [RecordChrome](../Sources/OpenTypeless/RecordChrome.swift)、[Paster](../Sources/OpenTypeless/Paster.swift)。在 disposable 輸入欄放好游標，顯示提示框後執行固定句貼入測試。字典、API 和提示音設定視窗可以主動取得焦點，不能與被動的錄音提示框混為一談。

**限制：** 其他 App、系統權限對話框或使用者主動切換仍可能改變焦點；此設定不是全系統焦點鎖。

## Speech: empty or punctuation

**症狀 / search terms：** `Whisper silence outputs period`、沒說話卻插入句點、`[BLANK_AUDIO]`。

**判斷：** 非空字串不一定有有效語音內容。句點、空白標記和不可見字元不應走到剪貼簿。

**本專案解法：** 對錄音器的 PCM16 WAV 辨識真正的數位靜音；無法解析的格式不猜測為靜音。ASR 之後再攔截空白、純標點和已知空白標記；`Paster.offer` 另有防線。無有效文字時關閉提示框，不改剪貼簿。數字、帶字母的程式碼與 emoji 仍可保留。

**程式與驗證：** [SpeechContent](../Sources/OpenTypelessCore/SpeechContent.swift)、[SpeechContentTests](../Tests/OpenTypelessTests/SpeechContentTests.swift)。`silence-probe <silent-pcm16.wav>` 會複製輸入，驗證兩種模式的提示框及剪貼簿版本號，不讀剪貼簿原文。

**限制：** 數位靜音判斷不是完整 VAD；它不能宣稱能排除所有背景噪音造成的有字幻覺。

## Speech: homophone errors

**症狀 / search terms：** Chinese homophone correction、抬官抗議／抬棺抗議、權限／全線、LLM 沒改同音錯字。

**判斷：** 分清楚「模型回傳未更正」「請求失敗」「結果被驗證器拒絕」。不能只看最終原文就下結論。開發測試曾重現模型對固定說法不提出修改；不是每次都由本地驗證器造成。

**本專案解法：** 精簡的整句語境規則，搭配有區別力的少量對照。詞語修正回傳 `from/to/occurrence`，由本機驗證短詞、位置、字典或同音關係；不直接接受全文改寫。同一個請求可回傳 `punctuated`，但只能在已驗證的文字上插入標點；原有文字、空白與標點必須保留，並保護英文 token、網址、路徑與反引號程式碼。將新案例放進測試，而不是持續增長提示詞。

**程式與驗證：** [ContextCorrection](../Sources/OpenTypelessCore/Vocabulary.swift)、[VocabularyTests](../Tests/OpenTypelessTests/VocabularyTests.swift)。例：修正「家人抬官抗議」，同時保留「台灣官員抗議不公平待遇」；修正麥克風權限，同時保留捷運全線通車。提示詞有 550 字元上限測試。

**限制：** 測試集通過不是一般準確率。音近判斷與 LLM 都可能失誤；日誌只存結果類型，不保存原文。

## Speech: cold start

**症狀 / search terms：** short dictation slow、Whisper model reload every utterance、Metal resident inference。

**本專案解法：** 模型由本機 worker 常駐，切換模型才重新預載；只允許 loopback，使用每次啟動的隨機 token，父程序退出後停止 worker。確認 Metal backend 真正啟用，不只檢查程序存在。

**程式與驗證：** [ResidentSpeechEngine](../Sources/OpenTypeless/ResidentSpeechEngine.swift)、[worker patch](../Patches/whisper-server.patch)。分開量測預載、辨識、雲端校正與貼入；不要把不含錄音時間的推論數字稱為完整體驗延遲。

**限制：** 沒有跨所有 M 系列、記憶體與系統版本的完整效能資料，不能從一台機器推導所有人的秒數。

## API: provider integration

**症狀 / search terms：** OpenAI-compatible API not compatible、Claude system prompt format、Gemini text extraction、API key save/delete。

**本專案解法：** 為四家分開建構 endpoint、認證、請求和回覆解析；固定精簡預設模型，避免 UI 變成大型目錄。拒絕截斷或拒答，忽略 reasoning/thinking 區塊；不把原始錯誤 body 印給使用者。測試包含各家的傳輸流程、失敗解析與每家金鑰隔離。

**程式與驗證：** [CloudProvider](../Sources/OpenTypelessCore/CloudProvider.swift)、[CloudProviderTests](../Tests/OpenTypelessTests/CloudProviderTests.swift)、[更換模型指南](../DEVELOPMENT.md)。模型改名不代表參數仍相容，必須查該模型官方文件。

## Release: personal paths

**症狀 / search terms：** macOS binary leaks build path、GitHub personal information leak、gitignore not enough。

**本專案解法：** 公開來源使用 allowlist，排除 runtime config、密文、金鑰表、錄音、個人字典、Git 歷史與二進位檔。Swift/C/C++ 重映射編譯路徑；App 複本移除偵錯符號後重新簽署。另查實際二進位內容，不能只檢查 `.swift`。

**程式與驗證：** [public-check.py](../Scripts/public-check.py)、[pack-app.sh](../Scripts/pack-app.sh)、[bootstrap.sh](../Scripts/bootstrap.sh)。Git 作者名稱、Email、簽署資訊和外部頁面也需獨立審查；用公開別名與自己的 GitHub noreply Email。

**限制：** 自動掃描不是絕對匿名保證。若真的把金鑰公開過，先撤銷或輪替，不能只刪除目前檔案。

## Speech: missing sentence punctuation

**症狀 / search terms：** missing punctuation、no commas or periods、整段沒有標點、Chinese mixed English dictation。

**原因：** ASR 未產生標點，而後處理只允許詞語替換（舊提示詞還明確禁止補標點），就沒有步驟能恢復斷句。空白／純標點攔截本身不會刪除句中標點。

**解法：** 在同一次上下文校正加入 `punctuated`；原生 JSON schema 要求該欄位存在並允許 null，本機解析仍相容舊回覆缺欄位。先驗證詞語修正，再驗證僅插入句讀標點。模型若在新增逗號處省略原有空格，本機先補回原空格；其他空白變動不接受。非法改寫保留合法詞語修正。無文字仍不請求、不貼上。提示詞維持 550 字元限制。

**程式與驗證：** [SentencePunctuation](../Sources/OpenTypelessCore/SentencePunctuation.swift)、[tests](../Tests/OpenTypelessTests/SentencePunctuationTests.swift)。固定雲端測試入口：`correction-probe --punctuation`，只使用公開測試句。

**限制：** 補標點需啟用上下文校正與有效 API。離線、逾時或模型沒有給出合法結果時保留原轉寫；驗證器能限制改寫，不能證明語意斷句一定正確。

API schema 參考：[OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)、[Gemini structured outputs](https://ai.google.dev/gemini-api/docs/structured-output)、[Claude structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)。四家服務共用 `ContextCorrection.draft` 提示詞，只有協定轉接層依供應商分開。

## API: retired model aliases

**症狀 / search terms：** deprecated model alias、unexpected API cost、Grok 4.1 Fast redirect、舊模型名稱與帳單不一致。

**原因：** API 接受舊名稱，不代表仍執行舊模型或沿用舊價格。xAI 官方公告，2026-05-15 後 `grok-4-1-fast-non-reasoning` 會轉向 `grok-4.3` 並使用 `none` 推理層級，按 Grok 4.3 收費。

**解法：** 明確指定目前的模型 ID、推理層級，讓 UI 與請求一致。這項修改本身不會把價格降回舊費率。程式不因 API 名稱仍能呼叫，就將它視為可用性或價格未變的證據。

**程式與驗證：** [CloudProvider](../Sources/OpenTypelessCore/CloudProvider.swift)、[provider tests](../Tests/OpenTypelessTests/CloudProviderTests.swift) 的 `testStructuredCorrectionAndPlainTranslationPayloads` 驗證校正指定 Grok 4.3／none、翻譯維持 Grok 4.7／high。本機 fixtures 不消耗 API 額度。

**限制：** 價格與服務端映射會再改變；舊實測不能保證當前帳單。開發用的付費回歸呼叫應與正常使用量分開評估，不記錄或公開使用者帳單。

依據：[官方遷移公告](https://docs.x.ai/developers/migration/may-15-retirement)、[官方價格](https://docs.x.ai/developers/pricing)。

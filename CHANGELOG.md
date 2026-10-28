# 更新紀錄 / Changelog

edgelesstype 是 Apple silicon Mac 的開源語音輸入工具：預設用本機 Whisper 辨識，也可以選擇 OpenAI 或 Google Gemini 雲端辨識，輸出繁體中文。

每一版從使用者遇到的問題寫起，接著是這次處理的難題、完成狀態，最後附英文摘要。日期代表原始碼更新，不代表另外打包的安裝檔。

edgelesstype is an open-source voice dictation app for Apple silicon Macs, with local Whisper by default and optional OpenAI or Google Gemini cloud recognition. Each entry starts with the problem a user ran into, then the changes, what has and has not been verified, and an English summary. Dates mark source updates, not separately packaged releases.

## 2026-10-29 — 雲端沒給字，就貼本機的

講完話，有時提示框一下就不見了，連按 Fn 的機會都沒有。查了失敗紀錄：20 次裡有 11 次是 Gemini 沒說原因就擋下回覆，大約 3 秒就結束，比「改用本機」按鈕出現的 5 秒還早。另一種是雲端回了空白，App 以為你沒講話，安靜收掉。

現在本機一直在旁邊辨識同一段錄音，所以雲端沒給字時，直接貼本機的結果。

### 這次處理的難題

- **被擋就不要再等一次：** 同一段錄音重送還是會被擋，只是多等 3 秒。有封鎖原因的回覆不再重送。
- **空白回覆不再安靜消失：** 雲端回空白、但本機有聽到字時，改貼本機，並在失敗紀錄記一筆，之後能看出有多常發生。
- **不吵你，但該知道的要知道：** 網路、逾時、被擋這類狀況直接貼本機，不跳提示；金鑰或額度出問題時，貼上後仍會提醒，免得雲端壞了你一直不知道。
- **真的沒聽到才失敗：** 只有本機也沒聽到字時，才出現紅色失敗提示和「重試」。

### 完成狀態

137 項自動測試通過，新增「被擋的回覆不重送」和「改貼本機時只在帳戶問題才提醒」。App 可以編譯。私人版已更新。被 Gemini 擋下的真實情境無法刻意重現，還沒親眼看到它改貼本機。

### Paste local Whisper when the cloud gives no text

Cloud failures after the resend, and empty cloud replies, now paste the local Whisper draft that runs beside the cloud instead of showing a failure card or ending silently. Replies blocked by the provider (`blockReason` or a blocking `finishReason`) are no longer resent, since the same audio is blocked again. Key and quota problems still show a notice after pasting. The failure card with「重試」appears only when local Whisper also hears nothing. 137 automated tests passed; not yet seen in a real blocked reply.

## 2026-10-28 — 按下「改用本機」，答案已經在那裡

上一版的「改用本機 · Fn」按下去之後，本機才開始辨識，等了雲端 5 秒，還要再等一次本機。現在雲端和本機從一開始就同時處理同一段錄音：平常仍貼雲端的結果；雲端超過 5 秒時按 Fn，本機的答案通常已經算好，馬上貼上。

### 這次處理的難題

- **兩邊同時跑，不能互相干擾：** 本機用自己的取消開關。按「改用本機」只中止雲端，不會把正在算的本機一起停掉。
- **雲端先回來時，本機不能硬砍：** 硬停會殺掉常駐的本機辨識程序，下一次就要重新載入模型。所以讓它默默算完再丟掉結果。
- **錄音檔不能先被刪：** 雲端貼完後 App 會刪掉錄音，本機那邊改讀同一個檔案的硬連結，算完自己刪除。
- **代價：** 雲端模式每次講話，電腦都會多跑一次本機 Whisper，比較耗電和 GPU。

### 完成狀態

135 項自動測試通過，新增「本機結果可立即取用」「取消後不再等待」「本機失敗只在讀取時出現」。App 可以編譯。還沒在真實的慢雲端情境按過 Fn。

### Local Whisper runs beside cloud recognition

Cloud and local Whisper now start on the same recording together. The cloud result is still the one pasted; when the cloud takes 5 seconds or more, tapping Fn pastes the local result, which is usually ready already. The local job has its own cancellation token and reads a hard link of the recording, so skipping the cloud does not stop it and a finished cloud does not kill the resident worker. Every cloud dictation now also runs local Whisper. 135 automated tests passed; not yet tried in a real slow session.

## 2026-10-27 — 雲端慢的時候，讓你自己決定要不要等

講完一段話，雲端有時幾秒就回來，有時要等很久。等的人不知道還要多久，也沒有辦法改變什麼。這次我們不替你猜，等滿 5 秒就把選擇交給你：辨識框右側浮出「改用本機 · Fn」，點它或再按一次 Fn，雲端立刻取消，改用電腦上的 Whisper 辨識同一段錄音。

### 這次處理的難題

- **雲端偶爾就是會慢：** 實測同時送出 10 次一分鐘的語音，有 1 次將近 50 秒才回來。提高或降低等待上限都只是替使用者猜，所以改成讓人自己選。
- **不要多學一個新東西：** 按鈕位置、樣子和「再按一次 Fn」的手勢，都跟校正時的「先貼原文 · Fn」相同。
- **按下去不能再等模型載入：** 雲端模式平常不載入本機引擎。按鈕出現的那一刻，就在背景先載入，按下時通常不必從頭等。
- **不能貼兩次：** 改用本機後，雲端請求立即取消；就算自動重送剛好要開始，也不會再送出新的上傳。
- **說清楚代價：** 本機結果不再經過雲端校正，標點和用字可能比雲端粗糙；但那段話會留下來。

### 完成狀態

132 項自動測試通過，包含按鈕出現的時機，以及改用本機後不再上傳。私人版已更新為這一版。雲端變慢無法刻意重現，這顆按鈕還沒在真實畫面上看過。

### Choose local recognition when the cloud is slow

After 5 seconds of cloud recognition, including upload, reply and the automatic resend, the recognition panel shows「改用本機 · Fn」. Clicking it or tapping Fn once cancels the cloud request and recognizes the same recording with local Whisper. It follows the existing「先貼原文 · Fn」pattern. The local engine starts loading when the button appears, and no new upload starts after the switch. Local text skips cloud correction, so punctuation may be rougher. 132 automated tests passed; the button has not yet been seen in a real slow session.

## 2026-10-26 — 講了一大段，不該因為一次失敗就消失

使用 Gemini 一趟式辨識時，偶爾講完一大段話，換來的是「服務商的回覆格式不符合預期」。這代表 Google 回了訊息，但裡面沒有任何文字；而那段錄音在失敗的瞬間就被刪除，只能重講一次。

### 這次處理的難題

- **找不到原因：** 用合成語音、照 App 相同的模型與設定送出 1 分鐘、3 分鐘、6 分鐘，再把 1 分鐘的音檔同時送 10 次，13 次全部正常回傳，沒有重現。App 為了隱私不保存回覆，所以事後也查不到。
- **先止血，再找病因：** 遇到空白或不完整回覆、服務暫時無法使用、逾時或斷線時，在背景自動重送同一段錄音一次，使用者不必做任何事。金鑰、額度與請求格式錯誤再送也會失敗，所以不重送。
- **錄音要留給使用者：** 重送也失敗時，紅色提示多一顆「重試」。錄音只放在記憶體，提示關閉就釋放，不寫成檔案。正在錄下一段時按重試，提示會保留，錄音不會遺失。
- **下次要抓得到兇手：** 每次失敗都寫入本機 `Config/transcription-failures.json`，保留最近 20 筆。內容只有 HTTP 狀態、結束原因、阻擋原因與 token 數，不含錄音、文字、字典或金鑰；測試會確認回覆中的文字不會混進紀錄。

### 完成狀態

131 項自動測試通過。私人版已更新。真正的失敗原因仍未知，要等下一次失敗的紀錄；「重試」按鈕尚未在真實失敗中看過。

### Keep the recording when cloud recognition fails

Gemini one-pass recognition sometimes returns a reply with no text, and the recording used to be deleted at once. Synthetic-speech runs did not reproduce it, so this release limits the loss first: transient failures are resent once automatically, and a final failure offers「重試」while the recording stays in memory until the card closes. Each failed attempt is logged locally with reply metadata only, never audio or text. 131 automated tests passed; the root cause is still unknown.

## 2026-10-25 — 轉圈不該說謊

辨識失敗時，螢幕上方跳出紅色的「語音辨識未完成」，底下的「語音辨識中」卻還在轉，秒數繼續往上跳。畫面同時說了兩件相反的事，看起來像還在努力，其實早就結束了。

### 這次處理的難題

- **那個秒數不是錄音長度：** 它是從開始處理到現在的計時器。失敗後沒有關掉辨識框，計時就一直跑下去。
- **同樣的漏洞不只一處：** 語音辨識、翻譯與繁體轉換失敗，都改成先關辨識框，再顯示失敗提示。
- **沒有回應也不能一直等：** 以前雲端沒回應時固定等 180 秒。現在是 15 秒加上錄音長度的四分之一，上限 180 秒：16 秒的錄音最多等 19 秒，長錄音仍有足夠時間。OpenAI 與 Gemini 都適用。

### 完成狀態

129 項自動測試通過，私人版已更新。辨識框關閉的畫面尚未在真實失敗中確認。

### No stale spinner after a failure

The recognition panel now closes whenever a failure card appears, so its spinner and elapsed-seconds counter no longer keep running after a failed job. Cloud audio requests give up on a silent reply after 15 seconds plus a quarter of the recording length, at most 180 seconds. 129 automated tests passed.

## 2026-10-24 — 多兩個 Google Gemini 語音辨識選項

除了本機 Whisper 和 OpenAI，現在也能用 Google Gemini 辨識語音。一種專心把聲音轉成文字，另一種一次就交回校正好的文字。兩種都要先同意上傳錄音。

### 這次處理的難題

- **兩種用法，各有取捨：** Gemini Transcribe（`gemini-3.5-transcribe`）用 smart 模式轉寫，並把字典詞當成自訂詞彙；辨識完照原設定校正。Gemini 一趟式（`gemini-3.8-flash`）直接從錄音交回校正後的文字，省掉第二次校正請求。
- **同意與金鑰跟著服務商走：** 沿用加密保存的 Google 金鑰，跟 OpenAI 一樣需要明確同意上傳錄音。語音設定、同意文字與金鑰按鈕，會依選擇的服務商切換。
- **錄音大小有上限：** 音訊直接放在請求裡，因此設定上限，讓每次請求都在 Google 的 20 MB 限制以內。
- **順手修好 Google 文字校正：** `gemini-3.8-flash` 不接受推理等級 `MINIMAL`，會回 HTTP 400；改為送出 `low`。

### 完成狀態

固定案例測試涵蓋請求格式、同意規則、大小上限、錯誤訊息與模擬連線。真實帳號的品質與速度，仍需使用者自己量測。

### Two Google Gemini speech options

Gemini Transcribe (`gemini-3.5-transcribe`, smart mode, dictionary words as custom vocabulary) and Gemini one-pass (`gemini-3.8-flash`, corrected text from the audio in one request) join local Whisper and OpenAI. Both reuse the encrypted Google key and require explicit audio consent; inline audio stays under Google's 20 MB limit. Google text correction now sends thinking level `low`, because `gemini-3.8-flash` rejects `MINIMAL` with HTTP 400. Fixture tests cover requests, consent, limits, sanitized failures and mock transport; real-account quality and latency still need the user's own measurement.

## 2026-10-21 — 校正沒套用時看得出來，等太久時可以先貼

雲端校正失敗時，貼上的原文看起來跟成功一樣，使用者不會知道少了校正；校正慢的時候，也只能乾等。

### 這次處理的難題

- **失敗要看得見，但不能擋住輸入：** 校正沒有套用、改貼原文時，螢幕上方出現簡短提示；真的什麼都沒貼上，則用另一張卡片。兩者都不蓋住輸入框。
- **等超過 3 秒，可以先貼原文：** 校正或翻譯超過 3 秒，可以先貼一次原文，其餘工作不會被取消。離線時，在送出前就略過雲端請求。
- **先知道慢在哪裡：** 記錄校正的連線、上傳與等待回覆秒數。開啟校正時，可能先對服務商主機預熱連線，不帶金鑰，也不帶文字。校正等待時間仍不設上限。

### 完成狀態

OpenAI 校正的推理強度沒有更動。真實的品質比較會花費 API 額度，需要使用者明確同意後才會進行。

### Visible correction failures and an early paste

A short top notice appears when correction was not applied and the original was pasted; failures that paste nothing use a separate card, and neither covers the input. After 3 seconds of correction or translation, the original can be pasted once without cancelling the job. Offline skips the cloud request before it is sent. Correction timing is recorded, and a keyless host warmup may run. OpenAI reasoning is unchanged; a live quality comparison still needs explicit permission.

## 2026-10-16 — Chrome 讀不到輸入框時，自己找回來

在 Chrome 裡聽寫時，App 偶爾讀不到正在輸入的欄位，就無法確認文字要貼到哪裡。

### 這次處理的難題

- **向 Chrome 要一次輔助資訊：** 原本的前景視窗沒有可編輯焦點時，請 Chrome 開啟整個程式的輔助使用資訊一次，並持續重新偵測，涵蓋延遲啟用的情況。
- **寧可不貼，也不亂貼：** 保留可編輯目標驗證、只貼一次、取消與手動補救；不會改成對整個瀏覽器盲貼，也不會送出搜尋。

### 完成狀態

模擬測試涵蓋快速、延遲、無法取得、取消、手動與背景瀏覽器等情境。實際 Chrome 相容性需要另外驗證。

### Chrome editable-focus recovery

When the foreground target lacks editable focus, the app asks Chrome once for process-wide accessibility and retries detection long enough to cover delayed activation. Verification, one-shot paste, cancellation and manual recovery stay in place; it never pastes blindly or submits a search. Simulated scenarios pass; native browser compatibility needs separate verification.

## 2026-10-15 — 校正改以整句判斷同音字與斷詞

語音辨識常把同音字或詞的邊界弄錯，校正要看整句話的意思，才知道該改成什麼。

### 這次處理的難題

- **同一套判斷方式：** 完整校正與舊的潤飾流程，共用依上下文判斷同音字和斷詞的指引；開啟校正的翻譯也一致。保留模稜兩可、否定與說話者原意，不寫死替換，也不增加模型呼叫。
- **狀態要記對：** 舊的潤飾成功時，記為 corrected 或 unchanged，不再誤記為 not_requested；只記狀態，不記文字。

### 完成狀態

離線檢查只驗證請求的組成與「沒有改字也接受」，不代表模型準確度，也無法說明過去辨識錯誤的原因。測試沒有收集任何私人錄音、上下文或逐字稿。

### Sentence-level correction guidance

Full-text correction, the legacy polish route and correction-enabled translation share contextual homophone and word-boundary guidance, preserving ambiguity, negation and intent without hardcoded substitutions or extra model calls. Successful legacy polishing is recorded as corrected or unchanged. Offline checks verify request construction only, not model accuracy.

## 2026-10-14 — 第一次安裝更安全，說明更好找

第一次安裝要準備模型、簽署與授權，步驟一多就容易出錯，說明也散在不同地方。

### 這次處理的難題

- **安全建立私人執行版：** 只複製允許清單內的檔案、檢查模型校驗碼、不覆蓋既有安裝，並用合成資料測試失敗情境。
- **步驟順序一致：** README、AI 安裝與簽署說明統一為「準備 → 簽署 → 為私人 App 授權」，並加入下載逾時上限與重試指引。
- **文件有入口：** 新增文件首頁、使用手冊、英文概覽與常見問題，以及檢查 AI 是否依據文件回答的測試；同步更新架構與隱私說明，以及 llms.txt 的正式 Markdown 連結。

### Safer first install and clearer docs

First-install preparation creates a separate private runtime with allowlisted files and model checksums, refuses to overwrite an existing installation, and has synthetic failure tests. README, AI installation and signing guides now share one order: prepare, sign, then grant permissions. A documentation home, user manual, English overview, FAQ and evidence-based AI reading checks were added, and llms.txt links to canonical Markdown.

## 2026-10-13 — 可選的錄音上下文與取消按鈕

辨識時若能參考游標附近的文字，人名和專有名詞比較容易認對；處理途中想反悔時，也需要一個能停下來的按鈕。

### 這次處理的難題

- **上下文只讀一小段：** 讀取游標附近有限長度的文字；要傳給 OpenAI 需要另外同意，預設關閉。擷取的文字不寫入檔案、診斷紀錄或開發用固定案例。
- **每個工作都能取消：** 處理中顯示小型取消按鈕，可以單獨取消這次工作；過期的進度與貼上回呼會被忽略。

### 完成狀態

合成資料測試涵蓋同意開關、上下文長度、過期結果與原生設定。不同 App 能否讀到上下文、實際準確度能提升多少，依環境而定。

### Optional recording context and cancellation

Bounded nearby-text context can help recognition, with separate, default-off OpenAI context consent; captured text stays out of files, diagnostics and fixtures. A compact cancel control stops each job, and stale progress or paste callbacks are ignored. Synthetic tests cover consent, bounds, stale results and native settings.

## 2026-10-13 — 統一模組名稱，私人資料改用新加密格式

### 這次處理的難題

- **名稱一致：** Swift 目標、匯入、原始碼與測試路徑、文件，統一為 EdgelessType、EdgelessTypeCore、EdgelessTypeTests。
- **加密格式升級不能掉資料：** 一般憑證改用 v2 驗證式加密格式與新檔名；透過經過測試的離線一次性遷移，保留服務商紀錄與金鑰，金鑰表備份與加密資料備份分開存放。
- **不破壞既有安裝：** 保留已安裝的簽署 ID、憑證身分與語音引擎通訊協定；舊名稱只留在這些穩定介面與遷移讀取器中。

### 完成狀態

提供準備、完成、還原三個遷移工具與合成遷移測試，不含任何私人資料或簽署金鑰。

### Unified module names and explicit private-data migration

Targets, imports, paths and docs now use EdgelessType, EdgelessTypeCore and EdgelessTypeTests. Credentials move to v2 authenticated-encryption envelopes through a tested offline one-time migration with separate key-table backups. Installed signing IDs, certificate identity and the speech-worker protocol are preserved. Prepare, finalize and rollback tools ship with synthetic tests only.

## 2026-10-13 — 處理狀態更清楚，本機更新更穩

錄音停止之後，畫面要讓人看得出現在進行到哪一步；更新私人版時，也不能因為重新簽署而弄丟系統權限。

### 這次處理的難題

- **每一步都看得出來：** 錄音、上傳、辨識、校正與翻譯分開顯示；處理中以轉圈、階段名稱和經過秒數呈現，不再顯示錄音控制。
- **連線省一點：** 重用不留快取、cookie 與憑證的連線；同時開啟校正與翻譯時合併成一次請求，保留原本的服務商與模型選擇。
- **記下時間，不記內容：** 系統有提供時，記錄上傳、等待回覆與連線秒數；不記錄錄音或文字。實際速度依環境而定。
- **更新不弄丟權限：** 本機更新必須使用穩定、有憑證支撐的簽署身分；本機版與公開或測試版的 bundle ID 分開；驗證身分連續，失敗時還原原本已簽署的檔案。也支援自訂本機 App 名稱，從公開原始碼單向更新私人執行版，保留個人資料並記錄建置來源。
- **自己簽署：** 新增逐步簽署指南與只讀取中繼資料的小工具，協助每位使用者選擇自己鑰匙圈中的身分；不散布作者的憑證或私鑰。
- **句尾不加句號：** 聽寫與翻譯的預覽及貼上文字，移除句尾的中英文句號；句中標點保留。
- **Grok Bot 也能自動貼上：** 對讀不到輔助使用焦點的編輯器，加入窄範圍備援：原本的程式仍在前景時，只送一次貼上。使用者已確認自動貼上與預覽收起；其他版本與欄位尚未驗證。
- **公開工程筆記：** 發布去識別化的[工程指南](docs/ENGINEERING-LESSONS.md)，記錄診斷步驟、失敗的嘗試、可重現的檢查與證據限制，並更正關於雲端音訊的過時架構說明。

### Clearer processing states and stable local updates

Recording, upload, recognition, correction and translation now show as distinct states with a spinner, stage name and elapsed time. HTTP sessions are ephemeral and reused, and correction plus translation share one request. Local updates require a stable certificate-backed identity, keep a separate bundle ID and restore signed files on failure. A personal signing guide, trailing full-stop removal, a narrow Grok Bot paste fallback and a de-identified [engineering guide](docs/ENGINEERING-LESSONS.md) were added.

## 2026-10-11 — 辨識和校正可以分開選

語音辨識與文字校正原本綁在一起。有人想用雲端辨識，有人只想在本機處理；舊的校正流程也可能因為一個替換字沒通過本機規則，就把整段回覆丟掉。

### 這次處理的難題

- **辨識方式自己選：** App 選單與字典視窗可以選擇 Whisper（本機）或 GPT Transcribe（OpenAI 雲端）。本機 Whisper 仍是預設；選擇在錄音開始時固定，這段錄音不會中途改變。
- **上傳錄音要先同意：** 啟用 OpenAI 辨識前需要明確同意上傳錄音。專用的 OpenAI 金鑰設定沿用加密紀錄，不影響校正服務商的選擇。
- **連線只走固定路線：** 固定的 HTTPS 端點、通用的上傳檔名、WAV 與檔案大小檢查、阻擋轉址，錯誤訊息不外洩細節。雲端模式不預熱本機 Whisper，也不會默默改用其他後端。
- **校正改收整段文字：** 不再要求模型回傳逐字替換清單，而是直接接受完整的校正文字，只檢查傳輸成功、回覆完整、內容非空，再於本機轉成繁體。移除同音字比對、修改次數、字數、位置比對與標點比較等限制。
- **長文與失敗都照舊安全：** 長文分段校正後一次貼上，校正後不再額外潤飾；所有輸出（包含退回的原文）都先轉成繁體。失敗、不完整或空白的回覆，維持原本的提示與補救方式。本機失敗紀錄只保存原因代碼、服務商與時間，之後的成功不會覆蓋它。

### 完成狀態

本機 96 項核心測試、貼上流程回歸測試、App 自我檢查與文件隱私檢查都通過。原生設定測試確認預設為本機、未同意時無法開啟雲端、選擇會保存，也能切回本機 Whisper。雲端辨識測試沒有使用真實金鑰或私人錄音；實際能否使用，取決於使用者的 OpenAI 帳號。雲端辨識需要網路與 API 額度，會把錄音傳給 OpenAI，每個檔案上限 25 MB；基本回覆檢查無法保證模型品質或原意不變。

### 特別感謝 / Acknowledgments

感謝 [@plumy_river（X）](https://x.com/plumy_river)／[@plumyriver0327（Threads）](https://www.threads.com/@plumyriver0327) 對本次更新提供的開發協助與支持。

Special thanks to [@plumy_river on X](https://x.com/plumy_river) / [@plumyriver0327 on Threads](https://www.threads.com/@plumyriver0327) for their development assistance and support for this update.

### Selectable transcription and full-text correction

Recognition and correction are now separate choices: local Whisper by default, or OpenAI GPT Transcribe after explicit audio-upload consent. The cloud path uses a fixed HTTPS endpoint, WAV and size checks, redirect blocking and sanitized errors, and never silently falls back to another backend. Correction now accepts the model's complete text after transport, completeness and non-empty checks, followed by local Traditional Chinese conversion. 96 core tests and the paste-flow, self-check and privacy checks passed; no real credentials or private recordings were used. Hosted CI results are in [GitHub Actions](https://github.com/0xedgelessblade/edgelesstype/actions).

## 2026-10-11 — 貼上更可靠，校正失敗看得出來

在 Codex 裡聽寫時，文字有時沒有自動貼上；手動貼上後預覽不會收起；校正失敗時，畫面也看不出來。

### 這次處理的難題

- **Codex 讀不到輸入框也能貼：** Codex 的輔助介面沒有提供焦點編輯器時，只在原本的 Codex 仍在前景時送出一次貼上。
- **不重複貼上：** 手動貼上後預覽會收起；等待送出時的重複貼上請求會被吃掉，已確認插入的文字不會再送第二次。
- **找得到更多輸入框：** 支援巢狀焦點與可編輯的上層元素，並能讀回帶格式的文字與字元範圍。沒有驗證到的鍵盤送出，不會被當成已確認插入。
- **校正不再被短秒數打斷：** 移除校正原本 4 秒與 8 秒的期限，等到完成或真的出錯為止；翻譯仍保留設定的期限。長文依句子邊界切成約 1,200 字的段落，保留空白與技術片段，各段校正後一次貼上。
- **一律輸出繁體：** 辨識結果、模型輸出、退回的原文、預覽與最後貼上前，都在本機轉成繁體；轉換失敗就停止輸出，不貼出未轉換的文字。
- **失敗要說出來：** 校正失敗時顯示可關閉的明確提示，不再看起來像成功。額度或頻率限制的提示文字為：

  > **AI 校正未完成**
  >
  > 服務端額度不足或請求過於頻繁。<br>
  > 請檢查服務商帳戶或稍後再試。

  翻譯失敗時直接告知，不插入失敗的翻譯；校正已失敗時，也不再多送一次潤飾請求。

### 完成狀態

本機 80 項核心測試通過，包含 9 秒延遲的服務商固定案例、長文完整性、繁體轉換與錯誤提示。記憶體中的貼上流程檢查涵蓋自動與手動貼上、防止重複、剪貼簿變化、取消、Codex 備援與最後的轉換關卡，但不操作真實編輯器。使用者已實際確認 Codex 自動貼上與預覽收起；原生警告畫面以固定、不含個資的文字檢查過。

這次原始碼更新不含錄音、真實聽寫範例、API 金鑰、私人字典、執行設定或本機診斷檔。服務商的額度、頻率、回覆大小與網路問題仍可能發生；Codex 備援無法透過輔助介面證明已插入，因此會保留剪貼簿內容供補救，也不宣稱一定適用每一種編輯器或未來版本。

### Paste reliability and output controls

Automatic paste works again in Codex when its accessibility interface hides the focused editor, previews close after manual paste, and confirmed insertions are never sent twice. Correction no longer has 4- and 8-second deadlines, long dictation is corrected in ordered segments of about 1,200 characters and pasted once, and every output is converted to Traditional Chinese locally or not pasted at all. Correction failures now show a dismissible notice. 80 core tests and in-memory paste-flow checks passed; a scoped Codex user test confirmed automatic paste. Hosted CI results are in [GitHub Actions](https://github.com/0xedgelessblade/edgelesstype/actions).

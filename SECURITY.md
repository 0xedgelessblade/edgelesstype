# 隱私與金鑰

API 金鑰使用 AES-256-GCM 保存於 `private/store.encrypted.json`。本機加密金鑰表位於使用者的 `~/.config/codex-secrets/open-typeless-keyring.json`，資料夾權限 700、檔案權限 600。兩者均不得加入公開 repository。

每家服務商有獨立的隨機紀錄，切換或刪除一家不會覆蓋其他家。讀不到、損壞或不配對的密文不能自動覆寫。App 不使用明碼 `.env`、日誌或 macOS 鑰匙圈存放 API 金鑰。

正式 API 請求只走固定 HTTPS 端點，不跟隨重新導向。UI 測試只傳送固定測試句。錯誤訊息不顯示服務商原始回應，避免把金鑰或轉寫內容帶到畫面。

公開檢查涵蓋原始碼檔案清單、個人路徑、Email、常見 token 格式、私鑰區塊，以及預設字典。自動檢查不能保證絕對匿名，發布前仍應看過待提交的 diff。Git 作者名稱與 Email 也是公開內容；使用公開別名與 GitHub noreply Email。

不要把敏感問題、金鑰或私人資料貼進公開 issue。若金鑰曾公開，應先到服務商撤銷或輪替；只刪除目前檔案不會抹除舊提交或其他人的副本。

每位使用者各自在自己的 Mac 建立金鑰表和密文檔；這些舊命名路徑不是 Codex 雲端，也不是 macOS Keychain。本專案沒有收集使用者 API 金鑰的後台。呼叫 API 時，金鑰會作為認證傳送給使用者選定的服務商。

此設計防範分享專案時連帶洩漏，並非對抗已控制同一使用者帳戶的程式：若同時取得密文及本機解密鑰匙，便可能讀出 API 金鑰。App「刪除金鑰」只移除本機紀錄；撤銷 API 權限須到服務商操作。

Clipboard restoration keeps a bounded, temporary copy of prior pasteboard items in memory only. It is not written to disk or sent to an API. The copy is released when an offer succeeds or is cancelled. Restoration requires confirmed insertion and unchanged pasteboard ownership; large or incomplete snapshots are not restored.

Paste diagnostics write at most 64 fixed stage labels for the latest offer to a local temporary file. They contain no transcript, clipboard contents, window titles, keys, or arbitrary application identifiers. They are not transmitted and must not be included in public exports or issue attachments.

## Optional audio transcription

Local Whisper remains the default. Audio upload requires a separately stored OpenAI transcription choice and explicit audio consent. The choice is captured when recording starts. Only that recording is posted to the fixed HTTPS OpenAI transcription endpoint; redirects, cookies, credential storage and persistent response caching are disabled. The upload uses a generic filename, never a personal file path. Audio, response text and keys are not logged. The existing temporary recording is deleted after processing, including failures.

The OpenAI transcription option reuses the encrypted OpenAI key record, independently of the selected text-correction provider. Merely opening the settings or saving a key does not enable audio upload. Preferences are runtime data in `Config/transcription.json` and are excluded from Git and public exports. Tests use synthetic bytes and URLProtocol fixtures, not private recordings or real credentials.

## Local code-signing identity

API credentials keep the encrypted-file design above. A separate, user-approved code-signing identity may live in the login Keychain solely to give the local app a stable identity across updates. It is not an API key and is never exported or published. Public CI uses no private signing identity. Local updates require the private signing profile and verify continuity instead of falling back to ad-hoc signatures. See [stable local signing](docs/LOCAL-SIGNING.md).

HTTP session reuse retains connection state, not disk response caches, cookies or credential storage. Audio requests can report numeric upload progress and transaction timings; unavailable timings remain absent. Translation with enabled context correction sends transcript and vocabulary together to the already-selected provider in one request. Runtime timing records contain no transcript, recording, dictionary, key, URL or request ID and must not be published.

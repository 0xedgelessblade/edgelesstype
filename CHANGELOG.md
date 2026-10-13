# Changelog

## Unreleased

- Add a step-by-step personal signing guide and a metadata-only helper to select each user's own Keychain identity; no author certificate or private key is distributed.
- Record user-confirmed Grok Bot automatic paste and preview dismissal.

- Require a stable certificate-backed identity for local updates, separate the local bundle ID from public/test builds, verify continuity and restore original signed files on failure.

- Remove trailing Chinese/English full stops from final dictation and translation previews and paste text; preserve internal punctuation.

- Add a narrow Grok Bot fallback for editors without readable accessibility focus; send paste once while the original process remains foreground. Live automatic insertion still requires target-app verification.
- Support a distinct local app display name and a one-way updater from public source to a private runtime, preserving personal data and recording build provenance.

Notable changes to edgelesstype. Dates identify source updates; they do not imply a separately packaged binary release.

## 2026-10-11 — Selectable transcription and full-text correction

### Why this change

Speech recognition and text correction now have independent choices. Local Whisper remains the default, while an explicit OpenAI option supports workflows that prefer cloud transcription. This update does not claim that either route is universally faster or more accurate.

The previous correction path could reject an entire reply when a word substitution failed a local content rule. Correction now accepts the model's complete text directly, with successful transport, completion and non-empty output checks, followed by local Traditional Chinese conversion.

### Added

- A speech-recognition selector in the app menu and dictionary window: **Whisper (local)** or **GPT Transcribe (OpenAI cloud)**.
- Explicit audio-upload consent before enabling OpenAI transcription. The choice is captured at recording start and remains stable for that recording.
- A dedicated OpenAI key-settings entry that reuses the encrypted OpenAI record without changing the text-correction provider.
- A fixed HTTPS audio-transcription endpoint, generic upload filenames, WAV/file-size checks, redirect blocking and sanitized error messages. Cloud mode skips local Whisper warm-up and does not silently fall back to another backend.

### Changed

- Request full corrected text instead of a structured list of word substitutions.
- Remove homophone/dictionary matching, edit-count and word-length limits, source-position matching, overlap checks and punctuation comparison from the normal correction path.
- Preserve long-text segmentation and paste the combined result once. Do not run an additional polish pass after contextual correction.
- Keep Traditional Chinese conversion before preview and paste, including fallback text. Failed, incomplete or empty replies retain the existing warning and recovery behavior.
- Retain a separate local failure-status record containing only a fixed reason code, provider and timestamp; a later success no longer overwrites the latest failure record.
- Update the UI and privacy documentation to distinguish optional audio upload from text-only correction. Runtime preferences and diagnostics remain excluded from Git and public exports.

### Validation and boundaries

- 96 core tests passed locally, covering backend selection, consent gating, request/response formats, mocked network transport, full-text correction and Traditional Chinese conversion.
- Paste-flow regression tests, app self-check and documentation/privacy checks passed locally. Native settings tests verified the local default, blocked cloud activation without consent, persisted choices and switching back to local Whisper.
- No real API credentials or private recordings were used for cloud-transcription testing. Actual account/model access still depends on the user's OpenAI account.
- Cloud transcription requires network access and API credit, sends the recording to OpenAI and has a 25 MB per-file limit. Model quality and unchanged meaning are not guaranteed by the basic reply checks. Hosted CI results are tracked separately in [GitHub Actions](https://github.com/0xedgelessblade/edgelesstype/actions).

### Acknowledgments / 特別感謝

Special thanks to [@plumy_river on X](https://x.com/plumy_river) / [@plumyriver0327 on Threads](https://www.threads.com/@plumyriver0327) for their development assistance and support for this update.

感謝 [@plumy_river（X）](https://x.com/plumy_river)／[@plumyriver0327（Threads）](https://www.threads.com/@plumyriver0327) 對本次更新提供的開發協助與支持。

## 2026-10-11 — Paste reliability and output controls

### Fixed

- Restored automatic paste in Codex when its accessibility interface does not expose a focused editor. The fallback sends a single paste chord only while the original Codex process is in the foreground.
- Fixed previews remaining open after manual paste. Queued paste requests are consumed while delivery is pending, and an already-confirmed automatic insertion is not sent a second time.
- Expanded focus resolution to nested focus relationships and editable ancestors, and added text readback support for attributed values and character ranges.
- Kept unverified keyboard delivery separate from confirmed insertion. Clipboard restoration and confirmed-insertion timing still require destination readback.

### Changed

- Removed the previous four-second and eight-second application deadlines for contextual correction. Correction waits for completion or a transport/provider error; translation retains its configured deadline.
- Processed long dictation in ordered segments of approximately 1,200 characters, preferring sentence boundaries and preserving whitespace and protected technical spans. Each segment uses the existing correction validator before the combined result is pasted once.
- Enforced local Traditional Chinese conversion for recognition results, model output, fallback text, previews, and the final paste entry point. Conversion failure stops output instead of returning unconverted text.
- Added persistent, dismissible correction-failure notices. A failed correction no longer silently looks like a successful one. The quota/rate-limit notice uses this wording:

  > **AI 校正未完成**
  >
  > 服務端額度不足或請求過於頻繁。<br>
  > 請檢查服務商帳戶或稍後再試。

- Reported translation failures without inserting an unsuccessful translation, and avoided a follow-up polish request after correction has already failed.

### Validation

- 80 core tests passed locally, including a delayed nine-second provider fixture, long-text integrity, Traditional Chinese conversion, and error-notice cases.
- Repeatable in-memory paste-flow checks cover automatic/manual delivery, duplicate prevention, clipboard changes, cancellation, the Codex fallback, and the final conversion gate. These checks do not control a real desktop editor.
- Automatic paste and preview dismissal were confirmed through a scoped Codex user test. The native warning layout was checked with fixed, non-sensitive fixture text.
- Release build, documentation references, and public-source checks passed locally. Hosted CI results are tracked separately in [GitHub Actions](https://github.com/0xedgelessblade/edgelesstype/actions).

### Privacy and limitations

- No recordings, real dictation samples, API credentials, private dictionaries, runtime settings, or local diagnostic files are included in this source update.
- Local paste diagnostics contain bounded, fixed stage labels only; they do not contain dictated text or clipboard contents and are not uploaded.
- Provider quotas, rate limits, response-size limits, and network failures still apply. Long text may require multiple correction requests. An indivisible technical span can exceed the normal segment size.
- The Codex fallback cannot prove insertion through accessibility readback. It retains the dictated clipboard for recovery and records delivery without claiming confirmed insertion. Compatibility with every editor or future app version is not implied.

### 繁體中文摘要

- 修復 Codex 自動貼上、手動貼上後預覽不收起，以及貼上時序造成的重複輸入。
- 移除上下文校正的短秒數期限，長文分段校正後一次合併貼上。
- 所有中文結果在本機轉為繁體；轉換失敗時停止輸出。
- 校正失敗顯示可關閉的明確提示，額度／頻率限制採用上方指定文案。
- 公開內容僅包含原始碼、固定測試與文件；驗證範圍與已知限制如上所述。

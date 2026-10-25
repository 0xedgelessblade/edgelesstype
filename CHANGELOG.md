# Changelog

## 2026-10-25 — No stale spinner after a failed recognition

- Hide the recognition panel whenever a failure card is shown (speech, translation and Traditional Chinese conversion). Previously the panel kept spinning and its elapsed-seconds counter kept rising after the job had already failed.
- Cloud audio requests (OpenAI and Gemini) now give up on a silent reply after 15 seconds plus a quarter of the recording length, at most 180 seconds, instead of always waiting 180 seconds.
- A cloud recognition failure still pastes nothing and does not fall back to local Whisper.

## 2026-10-24 — Google Gemini speech backends

- Add two opt-in Google speech backends beside local Whisper and OpenAI: Gemini Transcribe (`gemini-3.5-transcribe`, smart mode, dictionary words as custom vocabulary) and Gemini one-pass (`gemini-3.8-flash` returns corrected text from the audio in a single request; no separate correction request follows, timing outcome `merged`).
- Both reuse the encrypted Google key record and require the same explicit audio consent as OpenAI; the speech settings, consent text and key button now follow the chosen provider. Inline audio is capped so requests stay under Google's 20 MB limit.
- Fix Google text correction: `gemini-3.8-flash` rejects thinking level `MINIMAL` with HTTP 400, so requests now send `low`.
- Fixture tests cover request shape, consent, size limits, sanitized failures and mock transport; real-account quality and latency still need the user's own measurement.

## 2026-10-21 — Correction notices and transfer timing

- Show a short top notice when corrected text could not be applied and the original was pasted. Real failures that paste nothing use a separate card. Neither covers the input.
- After three seconds of correction or translation, offer to paste the original once without cancelling the rest of the job. Offline skips the cloud request before it is sent.
- Record numeric correction connection, upload and response-wait timings. A keyless host warmup may run when correction is enabled; it sends no credential or text. Timeout remains unlimited.
- OpenAI correction reasoning is unchanged. A live quality comparison still needs explicit permission.

## 2026-10-16 — Chrome editable-focus recovery

- Request Chrome process-wide accessibility exposure once when the original foreground target lacks editable focus, then retry detection long enough to cover delayed activation.
- Preserve editable-target verification, one-shot paste, cancellation and manual recovery; never fall back to blind browser-wide paste or submit a search.
- Add simulated fast, delayed, unavailable, cancelled, manual and background-browser tests; native browser compatibility requires separate verification.

## 2026-10-15 — Sentence-level speech correction guidance

- Share contextual homophone and word-boundary guidance between full-text correction and the legacy polish route; align correction-enabled translation. Preserve ambiguity, negation and speaker intent without hardcoded substitutions or additional model calls.
- Record successful legacy polishing as corrected/unchanged rather than not_requested, using status only.
- Offline checks verify request construction and unchanged-text acceptance, not model accuracy or the cause of historical speech errors. No private recordings, context or transcripts are collected for tests.

## 2026-10-14 — Installation and documentation paths

- Add safe first-install preparation of a separate private runtime, with allowlisted artifacts, model checksum checks, refusal to overwrite existing installations and synthetic failure tests.
- Align README, AI installation and signing instructions: prepare, sign, then grant permissions to the private app. Add bounded download timeouts and retry guidance.
- Add a documentation home, user manual, English overview, FAQ and evidence-based AI reading checks; update architecture/privacy descriptions and canonical Markdown links in llms.txt.

## 2026-10-13 — Optional recording context and cancellation

- Add bounded nearby-text context with separate, default-off OpenAI context consent; keep captured text out of files, diagnostics and development fixtures.
- Add a compact processing cancel control and per-job cancellation; ignore stale progress and paste callbacks.
- Test consent gating, bounded context, stale-result rejection and native setting controls with synthetic data. Cross-app context availability and real accuracy gains remain environment-dependent.

## 2026-10-13 — Unified module names and explicit private-data migration

- Rename Swift targets, imports, source/test paths and documentation to EdgelessType / EdgelessTypeCore / EdgelessTypeTests.
- Move normal credential storage to v2 authenticated-encryption envelopes and new data filenames. Preserve provider records and key material through a tested offline one-time migration, with key-table backups separate from encrypted-data backups.
- Preserve installed signing IDs, certificate identity and the existing speech-worker protocol. Keep legacy names only where required by these stable contracts or the explicit migration reader.
- Add prepare/finalize/rollback tools and synthetic migration tests; no private data or signing keys are included.


## 2026-10-13 — Stable local updates, processing clarity and engineering guide

- Show distinct recording, upload, recognition, correction and translation states; processing uses a spinner, stage label and elapsed time instead of recording controls.
- Reuse ephemeral HTTP sessions without caches, cookies or stored credentials; combine enabled text correction with translation in one request while preserving provider and model choices.
- Record numeric upload/response-wait/connection timing when Foundation provides it; no recordings or text are logged. Real end-to-end speed remains environment-dependent.

- Add a step-by-step personal signing guide and a metadata-only helper to select each user's own Keychain identity; no author certificate or private key is distributed.
- Record user-confirmed Grok Bot automatic paste and preview dismissal.

- Require a stable certificate-backed identity for local updates, separate the local bundle ID from public/test builds, verify continuity and restore original signed files on failure.

- Remove trailing Chinese/English full stops from final dictation and translation previews and paste text; preserve internal punctuation.

- Add a narrow Grok Bot fallback for editors without readable accessibility focus; send paste once while the original process remains foreground. A live success was user-confirmed; broader version/field support remains unverified.
- Support a distinct local app display name and a one-way updater from public source to a private runtime, preserving personal data and recording build provenance.

- Publish a de-identified [engineering guide](docs/ENGINEERING-LESSONS.md) with diagnosis steps, failed approaches, reproducible checks and explicit evidence limits. Correct outdated architecture statements about optional cloud audio.

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

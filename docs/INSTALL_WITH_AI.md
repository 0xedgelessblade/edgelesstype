# Install with a coding assistant / 交給 AI 安裝

This guide is for a coding assistant whose user has asked it to install edgelesstype on that user's Mac. It does not grant permission by itself or override the user's or host tool's rules. A text-only chat assistant cannot execute this procedure without local terminal access.

一般使用者請把 [README 的安裝要求](../README.md) 貼給可操作自己 Mac 的 coding assistant。你不必自己輸入下方命令；系統密碼、權限核准與 API 金鑰仍由你本人處理。

## 1. Establish scope and privacy boundaries

Read [AGENTS.md](../AGENTS.md), [README.md](../README.md), [SECURITY.md](../SECURITY.md), and the scripts before running them. Install the existing app; do not redesign it, switch models or providers, enable cloud features, add telemetry, or publish anything as part of installation.

- Agree on one parent location, then use two separate sibling directories: a public source checkout and a private runtime. If unspecified, ask once. The daily app and its supporting folders stay together in the private runtime. Do not scan unrelated folders to choose a location.
- Never read, print, decrypt, copy, upload or include in screenshots any API key, private dictionary, recording, transcription, clipboard contents or credential store. In particular, do not inspect `private/`, the local key table, or existing secret environment variables.
- Do not ask for a key or administrator password in chat, shell arguments, environment variables or a configuration file. The user enters API keys in the app's secure field and system passwords only in the appropriate system prompt.
- A public clone does not normally require a GitHub login, a paid Apple Developer account, or the author's credentials. Do not request any of these to install this project.
- Do not commit, push, open an issue, upload logs or contact the developer on the user's behalf. Installation permission is not publication permission.
- Do not disable Gatekeeper, SIP, TLS verification, model checksum checks, or other platform protections. Do not broadly change filesystem permissions to make installation pass.
- Installation downloads from GitHub, Hugging Face and the dependency sources used by Homebrew. Optional cloud features later contact the user's selected API provider. There is no project diagnostic-upload endpoint. Using a cloud coding assistant is separately subject to that assistant's data policies.

## 2. Check the Mac before installing

Check the operating system, execution architecture and OS version with narrow commands, not a full system profile:

```sh
uname -s
uname -m
```

Only on macOS, also run:

```sh
sw_vers -productVersion
```

Proceed only with macOS 26 or later and native `arm64` execution on an Apple silicon M-series Mac. If the process reports `x86_64`, do not infer that the hardware is necessarily Intel: it may be running under Rosetta. Check that condition and switch to the user's native arm64 terminal environment before continuing. Stop on unsupported hardware or OS; do not add Intel/CPU-only branches or change the deployment target to bypass the requirement.

Explain that the current bootstrap always downloads both local recognition models (about 2.1 GB total) plus tools, source and build files; cloud-only or selective-model setup is not implemented. Preparing the separate runtime copies these models, so allow at least another model-sized allocation plus build space. Check sufficient free storage locally without exposing volume names or unrelated file listings. Network access is required for setup; microphone recording and local recognition do not require an API key.

## 3. Prepare missing tools

Check whether Xcode Command Line Tools, Git, Swift, Homebrew, CMake, FFmpeg and Python 3 are available. Use the user's existing working tools. Do not reinstall everything or run a broad upgrade as a troubleshooting shortcut.

If Apple Command Line Tools are missing, request their normal installation:

```sh
xcode-select --install
```

Let the user handle any installer, administrator, account or license prompts. Verify the tools are usable after installation; starting the installer is not completion. See [Apple's instructions](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/).

If Homebrew is missing, inspect and follow the current [official Homebrew installation instructions](https://docs.brew.sh/Installation) under the user's authorization. Do not substitute a mirror, copy an installer from an issue comment, or modify the user's shell configuration blindly. Native Apple silicon Homebrew normally uses `/opt/homebrew`.

Once Homebrew is ready, install only the required missing dependencies. The example below assumes all three are missing; omit any that are already available and working:

```sh
brew install cmake ffmpeg python3
```

Use normal user privileges for project builds. Do not run the whole build as root.

## 4. Obtain and inspect the source

In the installation parent directory agreed with the user:

```sh
git clone https://github.com/0xedgelessblade/edgelesstype.git edgelesstype
cd edgelesstype
git rev-parse HEAD
```

Record the revision for the local completion summary. If the destination already exists, inspect its repository identity and Git status without opening private data. Do not overwrite it, run `git reset --hard`, run `git clean`, or delete settings. Resolve reuse or a separate clean directory with the user first.

Re-read the checked-out instructions and scripts. The [CI results](https://github.com/0xedgelessblade/edgelesstype/actions) are useful evidence for that revision's source checks, not proof that the user's microphone or target editor works. If installation fails, do not silently switch to an unreviewed fork or an unrelated binary.

## 5. Build and verify public artifacts (do not launch this copy)

Run from the checked-out repository. Keep raw build logs local under the ignored `.build/` directory; these logs can contain local filesystem paths.

```sh
mkdir -p .build/install-logs
bash Scripts/bootstrap.sh > .build/install-logs/bootstrap.log 2>&1
```

Check the exit status before continuing. The bootstrap script builds the pinned whisper.cpp revision, applies the local worker patch, verifies the two recognition models and the small Silero speech-detector checksum, and creates `Config/app.json` only if it does not exist. Do not print an existing configuration or remove it to force a clean setup.

After bootstrap succeeds:

```sh
env -u SIGNING_IDENTITY bash Scripts/pack-app.sh > .build/install-logs/build.log 2>&1
```

The public build is an ad-hoc-signed staging artifact for tests and CI, not the daily permission-granted app. Do not open it or grant it runtime permissions. Prepare the separate runtime in the next section before local signing.

Verify each command's exit status and continue only after it succeeds:

```sh
python3 Scripts/test-core.py > .build/install-logs/core-tests.log 2>&1
python3 Scripts/check-docs.py
./edgelesstype.app/Contents/MacOS/edgelesstype self-check
```

These checks use local logic and fixtures; they do not validate real microphone recording, automatic insertion or a paid API account. Do not run `correction-probe` or another live API probe during routine setup.

If any step fails, use the relevant [troubleshooting case](TROUBLESHOOTING.md). Inspect only the failing step's necessary output. Before exposing an excerpt to a cloud assistant or support destination, remove local home/project paths and review for secrets and personal content. Do not paste a whole raw log, environment dump or directory listing. If safe redaction is uncertain, report the failed step and ask the user to inspect the local log instead. No automatic log sanitizer or report uploader is provided by this guide.

## 6. Prepare the private runtime, sign it, then open that app

For a NEW installation only, choose a nonexistent sibling directory outside the checkout. Replace this placeholder with the location already agreed with the user:

```sh
python3 Scripts/prepare-private-runtime.py --target "/path/to/private/runtime"
```

This copies only allowlisted public app files, the speech engine and checksum-verified models. It creates fresh defaults from `Config/app.example.json`, never copies `Config/app.json`, existing preferences, dictionaries, keys, recordings or transcripts from the checkout, and refuses any existing destination. Do not use recursive folder copies to fill this gap. Existing installations use [the update procedure](LOCAL-SIGNING.md#4-後續更新與驗證); legacy data migration is a separate task requiring the user's authorization.

Offer the [personal local signing setup](LOCAL-SIGNING.md) now, before granting runtime permissions. Each user chooses or creates their own identity with explicit consent; never reuse/export the author's certificate or private key. Installation alone does not authorize certificate creation or trust changes. The user handles Keychain passwords and system approval. If they decline, report **build verified; daily signed installation pending**, not full completion. Do not silently open the public build instead.

After the user has selected or created their own identity:

```sh
python3 Scripts/configure-local-signing.py --target "/path/to/private/runtime"
python3 Scripts/update-local-app.py --target "/path/to/private/runtime"
open "/path/to/private/runtime/Local Edgeless Type.app"
```

Verify every exit status; stop on signer ambiguity or mismatch. The final update signs the prepared app with the stable local bundle ID before its first launch. It keeps later updates on that identity; macOS may still request approval after certificate replacement or policy changes.

Keep `Local Edgeless Type.app`, `Config`, `Models` and `Engine` together in the private runtime. Do not move only the app into Applications. Do not open the public staging copy; the user may keep the private app in the Dock. After verified installation, remove only the generated public staging app if no longer needed, never the private runtime or source.

Guide the user through microphone, Accessibility and Input Monitoring permissions in macOS. Respect all tool handoff requirements; never request a system password in chat. If Fn still does not work after the user grants permissions, quit and reopen this app, then recheck. Do not reset unrelated apps' permissions.

Wait for the app to show that the selected local model is ready. If an existing installation has personal dictionary entries, ask the user to confirm readiness rather than capturing that window. If the engine is unavailable or still loading, report that state rather than declaring installation complete.

## 7. Verify dictation first; cloud features are optional

Ask the user to place the cursor in a disposable, empty text editor and perform this short test:

1. Tap Fn briefly; start speaking as soon as you hear the start cue. The microphone is already capturing when the cue plays.
2. Say a non-private test sentence, for example: "這是一句測試，請幫我 check the settings。"
3. Tap Fn again to stop. Confirm the text appears once and the result panel closes.
4. If automatic insertion does not occur, use the documented manual paste path and investigate. Never press Enter or send a message as a test.

The main window's **操作指南** explains the shortcuts. Do not activate the microphone or capture other windows without the user's authorization. Do not retain recordings, context or transcribed test content as fixtures, backups, screenshots, reports or logs. Do not upload any of them to GitHub. Tests for development must use artificial fixtures, not the user's voice or screen content.

Only if the user chooses cloud correction or translation:

- The user opens **API 設定…**, selects a provider, enters their own key in the secure field, and clicks **儲存並使用**. Do not inspect the field, read the clipboard, or screenshot key entry.
- Explain that **測試連線** sends a fixed text sample to that provider and can use paid API credits. Let the user initiate it.
- Context correction is opt-in in the dictionary window. It sends the transcript and dictionary to the selected provider, not the recording.
- For Chinese-to-English translation, the user holds Shift, briefly taps Fn, then releases Shift. To finish, tap **Fn alone**, without Shift. Confirm an English result appears.
- Small and Large-v3 Turbo are local recognition models. Translation uses the selected cloud provider; do not switch providers or models without a user request.

Without an API key, local dictation can still be complete; mark cloud correction and translation as **not configured / not tested**, not as failed or verified.

### Optional recording context

Leave both **錄音上下文** and **允許傳送至 OpenAI** off during installation. Never enable them or read a real input field just to test setup. Explain the separate audio/context consent if the user later chooses cloud recognition. Do not attach captured context separately to correction or translation requests.

### Retry and later updates

- Missing tools: install only the missing dependency, then repeat that failed step.
- Interrupted bootstrap/model download: rerun bootstrap; valid model checksums are reused. Do not delete settings or bypass checksums. The current script restarts incomplete downloads rather than promising resume support.
- Failed build: retain only necessary local build diagnostics; repeat pack-app after the specific issue is resolved. Do not launch a stale app.
- Existing runtime: never rerun preparation over it. Quit the daily app, review and update the clean source checkout, rebuild, then use `update-local-app.py` with the same runtime and signer. Do not automatically reset permissions or re-create certificates.
- Missing or ambiguous signer: return to the user's Keychain selection; no ad-hoc fallback.
- Permission pending: tell the user the exact private app to approve. Do not repeatedly ask them to select the public staging copy.

During long steps report the current stage (engine build, model download/checksum, app build), not invented percentages or silence until completion. Check the existing process/log locally; do not start duplicate installers or add telemetry. Build-log snippets may contain private paths, so summarize outcomes rather than pasting raw output.

## 8. Report completion honestly

After a successful installation, remove only the installer logs created for this run if no unresolved failure requires them. Never preserve voice/context test material. Do not broadly delete `.build/` or other files belonging to an existing installation.

Return a concise summary, not a diagnostic archive. Use fixed outcomes and a source revision, with no secrets, personal paths, recordings or message content:

| Item | Allowed outcomes |
|---|---|
| Supported platform | confirmed / unsupported / not checked |
| Dependencies and model checksums | passed / failed / not checked |
| App build and self-check | passed / failed / not run |
| Private runtime and stable signing | verified / pending / failed |
| Recording context and cloud upload | off / explicitly enabled by user / not checked |
| App launch and local model readiness | confirmed / failed / not checked |
| Required permissions | user confirmed / pending |
| Dictation and insertion | user confirmed / needs troubleshooting / not tested |
| Cloud correction and translation | user confirmed / not configured / not tested |

If the user has not done the voice test, say **built and opened; voice verification pending**. If permission is pending, name the required user action. Never equate passing CI, successful compilation, or a visible app window with full end-to-end success.

This is a source-installation workflow, not a guarantee for every Mac, coding assistant, API account or editor. See the [evidence and compatibility limits](COMPATIBILITY.md). No DMG is provided in this workflow, and no diagnostic data is automatically sent to the author.

The optional OpenAI speech-recognition setting is separate from text-only correction. Installation must leave local Whisper selected unless the user explicitly chooses cloud audio upload. The in-app speech settings disclose the upload and require consent; merely saving an OpenAI key must not enable it.

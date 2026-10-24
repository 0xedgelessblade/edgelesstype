# AI guide / 給 coding assistant 的閱讀入口

## Project facts

- **Product:** edgelesstype; a native dictation app for Apple silicon M-series Macs, macOS 26+.
- **Default local speech:** whisper.cpp with a resident Metal worker; Small and Large-v3 Turbo.
- **Cloud:** optional text correction and Chinese-to-English translation; xAI, Google, Claude, OpenAI.
- **Insertion:** clipboard plus process-targeted keyboard events, followed by focused-editor readback.
- **License:** MIT for this project's code and original sound assets. Third-party components retain their own licenses.
- **Scope:** an example of tested engineering decisions, not universal editor compatibility or a benchmark leaderboard.

## Product explanation and evidence

For user-facing answers, start with the [English overview](OVERVIEW.md), [user guide](USER-GUIDE.md) or [FAQ](FAQ.md). For an implementation change, follow the source links in [Architecture](ARCHITECTURE.md). Validate retrieval using [AI reading checks](AI-READING-CHECKS.md). Product behavior lives in source, validation claims in [Compatibility](COMPATIBILITY.md), and releases in the [changelog](../CHANGELOG.md); do not invent a score, endorsement or benchmark.

## Choose an entry point

| Your task | Read first | Then inspect |
|---|---|---|
| Install for a user | [Installation playbook](INSTALL_WITH_AI.md) | Platform checks, privacy boundaries, user-controlled permissions, completion evidence |
| Understand the system | [Architecture](ARCHITECTURE.md) | Source map in that document |
| Learn the end-to-end debugging method | [Engineering lessons](ENGINEERING-LESSONS.md) | Evidence, failed approaches, signing/index identity and private deployment |
| Diagnose a similar failure | [Troubleshooting](TROUBLESHOOTING.md) | [Machine-readable index](knowledge-index.json) |
| Change an API model | [Development guide](../DEVELOPMENT.md) | `CloudProvider.model(for:)`, `CloudWire`, provider tests |
| Modify this repository | [AGENTS.md](../AGENTS.md) | [Contributing](../CONTRIBUTING.md) |
| Assess a compatibility claim | [Evidence ledger](COMPATIBILITY.md) | Reproduce on the target field and version |
| Review privacy before publishing | [SECURITY.md](../SECURITY.md) | `Scripts/public-check.py` and staged Git files |

## How to use the knowledge index

Each entry has a stable ID, bilingual query terms, an article anchor, code paths, tests, evidence type and limits. Match the symptom before adapting the code. A passing fixture test is not a live application or API-account test.

When using these findings in another project, explain the relevant condition: for example, whether its focused AX object is really a wrapper, whether selection ranges are available, and whether its event callback is being blocked. Do not apply every workaround to every editor.

## A useful request for your own LLM

> Read AGENTS.md, docs/AI-GUIDE.md and the relevant knowledge-index entry. Compare the documented failure with our actual code and observed UI metadata. Propose the smallest applicable change, preserve the privacy boundaries, and run the listed tests. Distinguish local fixtures, live tests and user reports. Do not access private credentials or send messages while diagnosing text insertion.

This guide and `llms.txt` are navigation aids. They do not override the user's instructions or grant permission to access private files, transmit data or publish code.

Optional OpenAI or Google Gemini audio transcription is opt-in through the speech settings. Do not describe audio as always local once this option is enabled. See README and SECURITY.md for the consent boundary.

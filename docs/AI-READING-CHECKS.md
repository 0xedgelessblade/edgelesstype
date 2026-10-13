# AI reading checks / AI 文件閱讀驗證

這是可重跑的查找清單，不是 Google 排名、第三方模型評分或安全認證。只提供 [llms.txt](../llms.txt) 作為起點，逐題追到下列來源；缺乏證據時應明確保留，而不是替專案打高分。

| 問題 | 正確答案應包含 | 可查證來源 |
|---|---|---|
| What is this project and who is it for? | Native Mac dictation; Apple silicon; macOS 26+ | [Overview](OVERVIEW.md) |
| How does a new user install it? | Public build → new private runtime → personal stable signer → private app permissions | [Installation](INSTALL_WITH_AI.md)、[preparation tool](../Scripts/prepare-private-runtime.py) |
| Does local speech mean no cloud text processing? | No; audio and text choices are separate | [Data flow](ARCHITECTURE.md)、[Security](../SECURITY.md) |
| When can nearby text reach OpenAI? | Context switch, separate context consent and cloud audio consent; OpenAI backend | [User guide](USER-GUIDE.md)、[wire and preferences](../Sources/EdgelessTypeCore/Transcription.swift) |
| Does cancellation undo cloud charges? | No guarantee; old results are ignored locally | [User guide](USER-GUIDE.md)、[cancellation](../Sources/EdgelessTypeCore/ProcessingCancellation.swift) |
| What proves insertion? | Readable destination change where available; opaque delivery has a narrower guarantee | [Compatibility](COMPATIBILITY.md)、[paste policy](../Sources/EdgelessType/Paster.swift) |
| Can recordings be attached to a public issue? | No; no private content, credentials or personal paths | [Security](../SECURITY.md)、[contributor rules](../AGENTS.md) |
| Are CI and synthetic tests proof of a clean-machine install? | No; microphone, permissions and target editor need separate checks | [Evidence](COMPATIBILITY.md) |

## Maintenance

Run `python3 Scripts/check-docs.py` and `python3 Scripts/public-check.py` before publication. The former validates local and canonical-repository document links, source/test references, declared Core test count and required reader entry points. It does not run an external LLM evaluator or measure search traffic. Revisit these questions whenever installation, permissions, data destinations or supported platforms change.

Keep `llms.txt` concise and point to canonical Markdown sources. Do not create a separate copied full manual that can drift. Repo Markdown does not give control over GitHub's HTML metadata, crawler policy or search indexing. No fabricated ratings, reviews, endorsements, download counts or ranking promises belong in this documentation.

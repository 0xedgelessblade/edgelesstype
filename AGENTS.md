# edgelesstype contributor instructions

- For an installation request, follow `docs/INSTALL_WITH_AI.md` and its privacy-first completion checklist. Do not treat installation as authorization to read secrets, enable cloud features, upload diagnostics, or publish code.
- Support only Apple silicon M-series Macs on macOS 26 or later. Do not add Intel, Windows, Linux or CPU-only branches.
- Keep the user interface small: provider selection, encrypted API key save/test/delete, and the dictionary. Model customization belongs in code, not a large model picker.
- Start model changes in `Sources/OpenTypelessCore/CloudProvider.swift`. Follow `DEVELOPMENT.md`; check current official provider docs before changing payload parameters.
- Normal correction uses `ContextCorrection.correctFullText`: accept the complete, non-empty model reply after transport checks, then convert Chinese locally to Traditional. Do not reintroduce edit-count, homophone, dictionary-match or source-text validation; legacy helpers exist only for historical fixtures. Never treat a clipboard read or successful AX setter as evidence of successful insertion.
- Preserve the encrypted store format and independent provider records. Do not print, commit, screenshot, or ask for API keys in chat. Use the app's secure field and fixed test phrase.
- Do not read the developer's other folders, personal settings, private store, or local key table to implement a feature.
- Use `python3 Scripts/test-core.py` for deterministic tests, including on Command Line Tools without XCTest. Run `python3 Scripts/public-check.py` before export.
- No personal paths, personal contact details, recordings, runtime configuration, private dictionaries, credential ciphertext, private keys, or unreviewed binaries in commits. Use a public Git alias and GitHub noreply email, configured by the contributor.
- Public copyright/name: edgelessblade. Do not infer or disclose the author's personal identity or location.
- Public source ZIPs must use the allowlist in `Scripts/public-check.py`; do not zip the working directory wholesale.
- Bundled binaries need their own privacy and license audit. Keep compiler path remapping in `Scripts/pack-app.sh` and `Scripts/bootstrap.sh`.

- Before diagnosing a known failure, read `docs/AI-GUIDE.md` and the matching `docs/knowledge-index.json` entry. Preserve the distinction between fixtures, native tests and user reports.
- Run `python3 Scripts/check-docs.py` after documentation edits. Do not claim hosted CI, general accuracy or universal editor compatibility from local evidence.

- OpenAI audio transcription is an explicit opt-in first-stage option. Keep local Whisper as the default, require saved audio consent, do not change the text-correction provider when managing the transcription key, and never upload private audio for development tests.

- Keep the public Git checkout as the canonical source. Update a separate private runtime only with reviewed code/assets using `Scripts/update-local-app.py`; never sync private runtime folders back to Git. Do not rebuild legacy source merely because it sits beside the running app. Local display names come from bundle metadata. Test local updates with synthetic files using `Scripts/test-local-update.py`.

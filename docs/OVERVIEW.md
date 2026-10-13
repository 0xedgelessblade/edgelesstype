# edgelesstype: open-source voice dictation for Apple silicon Macs

edgelesstype is a native Swift/AppKit dictation app for Apple silicon M-series Macs running macOS 26 or later. It turns speech into text and attempts to insert the result into the active editor. Local Whisper is the default; OpenAI audio transcription is optional and requires the user's consent.

[Documentation home](README.md) · [User guide](USER-GUIDE.md) · [AI-assisted installation](INSTALL_WITH_AI.md) · [Privacy](../SECURITY.md)

## What it does

- Press Fn to start and stop dictation; press Shift + Fn to start Chinese-to-English translation, then Fn alone to finish.
- Run local Whisper Small or Large-v3 Turbo with a resident Metal worker.
- Choose OpenAI speech recognition separately from text correction and translation.
- Convert Chinese output to Traditional Chinese; maintain a personal dictionary.
- Optionally use a small amount of text near the cursor as transcription context. Context capture and sending context to OpenAI have separate switches, both off by default.
- Cancel upload, recognition, correction or translation from the processing panel.
- Attempt insertion once, use readable editor changes as evidence where available, and provide manual paste recovery. The app does not press Enter or send messages.

## Requirements and installation

Apple silicon and macOS 26+ are required. This project currently provides a source installation workflow, not a DMG or a Homebrew Tap. A coding assistant with authorized local terminal access can follow the [installation guide](INSTALL_WITH_AI.md). A text-only chatbot cannot install the app by itself.

Current bootstrap downloads both local recognition models, about 2.1 GB total, plus the speech detector and build dependencies. Preparing a separate private runtime needs additional space for a model copy. Each user chooses or creates their own local code-signing identity and personally grants system permissions. This is not an Apple-notarized distribution.

## Data choices

| Feature | Destination | Default |
|---|---|---|
| Whisper speech recognition | This Mac | Selected |
| OpenAI speech recognition | OpenAI receives that recording | Off |
| Nearby-text context | Memory for one recording; local worker, or OpenAI with separate consent | Off |
| Text correction | Selected provider receives transcript and relevant vocabulary | Off |
| Chinese-to-English translation | Selected cloud provider | User-triggered; requires configuration |

Local speech recognition alone does not make a workflow fully offline if cloud correction or translation is used. Recordings, context, transcripts, credentials and personal dictionaries must never enter GitHub or diagnostic uploads. The project has no diagnostic-upload endpoint. See the [full privacy boundary and retention limits](../SECURITY.md).

## Evidence and limits

[Compatibility](COMPATIBILITY.md) distinguishes synthetic tests, native checks and user reports. Some editors do not expose readable text or support automated insertion. Context capture can be skipped when unsupported or timed out. Do not infer universal app support, a guaranteed accuracy gain or a speed ranking from this repository.

Public maintainer: [edgelessblade](https://github.com/0xedgelessblade). Project code uses the [MIT license](../LICENSE); third-party components retain their own licenses. Use [CITATION.cff](../CITATION.cff) and a source revision when citing the project. This is an independent project, not an official client endorsed by its API providers.

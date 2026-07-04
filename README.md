# Listening Clip Pipe

**English** | [中文](README.zh-CN.md)

> Capture the exact seconds you couldn't hear — one hotkey, straight into your study notes.

Listening Clip Pipe is a macOS menu bar tool built for **IELTS listening practice** (and any serious audio-based language learning). When you hit a stretch of connected speech, weak forms, or swallowed sounds you can't parse, press **⌥Z** to start recording the system audio, press **⌥Z** again to stop — the clip is saved locally and copied to your clipboard, ready to paste (Cmd+V) into Feishu, Notion, or any document, right where you're taking notes.

**This is v1.0** — the complete "capture → save → paste" pipeline, deliberately minimal.

## Why it's different

Traditional workflow when you mishear 3 seconds of an IELTS recording: find the audio file, scrub to the right spot, trim a clip, export it, upload it to your notes, then write down why you misheard it. Five minutes of friction for three seconds of audio — so nobody actually does it, and the mishearings never get reviewed.

Listening Clip Pipe collapses all of that into two keypresses:

- **🎧 Records what you hear, not what your mic hears.** It taps macOS system audio output directly (Core Audio Process Tap) — clean audio with zero room noise, works with headphones.
- **⚡ One hotkey, zero context switch.** ⌥Z to start, ⌥Z to stop. You never leave your player or your notes.
- **🔴 Impossible to miss that you're recording.** While recording, a floating always-on-top ● REC timer sits at the top-right of your screen — visible over full-screen apps, click-through so it never gets in your way.
- **📋 Paste-ready instantly.** The clip lands on your clipboard as a file; Cmd+V drops it into your document at the exact spot where you're writing your error analysis.
- **🤖 AI/script-friendly by design.** Every clip gets a unique ID, a structured text anchor, a per-clip metadata JSON, and a global index — so later you (or an LLM agent) can batch-process your mishearing collection: transcribe, tag connected-speech patterns, build review schedules.
- **🔒 100% local, minimal permissions.** No cloud, no account, no telemetry. Needs only the "System Audio Recording Only" permission — no microphone, no screen recording, no accessibility access.

## Requirements

- macOS 14.4+ (Apple Silicon or Intel)
- Xcode Command Line Tools (to build from source)

## Install

```bash
git clone https://github.com/wanglikai121666-stack/listening-clip-pipe.git
cd listening-clip-pipe
./build_app.sh
cp -R build/ListeningClipPipe.app /Applications/
open /Applications/ListeningClipPipe.app
```

A waveform icon appears in your menu bar. The first time you press ⌥Z, macOS asks for permission: **System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only** — allow it, then press ⌥Z again.

## Usage

1. Play your IELTS audio / podcast / lecture.
2. Hear something you can't parse → press **⌥Z** (menu bar icon turns red and a floating ● REC timer appears at the top-right of the screen).
3. Let the passage finish → press **⌥Z** again.
4. Notification: *Clip copied*. Switch to your notes and **Cmd+V**.
5. Write down what you misheard and why, right next to the audio.

The menu bar menu also offers **Copy Last Clip + Anchor**, **Copy Last Clip**, **Copy Last Anchor** (in case a paste didn't take), and **Open Clips Folder**.

## Data layout

Everything lives under `~/Documents/ListeningClipPipe/`:

```
~/Documents/ListeningClipPipe/
├── clips/
│   ├── LC_20260626_213522.wav    # the audio clip (16-bit PCM WAV)
│   └── LC_20260626_213522.json   # per-clip metadata
└── clips_index.json              # global index for batch processing
```

Each clip's text anchor (for locating the clip semantically inside your documents):

```
🎧 AUDIO_CLIP_ID: LC_20260626_213522
duration: 8.4s
local_file: LC_20260626_213522.wav
source: system_audio
note:
```

## Paste compatibility note

The clipboard is written in *composite* mode: one pasteboard item carrying both the file URL and the text anchor. Most editors take the file. If your target app pastes only one of the two, use the separate **Copy Last Clip** / **Copy Last Anchor** menu items as a fallback.

## v1.0 scope & roadmap

v1.0 does capture, storage, and clipboard — nothing else, on purpose. Not included (yet): automatic transcription, Feishu API sync (interface stubbed in `FeishuSyncService.swift`), source-text matching, replay/review UI, spaced-repetition scheduling, Anki export. The structured local data means all of these can be built on top without touching the capture pipeline.

## Troubleshooting

- **`swift build` fails / `import Foundation` errors about `SwiftBridging` redefinition**: some mixed-version Command Line Tools installs ship a stale `module.modulemap`. `build_app.sh` compiles with `swiftc` directly and auto-applies a VFS-overlay workaround; the permanent fix is `sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap{,.bak}`.
- **Permission prompt reappears after rebuilding**: the build is ad-hoc signed, so each rebuild has a new signature. Keep a copy in `/Applications` for daily use.
- **⌥Z does nothing**: check the menu bar icon exists (app running), and that no other app claims the ⌥Z global hotkey.

## License

[MIT](LICENSE)

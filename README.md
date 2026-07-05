# Listening Clip Pipe

**English** | [中文](README.zh-CN.md)

> Capture the exact seconds you couldn't hear — one hotkey, straight into your study notes.

Listening Clip Pipe is a macOS menu bar tool built for **IELTS listening practice** (and any serious audio-based language learning). Press **⌥Z** to start recording the whole listening session (system audio, no mic) — a floating timeline appears at the top-right of your screen. Whenever you hit a stretch of connected speech you can't parse, tap **Space** to open a **green mark** on the timeline, tap **Space** again to close it. Mark as many trouble spots as you want. Press **⌥Z** to stop: every green mark is cut into its own audio file, and the full recording **plus all marked segments** land on your clipboard — one Cmd+V pastes them all into Feishu, Notion, or any document. No marks? Then you get exactly one complete clip, same as a simple recorder.

Started as **v1.0** with the complete "capture → save → paste" pipeline — deliberately minimal.

## Why it's different

Traditional workflow when you mishear 3 seconds of an IELTS recording: find the audio file, scrub to the right spot, trim a clip, export it, upload it to your notes, then write down why you misheard it. Five minutes of friction for three seconds of audio — so nobody actually does it, and the mishearings never get reviewed.

Listening Clip Pipe collapses all of that into two keypresses:

- **🎧 Records what you hear, not what your mic hears.** It taps macOS system audio output directly (Core Audio Process Tap) — clean audio with zero room noise, works with headphones.
- **⚡ Space bar as the mark button, zero context switch.** While a session is recording, a single tap of Space opens/closes a green mark — the fastest possible reaction to a mishearing, and you never leave your player. Space is exclusively claimed only while recording (via a permission-free Carbon hotkey), and is restored the instant you stop.
- **⏪ Pre-roll for the "wait, what?" moment.** You never realize you're lost until you're already half-way through the phrase. The **Mark Pre-roll** menu option (0.1–1s) backdates each mark's start, so the cut segment includes the part you heard before you reacted.
- **🔴 A live timeline you can't miss.** While recording, a floating always-on-top timeline sits at the top-right of your screen — pulsing REC timer, mark count, and every green segment drawn in place across the whole session. Visible over full-screen apps, click-through. Optional: toggle via **Show On-Screen Timeline** in the menu.
- **📋 Paste-ready instantly.** The clip lands on your clipboard as a file; Cmd+V drops it into your document at the exact spot where you're writing your error analysis.
- **📝 One-click ASR analysis report.** The Library window (double-click the app icon, or menu → Library) lists every past session with play / delete / transcribe buttons. Transcribe calls SiliconFlow ASR (SenseVoiceSmall) on the full recording *and* each marked segment, then writes a Markdown report to `reports/`: the full transcript with the parts you didn't catch **bolded in place** (fuzzy-matched) with the segment audio linked right next to them — ready to pipe into Feishu later. Global pre-roll and your API key (stored locally only, never in this repo) are configurable in the same window.
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

1. Press **⌥Z** and start your IELTS audio / podcast / lecture — the whole session records, and the floating timeline appears (Space is now the mark button and won't reach other apps).
2. Hear something you can't parse → tap **Space**: a green segment opens on the timeline (backdated by the pre-roll setting).
3. The trouble spot passes → tap **Space** again to close the green segment. Repeat 2–3 for every spot you miss; the timeline shows all of them.
4. Session over → press **⌥Z**. Each green mark is cut into its own WAV; the clipboard gets the **full recording + all marked segments** (an unclosed final mark is ended at the stop point). No marks → clipboard gets the single full clip, like before.
5. Switch to your notes and **Cmd+V** — everything pastes at once. Write down what you misheard next to each segment.

The menu bar menu also offers **Start/Stop Recording** and **Mark (Space)** (mouse alternatives), **Copy Last Clip + Anchor**, **Copy Last Clip**, **Copy Last Anchor** (in case a paste didn't take), **Mark Pre-roll** (0.1–1s backdating), **Show On-Screen Timeline**, and **Open Clips Folder**.

## Data layout

Everything lives under `~/Documents/ListeningClipPipe/`:

```
~/Documents/ListeningClipPipe/
├── reports/
│   └── LC_20260626_213522_听力分析.md   # ASR analysis report (full transcript + marked parts)
├── clips/
│   ├── LC_20260626_213522_总录音.wav     # full session recording (plain LC_xxx.wav when unmarked)
│   ├── LC_20260626_213522_第1段切分.wav  # marked segment #1
│   ├── LC_20260626_213522_第2段切分.wav  # marked segment #2
│   └── LC_20260626_213522.json          # per-session metadata (incl. mark time ranges)
└── clips_index.json                # global index for batch processing (e.g. future ASR)
```

Each session's text anchor (for locating the audio semantically inside your documents):

```
🎧 AUDIO_CLIP_ID: LC_20260626_213522
duration: 754.2s
local_file: LC_20260626_213522_总录音.wav
source: system_audio
marks: 2
  - LC_20260626_213522_第1段切分.wav (12.3s–20.1s)
  - LC_20260626_213522_第2段切分.wav (95.0s–101.4s)
note:
```

## Paste compatibility note

- **Session with marks** → the clipboard holds multiple files (Finder-style multi-file copy): the full recording plus every sliced segment. One Cmd+V pastes them all.
- **Session without marks** → *composite* mode: one pasteboard item carrying both the file URL and the text anchor; most editors take the file.

If your target app doesn't paste what you expect, use the **Copy Last Clip** / **Copy Last Anchor** / **Copy Last Clip + Anchor** menu items as fallbacks.

## Scope & roadmap

The current version (v1.4.x) does capture, marking, slicing, local storage, clipboard, and on-demand ASR analysis reports (SiliconFlow SenseVoiceSmall — bring your own API key, set it in the Library window). Not included (yet): Feishu API sync (interface stubbed in `FeishuSyncService.swift`; reports are designed to be uploaded by an external CLI), replay/review UI, spaced-repetition scheduling, Anki export. The structured local data (mark time ranges in per-session metadata + global index) means all of these can be built on top without touching the capture pipeline.

## Troubleshooting

- **`swift build` fails / `import Foundation` errors about `SwiftBridging` redefinition**: some mixed-version Command Line Tools installs ship a stale `module.modulemap`. `build_app.sh` compiles with `swiftc` directly and auto-applies a VFS-overlay workaround; the permanent fix is `sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap{,.bak}`.
- **Permission prompt reappears after rebuilding**: the build is ad-hoc signed, so each rebuild has a new signature. Keep a copy in `/Applications` for daily use.
- **⌥Z does nothing**: check the menu bar icon exists (app running), and that no other app claims the ⌥Z global hotkey.
- **Space bar stopped typing spaces**: a recording session is running (menu bar icon is red) — press ⌥Z to stop and Space is restored instantly.

## License

[MIT](LICENSE)

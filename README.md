# zWhisper

**On-device AI dictation for macOS.** Hold a key, speak, and zWhisper types for you in any app — transcribed locally with Whisper, rewritten per-mode with Apple Intelligence, and pasted at your caret. No audio ever leaves your Mac.

zWhisper is a menu-bar agent (no Dock icon): it records your mic, transcribes on-device with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (CoreML / Apple Neural Engine), optionally rewrites the transcript through a per-mode LLM pass (Foundation Models on macOS 26+, or your own OpenAI-compatible key), and auto-pastes the result wherever you're typing.

## Features

- **Dictate anywhere** — ⌥⇧Space to toggle, hold right ⌘ for push-to-talk, or click the menu-bar icon
- **Live everything** — real-time waveform, streaming partial transcript as you speak, streaming rewrite
- **Modes** — Email, Message, Note, Meeting, Voice Note, Write for me, Super Mode (⌘1–⌘7) + your own custom modes with per-app auto-activation
- **On-device first** — Whisper runs locally (626MB model, downloaded once); mode rewrites use Apple Intelligence when available, BYOK cloud as an optional extra
- **Context-aware** — Super Mode reads your selection and clipboard to ground its answers
- **History** — every dictation with audio, word-level click-to-seek playback, reprocess with any mode
- **Vocabulary** — custom words and text replacements that actually reach the recognizer
- **Polite hotkeys** — Esc and ⌘-digits are only claimed while the popover is open; your other apps keep them
- **Private by design** — no accounts, no telemetry; cloud keys live in the Keychain

## Requirements

- macOS 26+ on Apple Silicon
- Microphone permission (required) and Accessibility permission (for auto-paste and push-to-talk)
- Apple Intelligence recommended for mode rewrites (Voice Note works regardless; BYOK cloud key is the fallback)

## Build & run

```sh
git clone https://github.com/umzcio/zWhisper.git
cd zWhisper/zwhisper-mac
brew install xcodegen          # once
xcodegen generate              # generates zWhisper.xcodeproj from project.yml
xcodebuild build -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS'
open ~/Library/Developer/Xcode/DerivedData/zWhisper-*/Build/Products/Debug/zWhisper.app
```

Run the tests:

```sh
xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS'
```

The Xcode project is **generated** — never edit `zWhisper.xcodeproj` directly; edit `project.yml` and re-run `xcodegen generate`.

## Repository layout

| Path | What it is |
|---|---|
| `zwhisper-mac/` | The native macOS app (Swift 6, SwiftUI + AppKit) — the product |
| `app/` | React/TypeScript web prototype — the visual/interaction source of truth |
| `zwhisper-design-spec.md` | Design handoff spec: tokens, components, motion, every screen |
| `zwhisper-swift-architecture.md` | Implementation source of truth: modules, state machine, milestones |
| `zwhisper-icon/` | App icon source art |

The prototype (`app/`) is a Vite app — `npm install && npm run dev` to explore the UX it encodes.

## Default hotkeys

| Key | Action |
|---|---|
| ⌥⇧Space | Toggle dictation |
| Hold right ⌘ | Push-to-talk (release to paste) |
| Esc | Cancel (only while the popover is open) |
| ⌥⇧K | Cycle modes |
| ⌘1–⌘7 | Pick a mode (only while the popover is open) |

Most are rebindable in Settings → Shortcuts.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

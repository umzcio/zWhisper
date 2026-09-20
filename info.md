# Research: SuperWhisper feature set & UI (for zWhisper prototype)

## Product essence
SuperWhisper is a macOS/iOS AI voice-to-text dictation app. Hotkey-triggered (default Option+Space), sits in the menu bar, dictates into any app. Pipeline: Dictation → Transcription (Whisper models, local or cloud) → Smart Processing (optional LLM reformatting per Mode) → auto-paste into focused app.

## Recording window (core UI)
- Floating popover window with: resize toggle (main/mini), real-time waveform, active mode display (click to switch), Stop button (ends + processes), Cancel (esc).
- Mini recording window: compact version, shows waveform, hover reveals stop button.
- Realtime transcription shows words as you speak (teleprompter UI).
- Context awareness indicator lights up when clipboard/selected-text context is captured.
- Animated recording window with fade effects; blue check indicator on mode selection.

## Modes system (defining feature)
- Built-in modes: pure voice transcription, Email, Voice Note, Message, Note, Meeting, "Write for me".
- Custom modes with own AI instructions/prompts; modes persist across sessions.
- Mode switching: global shortcut (⌥⇧K hold + tap to cycle), CMD+Number, menu bar, deep links.
- Auto-activation rules per app/website (e.g. Email mode when Mail is frontmost).
- Super Mode: reads active app/selected text/clipboard context to adapt output.

## Models
- Local Whisper models tiered: Nano, Fast, Pro, Ultra (v3) — speed/accuracy tradeoff; free tier = unlimited local.
- Cloud: OpenAI Whisper Large, plus models from Anthropic, Deepgram, Groq. Models library with type/provider/speed/accuracy filters, starring favorites, download/delete models, BYOK (custom API keys).

## History
- All recordings + results stored locally as JSON; history window with playback from any point, word-level timestamps, reprocess a past dictation with a different mode, progress display during processing.

## Settings (organized tabs)
- General/Configuration: launch at login, show in Dock, start recording on menubar click, always close window, theme (light/dark/system), sound effects style.
- Voice model: model picker, active duration.
- Sound: input device, dynamic normalization, silence removal.
- Shortcuts: toggle recording, push-to-talk, cancel, change mode (customizable).
- Vocabulary: custom words unique to user; text replacements; clickable vocabulary hints.
- Usage stats: dictation speed, words dictated, time saved, typing speed test; stat share card.

## Key UX details worth replicating
- Push-to-talk (hold key) AND toggle recording.
- Two-step flow: pick mode → dictate; mode persists.
- Clipboard restore after paste; auto-paste toggle.
- 100+ languages; translate to English on the fly.

## Prototype constraints (user decisions)
- Web prototype only (end product will be native Swift) — look/feel must translate to macOS-native.
- Mock/simulated transcription — no real audio or APIs.
- Full feature set: hold-to-talk/toggle recording, modes, history, settings, custom vocabulary.

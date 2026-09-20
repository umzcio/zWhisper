# zWhisper — Swift/macOS Architecture Plan

**Audience:** the AI coding agent (Kimi Code) implementing the app. **Companion document:** `zwhisper-design-spec.md` (referenced as §n throughout) — that spec is the visual/interaction source of truth; this document is the implementation source of truth. Where they conflict on platform mechanics, this document wins; where they conflict on pixels, motion, or copy, the spec wins.

---

## 1. Overview

zWhisper is a native macOS menu-bar AI dictation app (SuperWhisper-class): the user dictates from anywhere in the OS; zWhisper records the mic, transcribes on-device with WhisperKit (CoreML, Apple Neural Engine), rewrites the transcript through a per-mode LLM pass (Foundation Models framework as the primary engine, OpenAI-compatible BYOK providers as optional extras), and auto-pastes the result at the caret in whatever app is frontmost. The design spec (`zwhisper-design-spec.md`) describes the validated UI from the web prototype — recording popover hero (§3.1), modes/history/models/vocabulary/settings screens (§6), the dictation state machine and its timing budgets (§4, §7) — and this architecture realizes exactly that UI, no redesigns. The product is opinionated: on-device-first, dark-first (§1), Apple Silicon-only for v1.

---

## 2. App shape & project setup

**Shape.** Single app target, menu-bar agent: `LSUIElement = true` in `Info.plist` (no Dock icon, no main menu beyond a minimal one for keyboard-focus correctness). All UI is SwiftUI; three surfaces are hosted in AppKit shells:

- `NSStatusItem` (menu extra) — the record toggle and mode pill entry point (spec §3.3).
- Borderless `NSPanel` (`.nonactivatingPanel`, `.isFloatingPanel`, level `.floating`) hosting an `NSHostingView` for the recording popover — the hero surface (§3.1, §8).
- Standard `.titled` `NSWindow`s (via SwiftUI `WindowGroup` scenes with `titlebarAppearsTransparent`) for the five management screens (§6). Sizes per §6 table: Modes 960×640, History 1000×660, Models 1000×660, Vocabulary 960×640, Settings 920×640.

The faux desktop, faux menu bar, dock, and Notes demo window in the prototype are deleted — they are prototype scaffolding (§3.3, §3.9, §6.1), replaced by the real OS and real target apps.

**Deployment target: macOS 26.** Foundation Models is the primary mode-processing engine and requires macOS 26 — that makes 26 our floor, no debate. No `#available` gates are needed anywhere; the only runtime check is `SystemLanguageModel.default.availability` for the Apple-Intelligence-off configuration (§8, §10.4). BYOK cloud providers are **optional extras** (user-added keys, used by preference or when Apple Intelligence is unavailable) — they are not an OS-version fallback, and there is no macOS 14–25 compatibility path. Swift 6 language mode with strict concurrency, Xcode 26+.

**Bundle structure.** One target; source organized by module folders matching §3 of this doc (`AppState/`, `Audio/`, `Transcription/`, `Modes/`, `Hotkeys/`, `Paste/`, `Context/`, `Models/`, `Persistence/`, `Onboarding/`, `UI/Popover/`, `UI/Screens/`). No app extensions for v1. Resources: none beyond the app icon and any bundled sound blips (§6.6 Sound effects styles are synthesized — keep that, `AVAudioPlayer` with generated PCM is fine and avoids asset licensing).

**SPM dependencies.**

| Package | URL | Pin | Why |
|---|---|---|---|
| WhisperKit | `https://github.com/argmaxinc/argmax-oss-swift` | `from: "1.0.0"` (product `WhisperKit`) | On-device transcription; MIT; repo was renamed — do not use the old whisperkit URL. |
| KeyboardShortcuts | `https://github.com/sindresorhus/KeyboardShortcuts` | latest major (`from:` current release) | User-recordable global hotkeys + recorder UI for the Settings → Shortcuts pane (§6.6). Requires `-weak_framework Combine` in **Other Linker Flags**. |
| LaunchAtLogin-Modern | `https://github.com/sindresorhus/LaunchAtLogin-Modern` | latest major | "Launch at login" toggle (§6.6 General → Startup). |
| Settings | `https://github.com/sindresorhus/Settings` | latest major | Settings window scaffolding (tabbed panes, §6.6). Optional — a plain SwiftUI tab strip is acceptable if integration friction appears; decide at M6. |
| Sparkle | `https://github.com/sparkle-project/Sparkle` | `from: "2.x"` — **optional, direct distribution only** | Auto-updates outside the App Store. Exclude entirely from a MAS build. |

No other dependencies. In particular: no SwiftData (see §7), no Alamofire-style wrappers (BYOK is plain `URLSession`), no HotKey/Carbon shims (KeyboardShortcuts covers toggles; PTT hold is `NSEvent` monitors, §3 HotkeyManager).

**Distribution & signing.** v1 ships **direct distribution (Developer ID + notarization)**, sandbox **off**. Rationale: the app needs global `NSEvent` key monitors (PTT hold), Accessibility API reads of other apps' focused UI elements (context capture + paste target), and `CGEvent` posting (⌘V). Global monitors and AX reads work under the sandbox with user-granted Accessibility permission, but `CGEvent` keyboard posting into arbitrary apps and audio-tap edge cases are materially smoother unsandboxed, and Sparkle requires direct distribution anyway. Entitlements for the direct build: `com.apple.security.audio-input` (hardened runtime), and user-granted TCC permissions (microphone, Accessibility) — no sandbox entitlements. The MAS path is explicitly deferred; it would require sandbox on, an Accessibility-permission UX that MAS tolerates (user grants in System Settings), and Apple Events entitlement (`com.apple.security.automation.apple-events`) if we later add AppleScript-based context capture. Accessibility permission itself works identically either way.

---

## 3. Module breakdown

Single `AppState` object owns cross-module state; everything else is a service it coordinates. All modules are protocol-fronted so the mock engine's timing budgets (§7) can be replayed in unit tests.

| Module | Responsibility | Spec sections |
|---|---|---|
| `AppState` | Single source of truth: engine phase, active mode, popover visibility/size, settings, permissions | §4, §6 |
| `AudioCaptureEngine` | Mic capture, 16kHz mono conversion, ring buffer, RMS levels for waveform | §3.2, §5, §7 |
| `TranscriptionEngine` | WhisperKit wrapper: model load, streaming partials, final transcript, vocabulary prompting | §4.2, §6.5 |
| `ModeProcessor` | Mode definitions, LLM rewrite per mode — Foundation Models primary, BYOK providers optional | §6.2, §7 |
| `HotkeyManager` | Global hotkeys (toggle/cancel/cycle/mode-digit) + PTT hold via NSEvent monitors | §4.1, §6.6 Shortcuts |
| `PasteController` | AX focused-element discovery, clipboard snapshot/set/restore, CGEvent ⌘V, undo range | §4.3, §8 |
| `ContextCapture` | Frontmost app identity, selected text, clipboard read for context-enabled modes | §3.1 context dot, §6.2, §7 `CONTEXT_MS` |
| `ModelDownloadManager` | WhisperKit model download/delete/star/active, queue of 2 | §6.4 |
| `Persistence` | JSON stores: history, modes, vocabulary, settings, usage stats | §6.3–§6.6 |
| `OnboardingController` | First-run permissions flow and capability detection | §8 |

### 3.1 `AppState`

```swift
@MainActor @Observable final class AppState {
    var phase: DictationPhase        // §4 state machine, single writer
    var activeMode: Mode             // §6.2 library; ⌘1–7 shortcuts
    var popover: PopoverState        // hidden/visible, main/mini, position
    var settings: SettingsStore      // §6.6, persisted
    var permissions: PermissionState // mic / AX / apple-intelligence
    let audio: AudioCaptureEngine
    let transcription: TranscriptionEngine
    let modes: ModeProcessor
    let hotkeys: HotkeyManager
    let paste: PasteController
    // ...
}
```

`@Observable` (not `ObservableObject`) — Swift 6 strict concurrency + Observation framework is the modern path and avoids `@Published` boilerplate; WhisperKit v1.0.0 already requires Swift 6 mode so there is no legacy reason to stay on Combine. All UI observes `AppState` only; services publish narrow callbacks (closures/`AsyncStream`) into it. `AppState` is the only type allowed to mutate `phase` (§4 invariants live in one place).

### 3.2 `AudioCaptureEngine`

```swift
protocol AudioCaptureEngineProtocol {
    var levels: AsyncStream<Float> { get }        // RMS per ~16ms tick → waveform
    var buffers: AsyncStream<AVAudioPCMBuffer> { get } // 16kHz mono Float32 → transcription
    func start() async throws
    func stop() async -> AVAudioPCMBuffer             // full-session buffer for final pass
}
```

Implements spec §3.2 (waveform data source) and §7 energy ticker (50ms cadence — we emit RMS at the tap's native ~21ms with bufferSize 1024 @ 48kHz and let the waveform's lerp 0.2 smooth it). Owns silence-removal/normalization toggles from Settings → Sound (§6.6). See §5 below for the full pipeline.

### 3.3 `TranscriptionEngine`

```swift
protocol TranscriptionEngineProtocol {
    var partials: AsyncStream<String> { get }   // teleprompter text (§3.1, §4.2)
    func transcribeFinal(_ audio: AVAudioPCMBuffer) async throws -> Transcript
}
struct Transcript { let text: String; let segments: [Segment] }  // segment-level timings
```

Wraps `WhisperKit` with a pinned config: `WhisperKitConfig(model: "large-v3-v20240930_626MB")` default on Apple Silicon (falls back tier by tier per the 900ms budget, §4). Streaming follows the in-repo `Examples/WhisperAX` pattern verbatim — AVAudioEngine tap → rolling audio buffer → periodic `transcribe` on the window → partial strings — because the OSS package deliberately has no high-level streaming class; do not invent one. Vocabulary words (§6.5) are injected via WhisperKit's prompt/prefix support (`promptTokens`) on each pass — this closes the "prototype gap" flagged in §6.5: vocabulary must feed the real teleprompter.

### 3.4 `ModeProcessor`

```swift
struct Mode: Codable, Identifiable {
    let id: UUID
    var name: String
    var icon: SFSymbolName        // §8 icon map
    var colorHex: String          // §2.1 tokens; built-ins per §7 script bank colors
    var instructions: String      // "AI Instructions" → system prompt
    var readsSelectedText: Bool   // context toggles ("Super" badge, §6.2)
    var readsClipboard: Bool
    var autoActivationRules: [ActivationRule]  // frontmost-app/domain rules, §6.2
    var shortcutIndex: Int?       // ⌘1…⌘9
    var isBuiltIn: Bool
}
protocol ModeProcessorProtocol {
    func process(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error>
}
```

One `LanguageModelSession` per invocation (not per mode) with `instructions: mode.instructions` — per-session instructions are the framework's intended mechanism, and a fresh session per dictation prevents cross-dictation context bleed. Voice Note is an identity transform: short-circuit before any LLM call (§7). Details in §6 below.

### 3.5 `HotkeyManager`

Two mechanisms, split by capability:

- **KeyboardShortcuts** (Sindre Sorhus) for toggle-style bindings: Toggle recording (`⌥⇧Space` default), Cancel (`Esc` — but see below), Change mode/cycle (`⌥⇧K`), and `⌘1…⌘9` mode-select. These are user-recordable in Settings → Shortcuts (§6.6) via `KeyboardShortcuts.Recorder`, which gives us the "Press shortcut…" armed state and conflict handling nearly for free.
- **`NSEvent` global monitors** (`addGlobalMonitorForEvents(matching: [.keyDown, .keyUp])` plus a *local* monitor for when our own popover is key) for **push-to-talk hold** (default: hold `Space`). KeyboardShortcuts never reports key-up, so hold semantics must be hand-rolled: `keyDown` (not `isARepeat`, no modifier flags) starts; matching `keyUp` stops (§4.1). Guard: do not arm PTT when the frontmost app's focused element is editable — check via AX (`AXFocusedUIElement` role is text-ish) or, cheaply, skip when `AXIsProcessTrusted` is false and document the degraded behavior (PTT disabled until Accessibility granted). Cancel during `recording` is the KeyboardShortcuts Esc binding; cancel during `transcribing`/`processing` is the same binding re-checked in `AppState` (spec §4.2: Esc works in all three phases even though the ✕ button is disabled).

### 3.6 `PasteController`

```swift
protocol PasteControllerProtocol {
    func paste(text: String, restoreClipboard: Bool) async throws -> PasteReceipt
    func undo(_ receipt: PasteReceipt) async   // restores clipboard snapshot (§4.3 "Undo paste")
}
struct PasteReceipt { let changeCount: Int; let snapshot: [NSPasteboard.PasteboardType: Data]; let targetApp: String }
```

Sequence (§8): snapshot `NSPasteboard.general` (`changeCount` + full item archive) → write transcript → verify frontmost element via AX for the toast label ("Pasted to {app}") → post `CGEvent` ⌘V (keyboard source, keyDown+keyUp with `.maskCommand`) → wait one `changeCount` poll cycle → restore snapshot if `restoreClipboard` (§6.6 Paste group). "Undo paste" (§4.3) = restore the snapshot; we deliberately do **not** try to delete text from the target app (unreliable cross-app) — the spec's design intent is clipboard restore, and that is what we ship. The prototype's per-character typewriter (8ms/char) is a visual mock; the real app pastes atomically, which the spec explicitly permits (§7).

### 3.7 `ContextCapture`

```swift
struct CapturedContext {
    let frontmostApp: String          // bundle id + display name
    let selectedText: String?         // AXSelectedText of focused element
    let clipboard: String?            // only if mode.readsClipboard
    let capturedAt: Date
}
```

Runs in parallel with recording start and must complete within the 600ms `CONTEXT_MS` budget (§7) — that number becomes a real deadline with a `TaskGroup` timeout; the context dot lights when capture lands (§3.1). Selected-text read uses `AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute)` → `kAXSelectedTextAttribute`. Feeds "Super"-flagged modes (§6.2) and auto-activation rules (frontmost app matching, §6.2 editor).

### 3.8 `ModelDownloadManager`

Owns the catalog mirroring the Models screen (§6.4): WhisperKit CoreML bundles from `huggingface.co/argmaxinc/whisperkit-coreml` (tiny / base / small / medium / large-v2 / large-v3 / `large-v3-v20240930` + quantized turbo variants, 547–955MB). States per spec: `none → queued → downloading (progress bytes, MB/s, cancel) → downloaded (set active / delete)`, max 2 concurrent downloads, favorites/starring, DotMeter speed/accuracy ratings as static catalog metadata. Implemented on `URLSession.downloadTask` with resume data; WhisperKit's built-in `download()` is used only as the final import step so bundles land in the layout `WhisperKitConfig(modelFolder:)` expects. Cloud/BYOK rows in the same screen are metadata + Keychain-backed API keys (§6.4 ApiKeyPopover) — no download path.

### 3.9 `Persistence`

JSON files in `~/Library/Application Support/zWhisper/` — see §7.

### 3.10 `OnboardingController`

Ordered, skippable-per-step flow: welcome → microphone (system prompt) → Accessibility (`AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt`) → model download (default tier, with progress — reuse `ModelDownloadManager`) → Apple Intelligence capability check (informational card; sets the `ModeProcessor` backend) → done. See §8 for re-prompt and degradation rules.

---

## 4. The dictation state machine

Formal states, mirroring spec §4 exactly. `AppState.phase` is the single writer; every transition below is a method on `AppState` so invariants (popover visibility, timers, sounds) attach to transitions, not to call sites.

```swift
enum DictationPhase: Equatable {
    case idle
    case recording(mode: Mode, startedAt: Date, holdToTalk: Bool)
    case transcribing(audio: AVAudioPCMBuffer)
    case processing(transcript: String, mode: Mode, context: CapturedContext?)
    case pasting(result: String, targetApp: String)
    case pasted(appName: String)          // auto-dismiss after 700ms (§4.3)
    case cancelled                        // shake 400ms, close at 420ms, reset → idle
}
```

| From | Trigger | To | Side effects |
|---|---|---|---|
| idle | `start(mode)` — status item, ⌥⇧Space, PTT keyDown, popover button, auto-activation rule | recording | summon popover if hidden (SPRING_POP §5.1), start audio, start context capture (600ms deadline) |
| recording | `stop()` — PTT keyUp, Stop ■, ⌥⇧Space | transcribing | stop tap, waveform settle (300ms center-out, §3.2), teal shimmer |
| recording | mode switch ⌘1–7 / switcher | recording (same) | mode pill pulses (SPRING_MICRO); audio keeps running — do **not** restart capture (prototype restarts its script bank; the real pipeline has nothing to restart) |
| recording / transcribing / processing | `cancel()` — Esc or ✕ (✕ disabled in transcribing/processing per §3.1, Esc always live) | cancelled | shake keyframes `x: [0,−8,8,−4,0]` over 0.4s, close popover at 420ms, discard audio, no paste, no history entry |
| transcribing | final transcript ready | processing | purple shimmer, caption "Processing with {Mode} mode" (§3.1) |
| transcribing | error | cancelled (with error toast) | log; if model missing → route to Models screen |
| processing | processed text ready | pasting | — |
| pasting | `PasteController.paste` completes | pasted | green check, "Pasted to {app}", result toast (6s, Reprocess / Undo paste, §4.3), history entry written |
| pasted | 700ms timer | idle | popover exit (scale→0.9, y→−4, fade); toast lives independently |
| pasted | Reprocess (toast) | processing | remove pasted range = restore clipboard snapshot; advance to next mode in cycle order (§4.3) |

**Timing budgets (spec §7 is the UX contract).** The prototype's `TRANSCRIBE_MS = 900ms` and `PROCESS_MS = 700ms` are not implementation constants — they are **budgets the real pipeline must beat**:

- **Transcription ≤900ms for ≤60s dictations.** WhisperKit on M-series does ~150–300ms per short transcription depending on model, so default to `large-v3-v20240930_626MB` on M2+/16GB and `small` (turbo variant) on baseline M1/8GB. Settings → Sound "Active duration" caps recording length (15s/30s/60s/∞, default 30s §6.6) which keeps the budget honest.
- **Processing ≤700ms to first streamed token.** Foundation Models streams, so render partials into the popover teleprompter as they arrive; Voice Note bypasses entirely (identity).
- Context capture: 600ms deadline (§7 `CONTEXT_MS`).
- Timer display ticks at 50ms with 0.1s resolution (§4.2).

---

## 5. Audio pipeline

Diagram in words (all on a dedicated `AudioActor`, callbacks hop to `@MainActor` only for UI):

```
AVAudioEngine.inputNode
  └─ installTap(bufferSize: 1024)                       // native format, typically 48kHz (~21ms cadence)
       ├─ RMS per buffer → AsyncStream<Float>           // → waveform + Settings input meter
       └─ AVAudioConverter → 16kHz / mono / Float32     // whisper's expected format
            ├─ ring buffer (rolling ~30s window)        // feeds streaming loop
            │    └─ VAD gate (energy-based; WhisperAX pattern)
            │         └─ every ~1s of new voiced audio → WhisperKit transcribe(window)
            │              └─ partial string → teleprompter (§3.1, §4.2)
            └─ full-session accumulator buffer          // complete 16kHz audio since start
                 └─ on stop() → transcribeFinal(full buffer) → Transcript (segments)
                      └─ session audio also written to disk (m4a, AAC 16kHz) for History playback (§6.3)
```

Decisions:

- **Copy WhisperAX's tap pattern, not its UI.** The in-repo example is the validated streaming integration; deviating from it is where WhisperKit projects go wrong. Our tap feeds both RMS and conversion — WhisperAX only needs conversion — so install one tap and fan out.
- **Waveform amplitude = RMS per tap buffer,** smoothed by the spec's per-bar exponential lerp (`h += (target − h)·0.2`, §3.2). The layered-sine `sampleAmplitude` from the prototype is deleted — the lerp, bar geometry (48/28 bars, 4px wide, 6px gap, min 2px), settle stagger, and gradients (§2.6) are kept exactly. Render with SwiftUI `Canvas` inside `TimelineView(.animation)`; `CADisplayLink` only if profiling shows jank on the mini popover.
- **VAD gate** prevents feeding silence to Whisper (speed + hallucination suppression) and implements Settings → Sound "Silence removal" (§6.6). "Dynamic normalization" (same pane) is a pre-RMS gain ramp on the tap buffer; keep both toggles real since they are one-line gates in this pipeline.
- **Recording budget**: cap accumulator at the "Active duration" setting (§6.6); at cap, auto-stop as if `stop()` was pressed.
- Audio file per dictation is written via `AVAudioFile` alongside capture (16kHz mono AAC m4a) so History playback/word-seek (§6.3) has real media without re-encoding later.

---

## 6. Modes engine

**Data model:** `Mode` struct in §3.4. Built-in library ships exactly the §6.2 seed: Voice Transcription ⌘5, Email ⌘1, Message ⌘2, Note ⌘3, Meeting ⌘4, Write for me ⌘6, plus popover-only Super Mode ⌘7 — names, ⌘ indices, colors, and context flags per §6.2/§7. Custom modes are full CRUD via the editor sheet (§6.2): name, 6 color swatches, 8-glyph icon picker, instructions textarea, two context mini-switches, auto-activation rules (`When [app] is frontmost` rows). Persistence is JSON (§7).

**Processing pipeline:**

```
raw transcript
  + mode.instructions                        // system-level guidance
  + CapturedContext?                         // only when mode.readsSelectedText / readsClipboard
  + vocabulary hint (custom words, §6.5)     // already applied at transcription; also appended for spelling fidelity
  → LLM streaming → processed text
```

**Backend selection (`ModeBackend` protocol, exactly two implementations):**

```swift
protocol ModeBackend {
    func stream(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error>
}
```

1. **`FoundationModelsBackend`** (primary; Apple Intelligence enabled): one `LanguageModelSession(instructions: mode.instructions)` per invocation; `session.streamResponse(to:)` for streaming; `@Generable` is **not** used for v1 — modes produce free text, guided generation adds constraint without payoff here. The WWDC26 pluggable-provider surface (`LanguageModel`/`LanguageModelExecutor`) is noted as the future BYOK-inside-FoundationModels path; we do not build on it in v1 because our own protocol already isolates the backend.
2. **`CloudLLMBackend`** (optional extra — never an OS-version fallback, since macOS 26 is the floor): OpenAI-compatible chat-completions over `URLSession` (`/v1/chat/completions`, SSE streaming), provider+key from Models screen BYOK rows (§6.4), keys in Keychain (`kSecAttrAccessibleAfterFirstUnlock`). Used when the user has configured a provider key and either prefers cloud models or Apple Intelligence is unavailable.

Backend choice is made per launch and logged: `FoundationModelsBackend` when `SystemLanguageModel.default.availability` reports available, otherwise a configured `CloudLLMBackend`, otherwise modes other than Voice Note fail with an actionable card (§8) — never a spinner. The choice is re-evaluated on demand because Apple Intelligence can be toggled while the app runs (§10.4). **Voice Note mode short-circuits before either backend** — identity transform, no LLM call, zero latency (§7). Auto-activation rules are evaluated in `AppState.start(mode: nil)` (i.e., when the user triggers dictation without pinning a mode): match `ContextCapture.frontmostApp` (and browser domain for Safari rule rows, via Apple Events *only if granted later* — v1 matches app only, domain field is stored but inert; flag in UI copy).

**Live mode switch during recording** (§4.2 ⌘1–7): updates `activeMode` only; transcription is mode-agnostic, so nothing restarts. The processing pass uses whatever mode is active at `stop()` time.

---

## 7. Persistence

**Decision: plain JSON files in `~/Library/Application Support/zWhisper/`, no SwiftData.** SuperWhisper ships the same approach; the dataset is small (thousands of history entries, dozens of modes/words), the files are human-inspectable and git-friendly (users version their custom modes/vocabulary), and it sidesteps SwiftData's migration machinery for a schema we will churn during development. Writes are atomic (`Data.write(options: .atomic)`), debounced 500ms for high-churn stores, all behind one `PersistenceStore` actor.

```
~/Library/Application Support/zWhisper/
├── history.json          // array<HistoryEntry>, newest first, soft-capped at 1000 entries
├── audio/{entryID}.m4a   // referenced by HistoryEntry.audioPath
├── modes.json            // array<Mode> (custom + per-built-in overrides: disabled, shortcut rebind)
├── vocabulary.json       // { customWords: [Word], replacements: [Replacement] } (§6.5)
├── settings.json         // mirror of §6.6 keys (zw-settings:* equivalents)
└── usage.json            // daily aggregates for the Usage tab (§6.6): words, seconds, wpm
```

`settings.json` (not `UserDefaults`) keeps everything in one inspectable place — the spec's §8 row suggesting UserDefaults is fine for launch-critical flags only; we use `UserDefaults` solely for `hasCompletedOnboarding` and Sparkle keys.

```swift
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var modeID: UUID
    var rawTranscript: String
    var processedText: String
    var audioPath: String?             // relative to Application Support; nil if user disabled audio retention
    var segments: [TranscriptSegment]  // segment-level timings — see §10 on word-level gap
    var undoStack: [ProcessedVersion]  // per-entry reprocess history (§6.3 "Undo")
    var targetApp: String?
}
```

Vocabulary `Word` carries `useCount`/`lastUsedAt` for the §6.5 hover tooltip ("Used N× · last: {when}"); increments happen when the word appears in a final transcript. Usage stats are derived at read time from history + `usage.json` rollups — never a second source of truth.

---

## 8. Permissions & onboarding

| Capability | Mechanism | Without it |
|---|---|---|
| Microphone | `NSMicrophoneUsageDescription` in Info.plist; `AVCaptureDevice.requestAccess(for: .audio)` at onboarding step 2 | Recording button/hotkeys show a disabled state + "Grant microphone access" deep link to System Settings. Nothing else works — this one is hard-required. |
| Accessibility | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` at onboarding step 3; poll `AXIsProcessTrusted()` to detect grant | Auto-paste degrades to "copy to clipboard + toast 'Press ⌘V to paste'"; context capture (selection read) off; PTT focus-guard off (PTT disabled to be safe). App still fully transcribes. |
| Apple Intelligence | Runtime check per launch (and re-checked on demand): `SystemLanguageModel.default.availability` + `Guardrails` state — it can change while the app runs (§10.4) | `ModeProcessor` uses `CloudLLMBackend` if a key exists, else modes other than Voice Note show "requires Apple Intelligence or a cloud key" on invocation. Onboarding card explains, non-blocking. |
| Apple Events | **Not requested in v1** (direct distribution, no automation) | Safari-domain auto-activation rules match app-level only. |

**Onboarding order:** Welcome → Microphone → Accessibility → Default model download (with live progress; this is the longest step and must not feel broken — copy per §6.4 download row states) → Apple Intelligence check → "Try it" (arms a guided first dictation, the real-app equivalent of the prototype's auto-demo §4.1 — skipped permanently on first user interaction, same rule). Re-prompt behavior: a Permissions row in Settings → General shows live grant status with "Open System Settings" buttons (`x-apple.systempreferences:` deep links); if AX is revoked mid-session, the next paste attempt re-shows the prompt once, then falls back to clipboard-copy for the session.

---

## 9. Build order — milestones

Each milestone is independently demo-able and must not be merged past its "done when" bar. Motion values always come from spec §5.1, geometry from §3/§6 — never invent.

**M0 — Project skeleton & menu-bar presence.** Xcode project, SPM pins per §2, `LSUIElement`, `NSStatusItem` with `waveform` icon, empty borderless `NSPanel` popover shell (vibrancy, radius 14, shadow per §2.5) toggled from the status item, JSON persistence layer with unit tests, CI build green. *Done when:* clicking the menu-bar icon shows/dismisses an empty vibrancy panel; app runs headless with no Dock icon.

**M1 — Hotkeys & popover chrome.** KeyboardShortcuts wired for ⌥⇧Space (toggle) and Esc (cancel) with `KeyboardShortcuts.Recorder` in a stub Settings pane; popover adopts spec §3.1 layout with static content: mode pill, 48 idle bars, teleprompter hint, Start/Cancel buttons; summon/dismiss SPRING_POP, cancel shake keyframes; Main/Mini size toggle with animated frame change; draggable. *Done when:* ⌥⇧Space summons the popover anywhere in the OS; Esc shakes and closes it; double-click resizes Main↔Mini with layout springs.

**M2 — Audio capture & live waveform.** `AudioCaptureEngine` per §5; mic permission flow; waveform driven by real RMS (lerp 0.2, settle stagger); recording timer (50ms tick, `m:ss.d`); Settings → Sound input meter (24 segments, §6.6) and silence-removal/normalization toggles functional; 16kHz session audio written to disk. *Done when:* speaking into the mic animates the waveform and meter; stopping settles bars center-out over 300ms; an m4a of the session exists in Application Support. No transcription yet.

**M3 — WhisperKit transcription & teleprompter.** `ModelDownloadManager` minimal (bundled default model download on first launch with progress); `TranscriptionEngine` streaming partials per WhisperAX pattern → teleprompter with active-word accent (§3.1); final transcript on stop; vocabulary prompt injection (§6.5 gap closure). *Done when:* dictate → partial words stream live (target cadence §7: ≤180ms/word feel) → stop → final text in ≤900ms on the pinned default model; teleprompter auto-scrolls to end.

**M4 — Paste pipeline & history.** AX permission flow; `PasteController` full sequence (snapshot → set → ⌘V → restore) with "Undo paste" and "Pasted to {app}" toast (6s, §3.7/§4.3); history entries persisted with audio; History screen list+detail functional (playback, transport, click-to-seek at segment granularity, reprocess bar shell). *Done when:* dictating into TextEdit inserts text at the caret, clipboard is restored after, Undo paste restores the pre-paste clipboard, and the session appears in History with playable audio.

**M5 — Modes engine.** Built-in library per §6.2/§7; `ModeProcessor` with both backends (Foundation Models on 26+, cloud fallback); processing shimmer phase, streaming into teleprompter; Voice Note identity short-circuit; ⌘1–7 live switch; Reprocess from toast advances mode cycle (§4.3). *Done when:* the same utterance produces Voice Note's raw text and Email's formatted rewrite; the rewrite streams with ≤700ms to first token; with Apple Intelligence off it works with a configured cloud key or fails with the actionable card (§8).

**M6 — Management screens.** Modes (grid, editor sheet, delete alert, cycle strip), History (filters, word-level-ish transcript view), Models (full §6.4: filters, starring, 2-concurrent downloads, cancel, BYOK key popover), Vocabulary (chips + replacements + usage counts), Settings (all four panes, all toggles real). All geometry/staggers per §6 and §5.3. *Done when:* every screen matches the spec's component anatomy and every control is wired — no decorative controls except those the spec itself marks decorative.

**M7 — Polish & intelligence.** PTT hold via NSEvent monitors with focus guard; context capture + Super Mode with the 600ms dot deadline; auto-activation rules (app-level); Usage tab stats (real aggregates, count-up animations, sparkline, share card via `ImageRenderer`); sound effect styles (§6.6); reduced-motion compliance (§5.5); Launch-at-login; onboarding flow end-to-end; Sparkle (direct build). *Done when:* full pass over §4 trigger matrix works (all six triggers), and a fresh-install run from onboarding to third dictation has no dead ends.

---

## 10. Risks & open questions

1. **PTT Space-hold focus edge cases.** Holding Space in a browser, game, or VM may deliver synthetic or swallowed key-ups; a stuck "held" state would record indefinitely. Mitigation: safety auto-stop at the Active-duration cap, treat *any* subsequent keyDown from another key as implicit release, and require Accessibility permission for the editable-focus guard — without it PTT is disabled rather than risky. This is the single most likely source of "feels broken" bug reports.
2. **AX reliability across apps.** Electron apps, browsers, and terminals expose focused-element AX inconsistently; "Pasted to {app}" naming and selection capture will sometimes fail while ⌘V still works. Mitigation: paste path never hard-fails on AX misses (toast falls back to "Pasted"), and every AX read has a timeout. Electron targets may need their own AX opt-in flags — document as known limitation.
3. **WhisperKit first-run download UX.** Default model is ~626MB; onboarding must not look hung. The Models-screen download-row pattern (§6.4: progress bytes + MB/s + cancel) is reused verbatim in onboarding. Risk remains on metered connections — offer `small` as a "faster start" choice in onboarding.
4. **Foundation Models availability gate.** macOS 26 with Apple Intelligence **off** is a real configuration; `SystemLanguageModel.default.availability` must be checked per launch (it can change while the app runs if the user toggles it). Modes other than Voice Note must fail with an actionable card, never a spinner.
5. **Word-level timestamps.** WhisperKit's OSS surface exposes segment-level timings, not reliable per-word timestamps — this affects History's click-any-word seek (§6.3) and the active-word highlight. Ship v1 with **segment-level approximation** (interpolate words linearly across their segment's time span — visually identical to the prototype's synthesized jitter, §7); revisit if WhisperKit promotes `wordTimestamps` to the stable API. Flag this delta in the History screen spec notes.
6. **Sandbox vs direct distribution.** Decision (§2) is direct + unsandboxed, which trades away MAS discoverability and one-click install trust. If MAS becomes a requirement, the deltas are: sandbox on, Sparkle out, `-weak_framework Combine` retained, Apple Events entitlement needed for any future Safari-domain rules, and a review-risk conversation about Accessibility-prompting apps. Revisit only with a concrete MAS business case.
7. **KeyboardShortcuts Combine linker flag.** `-weak_framework Combine` is easy to forget in a new target configuration (e.g., a future TestFlight/CI config) and fails at runtime, not link time. Add a build-phase assertion or README checklist item at M0.

---

*End of architecture plan. Pixel/motion/copy questions: consult `zwhisper-design-spec.md`. Platform/API questions: consult this document. New conflicts discovered during implementation: update the spec, not the code's fidelity to the spec.*

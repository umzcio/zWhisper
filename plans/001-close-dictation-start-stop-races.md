# Plan 001: Close the dictation start/stop race windows (double transcription + stuck PTT recording)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c1e73d3..HEAD -- zwhisper-mac/Sources/zWhisper/AppState/AppState.swift zwhisper-mac/Tests/zWhisperTests/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `c1e73d3`, 2026-09-20

## Why this matters

`AppState`'s dictation state machine changes phase only *after* awaits, so two
trigger events inside the await window both pass the guard:

1. **Double stop**: `stopDictation()` guards on `case .recording` but doesn't
   set `phase = .transcribing` until after `await audio.stop()`. A second stop
   trigger in that window (PTT release + ⌥⇧Space, status-item click, or the
   auto-stop task) starts a **second concurrent transcription of the same
   audio** on one WhisperKit instance and orphans the first task so Esc can no
   longer cancel it.
2. **Quick PTT tap → stuck recording**: `startPushToTalk` sets
   `holdToTalkActive = true` and kicks off an async start; if the user releases
   right-⌘ before the start finishes (a tap under ~100–200 ms), `stopPushToTalk`
   sees `phase == .idle` and drops the stop. The pending start then enters
   `.recording` with nothing held — the mic stays live with no user awareness
   until the active-duration cap fires (or forever, if the cap is ∞). This is
   the exact "stuck recording" failure the architecture doc (§10.1) calls the
   most likely source of bug reports.

## Current state

- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift` (~1064 lines) — the
  dictation state machine. Relevant excerpts as of `c1e73d3`:

```swift
// AppState.swift:591-603 — PTT entry/exit
func startPushToTalk() {
    guard case .idle = phase, !holdToTalkActive else { return }
    holdToTalkActive = true
    startDictation()
}

func stopPushToTalk() {
    guard holdToTalkActive else { return }
    holdToTalkActive = false
    if case .recording = phase {          // ← false while the async start is in flight
        stopDictation()
    }
}

// AppState.swift:605-629 — the guard and the phase write are separated by awaits
func startDictation() {
    guard case .idle = phase else { return }
    Task { @MainActor in
        guard await requestRecordPermission() else { ... }
        ...
        do { try await audio.start() } catch { return }
        phase = .recording(startedAt: .now)   // ← only here does .idle end
        ...
    }
}

// AppState.swift:668-676 — same shape on the stop side
func stopDictation() {
    guard case .recording = phase else { return }
    autoStopTask?.cancel()
    transcriptionTask = Task { @MainActor in
        let sessionAudio = await audio.stop()
        ...
        phase = .transcribing                 // ← window between guard and write
        ...
    }
}
```

- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift:818-841` — `cancel()`
  (Esc) handles `.recording`, `.transcribing`, and `.processing`; read it fully
  before editing so the Esc-during-stop-window path still discards session audio.
- Test conventions: Swift Testing (`import Testing`, `@Test`, `#expect`) with
  protocol-fronted actor mocks. Exemplar: `zwhisper-mac/Tests/zWhisperTests/AppStateDictationTests.swift`
  (`MockAudioCaptureEngine` records `startCalls`/`stopCalls`/`cancelCalls` and
  returns a 1-second 16 kHz PCM buffer from `stop()`). `AppState` is injected
  with mocks via its initializer:

```swift
init(
    audio: AudioCaptureEngineProtocol = AudioCaptureEngine(),
    transcription: TranscriptionEngineProtocol = TranscriptionEngine(),
    modeProcessor: ModeProcessorProtocol = ModeProcessor.makeDefault(),
    paste: PasteControllerProtocol = PasteController(),
    persistence: PersistenceStore = PersistenceStore(),
    requestRecordPermission: @escaping @Sendable () async -> Bool = ...
)
```

  A `MockTranscriptionEngine` already exists in
  `zwhisper-mac/Tests/zWhisperTests/TranscriptionFlowTests.swift` — reuse it.
- Repo conventions: Swift 6 `SWIFT_STRICT_CONCURRENCY=complete`; `AppState` is
  `@MainActor @Observable`; comments reference architecture sections like
  `/// §4.1` — match that style.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests (full suite) | `cd zwhisper-mac && xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | `** TEST SUCCEEDED **` (54 existing + new tests) |

Notes: xcodebuild prints harmless `DVTCoreDevice`/`CoreSimulator` plugin
errors — ignore them; `** TEST SUCCEEDED **` is the only signal. You are NOT
adding or removing source files, so `xcodegen generate` is not required.

## Scope

**In scope** (the only files you should modify):
- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift`
- `zwhisper-mac/Tests/zWhisperTests/AppStateDictationTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `zwhisper-mac/Sources/zWhisper/Hotkeys/HotkeyManager.swift` — its
  implicit-release mitigation stays as-is; this plan fixes the state machine,
  not the event source.
- `TranscriptionEngine.swift` — the partial/final overlap (a separate finding)
  is *not* fixed here; closing the double-stop window removes its only
  guaranteed trigger.
- `AudioCaptureEngine.swift` — no engine changes needed.
- Any UI file.

## Git workflow

- Work on `main` (this repo's convention — solo maintainer commits directly).
- One commit for the fix + tests. Message style from `git log`, short
  imperative, e.g. `Fix double-stop race and stuck PTT recording`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make `stopDictation()` leave `.recording` synchronously

Move `phase = .transcribing` up into the synchronous guard block, before the
`Task` is created, and delete the later assignment inside the task:

```swift
func stopDictation() {
    guard case .recording = phase else { return }
    autoStopTask?.cancel()
    phase = .transcribing
    transcriptionTask = Task { @MainActor in
        let sessionAudio = await audio.stop()
        ...
        // (the old `phase = .transcribing` line here is removed)
```

Then read `cancel()` (`AppState.swift:818-841`) and confirm every branch still
makes sense when `phase` becomes `.transcribing` before `audio.stop()` has
returned (Esc in that window must still cancel the transcription task and
discard the session audio). Adjust nothing unless a branch is now wrong; if one
is and the fix isn't obvious, STOP.

**Verify**: `cd zwhisper-mac && xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **` (all 54 pre-existing tests still green).

### Step 2: Make `startDictation()` single-flight, and honor a PTT release that landed mid-start

Add a private flag and a trigger parameter:

```swift
private var startInFlight = false

enum StartTrigger { case toggle, pushToTalk }

func startDictation(trigger: StartTrigger = .toggle) {
    guard case .idle = phase, !startInFlight else { return }
    startInFlight = true
    Task { @MainActor in
        defer { startInFlight = false }
        guard await requestRecordPermission() else { ...; return }
        ...
        do { try await audio.start() } catch { return }
        // §4.1: a PTT release that landed while the engine was starting
        // must not leave a held-less recording running (§10.1).
        if trigger == .pushToTalk, !holdToTalkActive {
            await audio.cancel()
            return
        }
        phase = .recording(startedAt: .now)
        ...
    }
}
```

Check the real `AudioCaptureEngineProtocol` (in
`Sources/zWhisper/Audio/AudioCaptureEngine.swift:16`) for the exact `cancel()`
signature and use it. Update `startPushToTalk()` to call
`startDictation(trigger: .pushToTalk)`. Find all other `startDictation()`
callers (`grep -n "startDictation" zwhisper-mac/Sources -r`) and leave them on
the default `.toggle`.

**Verify**: full test command above → `** TEST SUCCEEDED **`.

### Step 3: Regression tests

Add to `AppStateDictationTests.swift` (pattern after the existing
`MockAudioCaptureEngine` usage):

1. **Double stop transcribes once**: start a dictation with mocks, wait until
   `phase == .recording`, call `stopDictation()` twice in immediate succession,
   wait for completion; assert the mock transcription engine's
   `transcribeFinal` was called exactly once and exactly one history entry was
   appended. To control timing inside the window, extend the mock audio
   engine's `stop()` (or `start()` in test 2) to suspend on a continuation the
   test resolves manually — add that hook to the existing mock rather than
   building a parallel one.
2. **Quick PTT tap ends idle**: call `startPushToTalk()` then
   `stopPushToTalk()` before releasing the mock's `start()` gate; then release
   it. Assert: `phase` ends `.idle`, `holdToTalkActive == false`, the mock
   transcription engine was never asked to transcribe, and the mock audio
   engine saw `cancel()` (or `stop()` — whichever the implementation uses to
   tear down) rather than entering a live recording.
3. **Double start records once**: two `startDictation()` calls before the
   `start()` gate is released → `startCalls == 1`.

Use polling-with-timeout (`while` + `Task.sleep` up to ~2 s) instead of fixed
sleeps where possible.

**Verify**: full test command → `** TEST SUCCEEDED **`, and the output lists
your 3 new tests as passed.

## Test plan

Covered in Step 3 — the tests are the deliverable's proof. Existing structural
pattern: `zwhisper-mac/Tests/zWhisperTests/AppStateDictationTests.swift`.

Verification: `cd zwhisper-mac && xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → all pass, 57 total.

## Done criteria

- [ ] Full test suite passes (`** TEST SUCCEEDED **`), including the 3 new tests
- [ ] `phase = .transcribing` appears exactly once in `stopDictation()`, before the `Task`
- [ ] `grep -n "startInFlight" zwhisper-mac/Sources/zWhisper/AppState/AppState.swift` shows the guard, the defer, and no leftover unused flag
- [ ] `grep -rn "startDictation" zwhisper-mac/Sources` shows PTT passing `.pushToTalk` and all other callers on the default
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" don't match the live code (drift).
- Moving `phase = .transcribing` synchronously breaks `cancel()` semantics in a
  way that needs more than a one-line guard adjustment.
- `AudioCaptureEngineProtocol` has no `cancel()` (or equivalent teardown) —
  report what it does have instead of inventing one.
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Any future dictation trigger (e.g. a Siri intent, auto-start on status-item
  click) must route through `startDictation(trigger:)` so the single-flight
  guard keeps covering it.
- `TranscriptionEngine`'s "one pass at a time" comment is only half-enforced
  (a partial pass can still overlap `transcribeFinal` on the same WhisperKit
  instance; known separate finding). If someone later fixes that inside
  `TranscriptionEngine`, these guards remain necessary — they protect the
  *state machine*, not the engine.
- Reviewer: scrutinize the `defer { startInFlight = false }` placement — every
  early return inside the task must release the flag.

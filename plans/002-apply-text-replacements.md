# Plan 002: Apply Vocabulary text replacements in the dictation pipeline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c1e73d3..HEAD -- zwhisper-mac/Sources/zWhisper/AppState/AppState.swift zwhisper-mac/Sources/zWhisper/Persistence/Models.swift zwhisper-mac/Tests/zWhisperTests/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none (touches `AppState.stopDictation` region — if plan 001
  is in flight simultaneously, land 001 first to avoid a merge collision)
- **Category**: direction (dead shipped feature → make it live)
- **Planned at**: commit `c1e73d3`, 2026-09-20

## Why this matters

Text Replacements are a fully shipped feature — CRUD in `AppState`, an editable
table in the Vocabulary screen, persistence in `vocabulary.json`, and
advertising in `README.md` ("text replacements that actually reach the
recognizer") and in-app copy ("Automatically swap phrases during processing") —
but **nothing in the dictation pipeline ever reads `vocabulary.replacements`**.
Users who populate the table get exactly nothing. Wiring it is small and has a
clean test story.

## Current state

- `zwhisper-mac/Sources/zWhisper/Persistence/Models.swift:50-54` — the model:

```swift
struct Replacement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var trigger: String
    var replacement: String
}
```

- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift:239-252` — CRUD
  (`addReplacement`, `updateReplacement`, `removeReplacement`) mutating
  `vocabulary.replacements` and saving `vocabulary.json`.
- A grep for `replacements` across `Sources/zWhisper` finds **only** those
  writes plus the Vocabulary UI — the pipeline never reads them. (Verify
  yourself: `grep -rn "replacements" zwhisper-mac/Sources/zWhisper --include="*.swift"`.)
- The place the final transcript lands, `AppState.swift:680-687` inside
  `stopDictation()`'s task:

```swift
let transcript = try await transcription.transcribeFinal(sessionAudio)
...
guard case .transcribing = phase else { return }
lastTranscript = transcript
transcriptText = transcript.text
partialText = ""
noteVocabularyUsage(in: transcript.text)
```

  From there `processAndPaste(transcript)` (`:704`) either pastes
  `transcript.text` verbatim (Voice Note / identity mode, `:706-708`) or feeds
  it as `raw:` to the mode processor (`:716`).
- **Design decision (made here, implement exactly this)**: apply replacements
  to the final transcript **before** mode processing — one deterministic pass,
  used for both identity modes and as the `raw:` input to the LLM. Rationale:
  the trigger is a raw-dictation artifact ("my email"), guaranteed present in
  the transcript; after an LLM rewrite the trigger phrase may no longer exist
  to match. The LLM may still reword the *replacement* text in rewrite modes —
  accepted for v1 (see Maintenance notes).
- Matching semantics (implement exactly this): **case-insensitive, whole-word**
  matching — trigger `cat` must not rewrite `concatenate`. Multi-word triggers
  ("my email") must work.
- Design-spec vocabulary the feature comes from: the design doc seeds examples
  like "my email" → the user's address. Keep UI copy unchanged.
- Test conventions: Swift Testing (`import Testing`, `@Test`, `#expect`),
  protocol-fronted mocks. `MockTranscriptionEngine` lives in
  `zwhisper-mac/Tests/zWhisperTests/TranscriptionFlowTests.swift`; a mock
  `ModeProcessorProtocol` capturing its `raw:` input lives in
  `ModeFlowTests.swift` (`ModeProcessorProtocol` is defined at
  `Sources/zWhisper/Modes/ModeProcessor.swift:16`). `AppState` takes all
  engines via initializer injection.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests (full suite) | `cd zwhisper-mac && xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | `** TEST SUCCEEDED **` |

Notes: xcodebuild prints harmless `DVTCoreDevice`/`CoreSimulator` plugin
errors — ignore them. You are not adding/removing source files, so
`xcodegen generate` is not required.

## Scope

**In scope** (the only files you should modify):
- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift`
- `zwhisper-mac/Tests/zWhisperTests/TranscriptionFlowTests.swift` (or a new
  test file — if you create one, you MUST run `xcodegen generate` afterward,
  because `project.yml` lists test files explicitly; verify the new file
  appears in the generated project)

**Out of scope** (do NOT touch, even though they look related):
- `Sources/zWhisper/Modes/*` — threading vocabulary into the LLM *prompt* for
  spelling fidelity is a separate, deliberate follow-up (DIR-02 in the audit);
  don't do it here.
- `VocabularyView.swift`, `Persistence/Models.swift` — model and UI are
  already correct.
- `TranscriptionEngine.swift` — Whisper prompt-token hints already work.
- The `reprocess()` path: replacements apply at transcription time, so a
  reprocess reuses the already-replaced `rawTranscript`. Do not special-case it.

## Git workflow

- Work on `main` (repo convention — solo maintainer commits directly).
- One commit, short imperative message, e.g. `Apply text replacements to transcripts before mode processing`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the replacement pass to `AppState`

Add a private helper near the vocabulary section (`AppState.swift:222-275`):

```swift
/// §6.5 text replacements: deterministic whole-word, case-insensitive swap
/// applied to the final transcript before mode processing.
private func applyingReplacements(to text: String) -> String {
    var result = text
    for entry in vocabulary.replacements {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: entry.trigger) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: NSRegularExpression.escapedTemplate(for: entry.replacement)
        )
    }
    return result
}
```

(Caveat: `\b` is ASCII-oriented; triggers consisting purely of non-word
characters like `->` won't match at a `\b` boundary. If you need to handle
those, STOP and report rather than redesigning the matching semantics.)

### Step 2: Apply it where the final transcript lands

In `stopDictation()`'s task, after the
`guard case .transcribing = phase else { return }` line, wrap the text:

```swift
lastTranscript = transcript
let replaced = applyingReplacements(to: transcript.text)
transcriptText = replaced
partialText = ""
noteVocabularyUsage(in: replaced)
```

and make sure the value handed to `processAndPaste` is the replaced text. The
cleanest way that preserves the `Transcript` type's segments: keep
`lastTranscript = transcript` as-is, and change the downstream call to
`await processAndPaste(...)` so the **text** it uses is the replaced string
(read `processAndPaste` at `:704-735`; it currently reads `transcript.text` in
three places — the identity branch, the `raw:` argument, and the
`processedText.isEmpty` fallback — all three must use the replaced text).
History's `rawTranscript` will then record the replaced text; that is the
intended behavior for v1 (the entry's text is what was actually processed and
pasted).

**Verify**: full test command → `** TEST SUCCEEDED **` (existing 54 tests stay green).

### Step 3: Regression tests

Add tests (reuse the mocks from `TranscriptionFlowTests.swift` /
`ModeFlowTests.swift`):

1. **Identity mode applies replacements**: with Voice Note active and a
   replacement ("my email" → "zach@example.com") added via
   `appState.addReplacement`, run a dictation with a mock transcript of
   "send it to my email please"; assert the pasted/history `processedText`
   contains "zach@example.com".
2. **LLM modes receive replaced raw**: with a rewrite mode active, assert the
   mock mode processor's captured `raw:` input contains the replacement, not
   the trigger.
3. **Case-insensitive**: trigger "my email" matches dictated "My Email".
4. **Whole-word**: trigger "cat" does not alter "concatenate".

**Verify**: full test command → `** TEST SUCCEEDED **`, new tests listed as passed.

## Test plan

Covered in Step 3. Structural pattern: `zwhisper-mac/Tests/zWhisperTests/TranscriptionFlowTests.swift`
(mock transcription engine feeding a fixed transcript through `stopDictation`).

## Done criteria

- [ ] Full test suite passes, including the 4 new tests
- [ ] `grep -rn "applyingReplacements" zwhisper-mac/Sources` shows the helper and its call site(s)
- [ ] No file under `Sources/zWhisper/Modes/` is modified (`git status`)
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the cited locations doesn't match the excerpts (drift — plan 001
  also edits `stopDictation`; if it landed first, reconcile carefully and only
  STOP if the flow is no longer recognizable).
- The `Transcript` type turns out not to let you carry replaced text cleanly
  through `processAndPaste` without changing `TranscriptionEngineProtocol` —
  report the shape you found instead of changing the protocol.
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- Known accepted limitation: in rewrite modes the LLM may reword the inserted
  replacement text. A post-LLM second pass was considered and rejected for v1
  (triggers may not survive the rewrite to be matched). Revisit only with a
  real user complaint.
- Follow-up deliberately out of scope: appending custom vocabulary *words* to
  the mode LLM prompt for spelling fidelity (audit finding DIR-02).
- Reviewer: check that history entries now store the replaced text as
  `rawTranscript` and that this matches how `reprocess()` replays entries.

# Plan 004: Gate result-toast actions on what actually happened (Undo paste / Reprocess)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c1e73d3..HEAD -- zwhisper-mac/Sources/zWhisper/AppState/AppState.swift zwhisper-mac/Sources/zWhisper/UI/Toasts/ResultToastView.swift zwhisper-mac/Sources/zWhisper/Paste/ToastController.swift zwhisper-mac/Tests/zWhisperTests/`
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

The result toast always shows "Undo paste" and "Reprocess", but both can be
wrong or destructive:

1. **Degraded path (no Accessibility permission)**: the transcript stays on the
   clipboard so the user can ⌘V manually — it was never pasted. The toast still
   shows "Undo paste", and pressing it **restores the pre-dictation clipboard,
   wiping the user's only copy of the transcript**.
2. **Auto-paste off**: no receipt exists, so "Undo paste" silently no-ops while
   the toast can flash "Clipboard restored", and "Reprocess" silently no-ops
   because `reprocess()` guards on the receipt instead of the transcript.
3. **Reprocess targets `history.first` blindly**: if the user deletes that
   entry from the History window during the toast's 6-second lifetime, the
   undo-stack version is appended to an unrelated entry.

## Current state

- `zwhisper-mac/Sources/zWhisper/UI/Toasts/ResultToastView.swift:43-53` — both
  buttons render unconditionally:

```swift
if !toast.clipboardRestored {
    // §4.3 toast buttons: Reprocess / Undo paste
    Button("Reprocess", action: onReprocess) ...
    Button("Undo paste", action: onUndo) ...
}
```

- `ResultToast` (`ResultToastView.swift:4-11`) carries only
  `words/duration/subtitle/clipboardRestored`.
- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift:751-767` — receipt
  availability, as of `c1e73d3`:

```swift
var receipt: PasteReceipt?
if settings.autoPaste {
    receipt = try? await paste.paste(text: processed, restoreClipboard: settings.restoreClipboard)
} else {
    await paste.copy(text: processed)
}
lastPasteReceipt = receipt
// receipt.didPaste == false  ⇔  degraded AX path, transcript still on clipboard
```

- `AppState.swift:810-814` — undo ignores `didPaste`:

```swift
func undoLastPaste() {
    guard let receipt = lastPasteReceipt else { return }
    Task { await paste.undo(receipt) }   // clobbers the clipboard even when didPaste == false
}
```

- `AppState.swift:563-576` — `reprocess()` guards on `lastPasteReceipt != nil`
  (wrong condition; it needs a transcript, not a receipt) and
  `AppState.swift:769-775` updates `history.first` without checking identity.
- `PasteReceipt` (`Sources/zWhisper/Paste/PasteController.swift:5-14`) already
  has `didPaste: Bool` — everything needed is in the type.
- `ToastController` (`Sources/zWhisper/Paste/ToastController.swift`, ~:32-35)
  mutates the toast to "Clipboard restored" after undo — read it and make sure
  that mutation can no longer fire when undo was a no-op.
- Test conventions: Swift Testing (`import Testing`, `@Test`, `#expect`).
  `PasteFlowTests.swift` has a mock `PasteControllerProtocol` and real-NSPasteboard
  `.serialized` suites — model new tests on the mock-based ones.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests (full suite) | `cd zwhisper-mac && xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | `** TEST SUCCEEDED **` |

xcodebuild prints harmless `DVTCoreDevice`/`CoreSimulator` plugin errors —
ignore them. No files added/removed, so `xcodegen generate` is not required.

## Scope

**In scope** (the only files you should modify):
- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift`
- `zwhisper-mac/Sources/zWhisper/UI/Toasts/ResultToastView.swift`
- `zwhisper-mac/Sources/zWhisper/Paste/ToastController.swift` (only if the
  "Clipboard restored" mutation needs gating — read it first)
- `zwhisper-mac/Tests/zWhisperTests/PasteFlowTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `PasteController.swift` — the 250 ms fixed-sleep / changeCount poll is a
  separate finding with its own plan candidate; do not change paste timing here.
- The disabled hard-coded "Reprocess with…" bar in
  `UI/Screens/History/HistoryView.swift` — dead-code removal is a separate
  tech-debt item.
- Any design-token or styling change to the toast.

## Git workflow

- Work on `main` (repo convention).
- One commit, short imperative, e.g. `Gate toast Undo/Reprocess on paste receipt; target reprocess by entry id`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Carry capability flags on the toast model

Add two fields to `ResultToast` (defaults keep existing call sites compiling):

```swift
/// §4.3: Undo paste only when a real ⌘V paste happened (not the AX-degraded
/// clipboard-only path, not the auto-paste-off copy path).
var canUndo: Bool = true
/// §6.3: Reprocess only when there is a transcript to re-run.
var canReprocess: Bool = true
```

In `ResultToastView`, render each button only when its flag is true.

In `AppState.pasteAndFinish` (`:791-796`), set them when building the toast:
`canUndo: receipt?.didPaste == true`, `canReprocess: lastTranscript != nil`.

### Step 2: Harden the two actions

- `undoLastPaste()`: change the guard to
  `guard let receipt = lastPasteReceipt, receipt.didPaste else { return }`.
- Read `ToastController.swift`; if it flips the toast to "Clipboard restored"
  after an undo that is now a no-op, gate that mutation the same way (only when
  `canUndo` was true). If it's already safe because the button can't fire,
  leave it and note why in the commit message.
- `reprocess()` (`:563-576`): change the guard from `lastPasteReceipt != nil`
  to `lastTranscript != nil` so Reprocess works with auto-paste off. Read the
  whole function first — if anything inside genuinely needs the receipt, STOP
  and report what it is.

### Step 3: Target reprocess at the right history entry

- Add `private var lastHistoryEntryID: UUID?` to `AppState`.
- In `pasteAndFinish`'s append branch (`:777-789`), assign the new entry's id
  (create the `HistoryEntry` in a `let` first). In the reprocess branch
  (`:769-775`), look the entry up `byID: lastHistoryEntryID` instead of taking
  `history.first`; if it's gone (user deleted it), just proceed to paste
  without touching history.

### Step 4: Regression tests in `PasteFlowTests.swift`

1. **Degraded path can't be undone**: mock paste returning
   `PasteReceipt(..., didPaste: false)` → toast model has `canUndo == false`;
   calling `undoLastPaste()` performs zero undo calls on the mock.
2. **Auto-paste off**: toast has `canUndo == false`, `canReprocess == true`;
   `reprocess()` re-runs processing (assert the mock mode processor saw a
   second `process` call).
3. **Reprocess after deleting the entry**: complete a dictation, delete the
   history entry via `deleteHistory(id:)`, call `reprocess()` → no crash, no
   unrelated entry mutated (assert the remaining history is unchanged apart
   from nothing being appended/rewritten).

**Verify** (after each step): full test command → `** TEST SUCCEEDED **`.

## Test plan

Covered in Step 4. Structural pattern: mock `PasteControllerProtocol` in
`zwhisper-mac/Tests/zWhisperTests/PasteFlowTests.swift`.

## Done criteria

- [ ] Full test suite passes, including the 3 new tests
- [ ] `grep -n "canUndo\|canReprocess" zwhisper-mac/Sources/zWhisper/UI/Toasts/ResultToastView.swift zwhisper-mac/Sources/zWhisper/AppState/AppState.swift` shows the flags defined, set, and consumed
- [ ] `undoLastPaste` guards on `receipt.didPaste`
- [ ] `reprocess()` no longer references `lastPasteReceipt` in its guard; history lookup uses an entry id, not `history.first`
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" don't match the live code (drift).
- `reprocess()` turns out to genuinely need the paste receipt (not just the
  transcript) — report the dependency instead of working around it.
- Gating the buttons requires changing the toast's visual layout beyond
  conditional rendering (design decision needed).
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- If a future "copy-only" toast variant wants Undo to mean "restore previous
  clipboard" even without a paste, that's a *new* behavior with its own UX —
  don't conflate it with this fix.
- The separate COR-04 finding (250 ms fixed sleep, changeCount never checked)
  will touch `PasteController.paste`; when it lands, re-check that
  `PasteReceipt.didPaste` semantics are unchanged.
- Reviewer: verify the toast with auto-paste OFF in a manual run — it should
  show Reprocess only.

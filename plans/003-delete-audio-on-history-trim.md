# Plan 003: Delete session audio files when history trims past 1000 entries

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
- **Category**: bug (privacy/disk — silent unbounded retention of voice recordings)
- **Planned at**: commit `c1e73d3`, 2026-09-20

## Why this matters

History is soft-capped at 1000 entries, but the trim only drops the rows — the
trimmed entries' `.m4a` session recordings are never deleted. After 1000
dictations, raw voice audio accumulates unboundedly in
`~/Library/Application Support/zWhisper/audio/` with no UI surface and no code
path that ever removes it. The single-entry delete path already deletes the
file; the trim path was simply missed.

## Current state

- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift:411-433` — the
  asymmetry, as of `c1e73d3`:

```swift
/// Newest first, soft-capped at 1000 entries (§7).
func appendHistory(_ entry: HistoryEntry) {
    history.insert(entry, at: 0)
    if history.count > 1000 {
        history.removeLast(history.count - 1000)   // ← audio files of removed entries leak
    }
    Task { await persistence.saveDebounced(history, to: "history.json") }
}

func deleteHistory(id: UUID) {
    guard let index = history.firstIndex(where: { $0.id == id }) else { return }
    let entry = history.remove(at: index)
    if let path = entry.audioPath {
        Task { await persistence.deleteFile(path) }   // ← the pattern to mirror
    }
    Task { await persistence.saveDebounced(history, to: "history.json") }
}
```

- `HistoryEntry.audioPath` (`Sources/zWhisper/Persistence/Models.swift:13`) is
  a path relative to the persistence directory; `persistence.deleteFile(_:)`
  (in `Sources/zWhisper/Persistence/PersistenceStore.swift`) takes that
  relative path.
- Test conventions: Swift Testing (`import Testing`, `@Test`, `#expect`).
  `PersistenceStore` is a concrete class whose initializer takes a directory —
  existing tests in `zwhisper-mac/Tests/zWhisperTests/PersistenceStoreTests.swift`
  construct it against a temp directory; follow that pattern. AppState-level
  history tests exist in `AppStateTests.swift`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests (full suite) | `cd zwhisper-mac && xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | `** TEST SUCCEEDED **` |

xcodebuild prints harmless `DVTCoreDevice`/`CoreSimulator` plugin errors —
ignore them. No files added/removed, so `xcodegen generate` is not required.

## Scope

**In scope** (the only files you should modify):
- `zwhisper-mac/Sources/zWhisper/AppState/AppState.swift`
- `zwhisper-mac/Tests/zWhisperTests/AppStateTests.swift`

**Out of scope** (do NOT touch, even though they look related):
- `PersistenceStore.swift` — `deleteFile` already works; no changes needed.
- `AudioCaptureEngine.swift` — session-file lifecycle on cancel/failure is
  already correct.
- A launch-time sweep of unreferenced files in `audio/` — considered and
  deliberately excluded (trim fix covers the leak going forward; a sweep is a
  riskier deletion path that needs its own design).
- Any pretty-print/serialization changes to `history.json` (separate perf
  finding, not this plan).

## Git workflow

- Work on `main` (repo convention).
- One commit, short imperative, e.g. `Delete session audio when history trims past 1000 entries`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Mirror the delete path in the trim branch

In `appendHistory`, capture the trimmed tail and delete its audio files:

```swift
func appendHistory(_ entry: HistoryEntry) {
    history.insert(entry, at: 0)
    if history.count > 1000 {
        let trimmed = history.suffix(from: 1000)
        for path in trimmed.compactMap(\.audioPath) {
            Task { await persistence.deleteFile(path) }
        }
        history.removeLast(history.count - 1000)
    }
    Task { await persistence.saveDebounced(history, to: "history.json") }
}
```

**Verify**: full test command → `** TEST SUCCEEDED **` (54 existing tests green).

### Step 2: Regression test with real files

Add a test in `AppStateTests.swift`:

1. Construct `AppState` with a temp-directory `PersistenceStore` (pattern from
   `PersistenceStoreTests.swift`) and the standard mocks.
2. Pre-create a real empty file for entry #1001's `audioPath` under the temp
   dir (e.g. `audio/old-session.m4a` — create the subdirectory too), seed
   `history` with 1000 entries, then append a 1001st whose `audioPath` points
   at a second real file.
3. Assert: `history.count == 1000`, and after a short poll (the deletion runs
   in a `Task`), the trimmed entry's file no longer exists on disk while the
   surviving entries' files do.

Avoid fixed multi-hundred-ms sleeps; poll up to ~2 s for the file to vanish.

**Verify**: full test command → `** TEST SUCCEEDED **`, new test listed as passed.

## Test plan

Covered in Step 2. Structural patterns: temp-dir store from
`PersistenceStoreTests.swift`, AppState assembly from `AppStateTests.swift`.

## Done criteria

- [ ] Full test suite passes, including the new trim-deletion test
- [ ] `sed -n '411,425p' zwhisper-mac/Sources/zWhisper/AppState/AppState.swift` shows the trim branch deleting trimmed entries' audio
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpt in "Current state" doesn't match the live code (drift).
- `PersistenceStore.deleteFile` turns out to have different semantics than
  "delete a relative path under the store directory" — report its actual
  contract.
- The test's file deletion cannot be observed without >2 s of polling
  (indicates the deletion task isn't running — debug once, then stop).

## Maintenance notes

- If the history cap (1000) is ever made configurable, the trim logic here
  keeps working — it keys off the literal in one place; lift it to a constant
  then.
- If per-entry audio retention (an "audio off" setting) is added later, this
  path stays correct: trimmed entries with `audioPath == nil` are skipped by
  the `compactMap`.
- Reviewer: confirm the deletion `Task` ordering can't delete a file still
  referenced by a *surviving* entry (it can't — paths are per-session UUIDs).

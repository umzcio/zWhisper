# Plan 005: Fix ModelCatalog "Ultra" row id duplicating "small" on baseline hardware

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c1e73d3..HEAD -- zwhisper-mac/Sources/zWhisper/Models/ zwhisper-mac/Sources/zWhisper/AppState/AppState.swift zwhisper-mac/Tests/zWhisperTests/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `c1e73d3`, 2026-09-20

## Why this matters

The Models catalog's "Ultra" row takes its `id` from
`ModelDownloadManager.defaultModelName`, which returns `"small"` on baseline
M1 / <16 GB machines. On exactly the hardware that logic targets, the catalog
becomes `[tiny, small, medium, small]` — duplicate `Identifiable` ids in a
SwiftUI `ForEach`, row state (`modelStates["small"]`) conflating the "Fast" and
"Ultra" rows, and a Download tap on "Ultra" that would fetch `small` again and
label it Ultra. The catalog id should be the literal variant string; the
hardware-aware *default choice* logic is separate and correct.

## Current state

- `zwhisper-mac/Sources/zWhisper/Models/ModelCatalog.swift:18-24` — as of
  `c1e73d3`:

```swift
static let locals: [ModelCatalogEntry] = [
    // §8 tier mapping: tiny≈Nano, small≈Fast, medium≈Pro, large-v3≈Ultra.
    ModelCatalogEntry(id: "tiny", name: "Nano", ...),
    ModelCatalogEntry(id: "small", name: "Fast", ...),
    ModelCatalogEntry(id: "medium", name: "Pro", ...),
    ModelCatalogEntry(id: ModelDownloadManager.defaultModelName, name: "Ultra", ...),  // ← "small" on M1/8GB
]
```

- `zwhisper-mac/Sources/zWhisper/Models/ModelDownloadManager.swift:10-15` — the
  default-choice logic (keep as-is):

```swift
static var defaultModelName: String {
    if isBaselineM1 || physicalMemoryGB < 16 {
        return "small"
    }
    return "large-v3-v20240930_626MB"
}
```

- Consumers to check after the change (grep for them; most key off catalog
  `id`s generically and need nothing): `AppState.modelStates`
  (`Sources/zWhisper/AppState/AppState.swift`, ~:277-305),
  `ModelPreferences.favoriteIDs`/`activeLocalID`
  (`ModelCatalog.swift:46-49`), and `ModelsView`'s
  `ForEach(..., id: \.element.id)` (`UI/Screens/Models/ModelsView.swift`, ~:135).
- Test conventions: Swift Testing (`import Testing`, `@Test`, `#expect`). This
  is a pure-data test — no mocks needed.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Tests (full suite) | `cd zwhisper-mac && xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | `** TEST SUCCEEDED **` |

xcodebuild prints harmless `DVTCoreDevice`/`CoreSimulator` plugin errors —
ignore them. No files added/removed, so `xcodegen generate` is not required.

## Scope

**In scope** (the only files you should modify):
- `zwhisper-mac/Sources/zWhisper/Models/ModelCatalog.swift`
- `zwhisper-mac/Tests/zWhisperTests/AppStateTests.swift` (or the most fitting
  existing test file for a pure catalog test — your call, but it must be an
  existing file)

**Out of scope** (do NOT touch, even though they look related):
- `ModelDownloadManager.defaultModelName` — the hardware-aware default is
  correct; this plan only stops *abusing* it as a catalog id.
- `ModelsView.swift` and `AppState` model-state plumbing — only touch if a grep
  reveals code that *assumes* the Ultra row's id equals `defaultModelName`
  (unlikely; if you find such code, that's a STOP condition).
- Cloud catalog rows (dead-provider-row finding is separate).

## Git workflow

- Work on `main` (repo convention).
- One commit, short imperative, e.g. `Fix duplicate Models catalog id on baseline hardware`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Pin the Ultra row's id to the literal variant

In `ModelCatalog.swift`, change the fourth local entry's id to the literal
`"large-v3-v20240930_626MB"` (the same string `defaultModelName` returns for
capable machines — the download/delete/isDownloaded plumbing in
`ModelDownloadManager` already works with variant strings). Leave the row's
name/detail/sizing untouched.

Then run: `grep -rn "defaultModelName" zwhisper-mac/Sources` — every remaining
use must be about *choosing the default model* (onboarding download, initial
active model), never about identifying the Ultra row. If a use conflates the
two, STOP and report it.

**Verify**: full test command → `** TEST SUCCEEDED **` (54 existing tests green).

### Step 2: Catalog integrity test

Add a test asserting:

1. `ModelCatalogEntry.locals.map(\.id)` has no duplicates.
2. `locals` contains exactly the ids `["tiny", "small", "medium", "large-v3-v20240930_626MB"]`.
3. `ModelCatalogEntry.all.map(\.id)` (locals + clouds) has no duplicates.

This test must be hardware-independent — it guards the construction, not the
runtime machine. (If the duplicate-id bug were still present, this test would
fail only on M1/8 GB machines; that's fine — CI runs on Apple Silicon with
≥16 GB, and the test still pins the invariant.)

**Verify**: full test command → `** TEST SUCCEEDED **`, new test listed as passed.

## Test plan

Covered in Step 2. Pure data assertions; any existing test file works as the
structural pattern.

## Done criteria

- [ ] Full test suite passes, including the new catalog integrity test
- [ ] `grep -n "defaultModelName" zwhisper-mac/Sources/zWhisper/Models/ModelCatalog.swift` returns no matches
- [ ] `grep -rn "defaultModelName" zwhisper-mac/Sources` shows only default-*choice* call sites
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpt in "Current state" doesn't match the live code (drift).
- You find code that relies on `locals[3].id == ModelDownloadManager.defaultModelName`
  (e.g. row-state initialization that looks the Ultra row up through the
  default name) — that coupling needs a design decision, not a drive-by fix.
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- If a new local variant is added to the catalog, extend the Step-2 test's
  expected id list — it's the tripwire for this bug class.
- Related but separate: the four cloud rows' keys/backends are mostly unwired
  (audit findings SEC-01/TDA-04); don't fix that here.
- Reviewer: sanity-check the Models screen on a ≥16 GB machine — the Ultra row
  should show and behave exactly as before (the id was already this literal
  string there).

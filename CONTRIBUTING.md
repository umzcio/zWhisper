# Contributing to zWhisper

Thanks for helping out. This file covers the workflow that keeps the project coherent — please read it before opening a PR.

## The two source-of-truth documents

- **`zwhisper-swift-architecture.md`** is the *implementation* source of truth: modules, the dictation state machine, the audio pipeline, milestones M0–M7, risks.
- **`zwhisper-design-spec.md`** is the *visual/interaction* source of truth: tokens, geometry, motion, copy. Motion values come from spec §5.1, geometry from §3/§6 — **never invent values**.

Where they conflict on platform mechanics, the architecture doc wins; where they conflict on pixels, motion, or copy, the design spec wins. If the web prototype (`app/src/`) and the design spec disagree, the prototype wins and the spec should be updated.

## Build & test

```sh
cd zwhisper-mac
xcodegen generate        # after any project.yml change or new source file
xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS'
```

- The Xcode project is generated from `project.yml` (XcodeGen). Never edit `zWhisper.xcodeproj` by hand, and **re-run `xcodegen generate` after adding any file** — it writes explicit file lists.
- CI (`.github/workflows/ci.yml`) runs exactly the command above on `macos-26` for changes under `zwhisper-mac/**`. Keep it green.
- Tests are Swift Testing (`@Suite`/`@Test`) in `zwhisper-mac/Tests/zWhisperTests/`. Engines are protocol-fronted so the pipeline can be replayed with mocks — add tests when you touch state machine or engine logic.
- The web prototype has no test suite: `npm run build` (type-check) + `npm run lint` must pass.

## Conventions that matter

- **Milestone discipline** (architecture §9): each milestone has a "done when" bar. Don't merge work past a milestone's scope.
- **Swift 6 strict concurrency.** `AppState` is the only writer of the dictation `phase`. All services are protocol-fronted actors; UI observes `AppState` only.
- **Hotkey discipline:** anything user-facing (Esc, ⌘-digits) is claimed only while the popover is open. A permanently-registered global hotkey steals the key from every app — we learned this the hard way.
- **Persistence:** debounced atomic JSON in `~/Library/Application Support/zWhisper/` via the `PersistenceStore` actor — no SwiftData.
- **Deployment target stays macOS 26.0** (Foundation Models floor). No `#available` gates; the only runtime check is `SystemLanguageModel.default.availability`.
- **No new dependencies** without an architecture-doc discussion. Sparkle stays out of any Mac App Store build.
- **`OTHER_LDFLAGS` must keep `-weak_framework Combine`** (KeyboardShortcuts fails at runtime without it). A pre-build script enforces this.
- **Code style:** match the file you're in. Default to no comments; when code implements a specific spec section, reference it (e.g. `// §6.4`).

## Security

- No sandbox entitlements on the direct build; the MAS path is explicitly deferred.
- BYOK cloud keys go to the Keychain, never disk. Never commit secrets.
- Mic and Accessibility permissions degrade gracefully — never hard-fail on a permission miss (see architecture §8).

## PRs

- Reference the spec section your change implements.
- Include the "done when" evidence: tests pass, plus a note on how you verified the behavior live (we verify against the real running app, not just compiles).

# zWhisper — macOS app

Native Swift/SwiftUI implementation of the zWhisper design spec (`../zwhisper-design-spec.md`),
following `../zwhisper-swift-architecture.md` (the implementation source of truth).

## Status: M7 — polish & intelligence (feature-complete)

- Xcode project generated with [XcodeGen](https://github.com/yonsm/XcodeGen) from `project.yml` (do not edit `zWhisper.xcodeproj` by hand).
- SPM pins per architecture §2: WhisperKit (`argmaxinc/argmax-oss-swift`, from 1.0.0), KeyboardShortcuts (2.x), LaunchAtLogin-Modern (1.x), Sparkle (2.x, direct distribution only — SUFeedURL/SUPublicEDKey are placeholders until a real appcast exists).
- Full dictation loop per architecture §4 with all six §4.1 triggers: status item, ⌥⇧Space, push-to-talk (**hold right ⌘**, NSEvent monitors, implicit-release + editable-focus guard for custom keys), popover Start button, onboarding "Try it", §6.2 auto-activation rules (app-level).
- Context capture (§3.7): frontmost app + AX selection + clipboard against the 600ms §7 deadline; §3.1 context dot with halo + tooltip; Super-flagged modes get the context in their prompt.
- Hotkey discipline: bare Esc and ⌘1–⌘7 are claimed **only while the popover is open** — a permanently-registered bare Esc would steal Escape from every app system-wide, and ⌘-digits would steal iTerm/Chrome tab switching. ⌥⇧Space/⌥⇧K/right-⌘ are always-on (no conflicts).
- Onboarding (§8): first-run window — Welcome → Microphone → Accessibility → default-model download (progress + MB/s + cancel) → Apple Intelligence check → "Try it" guided dictation; `hasCompletedOnboarding` in UserDefaults; §8 Permissions row in Settings → General with live status + deep links.
- Usage tab (§6.6): real aggregates from history, count-ups, 7-day sparkline, typing test with compare bars, share card (Copy text real, PNG decorative per spec).
- Reduced motion (§5.5): 150ms fades instead of springs, static waveform bars, glow off, shimmer slowed to 3s (honors `accessibilityDisplayShouldReduceMotion`).
- Sound effects (§6.6): Subtle/Classic/None record start/stop blips, synthesized off-main.
- Management screens (M6), modes engine (M5), paste pipeline (M4), transcription (M3), audio + waveform (M2), hotkeys + popover (M1), persistence (M0) — see git history for per-milestone detail.
- Deployment target macOS 26.0 (Foundation Models floor — §2), Swift 6 language mode, strict concurrency.

## Build & test

```sh
brew install xcodegen   # once
xcodegen generate
xcodebuild test -project zWhisper.xcodeproj -scheme zWhisper -destination 'platform=macOS'
```

## Checklist for new build configurations (architecture risk 10.7)

- [ ] `OTHER_LDFLAGS` contains `-weak_framework Combine` (KeyboardShortcuts fails at **runtime**, not link time, without it). A pre-build script fails the build if the flag is missing — keep it in every target that links KeyboardShortcuts.
- [ ] Deployment target stays at macOS 26.0 (Foundation Models floor — architecture §2).
- [ ] No sandbox entitlements on the direct build (architecture §2); MAS path is explicitly deferred.

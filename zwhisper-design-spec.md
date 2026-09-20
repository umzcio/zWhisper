# zWhisper — Design Handoff Specification

**Audience:** Swift/SwiftUI/AppKit engineering. **Source of truth:** the implemented web prototype (`/mnt/agents/output/app`); design docs (`/mnt/agents/output/design/*.md`) are the stated intent. Where the two disagree, the **implementation is documented** and marked `(delta from design: …)`.

All measurements are CSS pixels (1 CSS px = 1 pt on macOS). Colors are hex as shipped. Motion values are Framer Motion spring parameters with SwiftUI conversions in §5.

---

## 1. Product overview & design principles

zWhisper is a macOS menu-bar AI dictation app (SuperWhisper-class). Pipeline:

```
Dictate → Transcribe (Whisper) → Smart Process (per-mode LLM rewrite) → Auto-paste at caret
```

The web prototype simulates this end-to-end with a scripted mock engine — no real audio, no APIs. To preview native look/feel, the prototype presents a **faux macOS desktop**: wallpaper backdrop, functional menu bar, a demo "Notes" window that receives pasted dictations, and a floating recording popover that behaves like an `NSPanel`. All other screens (Modes, History, Models, Vocabulary, Settings) are management windows with traffic-light chrome and vibrancy surfaces.

Design principles, in priority order:

1. **Native-fidelity first** — every component maps 1:1 to an AppKit/SwiftUI equivalent (vibrancy panels, traffic lights, segmented controls, sheets). No web/marketing patterns.
2. **The recording popover is the hero** — spring physics, live waveform, teleprompter text, breathing glow.
3. **Micro-interaction density** — every control has hover/press spring feedback. macOS feels snappy; match that.
4. **Dark-first** — dark is the default theme; light theme available in Settings.

---

## 2. Design tokens

Defined in `src/index.css` (`:root` dark, `.light` overrides) and surfaced through `tailwind.config.js`.

### 2.1 Color tokens — Dark theme (default)

| Token | Value | Usage | Apple system color (Swift) |
|---|---|---|---|
| `--stage` | `#0B0B0F` | Desktop stage base behind wallpaper | — (near-black custom) |
| `--surface-1` | `#1C1C1E` | Window/popover body — used at 80% opacity + blur (vibrancy, see §2.5) | `NSColor.secondarySystemFill`-adjacent; ship as `NSVisualEffectView` |
| `--surface-2` | `#2C2C2E` | Cards, list rows, sidebar, grouped-list fills | `systemGray` dark ≈ |
| `--surface-3` | `#3A3A3C` | Hover states, pressed rows, switch track (off) | `systemGray` dark fill 2 |
| `--separator` | `#FFFFFF14` (white @ 8%) | 1px hairline borders everywhere | `NSColor.separatorColor` |
| `--text-1` | `#F5F5F7` | Primary text | `NSColor.labelColor` |
| `--text-2` | `#98989D` | Secondary text | `NSColor.secondaryLabelColor` |
| `--text-3` | `#636366` | Tertiary/placeholder text | `NSColor.tertiaryLabelColor` |
| `--zw-accent` (Tailwind `accent-blue`) | `#0A84FF` | Primary actions, active mode, links, focus rings | `NSColor.systemBlue` (dark variant) |
| `--accent-green` | `#30D158` | Recording-active indicator, success, switch track (on) | `NSColor.systemGreen` (dark) |
| `--accent-red` | `#FF453A` | Record/stop button, destructive | `NSColor.systemRed` (dark) |
| `--accent-orange` | `#FF9F0A` | Warnings, cloud-model badges | `NSColor.systemOrange` (dark) |
| `--accent-purple` | `#BF5AF2` | "Super Mode" / AI processing accents, context dot | `NSColor.systemPurple` (dark) |
| `--accent-teal` | `#64D2FF` | Waveform gradient secondary | `NSColor.systemTeal`-adjacent (custom `#64D2FF` ≈ systemTeal dark) |

Auxiliary hard-coded colors: star/favorite accent `#FFD60A` (`NSColor.systemYellow`); traffic lights `#FF5F57` / `#FEBC2E` / `#28C840`; selected-row/sidebar tint `#0A84FF26` (systemBlue @ 15%); per-mode icon tint = mode color @ 15% (`{color}26` suffix).

### 2.2 Color tokens — Light theme

| Token | Value | Dark counterpart |
|---|---|---|
| `--stage` | `#E8E8ED` | `#0B0B0F` |
| `--surface-1` | `#FFFFFF` (80% opacity when vibrant) | `#1C1C1E` |
| `--surface-2` | `#F5F5F7` | `#2C2C2E` |
| `--surface-3` | `#E8E8EA` | `#3A3A3C` |
| `--separator` | `#00000014` (black @ 8%) | `#FFFFFF14` |
| `--text-1` | `#1D1D1F` | `#F5F5F7` |
| `--text-2` | `#6E6E73` | `#98989D` |
| `--text-3` | `#AEAEB2` | `#636366` |
| `--zw-accent` | `#007AFF` | `#0A84FF` |
| `--accent-green` | `#28C840` | `#30D158` |
| `--accent-red` | `#FF3B30` | `#FF453A` |
| `--accent-orange` | `#FF9500` | `#FF9F0A` |
| `--accent-purple` | `#AF52DE` | `#BF5AF2` |
| `--accent-teal` | `#32ADE6` | `#64D2FF` |

These light values are the standard iOS/macOS light system colors; in Swift, prefer semantic `NSColor.system*` and let dark/light resolve automatically.

### 2.3 Typography

Fonts: **Inter** (UI; SF Pro proxy — in Swift use `NSFont.systemFont` / SwiftUI `.font(.system(...))`) and **JetBrains Mono** (shortcut glyphs, timers, timestamps — in Swift use `NSFont.monospacedSystemFont` / `.font(.system(.body, design: .monospaced))`). Body base: 13px/400, tracking −0.005em, antialiased.

| Role | Font | Size | Weight | Tracking | Notes |
|---|---|---|---|---|---|
| Window title | Inter | 13px | 600 | −0.01em | centered in 28px title bar, `text-2` color |
| Section heading | Inter | 20px | 700 | −0.02em | page headers (Modes, Models, …) |
| Body | Inter | 13px | 400 | −0.005em | default |
| Body emphasis | Inter | 13px | 500–600 | −0.005em | row titles, card names |
| Small label / meta | Inter | 11–12px | 400–600 | 0–0.02em | captions, badges (uppercase 10–11px use tracking 0.02em) |
| Teleprompter text | Inter | 17px | 500 | −0.01em | popover streaming text |
| Transcript body (History) | Inter | 15px | 500 | −0.01em | leading relaxed |
| Popover mode label | Inter | 12px | 600 | 0.02em, uppercase | compact variant: 10px |
| Shortcut glyphs | JetBrains Mono | 11px | 500 | 0 | ShortcutKey chips |
| Timestamps / timers | JetBrains Mono | 11–12px | 400–500 | 0 | `tabular-nums` everywhere |
| Stat numerals | Inter | 32px | 700 | −0.03em, tabular-nums | Usage tab only — never use display type elsewhere |

### 2.4 Spacing, radii, borders

- **Spacing scale** (4px base): 4, 8, 12, 16, 20, 24, 32. Popover inner padding 12 (`p-3`); window content padding 20–24 (`px-5/px-6`).
- **Radii**: popover 14px; windows and mode cards 12px; grouped-list cards 10px; menus/sheets' inner menus 8–10px; controls (buttons, inputs, kbd) 6px; segmented control 6–8px outer / 5–6px inner; pills 999px (full round). Tailwind `--radius` base = 10px (`0.625rem`) for shadcn primitives.
- **Borders**: hairline = `1px solid var(--separator)` on virtually every panel/card/control.

### 2.5 Shadows & vibrancy

| Token | Dark | Light | Usage |
|---|---|---|---|
| `--window-shadow` | `0 32px 96px rgba(0,0,0,0.45)` | `0 32px 96px rgba(0,0,0,0.18)` | management windows, sheets |
| `--popover-shadow` | `0 24px 64px rgba(0,0,0,0.5), 0 0 0 0.5px rgba(255,255,255,0.1)` | `0 24px 64px rgba(0,0,0,0.25), 0 0 0 0.5px rgba(0,0,0,0.08)` | popovers, toasts, menus |
| Card hover lift | `0 12px 32px rgba(0,0,0,0.35)` | — | mode cards on hover |
| kbd / control inner | `0 1px 0 rgba(255,255,255,0.06)` (bottom edge highlight) | — | ShortcutKey, dropdowns |

Vibrancy (CSS → AppKit):

| Surface | CSS | Swift |
|---|---|---|
| `.vibrancy` (windows, popovers) | `background: var(--surface-1-translucent)` (`rgba(28,28,30,0.8)` dark / `rgba(255,255,255,0.8)` light) + `backdrop-filter: blur(40px) saturate(1.8)` | `NSVisualEffectView`, material `.popover` (or `.hudWindow`), blending `.behindWindow`, state `.active` |
| `.vibrancy-menubar` (menu bar, dock, hint bar, sticky headers) | `--menubar-bg` (`rgba(11,11,15,0.35)` dark / `rgba(245,245,247,0.45)` light) + `blur(20px) saturate(1.6)` | material `.menu` / `.headerView` |

### 2.6 Effects

- **Recording glow**: `radial-gradient(closest-side, rgba(48,209,88,0.25), transparent)`, breathing scale 1→1.06, opacity 0.9→1, 2s ease-in-out infinite, behind waveform while recording.
- **Shimmer text** (processing): `linear-gradient(100deg, text-1 30%, accent-purple 50%, text-1 70%)`, background-size 200%, clip to text, sweep keyframe 200%→−200%, 1.2s linear infinite. Transcribing variant uses `accent-teal` instead of purple.
- **Waveform gradients**: recording `#30D158→#64D2FF` (left→right); playback `#0A84FF→#BF5AF2`.
- **Recording dot pulse**: opacity 1→0.3, 1s ease-in-out infinite (`zw-pulse-dot`); context-dot halo uses the same keyframe at 2s.
- **Caret blink**: opacity 1 for 0–45%, 0 for 50–95% of 1s (`zw-caret`); textarea caret color = accent.

---

## 3. Component anatomy

### 3.1 RecordingPopover (hero; `src/components/RecordingPopover.tsx`)

Two sizes, animated between with `layout` springs on all children:

| Size | W×H | Bars | Extras |
|---|---|---|---|
| Main | 420×240, radius 14, padding 12 | 48 | teleprompter, timer, captions |
| Mini | 220×64 | 28 | teleprompter/timer hidden; stop button hidden until hover (slides x 24→0, SPRING_MICRO) |

Position: top-center of stage (`top: 40px`, `left: 50% − width/2`). **Draggable** anywhere on stage: pointer drag, momentum off, constrained to stage bounds, scale 1.01 while dragging, grab/grabbing cursors. Double-click toggles Main/Mini (same as the chevron toggle button top-right). Watermark logo: 64px, 3% opacity, top-center.

Internal layout (top→bottom):
1. **Top row** (gap 8): context dot (12px hit area, 8px dot) → ModePill (compact) → spacer → recording timer + red dot (Main, while recording only) → resize toggle (13px chevrons icon, 20px button).
2. **Waveform area** (flex-1, py 8): canvas + recording glow overlay.
3. **Teleprompter** (Main only, min-height 26): single-line, horizontal auto-scroll to end on each new word; 17px/500; active word colored accent-blue then settles to text-1; shimmer classes applied during transcribing/processing. Sub-caption row (11px) cycles phase captions.
4. **Bottom row**: controls per phase (below).

**States** (engine phases, see §4):

| Phase | Visible UI |
|---|---|
| `idle` | Teleprompter hint "Tap the mic or hold Space to dictate." (Write-for-me: "Pick a topic, then speak the details." + topic chips row: 11px pills, hairline, surface-2, each starts recording). Bottom: "Dismiss" (ghost, left) + "Start dictation" (accent-red pill, Mic 13px, 12px/600, right; while hold-to-talk held: accent-blue ring-2 + scale 1.15). |
| `recording` | Waveform live; glow breathes; timer `m:ss.d` (mono 11px text-2) + 8px red dot pulsing 1s; mode pill; context dot lights 600ms in. Bottom: Cancel ✕ (28×28 ghost, radius 6, hover surface-3, hover scale 1.08), center label "≋ {mode}" (11px text-3), Stop ■ (28×28 accent-red, radius 6, hover scale 1.08). Hold-to-talk adds caption "Push to talk — release to paste" (11px text-2). |
| `transcribing` | Teleprompter teal shimmer sweep; caption "Transcribing…" (11px text-2); Cancel/Stop disabled (40% opacity). |
| `processing` | Purple shimmer; caption "Processing with {Mode} mode" (11px/500 accent-purple); context dot pulses. |
| `pasted` | Green check + "Pasted to Notes" (11px/500 accent-green); popover auto-closes 700ms later (exit: scale→0.9, y→−4, fade). |
| `cancelled` | Shake `x: [0,−8,8,−4,0]` over 0.4s, then popover closes at 420ms; waveform settle aborted. |

**Context dot** (left of mode pill): default 8px circle surface-3. When captured: 8px accent-purple dot + 24px `/super-mode-glow.png` halo pulsing (2s). Tooltip: "Context captured: Notes selection + clipboard".

**Mode change while open**: pill re-mounts with scale 1.15→1 pulse (SPRING_MICRO).

**Summon animation**: opacity 0→1, scale 0.85→1, y −8→0, spring 400/28. **Swift:** `NSPanel` (`.nonactivatingPanel`, `.borderless` style mask, `isFloatingPanel = true`, `level = .floating`), `NSVisualEffectView` background, corner radius 14, shadow per §2.5, draggable via background drag; animate with `NSAnimationContext` spring or SwiftUI `.spring`.

### 3.2 Waveform (`src/components/Waveform.tsx`)

Canvas 2D, ~60fps, DPR-capped at 2. Parameters:

- Bars: 48 (Main) / 28 (Mini); bar width 4px, gap 6px, centered as a group; corner radius min(4, w/2, h/2); heights symmetric about vertical center; min height 2px.
- Amplitude: `sampleAmplitude(t + i·0.17, active)` — layered sines (0.28·sin(5.3t)·sin(1.7t) + 0.16·sin(11.1t+1.3) + 0.1·sin(23.7t+0.7)) + uniform noise ±0.11, |·| then scaled: speaking `min(1, 0.25 + level·0.9)`, idle `min(1, level·0.12)`.
- Smoothing: per-bar exponential lerp `h += (target − h)·0.2` per frame (≈ time constant ~3 frames at 60fps).
- Settle (on stop): bars collapse to 2px, staggered center-out over 300ms (`delay_i = |i − mid|/mid · 300ms`).
- Reduced motion: static bars `4 + |sin(i·0.55)| · height·0.5`, no lerp animation.
- **Swift:** `Canvas` view or `CAShapeLayer` per bar driven by `CADisplayLink`; replace `sampleAmplitude` with real RMS/FFT from `AVAudioEngine` tap.

### 3.3 MenuBar (`src/components/Navbar.tsx`)

Fixed top, height 28px, `.vibrancy-menubar`, bottom hairline, horizontal padding 12, z above all stage content. Left→right: logo (16px, radius 4) + "zWhisper" (13px/600) — links home; decorative menus File/Edit/View/Window/Help (13px, hover white/10 bg, radius 4); separator (14px tall 1px); route links Modes/History/Models/Vocabulary/Settings (13px; active = accent-blue, else text-2) `(delta from design: design had no route links in the menu bar; implementation adds them for prototype navigation)`. Right→left: compact ModePill + ModeSwitcher (anchored below-right, top 32); Wifi 14px, BatteryFull 16px (decorative, text-1/80); live clock mono 12px tabular, format `"Wed Jan 15  9:41 AM"` (two spaces), 1s tick; zWhisper record toggle (AudioLines 14px, 24×20 hit area, active = accent-blue on accent-blue/25 bg; hover scale 1.05, tap 0.92). Clicking the record toggle navigates home if needed and toggles the popover. Mount: slides y −28→0, spring 400/30, delay 100ms.

**Swift:** `NSStatusItem` in the real app (menu extra); the in-window menu strip is prototype-only.

### 3.4 ModePill / ModeSwitcher (`src/components/ModeSwitcher.tsx`)

- **ModePill**: full-round, hairline, surface-2/80 bg (hover surface-3/80). Regular: px 10 py 4, icon 13px (mode color), label 12px/600 uppercase tracking 0.02em, chevron 12px text-3. Compact: px 8 py 2, icon 11px, label 10px, chevron 10px. Hover scale 1.02, tap 0.97 (spring 500/35).
- **ModeSwitcher popover**: 224px wide (w-56), radius 14, vibrancy + popover shadow, padding 6. Enter: opacity/scale 0.92→1, y −6→0, spring 400/30; exit scale 0.95 y −4. Rows: 13px/500 label, icon 14px, kbd shortcut mono 11px text-3 right; active row bg accent-blue/15 with blue Check (13px, stroke 3) that scales 0.5→1 (spring 500/35); hover surface-3/60. Dismiss on outside pointer-down. **Swift:** `NSPopover` or SwiftUI `.popover` with `List`-style rows; `NSMenu`-like behavior.

### 3.5 SidebarNav (`src/components/SidebarNav.tsx`)

Width **176px** (w-44) `(delta from design: 220px)`, surface-2/50 bg, right hairline, padding 8. Header: logo 20px (radius 5) + "zWhisper" 13px/600. Rows: icon 15px (stroke 2) + label 13px, radius 6, px 8 py 6, gap 2 vertical. Active row: bg `#0A84FF26`, medium weight, icon accent-blue; inactive: text-2, icon text-3, hover surface-3/60 + text-1. Items: Dictation, Modes, History, Models, Vocabulary, Settings. **Swift:** `NavigationSplitView` sidebar or `List` with `.sidebar` style; SF Symbols (see §8 icon map).

### 3.6 Window chrome / TrafficLights (`src/components/TrafficLights.tsx`, `WindowStub.tsx`)

- Title bar: 28px, bottom hairline, px 12. Traffic lights left: three 12px circles, gap 8, colors `#FF5F57 / #FEBC2E / #28C840`, each ring-1 black/20, tap scale 0.85. Red navigates home (real app: closes window). Title centered, 13px/600, tracking −0.01em, text-2; 52px right spacer balances the lights.
- Windows: radius 12, `.vibrancy`, `--window-shadow`, hairline. Enter/exit: opacity + y ±8, 250ms (no spring — plain tween) `(delta from design: design specified AnimatePresence crossfade + 8px drift 250ms; matches, but is duration-based not spring)`.

### 3.7 Toasts (three variants, all vibrancy + popover shadow + hairline)

| Variant | Geometry | Motion | Auto-dismiss |
|---|---|---|---|
| Home result toast | 288px (w-72), radius 14, padding 12, bottom-right (bottom 80px, right 24) | enter y 12→0 scale 0.96→1, spring 400/30 | 6s |
| Modes save toast | top-right (top 40, right 16), radius 10, px 12 py 8, green check + 12px/500 text | slides x 24→0, spring 400/30 | 3s |
| Inline pill toast (History, Settings) | full-round pill, px 12–14 py 6, bottom-center; Settings: surface-3 bg | y 12→0 scale 0.96→1, spring 400/30 (Settings: 500/35) | 2.2s (History), 3s (Settings/Vocabulary) |

Undo-paste confirmation mutates the Home toast text to "Clipboard restored" for 1.8s.

### 3.8 ShortcutKey (`src/components/ShortcutKey.tsx`)

kbd chip: radius 6, hairline, surface-2 bg, px 6 py 2, JetBrains Mono 11px/500 text-2, bottom highlight shadow `0 1px 0 rgba(255,255,255,0.06)`. **Swift:** bordered `NSButton`-less label; `RoundedRectangle` + `Color(nsColor: .secondaryLabelColor)` text.

### 3.9 Dock / Footer (`src/components/Footer.tsx`)

Decorative. 56px-tall frosted bar (`.vibrancy-menubar`, radius 16, hairline, px 12), centered bottom with 8px bottom margin. Six 36×36 generic app tiles (radius 10, hairline, diagonal gradient color 33%→13% alpha in palette order orange/teal/green/red/purple/gray), 1px×32 separator, zWhisper logo 36×36 (radius 10). On dictation complete: bounce y 0→−18→0, 0.5s easeOut.

### 3.10 Shared controls (Settings `controls.tsx`)

- **Switch**: 38×22 track, full-round; on = accent-green, off = surface-3, 150ms color fade; thumb 18px white, shadow `0 1px 3px rgba(0,0,0,0.4)`, x 2↔18 spring 500/35; tap scale 0.96. **Swift:** `Toggle(.switch)`.
- **SegmentedControl**: outer radius 7–8, surface-2 (Settings variant: black/25) bg, padding 2; segments 12px/500, radius 5–6, px 12; sliding indicator = surface-3 + hairline + `0 1px 3px rgba(0,0,0,0.35)` shadow, `layoutId` spring 500/35. **Swift:** `Picker(.segmented)`.
- **Dropdown**: 6px radius button, surface-3/70, 12px/500, chevron rotates 180° on open (150ms); menu 8px radius surface-3, max-h 224, rows with leading Check (12px, accent, invisible when unselected); enter scale 0.98 + y −4, 150ms. **Swift:** `Menu` / `NSPopUpButton`.
- **Slider**: track 4px full-round surface-3, fill accent-blue; thumb 16px white, shadow `0 1px 4px rgba(0,0,0,0.45)`, scale 1.15 while dragging; value bubble (mono 10px, surface-3, radius 5) appears above thumb, enter 120ms. Width 176 (w-44) in Settings rows. **Swift:** `Slider` with custom thumb or `NSSlider`.
- **Grouped list**: `Group` = surface-2 card, radius 10, hairline, rows separated by hairlines; row min-height 48, px 14 py 8; group title 11px/600 uppercase tracking 0.06em text-3.

---

## 4. Interaction spec — the dictation loop

Engine phases: `idle → recording → transcribing → processing → pasted → (idle)`, plus `cancelled` from any of recording/transcribing/processing. State machine (`src/lib/mockEngine.ts`, `src/pages/Home.tsx`):

```
idle
  ├─ start(mode)              → recording          [summon popover if closed]
recording
  ├─ stop()  (release Space / tap Stop / ⌥⇧Space)  → transcribing
  ├─ mode switch ⌘1–7        → recording (restart script bank with new mode)
  ├─ cancel() (Esc / ✕)      → cancelled
transcribing  ── 900ms ──→ processing
processing    ── 700ms ──→ pasted (fires onPaste + onComplete)
pasted        ── 700ms ──→ popover closes, dock bounces; toast shows 6s
cancelled     ── shake 400ms ──→ popover closes at 420ms, engine reset → idle
```

### 4.1 Triggers (all equivalent summons)

| Trigger | Behavior |
|---|---|
| Menu bar zWhisper icon | Toggles popover open/closed (idle state) |
| `⌥⇧Space` | Toggle: if idle → start recording; if recording → stop+process. Ignored when focus is in a text field. |
| Hold `Space` (push-to-talk) | keydown (not repeat, no modifiers, focus not editable) → summon + record immediately; keyup → stop+process. `holdActive` drives the pressed-ring mic button + caption. |
| Hint-bar mic button | pointerdown/up = same as hold Space. |
| Popover "Start dictation" button | Toggle start. |
| Auto-demo | After 800ms idle on Home load: popover summons + records; auto-stops at 6s. Skipped permanently on first pointerdown/keydown. |

### 4.2 While recording

- Words stream to teleprompter at 120–180ms/word (uniform random per word); active word accent-blue.
- Context dot lights at exactly 600ms.
- Timer `m:ss.d` ticks at 50ms (display 0.1s resolution).
- `⌘1…⌘7` (also Ctrl+digit accepted) switches mode **live**: mode pill pulses, script bank swaps (recording restarts with new mode's script). Same handler via ModeSwitcher selection.
- `Esc` while popover open → cancel (shake, no paste, Notes unchanged). Esc also cancels during transcribing/processing (popover Cancel ✕ is disabled during those phases, but Esc still works).

### 4.3 Stop → paste sequence (exact timings)

| t (after stop) | Event |
|---|---|
| 0ms | Waveform settle (bars →2px, center-out 300ms stagger); full script committed to teleprompter; phase `transcribing`; teal shimmer. |
| 900ms | Phase `processing`; purple shimmer; caption "Processing with {Mode} mode". |
| 1600ms | Phase `pasted`; green "Pasted to Notes" check; **auto-paste begins**: result text types into Notes at caret, 1 char per 8ms (125 chars/s), preserving prior content. |
| 1600+700ms | Popover closes (scale→0.9 fade); Dock icon bounces (0.5s). |
| same tick as paste | Result toast (bottom-right): mode icon, "Saved to History", `{words} words · {m:ss}` mono meta, buttons **Reprocess** / **Undo paste**; auto-dismiss 6s. |

- **Caret position**: paste inserts at the current textarea caret (`selectionStart`), not necessarily end-of-document. A `pasteRange = {start, len}` is tracked during type-out.
- **Undo paste**: removes exactly `pasteRange`; toast switches to "Clipboard restored" (1.8s). `(Design intent: the real app snapshots the clipboard before paste and restores it after; prototype simulates with a placeholder note.)`
- **Reprocess** (from toast): removes the pasted range, advances to the next mode in cycle order, re-types that mode's processed text at the same position after 30ms.
- **Cancel (Esc)**: shake keyframes `x: [0, −8, 8, −4, 0]` over 0.4s; close at 420ms; engine resets to idle.

---

## 5. Motion spec

### 5.1 Spring table (Framer Motion → SwiftUI)

Conversion for mass=1 springs: `response ≈ 2π/√stiffness`, `dampingFraction ≈ damping / (2·√stiffness)`.

| Token | Stiffness / Damping | SwiftUI equivalent | Used for |
|---|---|---|---|
| SPRING_POP | 400 / 28 | `.spring(response: 0.31, dampingFraction: 0.70)` | popover summon/dismiss |
| SPRING_DEFAULT | 400 / 30 | `.spring(response: 0.31, dampingFraction: 0.75)` | toasts, cards, menus, window-ish entrances, list rows, detail crossfades |
| SPRING_SHEET | 380 / 32 | `.spring(response: 0.32, dampingFraction: 0.82)` | mode editor sheet |
| SPRING_MICRO | 500 / 35 | `.spring(response: 0.28, dampingFraction: 0.78)` | all button hover/tap scales, switch thumb, segmented indicators, pill pulse, check scale-ins |
| PLAYHEAD | 600 / 40 | `.spring(response: 0.26, dampingFraction: 0.82)` | History seek playhead (`useSpring`) |

### 5.2 Standard gestures

- Press: scale 0.97 (small icon buttons 0.85–0.96; menubar record icon 0.92; play button 0.94). Hover (primary): 1.02; destructive/ghost buttons: 1.08 (popover controls) or bg fade only.
- Popover/menu enter: opacity 0→1, scale 0.92→1, y −6→0 (exit 0.95/−4), SPRING_DEFAULT. FilterBar dropdown variant: scale 0.98, y −4, 150ms tween.
- Window enter/exit: opacity + y ±8, 250ms tween (all management windows; Settings/Vocabulary/Models omit exit).
- Notes window entrance: scale 0.96→1 + fade, delay 250ms.
- Settings pane switch: crossfade + y ±6, 200ms, `mode="wait"`.

### 5.3 Staggers & per-screen motion

| Effect | Values |
|---|---|
| List rows (History) | y 12→0 + fade, stagger 0.04s, spring 400/30 |
| Grid cards (Modes) | y 16→0 + fade, stagger 0.05s, spring 400/30; new card: scale 0.8→1 |
| Rows (Models) | y 12→0, stagger 0.035s; banner slides y −12→0 |
| Sections (Vocabulary) | y 16→0, stagger 0.08s; chips cascade 0.02s (initial scale 0.8) |
| Rows (Usage tab) | stagger 0.07s, y 16→0 spring 400/30 |
| Shortcut chips (recorded) | scale 0.7→1, stagger 0.06s, spring 500/35 |
| Sidebar items | (design: x −12→0, 0.04 stagger — subtle; implementation relies on window-level entrance) |
| Waveform settle | 300ms center-out stagger (§3.2) |
| Transcript morph (reprocess) | out: fade + y −8, 250ms; in: paragraphs y 8→0, 300ms easeOut, stagger 0.03s (~900ms total) |
| Row delete/collapse | height→0 + fade, 250ms |
| Download bar expand | height 0→auto, 250ms, cubic-bezier(0.16,1,0.3,1) |

### 5.4 Ambient loops

| Loop | Values |
|---|---|
| Wallpaper drift | GSAP scale 1→1.04, y 0→−12, 30s half-cycle (60s full yoyo), sine.inOut `(design said 60s yoyo — implementation uses duration 30 + yoyo, equivalent)` |
| Recording glow | scale 1↔1.06, opacity 0.9↔1, 2s ease-in-out |
| Recording dot | opacity 1↔0.3, 1s |
| Context halo | pulse 2s |
| Shimmer | 1.2s linear sweep |
| Indeterminate progress | 2px bar, x −100%→300% of a 1/3-width thumb, 1.1s easeInOut infinite |

### 5.5 Reduced motion (`prefers-reduced-motion`)

- Wallpaper drift disabled entirely; waveform renders static bar heights (§3.2); shimmer sweeps slowed to 3s; transcript morph falls back to plain opacity fades; (design intent: springs become 150ms fades — partially implemented). **Swift:** honor `NSWorkspace.accessibilityDisplayShouldReduceMotion` / `@Environment(\.accessibilityReduceMotion)`.

---

## 6. Screen-by-screen spec

Common shell (all routes): `Layout` renders full-viewport stage (`bg-stage` + wallpaper image inset −4% with GSAP drift), fixed 28px MenuBar, content area below it (`pt-7`). Management windows are centered on stage. Window sizes are implementation values:

| Route | Window (W×H) | Notes |
|---|---|---|
| `/` Home | full stage | desktop + Notes + popover |
| `/modes` | 960×640 | matches design |
| `/history` | 1000×660 | matches design |
| `/models` | 1000×660, stage padding 16 | matches design |
| `/vocabulary` | 960×640, stage padding 16 | matches design |
| `/settings` | 920×640 | matches design |

(`WindowStub` exists at 860×560 but is unused by the routed pages — ignore it; delta vs design's per-page sizes resolved in favor of the pages.)

### 6.1 Home / Dictation (`pages/Home.tsx`)

- **Notes demo window**: 640×480, absolute at left 8%, top 10%, radius 12, vibrancy + window shadow, focus ring `ring-1 accent-blue/30`. Title bar "Meeting follow-up — Notes". Body: editable textarea, 13px, leading relaxed, accent caret, seeded with a 2-paragraph "Project sync — Tuesday" note. Status bar (24px, hairline top): "TextEdit.app — demo target" + live word count (mono). Red traffic light blurs the textarea.
- **Recording popover**: see §3.1; initial position top-center.
- **Hint bar**: full-round frosted pill, bottom 80px, centered; contents: mic button (20px red circle, press-and-hold = push-to-talk) + `Hold Space` Push to talk · `⌥⇧ Space` Toggle recording · `Esc` Cancel (12px text-2 with ShortcutKey chips, separated by 12px hairlines). Entrance: y 16→0 + fade, delay 500ms. Auto-dismisses after first successful dictation; recallable via 32px round "?" button (bottom-right, right 24).
- **Dock**: §3.9, fixed bottom.
- **Entrance choreography**: stage fades (implicit) → MenuBar slides (delay 100ms) → Notes window (delay 250ms) → hint bar (delay 500ms) → auto-demo dictation at 800ms idle.

### 6.2 Modes (`pages/Modes.tsx` + `components/modes/*`)

- Window 960×640: chrome, SidebarNav, content. Header: "Modes" 20px/700 + subtitle, right-aligned accent **New Mode** button (radius 6, px 12 py 6, 13px/500).
- Toolbar: SegmentedControl `All / Built-in / Custom` + search field (28px h, 192px w, radius 6, surface-2, magnifier 13px, focus ring accent-blue/60).
- **Grid**: 2 cols, gap 16, cards 96px tall (h-24), radius 12, surface-2, hairline, padding 12. Card: 36px tinted squircle (radius 10, mode color @ 15% bg, glyph 17px in mode color) · name 13px/600 + badges (10px pills: "Built-in" surface-3/text-2, "Custom" accent-blue/15, "Super" accent-purple/15 when readSelected/readClipboard) · description 12px text-2 truncated · ShortcutKey top-right. Active mode card: 1px accent border + outer `0 0 0 1px accent` ring + 20px blue check badge (top-right, overlapping −6px, scale 0.5→1 spring). Hover: lift y −2 + shadow, 150ms; ⋯ menu fades in (opacity 0→100), menu 144px wide radius 10, items Edit/Duplicate/Delete (Delete red, hidden for built-ins).
- Library seed: 6 built-ins (Voice Transcription ⌘5, Email ⌘1, Message ⌘2, Note ⌘3, Meeting ⌘4, Write for me ⌘6) + 2 custom ("Slack Update" ⌘7 green Hash, "Support Reply" ⌘8 purple LifeBuoy, both context flags on for Support Reply) `(delta from design: library's "Voice Transcription" maps to the store's "Voice Note" mode; the store additionally has a standalone "Super Mode" ⌘7 in the popover switcher that is not a library card)`.
- **Editor sheet**: slides from under title bar (top 28), 560px wide, radius 12, max-height window−40, scrim black/30 (fade 200ms), spring 380/32. Header 40px: 24px tinted icon tile + "New Mode"/"Edit {name}" + shortcut kbd. Body: left form (Name input + 6 color swatches — selected scales 1.15 with ring; 8-glyph icon picker 32px tiles; AI Instructions textarea 120px with placeholder text; "Include context" section — purple uppercase label + "Super" pill — with two mini-switches 30×18/thumb 14; auto-activation rules: `When [app chip: Mail/Slack/Notes/Safari] [domain field for Safari, 96px] is frontmost` rows + "Add rule" accent link) and right **Live preview** pane 220px wide (border-l, surface-2/40): mini waveform icon + "Sample" button wired to the mock engine; raw box and processed box (min-height 64, 12px), purple caret blink during streaming. Footer: Cancel ghost / Save accent (disabled until name non-empty). Esc cancels. Save → toast "… saved · ⌘N assigned", card pops into grid scale 0.8→1.
- **Delete**: centered 280px alert (scale 0.95→1 spring 400/30) over black/30 scrim; row collapses height→0 over 250ms.
- **ModeCycleStrip** (bottom frosted strip, py 10): "Try it: hold ⌥⇧ and tap K to cycle modes" + simulated hold button + K button + horizontally scrollable pill carousel; highlight = accent-blue/25 pill + accent ring traveling via `layoutId` spring 500/35; cycling sets the global mode.

### 6.3 History (`pages/History.tsx` + `components/history/*`)

- Window 1000×660. Split: **list pane 340px** (right hairline) + detail pane.
- List header (padding 12, gap 8): search field (28px, "Search transcripts", focus ring accent/50, clear ✕) + filter button (28×28; active: accent/20 tint + count badge 14px mono 9px). Filter popover 240px wide, radius 14: mode chips multi-select (11px pills) + date segmented row (Today / This week / All); chips AND-combined with search.
- Rows 72px under sticky frosted date headers (11px/600 uppercase text-3, "Today"/"Yesterday"/"Mon Jan 13"). Row: 28px mode squircle (radius 8) · title 13px/500 truncated (~40 chars) · meta 11px text-2 `9:41 AM · 0:38 · 142 words` · right: uppercase mode chip (10px) replaced on hover by 24×24 quick actions (play / reprocess / copy). Selected: bg `#0A84FF26`; hover surface-3/70. Playing row: 2px accent progress underline. "Processing…" rows: accent meta text + indeterminate 2px shimmer bar; the two seeded processing rows resolve at 3.2s and 4.4s after mount.
- 12 pre-seeded entries across 3 days, all modes; seeded durations drive word timing.
- **Detail pane**: header (px 16 py 12): 28px mode squircle + compact ModePill + full timestamp (mono 11px text-3), duration mono 11px, separator, Copy / Export (decorative → toast) / Delete (red ghost).
- **WaveformStrip**: 80px tall (h-20), surface-2/40 rounded 8 hairline; 80 pre-computed bars (deterministic seeded random-walk), gap 3px, min bar 2px, blue→purple gradient; played bars alpha 1, unplayed 0.3; click-to-seek; playhead = 1px white/90 line + 8px handle dot, spring 600/40.
- **Transport**: skip-back/forward 5s (32px round ghost buttons, mono "5" caption 8px), play/pause 36px accent circle (shadow-popover), time `0:12.4 / 0:38` mono, speed segmented 1×/1.5×/2× (mono 11px). Keyboard: Space play/pause, ←/→ seek 5s (disabled when typing).
- **Transcript**: 15px/500 relaxed paragraphs, px 20 py 16, Lenis-smoothed scroll (duration 0.8). Every word is a button: hover pill surface-3, active word accent-blue/20 bg + accent text (120ms color transition), hover tooltip timestamp `0:12.4` (mono 11px chip, −24px above). Click word → seek to its timestamp. Auto-scroll keeps active word centered (offset half viewport − 24px, 0.5s scroll). Word timestamps: deterministic jittered spread over 92% of duration.
- **Reprocess bar** (bottom, surface-2/40 + blur): optional purple banner "Reprocessed with {Mode} — Undo" (height 0→auto 250ms, bg accent-purple/10); row: "Reprocess with…" + scrollable mode chips (current mode disabled, picked chip accent/20 + check) + Apply (accent when armed). Pipeline: start+stop the shared engine → 900+700ms shimmer on transcript → text morph (§5.3) → banner. Undo replays the morph with the previous version (per-entry undo stack).
- Delete → toast "Recording deleted" (2.2s), detail → "Select a recording" placeholder (48px surface-2 mic tile, text-3).

### 6.4 Models (`pages/Models.tsx` + `components/models/*`)

- Window 1000×660. Header (px 20): title + 12px subtitle.
- **ActiveBanner**: vibrancy radius-10 card; 36px icon tile (green/15 local, orange/15 cloud); name chip (12px/600 surface-2 pill) + "Active" green pill (10px) + engine label; meta line 11px text-3; right: "Change" ghost button (scrolls list to top). Mount: y −12→0 spring; model swap crossfades inner content 180ms.
- **FilterBar**: type segmented (`All/Local/Cloud`), Provider dropdown (ghost button + 10px-radius menu, min-w 128), "Favorites only" star toggle (on: `#FFD60A` at 10% bg/30% border), sort dropdown (Speed/Accuracy/Size, default Speed).
- **Rows** (8px gaps, stagger 0.035, Lenis scroll lerp 0.12): radius-10 surface-2 cards, padding ~12; 36px squircle chip (local green / cloud orange tint); name 13px/600 + badges (10px pills; "Fastest cloud" purple, "BYOK" orange) + price hint; description 12px text-2; two **DotMeter** groups (label 10px uppercase text-3 + 5 dots; filled accent, empty surface-3; hover tooltip) in a 118px right column; then state control:
  - `none` → ghost **Download** button.
  - `queued` → "Queued" 12px text-3 (max 2 concurrent downloads).
  - `downloading` → row expands (height auto, 250ms, ease 0.16/1/0.3/1): accent progress bar + mono line `{done} / {total} — {MB/s} MB/s` + red Cancel. Tick 150ms, ~6s total, jitter ×(0.5–1.5), MB/s random 90–160. Cancel → "cancelling" state collapses after 350ms.
  - `downloaded` → green check (scale 0.5→1) + "Downloaded"/"Ready" green text; hover reveals trash (delete download) and **Set Active** accent button.
  - Cloud rows: gear opens ApiKeyPopover (masked `sk-…••••` mono input, Save → toast "API key saved locally").
- **StarButton**: ☆→★, tap scale 0.85, star pop scale 1.3→1 spring; color `#FFD60A`.
- Footer strip (frosted, hairline top): privacy caption 11px + "Compare models" accent link (decorative).

### 6.5 Vocabulary (`pages/Vocabulary.tsx` + `components/vocabulary/*`)

- Window 960×640, single scrolling column (px 20 py 16, gap 20), sections stagger 0.08.
- **Custom Words**: header + input "Add a word…" + accent Add (Enter submits). Chip field: 6px-radius pills, 13px/500, hairline; hover × (14px circle, red tint on hover); hover tooltip "Used N× · last: {when}" (surface-3 chip, −28px above). Add: chip pops scale 0.6→1 with accent-blue/35 bg flash fading to surface-2 (spring 500/35); duplicate: input shakes `x [0,−6,6,−6,6,0]` 300ms + red ring; remove: scale→0.6 fade + sibling reflow (`layout`). Seed: 14 words (zWhisper, SuperWhisper, Kowalski, Aysima, Qwen, Llamafile, Terraform, GraphQL, Nguyen, XGBoost, PostgreSQL, RxJS, Chernoff, Miroverse).
- **Text Replacements**: table grid `1fr 1fr 36px`; header row surface-2/60; inline-editable cells (click → input, commit on Enter/blur with 300ms accent bg flash); hover trash (red tint). Seeds: "my email"→alex@zwhisper.app, "new line"→line break, "smiley face"→😄, "calendar link"→cal.com/alex-zh. Add row slides in (height 0→auto, 250ms, ease 0.16/1/0.3/1) in edit mode.
- **Hints demo card**: purple icon tile 32px; mini teleprompter (stage/60 bg, radius 8) streams "Hey Aysima, can you send the Terraform plan to Nguyen before we push the GraphQL schema update?" at 140ms/word; vocab words render as underlined accent chips (slide y 6→0 on arrival); clicking one pops a card "{word} — from your vocabulary · Used N×" (scale 0.9→1 spring 500/35); Replay loops.
- Toast: "Vocabulary updated — applies to your next dictation", bottom-center, 3s. `(Noted intent, not yet wired: vocabulary should feed the Home teleprompter — see vocabData.ts header comment; flag as prototype gap, implement in the real pipeline.)`

### 6.6 Settings (`pages/Settings.tsx` + `components/settings/*`)

- Window 920×640. Below chrome: **toolbar tabs** — centered strip (border-b), four 64px-wide items (icon 19px stroke 1.8 over 11px/500 label), active = accent icon/label + sliding surface-3/70 rounded-8 indicator (`layoutId` spring 500/35), tap scale 0.96; tab click plays synthesized click sound. Panes crossfade + y ±6, 200ms (`mode="wait"`), padding px 24 py 20. All settings persist to `localStorage` (`zw-settings:` prefix).
- **General**: grouped lists — Startup (Launch at login on; Show in Dock off; Start recording when menu bar icon is clicked on — wired: toggles whether the menubar click auto-starts recording `(implementation note: setting stored; Home menubar behavior flag lives in this store)`; Always close window after dictation on) · Appearance (Theme segmented Light/Dark/System — Dark default; switching applies a 300ms palette crossfade to the whole shell via injected CSS transition; Sound effects style segmented Subtle/Classic/None — Subtle plays 1240Hz/0.035-gain 90ms sine blip, Classic 760Hz/0.09, None silent) · Paste (Auto-paste on; Restore clipboard on, with InfoTip) · Language (dropdown "Auto-detect", 100+ languages caption, translate-to-English switch off). Footer: logo 32px + "zWhisper Prototype v0.1 — transcription is simulated" text-3.
- **Sound**: Input device dropdown (decorative) + live **input meter** — 24 segments (3px gap, 14px tall, radius 2), green→yellow→red thresholds, driven by layered sine+noise, 75ms color transitions, spikes during a 3s "Test microphone" run (→ toast "Microphone looks good"); Dynamic normalization switch (on); Silence removal switch (on) + Aggressiveness slider 0–100 default 40; Active duration segmented 15s/30s/60s/∞ (default 30s).
- **Shortcuts**: recorder rows: Toggle recording `⌥⇧ Space`, Push to talk `Space`, Cancel dictation `Esc`, Change mode (cycle) `⌥⇧ K`, plus decorative `⌘1…⌘9` chip row. Clicking a field arms it ("Press shortcut…", pulsing accent ring 1.1s); captured combos animate chips in (scale 0.7→1, 0.06 stagger); conflicts shake x ±6 300ms + caption "Already used by …". Caption: "In the web prototype, some shortcuts are simulated with on-screen buttons."
- **Usage**: 3 StatCards (surface-2, radius 16): Words dictated **12,483** (count-up from 0, 1.2s ease-out, 32px/700 tabular) + 7-day sparkline (120×32 viewBox, accent stroke 1.5px, stroke-draw 1s); Dictation speed **148 wpm** ("vs 41 wpm typing"); Time saved **9.2 hrs**. Typing test card: sentence "The quick brown fox jumps over the lazy dog.", live mono wpm meter, result compare bars (yours vs 148, width tween 0.8s cubic-bezier 0.16/1/0.3/1) + verdict "Dictation is N× faster". Share card 320×180: dark gradient, logo, avatar (`avatar-user.jpg`), "9.2 hours saved with zWhisper this month", buttons Download PNG (decorative toast) / Copy text.

---

## 7. Mock engine behavior (prototype-only — treat as the UX timing budget)

`src/lib/mockEngine.ts` constants:

| Constant | Value | Real-pipeline budget guidance |
|---|---|---|
| `WORD_MIN/MAX_MS` | 120–180ms/word, uniform jitter | streaming partial-transcript cadence target |
| `CONTEXT_MS` | 600ms after record start | deadline for context capture (selection + clipboard read) |
| `TRANSCRIBE_MS` | 900ms | budget from audio end → final transcript (WhisperKit on-device should beat this for ≤60s dictations) |
| `PROCESS_MS` | 700ms | budget for mode LLM rewrite (streaming start should feel ≤700ms) |
| Typewriter paste | 8ms/char (125 chars/s) | visual paste cadence; real app may paste atomically, but keep undo-range tracking |
| Energy ticker | 50ms interval; amplitude = layered sines + noise (§3.2) | replace with `AVAudioEngine` tap RMS |
| History reprocess | reuses 900+700ms via start+stop | same budget applies server/on-device side |

**Script banks** (raw → processed pairs live in `src/lib/modes.ts`; library copies in `components/modes/data.ts`):
- Email ⌘1 `#0A84FF`: mockups/frames-12–15 review → formatted email with greeting, paragraphs, "Best, Alex".
- Message ⌘2 `#30D158`: running-late text → casual, "~10 min", ☕.
- Note ⌘3 `#FF9F0A`: pricing-page reminder → titled bullet checklist.
- Meeting ⌘4 `#BF5AF2`: sync action items → "Action Items — Sync" owner list.
- Voice Note ⌘5 `#64D2FF`: filler-heavy raw transcript, unprocessed (identity transform).
- Write for me ⌘6 `#FF453A`: topic-chips (Follow-up/Apology/Intro) → composed paragraph.
- Super Mode ⌘7 `#BF5AF2` (popover switcher only): summarize current note + next steps.
- Library-only samples: Slack Update ⌘7 (standup format), Support Reply ⌘8 (empathy + macro), new-mode generic sample.

Stop semantics: on stop the full script is considered spoken (teleprompter fills instantly). History word timestamps are synthesized deterministically (seeded PRNG, 92% of duration span, ±jitter).

---

## 8. Swift build notes

| Web concept | Swift/macOS API | Notes |
|---|---|---|
| Menu bar icon + popover toggle | `NSStatusItem` + `NSPopover` (or borderless `NSPanel`) | icon: `AudioLines` → SF Symbol `waveform` / `waveform.circle` |
| Recording popover | `NSPanel` (`.nonactivatingPanel`, `.borderless`, floating level) hosting SwiftUI via `NSHostingView`; background `NSVisualEffectView` (material `.popover`) | draggable by background; corner radius 14 via `contentView` mask; shadow per §2.5; two sizes 420×240 / 220×64 with animated frame change |
| Vibrancy surfaces | `NSVisualEffectView` (`.popover`, `.menu`, `.sidebar`, `.headerView`) | replaces `backdrop-filter` blur(40)/saturate(1.8) |
| Global hotkeys (⌥⇧Space toggle, Space hold PTT, Esc, ⌘1–7, ⌥⇧K cycle) | `KeyboardShortcuts` package (Sindre Sorhus) or Carbon `RegisterEventHotKey`; PTT needs key-down/key-up pair — use `NSEvent` global monitor for flags/keyUp | Space-hold PTT requires careful focus checks (don't intercept when a text field is first responder) |
| Waveform canvas | SwiftUI `Canvas` in a `TimelineView(.animation)`, or `CAShapeLayer` bars driven by `CADisplayLink` | 48/28 bars, 4px w / 6px gap, lerp 0.2; feed real amplitude from `AVAudioEngine` input tap (RMS) |
| Audio capture | `AVAudioEngine` / `AVCaptureSession`, 16kHz mono for Whisper | mic permission `NSMicrophoneUsageDescription` |
| Local transcription | **WhisperKit** (Core ML whisper variants: tiny≈Nano, base/small≈Fast, large-v3≈Pro/Ultra tiers) | download manager mirrors Models screen states |
| Cloud transcription (BYOK) | `URLSession` to OpenAI/Deepgram/Groq endpoints; keys in Keychain | matches BYOK popovers |
| Mode post-processing | Apple **Foundation Models** framework (on-device LLM) or BYOK cloud LLM | per-mode system prompt = "AI Instructions"; context capture = Accessibility read of selection + `NSPasteboard` |
| Auto-paste | Accessibility API (AX) to find focused element; set `NSPasteboard`, `CGEvent` ⌘V post, then restore clipboard (the "Restore clipboard" setting) | requires Accessibility permission; keep `pasteRange`-style undo via clipboard snapshot |
| Springs | `.spring(response:dampingFraction:)` per §5.1; AppKit: `NSAnimationContext` with `CAMediaTimingFunction` for tweens | all hover/press scales via `.scaleEffect` + spring |
| Menu-bar clock, traffic lights, title bars | native — delete the faux chrome; management windows = `NSWindow` with standard `.titled` style, `titlebarAppearsTransparent` for 28px look | window sizes §6 |
| Sidebar | `NavigationSplitView` + `List(.sidebar)` | SF Symbols map: Dictation `waveform`, Modes `square.stack.3d.up`, History `clock.arrow.circlepath`, Models `cpu`, Vocabulary `text.book.closed`, Settings `gearshape` |
| Mode icons (Lucide → SF Symbols) | Mail→`envelope`, MessageCircle→`bubble`, StickyNote→`note.text`, Users→`person.2`, Mic→`mic`, PenLine→`pencil.line`, Sparkles→`sparkles`, Hash→`number`, LifeBuoy→`lifebuoy`, Zap→`bolt` | tinted squircle = `Image(systemName:)` in `RoundedRectangle` with color @ 15% bg |
| Segmented controls / switches / sliders | `Picker(.segmented)`, `Toggle(.switch)`, `Slider` | custom slider thumb scale + value bubble per §3.10 if desired |
| Toasts | transient `NSPanel` or in-window overlay view with spring entrance + auto-dismiss timers per §3.7 | result toast = 6s; mutations 1.8–3s |
| Theme | semantic `NSColor` system colors; app-wide appearance override via `NSApp.appearance` for the Light/Dark/System setting | tokens in §2.1–2.2 map to system colors |
| Sounds | `NSSound` / `AVAudioPlayer` for Subtle/Classic click styles | prototype synthesizes 1240/760Hz sine blips |
| Settings persistence | `UserDefaults` (prototype uses `localStorage`) | keys mirror `zw-settings:*` list in §6.6 |
| History storage | SwiftData/Core Data: entry = {id, modeId, createdAt, duration, audioURL, text, undoStack} | word-level timestamps from WhisperKit segment/word timings replace the synthesized jitter |
| Usage stats | aggregate from History store; count-ups via `ContentTransition`/`Text` animations | share card via `ImageRenderer` |

---

*End of spec. Values not explicitly listed here should be read directly from the referenced source files — this document intentionally duplicates the source rather than paraphrasing it, so any conflict between this spec and `src/` should be resolved in favor of `src/` and this file updated.*

import { useCallback, useEffect } from "react";
import { Monitor, Moon, Sun } from "lucide-react";
import { useApp } from "@/lib/store";
import type { Theme } from "@/lib/store";
import {
  Dropdown,
  Group,
  InfoTip,
  Row,
  SegmentedControl,
  Switch,
} from "@/components/settings/controls";
import { usePersistentState } from "@/components/settings/settingsState";
import type { SoundStyle } from "@/components/settings/settingsState";

type ThemeChoice = "light" | "dark" | "system";

const LANGUAGES = [
  { value: "auto", label: "Auto-detect" },
  { value: "en", label: "English" },
  { value: "es", label: "Español" },
  { value: "de", label: "Deutsch" },
  { value: "fr", label: "Français" },
  { value: "ja", label: "日本語" },
  { value: "pt", label: "Português" },
];

/* Injected once: crossfades palette swaps over 300ms when the theme flips. */
function ensureThemeXfade() {
  if (document.getElementById("zw-theme-xfade")) return;
  const style = document.createElement("style");
  style.id = "zw-theme-xfade";
  style.textContent = `
    html.theme-xfade, html.theme-xfade * {
      transition-property: background-color, color, border-color, box-shadow, fill, stroke !important;
      transition-duration: 300ms !important;
      transition-timing-function: ease !important;
    }`;
  document.head.appendChild(style);
}

function resolveSystemTheme(): Theme {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export default function GeneralTab() {
  const { theme, setTheme } = useApp();

  const [themeChoice, setThemeChoice] = usePersistentState<ThemeChoice>(
    "theme-choice",
    theme === "light" ? "light" : "dark"
  );
  const [soundStyle, setSoundStyle] = usePersistentState<SoundStyle>("sound-style", "subtle");

  const [launchAtLogin, setLaunchAtLogin] = usePersistentState("launch-at-login", true);
  const [showInDock, setShowInDock] = usePersistentState("show-in-dock", false);
  const [menubarRecording, setMenubarRecording] = usePersistentState("menubar-click-recording", true);
  const [alwaysClose, setAlwaysClose] = usePersistentState("always-close", true);
  const [autoPaste, setAutoPaste] = usePersistentState("auto-paste", true);
  const [restoreClipboard, setRestoreClipboard] = usePersistentState("restore-clipboard", true);
  const [language, setLanguage] = usePersistentState("language", "auto");
  const [translateToEnglish, setTranslateToEnglish] = usePersistentState("translate-to-english", false);

  /** Applies a theme choice to the app shell with a 300ms palette crossfade. */
  const applyTheme = useCallback(
    (choice: ThemeChoice) => {
      ensureThemeXfade();
      const resolved: Theme = choice === "system" ? resolveSystemTheme() : choice;
      document.documentElement.classList.add("theme-xfade");
      setTheme(resolved);
      window.setTimeout(() => document.documentElement.classList.remove("theme-xfade"), 340);
    },
    [setTheme]
  );

  const pickTheme = (choice: ThemeChoice) => {
    setThemeChoice(choice);
    applyTheme(choice);
  };

  /* Re-apply a persisted choice on mount if it diverges from the current shell theme. */
  useEffect(() => {
    const resolved: Theme = themeChoice === "system" ? resolveSystemTheme() : themeChoice;
    if (resolved !== theme) applyTheme(themeChoice);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /* Follow OS appearance while "System" is selected. */
  useEffect(() => {
    if (themeChoice !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => setTheme(resolveSystemTheme());
    mq.addEventListener("change", onChange);
    setTheme(resolveSystemTheme());
    return () => mq.removeEventListener("change", onChange);
  }, [themeChoice, setTheme]);

  return (
    <div className="mx-auto flex w-full max-w-[560px] flex-col gap-5 pb-2">
      <Group title="Startup">
        <Row
          label="Launch at login"
          control={<Switch checked={launchAtLogin} onChange={setLaunchAtLogin} ariaLabel="Launch at login" />}
        />
        <Row
          label="Show in Dock"
          control={<Switch checked={showInDock} onChange={setShowInDock} ariaLabel="Show in Dock" />}
        />
        <Row
          label="Start recording when menu bar icon is clicked"
          caption="When off, the popover opens idle instead of recording."
          control={
            <Switch checked={menubarRecording} onChange={setMenubarRecording} ariaLabel="Start recording when menu bar icon is clicked" />
          }
        />
        <Row
          label="Always close window after dictation"
          control={<Switch checked={alwaysClose} onChange={setAlwaysClose} ariaLabel="Always close window after dictation" />}
        />
      </Group>

      <Group title="Appearance">
        <Row
          label="Theme"
          control={
            <SegmentedControl<ThemeChoice>
              id="theme"
              ariaLabel="Theme"
              value={themeChoice}
              onChange={pickTheme}
              options={[
                { value: "light", label: (<><Sun size={12} /> Light</>) },
                { value: "dark", label: (<><Moon size={12} /> Dark</>) },
                { value: "system", label: (<><Monitor size={12} /> System</>) },
              ]}
            />
          }
        />
        <Row
          label="Sound effects style"
          caption="Played on toggles and confirmations across the app."
          control={
            <SegmentedControl<SoundStyle>
              id="sound-style"
              ariaLabel="Sound effects style"
              value={soundStyle}
              onChange={setSoundStyle}
              options={[
                { value: "subtle", label: "Subtle" },
                { value: "classic", label: "Classic" },
                { value: "none", label: "None" },
              ]}
            />
          }
        />
      </Group>

      <Group title="Paste">
        <Row
          label="Auto-paste after transcription"
          control={<Switch checked={autoPaste} onChange={setAutoPaste} ariaLabel="Auto-paste after transcription" />}
        />
        <Row
          label={
            <>
              Restore clipboard after paste
              <InfoTip text="zWhisper preserves your clipboard: whatever you copied before dictating is restored right after the transcript is pasted." />
            </>
          }
          control={
            <Switch checked={restoreClipboard} onChange={setRestoreClipboard} ariaLabel="Restore clipboard after paste" />
          }
        />
      </Group>

      <Group title="Language">
        <Row
          label="Spoken language"
          caption="100+ languages supported"
          control={
            <Dropdown
              ariaLabel="Spoken language"
              options={LANGUAGES}
              value={language}
              onChange={setLanguage}
            />
          }
        />
        <Row
          label="Translate to English"
          control={
            <Switch checked={translateToEnglish} onChange={setTranslateToEnglish} ariaLabel="Translate to English" />
          }
        />
      </Group>

      <footer className="mt-2 flex flex-col items-center gap-2 pb-1">
        <img src="/logo.svg" alt="zWhisper" className="h-8 w-8 rounded-[8px] hairline" />
        <p className="text-[11px] text-3">zWhisper Prototype v0.1 — transcription is simulated</p>
      </footer>
    </div>
  );
}

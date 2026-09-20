/* eslint-disable react-refresh/only-export-components */
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import type { Mode } from "@/lib/modes";
import { DEFAULT_MODE, MODES } from "@/lib/modes";

export type Theme = "dark" | "light";

interface AppState {
  theme: Theme;
  toggleTheme: () => void;
  setTheme: (t: Theme) => void;
  mode: Mode;
  setMode: (m: Mode) => void;
  setModeById: (id: string) => void;
  /** recording popover visibility, controllable from the menubar icon */
  popoverOpen: boolean;
  setPopoverOpen: (open: boolean) => void;
  /** bump to summon popover + start recording immediately (push-to-talk) */
  summonSignal: number;
  summon: () => void;
}

const AppContext = createContext<AppState | null>(null);

export function AppProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>("dark");
  const [mode, setMode] = useState<Mode>(DEFAULT_MODE);
  const [popoverOpen, setPopoverOpen] = useState(false);
  const [summonSignal, setSummonSignal] = useState(0);

  const setTheme = useCallback((t: Theme) => {
    setThemeState(t);
    document.documentElement.classList.toggle("light", t === "light");
    document.documentElement.classList.toggle("dark", t === "dark");
  }, []);

  const toggleTheme = useCallback(() => {
    setTheme(theme === "dark" ? "light" : "dark");
  }, [theme, setTheme]);

  const setModeById = useCallback((id: string) => {
    const m = MODES.find((mm) => mm.id === id);
    if (m) setMode(m);
  }, []);

  const summon = useCallback(() => {
    setPopoverOpen(true);
    setSummonSignal((n) => n + 1);
  }, []);

  useEffect(() => {
    document.documentElement.classList.add("dark");
  }, []);

  const value = useMemo<AppState>(
    () => ({
      theme,
      toggleTheme,
      setTheme,
      mode,
      setMode,
      setModeById,
      popoverOpen,
      setPopoverOpen,
      summonSignal,
      summon,
    }),
    [theme, toggleTheme, setTheme, mode, setModeById, popoverOpen, summon, summonSignal]
  );

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useApp(): AppState {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error("useApp must be used inside <AppProvider>");
  return ctx;
}

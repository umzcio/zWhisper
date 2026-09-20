import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ChartColumn, Keyboard, Settings as GearIcon, Volume2 } from "lucide-react";
import TrafficLights from "@/components/TrafficLights";
import SidebarNav from "@/components/SidebarNav";
import { ToastProvider } from "@/components/settings/toast";
import { playClick } from "@/components/settings/settingsState";
import GeneralTab from "@/components/settings/GeneralTab";
import SoundTab from "@/components/settings/SoundTab";
import ShortcutsTab from "@/components/settings/ShortcutsTab";
import UsageTab from "@/components/settings/UsageTab";
import { cn } from "@/lib/utils";

type TabId = "general" | "sound" | "shortcuts" | "usage";

const TABS: { id: TabId; label: string; icon: typeof GearIcon }[] = [
  { id: "general", label: "General", icon: GearIcon },
  { id: "sound", label: "Sound", icon: Volume2 },
  { id: "shortcuts", label: "Shortcuts", icon: Keyboard },
  { id: "usage", label: "Usage", icon: ChartColumn },
];

/** macOS toolbar tab strip: icon-over-label, 64px items, sliding accent indicator. */
function Toolbar({ tab, onChange }: { tab: TabId; onChange: (t: TabId) => void }) {
  return (
    <div
      role="tablist"
      aria-label="Settings sections"
      className="flex shrink-0 items-center justify-center gap-1 border-b border-separator px-4 py-2"
    >
      {TABS.map((t) => {
        const active = t.id === tab;
        return (
          <motion.button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => {
              if (!active) {
                playClick();
                onChange(t.id);
              }
            }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className="relative flex w-16 cursor-pointer flex-col items-center gap-1 rounded-[8px] py-1.5"
          >
            {active && (
              <motion.span
                layoutId="settings-toolbar-indicator"
                transition={{ type: "spring", stiffness: 500, damping: 35 }}
                className="hairline absolute inset-0 rounded-[8px] bg-surface-3/70"
              />
            )}
            <t.icon
              size={19}
              strokeWidth={1.8}
              className={cn(
                "relative z-10 transition-colors duration-150",
                active ? "text-accent-blue" : "text-2"
              )}
            />
            <span
              className={cn(
                "relative z-10 text-[11px] font-medium transition-colors duration-150",
                active ? "text-accent-blue" : "text-2"
              )}
            >
              {t.label}
            </span>
          </motion.button>
        );
      })}
    </div>
  );
}

const PANES: Record<TabId, React.ComponentType> = {
  general: GeneralTab,
  sound: SoundTab,
  shortcuts: ShortcutsTab,
  usage: UsageTab,
};

/** Settings management window — 920×640, traffic-light chrome, SidebarNav, tabbed panes. */
export default function Settings() {
  const [tab, setTab] = useState<TabId>("general");
  const Pane = PANES[tab];

  return (
    <div className="flex h-full items-center justify-center p-6">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 8 }}
        transition={{ duration: 0.25 }}
        className="vibrancy hairline relative flex h-[640px] max-h-full w-[920px] max-w-full flex-col overflow-hidden rounded-[12px] shadow-window"
      >
        {/* 28px title bar */}
        <div className="flex h-7 shrink-0 items-center border-b border-separator px-3">
          <TrafficLights />
          <span className="flex-1 text-center text-[13px] font-semibold tracking-[-0.01em] text-2">
            Settings
          </span>
          <span className="w-[52px]" />
        </div>

        <ToastProvider>
          <div className="flex min-h-0 flex-1">
            <SidebarNav />
            <div className="flex min-w-0 flex-1 flex-col">
              <Toolbar tab={tab} onChange={setTab} />
              {/* pane slot: crossfade + 6px y drift, 200ms */}
              <div className="relative min-h-0 flex-1">
                <AnimatePresence mode="wait">
                  <motion.div
                    key={tab}
                    initial={{ opacity: 0, y: 6 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -6 }}
                    transition={{ duration: 0.2 }}
                    className="absolute inset-0 overflow-auto px-6 py-5"
                    role="tabpanel"
                  >
                    <Pane />
                  </motion.div>
                </AnimatePresence>
              </div>
            </div>
          </div>
        </ToastProvider>
      </motion.div>
    </div>
  );
}

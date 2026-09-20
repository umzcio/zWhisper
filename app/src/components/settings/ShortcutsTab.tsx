import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import ShortcutKey from "@/components/ShortcutKey";
import { Group, Row } from "@/components/settings/controls";
import { usePersistentState, playClick } from "@/components/settings/settingsState";
import { cn } from "@/lib/utils";

interface ShortcutAction {
  id: string;
  label: string;
  /** hint suffix shown after the combo, e.g. hold behavior */
  suffix?: string;
}

const ACTIONS: ShortcutAction[] = [
  { id: "toggle", label: "Toggle recording" },
  { id: "push", label: "Push to talk", suffix: "(hold)" },
  { id: "cancel", label: "Cancel dictation" },
  { id: "cycle-mode", label: "Change mode (cycle)" },
];

const DEFAULT_COMBOS: Record<string, string[]> = {
  toggle: ["⌥", "⇧", "Space"],
  push: ["Space"],
  cancel: ["Esc"],
  "cycle-mode": ["⌥", "⇧", "K"],
};

const MODIFIER_KEYS = new Set(["Meta", "Control", "Alt", "Shift"]);

function comboFromEvent(e: KeyboardEvent): string[] | null {
  if (MODIFIER_KEYS.has(e.key)) return null;
  const mods: string[] = [];
  if (e.ctrlKey) mods.push("⌃");
  if (e.altKey) mods.push("⌥");
  if (e.shiftKey) mods.push("⇧");
  if (e.metaKey) mods.push("⌘");
  let key = e.key;
  if (key === " ") key = "Space";
  else if (key === "Escape") key = "Esc";
  else if (key === "ArrowUp") key = "↑";
  else if (key === "ArrowDown") key = "↓";
  else if (key === "ArrowLeft") key = "←";
  else if (key === "ArrowRight") key = "→";
  else if (key.length === 1) key = key.toUpperCase();
  return [...mods, key];
}

const serialize = (keys: string[]) => keys.join("+");

/** Animated kbd chips — stagger in one-by-one (scale 0.7 → 1, 0.06 stagger) on every change. */
function ComboChips({ keys }: { keys: string[] }) {
  return (
    <span className="flex items-center gap-1">
      {keys.map((k, i) => (
        <motion.span
          key={`${serialize(keys)}-${i}`}
          initial={{ opacity: 0, scale: 0.7 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: i * 0.06, type: "spring", stiffness: 500, damping: 35 }}
          className="inline-flex"
        >
          <ShortcutKey keys={k} />
        </motion.span>
      ))}
    </span>
  );
}

function CaptureField({
  keys,
  armed,
  conflict,
  onArm,
}: {
  keys: string[];
  armed: boolean;
  conflict: boolean;
  onArm: () => void;
}) {
  return (
    <motion.div
      animate={conflict ? { x: [0, -6, 6, -4, 4, 0] } : { x: 0 }}
      transition={{ duration: 0.3 }}
    >
      <motion.button
        type="button"
        onClick={onArm}
        whileTap={{ scale: 0.97 }}
        animate={
          armed
            ? {
                boxShadow: [
                  "0 0 0 2px rgba(10,132,255,0.9)",
                  "0 0 0 2px rgba(10,132,255,0.25)",
                  "0 0 0 2px rgba(10,132,255,0.9)",
                ],
              }
            : conflict
              ? { boxShadow: "0 0 0 2px var(--accent-red)" }
              : { boxShadow: "0 0 0 0px rgba(10,132,255,0)" }
        }
        transition={
          armed
            ? { duration: 1.1, repeat: Infinity, ease: "easeInOut" }
            : { duration: 0.2 }
        }
        className={cn(
          "flex h-7 min-w-28 cursor-pointer items-center justify-center rounded-[7px] bg-surface-3/60 px-2",
          !armed && "hairline hover:bg-surface-3"
        )}
      >
        {armed ? (
          <span className="text-[11px] font-medium text-accent-blue">Press shortcut…</span>
        ) : (
          <ComboChips keys={keys} />
        )}
      </motion.button>
    </motion.div>
  );
}

export default function ShortcutsTab() {
  const [combos, setCombos] = usePersistentState<Record<string, string[]>>(
    "shortcut-combos",
    DEFAULT_COMBOS
  );
  const [armedId, setArmedId] = useState<string | null>(null);
  const [conflict, setConflict] = useState<{ id: string; other: string } | null>(null);

  /* Keystroke capture while a field is armed. */
  useEffect(() => {
    if (!armedId) return;
    const onKeyDown = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();
      const combo = comboFromEvent(e);
      if (!combo) return; // modifier-only press — keep waiting

      const other = ACTIONS.find(
        (a) => a.id !== armedId && serialize(combos[a.id] ?? []) === serialize(combo)
      );
      if (other) {
        playClick();
        setConflict({ id: armedId, other: other.label });
        setArmedId(null);
        window.setTimeout(() => setConflict(null), 2400);
        return;
      }
      setConflict(null);
      setCombos((prev) => ({ ...prev, [armedId]: combo }));
      setArmedId(null);
    };
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, [armedId, combos, setCombos]);

  /* Clicking anywhere else disarms the field. */
  useEffect(() => {
    if (!armedId) return;
    const onDown = (e: PointerEvent) => {
      if (!(e.target as HTMLElement).closest("[data-capture-field]")) setArmedId(null);
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [armedId]);

  return (
    <div className="mx-auto flex w-full max-w-[560px] flex-col gap-5 pb-2">
      <Group title="Keyboard">
        {ACTIONS.map((action) => (
          <div key={action.id} data-capture-field>
            <Row
              label={
                <>
                  {action.label}
                  {action.suffix && <span className="text-[11px] text-3">{action.suffix}</span>}
                </>
              }
              control={
                <CaptureField
                  keys={combos[action.id] ?? DEFAULT_COMBOS[action.id]}
                  armed={armedId === action.id}
                  conflict={conflict?.id === action.id}
                  onArm={() => {
                    playClick();
                    setConflict(null);
                    setArmedId(action.id);
                  }}
                />
              }
            />
            {conflict?.id === action.id && (
              <motion.p
                initial={{ opacity: 0, y: -2 }}
                animate={{ opacity: 1, y: 0 }}
                className="px-3.5 pb-2 text-right text-[11px] font-medium text-accent-red"
              >
                Already used by {conflict.other}
              </motion.p>
            )}
          </div>
        ))}
        <Row
          label={
            <>
              Mode shortcuts
              <span className="rounded bg-surface-3 px-1 py-px text-[10px] font-medium text-3">
                built-in
              </span>
            </>
          }
          control={
            <span className="flex flex-wrap items-center justify-end gap-1">
              {Array.from({ length: 9 }, (_, i) => (
                <ShortcutKey key={i} keys={`⌘${i + 1}`} />
              ))}
            </span>
          }
        />
      </Group>

      <p className="px-1 text-center text-[11px] leading-snug text-3">
        In the web prototype, some shortcuts are simulated with on-screen buttons.
      </p>
    </div>
  );
}

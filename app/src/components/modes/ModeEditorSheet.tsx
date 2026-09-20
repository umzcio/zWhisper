import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Check, ChevronDown, Plus, X } from "lucide-react";
import { cn } from "@/lib/utils";
import type { ActivationRule, LibraryMode } from "@/components/modes/data";
import {
  COLOR_SWATCHES,
  ICON_PICKER_OPTIONS,
  INSTRUCTIONS_PLACEHOLDER,
  MODE_ICON_MAP,
  RULE_APPS,
} from "@/components/modes/data";
import LivePreview from "@/components/modes/LivePreview";

const SPRING_SHEET = { type: "spring", stiffness: 380, damping: 32 } as const;
const SPRING_MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;

export interface ModeDraft {
  mode: LibraryMode;
  rules: ActivationRule[];
  isNew: boolean;
}

interface ModeEditorSheetProps {
  open: boolean;
  draft: ModeDraft | null;
  onCancel: () => void;
  onSave: (draft: ModeDraft) => void;
}

/** macOS sheet: slides down from the window title bar over a dimmed scrim */
export default function ModeEditorSheet({ open, draft, onCancel, onSave }: ModeEditorSheetProps) {
  return (
    <AnimatePresence>
      {open && draft && (
        <EditorPanel
          key={`${draft.mode.id}-${String(draft.isNew)}`}
          draft={draft}
          onCancel={onCancel}
          onSave={onSave}
        />
      )}
    </AnimatePresence>
  );
}

function EditorPanel({
  draft,
  onCancel,
  onSave,
}: {
  draft: ModeDraft;
  onCancel: () => void;
  onSave: (draft: ModeDraft) => void;
}) {
  const [mode, setMode] = useState<LibraryMode>(() => ({ ...draft.mode }));
  const [rules, setRules] = useState<ActivationRule[]>(() =>
    draft.rules.map((r) => ({ ...r }))
  );

  // Esc cancels the sheet
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onCancel]);

  const patch = (p: Partial<LibraryMode>) => setMode((m) => ({ ...m, ...p }));
  const isNew = draft.isNew;
  const canSave = mode.name.trim().length > 0;

  return (
        <div className="absolute inset-0 z-40">
          {/* scrim */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            onClick={onCancel}
            className="absolute inset-0 bg-black/30"
          />
          {/* sheet */}
          <motion.div
            initial={{ opacity: 0, y: -24 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -24 }}
            transition={SPRING_SHEET}
            className="vibrancy absolute left-1/2 top-7 flex max-h-[calc(100%-40px)] w-[560px] max-w-[calc(100%-32px)] -translate-x-1/2 flex-col overflow-hidden rounded-[12px] shadow-window hairline"
          >
            {/* sheet header */}
            <div className="flex h-10 shrink-0 items-center gap-2 border-b border-separator px-4">
              <span
                className="flex h-6 w-6 items-center justify-center rounded-[7px]"
                style={{ backgroundColor: `${mode.color}26` }}
              >
                {(() => {
                  const Icon = MODE_ICON_MAP[mode.icon] ?? MODE_ICON_MAP.Sparkles;
                  return <Icon size={13} strokeWidth={2.2} style={{ color: mode.color }} />;
                })()}
              </span>
              <span className="text-[13px] font-semibold text-1">
                {isNew ? "New Mode" : `Edit “${draft.mode.name}”`}
              </span>
              {mode.shortcut && (
                <kbd className="ml-auto font-mono text-[11px] font-medium text-3">
                  {mode.shortcut}
                </kbd>
              )}
            </div>

            {/* body: form + live preview */}
            <div className="flex min-h-0 flex-1">
              <div className="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
                {/* name + color */}
                <div>
                  <FieldLabel>Name</FieldLabel>
                  <input
                    value={mode.name}
                    onChange={(e) => patch({ name: e.target.value })}
                    placeholder="My Mode"
                    className="w-full rounded-md bg-surface-2 px-2.5 py-1.5 text-[13px] text-1 hairline placeholder:text-3 focus:outline-none focus:ring-2 focus:ring-accent-blue/60"
                  />
                  <div className="mt-2 flex items-center gap-2">
                    {COLOR_SWATCHES.map((c) => {
                      const selected = mode.color === c;
                      return (
                        <motion.button
                          key={c}
                          type="button"
                          aria-label={`Color ${c}`}
                          onClick={() => patch({ color: c })}
                          animate={{ scale: selected ? 1.15 : 1 }}
                          whileTap={{ scale: 0.9 }}
                          transition={SPRING_MICRO}
                          className={cn(
                            "h-5 w-5 cursor-pointer rounded-full",
                            selected && "ring-2 ring-white/70 ring-offset-2 ring-offset-surface-1"
                          )}
                          style={{ backgroundColor: c }}
                        >
                          {selected && <Check size={11} strokeWidth={3.5} className="mx-auto text-white" />}
                        </motion.button>
                      );
                    })}
                  </div>
                </div>

                {/* icon picker */}
                <div>
                  <FieldLabel>Icon</FieldLabel>
                  <div className="flex items-center gap-1.5">
                    {ICON_PICKER_OPTIONS.map((key) => {
                      const Icon = MODE_ICON_MAP[key];
                      const selected = mode.icon === key;
                      return (
                        <motion.button
                          key={key}
                          type="button"
                          aria-label={`Icon ${key}`}
                          onClick={() => patch({ icon: key })}
                          whileHover={{ scale: 1.06 }}
                          whileTap={{ scale: 0.92 }}
                          transition={SPRING_MICRO}
                          className={cn(
                            "flex h-8 w-8 cursor-pointer items-center justify-center rounded-[8px] hairline",
                            selected
                              ? "border-accent-blue bg-accent-blue/15"
                              : "bg-surface-2 hover:bg-surface-3"
                          )}
                        >
                          <Icon
                            size={14}
                            strokeWidth={2.2}
                            style={{ color: selected ? mode.color : "var(--text-2)" }}
                          />
                        </motion.button>
                      );
                    })}
                  </div>
                </div>

                {/* AI instructions */}
                <div>
                  <FieldLabel>AI Instructions</FieldLabel>
                  <textarea
                    value={mode.instructions}
                    onChange={(e) => patch({ instructions: e.target.value })}
                    placeholder={INSTRUCTIONS_PLACEHOLDER}
                    className="h-[120px] w-full resize-none rounded-md bg-surface-2 px-2.5 py-2 text-[12px] leading-relaxed text-1 hairline placeholder:text-3 focus:outline-none focus:ring-2 focus:ring-accent-blue/60"
                  />
                  <p className="mt-1 text-[11px] text-3">
                    These instructions shape the final text after transcription.
                  </p>
                </div>

                {/* include context */}
                <div className="rounded-md bg-surface-2/60 p-2.5 hairline">
                  <div className="mb-1 flex items-center gap-1.5">
                    <span className="text-[11px] font-semibold uppercase tracking-[0.02em] text-accent-purple">
                      Include context
                    </span>
                    <span className="rounded-full bg-accent-purple/15 px-1.5 py-px text-[9px] font-medium text-accent-purple">
                      Super
                    </span>
                  </div>
                  <ToggleRow
                    label="Read selected text"
                    checked={mode.readSelected}
                    onChange={(v) => patch({ readSelected: v })}
                  />
                  <ToggleRow
                    label="Read clipboard"
                    checked={mode.readClipboard}
                    onChange={(v) => patch({ readClipboard: v })}
                  />
                </div>

                {/* auto-activation rules */}
                <div>
                  <FieldLabel>Auto-activation</FieldLabel>
                  <div className="flex flex-col gap-1.5">
                    <AnimatePresence initial={false}>
                      {rules.map((rule) => (
                        <motion.div
                          key={rule.id}
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: "auto", opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          transition={{ duration: 0.2 }}
                          className="overflow-hidden"
                        >
                          <RuleRow
                            rule={rule}
                            onChange={(r) =>
                              setRules((rs) => rs.map((x) => (x.id === r.id ? r : x)))
                            }
                            onRemove={() => setRules((rs) => rs.filter((x) => x.id !== rule.id))}
                          />
                        </motion.div>
                      ))}
                    </AnimatePresence>
                    <motion.button
                      type="button"
                      whileTap={{ scale: 0.97 }}
                      transition={SPRING_MICRO}
                      onClick={() =>
                        setRules((rs) => [
                          ...rs,
                          {
                            id: `rule-${Date.now()}`,
                            app: "Mail",
                            domain: "",
                          },
                        ])
                      }
                      className="flex cursor-pointer items-center gap-1 self-start rounded-md px-2 py-1 text-[12px] font-medium text-accent-blue hover:bg-accent-blue/10"
                    >
                      <Plus size={12} /> Add rule
                    </motion.button>
                    {rules.length === 0 && (
                      <p className="text-[11px] text-3">
                        e.g. “When Mail is frontmost → activate this mode”.
                      </p>
                    )}
                  </div>
                </div>
              </div>

              <LivePreview mode={mode} />
            </div>

            {/* footer */}
            <div className="flex shrink-0 items-center justify-end gap-2 border-t border-separator px-4 py-2.5">
              <motion.button
                type="button"
                onClick={onCancel}
                whileTap={{ scale: 0.97 }}
                transition={SPRING_MICRO}
                className="cursor-pointer rounded-md px-3 py-1.5 text-[13px] text-2 hover:bg-surface-3/60 hover:text-1"
              >
                Cancel
              </motion.button>
              <motion.button
                type="button"
                disabled={!canSave}
                onClick={() => onSave({ mode, rules, isNew: draft.isNew })}
                whileHover={canSave ? { scale: 1.02 } : undefined}
                whileTap={canSave ? { scale: 0.97 } : undefined}
                transition={SPRING_MICRO}
                className={cn(
                  "rounded-md bg-accent-blue px-3 py-1.5 text-[13px] font-medium text-white",
                  canSave ? "cursor-pointer" : "cursor-default opacity-40"
                )}
              >
                Save Mode
              </motion.button>
            </div>
          </motion.div>
        </div>
  );
}

function FieldLabel({ children }: { children: string }) {
  return (
    <span className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.02em] text-3">
      {children}
    </span>
  );
}

/** macOS toggle with purple accent (Super Mode context) */
function ToggleRow({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex w-full cursor-pointer items-center justify-between rounded-md px-1.5 py-1.5 hover:bg-surface-3/40"
    >
      <span className="text-[12px] text-1">{label}</span>
      <span
        className={cn(
          "flex h-[18px] w-[30px] items-center rounded-full p-[2px] transition-colors duration-150",
          checked ? "justify-end bg-accent-purple" : "justify-start bg-surface-3"
        )}
      >
        <motion.span
          layout
          transition={SPRING_MICRO}
          className="h-[14px] w-[14px] rounded-full bg-white shadow-sm"
        />
      </span>
    </button>
  );
}

/** One auto-activation rule row: When [app] is frontmost → activate this mode */
function RuleRow({
  rule,
  onChange,
  onRemove,
}: {
  rule: ActivationRule;
  onChange: (r: ActivationRule) => void;
  onRemove: () => void;
}) {
  return (
    <div className="flex items-center gap-1.5 rounded-md bg-surface-2 px-2 py-1.5 text-[12px] text-2 hairline">
      <span className="shrink-0">When</span>
      <AppPicker value={rule.app} onChange={(app) => onChange({ ...rule, app })} />
      {rule.app === "Safari" && (
        <input
          value={rule.domain}
          onChange={(e) => onChange({ ...rule, domain: e.target.value })}
          placeholder="domain.com"
          className="w-24 rounded bg-surface-1 px-1.5 py-0.5 text-[11px] text-1 hairline placeholder:text-3 focus:outline-none focus:ring-1 focus:ring-accent-blue/60"
        />
      )}
      <span className="shrink-0">is frontmost → activate</span>
      <motion.button
        type="button"
        aria-label="Remove rule"
        onClick={onRemove}
        whileTap={{ scale: 0.85 }}
        transition={SPRING_MICRO}
        className="ml-auto flex h-5 w-5 shrink-0 cursor-pointer items-center justify-center rounded text-3 hover:bg-surface-3 hover:text-accent-red"
      >
        <X size={11} />
      </motion.button>
    </div>
  );
}

function AppPicker({ value, onChange }: { value: string; onChange: (app: string) => void }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [open]);

  return (
    <div ref={ref} className="relative shrink-0">
      <motion.button
        type="button"
        onClick={() => setOpen((o) => !o)}
        whileTap={{ scale: 0.96 }}
        transition={SPRING_MICRO}
        className="flex cursor-pointer items-center gap-1 rounded bg-surface-1 px-1.5 py-0.5 text-[11px] font-medium text-1 hairline hover:bg-surface-3"
      >
        {value}
        <ChevronDown size={10} className="text-3" />
      </motion.button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, scale: 0.92, y: -4 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: -4 }}
            transition={{ type: "spring", stiffness: 400, damping: 30 }}
            className="vibrancy absolute left-0 top-6 z-30 w-28 rounded-[8px] p-1 shadow-popover hairline"
          >
            {RULE_APPS.map((app) => (
              <button
                key={app}
                type="button"
                onClick={() => {
                  onChange(app);
                  setOpen(false);
                }}
                className={cn(
                  "flex w-full cursor-pointer items-center justify-between rounded px-2 py-1 text-left text-[11px]",
                  app === value ? "bg-accent-blue/15 text-1" : "text-2 hover:bg-surface-3/60 hover:text-1"
                )}
              >
                {app}
                {app === value && <Check size={10} className="text-accent-blue" strokeWidth={3} />}
              </button>
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

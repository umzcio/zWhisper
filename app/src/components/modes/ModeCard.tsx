import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Check, Copy, MoreHorizontal, Pencil, Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";
import ShortcutKey from "@/components/ShortcutKey";
import type { LibraryMode } from "@/components/modes/data";
import { MODE_ICON_MAP } from "@/components/modes/data";

const SPRING_MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;

interface ModeCardProps {
  mode: LibraryMode;
  active: boolean;
  onOpen: (mode: LibraryMode) => void;
  onDuplicate: (mode: LibraryMode) => void;
  onDelete: (mode: LibraryMode) => void;
}

/** 96px mode card: tinted squircle icon, name/description, badges, shortcut chip, ⋯ menu */
export default function ModeCard({ mode, active, onOpen, onDuplicate, onDelete }: ModeCardProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const Icon = MODE_ICON_MAP[mode.icon] ?? MODE_ICON_MAP.Sparkles;
  const isSuper = mode.readSelected || mode.readClipboard;

  useEffect(() => {
    if (!menuOpen) return;
    const onDown = (e: PointerEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false);
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [menuOpen]);

  return (
    <motion.div
      whileHover={{ y: -2 }}
      transition={{ duration: 0.15 }}
      className={cn(
        "group relative h-24 cursor-pointer rounded-[12px] bg-surface-2 p-3",
        "transition-shadow duration-150 hover:shadow-[0_12px_32px_rgba(0,0,0,0.35)]",
        active
          ? "border border-accent-blue shadow-[0_0_0_1px_var(--zw-accent)]"
          : "hairline"
      )}
      onClick={() => onOpen(mode)}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter") onOpen(mode);
      }}
    >
      <div className="flex h-full items-start gap-3">
        {/* tinted squircle icon */}
        <span
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px]"
          style={{ backgroundColor: `${mode.color}26` }}
        >
          <Icon size={17} strokeWidth={2.2} style={{ color: mode.color }} />
        </span>

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <span className="truncate text-[13px] font-semibold text-1">{mode.name}</span>
            <span
              className={cn(
                "shrink-0 rounded-full px-1.5 py-px text-[10px] font-medium",
                mode.builtIn ? "bg-surface-3 text-2" : "bg-accent-blue/15 text-accent-blue"
              )}
            >
              {mode.builtIn ? "Built-in" : "Custom"}
            </span>
            {isSuper && (
              <span className="shrink-0 rounded-full bg-accent-purple/15 px-1.5 py-px text-[10px] font-medium text-accent-purple">
                Super
              </span>
            )}
          </div>
          <p className="mt-0.5 truncate text-[12px] text-2">{mode.description}</p>
        </div>

        <ShortcutKey keys={mode.shortcut} className="mt-0.5 shrink-0" />
      </div>

      {/* active check, top-right */}
      {active && (
        <motion.span
          initial={{ scale: 0.5, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={SPRING_MICRO}
          className="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-accent-blue shadow-popover"
        >
          <Check size={11} strokeWidth={3.5} className="text-white" />
        </motion.span>
      )}

      {/* overflow menu */}
      <div
        ref={menuRef}
        className="absolute right-2 top-2"
        onClick={(e) => e.stopPropagation()}
      >
        <motion.button
          type="button"
          aria-label={`${mode.name} actions`}
          onClick={() => setMenuOpen((o) => !o)}
          whileTap={{ scale: 0.92 }}
          transition={SPRING_MICRO}
          className={cn(
            "flex h-6 w-6 cursor-pointer items-center justify-center rounded-md text-2 transition-opacity hover:bg-surface-3 hover:text-1",
            menuOpen ? "opacity-100" : "opacity-0 group-hover:opacity-100"
          )}
        >
          <MoreHorizontal size={14} />
        </motion.button>
        <AnimatePresence>
          {menuOpen && (
            <motion.div
              initial={{ opacity: 0, scale: 0.92, y: -4 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: -4 }}
              transition={{ type: "spring", stiffness: 400, damping: 30 }}
              className="vibrancy absolute right-0 top-7 z-30 w-36 rounded-[10px] p-1 shadow-popover hairline"
            >
              <MenuItem
                icon={Pencil}
                label="Edit"
                onClick={() => {
                  setMenuOpen(false);
                  onOpen(mode);
                }}
              />
              <MenuItem
                icon={Copy}
                label="Duplicate"
                onClick={() => {
                  setMenuOpen(false);
                  onDuplicate(mode);
                }}
              />
              {!mode.builtIn && (
                <MenuItem
                  icon={Trash2}
                  label="Delete"
                  destructive
                  onClick={() => {
                    setMenuOpen(false);
                    onDelete(mode);
                  }}
                />
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}

function MenuItem({
  icon: Icon,
  label,
  destructive,
  onClick,
}: {
  icon: typeof Pencil;
  label: string;
  destructive?: boolean;
  onClick: () => void;
}) {
  return (
    <motion.button
      type="button"
      whileTap={{ scale: 0.97 }}
      onClick={onClick}
      className={cn(
        "flex w-full cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-left text-[12px]",
        destructive
          ? "text-accent-red hover:bg-accent-red/10"
          : "text-1 hover:bg-surface-3/60"
      )}
    >
      <Icon size={13} />
      {label}
    </motion.button>
  );
}

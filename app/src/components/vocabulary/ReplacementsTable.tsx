import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";
import type { TextReplacement } from "@/components/vocabulary/vocabData";

type Field = "trigger" | "replacement";

interface ReplacementsTableProps {
  rows: TextReplacement[];
  /** id of a freshly added row whose first cell should enter edit mode */
  focusRowId: string | null;
  onFocused: () => void;
  onUpdate: (id: string, field: Field, value: string) => void;
  onDelete: (id: string) => void;
}

/** Inline-editable replacements table: click a cell → input, Enter/blur commits with accent flash */
export default function ReplacementsTable({
  rows,
  focusRowId,
  onFocused,
  onUpdate,
  onDelete,
}: ReplacementsTableProps) {
  const [editing, setEditing] = useState<{ id: string; field: Field } | null>(null);
  const [draft, setDraft] = useState("");
  const [flash, setFlash] = useState<string | null>(null);
  const flashTimer = useRef<number | undefined>(undefined);

  /* a new row was added → put its first cell into edit mode */
  useEffect(() => {
    if (focusRowId) {
      setEditing({ id: focusRowId, field: "trigger" });
      setDraft("");
      onFocused();
    }
  }, [focusRowId, onFocused]);

  useEffect(() => () => window.clearTimeout(flashTimer.current), []);

  const beginEdit = (id: string, field: Field, current: string) => {
    setEditing({ id, field });
    setDraft(current);
  };

  const commit = () => {
    if (!editing) return;
    const row = rows.find((r) => r.id === editing.id);
    if (row && draft.trim() && draft !== row[editing.field]) {
      onUpdate(editing.id, editing.field, draft.trim());
      setFlash(`${editing.id}:${editing.field}`);
      window.clearTimeout(flashTimer.current);
      flashTimer.current = window.setTimeout(() => setFlash(null), 300);
    }
    setEditing(null);
  };

  const renderCell = (row: TextReplacement, field: Field) => {
    const isEditing = editing?.id === row.id && editing.field === field;
    const flashing = flash === `${row.id}:${field}`;
    return (
      <div
        className={cn(
          "min-w-0 rounded-[4px] px-2 py-1 transition-colors duration-300",
          flashing && "bg-accent-blue/20"
        )}
      >
        {isEditing ? (
          <input
            autoFocus
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === "Enter") commit();
              if (e.key === "Escape") setEditing(null);
            }}
            className="w-full rounded-[4px] bg-surface-3/60 px-1 py-0.5 text-[13px] text-1 outline-none ring-1 ring-accent-blue"
          />
        ) : (
          <button
            type="button"
            onClick={() => beginEdit(row.id, field, row[field])}
            className={cn(
              "w-full cursor-text truncate rounded-[4px] px-1 py-0.5 text-left text-[13px] hover:bg-surface-3/50",
              row[field] ? "text-1" : "italic text-3"
            )}
          >
            {row[field] || (field === "trigger" ? "When I say…" : "Replace with…")}
          </button>
        )}
      </div>
    );
  };

  return (
    <div className="overflow-visible rounded-[10px] hairline">
      {/* header */}
      <div className="grid grid-cols-[1fr_1fr_36px] items-center gap-2 border-b border-separator bg-surface-2/60 px-2 py-1.5">
        <span className="px-2 text-[11px] font-semibold uppercase tracking-[0.02em] text-3">
          When I say
        </span>
        <span className="px-2 text-[11px] font-semibold uppercase tracking-[0.02em] text-3">
          Replace with
        </span>
        <span />
      </div>

      {/* rows */}
      <div>
        <AnimatePresence initial={false}>
          {rows.map((row) => (
            <motion.div
              key={row.id}
              layout="position"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
              className="group overflow-hidden border-b border-separator last:border-b-0"
            >
              <div className="grid grid-cols-[1fr_1fr_36px] items-center gap-2 px-2 py-1 hover:bg-surface-2/40">
                {renderCell(row, "trigger")}
                {renderCell(row, "replacement")}
                <motion.button
                  type="button"
                  aria-label="Delete replacement"
                  onClick={() => onDelete(row.id)}
                  whileTap={{ scale: 0.9 }}
                  className="flex h-7 w-7 cursor-pointer items-center justify-center rounded-md text-3 opacity-0 transition-opacity hover:bg-accent-red/10 hover:text-accent-red group-hover:opacity-100"
                >
                  <Trash2 size={13} />
                </motion.button>
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
        {rows.length === 0 && (
          <p className="px-4 py-3 text-[12px] text-3">No replacements yet.</p>
        )}
      </div>
    </div>
  );
}

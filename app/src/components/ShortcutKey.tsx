import { cn } from "@/lib/utils";

/** kbd-styled chip for shortcut glyphs (JetBrains Mono 11px) */
export default function ShortcutKey({
  keys,
  className,
}: {
  keys: string;
  className?: string;
}) {
  return (
    <kbd
      className={cn(
        "inline-flex items-center rounded-[6px] hairline bg-surface-2 px-1.5 py-0.5",
        "font-mono text-[11px] font-medium text-2 shadow-[0_1px_0_rgba(255,255,255,0.06)]",
        className
      )}
    >
      {keys}
    </kbd>
  );
}

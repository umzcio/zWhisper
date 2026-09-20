import { motion } from "framer-motion";
import { Star } from "lucide-react";
import { cn } from "@/lib/utils";

interface StarButtonProps {
  starred: boolean;
  onToggle: () => void;
}

/** ☆→★ favorite toggle, accent-yellow with a spring pop (1.3→1) */
export default function StarButton({ starred, onToggle }: StarButtonProps) {
  return (
    <motion.button
      type="button"
      aria-label={starred ? "Remove from favorites" : "Add to favorites"}
      onClick={(e) => {
        e.stopPropagation();
        onToggle();
      }}
      whileTap={{ scale: 0.85 }}
      className="flex h-7 w-7 cursor-pointer items-center justify-center rounded-md hover:bg-surface-3/70"
    >
      <motion.span
        key={String(starred)}
        initial={starred ? { scale: 1.3 } : false}
        animate={{ scale: 1 }}
        transition={{ type: "spring", stiffness: 500, damping: 35 }}
        className="block"
      >
        <Star
          size={15}
          className={cn(
            "transition-colors",
            starred ? "fill-[#FFD60A] text-[#FFD60A]" : "text-3 hover:text-2"
          )}
        />
      </motion.span>
    </motion.button>
  );
}

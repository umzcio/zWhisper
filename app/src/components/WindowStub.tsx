import type { ReactNode } from "react";
import { motion } from "framer-motion";
import TrafficLights from "@/components/TrafficLights";
import SidebarNav from "@/components/SidebarNav";

/** Management-window scaffold for sub-pages: traffic-light chrome + SidebarNav + content slot */
export default function WindowStub({
  title,
  children,
}: {
  title: string;
  children?: ReactNode;
}) {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 8 }}
        transition={{ duration: 0.25 }}
        className="vibrancy flex h-[560px] w-[860px] max-w-full flex-col overflow-hidden rounded-[12px] shadow-window hairline"
      >
        <div className="flex h-7 shrink-0 items-center border-b border-separator px-3">
          <TrafficLights />
          <span className="flex-1 text-center text-[13px] font-semibold tracking-[-0.01em] text-2">
            {title}
          </span>
          <span className="w-[52px]" />
        </div>
        <div className="flex min-h-0 flex-1">
          <SidebarNav />
          <div className="flex-1 overflow-auto p-6 text-[13px] text-2">
            {children ?? <p>{title} — coming soon.</p>}
          </div>
        </div>
      </motion.div>
    </div>
  );
}

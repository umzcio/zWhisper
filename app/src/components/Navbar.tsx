import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router";
import { motion } from "framer-motion";
import { Wifi, BatteryFull, AudioLines } from "lucide-react";
import { cn } from "@/lib/utils";
import { useApp } from "@/lib/store";
import { ModePill, ModeSwitcher } from "@/components/ModeSwitcher";

const MENU_ITEMS = ["File", "Edit", "View", "Window", "Help"];

const ROUTE_LINKS = [
  { to: "/modes", label: "Modes" },
  { to: "/history", label: "History" },
  { to: "/models", label: "Models" },
  { to: "/vocabulary", label: "Vocabulary" },
  { to: "/settings", label: "Settings" },
];

function formatClock(d: Date): string {
  const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  let h = d.getHours();
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12 || 12;
  const m = String(d.getMinutes()).padStart(2, "0");
  return `${days[d.getDay()]} ${months[d.getMonth()]} ${d.getDate()}  ${h}:${m} ${ampm}`;
}

/** macOS-style MenuBar — fixed top, 28px, frosted, with links to all routes */
export default function Navbar() {
  const { mode, setMode, popoverOpen, setPopoverOpen } = useApp();
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const [now, setNow] = useState(() => new Date());
  const navigate = useNavigate();
  const location = useLocation();

  useEffect(() => {
    const iv = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(iv);
  }, []);

  const togglePopover = () => {
    if (location.pathname !== "/") navigate("/");
    setPopoverOpen(!popoverOpen);
  };

  return (
    <motion.header
      initial={{ y: -28 }}
      animate={{ y: 0 }}
      transition={{ type: "spring", stiffness: 400, damping: 30, delay: 0.1 }}
      className="vibrancy-menubar fixed inset-x-0 top-0 z-50 flex h-7 items-center gap-1 border-b border-separator px-3"
    >
      {/* left: app identity + decorative menus + route links */}
      <Link to="/" className="flex cursor-pointer items-center gap-1.5 rounded px-1 py-0.5 hover:bg-white/10">
        <img src="/logo.svg" alt="zWhisper" className="h-4 w-4 rounded-[4px]" />
        <span className="text-[13px] font-semibold text-1">zWhisper</span>
      </Link>
      {MENU_ITEMS.map((item) => (
        <button
          key={item}
          type="button"
          className="cursor-default rounded px-2 py-0.5 text-[13px] text-1/90 hover:bg-white/10"
        >
          {item}
        </button>
      ))}
      <span className="mx-1 h-3.5 w-px bg-separator" />
      {ROUTE_LINKS.map((l) => (
        <Link
          key={l.to}
          to={l.to}
          className={cn(
            "rounded px-2 py-0.5 text-[13px] transition-colors hover:bg-white/10",
            location.pathname === l.to ? "text-accent-blue" : "text-2"
          )}
        >
          {l.label}
        </Link>
      ))}

      <div className="flex-1" />

      {/* right: mode pill, decorative icons, clock, record toggle */}
      <div className="relative">
        <ModePill compact mode={mode} onClick={() => setSwitcherOpen((o) => !o)} />
        <ModeSwitcher
          open={switcherOpen}
          activeMode={mode}
          onSelect={setMode}
          onClose={() => setSwitcherOpen(false)}
          className="absolute right-0 top-8 z-50"
        />
      </div>
      <Wifi size={14} className="ml-2 text-1/80" />
      <BatteryFull size={16} className="ml-1.5 text-1/80" />
      <span className="ml-2 font-mono text-xs text-1/90 tabular-nums">{formatClock(now)}</span>
      <motion.button
        type="button"
        aria-label="Toggle recording popover"
        onClick={togglePopover}
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.92 }}
        transition={{ type: "spring", stiffness: 500, damping: 35 }}
        className={cn(
          "ml-2 flex h-5 w-6 cursor-pointer items-center justify-center rounded",
          popoverOpen ? "bg-accent-blue/25 text-accent-blue" : "text-1/90 hover:bg-white/10"
        )}
      >
        <AudioLines size={14} />
      </motion.button>
    </motion.header>
  );
}

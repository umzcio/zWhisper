import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { Mic, Usb, Play } from "lucide-react";
import { useApp } from "@/lib/store";
import { Dropdown, Group, Row, SegmentedControl, Slider, Switch } from "@/components/settings/controls";
import { usePersistentState, playClick } from "@/components/settings/settingsState";
import { useToast } from "@/components/settings/toast";
import { cn } from "@/lib/utils";

const SEGMENTS = 24;

/** Simulated input level meter — 24 segments, green → yellow → red, driven by layered sine + noise. */
function LevelMeter({ testing, boosted }: { testing: boolean; boosted: boolean }) {
  const [level, setLevel] = useState(0.25);

  useEffect(() => {
    let t = Math.random() * 10;
    const iv = window.setInterval(() => {
      t += 0.07;
      const base = boosted ? 0.42 : 0.2;
      let target =
        base + 0.13 * Math.sin(t * 2.1) + 0.09 * Math.sin(t * 5.3 + 1.7) + Math.random() * 0.12;
      if (testing) target = Math.min(1, target + 0.32 + Math.random() * 0.3);
      const clamped = Math.max(0.04, Math.min(1, target));
      setLevel((prev) => prev + (clamped - prev) * 0.4);
    }, 40);
    return () => window.clearInterval(iv);
  }, [testing, boosted]);

  const lit = Math.round(level * SEGMENTS);

  return (
    <div className="flex flex-1 items-center gap-[3px]" aria-label="Input level meter">
      {Array.from({ length: SEGMENTS }, (_, i) => {
        const on = i < lit;
        const color =
          i < 15
            ? "var(--accent-green)"
            : i < 20
              ? "#FFD60A"
              : "var(--accent-red)";
        return (
          <span
            key={i}
            className="h-3.5 flex-1 rounded-[2px] transition-colors duration-75"
            style={{ backgroundColor: on ? color : "var(--surface-3)" }}
          />
        );
      })}
    </div>
  );
}

const INPUT_DEVICES = [
  { value: "builtin", label: (<><Mic size={12} className="text-3" /> Built-in Microphone</>) },
  { value: "usb", label: (<><Usb size={12} className="text-3" /> External USB Microphone</>) },
];

type Duration = "15s" | "30s" | "60s" | "inf";

export default function SoundTab() {
  const toast = useToast();
  const { popoverOpen } = useApp();

  const [device, setDevice] = usePersistentState("input-device", "builtin");
  const [normalization, setNormalization] = usePersistentState("normalization", true);
  const [silenceRemoval, setSilenceRemoval] = usePersistentState("silence-removal", true);
  const [aggressiveness, setAggressiveness] = usePersistentState("aggressiveness", 40);
  const [activeDuration, setActiveDuration] = usePersistentState<Duration>("active-duration", "30s");

  const [testing, setTesting] = useState(false);

  useEffect(() => {
    if (!testing) return;
    const timer = window.setTimeout(() => {
      setTesting(false);
      toast("Microphone looks good");
    }, 3000);
    return () => window.clearTimeout(timer);
  }, [testing, toast]);

  return (
    <div className="mx-auto flex w-full max-w-[560px] flex-col gap-5 pb-2">
      <Group title="Input">
        <Row
          label="Input device"
          control={
            <Dropdown
              ariaLabel="Input device"
              options={INPUT_DEVICES}
              value={device}
              onChange={setDevice}
              width={210}
            />
          }
        />
        <div className="flex min-h-12 items-center gap-3 px-3.5 py-2">
          <span className="shrink-0 text-[13px] text-1">Input level</span>
          <LevelMeter testing={testing} boosted={popoverOpen} />
        </div>
        <div className="flex min-h-12 items-center justify-between px-3.5 py-2">
          <span className="text-[13px] text-1">Microphone check</span>
          <motion.button
            type="button"
            disabled={testing}
            onClick={() => {
              playClick();
              setTesting(true);
            }}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.97 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className={cn(
              "hairline flex items-center gap-1.5 rounded-[6px] px-3 py-1 text-[12px] font-medium",
              testing
                ? "cursor-default bg-surface-3 text-3"
                : "cursor-pointer bg-accent-blue/15 text-accent-blue hover:bg-accent-blue/25"
            )}
          >
            <Play size={11} strokeWidth={2.5} />
            {testing ? "Testing…" : "Test microphone"}
          </motion.button>
        </div>
      </Group>

      <Group title="Processing">
        <Row
          label="Dynamic normalization"
          caption="Keeps quiet and loud speech consistent."
          control={
            <Switch checked={normalization} onChange={setNormalization} ariaLabel="Dynamic normalization" />
          }
        />
        <Row
          label="Silence removal"
          control={
            <Switch checked={silenceRemoval} onChange={setSilenceRemoval} ariaLabel="Silence removal" />
          }
        />
        <Row
          label={<span className={cn(!silenceRemoval && "text-3")}>Aggressiveness</span>}
          control={
            <div className="flex items-center gap-2.5">
              <span
                className={cn(
                  "w-7 text-right font-mono text-[11px] tabular-nums",
                  silenceRemoval ? "text-2" : "text-3"
                )}
              >
                {aggressiveness}
              </span>
              <Slider
                value={aggressiveness}
                onChange={setAggressiveness}
                disabled={!silenceRemoval}
                ariaLabel="Silence removal aggressiveness"
              />
            </div>
          }
        />
      </Group>

      <Group title="Listening">
        <Row
          label="Active duration"
          caption="How long the popover stays listening before auto-stopping."
          control={
            <SegmentedControl<Duration>
              id="active-duration"
              ariaLabel="Active duration"
              value={activeDuration}
              onChange={setActiveDuration}
              options={[
                { value: "15s", label: "15s" },
                { value: "30s", label: "30s" },
                { value: "60s", label: "60s" },
                { value: "inf", label: "∞" },
              ]}
            />
          }
        />
      </Group>
    </div>
  );
}

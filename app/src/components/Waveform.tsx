import { memo, useEffect, useRef } from "react";
import { cn } from "@/lib/utils";
import { sampleAmplitude } from "@/lib/mockEngine";

interface WaveformProps {
  /** number of bars — 48 Main, 28 Mini */
  bars?: number;
  /** speaking/recording drives amplitude; false renders low idle bars */
  active: boolean;
  /** settle bars to flat (2px) with a center-out stagger */
  settling?: boolean;
  /** recording: green→teal; playback: blue→purple */
  variant?: "recording" | "playback";
  className?: string;
}

/** Canvas waveform, ~60fps, simulated amplitude (layered sines + noise), heights lerped 0.2/frame */
const Waveform = memo(function Waveform({
  bars = 48,
  active,
  settling = false,
  variant = "recording",
  className,
}: WaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const stateRef = useRef({ active, settling, variant });

  useEffect(() => {
    stateRef.current = { active, settling, variant };
  }, [active, settling, variant]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!canvas || !ctx) return;

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const heights = new Array(bars).fill(2);
    const settleAt = new Array<number>(bars).fill(Infinity);
    let settleStart = -1;
    let raf = 0;
    let width = 0;
    let height = 0;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      canvas.width = Math.max(1, Math.round(rect.width * dpr));
      canvas.height = Math.max(1, Math.round(rect.height * dpr));
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    const BAR_W = 4;
    const GAP = 6;
    const start = performance.now();

    const frame = (now: number) => {
      const { active: isActive, settling: isSettling, variant: v } = stateRef.current;
      const t = (now - start) / 1000;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, height);

      if (isSettling && settleStart < 0) {
        settleStart = now;
        const mid = (bars - 1) / 2;
        for (let i = 0; i < bars; i++) {
          // 300ms staggered center-out
          settleAt[i] = now + (Math.abs(i - mid) / mid) * 300;
        }
      }
      if (!isSettling && settleStart >= 0) {
        settleStart = -1;
        settleAt.fill(Infinity);
      }

      const grad = ctx.createLinearGradient(0, 0, width, 0);
      if (v === "recording") {
        grad.addColorStop(0, "#30D158");
        grad.addColorStop(1, "#64D2FF");
      } else {
        grad.addColorStop(0, "#0A84FF");
        grad.addColorStop(1, "#BF5AF2");
      }
      ctx.fillStyle = grad;

      const total = bars * BAR_W + (bars - 1) * GAP;
      const x0 = (width - total) / 2;

      for (let i = 0; i < bars; i++) {
        let target: number;
        if (isSettling) {
          target = now >= settleAt[i] ? 2 : heights[i];
        } else if (reduced) {
          target = 4 + Math.abs(Math.sin(i * 0.55)) * height * 0.5;
        } else {
          const amp = sampleAmplitude(t + i * 0.17, isActive);
          target = 2 + amp * (height - 6);
        }
        heights[i] += (target - heights[i]) * 0.2;
        const h = Math.max(2, Math.min(height, heights[i]));
        const x = x0 + i * (BAR_W + GAP);
        const y = (height - h) / 2;
        const r = Math.min(4, BAR_W / 2, h / 2);
        ctx.beginPath();
        ctx.roundRect(x, y, BAR_W, h, r);
        ctx.fill();
      }
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
    };
  }, [bars]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width: "100%", height: "100%", display: "block" }}
      className={cn(className)}
      aria-hidden
    />
  );
});

export default Waveform;

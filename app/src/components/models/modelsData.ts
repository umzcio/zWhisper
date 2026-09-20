export type ModelType = "local" | "cloud";
export type CloudProvider = "OpenAI" | "Anthropic" | "Deepgram" | "Groq";

export interface ModelInfo {
  id: string;
  /** Display name, e.g. "Fast" */
  name: string;
  /** Engine label, e.g. "Whisper v3" */
  engine: string;
  description: string;
  type: ModelType;
  provider?: CloudProvider;
  /** total download size in MB (local models) */
  sizeMB: number;
  sizeLabel: string;
  /** 1–5 dot meters */
  speed: number;
  accuracy: number;
  /** extra badges beyond Local/Cloud */
  badges: { label: string; tone: "orange" | "purple" }[];
  /** e.g. "~$0.36/hr" for cloud models */
  priceHint?: string;
  /** bring-your-own-key model */
  byok?: boolean;
}

export const CLOUD_PROVIDERS: CloudProvider[] = ["OpenAI", "Anthropic", "Deepgram", "Groq"];

export const MODELS: ModelInfo[] = [
  {
    id: "nano",
    name: "Nano",
    engine: "Whisper v3",
    description: "Fastest, good for short notes",
    type: "local",
    sizeMB: 466,
    sizeLabel: "466 MB",
    speed: 4,
    accuracy: 2,
    badges: [],
  },
  {
    id: "fast",
    name: "Fast",
    engine: "Whisper v3",
    description: "Best balance — default",
    type: "local",
    sizeMB: 1536,
    sizeLabel: "1.5 GB",
    speed: 3,
    accuracy: 3,
    badges: [],
  },
  {
    id: "pro",
    name: "Pro",
    engine: "Whisper v3",
    description: "High accuracy, slower",
    type: "local",
    sizeMB: 2969,
    sizeLabel: "2.9 GB",
    speed: 2,
    accuracy: 4,
    badges: [],
  },
  {
    id: "ultra",
    name: "Ultra",
    engine: "Whisper v3 Large",
    description: "Maximum accuracy, long dictations",
    type: "local",
    sizeMB: 3174,
    sizeLabel: "3.1 GB",
    speed: 1,
    accuracy: 5,
    badges: [],
  },
  {
    id: "openai-whisper",
    name: "Whisper Large",
    engine: "OpenAI",
    description: "OpenAI hosted transcription, pay per use",
    type: "cloud",
    provider: "OpenAI",
    sizeMB: 0,
    sizeLabel: "—",
    speed: 3,
    accuracy: 5,
    badges: [],
    priceHint: "~$0.36/hr",
    byok: true,
  },
  {
    id: "deepgram-nova",
    name: "Nova-3",
    engine: "Deepgram",
    description: "Streaming-first cloud transcription",
    type: "cloud",
    provider: "Deepgram",
    sizeMB: 0,
    sizeLabel: "—",
    speed: 4,
    accuracy: 4,
    badges: [],
    priceHint: "~$0.26/hr",
    byok: true,
  },
  {
    id: "groq-whisper",
    name: "Whisper",
    engine: "Groq",
    description: "LPU-accelerated Whisper, near-instant",
    type: "cloud",
    provider: "Groq",
    sizeMB: 0,
    sizeLabel: "—",
    speed: 5,
    accuracy: 4,
    badges: [{ label: "Fastest cloud", tone: "purple" }],
    priceHint: "~$0.11/hr",
    byok: true,
  },
  {
    id: "anthropic-speech",
    name: "Speech",
    engine: "Anthropic",
    description: "Anthropic speech endpoint, billed to your key",
    type: "cloud",
    provider: "Anthropic",
    sizeMB: 0,
    sizeLabel: "—",
    speed: 3,
    accuracy: 4,
    badges: [{ label: "BYOK", tone: "orange" }],
    priceHint: "your key",
    byok: true,
  },
];

export type SortKey = "speed" | "accuracy" | "size";

export function formatMB(mb: number): string {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`;
  return `${Math.round(mb)} MB`;
}

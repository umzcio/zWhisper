/**
 * Page-local vocabulary state + helpers.
 *
 * The Home teleprompter should surface custom words as underline-chips while
 * dictating. The main agent can promote these defaults (and `findVocabWords`)
 * into shared state (`src/lib/*`) so the mock engine and this page share data.
 */

export interface VocabWord {
  word: string;
  uses: number;
  /** human label, e.g. "today", "yesterday", "this week" */
  lastUsed: string;
}

export interface TextReplacement {
  id: string;
  /** "When I say" */
  trigger: string;
  /** "Replace with" */
  replacement: string;
}

export const DEFAULT_VOCAB_WORDS: VocabWord[] = [
  { word: "zWhisper", uses: 128, lastUsed: "today" },
  { word: "SuperWhisper", uses: 46, lastUsed: "this week" },
  { word: "Kowalski", uses: 12, lastUsed: "today" },
  { word: "Aysima", uses: 34, lastUsed: "today" },
  { word: "Qwen", uses: 21, lastUsed: "yesterday" },
  { word: "Llamafile", uses: 8, lastUsed: "last week" },
  { word: "Terraform", uses: 57, lastUsed: "today" },
  { word: "GraphQL", uses: 63, lastUsed: "yesterday" },
  { word: "Nguyen", uses: 19, lastUsed: "today" },
  { word: "XGBoost", uses: 5, lastUsed: "last month" },
  { word: "PostgreSQL", uses: 41, lastUsed: "this week" },
  { word: "RxJS", uses: 17, lastUsed: "this week" },
  { word: "Chernoff", uses: 3, lastUsed: "last month" },
  { word: "Miroverse", uses: 9, lastUsed: "yesterday" },
];

export const DEFAULT_REPLACEMENTS: TextReplacement[] = [
  { id: "r1", trigger: "my email", replacement: "alex@zwhisper.app" },
  { id: "r2", trigger: "new line", replacement: "line break" },
  { id: "r3", trigger: "smiley face", replacement: "😄" },
  { id: "r4", trigger: "calendar link", replacement: "cal.com/alex-zh" },
];

/** Scripted sentence used by the Vocabulary Hints demo teleprompter. */
export const HINTS_DEMO_SENTENCE =
  "Hey Aysima, can you send the Terraform plan to Nguyen before we push the GraphQL schema update?";

/**
 * Find vocabulary words appearing in a text (word-boundary, case-insensitive,
 * punctuation-tolerant). Used to give vocab words the underline-chip treatment
 * in teleprompter surfaces (Hints demo here; Home popover once promoted).
 */
export function findVocabWords(
  text: string,
  words: readonly string[]
): { word: string; index: number }[] {
  const lowered = words.map((w) => w.toLowerCase());
  const matches: { word: string; index: number }[] = [];
  text.split(/\s+/).forEach((token, index) => {
    const clean = token.replace(/[^\p{L}\p{N}'-]/gu, "").toLowerCase();
    if (clean && lowered.includes(clean)) {
      matches.push({ word: clean, index });
    }
  });
  return matches;
}

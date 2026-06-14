import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

const VERBS = [
  "shabloinking",
  "flingle-ing",
  "goobering",
  "ruminating",
  "pondering my orb",
  "buffering charisma",
  "consulting the oracle",
  "reticulating splines",
  "summoning electrons",
  "polishing tokens",
  "vibing",
  "doing a think",
  "warming up the GPU hamsters",
  "inhaling context",
  "hallucinating responsibly",
  "aligning chakras",
  "booting the brain cell",
  "mining vibes",
  "checking the vibes",
];

const WARM = "\x1b[38;2;255;159;79m";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx: ExtensionContext) => {
    const CYCLES_PER_VERB = 3;
    const frames: string[] = [];
    for (let verbIdx = 0; verbIdx < VERBS.length; verbIdx++) {
      const verb = VERBS[verbIdx]!;
      for (let cycle = 0; cycle < CYCLES_PER_VERB; cycle++) {
        for (const spinner of SPINNER) {
          frames.push(`\x1b[2m${WARM}${spinner}\x1b[22m ${WARM}${verb} …\x1b[39m`);
        }
      }
    }

    ctx.ui.setWorkingMessage("");
    ctx.ui.setWorkingIndicator({
      frames,
      intervalMs: 100,
    });
  });
}

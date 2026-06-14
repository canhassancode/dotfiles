import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

export default function (pi: ExtensionAPI) {
  let tuiRef: { requestRender(): void } | undefined;

  const requestRender = () => tuiRef?.requestRender();

  let subagentCost = 0;

  pi.on("tool_result", (event) => {
    if (event.toolName !== "subagent") return;
    const details = event.details as { results?: Array<{ usage?: { cost?: number } }> } | undefined;
    if (details?.results) {
      for (const r of details.results) {
        subagentCost += r.usage?.cost ?? 0;
      }
    }
    requestRender();
  });

  pi.events.on("subagent:async-complete", (data: unknown) => {
    const payload = data as { results?: Array<{ modelAttempts?: Array<{ usage?: { cost?: number } }> }> } | undefined;
    if (payload?.results) {
      for (const r of payload.results) {
        const attempts = r.modelAttempts;
        if (attempts) {
          for (const a of attempts) {
            subagentCost += a.usage?.cost ?? 0;
          }
        }
      }
    }
    requestRender();
  });

  pi.on("session_start", async (_event, ctx) => {
    subagentCost = 0;
    ctx.ui.setFooter((tui, theme, footerData) => {
      tuiRef = tui;
      const unsub = footerData.onBranchChange(() => tui.requestRender());

      return {
        dispose: unsub,
        invalidate() {},
        render(width: number): string[] {
          let input = 0;
          let output = 0;
          let sessionCost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              const m = e.message as AssistantMessage;
              input += m.usage.input;
              output += m.usage.output;
              sessionCost += m.usage.cost.total;
            }
          }

          const usage = ctx.getContextUsage();
          const pct = usage?.percent ?? 0;
          const tokens = usage?.tokens ?? input;
          const pctInt = Math.round(pct);

          const model = ctx.model?.id || "—";
          const effort = pi.getThinkingLevel();

          const mcpStatus = footerData.getExtensionStatuses().get("mcp");
          const gitBranch = footerData.getGitBranch();

          const fmt = (n: number) => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`);

          const tokenColour =
            pctInt > 10 ? theme.fg("error", fmt(tokens)) : theme.fg("dim", fmt(tokens));
          const costText = subagentCost > 0
            ? `$${sessionCost.toFixed(2)}+$${subagentCost.toFixed(2)}`
            : `$${sessionCost.toFixed(2)}`;
          const left = [
            `${tokenColour} ${theme.fg("dim", `(${pctInt}%)`)}`,
            theme.fg("accent", `[ ${model} · ${effort} ]`),
            theme.fg("dim", costText),
          ].join(` ${theme.fg("muted", "·")} `);

          const cwdDisplay = (() => {
            const home = process.env.HOME;
            const c = ctx.cwd;
            if (home && c.startsWith(home)) return `~${c.slice(home.length)}`;
            return c;
          })();
          const rightLine1 = [
            theme.fg("dim", cwdDisplay),
            gitBranch ? theme.fg("dim", `⎇ ${gitBranch}`) : "",
          ].filter(Boolean).join(" ");
          const rightLine2 = mcpStatus ?? "";
          const hasLine2 = !!rightLine2;

          const results: string[] = [];

          if (rightLine1) {
            const gap = Math.max(1, width - visibleWidth(left) - visibleWidth(rightLine1));
            results.push(truncateToWidth(left + " ".repeat(gap) + rightLine1, width));
          } else {
            results.push(truncateToWidth(left, width));
          }

          if (hasLine2) {
            const gap = Math.max(0, width - visibleWidth(rightLine2));
            results.push(truncateToWidth(" ".repeat(gap) + rightLine2, width));
          }

          return results;
        },
      };
    });
  });

  pi.on("turn_start", () => requestRender());
  pi.on("turn_end", () => requestRender());
  pi.on("agent_end", () => requestRender());
  pi.on("thinking_level_select", () => requestRender());
  pi.on("model_select", () => requestRender());

  pi.on("session_shutdown", () => {
    tuiRef = undefined;
  });
}

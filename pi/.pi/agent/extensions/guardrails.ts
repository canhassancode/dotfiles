/**
 * Guardrails for interactive pi sessions running on the host filesystem.
 *
 * Policy model (edit the arrays below — they are the interface):
 *   denyBash      — bash commands blocked outright, no prompt, no override.
 *                   Reserved for the catastrophic-and-never-legitimate.
 *   confirmBash   — bash commands that require a Yes/No confirmation.
 *                   Blocked by default when there is no UI (print/headless mode),
 *                   so an accidental unattended run cannot wave them through.
 *   protectWrite  — paths the write/edit tools may not touch (clobber protection).
 *   protectRead   — paths the read tool may not open (keeps secrets out of context).
 *
 * Scope: this guards the agent's own tool calls only. Your `!`-prefixed commands
 * (user_bash) are deliberately untouched — those are yours to type.
 *
 * Honest limit: regex matching is a speed-bump, not isolation. It catches the
 * accidental and the obvious; a determined agent can evade it (`find -delete`,
 * base64, env indirection, cat-ing a secret via bash). Real isolation is the
 * sandbox's job — see README ("Going AFK").
 */

import { homedir } from "node:os";
import { basename, isAbsolute, join, resolve } from "node:path";
import { type ExtensionAPI, isToolCallEventType } from "@earendil-works/pi-coding-agent";

const denyBashPatterns: RegExp[] = [
	/(?=[\s\S]*\brm\b)(?=[\s\S]*(?:-[a-z]*r[a-z]*\b|--recursive))(?=[\s\S]*(?:\s\/(?:\s|$)|\s~(?:\s|$)|\$HOME|--no-preserve-root))/i,
	/:\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:/,
	/\bmkfs(?:\.\w+)?\b/i,
	/\bdd\b[\s\S]*\bof=\/dev\//i,
];

const confirmBashPatterns: RegExp[] = [
	/\brm\s+(?:-[a-z]*r[a-z]*|--recursive)/i,
	/\bfind\b[\s\S]*-delete\b/i,
	/\bxargs\b[\s\S]*\brm\b/i,
	/\bgit\s+push\b[\s\S]*(?:--force\b|--force-with-lease\b|\s-f\b)/i,
	/\bgit\s+reset\b[\s\S]*--hard\b/i,
	/\bgit\s+clean\b[\s\S]*-[a-z]*f/i,
	/\bsudo\b/i,
	/\b(?:chmod|chown)\b[\s\S]*(?:-[a-z]*R|\b777\b)/i,
	/\bcurl\b[\s\S]*(?:\s-d\b|--data\b|--data-\w+|\s-T\b|--upload-file\b|\s-F\b|--form\b)/i,
	/\bwget\b[\s\S]*(?:--post-data|--post-file)\b/i,
	/\bscp\b/i,
	/\b(?:nc|ncat)\b/i,
	/(?:curl|wget)\b[\s\S]*\|\s*(?:sudo\s+)?(?:ba)?sh\b/i,
];

const secretPrefixes: string[] = [
	join(homedir(), ".ssh"),
	join(homedir(), ".aws"),
	join(homedir(), ".gnupg"),
	join(homedir(), ".pi", "agent", "auth.json"),
];

const secretBasenamePatterns: RegExp[] = [/^\.env(?:\..+|rc)?$/i, /\.pem$/i, /\.key$/i];

function resolveToolPath(rawPath: string, cwd: string): string {
	let path = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	if (path === "~") path = homedir();
	else if (path.startsWith("~/")) path = join(homedir(), path.slice(2));
	if (!isAbsolute(path)) path = resolve(cwd, path);
	return path;
}

function isSecretPath(absolutePath: string): boolean {
	if (secretPrefixes.some((prefix) => absolutePath === prefix || absolutePath.startsWith(`${prefix}/`))) {
		return true;
	}
	const name = basename(absolutePath);
	return secretBasenamePatterns.some((pattern) => pattern.test(name));
}

type Block = { block: true; reason: string };

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx): Promise<Block | undefined> => {
		if (isToolCallEventType("bash", event)) {
			const command = event.input.command;

			const denied = denyBashPatterns.find((pattern) => pattern.test(command));
			if (denied) {
				if (ctx.hasUI) ctx.ui.notify(`Blocked (deny-list): ${command}`, "error");
				return { block: true, reason: "Command is on the hard-deny list (catastrophic, no override)" };
			}

			const flagged = confirmBashPatterns.find((pattern) => pattern.test(command));
			if (flagged) {
				if (!ctx.hasUI) {
					return { block: true, reason: "Flagged command blocked (no UI to confirm)" };
				}
				const ok = await ctx.ui.confirm("⚠️ Guardrail — run this command?", command);
				if (!ok) {
					return { block: true, reason: "Blocked by user" };
				}
			}
			return undefined;
		}

		if (isToolCallEventType("read", event)) {
			const target = resolveToolPath(event.input.path, ctx.cwd);
			if (isSecretPath(target)) {
				if (ctx.hasUI) ctx.ui.notify(`Blocked read of protected path: ${event.input.path}`, "warning");
				return { block: true, reason: `Reading "${event.input.path}" is blocked (secret path)` };
			}
			return undefined;
		}

		if (isToolCallEventType("write", event) || isToolCallEventType("edit", event)) {
			const target = resolveToolPath(event.input.path, ctx.cwd);
			if (target.includes("/.git/") || isSecretPath(target)) {
				if (ctx.hasUI) ctx.ui.notify(`Blocked write to protected path: ${event.input.path}`, "warning");
				return { block: true, reason: `Writing "${event.input.path}" is blocked (protected path)` };
			}
			return undefined;
		}

		return undefined;
	});
}

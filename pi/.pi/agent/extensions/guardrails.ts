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
	/\bgit\s+push\b/i,
	/\bgit\s+commit\b/i,
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

const guardrailExtensions: string[] = [
	join(homedir(), ".pi", "agent", "extensions", "guardrails.ts"),
];

const isExtensionGuardrail = (absolutePath: string): boolean =>
	guardrailExtensions.some((guardPath) => absolutePath === guardPath);

const secretPrefixes: string[] = [
	join(homedir(), ".ssh"),
	join(homedir(), ".aws"),
	join(homedir(), ".gnupg"),
	join(homedir(), ".pi", "agent", "auth.json"),
];

const secretBasenamePatterns: RegExp[] = [/^\.env(?:\..+|rc)?$/i, /\.pem$/i, /\.key$/i];

const maxMcpSqlCost = 100_000;
const writeSqlPattern =
	/\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|MERGE|REPLACE|UPSERT|CALL|DO|COPY|VACUUM|REINDEX|REFRESH|COMMENT|LOCK|SET|COMMIT|ROLLBACK|SAVEPOINT|NOTIFY)\b/i;
const largeTableSeqScanPatterns: RegExp[] = [/\bSeq Scan on (?:\w+\.)?t2060\b/i, /\bSeq Scan on (?:\w+\.)?t2061\b/i];

const explainedMcpSql = new Map<string, { cost: number; explainedAt: number }>();

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

type JsonRecord = Record<string, unknown>;
type McpToolInput = JsonRecord & { tool?: string; args?: string };
type McpSqlOperation = { kind: "explain" | "execute"; scope: string };
type SqlSafety = { ok: true; normalisedSql: string } | { ok: false; reason: string };
type Block = { block: true; reason: string };
type ToolResultPatch = { content?: Array<{ type: "text"; text: string }>; details?: unknown; isError?: boolean };

function isRecord(value: unknown): value is JsonRecord {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stripSqlComments(sql: string): string {
	return sql.replace(/--[^\n\r]*/g, " ").replace(/\/\*[\s\S]*?\*\//g, " ");
}

function normaliseSql(sql: string): string {
	return stripSqlComments(sql).replace(/;\s*$/g, "").replace(/\s+/g, " ").trim().toLowerCase();
}

function checkReadOnlySql(sql: string): SqlSafety {
	const scan = stripSqlComments(sql).replace(/\s+/g, " ").trim();
	const firstWord = scan.match(/[a-zA-Z]+/)?.[0].toUpperCase();
	if (!firstWord) return { ok: false, reason: "SQL is empty" };
	if (!new Set(["SELECT", "EXPLAIN", "SHOW", "VALUES", "WITH", "TABLE"]).has(firstWord)) {
		return { ok: false, reason: "SQL must be read-only" };
	}
	if (/\bEXPLAIN\b[\s\S]*\bANALYZE\b/i.test(scan)) {
		return { ok: false, reason: "EXPLAIN ANALYZE is blocked because it executes the query" };
	}
	if (writeSqlPattern.test(scan)) {
		return { ok: false, reason: "SQL contains a write/DDL keyword" };
	}
	const normalisedSql = normaliseSql(sql);
	if (!normalisedSql) return { ok: false, reason: "SQL is empty" };
	return { ok: true, normalisedSql };
}

function parseMcpArgs(rawArgs: unknown): JsonRecord | undefined {
	if (typeof rawArgs !== "string") return undefined;
	try {
		const parsed: unknown = JSON.parse(rawArgs);
		return isRecord(parsed) ? parsed : undefined;
	} catch {
		return undefined;
	}
}

function extractSql(args: JsonRecord): string | undefined {
	const candidate = args.sql ?? args.query ?? args.statement;
	return typeof candidate === "string" ? candidate : undefined;
}

function requestsExplainAnalyse(args: JsonRecord): boolean {
	return args.analyze === true || args.analyse === true;
}

function getMcpSqlOperation(tool: string): McpSqlOperation | undefined {
	if (tool.endsWith("_explain_query")) return { kind: "explain", scope: tool.slice(0, -"_explain_query".length) };
	if (tool.endsWith("_execute_sql")) return { kind: "execute", scope: tool.slice(0, -"_execute_sql".length) };
	if (tool.endsWith("_execute_query")) return { kind: "execute", scope: tool.slice(0, -"_execute_query".length) };
	if (tool.endsWith("_query")) return { kind: "execute", scope: tool.slice(0, -"_query".length) };
	return undefined;
}

function explainedSqlKey(operation: McpSqlOperation, normalisedSql: string): string {
	return `${operation.scope}\u0000${normalisedSql}`;
}

function getTextFromUnknown(value: unknown): string {
	if (typeof value === "string") return value;
	if (value === undefined || value === null) return "";
	try {
		return JSON.stringify(value) ?? "";
	} catch {
		return "";
	}
}

function getToolResultText(content: ReadonlyArray<{ type?: string; text?: string }>, details: unknown): string {
	const contentText = content
		.map((item) => (item.type === "text" && typeof item.text === "string" ? item.text : ""))
		.filter(Boolean)
		.join("\n");
	const detailsText = getTextFromUnknown(details);
	return [contentText, detailsText].filter(Boolean).join("\n");
}

function extractMaxExplainCost(text: string): number | undefined {
	const patterns: RegExp[] = [/\bCost:\s*([0-9]+(?:\.[0-9]+)?)\.\.([0-9]+(?:\.[0-9]+)?)/gi, /\bcost=([0-9]+(?:\.[0-9]+)?)\.\.([0-9]+(?:\.[0-9]+)?)/gi];
	let maxCost: number | undefined;
	for (const pattern of patterns) {
		for (const match of text.matchAll(pattern)) {
			const parsed = Number.parseFloat(match[2]);
			if (Number.isFinite(parsed) && (maxCost === undefined || parsed > maxCost)) maxCost = parsed;
		}
	}
	return maxCost;
}

function findBlockedSeqScan(text: string): string | undefined {
	return largeTableSeqScanPatterns.find((pattern) => pattern.test(text))?.source;
}

function blockedSqlResult(message: string, existingText: string): ToolResultPatch {
	return {
		isError: true,
		content: [{ type: "text" as const, text: [existingText, `Guardrail: ${message}`].filter(Boolean).join("\n\n") }],
	};
}

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

		if (isToolCallEventType<"mcp", McpToolInput>("mcp", event)) {
			const tool = typeof event.input.tool === "string" ? event.input.tool : undefined;
			if (!tool) return undefined;
			const operation = getMcpSqlOperation(tool);
			if (!operation) return undefined;

			const args = parseMcpArgs(event.input.args);
			if (!args) return { block: true, reason: `MCP SQL tool "${tool}" is missing parseable JSON args` };

			const sql = extractSql(args);
			if (!sql) return { block: true, reason: `MCP SQL tool "${tool}" is missing a sql/query/statement argument` };

			const safety = checkReadOnlySql(sql);
			if (!safety.ok) return { block: true, reason: safety.reason };

			if (operation.kind === "explain") {
				if (requestsExplainAnalyse(args)) {
					return { block: true, reason: "MCP explain_query must use analyze=false" };
				}
				return undefined;
			}

			const explained = explainedMcpSql.get(explainedSqlKey(operation, safety.normalisedSql));
			if (!explained) {
				return { block: true, reason: `MCP execute_sql blocked: run ${operation.scope}_explain_query first` };
			}
			if (explained.cost > maxMcpSqlCost) {
				return { block: true, reason: `MCP execute_sql blocked: explained cost ${explained.cost} exceeds ${maxMcpSqlCost}` };
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
			if (isExtensionGuardrail(target)) {
				if (!ctx.hasUI) {
					return { block: true, reason: `Writing "${event.input.path}" is blocked — guardrails cannot be edited without UI` };
				}
				const ok = await ctx.ui.confirm("⚠️ Guardrail — edit guardrails.ts?", `Editing ${event.input.path} bypasses agent guardrails. Allow?`);
				if (!ok) {
					return { block: true, reason: "Blocked by user" };
				}
			}
			return undefined;
		}

		return undefined;
	});

	pi.on("tool_result", (event): ToolResultPatch | undefined => {
		if (event.toolName !== "mcp") return undefined;
		const tool = typeof event.input.tool === "string" ? event.input.tool : undefined;
		if (!tool) return undefined;
		const operation = getMcpSqlOperation(tool);
		if (!operation || operation.kind !== "explain") return undefined;

		const args = parseMcpArgs(event.input.args);
		if (!args) return undefined;
		const sql = extractSql(args);
		if (!sql) return undefined;
		const safety = checkReadOnlySql(sql);
		if (!safety.ok) return undefined;
		if (event.isError) return undefined;

		const text = getToolResultText(event.content, event.details);
		const cost = extractMaxExplainCost(text);
		if (cost === undefined) {
			return blockedSqlResult("Could not parse EXPLAIN cost; execute_sql will remain blocked", text);
		}
		if (cost > maxMcpSqlCost) {
			return blockedSqlResult(`EXPLAIN cost ${cost} exceeds ${maxMcpSqlCost}; execute_sql will remain blocked`, text);
		}
		const blockedSeqScan = findBlockedSeqScan(text);
		if (blockedSeqScan) {
			return blockedSqlResult(`EXPLAIN contains a blocked sequential scan (${blockedSeqScan}); execute_sql will remain blocked`, text);
		}

		explainedMcpSql.set(explainedSqlKey(operation, safety.normalisedSql), { cost, explainedAt: Date.now() });
		return undefined;
	});
}

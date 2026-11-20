import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

const worker = "Complete the next runnable task and record its verification.";
const command = `/loop 20 --until 'grep -Fq -- "- [ ] " .omp/tasks/*.md; test "$?" -eq 1' ${worker}`;

interface Card {
	id: string;
	complete: boolean;
	blocked: boolean;
	dependencies: string[];
}

async function preflight(cwd: string): Promise<string | undefined> {
	const directory = join(cwd, ".omp", "tasks");
	const files = await readdir(directory).catch((error: NodeJS.ErrnoException) => {
		if (error.code === "ENOENT") return [];
		throw error;
	});
	const ledgers = files.filter(name => !name.startsWith(".") && name.endsWith(".md")).sort();
	if (ledgers.length === 0) return "No .omp/tasks/*.md ledger found.";

	const cards: Card[] = [];
	for (const name of ledgers) {
		const contents = await readFile(join(directory, name), "utf8");
		let card: Card | undefined;
		for (const line of contents.split(/\r?\n/)) {
			const checkbox = /^- \[([ xX])\] (.*)$/.exec(line);
			if (checkbox) {
				const id = /^\*\*([\w.-]+)(?=\s|\*\*)/.exec(checkbox[2])?.[1];
				if (!id) return `Cannot preflight ${name}: task cards must start with a bold task ID.`;
				card = { id, complete: checkbox[1] !== " ", blocked: /\bblocked\b/i.test(checkbox[2]), dependencies: [] };
				cards.push(card);
			} else if (line && !/^\s/.test(line)) {
				card = undefined;
			} else if (card) {
				const field = /^\s+- (Status|Depends on):\s*(.*)$/i.exec(line);
				if (field?.[1].toLowerCase() === "status") card.blocked ||= /^\**blocked\b/i.test(field[2]);
				if (field?.[1].toLowerCase() === "depends on") {
					card.dependencies = field[2].replaceAll("`", "").split(/[\s,]+/).filter(id => id && id !== "none");
				}
			}
		}
	}
	const known = new Set(cards.map(card => card.id));
	const completed = new Set(cards.filter(card => card.complete).map(card => card.id));
	const pending = cards.filter(card => !card.complete);
	if (pending.length === 0) return "No unchecked tasks.";
	if (pending.some(card => !card.blocked && card.dependencies.every(id => completed.has(id)))) return;
	const reasons = pending.map(card => {
		if (card.blocked) return `${card.id} is marked blocked`;
		const waiting = card.dependencies.filter(id => !completed.has(id));
		return `${card.id} needs ${waiting.map(id => known.has(id) ? id : `${id} (missing)`).join(", ")}`;
	});
	return `No runnable tasks: ${reasons.join("; ")}.`;
}

export default function (pi: ExtensionAPI) {
	// The interactive input hook runs before OMP dispatches built-in slash commands.
	pi.on("input", async (event, ctx) => {
		if (event.source !== "interactive" || ctx.mode !== "tui" || event.text !== "/skill:build" || event.images?.length) return;
		let refusal: string | undefined;
		try {
			if (!ctx.isIdle() || ctx.hasPendingMessages()) refusal = "Wait for the current turn before starting a build.";
			else if (ctx.sessionModes?.getState().loop.status !== "inactive") refusal = "Exit the current loop before starting a build.";
			else refusal = await preflight(ctx.cwd);
		} catch (error) {
			refusal = `Cannot read task ledger: ${error instanceof Error ? error.message : String(error)}`;
		}
		if (refusal) {
			ctx.ui.notify(refusal, "warning");
			return { handled: true };
		}
		return { text: command };
	});

	pi.on("before_agent_start", event => {
		if (event.prompt !== worker) return;
		return { systemPrompt: [...event.systemPrompt, "Read skill://build and apply its One iteration section to this turn. Do not start a new loop."] };
	});
}

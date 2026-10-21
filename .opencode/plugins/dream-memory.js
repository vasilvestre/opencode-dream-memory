// dream-memory — OpenCode plugin (v2).
//
// Injects shared memory plus the memory of the current project into the system
// prompt on every agent-loop LLM request, so it survives context compaction.
// AGENTS.md does not: it is summarized away when a session gets long.
//
// Files are read on each request, never cached, so a nightly rewrite shows up in
// the next turn. A missing or unreadable file contributes nothing: this hook
// runs on every request, and throwing here would break all of them.
//
// Layout under $DREAM_HOME (default ~/dreams):
//   MEMORY.md                facts true in every project
//   projects/<name>/MEMORY.md facts about one project
//
// <name> is the base name of the project directory, the same tag dream-corpus
// writes into the corpus and dream-deep uses as a file name.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const HOME = process.env.DREAM_HOME || path.join(os.homedir(), 'dreams');

// Cut points, not writer budgets: dream-deep is told to stay below them (see
// dream/agents/dream-deep.md). Shared memory is injected into every session,
// so its share is the smaller one.
const ROOT_MAX = 1000;
const PROJECT_MAX = 3000;

const HEADER =
  'Cross-session memory, written by a nightly pass from earlier sessions and possibly stale. ' +
  'Trust the repository and the live system over this block.';

// Drop the title, cut on a line boundary, and say what was dropped. A hard byte
// cut would drop a fact without telling the model.
function read(file, max, label) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
  const body = text
    .split('\n')
    .filter((line) => !line.startsWith('# '))
    .join('\n')
    .trim();
  if (!body) return '';
  if (body.length <= max) return body;
  const cut = body.lastIndexOf('\n', max);
  const kept = cut > 0 ? cut : max;
  return (
    `${body.slice(0, kept)}\n` +
    `[${label} truncated: ${body.length - kept} characters dropped, ` +
    `prune ${path.relative(HOME, file)} to fit]`
  );
}

function memoryBlock(directory) {
  const parts = [read(path.join(HOME, 'MEMORY.md'), ROOT_MAX, 'memory')];
  const name = path.basename(directory || '');
  if (name && name !== '.' && name !== '..' && !name.startsWith('.')) {
    const body = read(path.join(HOME, 'projects', name, 'MEMORY.md'), PROJECT_MAX, `${name} memory`);
    if (body) parts.push(`Project memory (${name}):\n${body}`);
  }
  const body = parts.filter(Boolean).join('\n\n');
  return body ? `${HEADER}\n\n${body}` : '';
}

export default {
  id: 'vasilvestre.opencode-dream-memory',
  async setup(ctx) {
    // OpenCode creates one plugin instance per project location, so the project
    // is known before a session exists. Worktrees share their canonical path.
    const location = ctx.location ?? {};
    const directory =
      location.project?.canonical || location.project?.directory || location.directory;
    await ctx.session.hook('context', (event) => {
      const block = memoryBlock(directory);
      if (block) event.system.push({ type: 'text', text: block });
    });
  },
};

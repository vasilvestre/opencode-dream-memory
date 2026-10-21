// dream-memory — OpenCode plugin (v2).
//
// Injects the user's cross-session memory file into the system prompt on every
// agent-loop LLM request, so it survives context compaction. AGENTS.md does
// not: it is summarized away when a session gets long.
//
// The file is read on each request, never cached, so a nightly rewrite shows up
// in the next turn. A missing or unreadable file injects nothing: this hook runs
// on every request, and throwing here would break all of them.
//
// Path: $DREAM_MEMORY_FILE, default ~/dreams/MEMORY.md.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const FILE =
  process.env.DREAM_MEMORY_FILE || path.join(os.homedir(), 'dreams', 'MEMORY.md');

// Memory grows every night. Past this size, the injected block costs more than
// it teaches, so the tail is dropped and the model is told so.
const MAX_CHARS = 4000;

const HEADER =
  'Cross-session memory, written by a nightly pass from earlier sessions and possibly stale. ' +
  'Trust the repository and the live system over this block.';

function memoryBlock() {
  let text;
  try {
    text = fs.readFileSync(FILE, 'utf8');
  } catch {
    return '';
  }
  // Drop the top-level title: the injected block supplies its own framing.
  const body = text
    .split('\n')
    .filter((line) => !line.startsWith('# '))
    .join('\n')
    .trim();
  if (!body) return '';
  const over = body.length - MAX_CHARS;
  // Cut on a line boundary, never mid-line: a hard byte cut drops whatever
  // project section happens to sit at the end without saying so.
  const cut = over > 0 ? body.lastIndexOf('\n', MAX_CHARS) : -1;
  const clipped =
    over > 0
      ? `${cut > 0 ? body.slice(0, cut) : body.slice(0, MAX_CHARS)}
[memory truncated: ${over} characters dropped, prune MEMORY.md to fit]`
      : body;
  return `${HEADER}\n\n${clipped}`;
}

export default {
  id: 'vasilvestre.opencode-dream-memory',
  async setup(ctx) {
    await ctx.session.hook('context', (event) => {
      const block = memoryBlock();
      if (block) event.system.push({ type: 'text', text: block });
    });
  },
};

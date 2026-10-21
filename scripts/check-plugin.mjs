// Smoke test: the hook registers, injects when the file exists, injects nothing
// when it does not, and truncates an oversized file.
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dream-memory-'));
const file = path.join(dir, 'MEMORY.md');
process.env.DREAM_MEMORY_FILE = file;

const { default: plugin } = await import('../.opencode/plugins/dream-memory.js');

assert.equal(plugin.id, 'vasilvestre.opencode-dream-memory');

let handler;
await plugin.setup({
  session: {
    hook: async (name, fn) => {
      assert.equal(name, 'context');
      handler = fn;
    },
  },
});
assert.equal(typeof handler, 'function', 'setup registers a context hook');

const absent = { system: [] };
handler(absent);
assert.equal(absent.system.length, 0, 'a missing file injects nothing');

fs.writeFileSync(file, '# Memory\n\n## homelab\n- ssh ControlMaster is configured\n');
const present = { system: [] };
handler(present);
assert.equal(present.system.length, 1, 'an existing file injects one block');
assert.match(present.system[0].text, /ControlMaster/);
assert.ok(!present.system[0].text.includes('# Memory'), 'the top-level title is dropped');

fs.writeFileSync(file, 'x'.repeat(5000));
const big = { system: [] };
handler(big);
assert.match(big.system[0].text, /truncated/, 'an oversized file is truncated');

fs.rmSync(dir, { recursive: true, force: true });
console.log('ok: 5 assertions');

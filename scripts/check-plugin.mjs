// Smoke test: shared and per-project memory are injected separately, a missing
// file contributes nothing, and each part is clipped on its own.
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dream-memory-'));
process.env.DREAM_HOME = home;

const { default: plugin } = await import('../.opencode/plugins/dream-memory.js');

assert.equal(plugin.id, 'vasilvestre.opencode-dream-memory');

// The plugin only reads the base name of the project directory.
async function inject(directory) {
  let handler;
  await plugin.setup({
    location: { directory, project: { canonical: directory } },
    session: {
      hook: async (name, fn) => {
        assert.equal(name, 'context');
        handler = fn;
      },
    },
  });
  assert.equal(typeof handler, 'function', 'setup registers a context hook');
  const event = { system: [] };
  handler(event);
  return event.system;
}

const root = path.join(home, 'MEMORY.md');
const project = (name) => {
  const dir = path.join(home, 'projects', name);
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, 'MEMORY.md');
};

assert.equal((await inject('/work/a')).length, 0, 'missing files inject nothing');

fs.writeFileSync(root, '# Shared\n\n## Global\n- rules live in instructions files\n');
let blocks = await inject('/work/a');
assert.equal(blocks.length, 1, 'shared memory alone injects one block');
assert.match(blocks[0].text, /instructions files/);
assert.ok(!blocks[0].text.includes('Project memory'), 'no project section without a file');
assert.ok(!blocks[0].text.includes('# Shared'), 'the top-level title is dropped');

fs.writeFileSync(project('a'), '# a\n\n- project a fact\n');
fs.writeFileSync(project('b'), '# b\n\n- project b fact\n');

blocks = await inject('/work/a');
assert.equal(blocks.length, 1);
assert.match(blocks[0].text, /instructions files[\s\S]*Project memory \(a\):\n- project a fact/, 'shared memory comes first, then the current project');
assert.ok(!blocks[0].text.includes('project b fact'), "another project's memory stays out");
assert.ok(!blocks[0].text.includes('# a'), 'the project title is dropped');

blocks = await inject('/work/b');
assert.match(blocks[0].text, /project b fact/, 'the block follows the project');
assert.ok(!blocks[0].text.includes('project a fact'));

fs.writeFileSync(project('a'), `# a\n\n${'x'.repeat(4000)}\n- tail fact\n`);
blocks = await inject('/work/a');
assert.match(blocks[0].text, /\[a memory truncated: \d+ characters dropped/, 'an oversized project file is truncated');
assert.ok(!blocks[0].text.includes('tail fact'), 'the tail is what gets dropped');
assert.ok(blocks[0].text.length < 200 + 1000 + 3000 + 300, 'the whole block stays bounded');

fs.rmSync(home, { recursive: true, force: true });
console.log('ok: plugin checks');

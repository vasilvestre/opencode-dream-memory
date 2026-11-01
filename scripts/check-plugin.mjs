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

// The plugin only reads the base name of the project directory. It registers
// one handler per hook, so the harness keeps them by name.
async function inject(directory, hook = 'context') {
  const handlers = {};
  await plugin.setup({
    location: { directory, project: { canonical: directory } },
    session: {
      hook: async (name, fn) => {
        handlers[name] = fn;
      },
    },
  });
  assert.deepEqual(Object.keys(handlers).sort(), ['compaction', 'context'], 'setup registers one context hook and one compaction hook');
  const event = { system: [] };
  handlers[hook](event);
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

// Compaction gets the same memory as the agent loop, with the same budget.
fs.writeFileSync(project('a'), '# a\n\n- project a fact\n');
const context = await inject('/work/a', 'context');
const compaction = await inject('/work/a', 'compaction');
assert.deepEqual(compaction, context, 'the compaction hook injects the same block as the context hook');
assert.match(compaction[0].text, /project a fact/);

// The summary is the model's job. The hook only adds context.
const event = { system: [], result: undefined };
const handlers = {};
await plugin.setup({
  location: { directory: '/work/a', project: { canonical: '/work/a' } },
  session: { hook: async (name, fn) => (handlers[name] = fn) },
});
handlers.compaction(event);
assert.equal(event.result, undefined, 'the compaction hook never replaces the summary');

// A missing memory file still adds nothing, and a broken one does not throw.
fs.rmSync(root);
fs.rmSync(path.join(home, 'projects'), { recursive: true, force: true });
assert.deepEqual(await inject('/work/a', 'compaction'), [], 'missing files inject nothing into compaction');
const broken = project('a');
fs.rmSync(broken, { force: true });
fs.mkdirSync(broken);
assert.deepEqual(await inject('/work/a', 'compaction'), [], 'an unreadable file injects nothing and does not throw');

fs.rmSync(home, { recursive: true, force: true });
console.log('ok: plugin checks');

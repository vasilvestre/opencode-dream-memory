# opencode-dream-memory

Injects a cross-session memory file into the system prompt of every OpenCode
request, so the memory survives context compaction.

`AGENTS.md` does not survive it. When a session gets long, OpenCode summarizes
the conversation, and the instructions file is summarized away with it. A plugin
hook runs on every agent-loop request, so the same block is re-sent each turn.

## Install

```bash
opencode plugin add @vasilvestre/opencode-dream-memory
```

Or point at a local checkout in `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "plugins": ["/home/you/code/opencode-dream-memory/.opencode/plugins/dream-memory.js"],
}
```

## What it injects

The content of `~/dreams/MEMORY.md`, without its top-level title, under a header
that says the file is written by a nightly pass and may be stale.

Override the path with `DREAM_MEMORY_FILE`:

```bash
DREAM_MEMORY_FILE=~/notes/agent-memory.md
```

Nothing is injected when the file is missing, empty, or unreadable. The hook runs
on every request, so it fails silent rather than breaking the session.

## Limits

- 4 000 characters. Past that, the tail is dropped and the block says so. A
  memory file that grows every night would otherwise cost more tokens each week.
- The file is read on each request, never cached, so a rewrite shows up in the
  next turn at the cost of one small read.
- The whole file is injected, not only the section for the current project. The
  hook event carries no working directory, and guessing one from the server
  process would be wrong.

## Test

```bash
npm test
```

Five assertions: the hook registers, a missing file injects nothing, an existing
file injects one block, the title is dropped, an oversized file is truncated.

## The dream job

The repo also ships the nightly job that writes the memory file it injects.

```bash
sh install.sh            # install, timer stays disabled
sh install.sh --enable   # install, then enable and start the 04:30 timer
```

It copies three scripts into `~/.local/bin`, two agents into
`~/.config/opencode/agents`, two systemd user units, and creates `~/dreams`
with `MEMORY.md`, `DREAMS.md` and an empty project list. It never overwrites
`MEMORY.md`, `DREAMS.md` or `dream-projects`, so it is safe to re-run.

Enable the timer only after reading a manual run: `dream` spends two agent runs
per invocation. The install script leaves it off on purpose, because a
curl-to-shell install cannot ask a question and a nightly job that spends money
should never start by default.

| Command | What it does |
|---|---|
| `dream` | builds the corpus, then the light and deep passes |
| `dream-corpus` | only the corpus, no model, no cost |
| `dream-status` | one screen of state, read-only |

Requirements: `opencode` and `jq` on `PATH`, plus systemd for the timer.

## Licence

MIT.

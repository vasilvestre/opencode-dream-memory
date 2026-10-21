# opencode-dream-memory

Two pieces that give an OpenCode agent memory across sessions:

1. **A plugin** that injects a memory file into the system prompt of every
   request, so the memory survives context compaction.
2. **A nightly job** that writes that file from past sessions.

`AGENTS.md` does not survive compaction. When a session gets long, OpenCode
summarizes the conversation and the instructions file goes with it. A plugin
hook runs on every agent-loop request, so the same block is re-sent each turn.

## Install the plugin

Until it is published on npm, use the discovery directory. Do **not** list the
file path in `plugins` in `opencode.jsonc`: OpenCode warns that a configured
plugin path must be a directory, and a path entry placed next to a discovered
copy loads the plugin twice. Two instances with the same id make OpenCode drop
every plugin.

```bash
mkdir -p ~/.config/opencode/plugins
ln -sf "$PWD/.opencode/plugins/dream-memory.js" ~/.config/opencode/plugins/dream-memory.js
```

Restart the service to load it: `opencode service restart`.

## Install the dream job

```bash
sh install.sh            # install, timer stays disabled
sh install.sh --enable   # install, then enable and start the 04:30 timer
```

`install.sh` copies three scripts into `$BIN_DIR` (default `~/.local/bin`), two
agents into `~/.config/opencode/agents`, two systemd user units, and creates
`~/dreams` with `MEMORY.md`, `DREAMS.md` and an empty project list. It rewrites
the unit's `ExecStart` to the chosen `BIN_DIR`, and it never overwrites
`MEMORY.md`, `DREAMS.md` or `dream-projects`.

Enable the timer only after reading a manual run. `dream` spends two agent runs
per invocation, and the script leaves the timer off on purpose: a curl-to-shell
install cannot ask a question, and a nightly job that spends money must not
start by default.

If `opencode` is not on the systemd default `PATH`, write its directory to
`~/.config/dream.env`, which the unit reads when present:

```bash
echo 'PATH=/opt/opencode/bin:/usr/local/bin:/usr/bin:/bin' > ~/.config/dream.env
```

## What the plugin injects

The content of `~/dreams/MEMORY.md`, without its top-level title, under a header
saying the file comes from a nightly pass and may be stale. Override the path:

```bash
DREAM_MEMORY_FILE=~/notes/agent-memory.md
```

Nothing is injected when the file is missing, empty or unreadable. The hook runs
on every request, so it fails silent instead of breaking the session.

## Privacy

The corpus is built from your real sessions. Each message contributes up to 400
characters, and the whole corpus is sent to whichever model `dream` runs.

- Inspect `~/dreams/.dreams/session-corpus/<date>.txt` before enabling the
  timer, and again after any session where you pasted something sensitive.
- `opencode session export --sanitize` is not an option: it replaces every
  message with `[redacted:text:...]`, which makes the corpus useless.
- For a private setup, set a local model in `~/.config/opencode/dream-models`
  (see below), or set `DREAM_HOME` on an encrypted volume and skip the timer.
- The dream job is instructed never to write secrets into `MEMORY.md`, and the
  plugin injects that file into every request. A secret that reaches it is
  re-sent on every turn.

### Which model runs each stage

`dream` reads `~/.config/opencode/dream-models`, one line per stage. The first
word is the stage, the rest is a list of models:

```
light opencode-go/deepseek-v4.1-flash
deep  opencode-go/deepseek-v4-pro
```

The script tries the models left to right and keeps the first that runs, so a
fallback after the first choice is fine. A stage with no line uses the script's
own defaults: `deepseek-v4.1-flash` for `light`, which reads the raw session
text, and `deepseek-v4-pro` for `deep`, which only sees staged candidates. Both
are paid models on purpose. A free model may train on its input, and a nightly
job that silently falls back to one sends your session text there.

Do not set the model in `dream/agents/*.md` for the job: `dream` passes `-m`,
and that flag beats the agent's pinned model. Override the file path with
`DREAM_MODELS`.

## Limits

- 4 000 characters. Past that, the tail is dropped on a line boundary and the
  block says how much was dropped. `dream-deep` is told to keep the file under
  3 500 characters and to delete older entries to stay there, because a memory
  file that only grows eventually loses its own tail.
- The whole file is injected, not only the section for the current project. The
  hook event carries no working directory, and guessing one from the server
  process would be wrong.
- The file is read on each request, never cached, so a nightly rewrite shows up
  in the next turn at the cost of one small read.

## Commands

| Command | What it does |
|---|---|
| `dream` | builds the corpus, then the light and deep passes |
| `dream-corpus` | only the corpus, no model, no cost |
| `dream-status` | one screen of state, read-only |

Requirements: `opencode` and `jq` on `PATH`, plus systemd for the timer.

## Test

```bash
npm test
```

Five assertions: the hook registers, a missing file injects nothing, an existing
file injects one block, the title is dropped, an oversized file is truncated.

## Licence

MIT.

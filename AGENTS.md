# AGENTS.md — maintainer instructions

Instructions for agents working in this repository.

## What this repo ships

Two things that share one purpose: giving an agent memory that survives a
session.

1. **The injection plugin** (`.opencode/plugins/dream-memory.js`) pushes a
   memory file into the system prompt on every LLM request.
2. **The dream job** (`dream/`) writes those memory files nightly from past
   OpenCode sessions.

Neither depends on the other at runtime, but they are useless apart: the job
writes what the plugin reads.

## Layout

| Path | Role |
|---|---|
| `.opencode/plugins/dream-memory.js` | the hook, loaded by OpenCode |
| `dream/dream` | runs corpus, then the light and deep passes |
| `dream/dream-corpus` | builds the corpus, no model, no cost |
| `dream/dream-status` | one screen of state, read-only |
| `dream/agents/dream-*.md` | the two agent prompts, permissions and model pin |
| `dream/systemd/` | the 04:30 timer |
| `scripts/check-plugin.mjs` | assertions on the hook: scope, isolation, budget |
| `scripts/check-corpus.sh` | corpus filter, redaction, torn export, preimage |
| `install.sh` | installs the plugin and the job; downloads the archive when piped |

## Hard rules

- **The hook must fail silent.** It runs on every request; an exception there
  breaks every request. Missing, empty or unreadable file means inject nothing.
- **The plugin id must stay unique.** OpenCode drops *every* plugin when two
  instances claim the same id, so a second copy of this file must not load.
- **`memoryBlock()` stays bounded.** Each part is cut on its own: shared memory
  at 1 000 characters, a project file at 3 000. Cuts land on a line boundary and
  report the dropped count. The sum is bounded by construction; never let one
  part borrow another's budget.
- **The writer knows the reader's cuts.** `dream-deep` keeps `MEMORY.md` under
  900 characters and `projects/<name>/MEMORY.md` under 2 800. Change a cut and
  its budget together, in `dream-memory.js`, `dream-deep.md` and the README, or
  the tail of a file disappears silently at 04:30.
- **One name per project.** `dream-corpus` tags a line with the base name of the
  project directory, the plugin reads `projects/<base name>/MEMORY.md`, and
  `dream` seeds those files from `dream-projects`. Changing one of the three
  naming schemes breaks the chain without an error.
- **The plugin file must stay tracked.** A global `~/.gitignore` entry for
  `.opencode` hides it, so a plain `git add -A` never stages it. After a fresh
  clone, `git ls-files .opencode` must list the plugin.
- **`opencode run --agent` does not apply the agent's `model`.** Only an
  explicit `-m` does. Never remove the `-m` from `dream`.
- **The corpus never ingests the dream's own sessions.** They are output, not
  source; `dream-corpus` skips any session whose agent starts with `dream-`,
  and redacts labelled secrets on the way in.
- **The memory file holds no secrets.** The corpus comes from real sessions; a
  password pasted in a chat must never reach `MEMORY.md`.
- **The install script never overwrites user data.** `MEMORY.md`, `DREAMS.md`,
  `dream-projects` and every `projects/<name>/MEMORY.md` are created only when
  missing. So is `dream-models`.
- **The timer stays off by default.** `--enable` exists, and a one-line install
  must not start a job that spends money.
- **`install.sh` must stay pipeable.** `curl ... | sh` gives it no directory, so
  `$ROOT/dream` is missing and it downloads the archive into a temp directory
  instead. Keep the `trap` that removes that directory, and keep the plugin copy
  skipping an existing symlink.

## Before you commit

```bash
git add -f .opencode/plugins/dream-memory.js   # a global .gitignore hides .opencode
npm test              # hook assertions, then the corpus checks
sh -n install.sh      # installer syntax
node --check .opencode/plugins/dream-memory.js
```

Run the hook test after any change to `dream-memory.js`, especially the
truncation and the missing-file paths: both are silent by design, so a
regression there produces no error, just lost memory.

## Testing the job by hand

```bash
dream corpus   # free: builds the corpus only
dream status   # free: read-only state
dream          # costs two agent runs
dream reset    # wipe memory and history, keep the config files
```

A full run writes `dreaming/light/<day>.md`, `dreaming/deep/<day>.md`, the
memory files it promoted into (`MEMORY.md` or `projects/<name>/MEMORY.md`) and
one diary entry in `DREAMS.md`. Check that the second run of the same day
rewrites the diary entry instead of adding a second one: that behaviour is
deliberate and easy to break. When `$DREAM_HOME` is a git repo, a run also makes
a `dream: before deep <day>` commit, which is the preimage to restore a bad
rewrite from.

## Loading the plugin locally

Symlink it into the discovery directory. Do **not** list its file path in
`plugins` in `opencode.jsonc`: OpenCode warns that a configured plugin path must
be a directory, and a path entry plus a discovery copy loads it twice.

```bash
ln -sf "$PWD/.opencode/plugins/dream-memory.js" ~/.config/opencode/plugins/dream-memory.js
```

Restart the service after editing the plugin: `opencode service restart`. A
running server caches the imported module, so a fresh `opencode run` can still
execute the previous version of the hook.

## Commits

Imperative subject, 72 characters or fewer, no trailing period. Say what
changed and why, not how. One commit per concern, and never mix the plugin and
the job in one unless they change together.

## Release

Not published to npm yet. When it is, bump `version`, run the checks above, and
`npm publish --access public`. Local use goes through the symlink or
`install.sh`, so a release is only needed to let other people install it.

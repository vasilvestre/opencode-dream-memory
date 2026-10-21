#!/bin/sh
# Install the dream job and its plugin: corpus builder, light/deep agents,
# systemd units, memory home.
#
#   curl -fsSL https://raw.githubusercontent.com/vasilvestre/opencode-dream-memory/main/install.sh | sh
#   sh install.sh            # same thing from a clone, timer disabled
#   sh install.sh --enable   # install, then enable and start the nightly timer
#
# Never overwrites MEMORY.md, DREAMS.md or dream-projects: those hold your data
# and your choices. Safe to re-run after a pull.
set -eu

ENABLE=0
[ "${1:-}" = "--enable" ] && ENABLE=1

BIN="${BIN_DIR:-$HOME/.local/bin}"
AGENTS="${AGENTS_DIR:-$HOME/.config/opencode/agents}"
PLUGINS="${PLUGINS_DIR:-$HOME/.config/opencode/plugins}"
UNITS="${UNITS_DIR:-$HOME/.config/systemd/user}"
HOME_DREAM="${DREAM_HOME:-$HOME/dreams}"
LIST="$HOME/.config/opencode/dream-projects"
MODELS="$HOME/.config/opencode/dream-models"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

command -v opencode >/dev/null || { echo "install: opencode is not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "install: jq is not on PATH" >&2; exit 1; }

# A piped install has no dream/ next to the script, so fetch the archive.
if [ ! -d "$ROOT/dream" ]; then
  url=https://github.com/vasilvestre/opencode-dream-memory/archive/refs/heads/main.tar.gz
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "install: downloading $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" | tar xz -C "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url" | tar xz -C "$tmp"
  else
    echo "install: curl or wget is required to download the archive" >&2
    exit 1
  fi
  ROOT=$tmp/opencode-dream-memory-main
fi
SRC=$ROOT/dream

mkdir -p "$BIN" "$AGENTS" "$UNITS" "$PLUGINS" "$(dirname "$LIST")" "$HOME_DREAM/dreaming/light" "$HOME_DREAM/dreaming/deep" "$HOME_DREAM/.dreams/session-corpus" "$HOME_DREAM/projects"

for f in dream dream-corpus dream-status; do
  install -m 755 "$SRC/$f" "$BIN/$f"
done
for f in dream-light.md dream-deep.md; do
  install -m 644 "$SRC/agents/$f" "$AGENTS/$f"
done
# One copy only: a second file with the same id makes OpenCode drop every plugin.
# An existing symlink stays, so a developer keeps editing the file they cloned.
[ -L "$PLUGINS/dream-memory.js" ] ||
  install -m 644 "$ROOT/.opencode/plugins/dream-memory.js" "$PLUGINS/dream-memory.js"
for f in dream.service dream.timer; do
  install -m 644 "$SRC/systemd/$f" "$UNITS/$f"
done
# The unit must point at the chosen BIN_DIR, which systemd cannot guess.
sed -i "s|^ExecStart=.*|ExecStart=$BIN/dream|" "$UNITS/dream.service"

[ -f "$HOME_DREAM/MEMORY.md" ] || cat > "$HOME_DREAM/MEMORY.md" <<'EOF'
# Shared memory

Facts true in every project, one per line. Project facts live in
`projects/<project>/MEMORY.md`.
EOF

[ -f "$HOME_DREAM/DREAMS.md" ] || cat > "$HOME_DREAM/DREAMS.md" <<'EOF'
# Dream Diary

One entry per night, newest first. Durable facts live in [MEMORY.md](MEMORY.md).

<!-- opencode:dreaming:diary:start -->
EOF

[ -f "$HOME_DREAM/.gitignore" ] || printf '.dreams/\n' > "$HOME_DREAM/.gitignore"

if [ ! -f "$LIST" ]; then
  cat > "$LIST" <<'EOF'
# Projects the dream job consolidates, one absolute path per line.
# A project opts in by having a MEMORY.md file at its root.
# Add your projects below, for example /home/you/code/my-project
EOF
fi

if [ ! -f "$MODELS" ]; then
  cat > "$MODELS" <<'EOF'
# Model per dream stage: <stage> <model> [<model> ...]. The script tries them
# left to right and keeps the first that runs.
# The light pass reads raw session text; the deep pass reads staged candidates.
# With no matching line, the script uses its own paid defaults.
#
# light opencode-go/deepseek-v4.1-flash
# deep  opencode-go/deepseek-v4-pro
EOF
fi

systemctl --user daemon-reload 2>/dev/null || true

echo "installed:"
echo "  $BIN/dream{,-corpus,-status}"
echo "  $AGENTS/dream-{light,deep}.md"
echo "  $PLUGINS/dream-memory.js"
echo "  $UNITS/dream.{service,timer}"
echo "  $HOME_DREAM (MEMORY.md, projects/, dreaming/, DREAMS.md)"

if [ "$ENABLE" -eq 1 ]; then
  systemctl --user enable --now dream.timer
  echo "timer: enabled (daily 04:30)"
elif systemctl --user is-enabled dream.timer >/dev/null 2>&1; then
  echo "timer: already enabled (daily 04:30)"
else
  echo "timer: disabled. Enable it when the output looks right:"
  echo "  systemctl --user enable --now dream.timer"
fi

#!/bin/sh
# Install the dream job: corpus builder, light/deep agents, systemd units.
#
#   sh install.sh           # install everything, leave the timer disabled
#   sh install.sh --enable  # install, then enable and start the nightly timer
#
# Never overwrites MEMORY.md, DREAMS.md or dream-projects: those hold your data
# and your choices. Safe to re-run after a pull.
set -eu

ENABLE=0
[ "${1:-}" = "--enable" ] && ENABLE=1

BIN="${BIN_DIR:-$HOME/.local/bin}"
AGENTS="${AGENTS_DIR:-$HOME/.config/opencode/agents}"
UNITS="${UNITS_DIR:-$HOME/.config/systemd/user}"
HOME_DREAM="${DREAM_HOME:-$HOME/dreams}"
LIST="$HOME/.config/opencode/dream-projects"
MODELS="$HOME/.config/opencode/dream-models"

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/dream

command -v opencode >/dev/null || { echo "install: opencode is not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "install: jq is not on PATH" >&2; exit 1; }

mkdir -p "$BIN" "$AGENTS" "$UNITS" "$(dirname "$LIST")" "$HOME_DREAM/dreaming/light" "$HOME_DREAM/dreaming/deep" "$HOME_DREAM/.dreams/session-corpus" "$HOME_DREAM/projects"

for f in dream dream-corpus dream-status; do
  install -m 755 "$SRC/$f" "$BIN/$f"
done
for f in dream-light.md dream-deep.md; do
  install -m 644 "$SRC/agents/$f" "$AGENTS/$f"
done
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

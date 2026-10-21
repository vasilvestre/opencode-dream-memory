#!/bin/sh
# Two invariants the dream job must not lose: the corpus never carries the
# dream's own output or a labelled secret, and the deep pass runs behind a
# git preimage. Both fail silently in production, hence this check.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
fake="$root/bin"
mkdir -p "$fake" "$root/home" "$root/repo/.git"

cat > "$fake/opencode" <<'EOF'
#!/bin/sh
case $1/$2 in
  session/list)
    printf '%s\n' '[{"id":"s1","updated":9999999999999},{"id":"s2","updated":9999999999999},{"id":"s3","updated":9999999999999}]'
    ;;
  session/export)
    case $3 in
      s1) printf '%s\n' '{"info":{"agent":"build"},"messages":[{"type":"user","text":"export API_KEY=abc123 then ok"},{"type":"assistant","content":[{"type":"text","text":"hello"}]}]}' ;;
      s2) printf '%s\n' '{"info":{"agent":"dream-light"},"messages":[{"type":"user","text":"self output"}]}' ;;
      s3) printf '{"info":{"agent":"build"},"messages":[{"type":"user","text":"trunc"\n' ;;
    esac
    ;;
esac
EOF
chmod +x "$fake/opencode"

printf '%s\n' "$root/repo" > "$root/projects"
PATH="$fake:$PATH" DREAM_HOME="$root/home" DREAM_PROJECTS="$root/projects" \
  "$repo/dream/dream-corpus" > /dev/null 2> "$root/err"

corpus=$(find "$root/home/.dreams/session-corpus" -name '*.txt')
has() { grep -Fq "$1" "$corpus" || { echo "check-corpus: missing $1" >&2; exit 1; }; }
lacks() { ! grep -Fq "$1" "$corpus" || { echo "check-corpus: leaked $1" >&2; exit 1; }; }

has 'API_KEY=[redacted]'
lacks 'abc123'
lacks 'self output'
has 'Assistant: hello'
grep -Fq 'unreadable export' "$root/err" ||
  { echo "check-corpus: a broken export must be skipped, not fatal" >&2; exit 1; }

# Preimage: a git data directory gets a commit before the deep pass.
data="$root/data"
mkdir -p "$data/dreaming/light"
git -C "$data" init -q
printf '# Memory\n' > "$data/MEMORY.md"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git -C "$data" add -A && git -C "$data" commit -qm init

cat > "$root/corpus-bin" <<EOF
#!/bin/sh
mkdir -p "$data/.dreams/session-corpus" "$data/dreaming/light"
echo x > "$data/.dreams/session-corpus/\$(date +%F).txt"
echo '# Light' > "$data/dreaming/light/\$(date +%F).md"
EOF
chmod +x "$root/corpus-bin"

PATH="$fake:$PATH" DREAM_HOME="$data" DREAM_PROJECTS=/dev/null \
  DREAM_CORPUS_BIN="$root/corpus-bin" "$repo/dream/dream" > /dev/null 2>&1

git -C "$data" log --oneline | grep -Fq 'dream: before deep' ||
  { echo "check-corpus: no preimage commit before the deep pass" >&2; exit 1; }
! git -C "$data" ls-files | grep -q '^\.dreams/' ||
  { echo "check-corpus: the corpus entered git" >&2; exit 1; }

echo 'ok: corpus filter, redaction, torn export, preimage'

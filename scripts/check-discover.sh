#!/bin/sh
# discover must print a repository opencode has seen but the project list
# omits, and must not print a listed one. Both failures read as an empty list,
# which looks like "nothing is missing".
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v sqlite3 >/dev/null 2>&1 ||
  { echo "check-discover: sqlite3 is not on PATH" >&2; exit 1; }
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/home" "$root/missing/.git" "$root/listed/.git"
db="$root/opencode.db"
sqlite3 "$db" <<EOF
create table project (worktree text);
insert into project values ('$root/missing');
insert into project values ('$root/listed');
EOF
printf '%s\n' "$root/listed" > "$root/dream-projects"

HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" \
  DREAM_DB="$db" DREAM_PROJECTS="$root/dream-projects" \
  "$repo/dream/dream" discover > "$root/out"

grep -Fxq "$root/missing" "$root/out" ||
  { echo "check-discover: a missing repository was not printed" >&2; exit 1; }
! grep -Fxq "$root/listed" "$root/out" ||
  { echo "check-discover: a listed repository was printed" >&2; exit 1; }

echo 'ok: discover prints a missing repository, skips a listed one'

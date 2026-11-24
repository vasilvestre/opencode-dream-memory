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

status=0
HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" \
  DREAM_DB="$db" DREAM_PROJECTS="$root/no-such-list" \
  "$repo/dream/dream" discover > "$root/out2" 2> "$root/err2" || status=$?
[ "$status" -eq 1 ] ||
  { echo "check-discover: an unreadable list did not exit 1 (got $status)" >&2; exit 1; }
grep -Fxq "dream: no project list at $root/no-such-list" "$root/err2" ||
  { echo "check-discover: an unreadable list printed no 'no project list' line" >&2; exit 1; }
[ ! -s "$root/out2" ] ||
  { echo "check-discover: an unreadable list still printed repositories" >&2; exit 1; }

mkdir "$root/list-dir"
status=0
HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" \
  DREAM_DB="$db" DREAM_PROJECTS="$root/list-dir" \
  "$repo/dream/dream" discover > "$root/out3" 2> "$root/err3" || status=$?
[ "$status" -eq 1 ] ||
  { echo "check-discover: a directory as list did not exit 1 (got $status)" >&2; exit 1; }
grep -Fxq "dream: no project list at $root/list-dir" "$root/err3" ||
  { echo "check-discover: a directory as list printed no 'no project list' line" >&2; exit 1; }
[ ! -s "$root/out3" ] ||
  { echo "check-discover: a directory as list still printed repositories" >&2; exit 1; }

echo 'ok: discover prints a missing repository, skips a listed one, stops on an unreadable list'


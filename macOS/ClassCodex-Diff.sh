#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")" && pwd)"
QUIET=0
NEW_BUILD=""
PREVIOUS=""
LIVE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --new-build) NEW_BUILD="${2:-}"; shift 2;;
    --previous) PREVIOUS="${2:-}"; shift 2;;
    --live) LIVE="${2:-}"; shift 2;;
    --quiet) QUIET=1; shift;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1;;
  esac
done

if [ -z "$LIVE" ]; then
  CONFIG="$ROOT/../config.txt"
  configured="$(awk -F= '$1=="ADDONS_PATH" {print substr($0,index($0,"=")+1); exit}' "$CONFIG" 2>/dev/null || true)"
  configured="${configured#\"}"; configured="${configured%\"}"
  if [ -n "$configured" ] && [ -d "$configured/ClassCodex" ]; then LIVE="$(cd "$configured/ClassCodex" && pwd)"; fi
fi

if [ -z "$LIVE" ]; then
  for root in "/Applications/World of Warcraft" "$HOME/Applications/World of Warcraft" "$HOME/Library/Application Support/Blizzard/World of Warcraft"; do
    if [ -d "$root/_retail_/Interface/AddOns/ClassCodex" ]; then LIVE="$root/_retail_/Interface/AddOns/ClassCodex"; break; fi
  done
fi

[ -n "$LIVE" ] && [ -d "$LIVE" ] || { [ "$QUIET" -eq 1 ] && exit 0 || { echo "ERROR: ClassCodex installation could not be located." >&2; exit 1; }; }

if [ -z "$PREVIOUS" ]; then
  SNAPSHOTS="$ROOT/../ClassCodex-Update-History/Snapshots"
  if [ -d "$SNAPSHOTS" ]; then
    while IFS= read -r d; do PREVIOUS="$d"; break; done < <(find "$SNAPSHOTS" -mindepth 1 -maxdepth 1 -type d -print | sort -r)
  fi
fi

if [ -z "$PREVIOUS" ] || [ ! -d "$PREVIOUS" ]; then
  [ "$QUIET" -eq 1 ] && exit 0
  echo "No previous snapshot available; file change summary skipped."
  exit 0
fi

if [ "$QUIET" -eq 0 ]; then
  echo ""
  echo "ClassCodex file change summary"
  echo "Previous: $(basename "$PREVIOUS")"
  [ -n "$NEW_BUILD" ] && echo "Current : $NEW_BUILD"
fi

declare -A OLD_HASH NEW_HASH
while IFS= read -r -d '' f; do
  rel="${f#$PREVIOUS/}"
  OLD_HASH["$rel"]="$(shasum -a 256 "$f" | awk '{print tolower($1)}')"
done < <(find "$PREVIOUS" -type f -print0)
while IFS= read -r -d '' f; do
  rel="${f#$LIVE/}"
  NEW_HASH["$rel"]="$(shasum -a 256 "$f" | awk '{print tolower($1)}')"
done < <(find "$LIVE" -type f -print0)

added=(); updated=(); removed=(); unchanged=0
for rel in "${!NEW_HASH[@]}"; do
  if [ -z "${OLD_HASH[$rel]+x}" ]; then added+=("$rel")
  elif [ "${NEW_HASH[$rel]}" != "${OLD_HASH[$rel]}" ]; then updated+=("$rel")
  else unchanged=$((unchanged+1)); fi
done
for rel in "${!OLD_HASH[@]}"; do
  [ -n "${NEW_HASH[$rel]+x}" ] || removed+=("$rel")
done

print_list() { local label="$1" marker="$2"; shift 2; local arr=("$@"); [ "${#arr[@]}" -gt 0 ] || return 0; echo; echo "$label:"; printf '  %s %s\n' "$marker" "${arr[@]}"; }
print_list "Added" "+" "${added[@]:-}"
print_list "Updated" "~" "${updated[@]:-}"
print_list "Removed" "-" "${removed[@]:-}"

echo
printf 'File summary:\n'
printf '  Added    : %d\n' "${#added[@]}"
printf '  Updated  : %d\n' "${#updated[@]}"
printf '  Removed  : %d\n' "${#removed[@]}"
printf '  Unchanged: %d\n' "$unchanged"

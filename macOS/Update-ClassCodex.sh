#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$ROOT/../config.txt"
HISTORY="$ROOT/../ClassCodex-Update-History"
SNAPSHOTS="$HISTORY/Snapshots"
CHANGELOGS="$HISTORY/Changelogs"
mkdir -p "$SNAPSHOTS" "$CHANGELOGS"

fail() { echo "ERROR: $*" >&2; exit 1; }
command -v curl >/dev/null || fail "curl is required."
command -v shasum >/dev/null || fail "shasum is required."
command -v osascript >/dev/null || fail "osascript is required for JSON parsing."

configured="$(awk -F= '$1=="ADDONS_PATH" {sub(/^[^=]*=/,""); print; exit}' "$CONFIG" 2>/dev/null || true)"
configured="${configured%\"}"; configured="${configured#\"}"
if [ -n "$configured" ]; then
  configured="$(eval echo "$configured")"
  [ -d "$configured" ] || fail "Configured ADDONS_PATH does not exist: $configured"
  ADDONS="$configured"
else
  ADDONS=""
  for root in "/Applications/World of Warcraft" "$HOME/Applications/World of Warcraft" "$HOME/Library/Application Support/Blizzard/World of Warcraft"; do
    if [ -d "$root/_retail_/Interface/AddOns" ]; then ADDONS="$root/_retail_/Interface/AddOns"; break; fi
  done
  [ -n "$ADDONS" ] || fail "Could not find WoW Retail AddOns. Set ADDONS_PATH in config.txt."
fi
LIVE="$ADDONS/ClassCodex"
CDN="https://wow-class-codex.s3.us-east-1.amazonaws.com"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --max-time 60 "$CDN/channels/retail/production/config.json" -o "$TMP/channel.json"
osascript "$ROOT/jxjson.js" config "$TMP/channel.json" > "$TMP/config.tsv"
IFS=$'\t' read -r BUILD MANIFEST_URL MANIFEST_SHA < "$TMP/config.tsv"
[ -n "$BUILD" ] && [ -n "$MANIFEST_URL" ] && [ -n "$MANIFEST_SHA" ] || fail "Production channel config is incomplete."
curl -fsSL --max-time 60 "$MANIFEST_URL" -o "$TMP/manifest.json"
actual="$(shasum -a 256 "$TMP/manifest.json" | awk '{print tolower($1)}')"
[ "$actual" = "$MANIFEST_SHA" ] || fail "Manifest SHA-256 verification failed."
osascript "$ROOT/jxjson.js" manifest "$TMP/manifest.json" > "$TMP/files.tsv"
[ -s "$TMP/files.tsv" ] || fail "Manifest contains no files."

mkdir -p "$TMP/stage"
declare -A EXPECTED_SIZE EXPECTED_HASH ENCODED_PATH
declare -a DOWNLOAD_PATHS LIVE_FILES
while IFS=$'\t' read -r rel size hash encoded; do
  case "$rel" in ClassCodex/*) short="${rel#ClassCodex/}" ;; *) fail "Unsafe manifest path: $rel" ;; esac
  case "/$short/" in *"/../"*) fail "Unsafe manifest path: $rel" ;; esac
  [ -n "$short" ] || fail "Empty manifest path."
  [ -n "${EXPECTED_SIZE[$short]+x}" ] && fail "Duplicate manifest path: $rel"
  EXPECTED_SIZE[$short]="$size"; EXPECTED_HASH[$short]="$hash"; ENCODED_PATH[$short]="$encoded"
  livefile="$LIVE/$short"
  if [ -f "$livefile" ] && [ "$(stat -f '%z' "$livefile")" = "$size" ] && [ "$(shasum -a 256 "$livefile" | awk '{print tolower($1)}')" = "$hash" ]; then
    continue
  fi
  DOWNLOAD_PATHS+=("$short")
done < "$TMP/files.tsv"

if [ -d "$LIVE" ]; then
  while IFS= read -r -d '' f; do LIVE_FILES+=("${f#"$LIVE/"}"); done < <(find "$LIVE" -type f -print0)
fi
declare -a REMOVED
for rel in "${LIVE_FILES[@]}"; do
  [ -n "${EXPECTED_SIZE[$rel]+x}" ] || REMOVED+=("$rel")
done
if [ "${#DOWNLOAD_PATHS[@]}" -eq 0 ] && [ "${#REMOVED[@]}" -eq 0 ]; then
  echo "ClassCodex is already up to date. No files need to be downloaded or rewritten."
  exit 0
fi

for rel in "${DOWNLOAD_PATHS[@]}"; do
  urlpath="${ENCODED_PATH[$rel]}""
  dest="$TMP/stage/$rel"; mkdir -p "$(dirname "$dest")"
  curl -fsSL --max-time 120 "$CDN/builds/retail/$BUILD/ClassCodex/$urlpath" -o "$dest"
  [ "$(stat -f '%z' "$dest")" = "${EXPECTED_SIZE[$rel]}" ] || fail "Size verification failed: $rel"
  [ "$(shasum -a 256 "$dest" | awk '{print tolower($1)}')" = "${EXPECTED_HASH[$rel]}" ] || fail "SHA-256 verification failed: $rel"
done

for rel in "${!EXPECTED_SIZE[@]}"; do
  source="$TMP/stage/$rel"; [ -f "$source" ] || source="$LIVE/$rel"
  [ -f "$source" ] || fail "Required manifest file is missing: ClassCodex/$rel"
  [ "$(stat -f '%z' "$source")" = "${EXPECTED_SIZE[$rel]}" ] || fail "Final size verification failed: $rel"
  [ "$(shasum -a 256 "$source" | awk '{print tolower($1)}')" = "${EXPECTED_HASH[$rel]}" ] || fail "Final SHA-256 verification failed: $rel"
done

mkdir -p "$LIVE"
for rel in "${REMOVED[@]}"; do rm -f "$LIVE/$rel"; echo "Removed: $rel"; done
for rel in "${DOWNLOAD_PATHS[@]}"; do mkdir -p "$(dirname "$LIVE/$rel")"; rm -f "$LIVE/$rel"; mv "$TMP/stage/$rel" "$LIVE/$rel"; done
find "$LIVE" -type d -empty -delete 2>/dev/null || true

snap="$SNAPSHOTS/$BUILD"; rm -rf "$snap"; mkdir -p "$snap"; cp -Rp "$LIVE/." "$snap/"
echo "ClassCodex updated successfully: $LIVE"
echo "Downloaded ${#DOWNLOAD_PATHS[@]} files; removed ${#REMOVED[@]} files."
echo "Snapshot saved: $snap"

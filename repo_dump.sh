#!/usr/bin/env bash
set -Eeuo pipefail

STAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
OUT="${STAMP}_full_dump.txt"

MAX_BYTES=$((512 * 1024))

{
  find . \
    -path "./.git" -prune -o \
    -path "./clusters/talos-home/flux-system" -prune -o \
    -path "./clusters/talos-home/flux-system/*" -prune -o \
    -type f -print0 \
  | sort -z \
  | while IFS= read -r -d '' f; do

      size=$(wc -c < "$f" 2>/dev/null || echo 0)
      if (( size > MAX_BYTES )); then
        continue
      fi

      if ! LC_ALL=C grep -Iq . "$f" 2>/dev/null; then
        continue
      fi

      echo "----- FILE: $f -----"
      sed 's/^/    /' "$f"
      echo
    done
} > "$OUT"

echo "Wrote dump to: $OUT"

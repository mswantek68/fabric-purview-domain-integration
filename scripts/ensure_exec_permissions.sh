#!/usr/bin/env bash
set -euo pipefail
echo "[perm-fix] Ensuring executable bits on scripts/*.sh"
changed=0
for f in scripts/*.sh; do
  if [[ -f "$f" && ! -x "$f" ]]; then
    chmod +x "$f"
    echo "[perm-fix] Added +x to $f"
    changed=$((changed+1))
  fi
done
echo "[perm-fix] Completed. Files updated: $changed"

#!/bin/bash
# PreToolUse hook: blocks any write/erase of the Tang Nano 9K flash until a flash backup exists.
# Exit code 2 = block the call; Claude sees the stderr text.
input=$(cat)
# Must match FLASH_BACKUP in the Makefile
backup="${CLAUDE_PROJECT_DIR:-.}/backup/tangnano9k_flash_backup.fs"

# Split a compound command on &&, ||, ; and | and check each part separately.
# `openFPGALoader --detect -f` only shows the flash, so it is not a write.
# awk only (no sed \n), so it behaves the same with the macOS BSD tools.
writes_flash=$(printf '%s' "$input" | awk '
  { n = split($0, part, /&&|\|\||;|\|/)
    for (i = 1; i <= n; i++) {
      s = part[i]
      if (s ~ /make[^"]*flash-perm/) hit = 1
      if (s ~ /openFPGALoader/) {
        if (s !~ /--detect/ && s ~ / -f( |"|$)/) hit = 1
        if (s ~ /--write-flash|--bulk-erase|--unprotect-flash|--protect-flash/) hit = 1
      }
    } }
  END { print hit + 0 }')

if [ "$writes_flash" = "1" ] && [ ! -s "$backup" ]; then
  echo "BLOCKED: no flash backup ($backup). Resolve the flash-backup question in AGENTS.md and get the user's approval first." >&2
  exit 2
fi
exit 0

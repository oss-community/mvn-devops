#!/usr/bin/env bash
# Prints the CHANGELOG.md section of a version, used as the GitHub release text.
# Usage: packaging/release-notes.sh <version>
set -euo pipefail
version=${1#v}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
notes=$(awk -v v="$version" '
  /^## / { if (found) exit; found = ($2 == v) ; next }
  found' "$ROOT/CHANGELOG.md")
[[ -n ${notes//[[:space:]]/} ]] || { echo "CHANGELOG.md has no section '## $version'" >&2; exit 1; }
printf '%s\n' "$notes"

#!/bin/zsh
# Finder launches .command files with an arbitrary working directory.
set -euo pipefail
cd -- "${0:A:h}"

if [[ ! -x "build/FRAME32.app/Contents/MacOS/FRAME32" ]]; then
  print -u2 'FRAME32 has not been built yet. Run ./scripts/build.sh first.'
  read -r '?Press Return to close…'
  exit 1
fi

if ! /usr/bin/open "$PWD/build/FRAME32.app"; then
  print -u2 'Could not open FRAME32.'
  read -r '?Press Return to close…'
  exit 1
fi

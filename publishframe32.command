#!/bin/zsh
# Publish from the normal macOS terminal, where Git metadata and network access are available.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd -- "${0:A:h}"

trap 'print -u2 "Publishing stopped. No force push was attempted."; read -r "?Press Return to close…"' ZERR

if ! command -v gh >/dev/null; then
  print -u2 'GitHub CLI is missing. Install it with: brew install gh'
  exit 1
fi
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  gh auth login --hostname github.com --git-protocol https --web
fi
account="$(gh api user --jq .login)"
if [[ "$account" != cyniibun ]]; then
  print -u2 "Expected GitHub account cyniibun; authenticated as $account. Nothing published."
  exit 1
fi

if [[ ! -d .git && ! -f .git ]]; then
  git init -b main
fi
if [[ "$(git rev-parse --show-toplevel)" != "$PWD" ]]; then
  print -u2 'The Git working directory does not match this project. Nothing published.'
  exit 1
fi
if [[ -z "$(git config user.name || true)" || -z "$(git config user.email || true)" ]]; then
  print -u2 'Configure your Git author name and email before publishing.'
  exit 1
fi

expected='https://github.com/cyniibun/frame-32.git'
if git remote get-url origin >/dev/null 2>&1; then
  remote="$(git remote get-url origin)"
  case "$remote" in
    https://github.com/cyniibun/frame-32|https://github.com/cyniibun/frame-32.git|git@github.com:cyniibun/frame-32.git) ;;
    *) print -u2 "Existing origin points elsewhere: $remote. Nothing published."; exit 1 ;;
  esac
fi

# Only the project deliverables are staged; generated builds and private settings are excluded.
git add -- .gitignore README.md Package.swift launchframe32.command publishframe32.command Sources Tests scripts Docs References
if ! git diff --cached --quiet; then
  git commit -m 'Add FRAME//32 native camera effects app and development documentation'
fi

if visibility="$(gh repo view cyniibun/frame-32 --json isPrivate --jq .isPrivate 2>/dev/null)"; then
  if [[ "$visibility" != true ]]; then
    print -u2 'The existing frame-32 repository is public. Review its visibility before publishing.'
    exit 1
  fi
else
  gh repo create cyniibun/frame-32 --private --description 'FRAME//32 — native Swift and Metal camera effects studio for macOS'
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$expected"
fi
git -c credential.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' push --set-upstream origin HEAD
print 'Published FRAME//32: https://github.com/cyniibun/frame-32'
/usr/bin/open 'https://github.com/cyniibun/frame-32'
read -r '?Press Return to close…'

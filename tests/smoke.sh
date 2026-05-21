#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/base" "$tmp/layer"

cd "$tmp/base"
git init -q --initial-branch=main
git config user.email layers@example.local
git config user.name "Git Layers Test"
printf 'line 1\nshared line\nline 3\n' > README.md
git add README.md
git commit -m "base" >/dev/null

cd "$tmp/layer"
git init -q --initial-branch=main
git config user.email layers@example.local
git config user.name "Git Layers Test"
printf 'line 1\nshared line patched by layer\nline 3\n' > README.md
printf 'TOKEN=secret\n' > .env
git add README.md .env
git commit -m "layer patch" >/dev/null

cd "$tmp/base"
git layers apply ../layer --name local --partial >/dev/null
test -z "$(git status --short)"
test -z "$(git diff -- README.md)"
test -f .env
grep -q 'shared line patched by layer' README.md

printf 'user edit\n' >> README.md
git diff -- README.md | grep -q '+user edit'
! git diff -- README.md | grep -q 'shared line patched by layer'
git add README.md
git commit -m "base user edit" >/dev/null
test -z "$(git status --short)"

git layers unapply local >/dev/null
test -z "$(git status --short)"
test ! -e .env
! grep -q 'shared line patched by layer' README.md
grep -q 'user edit' README.md

echo "smoke ok"

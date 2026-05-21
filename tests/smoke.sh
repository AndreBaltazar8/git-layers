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

tmp_ref="$tmp/ref-layer"
mkdir "$tmp_ref"
cd "$tmp_ref"
git init -q --initial-branch=main
git config user.email layers@example.local
git config user.name "Git Layers Test"
printf 'alpha\nbravo\ncharlie\n' > notes.txt
git add notes.txt
git commit -m "base" >/dev/null

git checkout -q -b layer/topic
perl -0pi -e 's/charlie/layer charlie/' notes.txt
printf 'TOKEN=secret\n' > .env
git add notes.txt .env
git commit -m "layer branch" >/dev/null

git checkout -q main
perl -0pi -e 's/alpha/base alpha/' notes.txt
git commit -am "base moved" >/dev/null

old_layer_commit="$(git rev-parse layer/topic)"
git layers apply-ref layer/topic --name topic >/dev/null
test -z "$(git status --short)"
grep -q 'base alpha' notes.txt
grep -q 'layer charlie' notes.txt
test -f .env

printf 'TOKEN=updated\n' > .env
git layers commit topic -m "update layer env" >/dev/null
new_layer_commit="$(git rev-parse layer/topic)"
test "$new_layer_commit" != "$old_layer_commit"
test "$(git rev-parse "$new_layer_commit^")" = "$old_layer_commit"
git show layer/topic:.env | grep -q 'TOKEN=updated'
test -z "$(git status --short)"

printf 'user delta\n' >> notes.txt
git diff -- notes.txt | grep -q '+user delta'
! git diff -- notes.txt | grep -q 'layer charlie'
git add notes.txt
git commit -m "base user edit" >/dev/null
test -z "$(git status --short)"

git layers unapply topic >/dev/null
test -z "$(git status --short)"
test ! -d .git/layers/refs/topic
test ! -e .env
grep -q 'base alpha' notes.txt
! grep -q 'layer charlie' notes.txt
grep -q 'user delta' notes.txt

echo "smoke ok"

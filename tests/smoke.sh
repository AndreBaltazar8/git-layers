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

tmp_stack="$tmp/ref-stack"
mkdir "$tmp_stack"
cd "$tmp_stack"
git init -q --initial-branch=main
git config user.email layers@example.local
git config user.name "Git Layers Test"
printf 'one\ntwo\nthree\nfour\nfive\n' > f.txt
git add f.txt
git commit -m "base" >/dev/null

git checkout -q -b layer/top
perl -0pi -e 's/one/layer one/' f.txt
git commit -am "layer top" >/dev/null

git checkout -q main
git checkout -q -b layer/bottom
perl -0pi -e 's/five/layer five/' f.txt
git commit -am "layer bottom" >/dev/null

git checkout -q main
git layers apply-ref layer/top --name top >/dev/null
git layers apply-ref layer/bottom --name bottom >/dev/null
test -z "$(git status --short)"
grep -q 'layer one' f.txt
grep -q 'layer five' f.txt

printf 'user edit\n' >> f.txt
git diff -- f.txt | grep -q '+user edit'
! git diff -- f.txt | grep -q 'layer one'
! git diff -- f.txt | grep -q 'layer five'

git layers unapply top >/dev/null
! grep -q 'layer one' f.txt
grep -q 'layer five' f.txt
grep -q 'user edit' f.txt

git layers unapply bottom >/dev/null
! grep -q 'layer one' f.txt
! grep -q 'layer five' f.txt
grep -q 'user edit' f.txt
git diff -- f.txt | grep -q '+user edit'

tmp_special="$tmp/special-paths"
mkdir "$tmp_special"
cd "$tmp_special"
git init -q --initial-branch=main
git config user.email layers@example.local
git config user.name "Git Layers Test"
mkdir -p 'src/(auth)'
printf 'base\n' > 'src/(auth)/[gameId].txt'
git add .
git commit -m "base" >/dev/null

git checkout -q -b layer/special
printf 'layer\n' > 'src/(auth)/[gameId].txt'
git commit -am "layer special path" >/dev/null

git checkout -q main
git layers apply-ref layer/special --name special >/dev/null
test -z "$(git status --short)"
test -z "$(git diff -- 'src/(auth)/[gameId].txt')"
printf 'user\n' >> 'src/(auth)/[gameId].txt'
git diff -- 'src/(auth)/[gameId].txt' | grep -q '+user'
! git diff -- 'src/(auth)/[gameId].txt' | grep -q 'layer'

if command -v git-crypt >/dev/null 2>&1; then
  tmp_crypt="$tmp/git-crypt-layer"
  mkdir "$tmp_crypt"
  cd "$tmp_crypt"
  git init -q --initial-branch=main
  git config user.email layers@example.local
  git config user.name "Git Layers Test"
  git-crypt init >/dev/null
  printf 'secret.txt filter=git-crypt diff=git-crypt\n' > .gitattributes
  printf 'line one\nline two\nline three\n' > README.md
  printf 'base secret\n' > secret.txt
  git add .gitattributes README.md secret.txt
  git commit -m "base" >/dev/null

  git checkout -q -b layer/secret
  perl -0pi -e 's/line three/layer line three/' README.md
  printf 'layer secret\n' > secret.txt
  git commit -am "layer encrypted file" >/dev/null

  git checkout -q main
  perl -0pi -e 's/line one/base line one/' README.md
  git commit -am "base moved" >/dev/null

  git layers apply-ref layer/secret --name secret-layer >/dev/null
  test -z "$(git status --short)"
  grep -q 'layer line three' README.md
  grep -q 'layer secret' secret.txt

  printf 'updated secret\n' > secret.txt
  git layers commit secret-layer -m "update encrypted layer secret" >/dev/null
  git show layer/secret:secret.txt | git-crypt smudge | grep -q 'updated secret'
  ! git show layer/secret:secret.txt | LC_ALL=C grep -q 'updated secret'
  test -z "$(git status --short)"

  git layers unapply secret-layer >/dev/null
  test -z "$(git status --short)"
  ! grep -q 'layer line three' README.md
  grep -q 'base line one' README.md

  git checkout -q -b layer/readme-only main
  perl -0pi -e 's/line two/layer line two/' README.md
  git commit -am "layer readme only" >/dev/null
  git checkout -q main
  git-crypt lock
  git layers apply-ref layer/readme-only --name readme-layer >/dev/null
  test -z "$(git status --short)"
  grep -q 'layer line two' README.md
fi

echo "smoke ok"

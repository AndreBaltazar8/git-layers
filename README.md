# git-layers

`git-layers` is a small Git plugin for applying local, versioned patch layers on
top of a real repository without committing those files to the base repo.

It is useful for files like `.env`, local README overrides, private config, or
machine-specific scripts. Layer files are copied into the worktree, but the
plugin subtracts those paths from normal base-repo commits:

- partial patches for tracked files are hidden from normal base commits
- layer-only files like `.env` stay local to the base worktree
- multiple partial layers can stack on the same tracked file
- layer contents can be their own Git repository and committed separately

## Normal Git Commands

This does not intercept or replace built-in Git commands. Git plugins can add
commands like `git layers`, but they cannot transparently override built-ins
like `git diff` or `git status`.

Instead, `git-layers` keeps applied layer files out of the base repo's normal
view:

- `git status` stays clean for applied layer-only hunks
- `git diff` does not show applied partial patch hunks
- `git add README.md` stages only the user's edits, not the layer hunks
- `git add .` does not stage applied layer-only files
- `git add .env` is blocked for ignored layer-only files unless you force it
  with `git add -f`

Use `git layers status` and `git layers diff` when you want the layer-aware
view.

## Install

From this repository:

```sh
export PATH="$PWD/bin:$PATH"
```

Git will find `bin/git-layers` as the `git layers` command.

## Basic Workflow

Apply an existing layer directory:

```sh
cd /path/to/base-repo
git layers apply ../patches/local --name local --partial
git status --short
```

With `--partial`, tracked files from the layer are installed as patch hunks.
Untracked files from the same layer are still installed as private overlay
files.

Apply a layer from another ref in the same repository:

```sh
cd /path/to/base-repo
git layers apply-ref my-layer-branch --name local
git status --short
```

`apply-ref` derives a layer from the changes on that ref, preserving changes
that already happened on your current base branch.

If the layer ref is a local branch, `git layers commit` commits layer overlay
changes on top of that branch:

```sh
printf 'TOKEN=updated\n' > .env
git layers commit local -m "Update local env"
```

The branch must still point at the same commit it had when the layer was
applied; if it moved, unapply and reapply before committing the layer.

Create an empty Git-backed layer and start tracking local files:

```sh
cd /path/to/base-repo
git layers init ../patches/private --name private --apply
printf 'TOKEN=secret\n' > .env
git layers track .env
git layers commit -m "Add local env"
```

Track a local edit to a file that already exists in the base repo. The default
`track` mode stores tracked files as partial patches:

```sh
cd /path/to/base-repo
printf '\nLocal note\n' >> README.md
git layers track README.md
git status --short
git layers commit -m "Customize README locally"
```

Save later edits back to the layer without committing:

```sh
git layers save
```

Save and commit later edits into the layer repo:

```sh
git layers commit -m "Update local config"
```

Remove a layer and restore the base worktree:

```sh
git layers unapply local
```

## Commands

```text
git layers init <layer-dir> [--name NAME] [--apply]
git layers apply <layer-dir> [--name NAME] [--partial] [--force] [--allow-empty]
git layers apply-ref <ref> [--base REF] [--name NAME] [--overlay] [--force] [--allow-empty]
git layers track [--layer NAME] [--mode auto|partial|overlay] [--force] <path>...
git layers save [NAME]
git layers commit [NAME] -m "message" [--init] [--allow-empty]
git layers status
git layers list
git layers diff [NAME_OR_LAYER_DIR]
git layers unapply [NAME] [--force]
```

## Examples and Tests

This repository includes two real example repos:

- `examples/base-repo`
- `examples/patches/local`

Try the mixed partial/overlay behavior:

```sh
export PATH="$PWD/bin:$PATH"
cd examples/base-repo
git layers apply ../patches/local --name local --partial
git status --short
git layers unapply local
```

Run the temporary-repo smoke test:

```sh
tests/smoke.sh
```

## Important Tradeoffs

Partial patch mode is text-oriented and currently expects UTF-8 files. Edits
outside layer hunks behave like normal base-repo edits. If someone edits inside
the same hunk that the layer owns, `git-layers` can report a patch conflict
instead of guessing.

Full-file overlays are exclusive per path. Use partial mode when multiple
layers or base edits need to touch the same tracked file.

`apply-ref` currently supports added and modified paths. If the layer branch
deletes a path, the command stops instead of guessing how that deletion should
interact with local edits.

For `apply-ref`, `git layers commit` currently commits overlay/new-file changes
back to the source branch. Partial tracked-file hunks are validated but not
inferred as layer edits; edit those directly on the layer branch for now.

For `git-crypt` paths, the base repo must be unlocked if an encrypted file
changed in the layer ref.

For private secrets, commit the layer repo only to a private remote. This plugin
keeps secrets out of the base repo; it does not encrypt the layer repo.

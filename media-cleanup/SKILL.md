---
name: media-cleanup
description: Clean up after studio work. Keeps the final video or image and the inputs needed to rebuild it, moves everything else in a job folder to a dated trash folder, and removes git worktrees that are clean and merged. Use when a studio job is finished, when generated media (voice takes, keyframes, clips, renders) piles up on disk, when the user asks to free space, tidy a job folder, empty the trash, or remove old worktrees.
---

# media-cleanup

Studio jobs leave a lot behind: every voice take, rejected keyframe, intermediate clip and render. This skill keeps what matters and moves the rest to a trash folder. It never deletes on its own.

Script: `scripts/media_cleanup.py` (Python 3, standard library). From the installed store it is `$KAITO_HOME/store/media-cleanup/scripts/media_cleanup.py`. `KAITO_HOME` defaults to `~/.kaito`.

## Clean a job folder

A job folder is for example `$KAITO_HOME/owners/<id>/studio/<job>/`.

1. Write the keep manifest: one path or glob per line, relative to the job folder, `#` for comments. Keep:
   - the final deliverable (the assembled video, the approved image set)
   - the rebuild inputs: lines JSON, parts JSON, prompts, sidecar files, scripts and settings used
   - approved artifacts: the takes, keyframes and clips the final was built from
   A folder name keeps everything under it. If you are unsure whether a file is needed to rebuild, keep it and ask.
2. Dry run first. It is the default and changes nothing:
   `python3 media_cleanup.py clean <job> --keep <manifest>`
3. Show the user the list with sizes. When they agree, run it again with `--apply`. Files move to `$KAITO_HOME/trash/YYYY-MM-DD/<job>/` with their relative paths, so a file can be put back by moving it back.

What it will not do:
- Touch a file tracked by git, when the folder is inside a repo.
- Touch anything outside the job folder.
- Run when a symlink in the job folder points outside it. It stops, moves nothing and exits 3.
- Run with an empty manifest.

## Empty the trash

`python3 media_cleanup.py purge --older-than 30d` lists the trash days older than 30 days and deletes nothing. Purge is the only step that deletes for good. Ask the user in chat first, name the days and the total size, and re-run with `--yes` only after a clear yes.

## Worktrees

`python3 media_cleanup.py worktrees <repo>` lists the git worktrees of a repo with size, branch, whether each is clean and whether its branch is merged into `origin/main` (or `main`). Lists only by default.

`--apply` removes a worktree only when it is clean and its branch is merged, with `git worktree remove` and then `git worktree prune`. It never removes the main checkout, a dirty tree (ignored files such as renders count as dirt), a locked one, a detached one or the folder you are standing in. It does not delete branches.

A branch merged by squash or rebase is not an ancestor of `origin/main`, so it shows as not merged and stays. Check the pull request, then remove it by hand if the user agrees. A branch that has no commits of its own yet also counts as merged, so a fresh worktree that is clean may be listed for removal: check no agent is using it. Other agents may be working in the worktrees: list first, apply only when the user says so.

## Exit codes

0 ok, 1 error, 2 usage, 3 needs a human decision (refused), 4 not found.

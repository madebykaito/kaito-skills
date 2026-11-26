#!/usr/bin/env python3
"""media_cleanup: tidy studio job folders and git worktrees without deleting anything by surprise.

  clean JOB --keep MANIFEST [--apply]   list (default) or move non-kept files to the dated trash
  purge --older-than 30d [--yes]        empty old trash days (needs --yes)
  worktrees REPO [--apply]              list worktrees, or remove clean merged ones

Exit codes: 0 ok, 1 error, 2 usage, 3 needs a human decision (refused), 4 not found.
Python 3 standard library only.
"""
import argparse
import datetime
import errno
import fnmatch
import json
import os
import re
import shutil
import stat
import subprocess
import sys


def kaito_home():
    return os.path.abspath(os.environ.get("KAITO_HOME") or os.path.join(os.path.expanduser("~"), ".kaito"))


def human(n):
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return ("%d %s" % (n, unit)) if unit == "B" else ("%.1f %s" % (n, unit))
        n /= 1024


def git(args, cwd):
    return subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)


def inside(path, root):
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


# ---------- keep manifest ----------

def read_manifest(path):
    """Lines of relative paths or globs; '#' comments; or a JSON list of strings."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.lstrip().startswith("["):
        items = json.loads(text)
        if not all(isinstance(i, str) for i in items):
            raise ValueError("manifest JSON must be a list of strings")
    else:
        items = [l.strip() for l in text.splitlines()]
    out = []
    for i in items:
        i = i.strip()
        if not i or i.startswith("#"):
            continue
        i = os.path.normpath(i)
        if os.path.isabs(i) or i == ".." or i.startswith(".." + os.sep):
            raise ValueError("manifest entry outside the job folder: %s" % i)
        out.append(i)
    return out


def is_kept(rel, patterns):
    for p in patterns:
        if p == "." or rel == p or rel.startswith(p + os.sep):
            return True
        if any(c in p for c in "*?["):
            if fnmatch.fnmatchcase(rel, p):
                return True
            # a glob that names a folder keeps everything beneath it
            parts = rel.split(os.sep)
            for k in range(1, len(parts)):
                if fnmatch.fnmatchcase(os.sep.join(parts[:k]), p):
                    return True
    return False


# ---------- clean ----------

def tracked_files(job):
    """Set of job-relative paths tracked by git, or empty when the folder is not in a repo."""
    r = git(["rev-parse", "--show-toplevel"], job)
    if r.returncode != 0:
        if "not a git repository" in r.stderr:
            return set()  # a job folder outside any repo has nothing tracked
        raise RuntimeError("cannot tell whether the job folder is in a repo: %s" % r.stderr.strip())
    top = os.path.realpath(r.stdout.strip())
    p = git(["ls-files", "-z", "--full-name"], job)
    if p.returncode != 0:
        raise RuntimeError("git ls-files failed, refusing to guess what is tracked: %s" % p.stderr.strip())
    out = set()
    for name in p.stdout.split("\0"):
        if not name:
            continue
        full = os.path.join(top, name)
        if inside(full, job):
            out.add(os.path.relpath(full, job))
    return out


def scan(job, patterns):
    """Returns (movable, kept, tracked, refused): lists of (rel, size) or (rel, why)."""
    tracked = tracked_files(job)
    movable, kept, trk, refused = [], [], [], []
    def walk_error(e):
        raise e
    for dirpath, dirnames, filenames in os.walk(job, followlinks=False, onerror=walk_error):
        if ".git" in dirnames:
            dirnames.remove(".git")
        # A nested repository has its own index; leave the whole repository alone.
        dirnames[:] = [d for d in dirnames if os.path.islink(os.path.join(dirpath, d)) or (
            os.path.relpath(os.path.join(dirpath, d), job) not in tracked
            and not os.path.lexists(os.path.join(dirpath, d, ".git")))]
        entries = [f for f in filenames if f != ".git"]
        # symlinks to directories show up in dirnames; treat them as entries, never descend
        for d in list(dirnames):
            if os.path.islink(os.path.join(dirpath, d)):
                dirnames.remove(d)
                entries.append(d)
        for name in entries:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, job)
            if os.path.islink(full):
                target = os.path.realpath(full)
                if not inside(target, job):
                    refused.append((rel, "symlink escapes the job folder -> %s" % os.readlink(full)))
                    continue
                size = 0
            else:
                size = os.lstat(full).st_size
            if rel in tracked:
                trk.append((rel, size))
            elif is_kept(rel, patterns):
                kept.append((rel, size))
            else:
                movable.append((rel, size))
    for lst in (movable, kept, trk, refused):
        lst.sort()
    return movable, kept, trk, refused


def reserve_dest(dest):
    """Atomically claim an unused destination name, so two runs never overwrite each other."""
    n = 0
    while True:
        cand = dest if n == 0 else "%s.%d" % (dest, n)
        try:
            os.close(os.open(cand, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
            return cand
        except FileExistsError:
            n += 1


def cmd_clean(a):
    job = os.path.realpath(a.job)
    if not os.path.isdir(job):
        print("not found: %s" % a.job, file=sys.stderr)
        return 4
    try:
        patterns = read_manifest(a.keep)
    except FileNotFoundError:
        print("not found: keep manifest %s" % a.keep, file=sys.stderr)
        return 4
    except (ValueError, json.JSONDecodeError) as e:
        print("bad manifest: %s" % e, file=sys.stderr)
        return 1
    if not patterns:
        print("refused: the keep manifest is empty, so everything would move. Name the final deliverable and the rebuild inputs.", file=sys.stderr)
        return 3
    day = a.date or datetime.date.today().isoformat()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
        print("bad --date: %s" % day, file=sys.stderr)
        return 2
    trash_root = os.path.realpath(os.path.join(kaito_home(), "trash"))
    trash = os.path.join(trash_root, day, os.path.basename(job))
    if not inside(os.path.realpath(trash), trash_root):
        print("refused: trash path escapes the trash folder", file=sys.stderr)
        return 3
    if inside(os.path.realpath(trash), job):
        print("refused: the trash folder is inside the job folder", file=sys.stderr)
        return 3
    movable, kept, trk, refused = scan(job, patterns)
    for rel, size in kept:
        print("keep     %10s  %s" % (human(size), rel))
    for rel, size in trk:
        print("tracked  %10s  %s  (git tracked, never moved)" % (human(size), rel))
    for rel, why in refused:
        print("REFUSED  %10s  %s  (%s)" % ("", rel, why))
    word = "move" if a.apply else "would-move"
    for rel, size in movable:
        print("%-8s %10s  %s" % (word, human(size), rel))
    total = sum(s for _, s in movable)
    print("summary: keep=%d tracked=%d refused=%d %s=%d (%s) job=%s" % (
        len(kept), len(trk), len(refused), "moved" if a.apply else "to_move", len(movable), human(total), job))
    if refused:
        print("refused: fix or remove the escaping symlinks first; nothing was moved.", file=sys.stderr)
        return 3
    if not a.apply:
        print("dry run: nothing changed. Re-run with --apply to move these to %s" % trash)
        return 0
    parents = set()
    trash_real = os.path.realpath(trash)
    for rel, _ in movable:
        dest_parent = os.path.dirname(os.path.join(trash, rel))
        if not inside(os.path.realpath(dest_parent), trash_real):
            print("refused: trash path escapes the trash folder for %s" % rel, file=sys.stderr)
            return 3
    for rel, _ in movable:
        src = os.path.join(job, rel)
        # the tree may have changed since the scan: re-check the source parent and the destination
        if not inside(os.path.realpath(os.path.dirname(src)), job) or not os.path.lexists(src):
            print("skipped %s: changed since the scan" % rel, file=sys.stderr)
            continue
        if not inside(os.path.realpath(os.path.dirname(os.path.join(trash, rel))), trash_real):
            print("refused: trash path escapes the trash folder for %s" % rel, file=sys.stderr)
            return 3
        os.makedirs(os.path.dirname(os.path.join(trash, rel)), exist_ok=True)
        dest = reserve_dest(os.path.join(trash, rel))
        shutil.move(src, dest)
        parents.add(os.path.dirname(src))
    # drop folders that the move left empty
    for p in sorted(parents, key=len, reverse=True):
        while p != job and inside(p, job):
            try:
                os.rmdir(p)
            except OSError:
                break
            p = os.path.dirname(p)
    print("moved %d files (%s) to %s" % (len(movable), human(total), trash))
    return 0


# ---------- purge ----------

def parse_age(s):
    m = re.fullmatch(r"(\d+)([dw]?)", s.strip())
    if not m:
        raise ValueError("--older-than takes days like 30d or weeks like 4w")
    return int(m.group(1)) * (7 if m.group(2) == "w" else 1)


def dir_size(path):
    total = 0
    for dp, _, fn in os.walk(path, followlinks=False):
        for f in fn:
            try:
                total += os.lstat(os.path.join(dp, f)).st_size
            except OSError:
                pass
    return total


def cmd_purge(a):
    try:
        days = parse_age(a.older_than)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 2
    today = datetime.date.fromisoformat(a.today) if a.today else datetime.date.today()
    cutoff = today - datetime.timedelta(days=days)
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        home_fd = os.open(kaito_home(), flags)
        try:
            trash_fd = os.open("trash", flags, dir_fd=home_fd)
        finally:
            os.close(home_fd)
    except FileNotFoundError:
        print("summary: 0 trash days older than %dd (0 B)" % days)
        return 0
    except OSError as e:
        if e.errno not in (errno.ELOOP, errno.ENOTDIR):
            raise
        print("refused: KAITO_HOME and trash must both be real directories", file=sys.stderr)
        return 3
    try:
        return purge_days(trash_fd, cutoff, days, a.yes)
    finally:
        os.close(trash_fd)


def purge_days(trash_fd, cutoff, days, confirmed):
    old = []
    for name in sorted(os.listdir(trash_fd)):
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", name):
            continue
        try:
            if datetime.date.fromisoformat(name) >= cutoff:
                continue
            entry = os.stat(name, dir_fd=trash_fd, follow_symlinks=False)
        except (ValueError, FileNotFoundError):
            continue
        if not stat.S_ISDIR(entry.st_mode):
            continue
        size = 0
        for _, _, files, day_fd in os.fwalk(name, dir_fd=trash_fd, follow_symlinks=False):
            for filename in files:
                try:
                    size += os.stat(filename, dir_fd=day_fd, follow_symlinks=False).st_size
                except OSError:
                    pass
        old.append((name, entry, size))
    for name, _, size in old:
        print("%s  %s" % (name, human(size)))
    print("summary: %d trash days older than %dd (%s)" % (len(old), days, human(sum(s for _, _, s in old))))
    if not old:
        return 0
    if not confirmed:
        print("refused: purge deletes for good. Confirm with the user in chat, then re-run with --yes.", file=sys.stderr)
        return 3
    if not shutil.rmtree.avoids_symlink_attacks:
        raise RuntimeError("safe trash purge is unavailable on this platform")
    for name, entry, _ in old:
        current = os.stat(name, dir_fd=trash_fd, follow_symlinks=False)
        if not os.path.samestat(entry, current) or not stat.S_ISDIR(current.st_mode):
            raise RuntimeError("trash day changed during purge")
        shutil.rmtree(name, dir_fd=trash_fd)
        print("purged %s" % name)
    return 0


# ---------- worktrees ----------

def list_worktrees(repo):
    p = git(["worktree", "list", "--porcelain"], repo)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "not a git repository")
    items, cur = [], None
    for line in p.stdout.splitlines() + [""]:
        if not line:
            if cur:
                items.append(cur)
            cur = None
            continue
        key, _, val = line.partition(" ")
        if key == "worktree":
            cur = {"path": val, "head": None, "branch": None, "locked": False, "bare": False}
        elif cur is not None:
            if key == "HEAD":
                cur["head"] = val
            elif key == "branch":
                cur["branch"] = val[len("refs/heads/"):] if val.startswith("refs/heads/") else val
            elif key == "bare":
                cur["bare"] = True
            elif key == "locked":
                cur["locked"] = True
    return items


def pick_base(repo, want):
    for c in ([want] if want else ["origin/main", "main"]):
        if git(["rev-parse", "--verify", "--quiet", c + "^{commit}"], repo).returncode == 0:
            return c
    return None


def cmd_worktrees(a):
    repo = os.path.realpath(a.repo)
    if not os.path.isdir(repo):
        print("not found: %s" % a.repo, file=sys.stderr)
        return 4
    try:
        wts = list_worktrees(repo)
    except RuntimeError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    base = pick_base(repo, a.base)
    if base is None:
        print("error: no origin/main or main to compare against; pass --base", file=sys.stderr)
        return 1
    here = os.path.realpath(os.getcwd())
    removable = []
    for i, w in enumerate(wts):
        path = w["path"]
        exists = os.path.isdir(path)
        w["main"] = (i == 0)
        w["size"] = dir_size(path) if exists else 0
        w["clean"] = None
        if exists:
            st = git(["status", "--porcelain", "--ignored"], path)  # ignored renders count as work
            w["clean"] = (st.returncode == 0 and st.stdout.strip() == "")
        w["merged"] = None
        if w["branch"] and w["head"]:
            w["merged"] = git(["merge-base", "--is-ancestor", w["head"], base], repo).returncode == 0
        why = None
        if w["main"]:
            why = "main checkout"
        elif w["bare"]:
            why = "bare"
        elif w["locked"]:
            why = "locked"
        elif not exists:
            why = "folder missing, git worktree prune clears it"
        elif inside(here, os.path.realpath(path)):
            why = "current directory is inside it"
        elif not w["branch"]:
            why = "detached head"
        elif not w["clean"]:
            why = "not clean"
        elif not w["merged"]:
            why = "not merged into %s" % base
        w["why"] = why
        if why is None:
            removable.append(w)
    for w in wts:
        print("%-7s %9s  branch=%-34s clean=%-3s merged=%-3s %s%s" % (
            "REMOVE" if w["why"] is None else ("main" if w["main"] else "keep"),
            human(w["size"]), w["branch"] or "(detached)",
            "-" if w["clean"] is None else ("yes" if w["clean"] else "no"),
            "-" if w["merged"] is None else ("yes" if w["merged"] else "no"),
            w["path"], "" if w["why"] is None else "  [%s]" % w["why"]))
    total = sum(w["size"] for w in removable)
    print("summary: base=%s worktrees=%d removable=%d (%s)" % (base, len(wts), len(removable), human(total)))
    print("note: a branch merged by squash or rebase is not an ancestor of %s, so it shows as not merged and is kept." % base)
    if not a.apply:
        print("dry run: nothing changed. Re-run with --apply to remove the REMOVE rows.")
        return 0
    failed = 0
    for w in removable:
        p = git(["worktree", "remove", w["path"]], repo)  # no --force: git itself refuses a dirty tree
        if p.returncode == 0:
            print("removed %s" % w["path"])
        else:
            failed += 1
            print("failed %s: %s" % (w["path"], p.stderr.strip()), file=sys.stderr)
    if git(["worktree", "prune"], repo).returncode != 0:
        failed += 1
        print("failed: git worktree prune", file=sys.stderr)
    return 1 if failed else 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="media_cleanup", allow_abbrev=False, description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")
    c = sub.add_parser("clean", allow_abbrev=False, help="move everything outside the keep manifest to the dated trash")
    c.add_argument("job")
    c.add_argument("--keep", required=True, help="file of relative paths or globs, one per line (or a JSON list)")
    g = c.add_mutually_exclusive_group()
    g.add_argument("--dry-run", action="store_true", help="list only (the default)")
    g.add_argument("--apply", action="store_true", help="move the rest to the trash")
    c.add_argument("--date", help=argparse.SUPPRESS)
    p = sub.add_parser("purge", allow_abbrev=False, help="delete trash days older than N days (needs --yes)")
    p.add_argument("--older-than", required=True)
    p.add_argument("--yes", action="store_true")
    p.add_argument("--today", help=argparse.SUPPRESS)
    w = sub.add_parser("worktrees", allow_abbrev=False, help="list git worktrees; --apply removes clean merged ones")
    w.add_argument("repo")
    w.add_argument("--apply", action="store_true")
    w.add_argument("--base", help="branch to test merges against (default origin/main, then main)")
    a = ap.parse_args(argv)
    if not a.cmd:
        ap.print_usage(sys.stderr)
        return 2
    return {"clean": cmd_clean, "purge": cmd_purge, "worktrees": cmd_worktrees}[a.cmd](a)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa
        print("error: %s" % e, file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""integrate.py: merge hand-offs into main deterministically (playbook 90, SYSTEM-REVIEW 6.2).

  make integrate [KEY=<hand-off key>] [DRY=1]

For every branch hand-off (oldest first; escalations are never touched), in a temporary worktree
`build/integrate/<key>` on branch `integrate/<key>` started from main:

  1. `git merge --no-ff --no-commit <branch>` (the shared files merge through the record-level driver
     `tools/agent/merge_shared.py` when it is installed: `make merge-driver`);
  2. `make rename APPLY=1`, `make stubs WRITE=1` (when the tool exists), `make merge-check STAGED=1`;
  3. `make status`, the hand-off's changelog row;
  4. `make check` (the full gate, in the temporary worktree);
  5. one merge commit holding the merge, the status and the changelog row;
  6. `git merge --ff-only` of that commit into main, then the hand-off is archived and cleared, the
     lock released and the worker's worktree removed when it is clean.

`main` is never dirty: a failed step leaves it untouched, removes the temporary worktree, and marks
the hand-off `integrate = rejected` with the reason and the log (`build/integrate/<key>.log`).
`make inbox` lists rejected hand-offs; the owner re-claims the unit (`make claim AGENT=<owner>
UNIT=<id>` reuses its lock and worktree), fixes the branch and hands off again, which clears the
rejection. DRY=1 stops after the check and leaves main alone.

A model is only needed when the driver reports a conflict in the same record; everything else is
mechanical. The integrator registers itself as agent `integrator` with the orchestrator role, so the
hand-off and lock tools accept it.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402
import heartbeat  # noqa: E402
import identity  # noqa: E402

AGENT = "integrator"
LINKS = (".venv", "build/toolchain", "build/re", "tools/vendor", "tools/setup/env.local.sh")
BRANCH_STATES = ("complete", "partial", "blocked", "review-passed", "review-failed")


class Rejected(Exception):
    pass


class AlreadyMerged(Exception):
    """The branch tip is already in main (merged by hand earlier): only the bookkeeping is left."""


def handoff_dir() -> Path:
    return common.common_dir() / "poolrad-handoffs"


def pending(key: str | None = None) -> list[Path]:
    """Branch hand-offs waiting, oldest first; a record already rejected waits for its worker."""
    files = sorted(handoff_dir().glob("*.md"), key=lambda p: p.stat().st_mtime)
    out = []
    for p in files:
        if key and p.stem != key:
            continue
        f = common.fields(p.read_text())
        if f.get("state") not in BRANCH_STATES:
            continue
        if f.get("integrate") == "rejected" and not key:
            continue
        out.append(p)
    return out


def run(args: list[str], cwd: Path, log, env: dict | None = None) -> int:
    log.write("$ %s\n" % " ".join(args))
    log.flush()
    r = subprocess.run(args, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, env=env, text=True)
    log.write("exit %d\n" % r.returncode)
    log.flush()
    return r.returncode


def add_changelog_row(path: Path, row: str) -> str:
    parts = [p.strip() for p in row.split("|") if p.strip()]
    if len(parts) != 3:
        raise Rejected("CHANGELOG must be '<section> | <change> | <evidence>', got %r" % row)
    line = "| %s | %s |\n" % (dt.date.today().isoformat(), " | ".join(parts))
    text = path.read_text()
    head = "|---|---|---|---|\n"
    if head not in text:
        raise Rejected("%s: no table header" % path)
    if line not in text:
        common.atomic_write(path, text.replace(head, head + line, 1))
    return line.strip()


def link_tools(main_dir: Path, wt: Path) -> None:
    for rel in LINKS:
        src, dst = main_dir / rel, wt / rel
        if src.exists() and not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.symlink_to(src)


def install_driver(main_dir: Path) -> None:
    """The record-level merge driver for the shared files (tools/agent/merge_shared.py), when present, and
    the pre-commit hook (tools/agent/hooks); both are per-clone git configuration shared by every worktree."""
    common.git("config", "core.hooksPath", "tools/agent/hooks", cwd=main_dir)
    if (main_dir / "tools/agent/merge_shared.py").exists():
        common.git("config", "merge.poolrad-shared.name", "record-level merge of the shared files", cwd=main_dir)
        common.git("config", "merge.poolrad-shared.driver",
                   ".venv/bin/python tools/agent/merge_shared.py %O %A %B %P", cwd=main_dir)


def mark(path: Path, **extra: str) -> None:
    """Rewrite the integrate_* fields of a hand-off record, keeping the worker's fields."""
    lines = [l for l in path.read_text().splitlines() if not l.startswith("integrate")]
    for k, v in extra.items():
        lines.append("%s = %s" % (k, common.single_line(str(v), k)))
    common.atomic_write(path, "\n".join(lines) + "\n")


def reject(path: Path, reason: str, log_path: Path) -> None:
    f = common.fields(path.read_text())
    reason = " ".join(reason.split())[:400]
    mark(path, integrate="rejected", integrate_reason=reason, integrate_log=str(log_path),
         integrate_time=dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"))
    control.event("integrate-rejected", agent=AGENT, key=path.stem, branch=f.get("branch", ""),
                  commit=f.get("commit", ""), reason=reason, log=str(log_path))
    print("integrate: %s rejected: %s (log %s)" % (path.stem, reason, log_path))


def make(target: str, cwd: Path, log, *extra: str) -> int:
    return run(["make", target, *extra], cwd, log, env={**os.environ, "POOLRAD_AGENT": AGENT})


def integrate_one(path: Path, main_dir: Path, dry: bool, py: str) -> bool:
    key = path.stem
    f = common.fields(path.read_text())
    branch, commit, state = f.get("branch", ""), f.get("commit", ""), f.get("state", "")
    agent = f.get("agent", "")
    logs = main_dir / "build/integrate"
    logs.mkdir(parents=True, exist_ok=True)
    log_path = logs / ("%s.log" % key)
    wt = logs / key
    tmp_branch = "integrate/%s" % key
    heartbeat.beat(AGENT, "integrating %s (%s, %s)" % (key, branch, state))
    with log_path.open("w") as log:
        log.write("integrate %s: branch %s commit %s state %s agent %s at %s\n" % (
            key, branch, commit, state, agent, dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")))
        try:
            if not branch or not common.git("branch", "--list", branch, cwd=main_dir):
                raise Rejected("branch %s does not exist" % branch)
            try:
                common.git("merge-base", "--is-ancestor", commit, branch, cwd=main_dir)
            except RuntimeError:
                raise Rejected("pinned commit %s is not on %s" % (commit, branch))
            tip = common.git("rev-parse", branch, cwd=main_dir)
            if subprocess.run(["git", "merge-base", "--is-ancestor", tip, "main"], cwd=main_dir,
                              capture_output=True).returncode == 0:
                # Merged earlier by hand and never cleared: only the bookkeeping below is left.
                log.write("branch tip %s is already in main; nothing to merge\n" % tip)
                print("integrate: %s was already merged (%s); clearing its record" % (key, tip[:12]))
                if dry:
                    return True
                raise AlreadyMerged()
            # The temporary worktree: always fresh, always from main.
            if wt.exists():
                subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=main_dir, capture_output=True)
                shutil.rmtree(wt, ignore_errors=True)
            if common.git("branch", "--list", tmp_branch, cwd=main_dir):
                common.git("branch", "-D", tmp_branch, cwd=main_dir)
            common.git("worktree", "add", "-b", tmp_branch, str(wt), "main", cwd=main_dir)
            link_tools(main_dir, wt)
            r = subprocess.run(["git", "merge", "--no-ff", "--no-commit", branch], cwd=wt,
                               capture_output=True, text=True)
            log.write(r.stdout + r.stderr)
            if r.returncode:
                conflicts = common.git("diff", "--name-only", "--diff-filter=U", cwd=wt).split()
                raise Rejected("merge conflict in %s" % ", ".join(conflicts or ["(see log)"]))
            if make("rename", wt, log, "APPLY=1"):
                raise Rejected("make rename APPLY=1 failed")
            if (wt / "tools/match/stubs.py").exists() and make("stubs", wt, log, "WRITE=1"):
                raise Rejected("make stubs WRITE=1 failed")
            common.git("add", "-u", cwd=wt)
            rc = make("merge-check", wt, log, "STAGED=1")
            if rc == 1:
                raise Rejected("make merge-check STAGED=1 found lost records (see log)")
            if rc:
                raise Rejected("make merge-check STAGED=1 could not run (see log)")
            if make("status", wt, log):
                raise Rejected("make status failed")
            if f.get("changelog"):
                add_changelog_row(wt / "docs/design/CHANGELOG.md", f["changelog"])
            common.git("add", "-u", cwd=wt)
            if make("check", wt, log):
                raise Rejected("make check failed (see log)")
            note = " ".join(f.get("note", "").split())[:72]
            msg = "Merge %s (%s)%s" % (branch, state, (": " + note) if note else "")
            trailers = ["--trailer", "Agent: %s" % AGENT]
            if agent:
                trailers += ["--trailer", "Agent: %s" % agent]
            common.git("commit", "-q", "-m", msg, *trailers, cwd=wt)
            merged = common.git("rev-parse", "HEAD", cwd=wt)
            if dry:
                print("integrate: DRY %s would fast-forward main to %s" % (key, merged[:12]))
                return True
            common.git("merge", "--ff-only", merged, cwd=main_dir)
            print("integrate: main is now %s (%s)" % (merged[:12], msg))
            control.event("integrate", agent=AGENT, key=key, branch=branch, commit=commit, merged=merged)
        except AlreadyMerged:
            pass
        except Rejected as e:
            reject(path, str(e), log_path)
            return False
        except RuntimeError as e:
            reject(path, "git: %s" % e, log_path)
            return False
        finally:
            subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=main_dir, capture_output=True)
            shutil.rmtree(wt, ignore_errors=True)
            subprocess.run(["git", "branch", "-D", tmp_branch], cwd=main_dir, capture_output=True)
    # The record, the lock and the worker's worktree (the usual orchestrator steps, now mechanical).
    import check
    import handoff
    import unlock
    try:
        check.require_receipt()
    except ValueError:
        # Only the already-merged path gets here without a receipt (main moved by hand): check main itself.
        with log_path.open("a") as log:
            if make("check", main_dir, log):
                print("integrate: %s is in main but make check on main fails (see %s)" % (key, log_path))
                return False
    try:
        with control.coordination_lock():
            handoff.finish(key, AGENT, "", changelog=False)   # the row is in the merge commit already
    except (ValueError, RuntimeError) as e:
        print("integrate: %s merged but its hand-off could not be cleared: %s" % (key, e))
        return True
    lock_key = key
    if unlock.main([lock_key, "--agent", AGENT]):
        print("integrate: lock %s left in place (see the message above); make inbox lists it" % lock_key)
        return True
    for row in common.git("worktree", "list", "--porcelain", cwd=main_dir).split("\n\n"):
        fld = dict(line.split(" ", 1) for line in row.splitlines() if " " in line)
        if fld.get("branch") == "refs/heads/" + branch:
            subprocess.run(["git", "worktree", "remove", fld["worktree"]], cwd=main_dir, capture_output=True)
    subprocess.run(["git", "branch", "-d", branch], cwd=main_dir, capture_output=True)
    return True


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--key", default="")                 # never from the environment: a nested make check would inherit it
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args(argv)
    try:
        common.require_main("integrate")
        main_dir = common.main_checkout()
        if common.git("status", "--porcelain", "--untracked-files=no", cwd=main_dir):
            raise ValueError("main has uncommitted tracked changes; commit or stash them first")
        identity.ensure(AGENT, "orchestrator", "make", "script", "integrate")
        install_driver(main_dir)
        todo = pending(a.key or None)
        if not todo:
            print("integrate: nothing to merge%s" % (" for %s" % a.key if a.key else ""))
            return 0
        ok = 0
        for p in todo:
            if integrate_one(p, main_dir, a.dry, sys.executable):
                ok += 1
        heartbeat.beat(AGENT, "integrated %d of %d" % (ok, len(todo)), done=True)
        print("integrate: %d of %d hand-offs merged" % (ok, len(todo)))
        return 0 if ok == len(todo) else 1
    except (ValueError, RuntimeError, OSError) as e:
        print("integrate: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""worker.py: a supervisor that owns a lock, posts heartbeats and runs disposable model sessions.

  make worker AGENT=<name> ROLE=decompiler|reviewer [UNIT=<id>] [BATCH=6] [SESSION_CMD='...']
              [MAX_SESSIONS=<n>] [TIMEOUT=<minutes>] [MAX_ATTEMPTS=2] [IDLE=300]
              [HARNESS= MODEL= SESSION= VARIANT=]
  .venv/bin/python tools/agent/worker.py --frontier [UNIT]         print the frontier (exhausted routines)
  .venv/bin/python tools/agent/worker.py --release UNIT [ROUTINE]   clear frontier entries (after a fix)

Why (docs/process/SYSTEM-REVIEW-2026-10-12.md 5.4 and 6.5): when a model session is the lock holder,
the lock's lifetime is the model's context window, and every exhausted session leaves a lock and a
parked draft for a human. Here the lock holder is this script. It claims a unit, plans bounded batches
of routines, runs ONE fresh model session per batch in the claimed worktree, verifies what the session
committed with `make match`, and on exhaustion hands the branch off (or gives the untouched claim
back). No lock outlives the process: SIGINT, SIGTERM and crashes end in a hand-off or an owner
release, then a `stopped` heartbeat. The supervisor never calls a model and decides nothing a model
should decide; everything judged happens inside a session, everything verified happens here.

Decompiler role, per unit:
  1. identity.ensure(agent, role, ...) registers or checks the agent's creation metadata.
  2. control.state(): running claims (claim.py); draining finishes the current unit and stops; paused
     or stopped ends the run (after a hand-off when commits exist). Nothing claimable: an idle
     heartbeat, a bounded sleep (IDLE seconds), another look, until control is no longer running.
  3. Batch planning: the unit's routines of re/symbols.toml that are not at L2/L3, whose notes do not
     say `blocked`, that are still `{@stub}` in src/<ID>.PAS and that are not exhausted in the frontier,
     in address order, BATCH at a time; a `{@stub-init}` initialisation part is one last item.
  4. One session per batch from tools/agent/worker_prompt.md (placeholders $worktree, $unit, $agent,
     $routines, $batch, ...), started with SESSION_CMD in its own process group, killed as a group after
     TIMEOUT minutes; stdout and stderr go to build/worker/<agent>/<unit>-batch<N>.log in the main
     checkout. A background thread posts a heartbeat every 10 minutes while it runs.
  5. After the session: uncommitted changes are saved to build/worker/<agent>/<unit>-batch<N>.patch and
     discarded; `make match UNIT=<id>` must be clean, else the batch's commits are saved with
     `git format-patch` and the branch is reset to where the batch started; else `make match WRITE=1`
     records L2 and any registry change is committed (`re: record L2 (worker)`). Routines of the batch
     still `{@stub}` without a `blocked` note get one more attempt in the frontier.
  6. Frontier: .git/poolrad-frontier/<unit>.json in the clone's common git directory,
     {"<routine id>": {"attempts": n, "last": "<iso time>", "agent": "...", "batch_log": "<path>"}}.
     A routine with attempts >= MAX_ATTEMPTS is not planned again until `--release` clears it.
  7. Nothing left to plan: `make check` in the worktree (log build/worker/<agent>/<unit>-check.log),
     then `make handoff STATE=complete|partial` from the worktree with an automatic note; a branch with
     no commits beyond main is given back with `unlock.py --owner` (lock, worktree and branch removed).
     MAX_SESSIONS reached: hand off what exists (partial) and stop.

Reviewer role: claims with --review, runs one session from tools/agent/review_prompt.md; a committed
work/reviews/<id>.md with no open must-fix and the review stamp written (`make review-pass CHECK=1`
passes) is handed off as review-passed, otherwise review-failed with the must-fix lines in the note; a
session that committed nothing ends in an owner release.

Arguments and environment (the Makefile passes the variables as options):
  --agent AGENT                 the worker's agent name (unique; the lock, heartbeat and trailer carry it)
  --role ROLE                   decompiler or reviewer
  --unit UNIT                   claim this unit (or review) once and stop after it; default: the queue
  --batch BATCH                 routines per session (default 6)
  --session-cmd SESSION_CMD     shell template with {prompt_file}, {worktree}, {model_flag} and {title}
                                (`<agent> <unit>-batch<N>`, quoted: OpenCode's session title, so each
                                session's cost can be found again); default
                                DEFAULT_SESSION_CMD below
  --session-model SESSION_MODEL model passed as {model_flag} (` --model <m>`), empty by default
  --max-sessions MAX_SESSIONS   stop after this many sessions in this run (default unlimited)
  --timeout TIMEOUT             minutes a session may run before its process group is killed (90)
  --max-attempts MAX_ATTEMPTS   frontier limit per routine (2)
  --idle IDLE                   seconds to sleep when nothing is claimable (300)
  --harness/--model/--session/--variant   creation metadata (HARNESS, MODEL, SESSION, VARIANT, also
                                POOLRAD_HARNESS, POOLRAD_MODEL, POOLRAD_SESSION_ID, POOLRAD_VARIANT),
                                needed the first time a name is used (`make agent-register` does the same)

The default session command runs the installed opencode (v2: `opencode run [flags] [message]`, no
directory flag, so the template changes directory first; `--standalone` keeps the server inside the
process group the supervisor kills on timeout, `--auto` approves tool use in a non-interactive run):

  cd {worktree} && opencode run --standalone --auto --title {title}{model_flag} "$(cat {prompt_file})"

An alternative for the Claude CLI (not installed on the machine this was written on):

  SESSION_CMD='cd {worktree} && claude -p "$(cat {prompt_file})"'
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import io
import json
import os
import re
import shlex
import signal
import string
import subprocess
import sys
import threading
import time
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402
import heartbeat  # noqa: E402
import identity  # noqa: E402

DEFAULT_SESSION_CMD = 'cd {worktree} && opencode run --standalone --auto --title {title}{model_flag} "$(cat {prompt_file})"'
DEFAULT_BATCH = 6
DEFAULT_TIMEOUT_MINUTES = 90
DEFAULT_MAX_ATTEMPTS = 2
DEFAULT_IDLE_SECONDS = 300
PULSE_SECONDS = 600                  # heartbeat period while a session or a check runs
KILL_GRACE_SECONDS = 10
BLOCKED = re.compile(r"(?<![A-Za-z])blocked(?![A-Za-z])", re.I)
STUB_RE = re.compile(r"^\s*\{@stub\}\s*(?:procedure|function)\s+([A-Za-z_][A-Za-z0-9_]*)", re.I | re.M)
STUB_INIT = "{@stub-init}"
HERE = Path(__file__).resolve().parent


class Interrupted(Exception):
    """SIGINT or SIGTERM: finish by handing off or releasing, then stop."""


# ----------------------------------------------------------------------------- registry and planning
@dataclass
class Item:
    id: str                        # re/symbols.toml id, or "<unit>:init" for an unlisted initialisation part
    name: str
    addr: int
    init: bool = False

    def line(self) -> str:
        return "%s %s%s" % (self.id, self.name, " (initialisation part)" if self.init else "")


def read_routines(root: Path) -> list[dict]:
    return tomllib.loads((root / "re/symbols.toml").read_text())["routine"]


def unit_routines(root: Path, unit: str) -> list[dict]:
    return [r for r in read_routines(root) if r.get("unit") == unit]


def stub_names(text: str) -> set[str]:
    """Names on `{@stub}` header lines (the routine is identified by the name on the line)."""
    return {m.group(1).lower() for m in STUB_RE.finditer(text)}


def is_init(r: dict) -> bool:
    return str(r.get("name", "")).lower().endswith("_init")


def done(r: dict) -> bool:
    return r.get("level") in ("L2", "L3")


def blocked(r: dict) -> bool:
    return bool(BLOCKED.search(str(r.get("notes", ""))))


def addr_of(r: dict) -> int:
    m = re.search(r":([0-9A-Fa-f]{1,4})$", str(r.get("addr") or r.get("id") or ""))
    return int(m.group(1), 16) if m else 0xFFFF


def plan(root: Path, unit: str, frontier: dict, max_attempts: int) -> list[Item]:
    """Everything of the unit a session could still work on, in address order, the init part last."""
    source = root / "src" / ("%s.PAS" % unit.upper())
    text = source.read_text() if source.exists() else ""
    stubs = stub_names(text)
    exhausted = {rid for rid, e in frontier.items() if int(e.get("attempts", 0)) >= max_attempts}
    rs = unit_routines(root, unit)
    items = []
    for r in rs:
        if done(r) or blocked(r) or is_init(r) or r["id"] in exhausted:
            continue
        if str(r.get("name", "")).lower() not in stubs:
            continue                               # decompiled but not yet recorded, or not in the source
        items.append(Item(r["id"], r["name"], addr_of(r)))
    items.sort(key=lambda i: i.addr)
    if STUB_INIT in text:
        init = next((r for r in rs if is_init(r)), None)
        rid = init["id"] if init else "%s:init" % unit
        if not (init and (done(init) or blocked(init))) and rid not in exhausted:
            items.append(Item(rid, init["name"] if init else "%s_init" % unit, 0x10000, init=True))
    return items


def batches(items: list[Item], size: int) -> list[list[Item]]:
    size = max(1, size)
    return [items[i:i + size] for i in range(0, len(items), size)]


# ----------------------------------------------------------------------------- frontier
def frontier_dir() -> Path:
    d = common.common_dir() / "poolrad-frontier"
    d.mkdir(exist_ok=True)
    return d


def frontier_path(unit: str) -> Path:
    return frontier_dir() / ("%s.json" % common.identifier(unit, "unit"))


def load_frontier(unit: str) -> dict:
    p = frontier_path(unit)
    if not p.exists():
        return {}
    data = json.loads(p.read_text())
    return data if isinstance(data, dict) else {}


def save_frontier(unit: str, data: dict) -> None:
    p = frontier_path(unit)
    if data:
        common.atomic_write(p, json.dumps(data, indent=1, sort_keys=True) + "\n")
    else:
        p.unlink(missing_ok=True)


def bump_frontier(unit: str, rid: str, agent: str, batch_log: str) -> int:
    data = load_frontier(unit)
    entry = data.get(rid) or {"attempts": 0}
    entry.update(attempts=int(entry.get("attempts", 0)) + 1, agent=agent, batch_log=batch_log,
                 last=dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"))
    data[rid] = entry
    save_frontier(unit, data)
    return entry["attempts"]


def release_frontier(unit: str, routine: str | None = None) -> int:
    """Clear a unit's frontier, or one routine of it (by id or name); returns how many entries went."""
    data = load_frontier(unit)
    if routine is None:
        n = len(data)
        save_frontier(unit, {})
        return n
    keys = [k for k in data if k.lower() == routine.lower() or k.split(":")[-1].lower() == routine.lower()]
    for k in keys:
        del data[k]
    save_frontier(unit, data)
    return len(keys)


def frontier_listing(unit: str | None = None) -> list[str]:
    paths = [frontier_path(unit)] if unit else sorted(frontier_dir().glob("*.json"))
    rows = []
    for p in paths:
        if not p.exists():
            continue
        for rid, e in sorted(json.loads(p.read_text()).items()):
            rows.append("%-8s %-14s attempts %d  last %s  by %s  log %s" % (
                p.stem, rid, int(e.get("attempts", 0)), e.get("last", "?"), e.get("agent", "?"),
                e.get("batch_log", "?")))
    return rows


# ----------------------------------------------------------------------------- git and shell helpers
def git_out(wt: Path, *args: str) -> str:
    return common.git(*args, cwd=wt)


def head_of(wt: Path) -> str:
    return git_out(wt, "rev-parse", "HEAD")


def commits_beyond_main(wt: Path) -> int:
    try:
        return int(git_out(wt, "rev-list", "--count", "main..HEAD") or 0)
    except RuntimeError:
        return 0


def salvage(wt: Path, patch: Path) -> bool:
    """Save every uncommitted change of the worktree to `patch` and discard it (tracked files restored,
    untracked files under src/, re/, docs/, work/ and the unit's probes removed). True when there was
    anything to save. The session's drafts are then in the patch, never parked in the branch."""
    status = git_out(wt, "status", "--porcelain", "--untracked-files=all")
    if not status.strip():
        return False
    parts = ["# git status --porcelain of %s at %s\n%s\n" % (
        wt, dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), status)]
    diff = subprocess.run(["git", "diff", "HEAD", "--"], cwd=wt, capture_output=True, text=True,
                          errors="replace").stdout
    if diff.strip():
        parts.append("# git diff HEAD\n%s\n" % diff)
    for line in status.splitlines():
        if line.startswith("??"):
            rel = line[3:].strip()
            p = wt / rel
            try:
                body = p.read_text(errors="replace") if p.is_file() and p.stat().st_size < 2_000_000 else "(not saved)"
            except OSError:
                body = "(unreadable)"
            parts.append("# untracked: %s\n%s\n" % (rel, body))
    patch.parent.mkdir(parents=True, exist_ok=True)
    patch.write_text("".join(parts))
    git_out(wt, "checkout", "--", ".")
    git_out(wt, "clean", "-fd", "--", "src", "re", "docs", "work", "tools/re/tp_idioms")
    return True


def reset_batch(wt: Path, start: str, patch_dir: Path) -> int:
    """Save the commits since `start` as patches, then reset the branch to `start`; returns their count."""
    n = int(git_out(wt, "rev-list", "--count", "%s..HEAD" % start) or 0)
    if n:
        patch_dir.mkdir(parents=True, exist_ok=True)
        git_out(wt, "format-patch", "-o", str(patch_dir), "%s..HEAD" % start)
    git_out(wt, "reset", "--hard", start)
    return n


def run_make(wt: Path, args: list[str], log: Path, env: dict | None = None) -> int:
    """Run `make <args>` in the worktree, appending its output to `log`; the exit code."""
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a") as f:
        f.write("\n$ make %s   (%s)\n" % (" ".join(shlex.quote(a) for a in args),
                                          dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")))
        f.flush()
        r = subprocess.run(["make", *args], cwd=wt, stdout=f, stderr=subprocess.STDOUT,
                           env={**os.environ, **(env or {})})
        f.write("$ exit %d\n" % r.returncode)
    return r.returncode


@dataclass
class SessionResult:
    returncode: int
    timed_out: bool
    seconds: float


def kill_group(proc: subprocess.Popen) -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            return
        try:
            proc.wait(timeout=KILL_GRACE_SECONDS)
            return
        except subprocess.TimeoutExpired:
            continue


def run_session(cmd_template: str, prompt_file: Path, wt: Path, log: Path, timeout_s: float,
                model_flag: str = "", title: str = "") -> SessionResult:
    """Run one model session (a shell command built from the template) in its own process group, its
    output appended to `log`; the whole group is killed when `timeout_s` passes or on interruption."""
    cmd = cmd_template.format(prompt_file=shlex.quote(str(prompt_file)), worktree=shlex.quote(str(wt)),
                              model_flag=model_flag, title=shlex.quote(title or prompt_file.stem))
    log.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with log.open("a") as f:
        f.write("\n$ %s   (%s)\n" % (cmd, dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")))
        f.flush()
        proc = subprocess.Popen(cmd, shell=True, cwd=wt, stdout=f, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, start_new_session=True,
                                env={**os.environ, "POOLRAD_WORKER": "1"})
        timed_out = False
        try:
            try:
                proc.wait(timeout=timeout_s)
            except subprocess.TimeoutExpired:
                timed_out = True
                kill_group(proc)
        except BaseException:                       # Interrupted, KeyboardInterrupt: never leave it running
            kill_group(proc)
            raise
        rc = proc.returncode if proc.returncode is not None else -1
        f.write("$ exit %d%s after %.0f s\n" % (rc, " (timed out, killed)" if timed_out else "",
                                                time.monotonic() - start))
    return SessionResult(rc, timed_out, time.monotonic() - start)


class Pulse:
    """A background heartbeat while something long runs (a session, make check)."""

    def __init__(self, agent: str, note: str, period: float = PULSE_SECONDS):
        self.agent, self.note, self.period = agent, note, period
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        while not self.stop.wait(self.period):
            try:
                heartbeat.beat(self.agent, self.note)
            except Exception:                        # a heartbeat never breaks the work
                pass

    def __enter__(self):
        try:
            heartbeat.beat(self.agent, self.note)
        except Exception:
            pass
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.stop.set()
        self.thread.join(timeout=5)


# ----------------------------------------------------------------------------- prompts
def render(template: Path, mapping: dict) -> str:
    return string.Template(template.read_text()).safe_substitute(mapping)


def batch_prompt(wt: Path, unit: str, agent: str, items: list[Item], number: int, notes: list[str] = ()) -> str:
    """The session's prompt; `notes` are the orchestrator's items of work/blockers.md that name the unit
    (claim.blocker_notes), which a session would otherwise never see."""
    text = ""
    if notes:
        text = ("Notes on this unit (work/blockers.md, or why make integrate rejected the last hand-off); do what they say first:\n" +
                "\n".join("  " + n for n in notes) + "\n")
    return render(HERE / "worker_prompt.md", dict(
        worktree=str(wt), unit=unit, unit_file="%s.PAS" % unit.upper(), unit_init="%s_init" % unit,
        agent=agent, batch=number, branch="unit/%s" % unit, notes=text,
        routines="\n".join("  %d. %s" % (k + 1, i.line()) for k, i in enumerate(items))))


def review_prompt(wt: Path, unit: str, agent: str) -> str:
    return render(HERE / "review_prompt.md", dict(
        worktree=str(wt), unit=unit, unit_file="%s.PAS" % unit.upper(), agent=agent,
        branch="review/%s" % unit))


# ----------------------------------------------------------------------------- the supervisor
@dataclass
class Config:
    agent: str
    role: str
    unit: str = ""
    batch: int = DEFAULT_BATCH
    session_cmd: str = DEFAULT_SESSION_CMD
    session_model: str = ""
    max_sessions: int = 0
    timeout_minutes: float = DEFAULT_TIMEOUT_MINUTES
    max_attempts: int = DEFAULT_MAX_ATTEMPTS
    idle_seconds: float = DEFAULT_IDLE_SECONDS
    harness: str = ""
    model: str = ""
    session: str = ""
    variant: str = ""
    sleep: object = field(default=None)            # tests replace the bounded wait


@dataclass
class UnitRun:
    key: str                                        # lock key: <unit> or review-<unit>
    unit: str
    wt: Path
    batch: int = 0
    matched: int = 0
    blocked: int = 0
    frontier: int = 0
    sessions: int = 0


class Worker:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.agent = common.identifier(cfg.agent, "agent")
        if cfg.role not in ("decompiler", "reviewer"):
            raise ValueError("ROLE must be decompiler or reviewer")
        self.main = common.main_checkout()
        self.logs = self.main / "build/worker" / self.agent
        self.sessions = 0
        self.current: UnitRun | None = None
        self.stopping = ""
        self.skipped: set[str] = set()              # units given back untouched in this run

    # ---- small helpers
    def say(self, note: str) -> None:
        print("worker %s: %s" % (self.agent, " ".join(note.split())), flush=True)
        try:
            heartbeat.beat(self.agent, note)
        except Exception:
            pass

    def wait(self, seconds: float) -> None:
        if self.cfg.sleep is not None:
            self.cfg.sleep(seconds)
        else:
            time.sleep(seconds)

    def model_flag(self) -> str:
        return (" --model " + shlex.quote(self.cfg.session_model)) if self.cfg.session_model else ""

    def state(self) -> str:
        return control.state()["state"]

    # ---- claiming
    def claim(self, unit: str = "") -> tuple[str, Path] | None:
        """Claim through claim.py; (lock key, worktree) or None when nothing is claimable now."""
        import claim as claim_tool
        args = ["--agent", self.agent]
        if unit:
            args += ["--unit", unit]
        if self.cfg.role == "reviewer":
            args.append("--review")
        for opt, value in (("--harness", self.cfg.harness), ("--model", self.cfg.model),
                           ("--session", self.cfg.session), ("--variant", self.cfg.variant)):
            if value:
                args += [opt, value]
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = claim_tool.main(args)
        text = out.getvalue() + err.getvalue()
        print(text.rstrip(), flush=True)
        if rc != 0:
            if unit:
                raise RuntimeError("could not claim %s: %s" % (unit, " ".join(text.split())[-300:]))
            return None
        m = re.search(r"^claim: worktree (\S+) \(branch (\S+)\)$", text, re.M)
        if not m:
            raise RuntimeError("claim printed no worktree line:\n" + text)
        wt, branch = Path(m.group(1)), m.group(2)
        uid = branch.split("/", 1)[1]
        key = ("review-" + uid) if branch.startswith("review/") else uid
        return key, wt

    # ---- the per-unit loop
    def run(self) -> int:
        identity.ensure(self.agent, self.cfg.role, self.cfg.harness, self.cfg.model, self.cfg.session,
                        self.cfg.variant)
        self.say("worker started (%s); checking control" % self.cfg.role)
        exit_code = 0
        try:
            while True:
                st = self.state()
                if st != "running":
                    self.stopping = "control is %s" % st
                    break
                claimed = self.claim(self.cfg.unit)
                if claimed is None:
                    self.say("idle: nothing to claim, looking again in %d s" % self.cfg.idle_seconds)
                    self.wait(self.cfg.idle_seconds)
                    continue
                key, wt = claimed
                unit = key[len("review-"):] if key.startswith("review-") else key
                self.current = UnitRun(key, unit, wt)
                if key in self.skipped and not self.cfg.unit:
                    # Given back untouched earlier in this run (nothing plannable): the queue would offer
                    # it again at once, so give it back and wait instead of spinning.
                    self.finish(self.current, "nothing plannable")
                    self.current = None
                    self.say("idle: %s has nothing plannable (frontier or blocked); looking again in %d s" % (
                        key, self.cfg.idle_seconds))
                    self.wait(self.cfg.idle_seconds)
                    continue
                if self.cfg.role == "reviewer":
                    self.work_review(self.current)
                else:
                    self.work_unit(self.current)
                self.finish(self.current, "done")
                self.current = None
                if self.cfg.unit or self.stopping:
                    break
                if self.state() == "draining":
                    self.stopping = "control is draining"
                    break
        except Interrupted as e:
            self.stopping = "interrupted by %s" % e
            exit_code = 130
        except Exception as e:                      # noqa: BLE001  anything: still hand off or release
            self.stopping = "crashed: %s: %s" % (type(e).__name__, " ".join(str(e).split())[:300])
            exit_code = 1
            print("worker: %s" % self.stopping, file=sys.stderr, flush=True)
        finally:
            if self.current is not None:
                for s in (signal.SIGINT, signal.SIGTERM):      # a second signal must not abort the hand-off
                    signal.signal(s, lambda *_: print("worker: finishing %s, please wait" % self.current.key,
                                                      file=sys.stderr))
                try:
                    self.finish(self.current, self.stopping or "stopping")
                except Exception as e:              # noqa: BLE001
                    print("worker: could not finish %s: %s" % (self.current.key, e), file=sys.stderr)
                    exit_code = exit_code or 1
                self.current = None
            try:
                os.chdir(self.main)
                heartbeat.beat(self.agent, "worker stopped: %s" % (self.stopping or "no more work"), done=True)
            except Exception:
                pass
        return exit_code

    def work_unit(self, run: UnitRun) -> None:
        os.chdir(run.wt)
        while True:
            st = self.state()
            if st in ("paused", "stopped"):
                self.stopping = "control is %s" % st
                return
            if self.cfg.max_sessions and self.sessions >= self.cfg.max_sessions:
                self.stopping = "MAX_SESSIONS=%d reached" % self.cfg.max_sessions
                return
            items = plan(run.wt, run.unit, load_frontier(run.unit), self.cfg.max_attempts)
            if not items:
                return
            batch = items[:self.cfg.batch]
            run.batch += 1
            self.run_batch(run, batch)

    def run_batch(self, run: UnitRun, batch: list[Item]) -> None:
        tag = "%s-batch%d" % (run.unit, run.batch)
        log = self.logs / (tag + ".log")
        prompt_file = self.logs / (tag + ".prompt.md")
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        import claim as claim_tool
        notes = claim_tool.blocker_notes(self.main, run.unit)
        why = claim_tool.rejection(run.unit)
        if why:
            notes = list(notes) + ["make integrate rejected this unit's last hand-off: %s. Fix that first "
                                   "(merge main into the branch if it is behind, resolve, make check), then continue." % why]
        prompt_file.write_text(batch_prompt(run.wt, run.unit, self.agent, batch, run.batch, notes))
        start = head_of(run.wt)
        note = "unit %s batch %d: routines %s" % (run.unit, run.batch, ", ".join(i.name for i in batch))
        self.sessions += 1
        run.sessions += 1
        with Pulse(self.agent, note):
            result = run_session(self.cfg.session_cmd, prompt_file, run.wt, log,
                                 self.cfg.timeout_minutes * 60, self.model_flag(), "%s %s" % (self.agent, tag))
        self.say("%s: session ended (exit %d%s); verifying" % (
            note, result.returncode, ", timed out" if result.timed_out else ""))
        self.verify_batch(run, batch, start, log)

    def verify_batch(self, run: UnitRun, batch: list[Item], start: str, log: Path) -> None:
        tag = "%s-batch%d" % (run.unit, run.batch)
        if salvage(run.wt, self.logs / (tag + ".patch")):
            print("worker: uncommitted changes saved to %s and discarded" % (self.logs / (tag + ".patch")))
        with Pulse(self.agent, "unit %s batch %d: make match" % (run.unit, run.batch)):
            rc = run_make(run.wt, ["match", "UNIT=%s" % run.unit], log)
            if rc != 0:
                n = reset_batch(run.wt, start, self.logs / (tag + "-commits"))
                print("worker: make match differs after batch %d; %d commit(s) saved to %s and reset to %s" % (
                    run.batch, n, self.logs / (tag + "-commits"), start[:12]))
            else:
                run_make(run.wt, ["match", "UNIT=%s" % run.unit, "WRITE=1"], log)
                if git_out(run.wt, "status", "--porcelain", "--", "re/symbols.toml"):
                    git_out(run.wt, "add", "re/symbols.toml")
                    git_out(run.wt, "commit", "-q", "-m", "re: record L2 (worker)", "--trailer", "Agent: %s" % self.agent)
        for item, outcome in self.outcomes(run, batch):
            if outcome == "matched":
                run.matched += 1
            elif outcome == "blocked":
                run.blocked += 1
            elif outcome == "stub":
                attempts = bump_frontier(run.unit, item.id, self.agent, str(log))
                run.frontier += 1
                print("worker: %s %s untouched or failed; frontier attempts %d" % (item.id, item.name, attempts))
            else:
                print("worker: %s %s is neither a stub nor recorded; left for the next batch" % (item.id, item.name))

    @staticmethod
    def outcomes(run: UnitRun, batch: list[Item]) -> list[tuple[Item, str]]:
        """What became of each item: matched (L2/L3 now), blocked (a blocked note), stub (still a
        {@stub}, so one more frontier attempt) or other. The registry's current name is used: a session
        may have renamed the routine (the id never changes)."""
        rs = {r["id"]: r for r in unit_routines(run.wt, run.unit)}
        source = run.wt / "src" / ("%s.PAS" % run.unit.upper())
        text = source.read_text() if source.exists() else ""
        stubs = stub_names(text)
        out = []
        for item in batch:
            r = rs.get(item.id)
            if item.init:
                if (r and done(r)) or STUB_INIT not in text:
                    out.append((item, "matched"))
                elif r and blocked(r):
                    out.append((item, "blocked"))
                else:
                    out.append((item, "stub"))
            elif r is None:
                out.append((item, "stub"))
            elif done(r):
                out.append((item, "matched"))
            elif blocked(r):
                out.append((item, "blocked"))
            elif str(r.get("name", "")).lower() in stubs:
                out.append((item, "stub"))
            else:
                out.append((item, "other"))
        return out

    # ---- reviews
    def work_review(self, run: UnitRun) -> None:
        os.chdir(run.wt)
        st = self.state()
        if st in ("paused", "stopped"):
            self.stopping = "control is %s" % st
            return
        if self.cfg.max_sessions and self.sessions >= self.cfg.max_sessions:
            self.stopping = "MAX_SESSIONS=%d reached" % self.cfg.max_sessions
            return
        run.batch = 1
        tag = "%s-review" % run.unit
        log = self.logs / (tag + ".log")
        prompt_file = self.logs / (tag + ".prompt.md")
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(review_prompt(run.wt, run.unit, self.agent))
        self.sessions += 1
        run.sessions += 1
        with Pulse(self.agent, "review %s: session running" % run.unit):
            result = run_session(self.cfg.session_cmd, prompt_file, run.wt, log,
                                 self.cfg.timeout_minutes * 60, self.model_flag(), "%s %s" % (self.agent, tag))
        self.say("review %s: session ended (exit %d%s)" % (
            run.unit, result.returncode, ", timed out" if result.timed_out else ""))
        if salvage(run.wt, self.logs / (tag + ".patch")):
            print("worker: uncommitted review changes saved to %s and discarded" % (self.logs / (tag + ".patch")))

    def review_outcome(self, run: UnitRun) -> tuple[str, str]:
        """(state, note) for the hand-off of a review branch that has commits."""
        review = run.wt / "work/reviews" / ("%s.md" % run.unit)
        try:
            tracked = bool(git_out(run.wt, "ls-files", "--", str(review.relative_to(run.wt))))
        except RuntimeError:
            tracked = False
        if not review.exists() or not tracked:
            return "review-failed", "worker: the session committed no work/reviews/%s.md" % run.unit
        must_fix = [l.strip() for l in review.read_text().splitlines()
                    if re.match(r"\s*-\s*\[ \]\s*must-fix\b", l, re.I)]
        if must_fix:
            return "review-failed", "worker: %d must-fix: %s" % (len(must_fix), " ; ".join(must_fix))[:900]
        log = self.logs / ("%s-review.log" % run.unit)
        if run_make(run.wt, ["review-pass", "UNIT=%s" % run.unit, "CHECK=1"], log) != 0:
            return "review-failed", "worker: no open must-fix but make review-pass CHECK=1 fails (see %s)" % log
        stamped = all(str(r.get("review", "")).startswith("passed") for r in unit_routines(run.wt, run.unit))
        if not stamped:                                  # the deterministic step the session skipped
            run_make(run.wt, ["review-pass", "UNIT=%s" % run.unit], log)
            if git_out(run.wt, "status", "--porcelain", "--", "re/symbols.toml"):
                git_out(run.wt, "add", "re/symbols.toml")
                git_out(run.wt, "commit", "-q", "-m", "re: review %s passed (worker)" % run.unit,
                        "--trailer", "Agent: %s" % self.agent)
        return "review-passed", "worker: review of %s passed, no open must-fix, stamp written" % run.unit

    # ---- ending a claim: hand off or give back
    def finish(self, run: UnitRun, why: str) -> None:
        """Never leave the lock: hand the branch off when it has commits, else release it (owner path)."""
        try:
            os.chdir(run.wt)
        except OSError:
            os.chdir(self.main)
            return                                       # the worktree is gone: nothing to hand off
        tag = "%s-%s" % (run.unit, "review" if run.key.startswith("review-") else "batch%d" % max(run.batch, 1))
        if salvage(run.wt, self.logs / (tag + ".final.patch")):
            print("worker: uncommitted changes saved to %s and discarded" % (self.logs / (tag + ".final.patch")))
        if commits_beyond_main(run.wt) == 0:
            os.chdir(self.main)
            self.release(run)
            return
        if run.key.startswith("review-"):
            state, note = self.review_outcome(run)
            check_log = None
        else:
            check_log = self.logs / ("%s-check.log" % run.unit)
            with Pulse(self.agent, "unit %s: make check before the hand-off" % run.unit):
                green = run_make(run.wt, ["check"], check_log) == 0
            rs = unit_routines(run.wt, run.unit)
            state = "complete" if rs and all(done(r) for r in rs) else "partial"
            note = "worker: %d matched this run, %d blocked, %d in frontier, check %s (%s); %s" % (
                run.matched, run.blocked, run.frontier, "green" if green else "RED", check_log, why)
        self.say("handing off %s as %s" % (run.key, state))
        rc = run_make(run.wt, ["handoff", "AGENT=%s" % self.agent, "UNIT=%s" % run.unit, "STATE=%s" % state,
                               "NOTE=%s" % " ".join(note.split()), "CHANGELOG="], self.logs / (run.unit + "-handoff.log"))
        if rc != 0:
            # The lock must still end in a record a human sees: escalate from the same worktree.
            esc = ("worker could not hand off %s as %s (make handoff exit %d, log %s); the branch keeps its "
                   "commits and its lock" % (run.key, state, rc, self.logs / (run.unit + "-handoff.log")))
            run_make(run.wt, ["handoff", "AGENT=%s" % self.agent, "UNIT=%s" % run.unit, "STATE=escalate",
                              "NOTE=%s" % esc, "CHANGELOG="], self.logs / (run.unit + "-handoff.log"))
            print("worker: " + esc, file=sys.stderr)
        os.chdir(self.main)

    def release(self, run: UnitRun) -> None:
        import unlock
        self.say("giving back %s: nothing beyond main" % run.key)
        self.skipped.add(run.key)
        if unlock.main([run.key, "--agent", self.agent, "--owner"]) != 0:
            print("worker: owner release of %s refused; the lock stays for the human (make inbox)" % run.key,
                  file=sys.stderr)


# ----------------------------------------------------------------------------- CLI
def install_signals(worker: Worker) -> None:
    def handler(signum, _frame):
        raise Interrupted(signal.Signals(signum).name)
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, handler)


def env_default(name: str, fallback: str = "") -> str:
    return os.environ.get(name, fallback)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--agent", default=env_default("AGENT"))
    ap.add_argument("--role", default=env_default("ROLE", "decompiler"))
    ap.add_argument("--unit", default=env_default("UNIT"))
    ap.add_argument("--batch", type=int, default=int(env_default("BATCH", str(DEFAULT_BATCH)) or DEFAULT_BATCH))
    ap.add_argument("--session-cmd", default=env_default("SESSION_CMD", DEFAULT_SESSION_CMD))
    ap.add_argument("--session-model", default=env_default("SESSION_MODEL"))
    ap.add_argument("--max-sessions", type=int, default=int(env_default("MAX_SESSIONS", "0") or 0))
    ap.add_argument("--timeout", type=float, default=float(env_default("TIMEOUT", str(DEFAULT_TIMEOUT_MINUTES)) or DEFAULT_TIMEOUT_MINUTES))
    ap.add_argument("--max-attempts", type=int, default=int(env_default("MAX_ATTEMPTS", str(DEFAULT_MAX_ATTEMPTS)) or DEFAULT_MAX_ATTEMPTS))
    ap.add_argument("--idle", type=float, default=float(env_default("IDLE", str(DEFAULT_IDLE_SECONDS)) or DEFAULT_IDLE_SECONDS))
    ap.add_argument("--harness", default=env_default("HARNESS") or env_default("POOLRAD_HARNESS"))
    ap.add_argument("--model", default=env_default("MODEL") or env_default("POOLRAD_MODEL"))
    ap.add_argument("--session", default=env_default("SESSION") or env_default("POOLRAD_SESSION_ID"))
    ap.add_argument("--variant", default=env_default("VARIANT") or env_default("POOLRAD_VARIANT"))
    ap.add_argument("--frontier", nargs="?", const="", metavar="UNIT", help="print the frontier and exit")
    ap.add_argument("--release", nargs="+", metavar=("UNIT", "ROUTINE"), help="clear frontier entries and exit")
    a = ap.parse_args(argv)
    try:
        if a.release:
            unit, routine = a.release[0].lower(), (a.release[1] if len(a.release) > 1 else None)
            n = release_frontier(unit, routine)
            print("frontier: released %d entr%s of %s%s" % (n, "y" if n == 1 else "ies", unit,
                                                           " (%s)" % routine if routine else ""))
            return 0
        if a.frontier is not None:
            rows = frontier_listing(a.frontier.lower() or None)
            print("\n".join(rows) if rows else "frontier: empty (%s)" % frontier_dir())
            return 0
        if not a.agent:
            print("worker: need AGENT=<name> and ROLE=decompiler|reviewer", file=sys.stderr)
            return 2
        cfg = Config(agent=a.agent, role=a.role, unit=a.unit.lower(), batch=a.batch, session_cmd=a.session_cmd,
                     session_model=a.session_model, max_sessions=a.max_sessions, timeout_minutes=a.timeout,
                     max_attempts=a.max_attempts, idle_seconds=a.idle, harness=a.harness, model=a.model,
                     session=a.session, variant=a.variant)
        worker = Worker(cfg)
    except (ValueError, RuntimeError, OSError) as e:
        print("worker: %s" % e, file=sys.stderr)
        return 2
    install_signals(worker)
    return worker.run()


if __name__ == "__main__":
    sys.exit(main())

"""The human's inbox (tools/agent/inbox.py) over a temporary coordination directory."""
import datetime as dt
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))
import check  # noqa: E402
import common  # noqa: E402
import inbox  # noqa: E402
import next as nxt  # noqa: E402


def iso(minutes_ago: float) -> str:
    return (dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=minutes_ago)).isoformat(timespec="seconds")


@pytest.fixture
def coordination(tmp_path, monkeypatch):
    d = tmp_path / "git-common"
    for sub in ("poolrad-handoffs", "poolrad-locks", "poolrad-heartbeats", "poolrad-frontier", "poolrad-checks"):
        (d / sub).mkdir(parents=True)
    monkeypatch.setattr(common, "common_dir", lambda: d)
    monkeypatch.setattr(check, "fingerprint", lambda: "f" * 64)
    monkeypatch.setattr(check, "receipts", lambda: d / "poolrad-checks")
    monkeypatch.setattr(nxt, "next_unit", lambda: ("ovl12", "biggest unit", 3, 168))
    monkeypatch.setattr(nxt, "next_review", lambda: None)
    monkeypatch.setattr(inbox, "commits_beyond_main", lambda branch: 0)
    h = d / "poolrad-handoffs"
    (h / "escalate-res06-20261012110841.md").write_text(
        "unit = res06\nagent = dec-1\nbranch = unit/res06\nstate = escalate\ntime = %s\nnote = %s\n" % (
            iso(90), "matcher gap: nested routine " + "x" * 500))
    (h / "ovl20.md").write_text(
        "unit = ovl20\nagent = haiku-dec\nbranch = unit/ovl20\ncommit = 47ae3511d812\nstate = partial\n"
        "time = %s\nnote = 6 of 21 routines at L2\nintegrate = rejected\nintegrate_reason = make check red: "
        "readability ovl20\nintegrate_log = /tmp/integrate/ovl20.log\nintegrate_time = %s\n" % (iso(60), iso(30)))
    (h / "res07.md").write_text(
        "unit = res07\nagent = deepseek-dec\nbranch = unit/res07\ncommit = 16e6fb827a60\nstate = partial\n"
        "time = %s\nnote = 14 of 19 routines at L2\n" % iso(45))
    (h / "review-ovl11.md").write_text(
        "unit = ovl11\nagent = rev-4\nbranch = review/ovl11\ncommit = 3305398\nstate = review-passed\n"
        "time = %s\nnote = re-review passes\n" % iso(10))
    locks = d / "poolrad-locks"
    (locks / "ovl09.lock").write_text("unit = ovl09\nagent = dec-3\nhost = h\nbranch = unit/ovl09\nstarted = %s\n" % iso(120))
    (locks / "ovl17.lock").write_text("unit = ovl17\nagent = dec-5\nhost = h\nbranch = unit/ovl17\nstarted = %s\n" % iso(5))
    (locks / "ovl30.lock").write_text("unit = ovl30\nagent = dec-6\nhost = h\nbranch = unit/ovl30\nstarted = %s\n" % iso(26 * 60))
    beats = d / "poolrad-heartbeats"
    (beats / "dec-3.txt").write_text("agent = dec-3\ntime = %s\nbranch = unit/ovl09\nstate = stopped\nnote = session budget reached\n" % iso(100))
    (beats / "dec-5.txt").write_text("agent = dec-5\ntime = %s\nbranch = unit/ovl17\nstate = working\nnote = matching\n" % iso(3))
    (beats / "dec-6.txt").write_text("agent = dec-6\ntime = %s\nbranch = unit/ovl30\nstate = working\nnote = matching\n" % iso(2))
    (d / "poolrad-frontier/ovl12.json").write_text(json.dumps({
        "ovl12:0675": {"attempts": 2, "last": iso(20), "agent": "dec-1", "batch_log": "/b/ovl12-batch3.log"},
        "ovl12:0700": {"attempts": 1, "last": iso(20), "agent": "dec-1", "batch_log": "/b/ovl12-batch3.log"}}))
    return d


def by_section(rows):
    out = {}
    for r in rows:
        out.setdefault(r["section"], []).append(r)
    return out


def test_inbox_lists_every_pending_decision_with_its_command(coordination, capsys):
    rows = inbox.items()
    s = by_section(rows)
    esc = s["Escalations"]
    assert len(esc) == 1 and "res06" in esc[0]["what"] and len(esc[0]["what"]) < 500       # note cut to 400
    assert esc[0]["command"] == 'make handoff-done AGENT=orch UNIT=escalate-res06-20261012110841 DECISION="<decision>"'
    rej = s["Rejected"]
    assert len(rej) == 1 and "readability ovl20" in rej[0]["what"]
    assert rej[0]["command"].startswith("make claim AGENT=haiku-dec UNIT=ovl20") and "/tmp/integrate/ovl20.log" in rej[0]["command"]
    merge = s["To merge"]
    assert [m["what"].split(" ")[0] for m in merge] == ["unit/res07", "review/ovl11"]        # newest last
    assert all(m["command"] == "make integrate" for m in merge)
    locks = s["Locks"]
    assert sorted(l["what"].split()[1] for l in locks) == ["ovl09", "ovl30"]                    # ovl17 is alive
    stopped = [l for l in locks if "ovl09" in l["what"]][0]
    assert "said it stopped" in stopped["what"]
    assert stopped["command"] == 'make unlock UNIT=ovl09 OPERATOR=1 FORCE=1 REASON="holder dec-3 confirmed gone"'
    old = [l for l in locks if "ovl30" in l["what"]][0]
    assert "no commits beyond main" in old["what"]
    fr = s["Frontier"]
    assert len(fr) == 1 and "ovl12:0675 (2)" in fr[0]["what"] and "ovl12:0700" not in fr[0]["what"]
    assert "worker.py --release ovl12" in fr[0]["command"]
    assert s["Main"][0]["command"] == "make check"
    assert [q["what"] for q in s["Queues"]] == ["next unit: ovl12 (biggest unit; 3 of 168 routines at L2)", "next review: none waiting"]
    assert s["Queues"][0]["command"] == "make worker AGENT=<name> ROLE=decompiler" and s["Queues"][1]["command"] == ""
    assert [r["section"] for r in rows] == sorted((r["section"] for r in rows), key=inbox.SECTIONS.index)
    assert inbox.main([]) == 0
    out = capsys.readouterr().out
    assert out.count("what:      ") == len(rows) and out.count("command:   ") == len(rows)
    assert "== Escalations ==" in out and "inbox: %d item(s) waiting" % (len(rows) - 2) in out
    assert inbox.main(["--json"]) == 0
    assert json.loads(capsys.readouterr().out) == rows


def test_inbox_is_quiet_when_main_is_checked_and_nothing_waits(coordination, monkeypatch, capsys):
    for p in list((coordination / "poolrad-handoffs").iterdir()) + list((coordination / "poolrad-locks").iterdir()) \
            + list((coordination / "poolrad-frontier").iterdir()):
        p.unlink()
    (coordination / "poolrad-checks" / ("f" * 64 + ".json")).write_text("{}")
    monkeypatch.setattr(nxt, "next_unit", lambda: None)
    rows = inbox.items()
    assert {r["section"] for r in rows} == {"Queues"}
    assert inbox.main([]) == 0 and "inbox: 0 item(s) waiting" in capsys.readouterr().out

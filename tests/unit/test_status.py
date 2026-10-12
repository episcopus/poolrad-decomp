import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))

import status  # noqa: E402


def test_status_copies_the_blockers_file_into_its_blockers_section(tmp_path):
    blockers = tmp_path / "blockers.md"
    blockers.write_text("# Blockers\n\n<!-- how to use this file -->\n\n"
                        "- ovlXX merge aborted: conflict over DS:1234, test entry.\n")
    out = tmp_path / "status.md"
    assert status.main(["status.py", "-o", str(out), "--blockers", str(blockers)]) == 0
    text = out.read_text()
    section = text.split("## Blockers and decisions waiting for the human", 1)[1].split("## Toolchain", 1)[0]
    assert "- ovlXX merge aborted: conflict over DS:1234, test entry." in section
    assert "how to use this file" not in text and "# Blockers" not in section
    assert "- Approach (decided 2026-10-11, SPEC 4)" in section    # the fixed decisions stay


def test_status_without_a_blockers_file_still_has_the_fixed_decisions(tmp_path):
    out = tmp_path / "status.md"
    assert status.main(["status.py", "-o", str(out), "--blockers", str(tmp_path / "missing.md")]) == 0
    assert "- Approach (decided 2026-10-11, SPEC 4)" in out.read_text()

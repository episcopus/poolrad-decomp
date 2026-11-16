"""ide_card.py pull (ports/coco3/tools/ide_card.py): a saved game of the SuperIDE card's save area is copied, byte for byte, into a PC SAVE folder;
a different slot already there is refused unless --replace-slot, which moves all of its files to the backup folder first."""
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("coco3_ide_card", ROOT / "ports/coco3/tools/ide_card.py")
ic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ic)

SEC, DRIVE = ic.SEC, ic.DRIVE_SECS
SAVE_LSN = 200
SLOT_F = [("SAVGAMF.DAT", bytes(range(256)) * 51 + b"\x01"), ("CHRDATF1.SAV", b"\x11" * 285), ("CHRDATF1.ITM", b"\x22" * 441), ("CHRDATF1.SPC", b"\x33" * 45)]
SLOT_A = [("SAVGAMA.DAT", b"\xaa" * 13137), ("CHRDATA1.SAV", b"\xab" * 285)]


def image_header():
    return b"PIM2" + bytes(12) + SAVE_LSN.to_bytes(4, "big") + (512).to_bytes(2, "big")


def fill(area):
    for name, data in SLOT_A + SLOT_F:
        area.add(name, data)


def card_file(tmp_path):
    """a card file like build/ide/POOLIDE.IMG: the boot drive, then the image (header "PIM2", the save area from image sector SAVE_LSN)"""
    b = bytearray(2 * DRIVE * SEC)
    b[DRIVE * SEC:DRIVE * SEC + 22] = image_header()
    area = ic.SaveArea(b, ic.saves_at(DRIVE, SAVE_LSN))
    fill(area)
    p = tmp_path / "POOLIDE.IMG"
    p.write_bytes(bytes(area.b))
    return p


def pull(tmp_path, monkeypatch, device, *extra):
    monkeypatch.chdir(tmp_path)                       # no build/ide/ide.env here: the options are the ones given
    return ic.main(["pull", str(device), *extra, "--backup", str(tmp_path / "backup")])


def folder(p):
    return sorted((f.name, f.read_bytes()) for f in p.iterdir())


def test_pull_into_an_empty_folder_and_again(tmp_path, monkeypatch, capsys):
    dev, dest = card_file(tmp_path), tmp_path / "SAVE"
    dest.mkdir()
    assert pull(tmp_path, monkeypatch, dev, "f", "--to", str(dest)) == 0
    assert folder(dest) == sorted(SLOT_F)
    assert pull(tmp_path, monkeypatch, dev, "F", "--to", str(dest)) == 0
    assert "already has the same 4 files" in capsys.readouterr().out
    assert not (tmp_path / "backup").exists()


def test_a_different_slot_is_kept_unless_replace(tmp_path, monkeypatch):
    dev, dest = card_file(tmp_path), tmp_path / "SAVE"
    dest.mkdir()
    old = {"SAVGAMF.DAT": b"old game", "CHRDATF1.SAV": b"old one", "CHRDATF8.SAV": b"a character no longer in the party", "SAVGAMA.DAT": b"slot A, not touched"}
    for n, d in old.items():
        (dest / n).write_bytes(d)
    with pytest.raises(SystemExit, match="--replace-slot"):
        pull(tmp_path, monkeypatch, dev, "F", "--to", str(dest))
    assert folder(dest) == sorted(old.items())
    assert pull(tmp_path, monkeypatch, dev, "F", "--to", str(dest), "--replace-slot") == 0
    assert folder(dest) == sorted(SLOT_F + [("SAVGAMA.DAT", old["SAVGAMA.DAT"])])
    (bdir,) = (tmp_path / "backup").iterdir()
    assert bdir.name.startswith("F-")
    assert folder(bdir) == sorted((n, d) for n, d in old.items() if n != "SAVGAMA.DAT")


def test_a_slot_the_card_has_not(tmp_path, monkeypatch):
    dev, dest = card_file(tmp_path), tmp_path / "SAVE"
    dest.mkdir()
    with pytest.raises(SystemExit, match=r"no saved game C \(it has: A F\)"):
        pull(tmp_path, monkeypatch, dev, "C", "--to", str(dest))
    assert folder(dest) == []


def test_pull_from_the_game_on_a_card(tmp_path, monkeypatch):
    """a card (here a small file, HDB-DOS offset 10, the game at drive 2): the boot drive lists POOL/BIN, the next drive starts with the image"""
    off, drive = 10, 2
    lba0 = off + drive * DRIVE
    b = bytearray((lba0 + DRIVE + ic.saves_at(0, SAVE_LSN) + 512 + 8) * SEC)
    dir_sec = (lba0 + 17 * 18 + 2) * SEC
    b[dir_sec:dir_sec + 11] = b"POOL    BIN"
    b[(lba0 + DRIVE) * SEC:(lba0 + DRIVE) * SEC + 22] = image_header()
    area = ic.SaveArea(b, ic.saves_at(lba0 + DRIVE, SAVE_LSN))
    fill(area)
    dev, dest = tmp_path / "card.raw", tmp_path / "SAVE"
    dev.write_bytes(bytes(area.b))
    dest.mkdir()
    assert pull(tmp_path, monkeypatch, dev, "F", "--to", str(dest), "--hdb-offset", str(off), "--drive", str(drive)) == 0
    assert folder(dest) == sorted(SLOT_F)
    with pytest.raises(SystemExit, match="no build of the game at drive 3"):
        pull(tmp_path, monkeypatch, dev, "F", "--to", str(dest), "--hdb-offset", str(off), "--drive", "3")

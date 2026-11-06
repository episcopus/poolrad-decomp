"""EGA picture blocks: every pinned picture-like .DAX (playbook 20, whitepaper 4.2.3)."""
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import dax  # noqa: E402
import pic  # noqa: E402

POOL = ROOT / "poolrad"


def _all_pic_blocks():
    for path in pic.iter_pic_files(str(POOL)):
        for b in dax.read_dax(path):
            yield path, b


def test_all_picture_blocks_decode():
    n = 0
    for path, b in _all_pic_blocks():
        n += 1
        dec = pic.decode_block(dax.unrle(b["data"]), path, b["id"])
        assert dec["kind"] in ("picture", "animation", "font")
        if dec["kind"] == "font":
            assert dec["font"]["glyphs"] == pic.FONT_GLYPHS
        else:
            assert dec["frames"]
            for fr in dec["frames"]:
                assert fr["width_px"] == fr["width_cols"] * 8
                assert len(fr["pixels"]) == pic.picture_bytes(fr["height"], fr["width_cols"], fr["items"])
    assert n >= 700  # TITLE+PIC+CPIC+SPRIT+HEAD+BODY+CHEAD+CBODY+COMSPR+ICON+8X8D+FINAL


def test_pic_cli_verify_ok():
    assert pic.main(["pic", "verify", str(POOL)]) == 0


def test_title_is_320x200():
    raw = dax.unrle(dax.read_dax(str(POOL / "TITLE.DAX"))[0]["data"])
    dec = pic.decode_block(raw, "TITLE.DAX", 1)
    assert dec["kind"] == "picture"
    fr = dec["frames"][0]
    assert fr["width_px"] == 320 and fr["height"] == 200 and fr["items"] == 1


def test_cpic_is_24x24():
    raw = dax.unrle(dax.read_dax(str(POOL / "CPIC1.DAX"))[0]["data"])
    dec = pic.decode_block(raw, "CPIC1.DAX", None)
    fr = dec["frames"][0]
    assert fr["width_px"] == 24 and fr["height"] == 24


def test_pic_animation_xor_roundtrip_dims():
    raw = dax.unrle(next(b for b in dax.read_dax(str(POOL / "PIC1.DAX")) if b["id"] == 1)["data"])
    dec = pic.decode_block(raw, "PIC1.DAX", 1)
    assert dec["kind"] == "animation" and dec["xor_delta"]
    frames = pic.frames_for_png(dec)
    assert len(frames) == raw[0]
    for fr in frames:
        rows = pic.decode_pixels(fr, 0)
        assert len(rows) == fr["height"]
        assert all(len(r) == fr["width_px"] for r in rows)


def test_png_dump_title(tmp_path):
    pytest.importorskip("PIL")
    out = tmp_path / "title.png"
    assert pic.main(["pic", "dump", str(POOL / "TITLE.DAX"), "1", str(out)]) == 0
    assert out.stat().st_size > 100
    from PIL import Image
    im = Image.open(out)
    assert im.size == (320, 200)


def test_png_dump_title_colours(tmp_path):
    """EGA paints the raw nibbles (the title uses ten colours); --cga goes through the
    record's 16-to-4 colour map (whitepaper 4.2.3), so at most four colours."""
    pytest.importorskip("PIL")
    from PIL import Image
    ega, cga = tmp_path / "ega.png", tmp_path / "cga.png"
    assert pic.main(["pic", "dump", str(POOL / "TITLE.DAX"), "1", str(ega)]) == 0
    assert pic.main(["pic", "dump", "--cga", str(POOL / "TITLE.DAX"), "1", str(cga)]) == 0
    ega_colours = {c for _, c in Image.open(ega).getcolors(256)}
    cga_colours = {c for _, c in Image.open(cga).getcolors(256)}
    assert len(ega_colours) == 10
    assert ega_colours <= set(pic.EGA)
    assert 1 < len(cga_colours) <= 4
    assert cga_colours <= set(pic.CGA)


def test_font_block_201():
    raw = dax.unrle(next(b for b in dax.read_dax(str(POOL / "8X8D1.DAX")) if b["id"] == 201)["data"])
    dec = pic.decode_block(raw, "8X8D1.DAX", 201)
    assert dec["kind"] == "font"

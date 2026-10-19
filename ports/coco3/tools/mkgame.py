#!/usr/bin/env python3
"""mkgame.py: build the game of the CoCo port from the laid-out C of mkvm.py (step 8.5c). Runs in the toolchain.

  mkgame.py GEN_DIR OUT_DIR      GEN_DIR from scripts/vm_host.sh (build/gen-vm), OUT_DIR for objects, stubs and images

What it does:
  1. compiles every unit of the game with CMOC (-fomit-frame-pointer);
  2. a unit whose code and constants do not fit a 16 KB bank is split at routine borders and its parts compiled again
     (the routines of the generated C are top level and not static, nested helpers stay with the routine that uses them);
  3. assigns the units to banks and the small resident ones to the core;
  4. writes the far stubs (the resident entry for every routine of a bank that another bank or the core calls), the entry
     table at the head of every bank, and the bank table.
The core and the banks are linked by the Makefile rules that follow (build/game/Makefile.inc), because they need the core's map."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

BANK_BYTES = 0x4000                      # slots 4 and 5
BANK_LIMIT = BANK_BYTES - 0x180          # room for the entry table (3 bytes an entry) and a margin
CORE_UNITS = ["pool", "res02", "res04", "res10", "res11"]   # resident
SKIP_UNITS = {"image", "poolvars", "vmlayout"}
RTL_BANK = ("rtl_heap", "rtl_file", "rtl_strx")                     # the runtime that has no variables lives in a bank of its own (the core is small)
# Replaced by the engine (step 8.5d): whole units, and routines of units that stay. The engine provides them under the same
# names; until a routine is written a stub stops the program and says which one was asked for.
ENGINE_UNITS = ["res07", "res08"]
CORE_ROUTINES = {"res06": ["GameClock"], "ovl34": ["Put8x8Symbol"],
                 "res05": ["LoadDaxBlock", "OpenDaxFile", "CloseDaxFile", "UnpackRle"]}   # cut out of the unit, written in src/game (the core, engapi.c)
ENGINE_ROUTINES = {
    "res06": ["SetEgaFillRegisters", "SetActivePage", "SetPageSegment", "FillPlaneRect", "LoadGameFont", "DrawGlyph"],   # GameClock: rtl_sys.c
    "ovl17": ["MergePictureData"],
}
ENGINE_EXTRA = ["ShowPictureItem", "DaxLoad", "DaxRead", "FileKnown", "DrawIconPic", "PictureCopy", "SaveRead", "SaveWrite", "SetPictureXY", "PictureBytes", "PicData", "DrawSpritePic", "PictureAppend", "PictureItemCopy"]                       # engine routines the original does not have (called by src/game/engapi.c)
WRAPPED = {"LoadPicture", "AllocatePicture", "ReleasePicture", "RemapPictureColors"}   # engine routines with a wrapper in src/game/engapi.c: the stub is _eng_<Name>
# Game routines that reach into a picture record (the PC's layout: Tail, Pixels, ByteSize) cannot: a picture is a handle and the
# pixels are the engine's. These are rewritten after the translation to say the same thing through the engine (step 8.5; the
# whitepaper's 4.2.3 and the routines' own comments name what each does). "fn" replaces a whole function, "between" the lines from
# one marker through another (inclusive) in one function.
PATCH_DECLS = ("void DrawIconPic(u16 h, s16 col, s16 row, u8 mirror);\nvoid PictureCopy(u16 src, u16 dst);\nvoid SetPictureXY(u16 h, u16 x, u16 y);\n"
               "u16 PictureBytes(u16 h);\nvoid PicData(u16 h, u16 rel, const u8 *buf, u8 n, u8 key);\nvoid DrawSpritePic(u16 h);\nvoid PictureAppend(u16 src, u16 dst, u8 index);\nvoid PictureItemCopy(u16 src, u16 dst, u8 item, u8 mirror);\nu16 DaxLoad(const u8 *name, u16 id);\nvoid DaxRead(u16 off, u8 *dst, u16 n);\n")
PATCHES = {
    # ovl28 LoadSpriteList and Show3DSprite: the picture record's X and Y, ByteSize and pixels are the engine's (handles), and the PIC
    # block of the camp (7,787 bytes) does not fit a page of the banked heap: LoadSpriteList reads the block from the engine's stage
    # (DaxLoad, DaxRead) as it goes instead of copying it first; the sprite list is worked on as a local copy.
    "ovl28": [
        ("fn", "LoadSpriteList", """void LoadSpriteList(const u8 *Name_in, u8 Bank, u8 Mode, PSpriteList List)
{
  POOL_TRACE("LoadSpriteList");
  const u8 *Name = Name_in;
  TSpriteList L;
  u16 Size = 0, Offset, Height, WidthCols, Row, k, c, q, h;
  u8 I, Loaded = 0, Count, IsPicOrFinal, PrevAllocated = 0, Digit[2], tmp[128], tmp2[128], ts1[10];
  farptr Prev = 0;
  memset((struct PA_u8_2 *)Digit, 0, sizeof(Digit));
  if (((rtl_str_cmp(Name, LastSpriteFile) == 0)) && ((Bank == LastSpriteBank))) {
    return;
  }
  FreeSpriteList(rtl_far(&(*FPD(TSpriteList *, List))));
  rtl_str_assign(LastSpriteFile, 8, Name);
  LastSpriteBank = Bank;
  IsPicOrFinal = (((rtl_str_cmp(Name, S("\003PIC")) == 0)) || ((rtl_str_cmp(Name, S("\005FINAL")) == 0)));
  rtl_str_int(Digit, 1, TileSet, 0);
  Size = DaxLoad(rtl_str_cat_v(ts1, 2, Name, Digit), Bank);
  if (Size == 0) {
    return;
  }
  L = (*FPD(TSpriteList *, List));
  DaxRead(0, tmp, 1);
  Count = tmp[0];
  if ((rtl_str_cmp(Name, S("\003PIC")) == 0) && Bank == 1 && Count > PicBlock1Sprites)
    Count = PicBlock1Sprites;
  Offset = 1;
  L.Flag = 1;
  for (I = 1; I <= Count; I++) {
    DaxRead(Offset, L.Slots[I - 1].Data, 4);
    DaxRead((u16)(Offset + 4), tmp, 4);
    Height = (u16)((u16)tmp[0] | ((u16)tmp[1] << 8));
    WidthCols = (u16)((u16)tmp[2] | ((u16)tmp[3] << 8));
    Offset = (u16)(Offset + 8);
    if ((s32)rtl_MaxAvail() >= FreeMemoryFloor) {
      Loaded++;
      AllocatePicture(Height, WidthCols, 1, Mode, (void *)&L.Slots[I - 1].Sprite);
      h = (u16)L.Slots[I - 1].Sprite;
      DaxRead(Offset, tmp, 4);
      SetPictureXY(h, (u16)((u16)tmp[0] | ((u16)tmp[1] << 8)), (u16)((u16)tmp[2] | ((u16)tmp[3] << 8)));
      Offset = (u16)(Offset + 13);                       /* X, Y, a skipped byte, the 8 palette bytes (not used here) */
      Row = (u16)(PictureBytes(h) - 1);
      if (IsPicOrFinal && I == 1) {                      /* PIC and FINAL are stored as differences from the first picture */
        Prev = rtl_getmem((u16)(Row + 1));
        for (k = 0; k <= Row; k = (u16)(k + c)) {
          c = (u16)(Row + 1 - k) < 128 ? (u16)(Row + 1 - k) : 128;
          DaxRead((u16)(Offset + k), tmp, c);
          rtl_Move(tmp, (void *)&FPD(struct PA_u8_1 *, Prev)->a[k], c);
        }
        PrevAllocated = 1;
      }
      for (k = 0; k <= Row; k = (u16)(k + c)) {
        c = (u16)(Row + 1 - k) < 128 ? (u16)(Row + 1 - k) : 128;
        DaxRead((u16)(Offset + k), tmp, c);
        if (IsPicOrFinal && I != 1) {
          rtl_Move((void *)&FPD(struct PA_u8_1 *, Prev)->a[k], tmp2, c);
          for (q = 0; q < c; q++)
            tmp[q] ^= tmp2[q];
        }
        PicData(h, k, tmp, (u8)c, 0);
      }
      if (((Mode & 1) > 0) && ((s16)VideoAdapter != AdapterCga)) {
        RemapPictureColors(rtl_far(&SpriteRemapFrom), rtl_far(&SpriteRemapTo), 0, 0, L.Slots[I - 1].Sprite);
      }
      Offset = (u16)(Offset + Row + 1);
    }
  }
  L.Count = Loaded;
  (*FPD(TSpriteList *, List)) = L;
  if (IsPicOrFinal && PrevAllocated)
    rtl_freemem(Prev, (u16)(Row + 1));
  FlushKeyboard();
}"""),
        ("between", "Show3DSprite", "    {\n      TSpritePicture *w1", "    }\n  } else {\n",
         "    DrawSpritePic((u16)List.Slots[Slot - 1].Sprite);\n  } else {\n"),
    ],
    # res12 CopyPictureItem (the combat icons: an item of a slot picture, mirrored or not, into the combat picture) and ovl13
    # ShowAttackAnimation (a byte size it works out and never reads): the picture records are the engine's
    "res12": [("fn", "CopyPictureItem", """void CopyPictureItem(u8 PicIndex, u8 Half, u8 ItemIndex, u8 Mirror)
{
  POOL_TRACE("CopyPictureItem");
  PictureItemCopy((u16)PictureSlots[PicIndex].u.a1.Pics[Half], (u16)CombatAnimationPicture, ItemIndex, Mirror);
}""")],
    "ovl13": [("between", "ShowAttackAnimation", "  PixelBytes = (*FPB(TPictureHeader *, CombatAnimationPicture)).ByteSize;\n",
               "    PixelBytes = ((u16)PixelBytes / 4);\n  }\n", "")],
    # ovl17 LoadMonster: the monster record comes out of a DAX block as bytes (a Pointer argument, so the translation does not know its type): the words
    # in it turn from the file's order into the CoCo's, as BlockRead does for the records of a character file. The affect and item records are Move
    # destinations of a known type: the translator turns them round itself (p2c_expr move_swaps, step 8.7b); the patches that did it by hand swapped twice.
    "ovl17": [("all", "  rtl_Move((void *)&(*FPD(u8 *, Block)), (void *)&(*FPD(u8 *, Who)), 285);\n",
               "  rtl_Move((void *)&(*FPD(u8 *, Block)), (void *)&(*FPD(u8 *, Who)), 285);\n  rtl_swapdesc((void *)&(*FPM(TCharacter *, Who)), swd_ovl17_0);\n")],
    "ovl32": [("between", "Load24x24Set", "  CopyBytes = (u16)(*FPB(TMemPic *, Loaded))", "Tail[DestOfs], CopyBytes);\n  }\n",
               "  if (SqrPaciBank1 != 0) {\n    PictureAppend((u16)Loaded, (u16)SqrPaciBank1, Index);\n  }\n"),
              ("fn", "DrawIcon", """void DrawIcon(s8 CellCol, s8 CellRow, u8 IconSet, u8 Mirror, u8 PicIndex)
{
  /* ovl32:04FC: the original copies the picture (mirrored above icon set 3) into a new one, blits it and frees it */
  farptr Pic = PictureSlots[PicIndex].u.a1.Pics[Mirror];
  if (Pic != 0)
    DrawIconPic((u16)Pic, (s16)((s16)CellCol * CellStep), (s16)((s16)CellRow * CellStep), (u8)((s16)IconSet > IconSetCopyLimit));
}""")],
    "ovl16": [("between", "EditCharacterIcon_CopyPictureSlot", "  PixelBytes = (*FPB(TMemPic_OVL16 *, PictureSlots[Dest]",
               "(*FPB(TMemPic_OVL16 *, PictureSlots[Dest].u.a0.SecondPic)).Pixels)), PixelBytes);\n",
               """  PictureCopy((u16)PictureSlots[Source].u.a0.FirstPic, (u16)PictureSlots[Dest].u.a0.FirstPic);
  PictureCopy((u16)PictureSlots[Source].u.a0.SecondPic, (u16)PictureSlots[Dest].u.a0.SecondPic);
""")],
}


def patch_unit(u, text):
    if u not in PATCHES:
        return text
    text = text.replace('#include "game.h"\n', '#include "game.h"\n' + PATCH_DECLS, 1)
    for p in PATCHES[u]:
        if p[0] == "before":
            items = parse_items(text)
            hit = [i for i, it in enumerate(items) if it[0] == "fn" and it[1] == p[1]]
            if len(hit) != 1:
                raise SystemExit("patch %s: %s not found once" % (u, p[1]))
            items.insert(hit[0], ("other", p[2]))
            text = "\n".join(it[1] if it[0] == "other" else it[3] for it in items) + "\n"
        elif p[0] == "all":                                  # every occurrence of a text in the unit
            old, new = p[1], p[2]
            if old not in text and "FPM(TMenuLine" in old:   # placement.toml may put the type in the banked class (FPB)
                old, new = old.replace("FPM(TMenuLine", "FPB(TMenuLine"), new.replace("FPM(TMenuLine", "FPB(TMenuLine")
            if old not in text:
                raise SystemExit("patch %s: %r not found" % (u, p[1]))
            text = text.replace(old, new)
        elif p[0] == "fn":
            items = parse_items(text)
            hit = [i for i, it in enumerate(items) if it[0] == "fn" and it[1] == p[1]]
            if len(hit) != 1:
                raise SystemExit("patch %s: %s not found once" % (u, p[1]))
            items[hit[0]] = ("other", p[2])
            text = "\n".join(it[1] if it[0] == "other" else it[3] for it in items) + "\n"
        else:
            items = parse_items(text)
            hit = [i for i, it in enumerate(items) if it[0] == "fn" and it[1] == p[1]]
            if len(hit) != 1:
                raise SystemExit("patch %s: %s not found once" % (u, p[1]))
            body = items[hit[0]][3]
            a = body.find(p[2])
            b = body.find(p[3], a)
            if a < 0 or b < 0:
                raise SystemExit("patch %s: markers not found in %s" % (u, p[1]))
            body = body[:a] + p[4] + body[b + len(p[3]):]
            items[hit[0]] = ("fn", p[1], items[hit[0]][2], body)
            text = "\n".join(it[1] if it[0] == "other" else it[3] for it in items) + "\n"
    return text


DEBUG_PATCH = json.loads(Path("build/run/debug_patch.json").read_text()) if Path("build/run/debug_patch.json").exists() else {}   # {unit: [[old, new], ...]}: a temporary probe (delete the file when done)
if DEBUG_PATCH:
    print("mkgame: DEBUG PATCH applied to", ", ".join(DEBUG_PATCH))
CMOC = ["cmoc", "-c", "--void-target", "--no-relocate", "-O2", "-fomit-frame-pointer", "-w"]


def stub_sym(name):
    return ("_eng_" if name in WRAPPED else "_") + name


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def compile_c(src, obj, incs):
    p = run(CMOC + ["-I" + i for i in incs] + ["-o", obj, src])
    if p.returncode != 0 or not os.path.exists(obj):
        errs = [l for l in (p.stdout + p.stderr).splitlines() if "error" in l.lower()] or (p.stdout + p.stderr).splitlines()[-3:]
        raise SystemExit("cmoc failed on %s: %s" % (src, "; ".join(errs[:3])))


def objinfo(obj):
    """-> dict(code=, rodata=, exports=set, imports=set, funcs={name: size}, order=[name])"""
    out = run(["lwobjdump", obj]).stdout
    sec, mode = None, None
    code = rodata = 0
    exports, imports, funcs, order = set(), set(), {}, []
    for line in out.splitlines():
        m = re.match(r"SECTION (\S+)", line)
        if m:
            sec, mode = m.group(1), None
            continue
        s = line.strip()
        if s == "Exported symbols":
            mode = "e"
            continue
        if s == "Local symbols:":
            mode = "l"
            continue
        if s == "Incomplete references":
            mode = "i"
            continue
        m = re.match(r"CODE ([0-9A-Fa-f]+) bytes", s)
        if m:
            n = int(m.group(1), 16)
            if sec == "code":
                code += n
            elif sec == "rodata":
                rodata += n
            elif sec in ("rwdata", "bss", "initgl") and n:
                raise SystemExit("%s has %d bytes in section %s: banks hold code and constants only" % (obj, n, sec))
            continue
        if mode == "e":
            m = re.match(r"(\S+)=", s)
            if m:
                exports.add(m.group(1))
        elif mode == "i":
            for m in re.finditer(r"ES=([^\s)]+)", s):
                imports.add(m.group(1))
        elif mode == "l" and sec == "code":
            m = re.match(r"funcsize_(\S+)=([0-9A-Fa-f]+)", s)
            if m:
                funcs[m.group(1)] = int(m.group(2), 16)
    return {"code": code, "rodata": rodata, "exports": exports, "imports": imports - exports, "funcs": funcs}


# ---------------------------------------------------------------------------- splitting
def parse_items(text):
    """The top level items of a generated unit: ('pre', text) for everything before the first routine, then
    ('fn', name, static, text), ('other', text) for frame structs and the like. Comments stay with what follows."""
    lines = text.split("\n")
    items, cur, i = [], [], 0
    pending = []                                            # comment or blank lines waiting for an item
    n = len(lines)
    while i < n:
        ln = lines[i]
        if ln.startswith("/*") and "*/" not in ln:         # a block comment
            j = i
            while "*/" not in lines[j]:
                j += 1
            pending += lines[i:j + 1]
            i = j + 1
            continue
        if ln.startswith("/*") or ln.strip() == "":
            pending.append(ln)
            i += 1
            continue
        m = re.match(r"^(static )?[A-Za-z_][\w ]*?[ *](\w+)\([^;{]*\)\s*$", ln)
        if m and i + 1 < n and lines[i + 1] == "{":
            j = i + 1
            while lines[j] != "}":
                j += 1
            items.append(("fn", m.group(2), bool(m.group(1)), "\n".join(pending + lines[i:j + 1])))
            pending = []
            i = j + 1
            continue
        # anything else at column 0: a directive, a typedef, a struct up to its closing line, a declaration
        j = i
        if re.match(r"^(struct|union|typedef struct|typedef union|enum)\b.*\{\s*$", ln) or ln.rstrip().endswith("{"):
            while not re.match(r"^\}.*;\s*$", lines[j]):
                j += 1
        items.append(("other", "\n".join(pending + lines[i:j + 1])))
        pending = []
        i = j + 1
    if pending:
        items.append(("other", "\n".join(pending)))
    return items


def routine_names(text):
    return [it[1] for it in parse_items(text) if it[0] == "fn" and not it[2]]


def strip_routines(text, names):
    """The unit text without the named routines (and the static helpers that precede them)."""
    items = parse_items(text)
    keep, pend = [], []
    for it in items:
        if it[0] == "fn":
            pend.append(it)
            if not it[2]:
                if it[1] not in names:
                    keep.extend(pend)
                pend = []
        else:
            keep.append(it)
    keep.extend(pend)
    return "\n".join(it[1] if it[0] == "other" else it[3] for it in keep) + "\n"


def c_string_len(body):
    """bytes a C string literal body (between the quotes, escapes unprocessed) stands for"""
    i = n = 0
    while i < len(body):
        if body[i] == "\\":
            i += 1
            if body[i] in "01234567":
                j = i
                while j < i + 3 and j < len(body) and body[j] in "01234567":
                    j += 1
                i = j
            elif body[i] == "x":
                j = i + 1
                while j < len(body) and body[j] in "0123456789abcdefABCDEF":
                    j += 1
                i = j
            else:
                i += 1
        else:
            i += 1
        n += 1
    return n


STRDEFS = {}                      # Pascal string constants of game.h written as #define NAME S("...") -> the literal's text


def string_forwarders(items, unit, fn_unit):
    """The routines of `unit` that pass one of their string value parameters (`const u8 *X = X_in;`) on to a routine of another unit (or
    of such a routine): a literal handed to them from this very unit points into this bank's rodata and the other bank would read
    the wrong bytes (the temple's "is not blind." reached ShowCharacterMessage through AskCastAnyway as junk), so the callers copy it too."""
    fns = {it[1]: it[3] for it in items if it[0] == "fn"}
    pars = {n: set(re.findall(r"const u8 \*(\w+) = \1_in;", b)) for n, b in fns.items()}
    fwd = set()
    changed = True
    while changed:
        changed = False
        for n, b in fns.items():
            if n in fwd or not pars[n]:
                continue
            for m in re.finditer(r"\b(\w+)\(([^;]*)\)", b):
                callee = m.group(1)
                if callee in fn_unit and (fn_unit[callee] != unit or callee in fwd) and any(
                        re.search(r"(?:^|[(,]\s*)%s\s*(?:,|\)|$)" % re.escape(p), m.group(2)) for p in pars[n]):
                    fwd.add(n)
                    changed = True
                    break
    return fwd


def copy_cross_literals(text, unit, fn_unit, same_unit=False):
    """A bank sees only its own rodata: a pointer to a string literal that reaches a routine of another bank would read the
    wrong bytes there. Every literal S("...") that is an argument of a call to a routine of another (non-core) unit becomes
    (memcpy(litK, "...", n), litK), a copy in a buffer of the caller's frame (K counts the literals of the statement)."""
    out = []
    items = parse_items(text)
    fwd = string_forwarders(items, unit, fn_unit)          # same-unit routines that hand their string parameter on to another bank
    for kind, *rest in items:
        if kind != "fn":
            out.append(rest[0] if kind == "other" else rest[2])
            continue
        body = rest[2]
        hits, stack, stmt = [], [], 0
        i = body.index("\n{\n") + 1
        L = len(body)
        while i < L:
            c = body[i]
            if body.startswith("/*", i):
                i = body.index("*/", i) + 2
            elif body.startswith("//", i):
                i = body.index("\n", i)
            elif c == '"':                                    # a string literal outside S(...): skip
                j = i + 1
                while body[j] != '"':
                    j += 2 if body[j] == "\\" else 1
                i = j + 1
            elif c == "'":
                j = i + 1
                while body[j] != "'":
                    j += 2 if body[j] == "\\" else 1
                i = j + 1
            elif c in ";{}":
                stmt = 0
                i += 1
            elif c == "(":
                k = i - 1
                while k >= 0 and body[k] == " ":
                    k -= 1
                e = k + 1
                while k >= 0 and (body[k].isalnum() or body[k] == "_"):
                    k -= 1
                name = body[k + 1:e]
                if name == "S" and body.startswith('"', i + 1):
                    j = i + 2
                    while body[j] != '"':
                        j += 2 if body[j] == "\\" else 1
                    callee = stack[-1] if stack else None
                    if body[j + 1] == ")" and callee and callee in fn_unit and (same_unit or fn_unit[callee] != unit or callee in fwd):
                        hits.append((k + 1, j + 2, body[i + 2:j], stmt))
                        stmt += 1
                    i = j + 2
                else:
                    stack.append(name)
                    i += 1
            elif c == ")":
                if stack:
                    stack.pop()
                i += 1
            elif (c.isalpha() or c == "_") and not (body[i - 1].isalnum() or body[i - 1] == "_"):
                j = i
                while j < L and (body[j].isalnum() or body[j] == "_"):
                    j += 1
                tok = body[i:j]
                p, q = i - 1, j
                while body[p] == " ":
                    p -= 1
                while body[q] == " ":
                    q += 1
                callee = stack[-1] if stack else None
                if tok in STRDEFS and body[p] in "(," and body[q] in ",)" and callee and callee in fn_unit and (same_unit or fn_unit[callee] != unit or callee in fwd):
                    hits.append((i, j, STRDEFS[tok], stmt))               # a string constant handed over: copied like a literal
                    stmt += 1
                i = j
            else:
                i += 1
        if not hits:
            out.append(rest[2])
            continue
        size = {}
        for a, b, lit, k in hits:
            size[k] = max(size.get(k, 0), c_string_len(lit) + 1)
        for a, b, lit, k in reversed(hits):
            body = body[:a] + '(memcpy(lit%d, "%s", %d), lit%d)' % (k, lit, c_string_len(lit), k) + body[b:]
        decl = "".join("  u8 lit%d[%d];\n" % (k, size[k]) for k in sorted(size))
        j = body.index("\n{\n") + 3
        out.append(body[:j] + decl + body[j:])
    return "\n".join(out) + "\n"


def split_unit(name, text, funcs, parts_wanted):
    """-> [text of part 1, ...]: the non-routine items go to every part, the routines are dealt out in order so that
    each part gets about the same size; static helpers stay with the routine after them."""
    items = parse_items(text)
    shared = [it[1] for it in items if it[0] == "other"]
    groups, cur = [], []
    for it in items:
        if it[0] != "fn":
            continue
        cur.append(it)
        if not it[2]:                                       # a non-static routine closes the group
            groups.append(cur)
            cur = []
    if cur:
        groups.append(cur)
    sizes = [sum(funcs.get(it[1], 0) for it in g) for g in groups]
    total = sum(sizes)
    target = total / parts_wanted
    parts, acc, part = [], 0, []
    for g, sz in zip(groups, sizes):
        if part and acc + sz > target * 1.02 and len(parts) < parts_wanted - 1:
            parts.append(part)
            part, acc = [], 0
        part.append(g)
        acc += sz
    parts.append(part)
    head = "\n".join(shared)
    return [head + "\n" + "\n".join(it[3] for g in p for it in g) + "\n" for p in parts]


def main(argv):
    gen, out = Path(argv[1]).resolve(), Path(argv[2])
    inc = out / "inc"
    obj = out / "obj"
    for d in (inc, obj, out / "src"):
        d.mkdir(parents=True, exist_ok=True)
    here = Path(__file__).resolve().parent.parent
    for f in ("game.h", "vmlayout.h"):
        (inc / f).write_text((gen / f).read_text())
    for f in ("pool.h", "coco_map.h"):
        (inc / f).write_text((here / "src/game" / f).read_text())
    incs = [str(here / "shim"), str(inc), str(gen)]
    # the table of procedure ids: CMOC cannot initialise from a 32-bit constant, so the id is two words
    gh = (gen / "game.h").read_text()
    ids = {m.group(1): int(m.group(2), 16) for m in re.finditer(r"^#define PROC_(\w+) (0x[0-9A-Fa-f]+)UL", gh, re.M)}
    pt = (gen / "proc_table.c").read_text()
    order = [m.group(1) for m in re.finditer(r"\{PROC_(\w+), \(void \(\*\)\(void\)\)(\w+)\}", pt)]
    fns = dict(re.findall(r"\{PROC_(\w+), \(void \(\*\)\(void\)\)(\w+)\}", pt))
    rows = sorted((ids[k], fns[k]) for k in fns)
    with open(out / "src/proc_table.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the table of procedure ids (the PC's far addresses of the routines the game stores in\n"
                "* its handler tables), sorted by id; rtl_proc looks an id up. Entry: high word, low word, the routine (its far stub).\n")
        w.write("        SECTION rodata\n        EXPORT  _pool_procs_c\n        EXPORT  _pool_procs_c_count\n")
        for i, f in rows:
            w.write("        IMPORT  _%s\n" % f)
        w.write("_pool_procs_c\n")
        for i, f in rows:
            w.write("        FDB     $%04X,$%04X,_%s\n" % (i >> 16, i & 0xFFFF, f))
        w.write("_pool_procs_c_count FDB %d\n        ENDSECTION\n" % len(rows))
    units = sorted(p.stem for p in gen.glob("*.c") if p.stem not in SKIP_UNITS and p.stem != "proc_table"
                   and p.stem not in ENGINE_UNITS)
    info = {}
    banks = []                                              # {name, objs[], units[]}
    engine_api = []                                         # routines the engine provides, in the order of the units
    for u in ENGINE_UNITS:
        engine_api += [n for n in routine_names((gen / (u + ".c")).read_text()) if not n.startswith("init_")]
    for u, names in ENGINE_ROUTINES.items():
        engine_api += names
    engine_api += ENGINE_EXTRA
    # the initialisation parts that do nothing (the translation only announces them) are not called: each call would bring its
    # bank in from the disk at start-up
    trivial = set()
    for u in units + ENGINE_UNITS:
        for m in re.finditer(r"void (init_\w+)\(void\)\s*\{(.*?)\n\}", (gen / (u + ".c")).read_text(), re.S):
            body = re.sub(r"/\*.*?\*/", "", m.group(2), flags=re.S).replace('POOL_TRACE("init");', "")
            if not body.strip():
                trivial.add(m.group(1))
    fn_unit = {}                                            # routine -> unit, for the routines that live in banks
    for u in units:
        if u not in CORE_UNITS:
            for n in routine_names((gen / (u + ".c")).read_text()):
                if n not in CORE_ROUTINES.get(u, []) and n not in ENGINE_ROUTINES.get(u, []):
                    fn_unit[n] = u
    for stem in RTL_BANK:                                   # the runtime bank is a bank too: its routines see only its constants
        for m in re.finditer(r"^[A-Za-z_][\w ]*?[ *](rtl_\w+)\(", (here / "src/game" / (stem + ".c")).read_text(), re.M):
            fn_unit[m.group(1)] = "rtl"
    for m in re.finditer(r'^#define (\w+) S\("(.*)"\)$', (gen / "game.h").read_text(), re.M):
        STRDEFS[m.group(1)] = m.group(2)
    core = []
    for u in units:
        src = gen / (u + ".c")
        if u not in CORE_UNITS:
            src = out / "src" / (u + ".c")
            t = (gen / (u + ".c")).read_text()
            if u in ENGINE_ROUTINES or u in CORE_ROUTINES:
                t = strip_routines(t, set(ENGINE_ROUTINES.get(u, [])) | set(CORE_ROUTINES.get(u, [])))
            t = patch_unit(u, t)
            for a, b in DEBUG_PATCH.get(u, []):                 # a temporary probe in a unit, from the environment (see the file)
                t = t.replace(a, b)
            src.write_text(copy_cross_literals(t, u, fn_unit))
        if u == "pool":
            src = out / "src" / "pool.c"
            t = (gen / "pool.c").read_text()
            for n in sorted(trivial):
                t = re.sub(r"^  %s\(\);\n" % n, "", t, flags=re.M)
            src.write_text(t)
        if u in CORE_UNITS and (u in ENGINE_ROUTINES or u in CORE_ROUTINES):      # the routines the engine or the core take over are cut out of the unit
            src = out / "src" / (u + ".c")
            src.write_text(patch_unit(u, strip_routines((gen / (u + ".c")).read_text(), set(ENGINE_ROUTINES.get(u, [])) | set(CORE_ROUTINES.get(u, [])))))
        o = obj / (u + ".o")
        compile_c(str(src), str(o), incs)
        inf = objinfo(str(o))
        size = inf["code"] + inf["rodata"]
        if u in CORE_UNITS:
            core.append(u)
            info[u] = inf
            continue
        if size <= BANK_LIMIT:
            banks.append({"name": u, "objs": [str(o)], "size": size, "units": [u]})
            info[u] = inf
            continue
        n = -(-size // BANK_LIMIT)
        # a unit in several banks: its routines are in different banks, so a literal handed to one of them is copied as well
        split_text = copy_cross_literals(t, u, fn_unit, True)
        while True:
            texts = split_unit(u, split_text, inf["funcs"], n)
            names = ["%s_%d" % (u, k + 1) for k in range(len(texts))]
            objs, infs = [], []
            for nm, t in zip(names, texts):
                (out / "src" / (nm + ".c")).write_text(t)
                o2 = obj / (nm + ".o")
                compile_c(str(out / "src" / (nm + ".c")), str(o2), incs)
                objs.append(str(o2))
                infs.append(objinfo(str(o2)))
            if all(i["code"] + i["rodata"] <= BANK_LIMIT for i in infs) or n >= 6:
                break
            n += 1
        for nm, o2, i2 in zip(names, objs, infs):
            banks.append({"name": nm, "objs": [o2], "size": i2["code"] + i2["rodata"], "units": [u]})
            info[nm] = i2
        print("split %s (%d bytes) into %d parts: %s" % (u, size, len(names), ", ".join(str(i["code"] + i["rodata"]) for i in infs)))
    # the runtime bank
    robjs = []
    rincs = [str(here / "shim"), str(inc), str(here / "src/engine")]
    for stem in RTL_BANK:
        o2 = obj / (stem + ".o")
        compile_c(str(here / "src/game" / (stem + ".c")), str(o2), rincs)
        robjs.append(str(o2))
    rinfo = {"code": 0, "rodata": 0, "exports": set(), "imports": set(), "funcs": {}}
    for o2 in robjs:
        i2 = objinfo(o2)
        rinfo["code"] += i2["code"]
        rinfo["rodata"] += i2["rodata"]
        rinfo["exports"] |= i2["exports"]
        rinfo["imports"] |= i2["imports"]
    rinfo["imports"] -= rinfo["exports"]
    banks.append({"name": "rtl", "objs": robjs, "size": rinfo["code"] + rinfo["rodata"], "units": ["rtl"]})
    info["rtl"] = rinfo
    p2 = run(["lwasm", "--6809", "-fobj", "-o", str(obj / "proc_table.o"), str(out / "src/proc_table.asm")])
    if p2.returncode:
        raise SystemExit("lwasm failed on proc_table.asm: " + p2.stderr[:300])
    info["proc_table"] = objinfo(str(obj / "proc_table.o"))
    core.append("proc_table")
    # who defines what
    defined = {}
    for b in banks:
        for nm in (b["name"],):
            for sym in info[nm]["exports"]:
                defined[sym] = ("bank", b["name"])
    for u in core:
        for sym in info[u]["exports"]:
            defined[sym] = ("core", u)
    # the routines of a bank that anybody outside it names
    entries = {b["name"]: [] for b in banks}
    seen = {}
    for who, inf in info.items():
        for sym in inf["imports"]:
            d = defined.get(sym)
            if d and d[0] == "bank" and d[1] != who:
                if sym not in seen:
                    seen[sym] = d[1]
                    entries[d[1]].append(sym)
    for k in entries:
        entries[k].sort()
    ids = {b["name"]: i + 1 for i, b in enumerate(banks)}
    asm = lambda src, o: run(["lwasm", "--6809", "-fobj", "-I" + str(here / "src/engine"), "-o", str(o), str(src)])
    # the resident stub of every far entry, the entry table at the head of every bank
    with open(out / "src/farstubs.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the resident stubs of the far entries\n        INCLUDE banks.inc\n        SECTION code\n        IMPORT  __farcall\n")
        # A bank with few entries: a stub is `ldx #entry` and a branch to the bank's common tail (`ldb #bank` / `jmp __farcall`),
        # 5 bytes (6 when the tail is out of short range). A bank with many: a stub is a `bsr` (2 bytes) to a tail that
        # takes the return address back off the stack and turns its distance from the first stub into the entry's address.
        for b in banks:
            syms = entries[b["name"]]
            k, bid = len(syms), ids[b["name"]]
            if k >= 8 and k <= 60:
                for i, sym in enumerate(syms):
                    w.write("        EXPORT  %s\n%s bsr     fcb%d\n" % (sym, sym, bid))
                w.write("fcb%d    puls    x\n        tfr     x,d\n        subd    #%s+2\n        pshs    d\n        lsra\n        rorb\n"
                        "        addd    ,s++\n        addd    #BANK_WINDOW\n        tfr     d,x\n        ldb     #%d\n        jmp     __farcall\n"
                        % (bid, syms[0], bid))
                continue
            for i, sym in enumerate(syms):
                far = ((k - i) * 6) + 2 > 120                       # worst case distance to the tail
                w.write("        EXPORT  %s\n%s ldx     #BANK_WINDOW+BANK_ENTRY_SIZE*%d\n        %s    fcb%d\n" %
                        (sym, sym, i, "lbra" if far else "bra ", bid))
            if k:
                w.write("fcb%d    ldb     #%d\n        jmp     __farcall\n" % (bid, bid))
        w.write("        ENDSECTION\n")
    for b in banks:
        with open(out / "src" / (b["name"] + "_entries.asm"), "w") as w:
            w.write("* generated by tools/mkgame.py: the JMP table at the head of bank %d (%s)\n        SECTION entries\n" % (ids[b["name"]], b["name"]))
            for sym in entries[b["name"]]:
                w.write("        IMPORT  %s\n" % sym)
            for sym in entries[b["name"]]:
                w.write("        jmp     %s\n" % sym)
            w.write("        ENDSECTION\n")
    # the routines the engine provides: a stub that stops the program and says which one was asked for, until it is written
    with open(out / "src/engine_stubs.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the engine's routines, not written yet\n        INCLUDE mailbox.inc\n        SECTION code\n")
        w.write("        IMPORT  __engcall\n")
        for sym in engine_api:
            w.write("        EXPORT  %s\n" % stub_sym(sym))
        for i, sym in enumerate(engine_api):
            w.write("%s ldb     #%d\n        bra     et%d\n" % (stub_sym(sym), i + 1, i // 24))
            if i % 24 == 23 or i == len(engine_api) - 1:             # a tail every 24 stubs, within short branch range
                w.write("et%d     jmp     __engcall\n" % (i // 24))
        w.write("        ENDSECTION\n")
    (out / "engine_names.txt").write_text("\n".join("%d %s" % (i + 1, n) for i, n in enumerate(engine_api)) + "\n")
    # the init parts of the replaced units do nothing here (the engine sets itself up); res08's is written by hand
    with open(out / "src/init_stubs.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the initialisation parts of the units the engine replaced\n        SECTION code\n")
        for u in ENGINE_UNITS:
            if u != "res08":                                # the init of res08 is src/game/platform.c
                w.write("        EXPORT  _init_%s\n_init_%s rts\n" % (u.upper(), u.upper()))
        w.write("        ENDSECTION\n")
    # helpers of CMOC's library that banks use: pulled into the core, which the banks then call by address
    stubbed = {stub_sym(n) for n in engine_api} | {sym for v in entries.values() for sym in v}
    lib = set()
    for who, inf in info.items():
        for sym in inf["imports"]:
            if sym not in defined and sym not in stubbed and not sym.startswith("_init_"):
                lib.add(sym)
    lib = sorted(lib - {"_main"})
    with open(out / "src/libpull.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the library helpers the banks need, referenced so that the core carries them\n        SECTION code\n")
        for sym in lib:
            w.write("        IMPORT  %s\n" % sym)
        w.write("libpull\n")
        for sym in lib:
            w.write("        FDB     %s\n" % sym)
        w.write("        ENDSECTION\n")
    objs_asm = []
    for nm in ("farstubs", "engine_stubs", "init_stubs", "libpull"):
        r = asm(out / "src" / (nm + ".asm"), obj / (nm + ".o"))
        if r.returncode:
            raise SystemExit("lwasm %s: %s" % (nm, r.stderr[:400]))
    for b in banks:
        r = asm(out / "src" / (b["name"] + "_entries.asm"), obj / (b["name"] + "_entries.o"))
        if r.returncode:
            raise SystemExit("lwasm %s: %s" % (b["name"], r.stderr[:400]))
    (out / "banks.json").write_text(json.dumps({
        "banks": [{"name": b["name"], "id": ids[b["name"]], "objs": b["objs"], "entries": entries[b["name"]], "size": b["size"]} for b in banks],
        "core": core, "engine_api": engine_api}, indent=1))
    tot = sum(b["size"] for b in banks)
    print("%d banks (%d bytes), core units %s; %d far entries; %d engine routines" %
          (len(banks), tot, " ".join(core), sum(len(v) for v in entries.values()), len(engine_api)))
    for b in banks:
        print("  %2d %-10s %6d bytes  %3d entries" % (ids[b["name"]], b["name"], b["size"], len(entries[b["name"]])))
    if "--link" in argv:
        return link_all(out, here, banks, ids, info, core, entries)
    return 0


ENGINE_C = ["api", "gameboot", "vol", "img", "dax", "gfx", "rsdos", "mailbox"]
ENGINE_ASM = ["boot", "mmu", "disk", "irq", "kernels", "rle", "engcall", "apitab", "nobanks"]


def build_engine(out, here):
    """The engine's program (POOL.BIN, task 1): the engine objects, the table of the routines the game calls (api_tab.c,
    from engine_names.txt and the api_ functions of api.c) and gameboot.c's main. Its map gives the core the addresses of
    the shared section ($0600..$097D: the interrupt handler, the keyboard, __engcall, the bank table) as constants."""
    eobj = out / "eobj"
    eobj.mkdir(exist_ok=True)
    names = [l.split()[1] for l in (out / "engine_names.txt").read_text().split("\n") if l.strip()]
    have = set(re.findall(r"^\w[\w ]*\bapi_(\w+)\(", (here / "src/engine/api.c").read_text(), re.M))
    with open(out / "src/api_tab.c", "w") as w:
        w.write("/* generated by tools/mkgame.py: routine number -> api_ function (0 is the bank loader) */\nvoid api_bankload(void);\nvoid api_unimpl(void);\n")
        for n in names:
            if n in have:
                w.write("void api_%s(void);\n" % n)
        w.write("void (*api_tab[%d])(void) = {\n  api_bankload,\n" % (len(names) + 1))
        for n in names:
            w.write("  api_%s,\n" % (n if n in have else "unimpl"))
        w.write("};\n")
    objs = []
    for c in ENGINE_C:
        compile_c(str(here / "src/engine" / (c + ".c")), str(eobj / (c + ".o")), [str(here / "src/engine")])
        objs.append(str(eobj / (c + ".o")))
    compile_c(str(out / "src/api_tab.c"), str(eobj / "api_tab.o"), [str(here / "src/engine")])
    objs.append(str(eobj / "api_tab.o"))
    for a in ENGINE_ASM:
        r = run(["lwasm", "--6809", "-fobj", "-I" + str(here / "src/engine"), "-o", str(eobj / (a + ".o")), str(here / "src/engine" / (a + ".asm"))])
        if r.returncode:
            raise SystemExit("lwasm %s: %s" % (a, r.stderr[:400]))
        objs.append(str(eobj / (a + ".o")))
    libs = ["-L/usr/local/share/cmoc/lib", "-lcmoc-crt-void", "-lcmoc-std-void"]
    r = run(["lwlink", "--format=decb", "--script=" + str(here / "src/engine/core.link"), "--map=" + str(out / "pool.map"),
             "-o", str(out / "POOL.BIN")] + objs + libs)
    if r.returncode:
        raise SystemExit("lwlink engine: " + (r.stderr + r.stdout)[:800])
    strip_low_records(out / "POOL.BIN")
    text = (out / "pool.map").read_text()
    sec = [(m.group(1), int(m.group(3), 16), int(m.group(4), 16)) for m in
           re.finditer(r"^Section: (\S+) \((.*?)\) load at ([0-9A-Fa-f]+), length ([0-9A-Fa-f]+)", text, re.M)]
    end = max(a + n for _, a, n in sec if a >= 0x2000)
    print("engine: %d routines of the game (%d written), ends at $%04X (%d bytes from $2000)" %
          (len(names), len(have & set(names)), end, end - 0x2000))
    if end > 0x7C00:
        raise SystemExit("the engine ends at $%04X, past the image of the shared data at $7C00" % end)
    sys.path.insert(0, str(here / "tools"))
    import symexport
    syms = symexport.read_map(str(out / "pool.map"))
    with open(obj_dir(out) / "engsyms.asm", "w") as f:
        f.write("* generated by tools/mkgame.py from pool.map: the engine's shared symbols (slot 0, both tasks see them)\n        SECTION _constants,constant\n")
        for n in sorted(syms):
            if n.startswith("_") and 0x0400 <= syms[n] < 0x0A00:
                f.write("%s\tEQU\t$%04X\n\tEXPORT\t%s\n" % (n, syms[n], n))
        f.write("        ENDSECTION\n")
    r = run(["lwasm", "--6809", "-fobj", "-o", str(obj_dir(out) / "engsyms.o"), str(obj_dir(out) / "engsyms.asm")])
    if r.returncode:
        raise SystemExit("lwasm engsyms: " + r.stderr[:400])


from stripbin import strip_low_records  # noqa: E402


def obj_dir(out):
    return out / "obj"


def link_all(out, here, banks, ids, info, core, entries):
    """core.bin and the bank images. The core's undefined symbols that are not written yet become stubs that stop the program
    (build/game/missing.txt lists them: that list is the work left)."""
    obj, src = out / "obj", out / "src"
    build_engine(out, here)
    r = run(["lwasm", "--6809", "-fobj", "-DGAME=1", "-I" + str(here / "src/engine"), "-o", str(obj / "farcallg.o"), str(here / "src/engine/farcall.asm")])
    if r.returncode:
        raise SystemExit("lwasm farcallg: " + r.stderr[:400])
    base = [obj / "farcallg.o", obj / "engsyms.o"]          # (the engine's shared symbols come from the engine's map)
    (obj / "rtl").mkdir(exist_ok=True)
    for stale in (obj / "rtl").glob("*.o"):
        stale.unlink()
    incs = [str(here / "shim"), str(out / "inc"), str(here / "src/engine")]
    for c in sorted((here / "src/game").glob("*.c")):          # the runtime and the platform layer of the CoCo
        if c.stem in RTL_BANK:
            continue                                            # in the runtime bank (below)
        compile_c(str(c), str(obj / "rtl" / (c.stem + ".o")), incs)
    for a in sorted((here / "src/game").glob("*.asm")):
        r = run(["lwasm", "--6809", "-fobj", "-I" + str(here / "src/engine"), "-o", str(obj / "rtl" / (a.stem + ".o")), str(a)])
        if r.returncode:
            raise SystemExit("lwasm %s: %s" % (a, r.stderr[:400]))
    rtl = sorted((obj / "rtl").glob("*.o"))
    libs = ["-L/usr/local/share/cmoc/lib", "-lcmoc-crt-void", "-lcmoc-std-void"]
    cobjs = [str(o) for o in base] + [str(obj / (n + ".o")) for n in ("farstubs", "engine_stubs", "init_stubs", "libpull")] + \
            [str(obj / (u + ".o")) for u in core] + [str(o) for o in rtl]
    missing = []
    for attempt in range(4):
        extra = []
        if missing:
            with open(src / "missing.asm", "w") as w:
                w.write("* generated by tools/mkgame.py: symbols nothing defines yet\n        INCLUDE mailbox.inc\n        SECTION code\n")
                for i, sym in enumerate(missing):
                    w.write("        EXPORT  %s\n%s ldd     #%d\n        lbra    __missing\n" % (sym, sym, 0x100 + i))
                w.write("__missing std   MB_BASE+$3C\n        lda     #2\n        sta     MB_STATUS\n        orcc    #$50\n@stop   bra     @stop\n        ENDSECTION\n")
            r = run(["lwasm", "--6809", "-fobj", "-I" + str(here / "src/engine"), "-o", str(obj / "missing.o"), str(src / "missing.asm")])
            if r.returncode:
                raise SystemExit("lwasm missing: " + r.stderr[:400])
            extra = [str(obj / "missing.o")]
            (out / "missing.txt").write_text("\n".join("%d %s" % (0x100 + i, m) for i, m in enumerate(missing)) + "\n")
        r = run(["lwlink", "--format=decb", "--script=" + str(here / "src/engine/gamecore.link"), "--map=" + str(out / "core.map"),
                 "-o", str(out / "core.bin")] + cobjs + extra + libs)
        if r.returncode == 0:
            break
        und = sorted(set(re.findall(r"External symbol (\S+) not found", r.stderr + r.stdout)))
        if not und:
            raise SystemExit("lwlink core: " + (r.stderr + r.stdout)[:800])
        missing = sorted(set(missing) | set(und))
    else:
        raise SystemExit("lwlink core: still failing: " + (r.stderr + r.stdout)[:800])
    top = max((int(m.group(2), 16) + int(m.group(3), 16) for m in
               re.finditer(r"^Section: (\S+) \((.*?)\) load at ([0-9A-Fa-f]+), length ([0-9A-Fa-f]+)", (out / "core.map").read_text(), re.M)
               if False), default=0)
    sec = [(m.group(1), int(m.group(3), 16), int(m.group(4), 16)) for m in
           re.finditer(r"^Section: (\S+) \((.*?)\) load at ([0-9A-Fa-f]+), length ([0-9A-Fa-f]+)", (out / "core.map").read_text(), re.M)]
    end = max(a + n for _, a, n in sec)
    print("core: ends at $%04X (%d bytes from $2000); %d symbols still missing" % (end, end - 0x2000, len(missing)))
    if end > 0x4C80:
        raise SystemExit("the core ends at $%04X, past the heap tables at $4C80 (src/game/coco_map.h)" % end)
    for m in missing:
        print("   missing", m)
    # the banks
    sym = here / "tools/symexport.py"
    for b in banks:
        n = b["name"]
        objs = [str(obj / (n + "_entries.o"))] + b["objs"]
        r = run(["python3", str(sym), str(out / "core.map"), str(src / (n + "_syms.asm"))] + objs)
        if r.returncode:
            raise SystemExit("symexport %s: %s" % (n, r.stderr[:600]))
        r = run(["lwasm", "--6809", "-fobj", "-o", str(obj / (n + "_syms.o")), str(src / (n + "_syms.asm"))])
        if r.returncode:
            raise SystemExit("lwasm syms %s: %s" % (n, r.stderr[:300]))
        r = run(["lwlink", "--format=raw", "--script=" + str(here / "src/engine/bank.link"), "--map=" + str(out / (n + ".map")),
                 "-o", str(out / (n + ".raw"))] + objs + [str(obj / (n + "_syms.o"))])
        if r.returncode:
            raise SystemExit("lwlink bank %s: %s" % (n, (r.stderr + r.stdout)[:600]))
        r = run(["python3", str(here / "tools/bankcheck.py"), str(out / (n + ".map"))])
        if r.returncode:
            raise SystemExit(r.stderr or r.stdout)
    print("%d banks linked" % len(banks))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

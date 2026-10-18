"""ptypes.py: the Pascal type model of the translator (sizes as Turbo Pascal 6.0 lays them out)."""
from __future__ import annotations


class Ty:
    """A Pascal type. `kind` is one of: int bool char enum real string array record ptr set file proc void
    untyped. `cname` is the C name when the type has one (a declared type or a base type)."""

    def __init__(self, kind, **kw):
        self.kind = kind
        self.name = None          # the Pascal name of a declared type
        self.cname = None         # the C name
        self.lo = 0               # int/char/enum/bool: range
        self.hi = 0
        self.signed = False
        self.size_ = None
        self.elem = None          # array/set/file element, pointer target
        self.index = None         # array: index type (or None for plain numbers)
        self.fields = []          # record: [(name, Ty)]; every field of every arm, in order
        self.variant = None       # record: list of arms (each a list of (name, Ty)) after the fixed part
        self.members = []         # enum: member names
        self.maxlen = 255         # string
        self.params = []          # proc: [Param]
        self.ret = None
        self.unit = None
        self.__dict__.update(kw)

    # --- classification -----------------------------------------------------------------------------
    @property
    def is_int(self):
        return self.kind == "int"

    @property
    def is_ordinal(self):
        return self.kind in ("int", "bool", "char", "enum")

    @property
    def is_str(self):
        return self.kind == "string"

    def size(self) -> int:
        if self.size_ is not None:
            return self.size_
        k = self.kind
        if k in ("int", "bool", "char", "enum"):
            if k == "enum":
                return 1 if len(self.members) <= 256 else 2
            if k in ("bool", "char"):
                return 1
            if self.lo >= 0 and self.hi <= 255:
                return 1
            if self.lo >= -128 and self.hi <= 127:
                return 1
            if self.lo >= -32768 and self.hi <= 65535:
                return 2
            return 4
        if k == "string":
            return self.maxlen + 1
        if k == "array":
            return (self.hi - self.lo + 1) * self.elem.size()
        if k == "record":
            base = sum(t.size() for _n, t in self.fields)
            if self.variant:
                base += max((sum(t.size() for _n, t in arm) for arm in self.variant), default=0)
            return base
        if k == "ptr":
            return 4
        if k == "proc":
            return 4
        if k == "set":
            return set_bytes(self)
        if k == "file":
            return 128 if self.elem is not None or True else 128
        if k == "real":
            return self.size_ or 6
        raise ValueError("size of %s" % k)

    def swaps(self, base=0):
        """[(offset, width, count)] of the multi-byte scalars of a value of this type laid out as Turbo Pascal stores it: each
        entry is `count` scalars of `width` bytes (2 or 4) from `offset` on. A big endian machine reverses each (the CoCo,
        tools/mkvm.py). Variant parts of records are left out (their arms share bytes); reals, sets and strings are bytes."""
        k = self.kind
        if k in ("int", "enum", "bool", "char"):
            n = self.size()
            return [(base, n, 1)] if n in (2, 4) else []
        if k in ("ptr", "proc"):
            return [(base, 4, 1)]
        if k == "array":
            n = self.hi - self.lo + 1
            es = self.elem.size()
            inner = self.elem.swaps(0)
            if not inner:
                return []
            if len(inner) == 1 and inner[0][0] == 0 and inner[0][2] == 1 and inner[0][1] == es:
                return [(base, es, n)]                               # an array of plain scalars: one run
            out = []
            for i in range(n):
                out += [(base + i * es + o, w, c) for o, w, c in inner]
            return out
        if k == "record":
            out, off = [], 0
            for _n, t in self.fields:
                out += t.swaps(base + off)
                off += t.size()
            return out
        return []

    def int_range(self):
        """(lo, hi) of an ordinal type."""
        return self.lo, self.hi

    def storage(self):
        """(bytes, signed) of an ordinal type as stored."""
        n = self.size()
        if self.kind == "int":
            signed = self.lo < 0
            if n == 2 and self.lo >= 0:
                signed = False
            return n, signed
        return n, False

    def __repr__(self):
        return "Ty(%s%s)" % (self.kind, " " + self.name if self.name else "")


def set_bytes(t: Ty) -> int:
    """Turbo Pascal stores a set from the byte holding its lowest member to the byte holding its highest."""
    base = t.elem
    hi = base.hi if base.is_ordinal else 255
    lo = base.lo if base.is_ordinal else 0
    return (hi // 8) - (lo // 8) + 1 if hi >= 0 else 1


def set_first_byte(t: Ty) -> int:
    base = t.elem
    return (base.lo // 8) if base.is_ordinal and base.lo > 0 else 0


def make_int(name, lo, hi, cname):
    t = Ty("int", lo=lo, hi=hi, signed=lo < 0)
    t.name = name
    t.cname = cname
    return t


BYTE = make_int("Byte", 0, 255, "u8")
SHORTINT = make_int("ShortInt", -128, 127, "s8")
INTEGER = make_int("Integer", -32768, 32767, "s16")
WORD = make_int("Word", 0, 65535, "u16")
LONGINT = make_int("LongInt", -2147483648, 2147483647, "s32")
BOOLEAN = Ty("bool", lo=0, hi=1, name="Boolean", cname="u8")
CHAR = Ty("char", lo=0, hi=255, name="Char", cname="u8")
REAL = Ty("real", size_=6, name="Real", cname="double")
SINGLE = Ty("real", size_=4, name="Single", cname="double")
DOUBLE = Ty("real", size_=8, name="Double", cname="double")
EXTENDED = Ty("real", size_=10, name="Extended", cname="double")
COMP = Ty("real", size_=8, name="Comp", cname="double")
POINTER = Ty("ptr", elem=None, name="Pointer", cname="farptr")
STRING255 = Ty("string", maxlen=255, name="string")
VOID = Ty("void")
UNTYPED = Ty("untyped")
NILTYPE = Ty("ptr", elem=None)
TEXTFILE = Ty("file", elem=None, name="Text", cname="TextRec")
TEXTFILE.size_ = 256
TEXTFILE.text = True
ANYFILE = Ty("file", elem=None, name="File", cname="FileRec")
ANYFILE.size_ = 128


def range_type(lo: int, hi: int) -> Ty:
    """The integer type Turbo Pascal gives an anonymous subrange."""
    if lo >= 0 and hi <= 255:
        return BYTE if (lo, hi) == (0, 255) else _sub(lo, hi, BYTE)
    if lo >= -128 and hi <= 127:
        return _sub(lo, hi, SHORTINT)
    if lo >= -32768 and hi <= 32767:
        return _sub(lo, hi, INTEGER)
    if lo >= 0 and hi <= 65535:
        return _sub(lo, hi, WORD)
    return _sub(lo, hi, LONGINT)


def _sub(lo, hi, base):
    t = Ty("int", lo=lo, hi=hi, signed=lo < 0)
    t.cname = base.cname
    t.base = base
    return t


def sizeof(t: Ty) -> int:
    return t.size()

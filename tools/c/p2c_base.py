"""p2c_base.py: symbols, scopes, C naming and type declarators for the Pascal to C translator."""
from __future__ import annotations

from ptypes import Ty


class Sym:
    """A named thing. kind: const type var routine enumconst unit."""

    def __init__(self, kind, name, **kw):
        self.kind = kind
        self.name = name
        self.cname = name
        self.type = None
        self.value = None          # const: python value (int / str / list of ints for sets / float)
        self.unit = None
        self.__dict__.update(kw)


class Scope:
    def __init__(self, parent=None, name=""):
        self.parent = parent
        self.name = name
        self.syms: dict[str, Sym] = {}

    def add(self, s: Sym):
        self.syms[s.name.lower()] = s
        return s

    def find(self, name: str):
        k = name.lower()
        sc = self
        while sc is not None:
            if hasattr(sc, "uses"):
                return sc.find(name)
            s = sc.syms.get(k)
            if s is not None:
                return s
            sc = sc.parent
        return None

    def find_local(self, name: str):
        return self.syms.get(name.lower())


C_RESERVED = set("""auto break case char const continue default do double else enum extern float for goto if
inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void
volatile while _Bool bool true false NULL EOF errno stdin stdout stderr main exit abs free malloc printf memcpy
memset memmove strlen strcmp assert min max u8 u16 u32 s8 s16 s32 farptr S fr up Result index time y1 j0 j1 jn
y0 yn signal select read write open close remove rename link unlink access dup pipe sleep environ optarg
gamma round trunc floor ceil exp log pow sqrt sin cos tan div ldiv toupper tolower isalpha isdigit
Sound Delay Intr Mem Port Seek Erase Assign Reset Rewrite Close GetMem FreeMem Halt Random Randomize Move
FillChar KeyPressed ReadKey Pos Copy Length Delete Insert Str Val Chr Ord Succ Pred Odd Abs Sqr Hi Lo Swap
Inc Dec Exit New Dispose UpCase Trunc Round SizeOf Ptr
""".split())


def cstr_literal(s: str) -> str:
    """A C string literal for a Pascal string: length byte first, then the characters (octal escapes)."""
    data = bytes([len(s) & 255]) + s.encode("latin-1")
    return c_bytes(data)


def c_bytes(data: bytes) -> str:
    out = ['"']
    for b in data:
        if b == 34:
            out.append('\\"')
        elif b == 92:
            out.append("\\\\")
        elif 32 <= b < 127 and b != 63:        # '?' avoided (trigraphs)
            out.append(chr(b))
        else:
            out.append("\\%03o" % b)
    out.append('"')
    return "".join(out)


def c_char(v: int) -> str:
    if v == 39:
        return "'\\''"
    if v == 92:
        return "'\\\\'"
    if 32 <= v < 127:
        return "'%s'" % chr(v)
    return "0x%02X" % v


def decl(t: Ty, name: str) -> str:
    """A C declaration of `name` with type t (name may be "" or an abstract declarator like "(*)")."""
    if t.cname:
        return ("%s %s" % (t.cname, name)).strip()
    k = t.kind
    if k == "array":
        n = t.hi - t.lo + 1
        return decl(t.elem, "%s[%d]" % (name, n))
    if k == "string":
        return decl_u8(name, t.maxlen + 1)
    if k in ("int", "bool", "char", "enum"):
        n, signed = t.storage()
        base = {1: "s8" if signed else "u8", 2: "s16" if signed else "u16", 4: "s32"}[n]
        return ("%s %s" % (base, name)).strip()
    if k in ("ptr", "proc"):
        return ("farptr %s" % name).strip()
    if k == "real":
        return ("double %s" % name).strip()
    if k == "set":
        return decl_u8(name, t.size())
    if k == "file":
        return ("%s %s" % ("TextRec" if getattr(t, "text", False) else "FileRec", name)).strip()
    raise ValueError("cannot declare %r %s" % (t, name))


def decl_u8(name: str, n: int) -> str:
    return "u8 %s[%d]" % (name, n)


def ctype(t: Ty) -> str:
    """The type name for casts: `u16`, `TFoo`, `u8 (*)[41]`."""
    return decl(t, "")


def ptr_ctype(t: Ty) -> str:
    """C type 'pointer to t', for casts: `u16 *`, `u8 (*)[41]`."""
    return decl(t, "(*)")

#!/usr/bin/env python3
"""peep.py FILE.s: a peephole pass over the assembly CMOC writes (step 8.9c, idea 7). mkgame compiles with `cmoc --lwasm=tools/lwasm_peep.sh`, so CMOC's own
call of the assembler first runs this on the .s file it has just written. Every rule keeps the registers and the memory the following code can see, and a
label or a comment-free branch target between the instructions of a pattern stops it (comments are skipped).

R1  TFR D,X ; LEAX n,X ; TFR X,D ; ADDD ,S++ ; TFR D,X       (the address of a member of a record, plus a stacked array index)
      -> ADDD ,S++ ; ADDD #n ; TFR D,X                          (n = 0: ADDD ,S++ ; TFR D,X)           D and X end the same
R2  TFR X,D ; ADDD ,S++ ; TFR D,X                               (X plus a stacked index, any other source of X)
      -> PULS A,B ; LEAX D,X                                     when the next instruction replaces D or does not read it (a load, a store through X)
R3  LEAX ,X                                                     (a member at offset 0)  -> removed when no conditional branch follows

The statistics go to stderr as one line: rule counts."""
import re
import sys

INS = re.compile(r"^\t([A-Z][A-Z0-9]*)(?:\t([^\t]*))?(.*)$")
FLAG_SAFE_NEXT = re.compile(r"^(LD[ABDXYU]|ST[ABDXYU]|CLR[AB]?|INC[AB]?|DEC[AB]?|TST[AB]?|CMP[ABDXYU]|ADD[ABD]|SUB[ABD]|AND[AB]|OR[AB]|EOR[AB]|LEA[XYUS]|PSHS|PSHU|NEG[AB]?|COM[AB]?|LSR[AB]?|ASL[AB]?|ASR[AB]?|ROL[AB]?|ROR[AB]?|TFR|EXG|SEX|MUL|ABX|JSR|LBSR|BSR)$")
D_READERS = re.compile(r"^(STD|STA|STB|ADDD|SUBD|CMPD|PSHS|PSHU|TFR|EXG|SEX|ADCA|ADCB|ADDA|ADDB|SUBA|SUBB|SBCA|SBCB|ANDA|ANDB|ORA|ORB|EORA|EORB|CMPA|CMPB|INCA|INCB|DECA|DECB|NEGA|NEGB|COMA|COMB|LSRA|LSRB|ASLA|ASLB|ASRA|ASRB|ROLA|ROLB|RORA|RORB|TSTA|TSTB|MUL|ABX|DAA|BITA|BITB|JSR|LBSR|BSR|RTS|PULS)$")


def parse(lines):
    """-> list of (mnemonic, operand) or None for a line that is not an instruction (comment: skipped by the matcher, label or directive: a barrier)"""
    out = []
    for l in lines:
        if l.startswith("*") or not l.strip():
            out.append("c")
            continue
        m = INS.match(l)
        if m and l[0] == "\t":
            out.append((m.group(1), (m.group(2) or "").strip()))
        else:
            out.append(None)
    return out


def peep(text):
    lines = text.split("\n")
    P = parse(lines)
    stats = {"R1": 0, "R2": 0, "R3": 0}
    drop = set()
    new = {}                                   # line index -> replacement line text
    n = len(lines)

    def nexti(i, k):
        """the indexes of the next k instructions after line i, skipping comments; None if a barrier or the end comes first"""
        out = []
        j = i + 1
        while len(out) < k:
            if j >= n or P[j] is None:
                return None
            if P[j] != "c":
                out.append(j)
            j += 1
        return out
    i = 0
    while i < n:
        if P[i] in (None, "c") or i in drop:
            i += 1
            continue
        mn, op = P[i]
        # R1
        if mn == "TFR" and op == "D,X":
            nx = nexti(i, 4)
            if nx and all(P[j] != "c" and j not in drop for j in nx):
                a, b, c, d = (P[j] for j in nx)
                mo = re.match(r"^(-?[\w$]+|),X$", a[1]) if a[0] == "LEAX" else None
                if mo and b == ("TFR", "X,D") and c == ("ADDD", ",S++") and d == ("TFR", "D,X"):
                    off = mo.group(1)
                    # first instruction is the TFR D,X at i; the pieces become: ADDD ,S++ [ADDD #n] TFR D,X
                    new[i] = "\tADDD\t,S++\t\tindex of the array added to the address of the record (optim: peep R1)"
                    drop.add(nx[1])
                    if off in ("", "0"):
                        drop.add(nx[0])
                        new[nx[2]] = "\tTFR\tD,X\t\tput resulting address in X"
                        drop.add(nx[3])
                    else:
                        new[nx[0]] = "\tADDD\t#%s\t\tmember offset (optim: peep R1)" % off
                        drop.add(nx[2])
                        new[nx[3]] = "\tTFR\tD,X\t\tput resulting address in X"
                        # the order of the three: ADDD ,S++ at i, ADDD #n at nx[0], TFR at nx[3]
                        new[nx[2]] = None
                    stats["R1"] += 1
                    i = nx[3] + 1
                    continue
        # R2
        if mn == "TFR" and op == "X,D":
            nx = nexti(i, 3)
            if nx:
                b, c, d = (P[j] for j in nx)
                if b == ("ADDD", ",S++") and c == ("TFR", "D,X") and d[0] not in ("LDD",) and nx[0] not in drop:
                    if FLAG_SAFE_NEXT.match(d[0]) and not D_READERS.match(d[0]) or d[0] in ("LDA", "LDB", "LDD", "LDX", "LDY", "LDU", "CLR", "TST", "INC", "DEC"):
                        new[i] = "\tPULS\tA,B\t\tindex of the array (optim: peep R2)"
                        new[nx[0]] = "\tLEAX\tD,X\t\tadd it to the address (optim: peep R2)"
                        drop.add(nx[1])
                        stats["R2"] += 1
                        i = nx[1] + 1
                        continue
        # R3
        if mn == "LEAX" and op == ",X":
            nx = nexti(i, 1)
            if nx and not (P[nx[0]][0].startswith(("B", "LB")) and P[nx[0]][0] not in ("BSR", "LBSR")):
                drop.add(i)
                stats["R3"] += 1
        i += 1
    out = []
    for k, l in enumerate(lines):
        if k in new and new[k] is None:
            continue
        if k in drop and k not in new:
            continue
        out.append(new.get(k, l) if k in new else l)
    return "\n".join(out), stats


if __name__ == "__main__":
    f = sys.argv[1]
    t, st = peep(open(f, errors="surrogateescape").read())
    open(f, "w", errors="surrogateescape").write(t)
    sys.stderr.write("peep %s: %s\n" % (f, st))

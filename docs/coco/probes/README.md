# CMOC probes

Small C programs that settle how CMOC compiles an idiom, the way `make tpc` settles Turbo Pascal idioms. A claim about CMOC semantics in the Phase 8 docs should point at a probe here.

## cmoc-byte-arith.c

Question: does CMOC widen byte operands to `int` like standard C (and like Turbo Pascal, where Byte operands count as Integer)?

Run 2026-10-17 with CMOC 0.1.86 (built from the GitHub mirror `stahta01/cmoc`) and LWTOOLS 4.21 (mirror `stahta01/lwtools`), in the USim 6809 simulator that ships in CMOC's source tree:

```sh
cmoc --usim -o p.srec cmoc-byte-arith.c
usim p.srec            # src/usim-0.91-cmoc/usim in the CMOC build tree
```

Output: `144 44 70000 253 144 0`

| Printed | Expression | Standard C | CMOC |
|---|---|---:|---:|
| 1st | `row * 40`, `row` = 10 (`unsigned char`) | 400 | 144 |
| 2nd | `a + b`, 200 + 100 (`unsigned char`) | 300 | 44 |
| 3rd | `(long)w1 + w2`, 60000 + 10000 (`unsigned int`) | 70000 | 70000 |
| 4th | `k - 10`, `k` = 7 (`unsigned char`), stored in `int` | -3 | 253 |
| 5th | `(unsigned char)(a << 1)` | 144 | 144 |
| 6th | `si < 0u`, `si` = -1 | 0 | 0 |

With `-Wgives-byte`, CMOC 0.1.86 warns only about the addition (line 6), not the multiply by a constant (line 5) or the subtraction of a constant (line 8).

Conclusion: in CMOC a binary operation on two byte-sized operands (an 8-bit constant counts as one) is computed in 8 bits, and the warning does not find every case. The port must cast explicitly (PORTING-GUIDE section 6).

To do in step 8.0: rerun with CMOC 0.1.100 inside `jamieleecho/coco-dev` and record the result here.

/* fpir-initial-s.c: open questions on CMOC 0.1.100 options (research 04, Q2 and Q6).
 * Compile with: cmoc -S --void-target --initial-s=1F80 -O2 ...  (make asm-probe) */
_CMOC_fpir_ unsigned int twice(unsigned int x)   /* first parameter in X? (0.1.86 had it) */
{
    return x + x;
}

_CMOC_fpir_ unsigned char inc(unsigned char b)   /* first parameter in B? */
{
    return b + 1;
}

int main(void)
{
    return twice(3) + inc(4);
}

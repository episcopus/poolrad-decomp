/* cmoc-bug-negbyte.c: CMOC 0.1.100 assembles `LDB #$FFFF` for a negative constant stored in a
 * signed byte at a fixed address (the pointer is a literal address), and lwasm rejects it with
 * "Byte overflow". Through a pointer variable the same store is fine (`LDB #$FF`). Found
 * compiling ovl12 (step 8.1). Workaround: store an unsigned byte constant (0xFF). */
#define Roll (*(signed char *)0x6822)

void miss(void)
{
    Roll = -1;
}

void ok(signed char *p)
{
    *p = -1;
}

int main(void)
{
    miss();
    return 0;
}

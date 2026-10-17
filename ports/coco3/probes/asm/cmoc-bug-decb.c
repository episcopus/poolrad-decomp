/* cmoc-bug-decb.c: CMOC 0.1.100 (-O1, -O2) turns `byte -= constant;` on a byte at a fixed address
 * into `DECB #$05`, which is not an instruction: the optimizer then stops with "failed to determine
 * registers affected by opcode of DECB #$05". Found compiling ovl12 (step 8.1). Workaround:
 * write `x = x - 5;`. `make asm-probe P=cmoc-bug-decb` shows the bad line. */
enum { Step = 5 };
#define Morale (*(unsigned char *)0x6825)

void lower(void)
{
    Morale -= Step;
}

int main(void)
{
    lower();
    return 0;
}

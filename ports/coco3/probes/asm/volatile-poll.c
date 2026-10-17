/* volatile-poll.c: Q7 (PORTING-GUIDE section 12). Does a polling loop on a global that only an
 * interrupt handler changes reload it on every pass? CMOC ignores `volatile`, so the answer
 * must come from the generated code (make asm-probe P=volatile-poll prints the loops). */
unsigned char ticks;            /* set by an ISR in the real program */
unsigned int bigticks;

void wait_for_tick(void)
{
    while (ticks == 0)
        ;
}

void wait_until_ten(void)
{
    unsigned char t = ticks;    /* a local copy is not reloaded: the idiom to avoid */
    while (t < 10)
        ;
}

void wait_for_big(void)
{
    while (bigticks < 100u)
        ;
}

unsigned char read_twice(void)
{
    unsigned char a = ticks;
    unsigned char b = ticks;    /* does the second read survive? */
    return (unsigned char)(a - b);
}

int main(void)
{
    wait_for_tick();
    wait_until_ten();
    wait_for_big();
    return read_twice();
}

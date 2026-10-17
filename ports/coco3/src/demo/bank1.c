/* bank1.c: code bank 1, linked at $8000 (window slots 4 and 5). */
extern unsigned int core_double(unsigned int x);                  /* resident */
extern unsigned int bank2_mul(unsigned int a, unsigned int b);    /* other bank, via stub */

unsigned int bank1_whoami(void)
{
    return 0xB1B1u;
}

unsigned int bank1_add(unsigned int a, unsigned int b)
{
    return a + b;
}

unsigned int bank1_chain(unsigned int x)
{
    return bank2_mul(core_double(x), 10u) + 1u;
}

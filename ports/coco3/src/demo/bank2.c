/* bank2.c: code bank 2, also linked at $8000. */
unsigned int bank2_whoami(void)
{
    return 0xB2B2u;
}

unsigned int bank2_mul(unsigned int a, unsigned int b)
{
    return a * b;
}

unsigned int bank2_bytes(unsigned char a, unsigned char b)
{
    unsigned int s = a + b;     /* CMOC: 8-bit add, 200 + 100 gives 44 */
    return s;
}

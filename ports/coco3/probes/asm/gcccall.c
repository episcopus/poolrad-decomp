/* gcccall.c: CMOC 0.1.87+ has an experimental register calling convention, __gcccall
 * (the gcc6809 convention). What does it do to a call and to a callee? Relevant to the
 * far-call stubs (arguments no longer on the stack) and to decision D11. */
__gcccall int add3(int a, int b, int c)
{
    return a + b + c;
}

__gcccall unsigned char lo(unsigned char x, unsigned int y)
{
    return (unsigned char)(x + (unsigned char)y);
}

int main(void)
{
    return add3(1, 2, 3) + lo(4, 5);
}

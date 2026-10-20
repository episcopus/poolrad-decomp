/* long-ret.c: how CMOC returns and takes a 32 bit value, and whether `(u16)&((T *)0)->field` is accepted (HEAP-STUDY option 1). */
typedef unsigned long u32; typedef unsigned int u16;
typedef struct { unsigned char a[8]; u32 p; unsigned char b[3]; } R;
u32 peek(u32 p, u16 off);
u32 f(void) { return 0x11223344UL; }
u32 g(u32 p) { return peek(p, (u16)&(((R *)0)->p)); }
u32 h(u32 p, int i) { return peek(p, (u16)&(((R *)0)->b[i])); }
int main(void) { return 0; }

/* win-order.c: in which order CMOC 0.1.100 -O2 evaluates calls that return a pointer into a data window (HEAP-STUDY.md, option 1).
 * W(n) stands for vm_ptr / the banked accessor: a call whose result is good until the next call. Read the assembly with
 * `make asm-probe P=win-order`: a `jsr _W` is preceded by `ldd #n` (the argument). */
unsigned char *W(unsigned int n);
typedef struct { unsigned char a[8]; unsigned int w; unsigned char b; } R;
void f3(unsigned char x, unsigned char y, unsigned char z);
void g2(unsigned char *x, unsigned char *y);
void h2(R *x, unsigned char y);

void t1(void) { *W(1) = *W(2); }
void t2(void) { *W(1) = *W(2) + *W(3); }
void t3(void) { *W(1) += *W(2); }
void t4(void) { ((R *)W(1))->a[*W(2)] = *W(3); }
void t5(void) { *(R *)W(1) = *(R *)W(2); }
void t6(void) { f3(*W(1), *W(2), *W(3)); }
void t7(void) { g2(W(1), W(2)); }
void t8(void) { if (*W(1) == *W(2) && *W(3)) t1(); }
void t9(void) { (*W(1))++; }
void t10(void) { ((R *)W(1))->w = ((R *)W(2))->w + ((R *)W(3))->w; }
void t11(void) { ((R *)W(1))->b = *W(2); }
void t12(void) { h2((R *)W(1), *W(2)); }
int main(void) { return 0; }

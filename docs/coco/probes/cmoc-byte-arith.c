#include <cmoc.h>
unsigned char row = 10; unsigned char a = 200, b = 100;
unsigned int w1 = 60000, w2 = 10000; int si = -1; unsigned char k = 7;
int main(void) {
  unsigned int r1 = row * 40;          /* expect 400 */
  unsigned int r2 = a + b;             /* expect 300 */
  long l = (long)w1 + w2;              /* expect 70000 */
  int r3 = k - 10;                     /* expect -3 */
  unsigned char sh = (unsigned char)(a << 1); 
  printf("%u %u %ld %d %u %d\n", r1, r2, l, r3, sh, (int)(si < 0u));
  return 0;
}

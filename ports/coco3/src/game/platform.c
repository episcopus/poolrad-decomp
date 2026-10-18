/* platform.c: the game's start on the CoCo (step 8.5c): what the PC's Turbo Pascal program header did, in C. */
#include "game.h"

void pool_init_units(void);
void pool_main(void);

int main(void)
{
    pool_init_units();
    pool_main();
    return 0;
}

/* platform.c: the game's start on the CoCo (step 8.5c): what the PC's Turbo Pascal program header and the initialisation part
 * of RES08 did, and the hardware layer of the sound driver (nothing yet: no sound). */
#include "game.h"
#include "mailbox.h"

void pool_init_units(void);
void pool_main(void);
void irq_start(void);
void eng_leave(void);
void vm_init(void);

/* the initialisation part of RES08, with the answers of POOL.CFG the original ran with (E, P, C:\POOLRAD\, C:\POOLRAD\SAVE\, F):
 * the EGA's semantics for the game, no sound hardware */
void init_RES08(void)
{
    CheckBreak = 0;
    VideoAdapter = 1;
    SavedVideoMode = 3;
    CurrentVideoMode = 3;
    TextPage = 0;
    FillTextPage = 0;
    SoundMode = 2;
    rtl_str_assign(GameDir, 255, S("\013C:\\POOLRAD\\"));
    rtl_str_assign(SaveDir, 255, S("\023C:\\POOLRAD\\SAVE\\"));
    CfgFlagF = 1;
}

/* the hardware layer of res03's sound driver */
void SetSoundOutput(u16 enabled) { (void)enabled; }
void SetSpeakerTune(u16 tune) { (void)tune; }
void SetTandyTune(u16 tune) { (void)tune; }
void StartSoundTimer(void) { }
void StopSoundTimer(void) { }

int main(void)
{
    eng_leave();                                  /* the game's own address space (boot starts in the engine's) */
    vm_init();
    irq_start();
    pool_init_units();
    pool_main();
    rtl_Halt(0);
    return 0;
}

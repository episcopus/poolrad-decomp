/* platform.c: the game's start on the CoCo (step 8.5c): what the PC's Turbo Pascal program header and the initialisation part
 * of RES08 did. The sound driver is src/snd (step 8.8: the PC speaker's tunes on the CoCo's DAC); its first call allocates its state. */
#include "game.h"
#include "mailbox.h"

void pool_init_units(void);
void pool_main(void);
void irq_start(void);
void eng_leave(void);
void vm_init(void);

/* the initialisation part of RES08, with the answers of POOL.CFG the original ran with (E, P, C:\POOLRAD\, C:\POOLRAD\SAVE\, F):
 * the EGA's semantics for the game, the PC speaker (SoundSpeaker: the CoCo's DAC plays its tunes) */
void init_RES08(void)
{
    CheckBreak = 0;
    SavedVideoMode = 3;
    CurrentVideoMode = 3;
    VideoAdapter = 1;
    SetVideoMode(0xD);
    TextPage = 0;
    FillTextPage = 0;
    SetActivePage(TextPage);
    SetPageSegment(FillTextPage);
    SoundMode = SoundSpeaker;
    SilenceSound();                     /* as RES08: saves SoundMode, starts the driver, no tune, stops it (the sound bank loads here) */
    rtl_str_assign(GameDir, 255, S("\013C:\\POOLRAD\\"));
    rtl_str_assign(SaveDir, 255, S("\020C:\\POOLRAD\\SAVE\\"));
    CfgFlagF = 1;
}

int main(void)
{

    vm_init();
    irq_start();
    pool_init_units();
    pool_main();
    rtl_Halt(0);
    return 0;
}

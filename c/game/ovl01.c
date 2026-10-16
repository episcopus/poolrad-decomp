#include "game.h"

/* ovl01:0000. Waits for a keypress or a timeout: loops until the GameClock tick count
     reaches Start plus 100 times Pause, or a key is waiting (KeyPressed), then calls
     FlushKeyboard, which does nothing (QUIRK 0899:010A: its first statement is Exit), so a
     pending key still reaches the next screen. Called by the credits (Pause 10) and the title
     sequence (Pause 5). */
void WaitKeyOrTimeout(u16 Pause)
{
  s32 Start = 0;
  s32 Limit = 0;
  Start = GameClock();
  Limit = (100 * Pause) + Start;
  do {
  } while (!(((GameClock() >= Limit)) || rtl_KeyPressed()));
  FlushKeyboard();
}

/* ovl01:0206. Shows the credits screen: two empty windows (DrawWindow) and some thirty
     name and role lines in LightGreen, cyan and yellow (DrawTextAt), then waits for a key or a
     timeout (WaitKeyOrTimeout). Called by the title sequence (ShowTitleScreen). */
void ShowCredits(void)
{
  DrawWindow(1, 1, 0x26, 3, 0, 0, S("\000"));
  DrawWindow(1, 5, 0x26, 0x17, 0, 0, S("\000"));
  DrawTextAt(5, 1, LightGreen_OVL01, S("\024scenario created by:"));
  DrawTextAt(0x1A, 1, Yellow_OVL01, S("\011tsr, inc."));
  DrawTextAt(0xF, 2, LightGreen_OVL01, S("\010jim ward"));
  DrawTextAt(2, 3, LightGreen_OVL01, S("$david cook,steve winter,mike breault"));
  DrawTextAt(1, 5, LightGreen_OVL01, S("\020game created by:"));
  DrawTextAt(0x12, 5, Yellow_OVL01, S("\024ssi special projects"));
  DrawTextAt(0xE, 6, LightCyan_OVL01, S("\013version 1.3"));
  DrawTextAt(2, 7, Yellow_OVL01, S("\014programming:"));
  DrawTextAt(0x14, 7, Yellow_OVL01, S("\010original"));
  DrawTextAt(2, 8, LightCyan_OVL01, S("\014scot bayless"));
  DrawTextAt(0x14, 8, Yellow_OVL01, S("\014programming:"));
  DrawTextAt(2, 9, LightCyan_OVL01, S("\012brad myers"));
  DrawTextAt(0x14, 9, LightCyan_OVL01, S("\013keith brors"));
  DrawTextAt(2, 0xA, LightCyan_OVL01, S("\012russ brown"));
  DrawTextAt(0x14, 0xA, LightCyan_OVL01, S("\012brad myers"));
  DrawTextAt(2, 0xB, LightCyan_OVL01, S("\011ted greer"));
  DrawTextAt(2, 0xD, Yellow_OVL01, S("\015graphic arts:"));
  DrawTextAt(0x14, 0xD, Yellow_OVL01, S("\021encounter coding:"));
  DrawTextAt(2, 0xE, LightCyan_OVL01, S("\010tom wahl"));
  DrawTextAt(0x14, 0xE, LightCyan_OVL01, S("\013paul murray"));
  DrawTextAt(2, 0xF, LightCyan_OVL01, S("\012fred butts"));
  DrawTextAt(0x14, 0xF, LightCyan_OVL01, S("\012russ brown"));
  DrawTextAt(2, 0x10, LightCyan_OVL01, S("\015darla marasco"));
  DrawTextAt(0x14, 0x10, LightCyan_OVL01, S("\015victor penman"));
  DrawTextAt(2, 0x11, LightCyan_OVL01, S("\016susan halbleib"));
  DrawTextAt(0x14, 0x11, LightCyan_OVL01, S("\014dave shelley"));
  DrawTextAt(2, 0x13, Yellow_OVL01, S("\017project manager"));
  DrawTextAt(0x14, 0x13, Yellow_OVL01, S("\012developer:"));
  DrawTextAt(2, 0x14, LightCyan_OVL01, S("\015victor penman"));
  DrawTextAt(0x14, 0x14, LightCyan_OVL01, S("\021george mac donald"));
  DrawTextAt(2, 0x16, Yellow_OVL01, S("\010testing:"));
  DrawTextAt(0xB, 0x16, LightCyan_OVL01, S("\032joel billings,steve salyer"));
  DrawTextAt(2, 0x17, LightCyan_OVL01, S("#james kucera,robert daly,rick white"));
  WaitKeyOrTimeout(0xA);
}

/* ovl01:0627. Shows the title sequence: backs up GameDir (into a String40, so a directory of
     more than 40 characters comes back cut: StrLCopy limit $28 at ovl01:0647) and clears it, loads
     the title picture (LoadPicture) and shows it (ShowPicture), waits (WaitKeyOrTimeout), then,
     when the F flag (CfgFlagF) is set, reloads, reshows, frees the title picture (ReleasePicture) and
     waits for a key or a deadline (GameClock ticks, 500 after the start). On EGA each pass of
     that wait adds Random(4) to the running sum Total (ovl01:0721..0726); when the sum passes 50000
     the palette animation runs (SetPaletteRegister with Delay) and the sum starts again from 0
     (ovl01:073E..0743). QUIRK ovl01:0729: whether the animation ever fires depends on how many
     passes the loop makes before the deadline, so on the CPU speed (about 33,000 passes at the
     mean of 1.5); it did not fire in the oracle run (whitepaper 5.8), on period hardware it is not
     known. Then calls FlushKeyboard, which does nothing (QUIRK 0899:010A), and shows the credits
     (ShowCredits). With F clear it only restores GameDir and returns. Entry point (no callers in
     the map). Side effects: screen, GameDir. */
void ShowTitleScreen(void)
{
  PT8x8Bank Pic = 0;
  s32 Total = 0;
  u8 I = 0;
  String40_RES06 DirBackup = {0};
  s32 Deadline = 0;
  u8 t1;
  Total = 0;
  Pic = 0;
  rtl_str_assign(DirBackup, 40, GameDir);
  rtl_str_assign(GameDir, 255, S("\000"));
  LoadPicture(S("\005title"), 1, 0, 0, (void *)&Pic);
  ShowPicture(0, 0, Pic);
  WaitKeyOrTimeout(5);
  if (CfgFlagF == 0) {
    rtl_str_assign(GameDir, 255, DirBackup);
  } else {
    LoadPicture(S("\005title"), 2, 0, 0, (void *)&Pic);
    rtl_str_assign(GameDir, 255, DirBackup);
    ShowPicture(0, 0, Pic);
    ReleasePicture((void *)&Pic);
    Deadline = GameClock() + 500;
    do {
      if (VideoAdapter == AdapterEga) {
        Total += rtl_Random(4);
        if (Total > 50000) {
          Total = 0;
          t1 = (u16)(rtl_Random(3) + 1);
          I = 0;
          if (I <= t1) for (;;) {
            SetPaletteRegister(1, 9);
            rtl_Delay(0x96);
            SetPaletteRegister(1, 0xB);
            rtl_Delay(0x64);
            SetPaletteRegister(1, 0xF);
            rtl_Delay(0x32);
            SetPaletteRegister(1, 0xB);
            rtl_Delay(0x64);
            SetPaletteRegister(1, 9);
            rtl_Delay(0x96);
            SetPaletteRegister(1, 1);
            if (I == t1) break;
            I++;
          }
        }
      }
    } while (!(rtl_KeyPressed() || ((GameClock() >= Deadline))));
    FlushKeyboard();
    ShowCredits();
  }
}

/* Initialisation part of unit OVL01. */
void init_OVL01(void)
{
}

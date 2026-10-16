#include "game.h"

/* ovl00:0042. Called by the heap manager when an allocation of Size bytes fails. A zero size
     returns at once with an unassigned Integer result (QUIRK ovl00:004C: jbe to ovl00:00A3, which
     loads AX from the result word at [bp-2] and returns without calling QuitGame). A non-zero
     size warns that memory is short; when OfferSaveOnHeapError is set it lets the player act through the save
     and load unit (SaveGame) and asks again until HeapErrorStop says to stop, else it announces the
     exit. Then it always ends the game through QuitGame, so that path never returns to the heap
     manager. */
s16 HeapErrorHandler(u16 Size)
{
  s16 Result = 0;
  u8 Quit = 0;
  if (Size > 0) {
    Quit = 0;
    do {
      ShowMessageLine(Yellow_OVL00, S("\034WARNING: Insufficient Memory"));
      if (OfferSaveOnHeapError) {
        SaveGame();
        Quit = HeapErrorStop;
      } else {
        Quit = 1;
        ShowMessageLine(Yellow_OVL00, S("$Insufficient Memory. Exiting Program"));
      }
    } while (!(Quit));
    QuitGame();
  }
  return Result;
}

/* Initialisation part of unit OVL00. */
void init_OVL00(void)
{
  /* Initialisation (ovl00:00AC): stores @HeapErrorHandler as the far pointer at DS:4414, the
     HeapError vector Turbo Pascal calls when an allocation fails (whitepaper 3.6). */
  HeapError = PROC_HeapErrorHandler;
}

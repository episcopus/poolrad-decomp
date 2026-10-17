#include "game.h"

/* Initialisation part of unit RES08. */
void init_RES08(void)
{
  POOL_TRACE("init");
  /* 042B:00A4. Starts the game: initialises res05, then the overlay manager on GAME.OVR; probes
     pool.cfg (retrying with 'Please insert startup disk.' until it opens) and parses POOL.CFG:
     line 1 the video choice (E: VideoAdapter 1 and EGA mode $0D, T: 2 with a smaller heap,
     else 0), line 2 the sound choice (T: 0, P: 1, else 2), lines 3-4 the game and save
     directories, line 5 the F flag. Gives the overlay buffer $18800 bytes (halting with how
     many more bytes are needed when short), halts on an overlay error, and starts the sound
     unit. Side effects: files, screen, heap, sound, halt on failure. */
  WaitForOverlayDisk();
  rtl_OvrInit(S("\010GAME.OVR"));
  do {
    rtl_assign(&CfgProbe, S("\010pool.cfg"));
    rtl_reset(&CfgProbe, 0x80);
    CfgProbeResult = rtl_IOResult();
    if (CfgProbeResult != 0) {
      rtl_write_str(&Output, S("\033Please insert startup disk."), 0), rtl_write_ln(&Output);
      CfgChar = ReadGameKey();
    }
  } while (!(CfgProbeResult == 0));
  rtl_close(&CfgProbe);
  CheckBreak = 0;
  rtl_assign(&CfgText, S("\010POOL.CFG"));
  rtl_reset_text(&CfgText);
  if (rtl_IOResult() != 0) {
    rtl_write_str(&Output, S("\027Unable to find POOL.CFG"), 0), rtl_write_ln(&Output);
    rtl_Halt(0);
  }
  rtl_read_char(&CfgText, &CfgChar), rtl_read_ln(&CfgText);
  Regs.AH = 0xF;
  rtl_Intr(0x10, &Regs);
  SavedVideoMode = Regs.AL;
  CurrentVideoMode = SavedVideoMode;
  switch ((u8)CfgChar) {
  case 'E':
  {
    VideoAdapter = 1;
    SetVideoMode(0xD);
    TextPage = 0;
    FillTextPage = 0;
    SetActivePage(TextPage);
    SetPageSegment(FillTextPage);
    break;
  }
  case 'T':
  {
    VideoAdapter = 2;
    NewHeapEnd = POOL_FARPTR((u16)(HeapWords[1] - 0x400), HeapWords[0]);
    HeapEnd = NewHeapEnd;
    SetVideoMode(9);
    break;
  }
  default:
  {
    {
      VideoAdapter = 0;
      SetVideoMode(4);
    }
  }
  }
  if (0x18800 - rtl_OvrGetBuf() <= rtl_MemAvail()) {
    rtl_OvrSetBuf(0x18800);
  } else {
    RestoreVideoMode();
    rtl_write_str(&Output, S(")Not enough memory to run game.  You need "), 0), rtl_write_int(&Output, 0x18800 - rtl_OvrGetBuf(), 0), rtl_write_str(&Output, S("\014 more bytes."), 0), rtl_write_ln(&Output);
    rtl_Halt(0);
  }
  if (OvrResult != 0) {
    RestoreVideoMode();
    rtl_write_str(&Output, S("\035Overlay error, program abort!"), 0), rtl_write_ln(&Output);
    rtl_Halt(0);
  }
  rtl_read_char(&CfgText, &CfgChar), rtl_read_ln(&CfgText);
  switch ((u8)CfgChar) {
  case 'T':
  {
    SoundMode = 0;
    break;
  }
  case 'P':
  {
    SoundMode = 1;
    break;
  }
  default:
  {
    SoundMode = 2;
  }
  }
  NewHeapEnd = POOL_FARPTR((u16)(HeapWords[1] - 0x400), HeapWords[0]);
  HeapEnd = NewHeapEnd;
  SilenceSound();
  rtl_read_str(&CfgText, GameDir, 255), rtl_read_ln(&CfgText);
  /* QUIRK 042B:032D: the original copies GameDir onto itself (System_StrLCopy with the same source
     and destination, limit $FF). Kept: the source's own assignment emits the bytes at 042B:032D. */
  rtl_str_assign(GameDir, 255, GameDir);
  rtl_read_str(&CfgText, SaveDir, 255), rtl_read_ln(&CfgText);
  /* QUIRK 042B:0358: SaveDir is copied onto itself the same way. Kept for the same reason. */
  rtl_str_assign(SaveDir, 255, SaveDir);
  rtl_read_char(&CfgText, &CfgChar), rtl_read_ln(&CfgText);
  if (CfgChar == 'F') {
    CfgFlagF = 1;
  } else {
    CfgFlagF = 0;
  }
  rtl_close(&CfgText);
}

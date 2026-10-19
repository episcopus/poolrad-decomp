#include "game.h"

/* ovl33:0004. When DebugMode (DS:49F7) is set, clears the top line, shows the three numbers there
     separated by ' , ' in Yellow, shows Message on the message line and waits for a key, then clears
     the top line again. Does nothing (not even the clear) otherwise.
     The numbers are shown with DrawTextAt(TraceLeft, TraceTop, Yellow, ...) and Message with
     ShowMessageLine(Yellow, Message) (whitepaper 5.15); both are coloured Yellow. The clear is
     ClearRect with the top line rectangle, through the video hardware VideoAdapter selects.
     The only caller is the training and rewards unit (ovl12:2233), which passes the label
     'max,cur,lost' and the three hit point bytes of a character: hp_max (at +$32 of the 285 byte
     character record) and the bytes at +$11B and +$75, so the three numbers are a character's
     maximum, current and lost hit points (whitepaper 4.2.5). The routine itself only shows the three
     bytes it is given.
     Parameters: Message the label shown on the message line; Max, Current, Lost the three byte values
     shown on the top line. Reads DebugMode. Side effects: the screen, and a wait for a key (through
     ShowMessageLine). */
void ShowDebugTrace(const u8 *Message_in, u8 Max, u8 Current, u8 Lost)
{
  POOL_TRACE("ShowDebugTrace");
  const u8 *Message = Message_in;
  u8 MaxText[256] = {0};
  u8 CurrentText[256] = {0};
  u8 LostText[256] = {0};
  u8 ts1[256];
  if (DebugMode) {
    rtl_str_int(MaxText, 255, Max, 0);
    rtl_str_int(CurrentText, 255, Current, 0);
    rtl_str_int(LostText, 255, Lost, 0);
    ClearRect(TraceLeft, TraceTop, TraceRight, TraceBottom);
    DrawTextAt(TraceLeft, TraceTop, Yellow_OVL33, rtl_str_cat(ts1, 5, (const u8 *const[]){MaxText, S("\003 , "), CurrentText, S("\003 , "), LostText}));
    ShowMessageLine(Yellow_OVL33, Message);
    ClearRect(TraceLeft, TraceTop, TraceRight, TraceBottom);
  }
}

/* Initialisation part of unit OVL33. */
void init_OVL33(void)
{
  POOL_TRACE("init");
}

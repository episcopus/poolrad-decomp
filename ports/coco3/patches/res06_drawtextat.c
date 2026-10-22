void DrawTextAt(u8 Col, u8 Row, u8 Color, const u8 *Text_in)
{
  POOL_TRACE("DrawTextAt");
  u8 Buf[41];
  u8 Len = 0;
  if ((((s16)Col > LastCol)) || (((s16)Row > LastCol))) {
    return;
  }
  Len = Text_in[0];
  if (Len == 0) {
    return;
  }
  if (Len > 40) {                          /* (step 8.9f: the engine draws the whole string in one call; what is past the 40th cell of the row is not seen) */
    Len = 40;
  }
  memcpy(Buf, Text_in, (u16)Len + 1);
  Buf[0] = Len;
  DrawTextRun(Col, Row, Color, Buf);
}

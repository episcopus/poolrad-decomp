u8 CombatantIndex(PCharacter Who)
{
  POOL_TRACE("CombatantIndex");
  const u16 *rec;
  const u16 *base;
  u16 Lo = (u16)Who;
  u16 Hi = (u16)(Who >> 16);              /* (0 when tools/narrow.py has made Who a 16 bit handle, as the high word of a banked record's farptr is) */
  u8 Count = 0;
  u8 Found = 0;
  u8 I = 0;
  /* (step 8.9e: the window of the table of records is taken once, not at every entry. Big-battle round 2026-11-14: a record is compared as two 16 bit
     words, the low one first (most differ there), not through the 32 bit compare of the library; a farptr is big-endian, the high word first) */
  Count = CombatantTable[0].Kind;
  base = (const u16 *)CombatantRecord;
  rec = base;
  do {
    I++;
    if (I == 0)
      rec = base - 2;                    /* (a count of 0: after entry 255 the original looks at entry 0, just below the table) */
    if (rec[1] == Lo && rec[0] == Hi) {
      Found = 1;
    }
    rec += 2;
  } while (!(Found || (I == Count)));
  return Found ? I : 0;
}

u8 CombatantIndex(PCharacter Who)
{
  POOL_TRACE("CombatantIndex");
  const farptr *rec;
  u8 Count = 0;
  u8 Found = 0;
  u8 I = 0;
  Count = CombatantTable[0].Kind;          /* (step 8.9e: the window of the table of records is taken once, not at every entry) */
  rec = CombatantRecord;
  do {
    I++;
    if (rec[I - 1] == Who) {
      Found = 1;
    }
  } while (!(Found || (I == Count)));
  return Found ? I : 0;
}

void SortTable(void)
{
  POOL_TRACE("SortTable");
  TSortRec *base = SortEntries;          /* (step 8.9e: pointers into the table, and the keys of the record I kept in locals; the exchanges are the original's) */
  TSortRec *pi;
  TSortRec *pj;
  TSortRec *last;
  u8 n = 0;
  u8 ki = 0;
  u8 vi = 0;
  u8 kj = 0;
  u8 vj = 0;
  u8 t;
  /* (big-battle round 2026-11-14: I and J walk as pointers, from record 1 to the count, as the for loops did: no record address computed from an index) */
  n = base[0].Val_;
  if (n <= 1) {
    return;
  }
  last = base + n;
  for (pi = base + 1; pi != last; pi++) {
    ki = pi->Key;
    vi = pi->Val_;
    for (pj = pi + 1; ; pj++) {
      kj = pj->Key;
      if (kj < ki || (kj == ki && (vj = pj->Val_) < vi && (u8)(vj & 1) <= (u8)(vi & 1))) {
        t = pi->Head; pi->Head = pj->Head; pj->Head = t;
        t = pi->Key; pi->Key = pj->Key; pj->Key = t;
        t = pi->Val_; pi->Val_ = pj->Val_; pj->Val_ = t;
        ki = pi->Key;
        vi = pi->Val_;
      }
      if (pj == last)
        break;
    }
  }
}

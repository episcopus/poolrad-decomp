void SortTable(void)
{
  POOL_TRACE("SortTable");
  TSortRec *base = SortEntries;          /* (step 8.9e: pointers into the table, and the keys of the record I kept in locals; the exchanges are the original's) */
  TSortRec *pi;
  TSortRec *pj;
  u8 I = 0;
  u8 J = 0;
  u8 n = 0;
  u8 ki = 0;
  u8 vi = 0;
  u8 kj = 0;
  u8 vj = 0;
  u8 t;
  n = base[0].Val_;
  if (n <= 1) {
    return;
  }
  for (I = 1; I <= (u8)(n - 1); I++) {
    pi = &base[I];
    ki = pi->Key;
    vi = pi->Val_;
    for (J = (u8)(I + 1); J <= n; J++) {
      pj = &base[J];
      kj = pj->Key;
      if (kj < ki || (kj == ki && (vj = pj->Val_) < vi && (u8)(vj & 1) <= (u8)(vi & 1))) {
        t = pi->Head; pi->Head = pj->Head; pj->Head = t;
        t = pi->Key; pi->Key = pj->Key; pj->Key = t;
        t = pi->Val_; pi->Val_ = pj->Val_; pj->Val_ = t;
        ki = pi->Key;
        vi = pi->Val_;
      }
    }
  }
}

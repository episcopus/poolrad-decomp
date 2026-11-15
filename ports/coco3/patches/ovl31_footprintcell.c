u8 FootprintCell(u8 Kind, u8 Index, s8 *DX, s8 *DY)
{
  POOL_TRACE("FootprintCell");
  /* big-battle round (2026-11-14): the cell's record is mapped once (the translation took Footprints' data window for DX and again for DY) */
  const TFootCell *f;
  if (Kind == 0) {
    return 0;
  }
  f = &Footprints[Kind][Index];
  (*DX) = f->DX;
  (*DY) = f->DY;
  return (*DX) >= 0 ? 1 : 0;
}

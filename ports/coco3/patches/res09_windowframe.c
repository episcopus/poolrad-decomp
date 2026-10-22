void DrawWindowFrame(s8 LeftCol, s8 TopRow, s8 RightCol, s8 BottomRow_, u8 FrameSet)
{
  POOL_TRACE("DrawWindowFrame");
  u16 TileBase = 0;
  u16 Banks_[5];
  u16 Bases_[5];
  u8 K = 0;
  s16 N = 0;
  LeftCol--;
  TopRow--;
  RightCol++;
  BottomRow_++;
  TileBase = (s16)((s16)FrameSet * TilesPerFrameSet) + FirstFrameTile;
  for (K = 0; K < 5; K++) {                /* (step 8.9f: the banks of the tiles and their first symbols, for the engine's PutTileRun) */
    Banks_[K] = (u16)TileBanks[K];
    Bases_[K] = SymbolBase[K];
  }
  PutTileRun(LeftCol, TopRow, 1, 0, (u16)((u16)TileBase + TileCorner), Banks_, Bases_);
  PutTileRun(RightCol, TopRow, 1, 0, (u16)((u16)TileBase + TileCorner), Banks_, Bases_);
  PutTileRun(LeftCol, BottomRow_, 1, 0, (u16)((u16)TileBase + TileCorner), Banks_, Bases_);
  PutTileRun(RightCol, BottomRow_, 1, 0, (u16)((u16)TileBase + TileCorner), Banks_, Bases_);
  N = (s16)((s16)RightCol - 1) - ((s16)LeftCol + 1) + 1;
  if (N > 0) {
    PutTileRun((s16)((s16)LeftCol + 1), TopRow, (u8)N, 0, (u16)((u16)TileBase + TileHorizontal), Banks_, Bases_);
    PutTileRun((s16)((s16)LeftCol + 1), BottomRow_, (u8)N, 0, (u16)((u16)TileBase + TileHorizontal), Banks_, Bases_);
  }
  N = (s16)((s16)BottomRow_ - 1) - ((s16)TopRow + 1) + 1;
  if (N > 0) {
    PutTileRun(LeftCol, (s16)((s16)TopRow + 1), (u8)N, 1, (u16)((u16)TileBase + TileVertical), Banks_, Bases_);
    PutTileRun(RightCol, (s16)((s16)TopRow + 1), (u8)N, 1, (u16)((u16)TileBase + TileVertical), Banks_, Bases_);
  }
}

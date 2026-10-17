#include "game.h"

/* ovl27:0000. Draws the 5x5 grid of 3x3-tile area blocks around map position (LeftCol, TopRow)
     into the 3D view window. The block code comes from AreaMap, minus one. Entries 1 to 9 of
     SpecialBlocks are tested for that position. Entries 1 and 2 have no case arm, so a match leaves
     the map code. Entries 3 to 9 can replace it: entry 6 always, the others only while the game
     variables named above allow. Each block is one picture drawn by DrawCellPicture, stepped by BlockCells.
     Parameters: LeftCol and TopRow are the map column and row of the top-left block.
     Callers: ShowAreaView (ovl26:0293) passes MapBaseX[AreaViewKind] plus the party column, minus 2
     (ovl26:023F), and the party row minus 2, then clamps the column to 0..39 (ovl26:025D) and the
     row to 0..31 (ovl26:027F). AnimateAreaDoors, when its byte parameter is nonzero, calls this with (17, 15)
     (ovl18:06C2), then nine times with a word from the table at DS:094D and a word from the table at
     DS:095F (index 0..8, ovl18:07C8), then with (23, 25) (ovl18:08D4). When that byte is zero those
     calls are skipped.
     Globals: reads AreaMap, SpecialBlocks and the words of GameVars^ named above. Side effects:
     the 3D view part of the screen, through DrawCellPicture. */
void DrawAreaView(s16 LeftCol, s16 TopRow)
{
  POOL_TRACE("DrawAreaView");
  s8 BaseCol = 0;
  s8 BaseRow = 0;
  u8 Special = 0;
  s8 TileCol = 0;
  s8 TileRow = 0;
  u8 Count = 0;
  u8 GridCol = 0;
  u8 GridRow = 0;
  BaseRow = 0;
  {
    if (0 <= 4) {
      GridRow = 0;
      for (;;) {
          BaseCol = 0;
          {
            if (0 <= 4) {
              GridCol = 0;
              for (;;) {
                  TileCol = GridCol + LeftCol;
                  TileRow = GridRow + TopRow;
                  Count = AreaMap[TileRow][TileCol] - 1;
                  {
                    if (1 <= SpecialCount) {
                      Special = 1;
                      for (;;) {
                          if (((TileCol == SpecialBlocks[Special].Col)) && ((TileRow == SpecialBlocks[Special].Row))) {
                            /* Entries 1 and 2 have no arm, so a position match leaves Count. Entries 3 to 9 can
                               replace it; the case labels are those entries of SpecialBlocks. */
                            switch (Special) {
                            case 3:
                            {
                              if ((*FPD(TGameVars (*), GameVars))[396] != 255) {
                                Count = SpecialBlocks[Special].Pic - 1;
                              }
                              break;
                            }
                            case 4:
                            {
                              if (((((*FPD(TGameVars (*), GameVars))[466] != 0)) || (((((*FPD(TGameVars (*), GameVars))[380] & 8)) != 0))) || (((*FPD(TGameVars (*), GameVars))[415] == 0))) {
                                Count = SpecialBlocks[Special].Pic - 1;
                              }
                              break;
                            }
                            case 5:
                            {
                              if ((((*FPD(TGameVars (*), GameVars))[416] & 2)) == 0) {
                                Count = SpecialBlocks[Special].Pic - 1;
                              }
                              break;
                            }
                            case 6:
                            {
                              Count = SpecialBlocks[Special].Pic - 1;
                              break;
                            }
                            case 7:
                            {
                              if ((((*FPD(TGameVars (*), GameVars))[416] & 1)) == 0) {
                                Count = SpecialBlocks[Special].Pic - 1;
                              }
                              break;
                            }
                            case 8:
                            case 9:
                            {
                              if ((*FPD(TGameVars (*), GameVars))[435] > 253) {
                                Count = SpecialBlocks[Special].Pic - 1;
                              }
                              break;
                            }
                            }
                          }
                        if (Special == SpecialCount) break;
                        Special++;
                      }
                    }
                  }
                  /* QUIRK ovl27:01CC: the original adds and subtracts 1 from both coordinates, which changes
                     nothing; kept for a byte-exact match. The fourth argument is always 1 here and DrawCellPicture
                     never reads it. */
                  DrawCellPicture((s16)((BaseCol + 1) - 1), (s16)((BaseRow + 1) - 1), Count, 1);
                  BaseCol += BlockCells;
                if (GridCol == 4) break;
                GridCol++;
              }
            }
          }
          BaseRow += BlockCells;
        if (GridRow == 4) break;
        GridRow++;
      }
    }
  }
}

/* ovl27:0207. Frames the three windows of the adventure screen: the 3D view on the left (15x15
     cells), the side window on the right and the text area at the bottom, with no text in them.
     Side effects: the screen (through DrawWindow, which clears each window, draws its frame
     and would centre its text on the top row). */
void DrawAdventureScreen(void)
{
  POOL_TRACE("DrawAdventureScreen");
  DrawWindow(ViewLeft, ViewTop, ViewRight, ViewBottom, PlainFrame, Black_OVL27, S("\000"));
  DrawWindow(SideLeft, SideTop, SideRight, SideBottom, PlainFrame, Black_OVL27, S("\000"));
  DrawWindow(TextLeft, TextTop, TextRight, TextBottom, PlainFrame, Black_OVL27, S("\000"));
}

/* Initialisation part of unit OVL27. */
void init_OVL27(void)
{
  POOL_TRACE("init");
  /* ovl27:0283. Empty initialisation: push bp, mov bp, sp, pop bp, retf. */
}

#include "game.h"

/* ovl10:0000. Scatters rare tiles over the plain ground (GroundPicture cells) of the combat map:
     on a d100 roll of 98 tile $1A, of 99 tile $1B, and on 100, unless WallViewMode is $A, one time in 100
     tile $1C (d10 of 1..6) or $1D (7..10). Called last by both map builders. */
void ScatterRareTiles(void)
{
  POOL_TRACE("ScatterRareTiles");
  s8 Col = 0;
  s8 Row = 0;
  u8 Roll = 0;
  s32 t1;
  {
    {
      Col = 0;
      for (;;) {
          {
            {
              Row = 0;
              for (;;) {
                  if (CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col]].Picture == GroundPicture) {
                    Roll = RollDice(1, 100);
                    t1 = Roll;
                    if ((t1 >= 1 && t1 <= 97)) {
                    } else if (t1 == 98) {
                      (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = 0x1A;
                    } else if (t1 == 99) {
                      (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = 0x1B;
                    } else if (t1 == 100) {
                      if (WallViewMode != 0xA) {
                        if (RollDice(1, 100) == 1) {
                          switch (RollDice(1, 10)) {
                          case 1:
                          case 2:
                          case 3:
                          case 4:
                          case 5:
                          case 6:
                          {
                            (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = 0x1C;
                            break;
                          }
                          case 7:
                          case 8:
                          case 9:
                          case 10:
                          {
                            (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = 0x1D;
                            break;
                          }
                          }
                        }
                      }
                    }
                  }
                if (Row == MapLastRow_OVL10) break;
                Row++;
              }
            }
          }
        if (Col == MapLastCol_OVL10) break;
        Col++;
      }
    }
  }
}

typedef struct Frame_PassageKind {
  s8 Col;
  s8 Row;
  u8 Dir;
  u8 Result;
  u8 Here;
  u8 There;
  u8 OppositeDir;
} Frame_PassageKind;

/* ovl10:012B. Nested in PassageKind: the kind of side Dir of area map cell (Col, Row): 1 a solid
       wall (DoorKindAt 0), 0 no wall (WallIdAt 0), 3 a door. Off the 16x16 map: 0 for the west and
       east sides (Dir 2 or 6) on the party's row (PartyMapRow), else 1, so a corridor the party stands in
       stays open beyond the map's edge. */
static u8 PassageKind_WallSideKind(struct Frame_PassageKind *up, s8 Col, s8 Row, u8 Dir)
{
  u8 Result = 0;
  if (((((Col >= 0)) && ((Col <= MapEdge))) && ((Row >= 0))) && ((Row <= MapEdge))) {
    if (DoorKindAt(Col, Row, Dir) == 0) {
      Result = SideWall;
    } else if (WallIdAt(Col, Row, Dir) == 0) {
      Result = SideOpen;
    } else {
      Result = SideDoor;
    }
  } else if (((Row == PartyMapRow)) && ((((Dir == DirEast)) || ((Dir == DirWest))))) {
    Result = SideOpen;
  } else {
    Result = SideWall;
  }
  return Result;
}

/* ovl10:01AD. The passage between area map cell (Col, Row) and its neighbour in direction Dir
     (0 north, 2 east, 4 south, 6 west, steps DirStepX/DirStepY): WallSideKind of this side of the cell
     OR WallSideKind of the opposite side of the neighbour: 0 open, 1 a wall, 3 a door. Called by
     BuildDungeonMap for the three drawn sides of every cell and by FindStartCell to find open
     directions for the placement groups. */
u8 PassageKind(s8 Col, s8 Row, u8 Dir)
{
  POOL_TRACE("PassageKind");
  Frame_PassageKind fr;
  memset(&fr, 0, sizeof fr);
  fr.Col = Col;
  fr.Row = Row;
  fr.Dir = Dir;
  fr.OppositeDir = (((s16)(fr.Dir + 4)) % 8);
  fr.Here = PassageKind_WallSideKind(&fr, fr.Col, fr.Row, fr.Dir);
  fr.There = PassageKind_WallSideKind(&fr, (s16)(fr.Col + DirStepX[fr.Dir]), (s16)(fr.Row + DirStepY[fr.Dir]), fr.OppositeDir);
  fr.Result = (fr.Here | fr.There);
  return fr.Result;
}

typedef struct Frame_BuildDungeonMap {
  s8 CellCol;
  s8 CellRow;
  s8 MapX;
  s8 MapY;
  u8 Unused[2];
  u8 North;
  u8 West;
  u8 East;
  u8 Unused2;
} Frame_BuildDungeonMap;

/* ovl10:0221. Stores Picture + 1 (a CombatTiles index) at the combat map cell of sub-cell
       (SubCol, SubRow) of the area cell being drawn, when that cell is on the 50x25 map. The block
       skews 6 columns right per area column and a further 5 right per area row. */
static void BuildDungeonMap_SetDungeonCell(struct Frame_BuildDungeonMap *up, u8 SubCol, u8 SubRow, u8 Picture)
{
  s8 Col = 0;
  s8 Row = 0;
  Col = (((up->CellCol * 6) + (up->CellRow * 5)) + 0x15) + SubCol;
  Row = ((up->CellRow * 5) + 0xA) + SubRow;
  if (((((Col >= 0)) && ((Col <= MapLastCol_OVL10))) && ((Row >= 0))) && ((Row <= MapLastRow_OVL10))) {
    (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = Picture + 1;
  }
}

/* ovl10:02BA. The floor of the area cell (sub-rows 2..4 of sub-columns 0..5, GroundPicture) and
       its west side: a wall is a diagonal of pictures 4, 3, $D down sub-rows 2..4, a door two
       pictures at (1, 2) and (5, 4). */
static void BuildDungeonMap_DrawFloorAndWest(struct Frame_BuildDungeonMap *up)
{
  u8 SubCol = 0;
  u8 SubRow = 0;
  {
    {
      SubRow = 2;
      for (;;) {
          {
            {
              SubCol = 0;
              for (;;) {
                  BuildDungeonMap_SetDungeonCell(up, SubCol, SubRow, GroundPicture);
                if (SubCol == 5) break;
                SubCol++;
              }
            }
          }
        if (SubRow == 4) break;
        SubRow++;
      }
    }
  }
  if (up->West == SideWall) {
    {
      {
        SubRow = 2;
        for (;;) {
            BuildDungeonMap_SetDungeonCell(up, (s16)(SubRow - 1), SubRow, 4);
            BuildDungeonMap_SetDungeonCell(up, SubRow, SubRow, 3);
            BuildDungeonMap_SetDungeonCell(up, (s16)(SubRow + 1), SubRow, 0xD);
          if (SubRow == 4) break;
          SubRow++;
        }
      }
    }
  } else if (up->West == SideDoor) {
    BuildDungeonMap_SetDungeonCell(up, 1, 2, 8);
    BuildDungeonMap_SetDungeonCell(up, 5, 4, 0);
  }
}

/* ovl10:0377. The north side of the area cell: sub-columns 3..4 of sub-rows 0..1 are a wall
       (pictures 5 over $A) when North is SideWall, else floor. */
static void BuildDungeonMap_DrawNorthSide(struct Frame_BuildDungeonMap *up)
{
  u8 Unused[2] = {0};
  if (up->North == SideWall) {
    BuildDungeonMap_SetDungeonCell(up, 3, 0, 5);
    BuildDungeonMap_SetDungeonCell(up, 4, 0, 5);
    BuildDungeonMap_SetDungeonCell(up, 3, 1, 0xA);
    BuildDungeonMap_SetDungeonCell(up, 4, 1, 0xA);
  } else {
    BuildDungeonMap_SetDungeonCell(up, 3, 0, GroundPicture);
    BuildDungeonMap_SetDungeonCell(up, 4, 0, GroundPicture);
    BuildDungeonMap_SetDungeonCell(up, 3, 1, GroundPicture);
    BuildDungeonMap_SetDungeonCell(up, 4, 1, GroundPicture);
  }
}

/* Picture table for the corner drawers, raw CombatTiles picture ids with artwork meaning not viewed
       (Purpose unknown): NorthWest top-left $0/$D/$F/5/$12/2, top-right $0/$11/5, bottom-left
       $0/$10/$A/$14/7/1/3, bottom-right $0/$17/$A/$D/$15/6. NorthEast top-left 4/$0/$F/5,
       top-right $0/$18/1/$B/3/9/5/$11/$13, bottom-left $0/$10/$A, bottom-right
       $0/4/8/$C/$E/$17/$A (ovl10:040F, 0615). The case tables below map side conditions to each position. */
/* ovl10:040F. The north-west corner of the area cell: the four pictures of sub-columns 1..2,
       sub-rows 0..1, chosen from North, West and whether the corner is open on the far side (the
       west passage of the cell to the north and the north passage of the cell to the west both
       open: OpenCorner). The four cases of K pick the top-left, top-right, bottom-left and
       bottom-right picture in turn. */
static void BuildDungeonMap_DrawNorthWestCorner(struct Frame_BuildDungeonMap *up)
{
  u8 K = 0;
  u8 TopLeft = 0;
  u8 BottomLeft = 0;
  u8 TopRight = 0;
  u8 BottomRight = 0;
  u8 OpenCorner = 0;
  if (((PassageKind(up->MapX, (s16)(up->MapY - 1), DirWest) == SideOpen)) && ((PassageKind((s16)(up->MapX - 1), up->MapY, DirNorth) == SideOpen))) {
    OpenCorner = 1;
  } else {
    OpenCorner = 0;
  }
  {
    {
      K = 1;
      for (;;) {
          switch (K) {
          case 1:
          {
            switch (up->North) {
            case SideOpen:
            {
              switch (up->West) {
              case SideOpen:
              {
                TopLeft = GroundPicture;
                break;
              }
              case SideDoor:
              {
                TopLeft = 0xD;
                break;
              }
              case SideWall:
              {
                if (OpenCorner != 0) {
                  TopLeft = 0;
                } else {
                  TopLeft = 0xD;
                }
                break;
              }
              }
              break;
            }
            case SideDoor:
            case SideWall:
            {
              if (up->West == SideOpen) {
                if (OpenCorner != 0) {
                  TopLeft = 0xF;
                } else {
                  TopLeft = 5;
                }
              } else if (OpenCorner != 0) {
                TopLeft = 0x12;
              } else {
                TopLeft = 2;
              }
              break;
            }
            }
            break;
          }
          case 2:
          {
            switch (up->North) {
            case SideOpen:
            {
              TopRight = GroundPicture;
              break;
            }
            case SideDoor:
            {
              TopRight = 0x11;
              break;
            }
            case SideWall:
            {
              TopRight = 5;
              break;
            }
            }
            break;
          }
          case 3:
          {
            switch (up->West) {
            case SideOpen:
            {
              if (up->North == SideOpen) {
                BottomLeft = GroundPicture;
              } else if (OpenCorner != 0) {
                BottomLeft = 0x10;
              } else {
                BottomLeft = 0xA;
              }
              break;
            }
            case SideDoor:
            {
              if (OpenCorner != 0) {
                BottomLeft = 0x14;
              } else {
                BottomLeft = 7;
              }
              break;
            }
            case SideWall:
            {
              if (OpenCorner != 0) {
                BottomLeft = 1;
              } else {
                BottomLeft = 3;
              }
              break;
            }
            }
            break;
          }
          case 4:
          {
            switch (up->West) {
            case SideOpen:
            case SideDoor:
            {
              switch (up->North) {
              case SideOpen:
              {
                BottomRight = GroundPicture;
                break;
              }
              case SideDoor:
              {
                BottomRight = 0x17;
                break;
              }
              case SideWall:
              {
                BottomRight = 0xA;
                break;
              }
              }
              break;
            }
            case SideWall:
            {
              switch (up->North) {
              case SideOpen:
              {
                BottomRight = 0xD;
                break;
              }
              case SideDoor:
              {
                BottomRight = 0x15;
                break;
              }
              case SideWall:
              {
                BottomRight = 6;
                break;
              }
              }
              break;
            }
            }
            break;
          }
          }
        if (K == 4) break;
        K++;
      }
    }
  }
  BuildDungeonMap_SetDungeonCell(up, 1, 0, TopLeft);
  BuildDungeonMap_SetDungeonCell(up, 2, 0, TopRight);
  BuildDungeonMap_SetDungeonCell(up, 1, 1, BottomLeft);
  BuildDungeonMap_SetDungeonCell(up, 2, 1, BottomRight);
}

/* ovl10:0615. The north-east corner of the area cell: the four pictures of sub-columns 5..6,
       sub-rows 0..1, chosen from North, East, the east passage of the cell to the north (NorthEast),
       the north passage of the cell to the east (EastNorth) and OpenCorner (both open). The four
       cases of K pick the top-left, top-right, bottom-left and bottom-right picture in turn. */
static void BuildDungeonMap_DrawNorthEastCorner(struct Frame_BuildDungeonMap *up)
{
  u8 K = 0;
  u8 TopLeft = 0;
  u8 BottomLeft = 0;
  u8 TopRight = 0;
  u8 BottomRight = 0;
  u8 OpenCorner = 0;
  u8 NorthEast = 0;
  u8 EastNorth = 0;
  NorthEast = PassageKind(up->MapX, (s16)(up->MapY - 1), DirEast);
  EastNorth = PassageKind((s16)(up->MapX + 1), up->MapY, DirNorth);
  if (((NorthEast == SideOpen)) && ((EastNorth == SideOpen))) {
    OpenCorner = 1;
  } else {
    OpenCorner = 0;
  }
  {
    {
      K = 1;
      for (;;) {
          switch (K) {
          case 1:
          {
            switch (up->North) {
            case SideOpen:
            {
              if (NorthEast == SideWall) {
                TopLeft = 4;
              } else {
                TopLeft = GroundPicture;
              }
              break;
            }
            case SideDoor:
            {
              TopLeft = 0xF;
              break;
            }
            case SideWall:
            {
              TopLeft = 5;
              break;
            }
            }
            break;
          }
          case 2:
          {
            if (up->North == SideOpen) {
              switch (NorthEast) {
              case SideOpen:
              {
                TopRight = GroundPicture;
                break;
              }
              case SideDoor:
              {
                if (((up->East == SideOpen)) && ((EastNorth != SideOpen))) {
                  TopRight = 0x18;
                } else {
                  TopRight = 1;
                }
                break;
              }
              case SideWall:
              {
                if (((up->East == SideOpen)) && ((EastNorth != SideOpen))) {
                  TopRight = 0xB;
                } else {
                  TopRight = 3;
                }
                break;
              }
              }
            } else if (up->East != SideOpen) {
              TopRight = 9;
            } else if (EastNorth != SideOpen) {
              TopRight = 5;
            } else if (OpenCorner != 0) {
              TopRight = 0x11;
            } else {
              TopRight = 0x13;
            }
            break;
          }
          case 3:
          {
            switch (up->North) {
            case SideOpen:
            {
              BottomLeft = GroundPicture;
              break;
            }
            case SideDoor:
            {
              BottomLeft = 0x10;
              break;
            }
            case SideWall:
            {
              BottomLeft = 0xA;
              break;
            }
            }
            break;
          }
          case 4:
          {
            if (up->North == SideOpen) {
              if (NorthEast == SideOpen) {
                BottomRight = GroundPicture;
              } else if (up->East != SideOpen) {
                BottomRight = 4;
              } else if (EastNorth == SideOpen) {
                BottomRight = 8;
              } else {
                BottomRight = 0xC;
              }
            } else if (up->East != SideOpen) {
              BottomRight = 0xE;
            } else if (EastNorth == SideOpen) {
              BottomRight = 0x17;
            } else {
              BottomRight = 0xA;
            }
            break;
          }
          }
        if (K == 4) break;
        K++;
      }
    }
  }
  BuildDungeonMap_SetDungeonCell(up, 5, 0, TopLeft);
  BuildDungeonMap_SetDungeonCell(up, 6, 0, TopRight);
  BuildDungeonMap_SetDungeonCell(up, 5, 1, BottomLeft);
  BuildDungeonMap_SetDungeonCell(up, 6, 1, BottomRight);
}

/* ovl10:0810. Builds the combat map of a dungeon battle (CreateCombatMap calls it when
     AreaViewKind is AreaViewDungeon): every area map cell within 6 columns and 2 rows of the party
     (PartyMapColumn, PartyMapRow) becomes a skewed block of the combat map, 6 columns right and 5 rows down per
     area column and row from the party's block at (21, 10), drawn from its west, north and east
     passages (PassageKind) by the four nested drawers below, then ScatterRareTiles. Globals: reads
     PartyMapColumn, PartyMapRow and the area map (through PassageKind), writes CombatMap^.Cells. */
void BuildDungeonMap(void)
{
  POOL_TRACE("BuildDungeonMap");
  Frame_BuildDungeonMap fr;
  memset(&fr, 0, sizeof fr);
  {
    {
      fr.CellRow = (-2);
      for (;;) {
          {
            {
              fr.CellCol = (-6);
              for (;;) {
                  fr.MapX = PartyMapColumn + fr.CellCol;
                  fr.MapY = PartyMapRow + fr.CellRow;
                  fr.West = PassageKind(fr.MapX, fr.MapY, DirWest);
                  fr.North = PassageKind(fr.MapX, fr.MapY, DirNorth);
                  fr.East = PassageKind(fr.MapX, fr.MapY, DirEast);
                  BuildDungeonMap_DrawFloorAndWest(&fr);
                  BuildDungeonMap_DrawNorthSide(&fr);
                  BuildDungeonMap_DrawNorthWestCorner(&fr);
                  BuildDungeonMap_DrawNorthEastCorner(&fr);
                if (fr.CellCol == 6) break;
                fr.CellCol++;
              }
            }
          }
        if (fr.CellRow == 2) break;
        fr.CellRow++;
      }
    }
  }
  ScatterRareTiles();
}

/* ovl10:08A4. Maps the wilderness block code (CombatBlock) through an ordered table of terrain flags.
     QUIRK ovl10:08AA..0B14: the first matching range wins for overlapping codes 3, 4 and 7 (value 3),
     $28, $29 and $2B (value 1), $7C (value 8), and $F5 (value $20). QUIRK ovl10:0B68: a code in no
     range leaves local Flags unassigned, so the returned byte is unset. QUIRK ovl10:0B6B: when
     Flag3DTiles is set and game word VarAreaDoors is $FF, that bit is replaced by FlagPlain. Called by
     the wilderness builders for every test. */
u8 BlockTerrainFlags(void)
{
  POOL_TRACE("BlockTerrainFlags");
  u8 Result = 0;
  u8 Flags = 0;
  switch (CombatBlock) {
  case 1:
  case 2:
  case 40:
  case 41:
  case 79:
  case 80:
  case 81:
  case 82:
  case 83:
  case 84:
  case 85:
  case 86:
  case 91:
  case 92:
  case 0x2B:
  case 0xF1:
  {
    Flags = 1;
    break;
  }
  case 168:
  case 169:
  case 170:
  case 171:
  case 172:
  case 173:
  case 174:
  case 175:
  case 176:
  case 177:
  {
    Flags = 0x21;
    break;
  }
  case 0xB9:
  case 188:
  case 189:
  case 190:
  case 191:
  case 192:
  {
    Flags = 0x11;
    break;
  }
  case 3:
  case 4:
  case 6:
  case 7:
  case 8:
  case 9:
  case 19:
  case 20:
  case 21:
  case 23:
  case 24:
  case 25:
  {
    Flags = 3;
    break;
  }
  case 10:
  case 11:
  case 12:
  case 13:
  case 14:
  case 15:
  case 16:
  case 17:
  case 18:
  case 0x16:
  case 26:
  case 27:
  case 28:
  case 29:
  case 30:
  case 31:
  case 32:
  case 33:
  case 34:
  case 35:
  case 36:
  case 201:
  case 202:
  case 203:
  case 204:
  case 205:
  case 206:
  case 207:
  case 208:
  {
    Flags = 2;
    break;
  }
  case 209:
  case 210:
  case 211:
  case 212:
  case 213:
  {
    Flags = 0x12;
    break;
  }
  case 0x25:
  case 0x39:
  case 0x40:
  case 154:
  case 155:
  case 156:
  case 157:
  case 158:
  case 164:
  case 165:
  case 0xB4:
  case 0xF3:
  case 239:
  case 240:
  case 0xFA:
  case 0xFC:
  {
    Flags = 4;
    break;
  }
  case 39:
  case 42:
  case 44:
  case 0x99:
  case 0x9F:
  {
    Flags = 5;
    break;
  }
  case 45:
  case 46:
  case 51:
  case 52:
  case 53:
  case 54:
  case 55:
  case 56:
  case 67:
  case 68:
  case 69:
  case 70:
  case 71:
  case 72:
  case 73:
  case 74:
  case 75:
  case 76:
  case 77:
  case 93:
  case 94:
  case 95:
  case 96:
  case 97:
  {
    Flags = 0x44;
    break;
  }
  case 181:
  case 182:
  case 183:
  case 184:
  case 0xBA:
  case 193:
  case 194:
  case 195:
  case 196:
  case 197:
  case 198:
  case 199:
  case 200:
  {
    Flags = 0x14;
    break;
  }
  case 47:
  case 48:
  case 49:
  case 50:
  case 98:
  case 99:
  case 100:
  case 101:
  case 0xF2:
  {
    Flags = 0x40;
    break;
  }
  case 0x26:
  {
    Flags = 0x41;
    break;
  }
  case 178:
  case 179:
  {
    Flags = 0x60;
    break;
  }
  case 58:
  case 59:
  case 60:
  case 65:
  case 66:
  {
    Flags = 0x48;
    break;
  }
  case 61:
  case 62:
  case 63:
  case 121:
  case 122:
  case 123:
  case 124:
  case 135:
  case 136:
  case 137:
  case 0x8B:
  case 0x8D:
  case 144:
  case 145:
  case 146:
  case 147:
  case 0x95:
  case 151:
  case 152:
  case 160:
  case 161:
  case 162:
  case 166:
  case 167:
  case 214:
  case 215:
  case 216:
  case 0xEE:
  {
    Flags = 8;
    break;
  }
  case 87:
  case 88:
  case 89:
  case 90:
  case 0xA3:
  case 0xE0:
  {
    Flags = 0x88;
    break;
  }
  case 0x7D:
  case 0x8A:
  case 0x8C:
  case 0x8E:
  case 0x8F:
  case 0x94:
  case 0x96:
  {
    Flags = 9;
    break;
  }
  case 126:
  case 127:
  case 128:
  case 129:
  case 130:
  case 131:
  case 132:
  case 133:
  case 229:
  case 230:
  case 231:
  {
    Flags = 0x28;
    break;
  }
  case 217:
  case 218:
  case 219:
  case 220:
  case 221:
  case 222:
  case 223:
  {
    Flags = 0x18;
    break;
  }
  case 0x4E:
  case 0xF5:
  case 232:
  case 233:
  {
    Flags = 0x20;
    break;
  }
  case 0x6D:
  case 244:
  case 246:
  {
    Flags = 0x80;
    break;
  }
  case 110:
  case 111:
  case 112:
  case 113:
  case 115:
  case 116:
  case 117:
  case 118:
  case 119:
  case 120:
  {
    Flags = 0x81;
    break;
  }
  case 102:
  case 103:
  case 104:
  case 105:
  case 106:
  case 107:
  case 108:
  case 0x72:
  {
    Flags = 0x90;
    break;
  }
  case 225:
  case 226:
  case 227:
  case 228:
  case 234:
  case 235:
  case 236:
  case 237:
  {
    Flags = 0xA0;
    break;
  }
  }
  if (((Flags & Flag3DTiles)) != 0) {
    if ((*FPD(TGameVars (*), GameVars))[435] == 0xFF) {
      Flags -= Flag3DTiles;
      Flags = (Flags | FlagPlain);
    }
  }
  Result = Flags;
  return Result;
}

typedef struct Frame_PlaceRiver {
  u8 Chance;
  u8 Bridges;
  s8 StartCol;
  s8 Col;
  s8 Row;
  u8 Unused;
} Frame_PlaceRiver;

/* ovl10:0B97. Puts the bridge tiles BridgeWest, BridgeEast on the river cells of (Row, Col)
       and counts the bridge rows. */
static void PlaceRiver_PlaceBridge(struct Frame_PlaceRiver *up, s8 Row, s8 Col)
{
  (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = BridgeWest;
  (*FPD(TCombatMap (*), CombatMap)).Cells[Row][(s16)(Col + 1)] = BridgeEast;
  up->Bridges++;
}

/* ovl10:0BDE. Draws a river on the wilderness combat map: with FlagRiverSometimes 35 in 100,
     with FlagRiverOften 75 in 100, otherwise never. The river runs down a diagonal, one column
     right per row, as the tile pair RiverWest, RiverEast; its top column is 34 - 5d4 moved left to
     the next column with (Col + 2) mod 7 = 0. Each row gets a bridge (PlaceBridge) on a d20 of 1,
     and the row after a bridge always (the odd count), so a bridge is two rows high; a river with
     no bridge gets one on rows 7..15. */
void PlaceRiver(void)
{
  POOL_TRACE("PlaceRiver");
  Frame_PlaceRiver fr;
  memset(&fr, 0, sizeof fr);
  fr.Chance = 0;
  fr.Bridges = 0;
  if (((BlockTerrainFlags() & FlagRiverSometimes)) != 0) {
    fr.Chance = 35;
  }
  if (((BlockTerrainFlags() & FlagRiverOften)) != 0) {
    fr.Chance = 75;
  }
  if (RollDice(1, 100) <= fr.Chance) {
    fr.Col = 34 - RollDice(5, 4);
    while ((((s16)(fr.Col + 2)) % 7) > 0) {
      fr.Col--;
    }
    fr.StartCol = fr.Col;
    {
      {
        fr.Row = 0;
        for (;;) {
            if (fr.Col <= MapLastCol_OVL10) {
              (*FPD(TCombatMap (*), CombatMap)).Cells[fr.Row][fr.Col] = RiverWest;
              (*FPD(TCombatMap (*), CombatMap)).Cells[fr.Row][(s16)(fr.Col + 1)] = RiverEast;
              if (((RollDice(1, 20) == 1)) || (fr.Bridges & 1)) {
                PlaceRiver_PlaceBridge(&fr, fr.Row, fr.Col);
              }
              fr.Col++;
            }
          if (fr.Row == MapLastRow_OVL10) break;
          fr.Row++;
        }
      }
    }
    if (fr.Bridges == 0) {
      fr.Row = (12 - RollDice(1, 9)) + 4;
      fr.Col = fr.StartCol + fr.Row;
      PlaceRiver_PlaceBridge(&fr, fr.Row, fr.Col);
      PlaceRiver_PlaceBridge(&fr, (s16)(fr.Row + 1), (s16)(fr.Col + 1));
    }
  }
}

/* ovl10:0D13. Puts two-cell features on the plain ground: for every ground cell whose northern
     neighbour is ground too, with Chance in 100 (1 by default and for FlagMany2ATiles, 3 for
     FlagSome2ATiles, 4 for FlagTallKinds4To6, 7 for FlagMostTall, none for Flag3DTiles; the last
     flag tested wins), a kind 1..6: a d10 of 1..8 halved and rounded up gives 1..4, 9 and 10 give
     d2 + 4; with FlagTallKinds4To6 the kind is d3 + 3 instead. The cell gets tile Kind + $23 and,
     for kinds below 5, the cell above tile Kind + $1F. */
void PlaceTallFeatures(void)
{
  POOL_TRACE("PlaceTallFeatures");
  u8 Unused = 0;
  u8 Chance = 0;
  u8 Kind = 0;
  s8 Col = 0;
  s8 Row = 0;
  Chance = 1;
  if (((BlockTerrainFlags() & FlagMany2ATiles)) != 0) {
    Chance = 1;
  }
  if (((BlockTerrainFlags() & FlagSome2ATiles)) != 0) {
    Chance = 3;
  }
  if (((BlockTerrainFlags() & FlagTallKinds4To6)) != 0) {
    Chance = 4;
  }
  if (((BlockTerrainFlags() & FlagMostTall)) != 0) {
    Chance = 7;
  }
  if (((BlockTerrainFlags() & Flag3DTiles)) != 0) {
    Chance = 0;
  }
  {
    {
      Col = 0;
      for (;;) {
          {
            {
              Row = 1;
              for (;;) {
                  if ((((CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col]].Picture == GroundPicture)) && ((CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[(s16)(Row - 1)][Col]].Picture == GroundPicture))) && ((RollDice(1, 100) <= Chance))) {
                    Kind = RollDice(1, 10);
                    if (Kind > 8) {
                      Kind = RollDice(1, 2) + 4;
                    } else {
                      Kind = (s16)((u16)((s16)(Kind + 1)) >> 1);
                    }
                    if (((BlockTerrainFlags() & FlagTallKinds4To6)) != 0) {
                      Kind = RollDice(1, 3) + 3;
                    }
                    (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = (Kind + FeatureBase) + 4;
                    if (Kind < 5) {
                      (*FPD(TCombatMap (*), CombatMap)).Cells[(s16)(Row - 1)][Col] = Kind + FeatureBase;
                    }
                  }
                if (Row == MapLastRow_OVL10) break;
                Row++;
              }
            }
          }
        if (Col == MapLastCol_OVL10) break;
        Col++;
      }
    }
  }
}

/* ovl10:0E9E. Scatters single-cell features over the plain ground: a d255 roll per ground cell is
     compared with five cumulative chances set from BlockTerrainFlags. Up to Chance3D: a d4 of 1..3
     gives tiles $3D..$3F, a 4 the pair $40 below $41 when the cell above is ground; then tiles
     $37..$39 (Chance37), $2A..$2D (Chance2A), $39..$3C (Chance39) and $2E..$31 (Chance2E; a 4
     becomes a d3 without FlagTallKinds4To6). Note the sums add the chances in different orders;
     the totals are the same. */
void ScatterTerrainFeatures(void)
{
  POOL_TRACE("ScatterTerrainFeatures");
  u8 Chance3D = 0;
  u8 Chance37 = 0;
  u8 Chance2A = 0;
  u8 Chance2E = 0;
  u8 Chance39 = 0;
  u8 Roll = 0;
  s8 Col = 0;
  s8 Row = 0;
  Chance3D = 0;
  Chance37 = 6;
  Chance2A = 0xF;
  Chance2E = 0x28;
  Chance39 = 0;
  if (((BlockTerrainFlags() & FlagMany2ATiles)) != 0) {
    Chance2A = 0x2D;
    Chance2E = 0xA;
  }
  if (((BlockTerrainFlags() & FlagSome2ATiles)) != 0) {
    Chance2A = 0x19;
  }
  if (((BlockTerrainFlags() & FlagTallKinds4To6)) != 0) {
    Chance2E = 5;
    Chance39 = 0x1E;
  }
  if (((BlockTerrainFlags() & Flag3DTiles)) != 0) {
    Chance3D = 0xF;
    Chance2E = 0x19;
    Chance2A = 0xA;
  }
  {
    {
      Col = 0;
      for (;;) {
          {
            {
              Row = 0;
              for (;;) {
                  if (CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col]].Picture == GroundPicture) {
                    Roll = RollDice(1, 0xFF);
                    if (Roll <= Chance3D) {
                      Roll = RollDice(1, 4);
                      if ((((Roll == 4)) && ((Row > 0))) && ((CombatTiles[(*FPD(TCombatMap (*), CombatMap)).Cells[(s16)(Row - 1)][Col]].Picture == GroundPicture))) {
                        (*FPD(TCombatMap (*), CombatMap)).Cells[(s16)(Row - 1)][Col] = 0x41;
                        (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = 0x40;
                      }
                      if (Roll < 4) {
                        (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = (Roll + FeatureBase) + 0x1D;
                      }
                    } else if (Roll <= (s16)(Chance37 + Chance3D)) {
                      (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = (RollDice(1, 3) + FeatureBase) + 0x17;
                    } else if (Roll <= (s16)((Chance2A + Chance3D) + Chance37)) {
                      (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = (RollDice(1, 4) + FeatureBase) + 0xA;
                    } else if (Roll <= (s16)(((Chance39 + Chance2A) + Chance3D) + Chance37)) {
                      Roll = (((s16)(RollDice(1, 10) - 1)) / 3) + 1;
                      (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = (Roll + FeatureBase) + 0x19;
                    } else if (Roll <= (s16)((((Chance2E + Chance39) + Chance2A) + Chance3D) + Chance37)) {
                      Roll = RollDice(1, 4);
                      if (((Roll == 4)) && ((((BlockTerrainFlags() & FlagTallKinds4To6)) == 0))) {
                        Roll = RollDice(1, 3);
                      }
                      (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = (Roll + FeatureBase) + 0xE;
                    }
                  }
                if (Row == MapLastRow_OVL10) break;
                Row++;
              }
            }
          }
        if (Col == MapLastCol_OVL10) break;
        Col++;
      }
    }
  }
}

/* ovl10:11B4. Builds the combat map of a wilderness battle: fills it with GroundTile, takes the
     area map block under the party (GameVars^ VarMapX, VarMapY, the column moved by 13 or 26 for
     AreaViewKind 3 and 4 like MapBaseX) as CombatBlock, then adds a river (PlaceRiver), the tall
     features, the scattered features and the rare tiles. */
void BuildWildernessMap(void)
{
  POOL_TRACE("BuildWildernessMap");
  s8 Col = 0;
  s8 Row = 0;
  u8 Unused[2] = {0};
  rtl_FillChar((void *)&(*FPD(TCombatMap (*), CombatMap)).Cells, 1250, GroundTile);
  Col = (*FPD(TGameVars (*), GameVars))[195];
  Row = (*FPD(TGameVars (*), GameVars))[196];
  if (AreaViewKind == 3) {
    Col += 0xD;
  }
  if (AreaViewKind == 4) {
    Col += 0x1A;
  }
  CombatBlock = AreaMap[Row][Col];
  PlaceRiver();
  PlaceTallFeatures();
  ScatterTerrainFeatures();
  ScatterRareTiles();
}

/* ovl10:1244. Loads DungCom (AreaViewKind 1) or WildCom and then RandCom at index $22, allocates
     CombatMap^ (CombatMapSize bytes), clears ShowCursor, sets CursorKind to 1 and clears the Head6
     tile gate before building the dungeon or wilderness map. QUIRK ovl10:1244: Load24x24Set's final
     argument ($18, $21 or 5) is not read by that routine. */
void CreateCombatMap(void)
{
  POOL_TRACE("CreateCombatMap");
  if (AreaViewKind == AreaViewDungeon) {
    Load24x24Set(S("\007DungCom"), 0, 0x18);
  } else {
    Load24x24Set(S("\007WildCom"), 0, 0x21);
  }
  Load24x24Set(S("\007RandCom"), 0x22, 5);
  CombatMap = rtl_getmem(CombatMapSize);
  (*FPD(TCombatMap (*), CombatMap)).ShowCursor = 0;
  (*FPD(TCombatMap (*), CombatMap)).CursorKind = 1;
  (*FPD(TCombatMap (*), CombatMap)).Head6 = 0;
  if (AreaViewKind == AreaViewDungeon) {
    BuildDungeonMap();
  } else {
    BuildWildernessMap();
  }
}

/* ovl10:12E1. Walks the party list (PartyListHead) and readies each character for the battle: calls
     RecalcCombatValues on it, allocates and zeroes its Combat record, sets NoBody for list entries past
     game word VarPartySize, gives it the icon set FacingCombatDir of the party facing (turned half
     round, + 4 mod 8, for side 1), and marks a party-side NoBody member computer-run when B84's
     low-seven-bit morale is 0 or above MaxComputerMorale. It then stores Var2Morale plus
     ComputerRun in B84; Var2Morale is the morale source [I] (ovl09:10D7 reads B84 as morale). */
void PrepareCombatants(void)
{
  POOL_TRACE("PrepareCombatants");
  PCharacter Who = 0;
  u8 Count = 0;
  u8 Morale = 0;
  Who = PartyListHead;
  Count = 0;
  while (Who != 0) {
    RecalcCombatValues(Who);
    Count++;
    (*FPD(TCharacter (*), Who)).Combat = rtl_getmem(CombatRecordSize);
    rtl_FillChar((void *)&(*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)), CombatRecordSize, 0);
    if (Count > (*FPD(TGameVars (*), GameVars2))[830]) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody = 1;
    }
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet = FacingCombatDir[(s16)((u16)PartyFacing >> 1)];
    if ((*FPD(TCharacter (*), Who)).Side == SideMonsters) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet = (((s16)((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet + 4)) % 8);
    }
    Morale = ((*FPD(TCharacter (*), Who)).B84 & MoraleMask);
    if (((((*FPD(TCharacter (*), Who)).Side == SideParty)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == 1))) && ((((Morale == 0)) || ((Morale > MaxComputerMorale))))) {
      (*FPD(TCharacter (*), Who)).B84 = (*FPD(TGameVars (*), GameVars2))[710] + ComputerRun;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
}

/* ovl10:1403. True when grid cell (Col, Row) lies beyond the 11x6 placement grid in both
     directions: Col outside 0..10 and Row outside 0..5. QUIRK ovl10:1413: a cell off the grid in one direction only answers
     False. FindStartCell uses it to end a ring or a group. */
u8 IsBeyondGrid(s8 Col, s8 Row)
{
  POOL_TRACE("IsBeyondGrid");
  u8 Result = 0;
  if (((((Col >= 0)) && ((Col < 11)))) || ((((Row >= 0)) && ((Row < 6))))) {
    Result = 0;
  } else {
    Result = 1;
  }
  return Result;
}

/* ovl10:1434. Tries to put combatant Index on grid cell (Col, Row) of placement group Group of
     the side PlacingSide, whose grid origin is (OriginCol, OriginRow) in area map steps. The cell
     must be on the grid and free in PlacementCells; the combatant's map cell is then column
     Col + 6 OriginCol + 5 OriginRow + 22, row Row + 5 OriginRow + 10 (CombatantTable[Index]). True,
     and the grid cell used, when ProbeStep finds no occupant there and a tile that is not off the
     map or blocked. QUIRK ovl10:1434: X and Y are stored before ProbeStep; if ProbeStep rejects an
     otherwise valid cell, the attempted coordinates remain in CombatantTable[Index]. */
u8 TryPlaceAt(u8 Index, s8 Col, s8 Row, s8 OriginCol, s8 OriginRow, u8 Group)
{
  POOL_TRACE("TryPlaceAt");
  u8 Result = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  if ((((((Col < 0)) || ((Row < 0))) || ((Col > GridLastCol))) || ((Row > GridLastRow))) || ((PlacementCells[PlacingSide][Group][Row][Col] == 0))) {
    Result = 0;
  } else {
    CombatantTable[Index].X = ((Col + (OriginCol * 6)) + (OriginRow * 5)) + 0x16;
    CombatantTable[Index].Y = (Row + (OriginRow * 5)) + 0xA;
    ProbeStep(CombatantRecord[Index - 1], DirNone, &Occupant, &Tile);
    if ((((Occupant == 0)) && ((Tile > 0))) && ((CombatTiles[Tile].Cost < CostBlocked_OVL10))) {
      Result = 1;
      PlacementCells[PlacingSide][Group][Row][Col] = 0;
    } else {
      Result = 0;
    }
  }
  return Result;
}

/* ovl10:1577. Finds a start cell for combatant Index on the placement grid of the side
     PlacingSide and places it there (TryPlaceAt); False when every group is used up. The search
     walks rings: phase 1 starts a ring at RingStartCol/RingStartRow of the group's facing (from
     GroupFacing) moved Ring steps backwards, phases 2 and 3 alternate Reach steps to either side.
     A ring ends after FirstRingCells of the side for the first ring, 12 cells for later ones, or
     when it leaves the grid while not IsBeyondGrid. For side 0 facing an odd direction, the first
     ring of group 0 is followed by one more skipped ring when one of the three FacingWallDirs from
     the party's area map cell is not a plain wall (PassageKind answers 1 for a wall on both sides;
     outside the dungeon view every direction counts as open). A cell beyond the grid moves on to
     the next group (up to 3) whose FacingWallDirs direction is open, with its origin one area map
     step that way. */
u8 FindStartCell(u8 Index)
{
  POOL_TRACE("FindStartCell");
  u8 Result = 0;
  u8 Placed = 0;
  u8 First = 0;
  u8 Failed = 0;
  u8 OutOfGrid = 0;
  u8 OpenSide = 0;
  u8 Phase = 0;
  u8 Dir = 0;
  u8 Facing = 0;
  u8 I = 0;
  s8 StepX = 0;
  s8 StepY = 0;
  s8 MapX = 0;
  s8 MapY = 0;
  u8 Ring = 0;
  u8 Reach = 0;
  s8 OriginCol = 0;
  s8 OriginRow = 0;
  u8 RingCells = 0;
  u8 Group = 0;
  s8 RingCol = 0;
  s8 RingRow = 0;
  s8 Col = 0;
  s8 Row = 0;
  First = 1;
  Failed = 0;
  Phase = 1;
  Ring = 0;
  Group = 0;
  OriginCol = SideOriginCol[PlacingSide];
  OriginRow = SideOriginRow[PlacingSide];
  do {
    Facing = (s16)((u16)GroupFacing[SideFacing[PlacingSide]][Group] >> 1);
    switch (Phase) {
    case 1:
    {
      StepX = DirStepX[FacingCombatDir[(((s16)(Facing + FacingOffsetBack)) % 4)]];
      StepY = DirStepY[FacingCombatDir[(((s16)(Facing + FacingOffsetBack)) % 4)]];
      RingCol = RingStartCol[(Group > 0)][Facing] + (StepX * Ring);
      RingRow = RingStartRow[(Group > 0)][Facing] + (StepY * Ring);
      Col = RingCol;
      Row = RingRow;
      Reach = 1;
      Phase = 2;
      RingCells = 1;
      break;
    }
    case 2:
    {
      StepX = DirStepX[FacingCombatDir[(((s16)(Facing + FacingOffsetRight)) % 4)]];
      StepY = DirStepY[FacingCombatDir[(((s16)(Facing + FacingOffsetRight)) % 4)]];
      Col = RingCol + (StepX * Reach);
      Row = RingRow + (StepY * Reach);
      Phase = 3;
      RingCells++;
      break;
    }
    case 3:
    {
      StepX = DirStepX[FacingCombatDir[(((s16)(Facing + FacingOffsetLeft)) % 4)]];
      StepY = DirStepY[FacingCombatDir[(((s16)(Facing + FacingOffsetLeft)) % 4)]];
      Col = RingCol + (StepX * Reach);
      Row = RingRow + (StepY * Reach);
      Phase = 2;
      Reach++;
      RingCells++;
      break;
    }
    }
    if (((((Col < 0)) || ((Row < 0))) || ((Col > GridLastCol))) || ((Row > GridLastRow))) {
      OutOfGrid = 1;
    } else {
      OutOfGrid = 0;
    }
    if (Phase > 1) {
      if ((((((OutOfGrid != 0)) && !IsBeyondGrid(Col, Row))) || ((((First != 0)) && ((RingCells >= FirstRingCells[PlacingSide]))))) || ((((First == 0)) && ((RingCells > LaterRingLastCellCount))))) {
        Ring++;
        if (((((PlacingSide == SideParty)) && (SideFacing[0] & 1)) && ((Group == 0))) && ((Ring == 1))) {
          MapX = SideOriginCol[PlacingSide] + PartyMapColumn;
          MapY = SideOriginRow[PlacingSide] + PartyMapRow;
          OpenSide = 0;
          {
            {
              I = 1;
              for (;;) {
                  Dir = FacingWallDirs[SideFacing[PlacingSide]][I];
                  if (((AreaViewKind > AreaViewDungeon)) || ((PassageKind(MapX, MapY, Dir) != SideWall))) {
                    OpenSide = 1;
                  }
                if (I == 3) break;
                I++;
              }
            }
          }
          if (OpenSide != 0) {
            Ring++;
          }
        }
        Phase = 1;
        First = 0;
      }
    }
    if (OutOfGrid != 0) {
      if (IsBeyondGrid(Col, Row)) {
        Placed = 0;
        Phase = 0;
        while (((Group < 3)) && ((Phase != 1))) {
          Group++;
          MapX = SideOriginCol[PlacingSide] + PartyMapColumn;
          MapY = SideOriginRow[PlacingSide] + PartyMapRow;
          Dir = FacingWallDirs[SideFacing[PlacingSide]][Group];
          if (((AreaViewKind > AreaViewDungeon)) || ((PassageKind(MapX, MapY, Dir) != SideWall))) {
            OriginCol = SideOriginCol[PlacingSide] + DirStepX[Dir];
            OriginRow = SideOriginRow[PlacingSide] + DirStepY[Dir];
            Ring = 0;
            Phase = 1;
          }
        }
        if (Phase != 1) {
          Failed = 1;
        }
      }
    }
    if (OutOfGrid == 0) {
      Placed = TryPlaceAt(Index, Col, Row, OriginCol, OriginRow, Group);
    }
  } while (!(Placed || ((Failed != 0))));
  if (Failed != 0) {
    Result = 0;
  } else {
    Result = 1;
  }
  return Result;
}

/* ovl10:19F5. Puts every character of the party list on the combat map. It clears CombatantTable,
     sets the two sides' grids: side 0 at the origin facing the party facing (PartyFacing), side 1
     VarStepsAhead area map steps ahead facing back; the first ring of a side holds half its
     combatants (PartySideCount/EnemySideCount, rounded up); each of the 4 groups of a side's PlacementCells is the
     shape PlacementShapes of the side's facing (group 1: shape 4). Then every character becomes
     combatant Index (CombatantRecord, CombatantTable Unk2 and Kind from CombatSize) and gets a cell
     from FindStartCell. A placed character with Flag10D 0 is taken off again and, outside a duel and
     unless NoBody, leaves a body (BodyTile, BodyTable). One that finds no cell and has NoBody is cut
     out of the list through RemoveSelectedCharacter; the list ends after the last character kept. */
void PlaceAllCombatants(void)
{
  POOL_TRACE("PlaceAllCombatants");
  s8 Col = 0;
  s8 Row = 0;
  PCharacter Prev = 0;
  PCharacter Who = 0;
  u8 Index = 0;
  u8 Group = 0;
  u8 Shape = 0;
  u8 PlacedCount = 0;
  u8 DroppedCount = 0;
  RecountCombatSides();
  DroppedCount = 0;
  PlacedCount = 0;
  {
    {
      Index = 1;
      for (;;) {
          CombatantTable[Index].Kind = 0;
        if (Index == CombatantClearLoopLast) break;
        Index++;
      }
    }
  }
  RebuildOccupancy();
  SideOriginCol[0] = 0;
  SideOriginRow[0] = 0;
  SideFacing[0] = (s16)((u16)PartyFacing >> 1);
  SideOriginCol[1] = SideOriginCol[0] + (DirStepX[PartyFacing] * (*FPD(TGameVars (*), GameVars2))[705]);
  SideOriginRow[1] = SideOriginRow[0] + (DirStepY[PartyFacing] * (*FPD(TGameVars (*), GameVars2))[705]);
  SideFacing[1] = (s16)((u16)((((s16)(PartyFacing + 4)) % 8)) >> 1);
  {
    {
      PlacingSide = SideParty;
      for (;;) {
          FirstRingCells[PlacingSide] = (s16)((u16)((s16)(SideCounts[PlacingSide] + 1)) >> 1);
        if (PlacingSide == SideMonsters) break;
        PlacingSide++;
      }
    }
  }
  {
    {
      PlacingSide = SideParty;
      for (;;) {
          {
            {
              Group = 0;
              for (;;) {
                  if (Group == 1) {
                    Shape = 4;
                  } else {
                    Shape = SideFacing[PlacingSide];
                  }
                  {
                    {
                      Row = 0;
                      for (;;) {
                          {
                            {
                              Col = 0;
                              for (;;) {
                                  if (((PlacementShapes[Shape][Row].Lo_ > Col)) || ((PlacementShapes[Shape][Row].Hi_ < Col))) {
                                    PlacementCells[PlacingSide][Group][Row][Col] = 0;
                                  } else {
                                    PlacementCells[PlacingSide][Group][Row][Col] = 1;
                                  }
                                if (Col == GridLastCol) break;
                                Col++;
                              }
                            }
                          }
                        if (Row == GridLastRow) break;
                        Row++;
                      }
                    }
                  }
                if (Group == 3) break;
                Group++;
              }
            }
          }
        if (PlacingSide == SideMonsters) break;
        PlacingSide++;
      }
    }
  }
  Index = 1;
  CombatantTable[0].Kind = 1;
  Prev = PartyListHead;
  Who = PartyListHead;
  while (Who != 0) {
    DiscardWaitingKey();
    CombatantRecord[Index - 1] = Who;
    PlacingSide = (*FPD(TCharacter (*), Who)).Side;
    CombatantTable[Index].Unk2 = Index;
    CombatantTable[Index].Kind = ((*FPD(TCharacter (*), Who)).CombatSize & 7);
    if (FindStartCell(Index)) {
      Prev = Who;
      if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
        CombatantTable[Index].Kind = 0;
        if (((DuelMode == 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == 0))) {
          Col = CombatantTable[Index].X;
          Row = CombatantTable[Index].Y;
          BodyCount++;
          BodyTable[BodyCount - 1].Tile = (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col];
          (*FPD(TCombatMap (*), CombatMap)).Cells[Row][Col] = BodyTile;
          BodyTable[BodyCount - 1].Who = Who;
          BodyTable[BodyCount - 1].X = Col;
          BodyTable[BodyCount - 1].Y = Row;
        }
      }
      RebuildOccupancy();
      Index++;
      CombatantTable[0].Kind++;
      PlacedCount++;
    } else {
      CombatantTable[Index].Kind = 0;
      if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == 1) {
        DroppedCount++;
        CombatantRecord[Index - 1] = 0;
        SelectedCharacter = Who;
        RemoveSelectedCharacter(1, 0);
        Who = Prev;
      } else {
        Prev = Who;
        Index++;
        CombatantTable[0].Kind++;
      }
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  (*FPD(TCharacter (*), Prev)).Next = 0;
}

/* ovl10:1E31 (entry 1, called by RunCombat). Starts a battle: frees the picture animation and the
     HEAD/BODY sprites, then sets HeadBankIndex and BodyBankIndex to $FF (no sprite loaded). It prints
     'A battle begins...' on row 24, resets the round state (MagicToggleOn, CombatRound, AttackRoll, the bodies,
     the lists CloudList and LootListBoundary, game word Var2BattleWord), caps Var2Morale at 100, creates the map,
     discards waiting keys, prepares combatants, discards waiting keys again, places them, and discards
     waiting keys once more. It allocates CombatAnimationPicture, centres the view on the first party character, calls
     DrawCombatScreen, runs HookBattleStart for each character, calls UpdateMonsterMorale and enters ViewModeCombat. */
void StartBattle(void)
{
  POOL_TRACE("StartBattle");
  u8 Unused[10] = {0};
  PCharacter Who = 0;
  FreeSpriteList(rtl_far(&PictureAnimation));
  ReleasePicture((void *)&HeadSpriteBank);
  ReleasePicture((void *)&BodySpriteBank);
  HeadBankIndex = 0xFF;
  BodyBankIndex = 0xFF;
  ClearPromptLine();
  DelayByGameSpeed();
  DrawTextAt(0, 0x18, 0xA, S("\022A battle begins..."));
  MagicToggleOn = 0;
  CombatRound = 0;
  AttackRoll = 0;
  BodyCount = 0;
  CloudList = 0;
  LootListBoundary = 0;
  rtl_FillChar((void *)&BodyTable, 56, 0);
  (*FPD(TGameVars (*), GameVars2))[819] = 0;
  if ((*FPD(TGameVars (*), GameVars2))[710] > 100) {
    (*FPD(TGameVars (*), GameVars2))[710] = 100;
  }
  CreateCombatMap();
  DiscardWaitingKey();
  PrepareCombatants();
  DiscardWaitingKey();
  PlaceAllCombatants();
  DiscardWaitingKey();
  AllocatePicture(0x18, 3, 4, 1, (void *)&CombatAnimationPicture);
  (*FPD(TCombatMap (*), CombatMap)).ViewX = CombatantX(PartyListHead) - 3;
  (*FPD(TCombatMap (*), CombatMap)).ViewY = CombatantY(PartyListHead) - 3;
  DrawCombatScreen();
  Who = PartyListHead;
  while (Who != 0) {
    RunAffectHooks(HookBattleStart, Who);
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  UpdateMonsterMorale();
  ViewMode = ViewModeCombat;
}

/* Initialisation part of unit OVL10. */
void init_OVL10(void)
{
  POOL_TRACE("init");
}

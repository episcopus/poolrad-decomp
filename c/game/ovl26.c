#include "game.h"

/* ovl26:0000. Draws the animated party marker onto the 5x5 map window ShowAreaView drew (through
     DrawAreaView); the wilderness map screen DrawWildernessScreen also calls it directly, after its own
     DrawAreaView. The marker cell is the party position within that window, MapBaseX[AreaViewKind]
     plus GameVars^[VarMapX] (the column) and GameVars^[VarMapY] (the row), folded with the same edge
     limits ShowAreaView clamps the window to (ovl26:0253..0285): columns and rows 0 and 1 stay at the
     edges, 2 to 41 (rows 2 to 33) become the centre cell 2, 42 (row 34) cell 3 and 43 (row 35) or more
     cell 4. PicLoad draws the marker itself (DrawIcon) with the icon set PartyFacing and the walk animation
     MarkerFrame (MarkerFrame mod 2 picks the mirrored half, MarkerFrame div 2 + 9 the picture 9 to
     11); the frame then steps to the next of its six values.
     Reads and changes: MapBaseX, AreaViewKind, GameVars^, PartyFacing, MarkerFrame. Side effect: the view
     on the screen, through DrawIcon and the display step FlushPictureChanges that drawing units call. */
void DrawPartyMarker(void)
{
  POOL_TRACE("DrawPartyMarker");
  s8 MarkerCol = 0;
  s8 MarkerRow = 0;
  MarkerCol = MapBaseX[AreaViewKind] + (*FPD(TGameVars (*), GameVars))[195];
  if (MarkerCol < CentreCell) {
  } else if (MarkerCol < Cell3Column) {
    MarkerCol = CentreCell;
  } else if (MarkerCol < Cell4Column) {
    MarkerCol = 3;
  } else {
    MarkerCol = 4;
  }
  if ((*FPD(TGameVars (*), GameVars))[196] < CentreCell) {
    MarkerRow = (*FPD(TGameVars (*), GameVars))[196];
  } else if ((*FPD(TGameVars (*), GameVars))[196] < Cell3Row) {
    MarkerRow = CentreCell;
  } else if ((*FPD(TGameVars (*), GameVars))[196] < Cell4Row) {
    MarkerRow = 3;
  } else {
    MarkerRow = 4;
  }
  DrawIcon(MarkerCol, MarkerRow, PartyFacing, (MarkerFrame % 2), (s16)((MarkerFrame / 2) + FirstMarkerPicture));
  MarkerFrame = (((s16)(MarkerFrame + 1)) % MarkerFrames);
  FlushPictureChanges();
}

typedef struct Frame_ShowAreaView {
  s8 WindowLeft;
  s8 WindowTop;
  u8 ViewKind;
} Frame_ShowAreaView;

/* ovl26:00C7. Purpose unknown beyond the mapping: turns the special view code (SpecialViewCode1) into wall
       view descriptor 2 (WallDescriptor2): codes 8 and $41 give 0, anything else $0F. This unit only reads
       SpecialViewCode1; whitepaper 5.2.1 records who sets it together with SpecialViewGate. The descriptors reach the
       screen through DrawWallDescriptors; what the values select is still open. */
static u8 ShowAreaView_WallDesc2FromCode(struct Frame_ShowAreaView *up, u8 SpecialCode)
{
  u8 Result = 0;
  switch (SpecialCode) {
  case 8:
  {
    Result = 0;
    break;
  }
  case 0x41:
  {
    Result = 0;
    break;
  }
  case 0xE8:
  {
    Result = 0xF;
    break;
  }
  default:
  {
    Result = 0xF;
  }
  }
  return Result;
}

/* ovl26:00FB. Purpose unknown beyond the mapping: turns the special view code (SpecialViewCode1) into wall
       view descriptor 3 (WallDescriptor3): code 8 gives 8, anything else 7. This unit only reads SpecialViewCode1. */
static u8 ShowAreaView_WallDesc3FromCode(struct Frame_ShowAreaView *up, u8 SpecialCode)
{
  u8 Result = 0;
  switch (SpecialCode) {
  case 8:
  {
    Result = 8;
    break;
  }
  case 0x41:
  {
    Result = 7;
    break;
  }
  case 0xE8:
  {
    Result = 7;
    break;
  }
  default:
  {
    Result = 7;
  }
  }
  return Result;
}

/* ovl26:012F. Purpose unknown beyond the mapping: turns the special view code (SpecialViewCode2) into wall
       view descriptor 4 (WallDescriptor4): code $0B gives 8, code 6 gives 1, anything else 6. This unit only
       reads SpecialViewCode2; whitepaper 5.2.1 records who sets it together with SpecialViewGate. */
static u8 ShowAreaView_WallDesc4FromCode(struct Frame_ShowAreaView *up, u8 SpecialCode)
{
  u8 Result = 0;
  switch (SpecialCode) {
  case 0xB:
  {
    Result = 8;
    break;
  }
  case 9:
  {
    Result = 6;
    break;
  }
  case 0xDB:
  {
    Result = 6;
    break;
  }
  case 6:
  {
    Result = 1;
    break;
  }
  default:
  {
    Result = 6;
  }
  }
  return Result;
}

/* ovl26:016D. Shows the current area view, the way the view dispatcher of the resident unit asks
     for it (RedrawView, view types 3 and 4). The kind is AreaViewKind, or 1 whenever the
     game variable VarForceWallView is set. Kind 1 draws the 3D wall view: it asks GeoLoad for
     the event byte of the party cell (EventByteAt; bit 7 says the cell is interior), picks the wall id
     table entry WallViewIdTable[VarWallIndexInside] or WallViewIdTable[VarWallIndexOutside] accordingly, refreshes
     descriptors 2 to 4 from the special view codes SpecialViewCode1 and SpecialViewCode2 while SpecialViewGate is set, hands all
     four descriptors to SetWallDescriptors, clears WallMapMode when VarShowWallOverlays asks, and lets DrawWallView draw
     the rest. Kinds 2 to 4 draw the 5x5 map window (DrawAreaView) around the party position minus 2,
     clamped to columns 0..39 and rows 0..31, then DrawPartyMarker. Reads: AreaViewKind, GameVars^,
     PartyMapColumn, PartyMapRow, PartyFacing, SpecialViewCode2, SpecialViewCode1, SpecialViewGate, WallViewIdTable,
     MapBaseX. Changes: WallDescriptor1 to WallDescriptor4,
     PartyCellEventByte, WallMapMode. Side effect: the view on the screen.
     QUIRK ovl26:018C: the three helpers below are nested functions of this routine: the caller
     pushes its frame as their static link (push bp at ovl26:01D7, 01E3, 01EF), which is why they
     carry 4 parameter bytes and live in the code right before this routine. */
void ShowAreaView(void)
{
  POOL_TRACE("ShowAreaView");
  Frame_ShowAreaView fr;
  memset(&fr, 0, sizeof fr);
  fr.ViewKind = AreaViewKind;
  if ((*FPD(TGameVars (*), GameVars))[230] != 0) {
    fr.ViewKind = 1;
  }
  switch (fr.ViewKind) {
  case 1:
  {
    PartyCellEventByte = EventByteAt(PartyMapColumn, PartyMapRow);
    if (PartyCellEventByte > InteriorBit) {
      WallDescriptor1 = WallViewIdTable[(*FPD(TGameVars (*), GameVars))[254]];
    } else {
      WallDescriptor1 = WallViewIdTable[(*FPD(TGameVars (*), GameVars))[253]];
    }
    if (SpecialViewGate != 0) {
      WallDescriptor2 = ShowAreaView_WallDesc2FromCode(&fr, SpecialViewCode1);
      WallDescriptor3 = ShowAreaView_WallDesc3FromCode(&fr, SpecialViewCode1);
      WallDescriptor4 = ShowAreaView_WallDesc4FromCode(&fr, SpecialViewCode2);
    }
    SetWallDescriptors(WallDescriptor1, WallDescriptor2, WallDescriptor3, WallDescriptor4);
    if ((*FPD(TGameVars (*), GameVars))[251] != 0) {
      WallMapMode = 0;
    }
    DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
    break;
  }
  case 2:
  case 3:
  case 4:
  {
    fr.WindowLeft = (MapBaseX[fr.ViewKind] + (*FPD(TGameVars (*), GameVars))[195]) - 2;
    if (fr.WindowLeft < 0) {
      fr.WindowLeft = 0;
    }
    if (fr.WindowLeft > MaxWindowLeft) {
      fr.WindowLeft = MaxWindowLeft;
    }
    fr.WindowTop = (*FPD(TGameVars (*), GameVars))[196] - 2;
    if (fr.WindowTop < 0) {
      fr.WindowTop = 0;
    }
    if (fr.WindowTop > MaxWindowTop) {
      fr.WindowTop = MaxWindowTop;
    }
    DrawAreaView(fr.WindowLeft, fr.WindowTop);
    DrawPartyMarker();
    break;
  }
  }
}

/* Initialisation part of unit OVL26. */
void init_OVL26(void)
{
  POOL_TRACE("init");
  /* ovl26:02A0. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
     (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the area view unit runs no code
     at start-up. */
}

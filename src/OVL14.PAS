unit OVL14;
{ Wilderness travel (whitepaper 5.3): the area-map movement keys and icon sets, and the
  Bash/Pick/Knock/Exit command menu, whose Pick and Knock use the party members' thief and
  magic-user levels and memorized Knock spell (the party list is a list of TCharacter). }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS;
procedure ClearIconBits(Col, Row, Icon: ShortInt);
procedure SetIconBits(Col, Row, Icon: ShortInt);
function AnyMemberHasClassLevel(Which: ShortInt): Byte;
function DoBash: Byte;
function DoPick: Byte;
function FindSpellSlot(Code: Byte; Rec: PCharacter): Byte;
function FindMemberWithSpell(Code: Byte): PCharacter;
function DoKnock: Boolean;
procedure ClampPartyPosition;
procedure MoveParty;
procedure CheckMapCell;
procedure DoWildernessMenu;
function HandleWildernessKeys: Char;
implementation
uses OVL29, RES03, RES05, RES06, RES07, OVL20, OVL24, OVL25, OVL19, OVL15, RES12, RES09, OVL32, OVL28;

{ ovl14:0000. Clears the icon set's bit pair in the event byte of the area-map cell
  (Col, Row): bits 6-7 for icon 6, 4-5 for 4, 2-3 for 2, 0-1 for 0. Called by DoWildernessMenu
  on the Exit path with the party cell and icon set. }
procedure ClearIconBits(Col, Row, Icon: ShortInt);
begin
  case Icon of
    6:
      GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $3F;
    4:
      GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $CF;
    2:
      GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $F3;
    0:
      GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $FC;
  end;
end;
{ ovl14:0109. Sets the icon set's bit in the map cell byte (Col, Row): bit 6 for icon 6,
  4 for 4, 2 for 2, 0 for 0, clearing the pair's other bit; out-of-map cells do
  nothing. The counterpart of ClearIconBits. Called by the Bash and Pick commands. }
procedure SetIconBits(Col, Row, Icon: ShortInt);
begin
  if (Col < 0) or (Col > $F) or (Row < 0) or (Row > $F) then
  begin
    { out of the map: nothing to set }
  end
  else
    case Icon of
      6:
        GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $3F or $40;
      4:
        GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $CF or $10;
      2:
        GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $F3 or $04;
      0:
        GeoCells^.Cells[Row, Col] := GeoCells^.Cells[Row, Col] and $FC or $01;
    end;
end;
{ ovl14:0236. Returns 1 when any character of the PartyListHead list has a class level above 0 in
  ClassLevels[Which] (+$96+Which), else 0. The Bash/Pick/Knock menu (DoWildernessMenu) offers Pick when flag 6 is
  found and Knock when flag 5 is found. }
function AnyMemberHasClassLevel(Which: ShortInt): Byte;
var
  Rec: PCharacter;
  Found: Byte;
begin
  Found := 0;
  Rec := Pointer(PartyListHead);
  while (Rec <> nil) and (Found = 0) do
  begin
    if Rec^.ClassLevels[Which] > 0 then
      Found := 1;
    Rec := Rec^.Next;
  end;
  AnyMemberHasClassLevel := Found;
end;
{ ovl14:0294. The Bash command (the B key): walks the PartyListHead records and tries to force
  the first one whose lock answers the DoorKindAt cell test with 3 (or another value,
  below): each lock type wants its own 1d6/1d8 roll (RollDice), setting Done on success
  and clearing DoorMenuFlags[0] on some failures. On success it sets the icon bits like Pick
  and returns 1, else 0. }
function DoBash: Byte;
var
  Rec: PCharacter;
  Done: Byte;
begin
  Done := 0;
  Rec := Pointer(PartyListHead);
  while (Rec <> nil) and (Done = 0) do
  begin
    with Rec^ do
    begin
      if DoorKindAt(PartyMapColumn, PartyMapRow, PartyFacing) = 3 then
        case Strength of
          $12:
            case StrengthPercent of
              $5B..$63:
                if RollDice(1, 6) = 1 then
                  Done := 1;
              $64:
                if RollDice(1, 6) <= 2 then
                  Done := 1;
            else
              DoorMenuFlags[0] := 0;
            end;
          $13, $14:
            if RollDice(1, 6) <= 3 then
              Done := 1;
          $15, $16:
            if RollDice(1, 6) <= 4 then
              Done := 1;
          $17:
            if RollDice(1, 6) <= 5 then
              Done := 1;
          $18:
            if RollDice(1, 8) <= 7 then
              Done := 1;
          $19:
            Done := 1;
        else
          DoorMenuFlags[0] := 0;
        end
      else
        case Strength of
          $03..$07:
            if RollDice(1, 6) = 1 then
              Done := 1;
          $08..$0F:
            if RollDice(1, 6) <= 2 then
              Done := 1;
          $10..$11:
            if RollDice(1, 6) <= 3 then
              Done := 1;
          $12:
            case StrengthPercent of
              0..$32:
                if RollDice(1, 6) <= 3 then
                  Done := 1;
              $33..$63:
                if RollDice(1, 6) <= 4 then
                  Done := 1;
              $64:
                if RollDice(1, 6) <= 5 then
                  Done := 1;
            end;
        end;
    end;
    Rec := Rec^.Next;
  end;
  if Done <> 0 then
  begin
    SetIconBits(PartyMapColumn, PartyMapRow, PartyFacing);
    SetIconBits(PartyMapColumn + DirStepX[PartyFacing], PartyMapRow + DirStepY[PartyFacing], (PartyFacing + 4) mod 8);
  end;
  DoBash := Done;
end;
{ ovl14:04DF. The Pick command (the P key): rolls 1d100 (RollDice) against each
  PartyListHead record's +$78 byte and requires its +$10C byte clear; on the first success it
  sets the icon bits at the party cell and ahead of it (the facing cell uses the icon
  set +4 mod 8), clears the DoorMenuFlags[1] menu flag, and returns 1, else 0. }
function DoPick: Byte;
var
  Rec: PCharacter;
  Done: Byte;
begin
  Done := 0;
  Rec := Pointer(PartyListHead);
  while (Rec <> nil) and (Done = 0) do
  begin
    with Rec^ do
    begin
      if RollDice(1, $64) <= ThiefSkills[2] then
        if Status = 0 then
          Done := 1;
    end;
    Rec := Rec^.Next;
  end;
  DoorMenuFlags[1] := 0;
  if Done <> 0 then
  begin
    SetIconBits(PartyMapColumn, PartyMapRow, PartyFacing);
    SetIconBits(PartyMapColumn + DirStepX[PartyFacing], PartyMapRow + DirStepY[PartyFacing], (PartyFacing + 4) mod 8);
  end;
  DoPick := Done;
end;
{ ovl14:05AB. Scans the 21 memorized spell slots (Spells, +$17) of Rec for the spell Code: returns the slot index, or $FF
  when no slot holds it. }
function FindSpellSlot(Code: Byte; Rec: PCharacter): Byte;
var
  Slot: Byte;
begin
  Slot := 0;
  while (Slot <= $14) and (Rec^.Spells[Slot] <> Code) do
    Inc(Slot);
  if Slot <= $14 then
    FindSpellSlot := Slot
  else
    FindSpellSlot := $FF;
end;
{ ovl14:05EE. Returns the first character of the PartyListHead list that has the spell Code memorized,
  or nil when none does. }
function FindMemberWithSpell(Code: Byte): PCharacter;
var
  Rec: PCharacter;
begin
  Rec := Pointer(PartyListHead);
  while (Rec <> nil) and (FindSpellSlot(Code, Rec) = $FF) do
    Rec := Rec^.Next;
  FindMemberWithSpell := Rec;
end;
const
  KnockSpell = $1F;              { spell 31 of SpellTable, Knock: DoKnock clears its memorized slot }
{ ovl14:0648. The Knock command (the K key): clears the KnockSpell slot of the first
  record holding it and returns True, or returns False when no record holds it. }
function DoKnock: Boolean;
var
  Rec: PCharacter;
begin
  Rec := FindMemberWithSpell(KnockSpell);
  if Rec <> nil then
  begin
    Rec^.Spells[FindSpellSlot(KnockSpell, Rec)] := 0;
    DoKnock := True;
  end
  else
    DoKnock := False;
end;
{ ovl14:068D. Steps the party one cell in the current icon set's direction when
  DoorKindAt allows it, clamping the result into the 16x16 area map: each clamped
  coordinate is written back and the edge flag GameVars2^[725] (+$5AA) is set. Called
  by the movement driver HandleWildernessKeys. The direction tables DirStepX/DirStepY are indexed
  by the icon set. }
procedure ClampPartyPosition;
var
  Col, Row: Integer;
  Icon: Integer;
begin
  Col := PartyMapColumn;
  Row := PartyMapRow;
  Icon := PartyFacing;
  GameVars2^[725] := 0;
  if DoorKindAt(Col, Row, Icon) <> 0 then
  begin
    Inc(Col, DirStepX[Icon]);
    Inc(Row, DirStepY[Icon]);
    if Col > $F then
    begin
      PartyMapColumn := $F;
      GameVars2^[725] := 1;
    end;
    if Col < 0 then
    begin
      PartyMapColumn := 0;
      GameVars2^[725] := 1;
    end;
    if Row > $F then
    begin
      PartyMapRow := $F;
      GameVars2^[725] := 1;
    end;
    if Row < 0 then
    begin
      PartyMapRow := 0;
      GameVars2^[725] := 1;
    end;
  end;
end;
{ ovl14:073B. Moves the party one cell in the current icon set's direction, wrapping
  the 16x16 area map ($F steps to 0, 0 steps to $F), then refreshes the cell bytes
  PartyCellWallId (through WallIdAt) and PartyCellEventByte (through EventByteAt), resets the DoorMenuFlags..DoorMenuFlags[2]
  menu flags to 1, and steps
  the sound through AdvanceGameClock (mode 2 when GameVars2^[714] has bit 0, else mode 1).
  Called by DoWildernessMenu. }
procedure MoveParty;
begin
  PlaySound(SoundStep);
  Inc(PartyMapColumn, DirStepX[PartyFacing]);
  Inc(PartyMapRow, DirStepY[PartyFacing]);
  if PartyMapColumn < 0 then
    PartyMapColumn := $F;
  if PartyMapColumn > $F then
    PartyMapColumn := 0;
  if PartyMapRow < 0 then
    PartyMapRow := $F;
  if PartyMapRow > $F then
    PartyMapRow := 0;
  PartyCellWallId := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
  FillChar(DoorMenuFlags, 3, 1);
  PartyCellEventByte := EventByteAt(PartyMapColumn, PartyMapRow);
  if GameVars2^[714] and 1 > 0 then
    AdvanceGameClock(1, 2)
  else
    AdvanceGameClock(1, 1);
end;
{ ovl14:0818. Checks the area-map block ahead of the party: steps the GameVars area-map
  position by the icon set's direction, clamps it (columns 0..$F, rows 0..$23), and
  reads that cell of AreaMap. N ($4E) and the impassable ranges pass through silently;
  the river codes ($66..$6C, $72) either print the stench message (when GameVars^[VarRiverGate]
  is 0) or move there; anything else moves there with a sound. Called by DoWildernessMenu. }
procedure CheckMapCell;
var
  MapCol, GridCol, GridRow: ShortInt;
begin
  GridCol := GameVars^[VarMapX] + DirStepX[PartyFacing];
  GridRow := GameVars^[VarMapY] + DirStepY[PartyFacing];
  if GridCol < 0 then
    GridCol := 0;
  if GridCol > $F then
    GridCol := $F;
  if GridRow < 0 then
    GridRow := 0;
  if GridRow > $23 then
    GridRow := $23;
  MapCol := GridCol + MapBaseX[AreaViewKind];
  case AreaMap[GridRow, MapCol] of
    $4E, $7E..$80, $82..$84, $A8..$AC, $AE..$B3, $BC, $DD..$DE, $E1..$E9, $F5:
      ;
    $66..$6C, $72:
      if GameVars^[VarRiverGate] = 0 then
        FlashMessageLine('The river''s stench drives you back.', $E)
      else
      begin
        GameVars^[VarMapX] := GridCol;
        GameVars^[VarMapY] := GridRow;
        AdvanceGameClock($C, 3);
      end;
  else
    GameVars^[VarMapX] := GridCol;
    GameVars^[VarMapY] := GridRow;
    AdvanceGameClock($C, 3);
  end;
end;
{ ovl14:0989. The wilderness key driver (called by RunWilderness (ovl03:32F8)): in the 3D view it
  reads menu and movement keys through ReadPromptChoice and dispatches them (A/C/V/E/S/L
  menu keys, H/M/P/K movement with the icon sets, anything else through UpdateSelectedCharacter),
  otherwise it loads the ICON pictures for map pages 2..4 and runs a smaller key loop;
  either loop repeats through DrawLocationLine until Redraw is set, then it tidies the
  window and returns the key. Also clears GameVars2^[713] on entry. }
function HandleWildernessKeys: Char;
var
  Redraw: Byte;
  Key: Char;
  KeyFlag: Byte;
  SpareBuf: String[40];   { 41 frame-filling bytes, never read; purpose unknown }
  ViewFlag: Byte;         { flag ViewSelectedCharacter (View) takes }
  SpareLong: LongInt;     { 4 frame-filling bytes, never read; purpose unknown }
begin
  GameVars2^[713] := 0;
  case AreaViewKind of
    1:
      begin
        Redraw := 0;
    repeat
      Key := ReadPromptChoice('', WildernessPromptWithArea, $D, $A, $F, 1, 0, KeyFlag);
      if KeyFlag = 0 then
        case Key of
          'A':
            if GameVars^[VarShowWallOverlays] = 0 then
            begin
              WallMapMode := Ord(WallMapMode = 0);
              DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
            end
            else
              FlashMessageLine('Not Here', $E);
          'C':
            if SelectedCharacter^.Status = 0 then
              CastSpells;
          'V':
            ViewSelectedCharacter(ViewFlag);
          'E':
            Redraw := 1;
          'S':
            GameVars2^[714] := GameVars2^[714] xor 1;
          'L':
            begin
              GameVars2^[714] := GameVars2^[714] or 2;
              AdvanceGameClock(1, 2);
              EclPC := EclSearchEntry;
              Redraw := 1;
            end;
        end
      else
        case Key of
          'H':
            begin
              ClampPartyPosition;
              Redraw := 1;
            end;
          'P':
            begin
              PartyFacing := (PartyFacing + 4) mod 8;
              PartyCellWallId := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
              DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
            end;
          'K':
            begin
              PartyFacing := (PartyFacing + 6) mod 8;
              PlaySound(SoundStep);
              PartyCellWallId := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
              DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
            end;
          'M':
            begin
              PartyFacing := (PartyFacing + 2) mod 8;
              PlaySound(SoundStep);
              PartyCellWallId := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
              DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
            end;
        else
          UpdateSelectedCharacter(Key);
          DrawPartyRoster(SelectedCharacter);
        end;
      DrawLocationLine;
    until Redraw <> 0;
  end;
  2..4:
  begin
    if PreviousAreaViewKind < 2 then
    begin
      LoadPictureSlot('ICON', 0, 9);
      LoadPictureSlot('ICON', 1, $A);
      LoadPictureSlot('ICON', 2, $B);
      DrawWildernessScreen;
    end;
    Redraw := 0;
    repeat
      Key := ReadPromptChoice('', WildernessPromptNoArea, $D, $A, $F, 1, 0, KeyFlag);
      if KeyFlag = 0 then
        case Key of
          'C':
            CastSpells;
          'V':
            ViewSelectedCharacter(ViewFlag);
          'E':
            Redraw := 1;
          'S':
            GameVars2^[714] := GameVars2^[714] xor 1;
          'L':
            begin
              GameVars2^[714] := GameVars2^[714] or 2;
              AdvanceGameClock(1, 2);
              EclPC := EclSearchEntry;
              Redraw := 1;
            end;
        end
      else
      begin
        Redraw := 1;
        case Key of
          'H':
            PartyFacing := 0;
          'M':
            PartyFacing := 2;
          'P':
            PartyFacing := 4;
          'K':
            PartyFacing := 6;
        else
          UpdateSelectedCharacter(Key);
          DrawPartyRoster(SelectedCharacter);
          Redraw := 0;
        end;
      end;
      DrawLocationLine;
    until Redraw <> 0;
    end;
  end;
  PreviousAreaViewKind := AreaViewKind;
  if EclWindowCleared = 0 then
  begin
    ClearWindow(1, $11, $26, $16);
    EclWindowCleared := 1;
  end;
  HandleWildernessKeys := Key;
end;
{ ovl14:0D6D. The wilderness command menu (called by RunWilderness (ovl03:32F8)): in the 3D view it
  builds the Bash/Pick/Knock/Exit menu from the DoorMenuFlags/DoorMenuFlags[1]/DoorMenuFlags[2] flags and the
  record flag checks, prompts through ReadPromptChoice and dispatches the key: in the DoorKindAt = 2
  arm 'B' calls DoBash, 'P' calls DoPick (ovl14:0ED6) and 'K' calls DoKnock, with Knock
  offered when FindMemberWithSpell($1F) finds a record (ovl14:0E14), while in the = 3 arm 'B'
  calls DoBash and 'K' calls DoKnock, with Knock offered when AnyMemberHasClassLevel(5) is set
  (ovl14:0F53), but 'P' only clears the Pick flag (mov DoorMenuFlags[1],0 at ovl14:1015, no DoPick
  call); on the map pages it steps the area map (CheckMapCell on pages 2..4);
  on success it moves the party (MoveParty), then always tidies the sprite banks. }
procedure DoWildernessMenu;
var
  Done: Byte;
  MenuFlag: Byte;
  Menu: String[40];
  Key2: Char;
begin
  Done := 0;
  case AreaViewKind of
    1:
    begin
      if GameVars2^[713] < $FF then
      begin
      case DoorKindAt(PartyMapColumn, PartyMapRow, PartyFacing) of
        1:
          Done := 1;
        2:
        begin
          Menu[0] := #0;
          if DoorMenuFlags[0] <> 0 then
            Menu := 'Bash';
          if (DoorMenuFlags[1] <> 0) and (AnyMemberHasClassLevel(6) <> 0) then
            Menu := Menu + ' Pick';
          if (DoorMenuFlags[2] <> 0) and (FindMemberWithSpell(KnockSpell) <> nil) then
            Menu := Menu + ' Knock';
          Menu := Menu + ' Exit';
          if Menu = ' Exit' then
            ClearIconBits(PartyMapColumn, PartyMapRow, PartyFacing)
          else
          begin
            Key2 := ReadPromptChoice('Locked. ', Menu, $D, $A, $F, 0, 0, MenuFlag);
            case Key2 of
              'B':
                Done := DoBash;
              'P':
                Done := DoPick;
              'K':
                Done := Ord(DoKnock);
            end;
          end;
        end;
        3:
        begin
          Menu[0] := #0;
          if DoorMenuFlags[0] <> 0 then
            Menu := 'Bash';
          if (DoorMenuFlags[1] <> 0) and (AnyMemberHasClassLevel(6) <> 0) then
            Menu := Menu + ' Pick';
          if (DoorMenuFlags[2] <> 0) and (AnyMemberHasClassLevel(5) <> 0) then
            Menu := Menu + ' Knock';
          Menu := Menu + ' Exit';
          if Menu = ' Exit' then
            ClearIconBits(PartyMapColumn, PartyMapRow, PartyFacing)
          else
          begin
            Key2 := ReadPromptChoice('Locked. ', Menu, $D, $A, $F, 0, 0, MenuFlag);
            case Key2 of
              'B':
                Done := DoBash;
              'P':
                DoorMenuFlags[1] := 0;
              'K':
                Done := Ord(DoKnock);
            end;
          end;
        end;
      end;
      if Done <> 0 then
        MoveParty
      else
        PlaySound(SoundNoAction);
      DrawLocationLine;
    end
    else
      GameVars2^[713] := 0;
  end;
  2..4:
  begin
    if GameVars2^[713] < $FF then
    begin
      CheckMapCell;
      DrawLocationLine;
    end
    else
      GameVars2^[713] := 0;
  end;
  end;
  FreeSpriteList(@PictureAnimation);
  ReleasePicture(HeadSpriteBank);
  ReleasePicture(BodySpriteBank);
  HeadBankIndex := $FF;
  BodyBankIndex := $FF;
end;

{ ovl14:10A7. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
  (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the wilderness unit runs no code
  at start-up. }
begin
end.

unit OVL14;
{ Wilderness travel (whitepaper 5.3): the area-map movement keys and icon sets, the
  Bash/Pick/Knock/Exit command menu, and the code-table records behind Knock. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
type
  { A heap record chained through Next. Each one holds a 21-byte code table the trio
    below scans; the records' owner is not known yet (the loader only clears the head,
    nothing in this unit allocates them). }
  PCodeRec = ^TCodeRec;
  TCodeRec = record
    Unknown00: array[0..$0F] of Byte; { +$00..+$0F: not read here }
    LockType: Byte;                   { +$10: the Bash/Pick lock kind }
    Unknown11: array[$11..$15] of Byte; { +$11..+$15: not read here }
    Strength: Byte;                   { +$16: 0..100 value gating the Bash rolls }
    Codes: array[0..$14] of Byte;     { +$17..+$2B: scanned for the wanted code }
    Unknown2C: array[$2C..$77] of Byte; { +$2C..+$77: not read here }
    PickThreshold: Byte;              { +$78: the 1d100 Pick roll must not exceed it }
    Unknown79: array[$79..$95] of Byte; { +$79..+$95: not read here }
    Flags: array[0..13] of ShortInt;  { +$96..+$A3: positive gates a menu item (5 Knock, 6 Pick);
                                        signed: ovl14:026A compares with jle; extent uncertain }
    UnknownA4: array[$A4..$103] of Byte; { +$A4..+$103: not read here }
    Next: PCodeRec;                   { +$104: next record, nil ends the list }
    Unknown108: array[$108..$10B] of Byte; { +$108..+$10B: not read here }
    PickFlag: Byte;                   { +$10C: Pick proceeds only when it is 0 }
  end;
procedure ClearIconBits(Col, Row, Icon: ShortInt);
procedure SetIconBits(Col, Row, Icon: ShortInt);
function HasRecFlag(Which: ShortInt): Byte;
function DoBash: Byte;
function DoPick: Byte;
function FindCodeSlot(Code: Byte; Rec: PCodeRec): Byte;
function FindCodeRecord(Code: Byte): PCodeRec;
function DoKnock: Boolean;
procedure ClampPartyPosition;
procedure MoveParty;
procedure CheckMapCell;
function HandleWildernessKeys: Char;
procedure DoWildernessMenu;
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
{ ovl14:0236. Returns 1 when any record of the ds5D96 list has a positive byte at
  +$96+Which, else 0. The Bash/Pick/Knock menu (DoWildernessMenu) offers Pick when flag 6 is
  found and Knock when flag 5 is found. }
function HasRecFlag(Which: ShortInt): Byte;
var
  Rec: PCodeRec;
  Found: Byte;
begin
  Found := 0;
  Rec := Pointer(ds5D96);
  while (Rec <> nil) and (Found = 0) do
  begin
    if Rec^.Flags[Which] > 0 then
      Found := 1;
    Rec := Rec^.Next;
  end;
  HasRecFlag := Found;
end;
{ ovl14:0294. The Bash command (the B key): walks the ds5D96 records and tries to force
  the first one whose lock answers the DoorKindAt cell test with 3 (or another value,
  below): each lock type wants its own 1d6/1d8 roll (RollDice), setting Done on success
  and clearing ds6DDE[0] on some failures. On success it sets the icon bits like Pick
  and returns 1, else 0. }
function DoBash: Byte;
var
  Rec: PCodeRec;
  Done: Byte;
begin
  Done := 0;
  Rec := Pointer(ds5D96);
  while (Rec <> nil) and (Done = 0) do
  begin
    with Rec^ do
    begin
      if DoorKindAt(PartyMapColumn, PartyMapRow, PartyFacing) = 3 then
        case LockType of
          $12:
            case Strength of
              $5B..$63:
                if RollDice(1, 6) = 1 then
                  Done := 1;
              $64:
                if RollDice(1, 6) <= 2 then
                  Done := 1;
            else
              ds6DDE[0] := 0;
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
          ds6DDE[0] := 0;
        end
      else
        case LockType of
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
            case Strength of
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
  ds5D96 record's +$78 byte and requires its +$10C byte clear; on the first success it
  sets the icon bits at the party cell and ahead of it (the facing cell uses the icon
  set +4 mod 8), clears the ds6DDF menu flag, and returns 1, else 0. }
function DoPick: Byte;
var
  Rec: PCodeRec;
  Done: Byte;
begin
  Done := 0;
  Rec := Pointer(ds5D96);
  while (Rec <> nil) and (Done = 0) do
  begin
    with Rec^ do
    begin
      if RollDice(1, $64) <= PickThreshold then
        if PickFlag = 0 then
          Done := 1;
    end;
    Rec := Rec^.Next;
  end;
  ds6DDF := 0;
  if Done <> 0 then
  begin
    SetIconBits(PartyMapColumn, PartyMapRow, PartyFacing);
    SetIconBits(PartyMapColumn + DirStepX[PartyFacing], PartyMapRow + DirStepY[PartyFacing], (PartyFacing + 4) mod 8);
  end;
  DoPick := Done;
end;
{ ovl14:05AB. Scans Rec's 21-byte code table for Code: returns the slot index, or $FF
  when no slot holds it. }
function FindCodeSlot(Code: Byte; Rec: PCodeRec): Byte;
var
  Slot: Byte;
begin
  Slot := 0;
  while (Slot <= $14) and (Rec^.Codes[Slot] <> Code) do
    Inc(Slot);
  if Slot <= $14 then
    FindCodeSlot := Slot
  else
    FindCodeSlot := $FF;
end;
{ ovl14:05EE. Returns the first record of the ds5D96 list whose code table holds Code,
  or nil when none does. }
function FindCodeRecord(Code: Byte): PCodeRec;
var
  Rec: PCodeRec;
begin
  Rec := Pointer(ds5D96);
  while (Rec <> nil) and (FindCodeSlot(Code, Rec) = $FF) do
    Rec := Rec^.Next;
  FindCodeRecord := Rec;
end;
const
  KnockCode = $1F;              { the code table slot Knock clears }
{ ovl14:0648. The Knock command (the K key): clears the KnockCode slot of the first
  record holding it and returns True, or returns False when no record holds it. }
function DoKnock: Boolean;
var
  Rec: PCodeRec;
begin
  Rec := FindCodeRecord(KnockCode);
  if Rec <> nil then
  begin
    Rec^.Codes[FindCodeSlot(KnockCode, Rec)] := 0;
    DoKnock := True;
  end
  else
    DoKnock := False;
end;
{ ovl14:068D. Steps the party one cell in the current icon set's direction when
  DoorKindAt allows it, clamping the result into the 16x16 area map: each clamped
  coordinate is written back and the edge flag ds49D6^[725] (+$5AA) is set. Called
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
  ds49D6^[725] := 0;
  if DoorKindAt(Col, Row, Icon) <> 0 then
  begin
    Inc(Col, DirStepX[Icon]);
    Inc(Row, DirStepY[Icon]);
    if Col > $F then
    begin
      PartyMapColumn := $F;
      ds49D6^[725] := 1;
    end;
    if Col < 0 then
    begin
      PartyMapColumn := 0;
      ds49D6^[725] := 1;
    end;
    if Row > $F then
    begin
      PartyMapRow := $F;
      ds49D6^[725] := 1;
    end;
    if Row < 0 then
    begin
      PartyMapRow := 0;
      ds49D6^[725] := 1;
    end;
  end;
end;
{ ovl14:073B. Moves the party one cell in the current icon set's direction, wrapping
  the 16x16 area map ($F steps to 0, 0 steps to $F), then refreshes the cell bytes
  ds6AB0 (through WallIdAt) and ds6AB1 (through EventByteAt), resets the ds6DDE..ds6DE0
  menu flags to 1, and steps
  the sound through ovl20_e1 (mode 2 when ds49D6^[714] has bit 0, else mode 1).
  Called by DoWildernessMenu. }
procedure MoveParty;
begin
  PlaySound(ds2628);
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
  ds6AB0 := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
  FillChar(ds6DDE, 3, 1);
  ds6AB1 := EventByteAt(PartyMapColumn, PartyMapRow);
  if ds49D6^[714] and 1 > 0 then
    ovl20_e1(1, 2)
  else
    ovl20_e1(1, 1);
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
        ovl20_e1($C, 3);
      end;
  else
    GameVars^[VarMapX] := GridCol;
    GameVars^[VarMapY] := GridRow;
    ovl20_e1($C, 3);
  end;
end;
{ ovl14:0989. The wilderness key driver (called by ovl03_fn_3379): in the 3D view it
  reads menu and movement keys through ReadPromptChoice and dispatches them (A/C/V/E/S/L
  menu keys, H/M/P/K movement with the icon sets, anything else through UpdateSelectedCharacter),
  otherwise it loads the ICON pictures for map pages 2..4 and runs a smaller key loop;
  either loop repeats through DrawLocationLine until Redraw is set, then it tidies the
  window and returns the key. Also clears ds49D6^[713] on entry. }
function HandleWildernessKeys: Char;
var
  Redraw: Byte;
  Key: Char;
  KeyFlag: Byte;
  SpareBuf: String[40];   { 41 frame-filling bytes, never read; purpose unknown }
  ViewFlag: Byte;         { flag ViewSelectedCharacter (View) takes }
  SpareLong: LongInt;     { 4 frame-filling bytes, never read; purpose unknown }
begin
  ds49D6^[713] := 0;
  case AreaViewKind of
    1:
      begin
        Redraw := 0;
    repeat
      Key := ReadPromptChoice('', ds04B6, $D, $A, $F, 1, 0, KeyFlag);
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
            ds49D6^[714] := ds49D6^[714] xor 1;
          'L':
            begin
              ds49D6^[714] := ds49D6^[714] or 2;
              ovl20_e1(1, 2);
              EclPC := ds49E5;
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
              ds6AB0 := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
              DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
            end;
          'K':
            begin
              PartyFacing := (PartyFacing + 6) mod 8;
              PlaySound(ds2628);
              ds6AB0 := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
              DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
            end;
          'M':
            begin
              PartyFacing := (PartyFacing + 2) mod 8;
              PlaySound(ds2628);
              ds6AB0 := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
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
    if ds49F9 < 2 then
    begin
      LoadPictureSlot('ICON', 0, 9);
      LoadPictureSlot('ICON', 1, $A);
      LoadPictureSlot('ICON', 2, $B);
      DrawWildernessScreen;
    end;
    Redraw := 0;
    repeat
      Key := ReadPromptChoice('', ds04DF, $D, $A, $F, 1, 0, KeyFlag);
      if KeyFlag = 0 then
        case Key of
          'C':
            CastSpells;
          'V':
            ViewSelectedCharacter(ViewFlag);
          'E':
            Redraw := 1;
          'S':
            ds49D6^[714] := ds49D6^[714] xor 1;
          'L':
            begin
              ds49D6^[714] := ds49D6^[714] or 2;
              ovl20_e1(1, 2);
              EclPC := ds49E5;
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
  ds49F9 := AreaViewKind;
  if ds84E4 = 0 then
  begin
    ClearWindow(1, $11, $26, $16);
    ds84E4 := 1;
  end;
  HandleWildernessKeys := Key;
end;
{ ovl14:0D6D. The wilderness command menu (called by ovl03_fn_3379): in the 3D view it
  builds the Bash/Pick/Knock/Exit menu from the ds6DDE/ds6DDF/ds6DE0 flags and the
  record flag checks, prompts through ReadPromptChoice and dispatches the key: in the DoorKindAt = 2
  arm 'B' calls DoBash, 'P' calls DoPick (ovl14:0ED6) and 'K' calls DoKnock, with Knock
  offered when FindCodeRecord($1F) finds a record (ovl14:0E14), while in the = 3 arm 'B'
  calls DoBash and 'K' calls DoKnock, with Knock offered when HasRecFlag(5) is set
  (ovl14:0F53), but 'P' only clears the Pick flag (mov ds6DDF,0 at ovl14:1015, no DoPick
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
      if ds49D6^[713] < $FF then
      begin
      case DoorKindAt(PartyMapColumn, PartyMapRow, PartyFacing) of
        1:
          Done := 1;
        2:
        begin
          Menu[0] := #0;
          if ds6DDE[0] <> 0 then
            Menu := 'Bash';
          if (ds6DDF <> 0) and (HasRecFlag(6) <> 0) then
            Menu := Menu + ' Pick';
          if (ds6DE0 <> 0) and (FindCodeRecord(KnockCode) <> nil) then
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
          if ds6DDE[0] <> 0 then
            Menu := 'Bash';
          if (ds6DDF <> 0) and (HasRecFlag(6) <> 0) then
            Menu := Menu + ' Pick';
          if (ds6DE0 <> 0) and (HasRecFlag(5) <> 0) then
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
                ds6DDF := 0;
              'K':
                Done := Ord(DoKnock);
            end;
          end;
        end;
      end;
      if Done <> 0 then
        MoveParty
      else
        PlaySound(ds2622);
      DrawLocationLine;
    end
    else
      ds49D6^[713] := 0;
  end;
  2..4:
  begin
    if ds49D6^[713] < $FF then
    begin
      CheckMapCell;
      DrawLocationLine;
    end
    else
      ds49D6^[713] := 0;
  end;
  end;
  FreeSpriteList(@PictureAnimation);
  ReleasePicture(ds6B01);
  ReleasePicture(ds6B06);
  HeadBankIndex := $FF;
  BodyBankIndex := $FF;
end;

{ ovl14:10A7. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
  (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the wilderness unit runs no code
  at start-up. }
begin
end.

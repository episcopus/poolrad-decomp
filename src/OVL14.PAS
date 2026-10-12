unit OVL14;
{ Wilderness travel (whitepaper 5.2): the area-map movement keys and icon sets, the
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
    Unknown00: array[0..$16] of Byte; { +$00..+$16: not read here }
    Codes: array[0..$14] of Byte;     { +$17..+$2B: scanned for the wanted code }
    Unknown2C: array[$2C..$77] of Byte; { +$2C..+$77: not read here }
    PickThreshold: Byte;              { +$78: the 1d100 Pick roll must not exceed it }
    Unknown79: array[$79..$95] of Byte; { +$79..+$95: not read here }
    Flags: array[0..13] of ShortInt;  { +$96..+$A3: nonzero gates a menu item (5 Knock, 6 Pick);
                                        signed: ovl14:026A compares with jle; extent uncertain }
    UnknownA4: array[$A4..$103] of Byte; { +$A4..+$103: not read here }
    Next: PCodeRec;                   { +$104: next record, nil ends the list }
    Unknown108: array[$108..$10B] of Byte; { +$108..+$10B: not read here }
    PickFlag: Byte;                   { +$10C: Pick proceeds only when it is 0 }
  end;
procedure ClearIconBits(Col, Row, Icon: ShortInt);
procedure SetIconBits(Col, Row, Icon: ShortInt);
function HasRecFlag(Which: ShortInt): Byte;
procedure ovl14_fn_0294;
function DoPick: Byte;
function FindCodeSlot(Code: Byte; Rec: PCodeRec): Byte;
function FindCodeRecord(Code: Byte): PCodeRec;
function DoKnock: Boolean;
procedure ClampPartyPosition;
procedure MoveParty;
procedure CheckMapCell;
procedure ovl14_e2;
procedure ovl14_e1;
implementation
uses OVL29, RES03, RES05, RES06, OVL20, OVL24;

{ ovl14:0000. Clears the icon set's bit pair in the event byte of the area-map cell
  (Col, Row): bits 6-7 for icon 6, 4-5 for 4, 2-3 for 2, 0-1 for 0. Called by ovl14_e1
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
{ ovl14:0236. Returns 1 when any record of the ds5D96 list has a nonzero byte at
  +$96+Which, else 0. The Bash/Pick/Knock menu (ovl14_e1) offers Pick when flag 6 is
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
{ ovl14:0294: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl14_fn_0294; begin end;
{ ovl14:04DF. The Pick command (the P key): rolls 1d100 (ovl24_e8) against each
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
      if ovl24_e8(1, $64) <= PickThreshold then
        if PickFlag = 0 then
          Done := 1;
    end;
    Rec := Rec^.Next;
  end;
  ds6DDF := 0;
  if Done <> 0 then
  begin
    SetIconBits(ds6AAD, ds6AAE, ds6AAF);
    SetIconBits(ds6AAD + ds2736[ds6AAF], ds6AAE + ds273F[ds6AAF], (ds6AAF + 4) mod 8);
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
  ovl29_e3 allows it, clamping the result into the 16x16 area map: each clamped
  coordinate is written back and the edge flag ds49D6^[725] (+$5AA) is set. Called
  by the movement driver ovl14_e2. The direction tables ds2736/ds273F are indexed
  by the icon set [I]. }
procedure ClampPartyPosition;
var
  Col, Row: Integer;
  Icon: Integer;
begin
  Col := ds6AAD;
  Row := ds6AAE;
  Icon := ds6AAF;
  ds49D6^[725] := 0;
  if ovl29_e3(Col, Row, Icon) then
  begin
    Inc(Col, ds2736[Icon]);
    Inc(Row, ds273F[Icon]);
    if Col > $F then
    begin
      ds6AAD := $F;
      ds49D6^[725] := 1;
    end;
    if Col < 0 then
    begin
      ds6AAD := 0;
      ds49D6^[725] := 1;
    end;
    if Row > $F then
    begin
      ds6AAE := $F;
      ds49D6^[725] := 1;
    end;
    if Row < 0 then
    begin
      ds6AAE := 0;
      ds49D6^[725] := 1;
    end;
  end;
end;
{ ovl14:073B. Moves the party one cell in the current icon set's direction, wrapping
  the 16x16 area map ($F steps to 0, 0 steps to $F), then refreshes the cell bytes
  ds6AB0 (through ovl29_e2) and ds6AB1 (through ovl29_e4), clears ds6DDE, and steps
  the sound through ovl20_e1 (mode 2 when ds49D6^[714] has bit 0, else mode 1).
  Called by ovl14_e1. }
procedure MoveParty;
begin
  res03_fn_00DC(ds2628);
  Inc(ds6AAD, ds2736[ds6AAF]);
  Inc(ds6AAE, ds273F[ds6AAF]);
  if ds6AAD < 0 then
    ds6AAD := $F;
  if ds6AAD > $F then
    ds6AAD := 0;
  if ds6AAE < 0 then
    ds6AAE := $F;
  if ds6AAE > $F then
    ds6AAE := 0;
  ds6AB0 := ovl29_e2(ds6AAD, ds6AAE, ds6AAF);
  FillChar(ds6DDE, 3, 1);
  ds6AB1 := ovl29_e4(ds6AAD, ds6AAE);
  if ds49D6^[714] and 1 > 0 then
    ovl20_e1(1, 2)
  else
    ovl20_e1(1, 1);
end;
{ ovl14:0818. Checks the area-map block ahead of the party: steps the GameVars area-map
  position by the icon set's direction, clamps it (columns 0..$F, rows 0..$23), and
  reads that cell of AreaMap. N ($4E) and the impassable ranges pass through silently;
  the river codes ($66..$6C, $72) either print the stench message (when GameVars^[418]
  is 0) or move there; anything else moves there with a sound. Called by ovl14_e1. }
procedure CheckMapCell;
var
  MapCol, GridCol, GridRow: ShortInt;
begin
  GridCol := GameVars^[VarMapX] + ds2736[ds6AAF];
  GridRow := GameVars^[VarMapY] + ds273F[ds6AAF];
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
      if GameVars^[418] = 0 then
        res06_fn_0D68('The river''s stench drives you back.', $E)
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
{ ovl14:0989: retf 0: 0 bytes of parameters; 60 bytes of locals }
{@stub} procedure ovl14_e2; begin end;
{ ovl14:0D6D: retf 0: 0 bytes of parameters; 300 bytes of locals }
{@stub} procedure ovl14_e1; begin end;

begin
end.

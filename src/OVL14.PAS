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
    Unknown2C: array[$2C..$103] of Byte; { +$2C..+$103: not read here }
    Next: PCodeRec;                   { +$104: next record, nil ends the list }
  end;
procedure ovl14_fn_0000;
procedure ovl14_fn_0109;
procedure ovl14_fn_0236;
procedure ovl14_fn_0294;
procedure ovl14_fn_04DF;
function FindCodeSlot(Code: Byte; Rec: PCodeRec): Byte;
function FindCodeRecord(Code: Byte): PCodeRec;
function DoKnock: Boolean;
procedure ovl14_fn_068D;
procedure ovl14_fn_073B;
procedure ovl14_fn_0818;
procedure ovl14_e2;
procedure ovl14_e1;
implementation

{ ovl14:0000: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl14_fn_0000; begin end;
{ ovl14:0109: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl14_fn_0109; begin end;
{ ovl14:0236: retf 2: 2 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl14_fn_0236; begin end;
{ ovl14:0294: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl14_fn_0294; begin end;
{ ovl14:04DF: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl14_fn_04DF; begin end;
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
{ ovl14:068D: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl14_fn_068D; begin end;
{ ovl14:073B: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl14_fn_073B; begin end;
{ ovl14:0818: retf 0: 0 bytes of parameters; 40 bytes of locals }
{@stub} procedure ovl14_fn_0818; begin end;
{ ovl14:0989: retf 0: 0 bytes of parameters; 60 bytes of locals }
{@stub} procedure ovl14_e2; begin end;
{ ovl14:0D6D: retf 0: 0 bytes of parameters; 300 bytes of locals }
{@stub} procedure ovl14_e1; begin end;

begin
end.

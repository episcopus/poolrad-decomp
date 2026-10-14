{ Probe: the frame layout of ovl22_e8 (ovl22:331A). The original reserves 0x12a bytes of locals;
  this reconstructs the body with dummy externals to see how the Text copy and the two string
  temporaries ('Casts a Spell' and the 'Spell:' concatenation) add up.
  make tpc SRC=tools/re/tp_idioms/ovl22/E8FRAME.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
program E8Frame;

type
  String40 = string[40];
  PCharacter = ^TCharacter;
  TCharacter = record
    Name: string[15];
    Pad: array[$10..$140] of Byte;
  end;

var
  ds49F3: Byte;
  SpellNames: array[0..$38] of string[40];

procedure DrawTextAt(Col, Row, Color: Byte; Text: string); far;
begin
end;

procedure ClearWindow(LeftCol, TopRow, RightCol, BottomRow: ShortInt); far;
begin
end;

procedure DelayByGameSpeed; far;
begin
end;

procedure res12_fn_16EC(Who: Pointer; Text: string; A, B: Byte); far;
begin
end;

procedure res12_fn_1816(Who: Pointer; Col, Row, Mode: Byte); far;
begin
end;

procedure res12_fn_17E3; far;
begin
end;

procedure e8(Who: PCharacter; Message: String40; Spell: Byte); far;
const
  CombatViewMode = 5;
  MessageColour = $A;
  TimedMessage = 1;
  NameColumn = 1;
  MessageRow = $13;
  SpellNameRow = $14;
  GapAfterName = 2;
  NoMode = 0;
begin
  if ds49F3 = CombatViewMode then
  begin
    res12_fn_16EC(Who, 'Casts a Spell', MessageColour, TimedMessage);
    ClearWindow(0, $17, $27, $17);
    DrawTextAt(0, $17, MessageColour, 'Spell:' + SpellNames[Spell]);
  end
  else
  begin
    ClearWindow(1, $12, $26, $16);
    res12_fn_1816(Who, NameColumn, MessageRow, NoMode);
    DrawTextAt(Length(Who^.Name) + GapAfterName, MessageRow, MessageColour, Message);
    DrawTextAt(1, SpellNameRow, MessageColour, SpellNames[Spell]);
    DelayByGameSpeed;
    res12_fn_17E3;
  end;
end;

begin
  e8(nil, '', 0);
end.

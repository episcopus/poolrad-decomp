{ Probe: the codegen of ovl22_e22's Charisma increment (ovl22:13D8). The original is
  `call RollDice; les di,[ds6C95]; add es:[di+0x15], al` (a byte add into the field, no word
  extension). This shows which source form gives that vs the word-extended `xor ah,ah` shape.
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB22.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
program Prb22;

type
  String40 = string[40];
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$14] of Byte;
    Charisma: Byte;
  end;

var
  ds6C95: PCharacter;
  ds681B: Byte;

function RollDice(Count, Sides: Byte): Byte; far;
begin
  RollDice := 1;
end;

procedure ApplySpellToTargets(Spell, CasterLevel, Flag, Damage, Kind: Byte; Message: String40); far;
begin
end;

procedure e22; far;
const
  DiceCount = 2;
  DiceSides = 4;
  CharismaCap = $19;
  RestoreOnRemoval = 1;
  MessageColour = $A;
  TimedMessage = 1;
var
  OldCharisma: Byte;
begin
  OldCharisma := ds6C95^.Charisma;
  ds6C95^.Charisma := ds6C95^.Charisma + RollDice(DiceCount, DiceSides);
  if ds6C95^.Charisma > CharismaCap then
    ds6C95^.Charisma := CharismaCap;
  ApplySpellToTargets(ds681B, OldCharisma, RestoreOnRemoval, 0, 0, 'is friendly');
end;

begin
  e22;
end.

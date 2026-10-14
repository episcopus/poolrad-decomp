program PRB19DEC;
{ UseItem (ovl19:1A8A) takes a spell number above $38 down by $17. The original does it as
  `sub byte ptr [bp-1], 0x17` (ovl19:1B2E), which is Dec(Spell, SpellShift). The assignment
  Spell := Spell - SpellShift with the same constant widens the byte through AX (xor ah, ah; sub ax). }
{$A-,O+,F+,S-,R-,G-,I-}
const
  LastSpell = $38;
  SpellShift = $17;

procedure ProbeDec(Item: Byte; var Done: Byte);
var
  Spell: Byte;
begin
  Spell := Item;
  if Spell > LastSpell then
    Dec(Spell, SpellShift);
  Done := Spell;
end;

procedure ProbeAssign(Item: Byte; var Done: Byte);
var
  Spell: Byte;
begin
  Spell := Item;
  if Spell > LastSpell then
    Spell := Spell - SpellShift;
  Done := Spell;
end;

var
  Flag: Byte;

begin
  ProbeDec(Flag, Flag);
  ProbeAssign(Flag, Flag);
end.

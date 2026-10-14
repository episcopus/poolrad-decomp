{ Probe: how TP 6.0 calls a routine through a 0-based global table of far procedure
  pointers aliased over a procedural variable (ovl22:0C20 calls SpellHandlers[Spell]
  with no arguments and the target picker ds6B84(A, B, Done) with three). }
{$A-,O+,F+,S-,R-,G-,I-}
program CallTab;

type
  TTargetPicker = procedure(Spell: Byte; Unused: Byte; var Done: Byte);
  TSpellHandler = procedure;

var
  ds6B84: Pointer;
  TargetPicker: TTargetPicker absolute ds6B84;
  SpellHandlers: array[0..$38] of TSpellHandler absolute ds6B84;
  Spell, B, Done: Byte;

begin
  TargetPicker(Spell, B, Done);
  SpellHandlers[Spell];
end.

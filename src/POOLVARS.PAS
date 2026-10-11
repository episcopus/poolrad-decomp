unit POOLVARS;
{ Game globals whose owning unit is not known yet. Names: dsXXXX is the DS offset
  (re/dseg.toml may give a better name later); others are named in re/dseg.toml. }
{$A-,F+,S-,R-,G-,I-}
interface
uses Dos;
var
  ds2612: Word;
  ds49F7: Boolean;
  ds49D0: Boolean;
  Regs: Registers;
  ds4A1C: Byte;
  ds5372: Byte;
  ds5373: Byte;
  ds557D: Boolean;
implementation
end.

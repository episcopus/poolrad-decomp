unit POOLVARS;
{ Game globals whose owning unit is not known yet. Names: dsXXXX is the DS offset
  (re/dseg.toml may give a better name later); others are named in re/dseg.toml. }
{$A-,F+,S-,R-,G-,I-}
interface
uses Dos;
var
  ds2612: Word;                   { passed to res03_fn_00DC when the sound stops (QuitGame, Ctrl-S); meaning unknown }
  DebugMode: Boolean;             { STING debug mode: switched by Ctrl-D in ReadGameKey; ShowDebugTrace shows only when set }
  ds49D0: Boolean;                { when set, HeapErrorHandler offers ovl17_e9 (save and load unit) before quitting }
  Regs: Registers;                { registers for Intr calls (QuitGame) }
  SavedVideoMode: Byte;           { the video mode QuitGame restores }
  SoundMode: Byte;                { sound setting; 2 while paused by Ctrl-S (ReadGameKey) }
  SoundModeBeforePause: Byte;     { SoundMode before a Ctrl-S pause; restored when 0 or 1 }
  ds557D: Boolean;                { set by ovl17_e9; True ends HeapErrorHandler's retry loop }
implementation
end.

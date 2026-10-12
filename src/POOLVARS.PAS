unit POOLVARS;
{ Game globals whose owning unit is not known yet. Names: dsXXXX is the DS offset
  (re/dseg.toml may give a better name later); others are named in re/dseg.toml. }
{$A-,F+,S-,R-,G-,I-}
interface
uses Dos;
type
  { One fixed position of the area view whose block the game variables can override
    (the table at DS:0C30; DrawAreaView reads entries 1..9, entry 0 is never read). }
  TSpecialBlock = record
    Col, Row: Word;              { position of the block on the area map (DS:3648) }
    Pic: Word;                   { the block code drawn instead of the one in the map }
  end;
  { The word variables of the game: the structure the far pointer at DS:49D2 leads to. ovl07 and
    ovl17 index it dynamically (the variables of the ECL scripts), words 195 and 196 keep the party
    position on the area map, and DrawAreaView reads words 380, 396, 415, 416, 435 and 466 as gates
    for fixed area blocks. The upper bound is still unknown; 465 words are in use. }
  TGameVars = array[0..511] of Word;
var
  SpecialBlocks: array[0..9] of TSpecialBlock;  { fixed area blocks; entries 1..9 (0 never read) }
  ds2612: Word;                   { passed to res03_fn_00DC when the sound stops (QuitGame, Ctrl-S); meaning unknown }
  AreaMap: array[0..35, 0..43] of Byte;  { the area map: one block code per 3x3-tile block, one more
                                          than the code ovl32_e2 draws; byte 0x4E (the letter N)
                                          where no block is drawn (all of rows 34 and 35 in the
                                          shipped image). Read by DrawAreaView, ovl10 and ovl14. }
  ds49D0: Boolean;                { when set, HeapErrorHandler offers ovl17_e9 (save and load unit) before quitting }
  GameVars: ^TGameVars;             { the game variables (see TGameVars) }
  DebugMode: Boolean;             { STING debug mode: switched by Ctrl-D in ReadGameKey; ShowDebugTrace shows only when set }
  Regs: Registers;                { registers for Intr calls (QuitGame) }
  SavedVideoMode: Byte;           { the video mode QuitGame restores }
  SoundMode: Byte;                { sound setting; 2 while paused by Ctrl-S (ReadGameKey) }
  SoundModeBeforePause: Byte;     { SoundMode before a Ctrl-S pause; restored when 0 or 1 }
  ds557D: Boolean;                { set by ovl17_e9; True ends the retry loop of HeapErrorHandler }
implementation
end.

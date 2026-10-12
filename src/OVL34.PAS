unit OVL34;
{ The 8x8 tile loader (whitepaper 4.x): Load8x8Bank loads one bank of 8x8 tiles from an 8X8D
  file through res07, and Put8x8Symbol draws one tile at a column and row, either through
  res07_fn_08D4 or by copying it into the staging buffer and showing it with res07_fn_1951. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure Load8x8Bank(Count, Bank: Byte);
procedure Put8x8Symbol(XPos, YPos: ShortInt; Symbol: Word; Direct: Boolean; Attr: Byte);
implementation
uses POOLVARS, RES04, RES07;

const
  FirstBank = 0;                { lowest 8x8 bank Load8x8Bank takes }
  LastBank = 4;                 { highest 8x8 bank }
  LoadArg2 = 1;                 { second argument Load8x8Bank passes res07_fn_0111 }
  LoadArg3 = $D;                { third argument Load8x8Bank passes res07_fn_0111 }

{ ovl34:003B. Loads Count tiles of 8x8 bank Bank (0..4) from the file 8x8d<TileSet> through
  res07_fn_0111. On a failure (the bank pointer stays nil) it announces Unable to load
  8x8D<set>-<count> on Output, waits for a key and ends the game; otherwise it flushes the
  keyboard. Called by LoadWallSet and ovl11_fn_0435. }
procedure Load8x8Bank(Count, Bank: Byte);
var
  NumSet: string[1];            { Str(TileSet): the file number in the name and the message }
  NumCount: string[3];          { Str(Count): the count in the message }
  Unused: Byte;                 { never read or written; the frame needs one byte here (sub sp,0x108) }
  Key: Char;                    { the key waited for before quitting on a failure }
begin
  if Bank in [FirstBank..LastBank] then
  begin
    Str(TileSet, NumSet);
    Str(Count, NumCount);
    res07_fn_0111('8x8d' + NumSet, Count, LoadArg2, LoadArg3, TileBanks[Bank]);
    if TileBanks[Bank] = nil then
    begin
      res07_fn_00FF;
      WriteLn(Output, 'Unable to load 8x8D' + NumSet + '-' + NumCount);
      Key := ReadGameKey;
      res07_fn_00FF;
      QuitGame;
    end;
    FlushKeyboard;
  end;
end;

{ ovl34:015D: retf 10: 10 bytes of parameters; 6 bytes of locals.
  Draws one 8x8 symbol; signature from the pushes of its callers (res09_fn_0000, ovl29). }
{@stub} procedure Put8x8Symbol(XPos, YPos: ShortInt; Symbol: Word; Direct: Boolean; Attr: Byte); begin end;

begin
end.

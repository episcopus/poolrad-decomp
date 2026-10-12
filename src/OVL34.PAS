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

{ ovl34:015D. Draws 8x8 symbol Symbol at (XPos, YPos). Symbols 1..$11E live in banks 0..4
  (ranges 1..$2D, $2E..$73, $74..$B9, $BA..$FF, $100..$11E, based at SymbolBase); 0 and
  $11F..$7FFF are fatal (Bad symbol number in Put8x8Symbol on Output, a key, then the game
  ends). QUIRK ovl34:01C0: symbols above $7FFF skip the check and run on with an unset bank.
  A nil bank pointer draws nothing. Otherwise Symbol is made bank relative and the tile is
  drawn through res07_fn_08D4 when Direct is set (the 3D view) or copied into the staging
  buffer TileBuf and shown with res07_fn_1951 (window frames). Called by res09_fn_0000 and
  ovl29 (three times). }
procedure Put8x8Symbol(XPos, YPos: ShortInt; Symbol: Word; Direct: Boolean; Attr: Byte);
var
  Bank: Byte;                   { the bank holding Symbol, from the case ranges }
  Key: Char;                    { the key waited for before quitting on a bad symbol }
begin
  case Symbol of
    1..$2D: Bank := 0;
    $2E..$73: Bank := 1;
    $74..$B9: Bank := 2;
    $BA..$FF: Bank := 3;
    $100..$11E: Bank := 4;
    0, $11F..$7FFF:
    begin
      res07_fn_00FF;
      WriteLn(Output, 'Bad symbol number in Put8x8Symbol.');
      Key := ReadGameKey;
      QuitGame;
    end;
  end;
  if TileBanks[Bank] <> nil then
  begin
    Dec(Symbol, SymbolBase[Bank]);
    if Direct then
      res07_fn_08D4(XPos, YPos, Lo(Symbol), Attr, TileBanks[Bank], DrawBuf)
    else
      with TileBanks[Bank]^ do
      begin
        Move(Data[Symbol * Stride], TileBuf^.Data[0], Stride);
        res07_fn_1951(XPos, YPos, TileBuf);
      end;
  end;
end;

begin
end.

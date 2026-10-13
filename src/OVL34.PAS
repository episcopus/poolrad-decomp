unit OVL34;
{ The 8x8 tile loader (whitepaper 4.2.3): Load8x8Bank loads one bank of 8x8 tiles from an 8X8D
  file through res07, and Put8x8Symbol draws one tile at a column and row, either through
  DrawPictureItem or by copying it into the staging buffer and showing it with ShowPicture. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure Load8x8Bank(BlockId, Bank: Byte);
procedure Put8x8Symbol(XPos, YPos: ShortInt; Symbol: Word; Direct: Byte; Attr: Byte);
implementation
uses POOLVARS, RES04, RES07;

const
  FirstBank = 0;                { lowest 8x8 bank Load8x8Bank takes }
  LastBank = 4;                 { highest 8x8 bank }
  { Purpose unknown: the B and C arguments of LoadPicture for an 8x8 bank; the whole-picture
    loads (TITLE in ovl01, SQRPACI in ovl11, FINAL in ovl18) pass 0 and 0 there. }
  TileLoadB = 1;
  TileLoadC = $D;

{ ovl34:003B. Loads block BlockId of the file 8x8d<TileSet> into 8x8 bank Bank (0..4) through
  LoadPicture (its first number is the DAX block id, as TITLE 1 and 2 in ovl01 and FINAL 1..6 in
  ovl18 show; LoadWallSet passes its WALLDEF block id). On a failure (the bank pointer stays nil)
  it announces Unable to load 8x8D<set>-<block> on Output, waits for a key and ends the game;
  otherwise it flushes the keyboard. Any other Bank does nothing. Called by LoadWallSet and
  StartGame. }
procedure Load8x8Bank(BlockId, Bank: Byte);
var
  NumSet: string[1];            { Str(TileSet): the file number in the name and the message }
  NumBlock: string[3];          { Str(BlockId): the block id in the message }
  Unused: Byte;                 { never read or written; the frame needs one byte here (sub sp,0x108) }
  Key: Char;                    { the key waited for before quitting on a failure }
begin
  if Bank in [FirstBank..LastBank] then
  begin
    Str(TileSet, NumSet);
    Str(BlockId, NumBlock);
    LoadPicture('8x8d' + NumSet, BlockId, TileLoadB, TileLoadC, TileBanks[Bank]);
    if TileBanks[Bank] = nil then
    begin
      RestoreVideoMode;
      WriteLn(Output, 'Unable to load 8x8D' + NumSet + '-' + NumBlock);
      Key := ReadGameKey;
      RestoreVideoMode;
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
  drawn through DrawPictureItem when Direct is nonzero (the 3D view) or copied into the staging
  buffer TileBuf and shown with ShowPicture (window frames). Called by DrawWindowFrame and
  ovl29 (three times): DrawWindowFrame passes Direct 0, the ovl29 calls (the 3D view and the
  overhead wall map) pass 1 (ovl29:010C, 0146, 02FB). }
procedure Put8x8Symbol(XPos, YPos: ShortInt; Symbol: Word; Direct: Byte; Attr: Byte);
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
      RestoreVideoMode;
      WriteLn(Output, 'Bad symbol number in Put8x8Symbol.');
      Key := ReadGameKey;
      QuitGame;
    end;
  end;
  if TileBanks[Bank] <> nil then
  begin
    Dec(Symbol, SymbolBase[Bank]);
    if Direct <> 0 then
      DrawPictureItem(XPos, YPos, Lo(Symbol), Attr, TileBanks[Bank], DrawBuf)
    else
      with TileBanks[Bank]^ do
      begin
        Move(Data[Symbol * Stride], TileBuf^.Data[0], Stride);
        ShowPicture(XPos, YPos, TileBuf);
      end;
  end;
end;

begin
end.

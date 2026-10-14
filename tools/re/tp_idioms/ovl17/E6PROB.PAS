{ Probe for ovl17_e6's local layout and Str/LoadDaxBlock codegen (playbook 30).
  Question: with the declared locals Size, Block, Offset, Item, Affect, CharSet: string[1], I, Roll,
  Monster, ErrMsg: string[40], Name: String20, Ext: string[4], which offsets do they and the string
  temporaries get? (the original uses 2, 6, 8, 0xc, 0x10, 0x12, 0x13, 0x14, 0x18, 0x2b, 0x114, 0x119) }
{$F+,S-,R-,I-}
program E6Prob;

type
  String20 = string[20];
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$7E] of Byte;
    Affects: Pointer;
    Pad83: array[$83..$C7] of Byte;
    Items: Pointer;
    PadCC: array[$CC..$103] of Byte;
    Next: PCharacter;
    Combat: Pointer;
    Pad10C: array[$10C..$12B] of Byte;
  end;
  PItem = ^TItem;
  TItem = record Pad: array[0..62] of Byte; end;
  PAffect = ^TAffect;
  TAffect = record Pad: array[0..8] of Byte; end;

var
  TileSet: Byte;

procedure LoadDaxBlock(Name: String20; Ext: String20; BlockId: Byte; var Size: Word; var Block: Pointer); begin end;

procedure T(Kind: Byte; Who: Pointer);
var
  Size: Word;
  Block: Pointer;
  Offset: Word;
  Item: PItem;
  Affect: PAffect;
  CharSet: string[1];
  I: Byte;
  Roll: Byte;
  Monster: PCharacter;
  ErrMsg: string[40];
  Name: String20;
  Ext: string[4];
begin
  Str(TileSet, CharSet);
  Name := 'MON' + CharSet + 'CHA';
  Ext := '.dax';
  LoadDaxBlock(Name, Ext, Kind, Size, Block);
  if Size = 0 then
  begin
    ErrMsg := 'Unable to load monster';
    Monster := Who;
    Monster^.Items := nil;
  end;
end;

begin
  T(0, nil);
end.

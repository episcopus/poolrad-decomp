{ Probe for res12:01FB (playbook 30).
  Question: which Pascal reproduces the original's armour-movement chain:
    mov al,[di+2eh]; ...; cmp byte [di+5582h],2; jne end;
    mov ax,[di+37h]; cmp ax,0; jb L2; cmp ax,96h; ja L2; ...
  Does `(W >= 0) and (W <= $96)` emit the leading cmp ax,0 / jb, and how do the else-if
  ranges and the trailing plus block lay out? The record offsets match POOLVARS (Weight +37h,
  Plus +32h, BaseMovement +72h, Movement +11Ch). }
{$F+,S-,R-,I-}
program Res12Probe;

type
  TRaceRow = array[0..15] of Byte;
  PCharacter = ^TCharacter;
  PItem = ^TItem;
  TItem = record
    Text: string[40];
    Flag29: Byte;
    Next: Pointer;
    ItemType: Byte;
    NameNum: array[1..3] of Byte;
    Plus: ShortInt;
    PlusSave: Byte;
    Readied: Boolean;
    HiddenNames: Byte;
    Cursed: Boolean;
    Weight: Word;
    Count: Byte;
    Value: Word;
    Affects: array[1..3] of Byte;
  end;
  TCharacter = record
    Pad: array[0..$71] of Byte;
    BaseMovement: Byte;
    Pad2: array[0..$A8] of Byte;
    Movement: Byte;
  end;

var
  RaceRow: array[0..128] of TRaceRow;

procedure SetMovement(Who: PCharacter; Item: PItem);
begin
  if RaceRow[Item^.ItemType][0] = 2 then
  begin
    case Item^.Weight of
      0..$96: Who^.Movement := Who^.BaseMovement;
      $97..$18F: Who^.Movement := 9;
    else
      Who^.Movement := 6;
    end;
    if Item^.Plus <> 0 then
      if Who^.Movement <= 9 then
        Who^.Movement := Who^.Movement + 3;
  end;
end;

var
  Who: PCharacter;
  Item: PItem;

begin
  SetMovement(Who, Item);
end.

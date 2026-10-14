{ Probe for res12:0442 (playbook 30).
  Questions: the string temp pattern of (a) `P^.Text := P^.Text + '* '`, (b) an explicit local
  Name/Temp pair around a string function, and (c) the exact StrCopy/StrConcat/StrLCopy call
  shapes, so the item-name formatter can be reproduced. Record offsets as POOLVARS (Text +0,
  NameNum +2F, HiddenNames +35, Count +39, ItemType +2E). }
{$F+,S-,R-,I-}
program Res12Probe3;

type
  PItem = ^TItem;
  TItem = record
    Text: string[40];
    Flag29: Byte;
    Next: Pointer;
    ItemType: Byte;
    NameNum: array[1..3] of Byte;
    Plus: ShortInt;
    PlusSave: ShortInt;
    Readied: Boolean;
    HiddenNames: Byte;
    Cursed: Boolean;
    Weight: Word;
    Count: Byte;
    Value: Word;
    Affects: array[1..3] of Byte;
  end;

function NumberToStr(N: Byte): string;
begin
  NumberToStr := '';
end;

procedure Magic(P: PItem);
var
  Temp: string[255];
  Name: string[255];
begin
  Temp := P^.Text + '* ';
  P^.Text := Temp;
  if P^.Count > 0 then
  begin
    Name := P^.Text;
    Name := Name + NumberToStr(P^.Count) + ' ';
    P^.Text := Name;
  end;
end;

var
  Item: PItem;

begin
  Magic(Item);
end.

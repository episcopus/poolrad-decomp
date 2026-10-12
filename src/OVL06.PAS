unit OVL06;
{ Shop: the shopkeeper screen. ovl06_e1 (053E) is the entry: it shows the shop menu
  (Buy/View/Take/Pool/Share/Appraise/Exit) through ovl25_e2 and dispatches each choice.
  ChooseShopItem (0030) lists the shop's stock in the shop window and runs the item picker
  (ovl25_e4); ovl06_fn_0361 (0361) is the Buy flow, AddInventoryItem (0239) adds an item to the
  shop's stock list. Whitepaper section 5.4. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ChooseShopItem(var Action: Byte; var Selected: PMenuItem; var Head: PMenuItem; var Count: Word);
procedure AddInventoryItem(Item: PMenuItem; OK: PByte);
procedure ovl06_fn_0311;
procedure ovl06_fn_0361;
procedure ovl06_e1;
implementation
uses OVL19, OVL25, RES09, RES12;

{ ovl06:0030 (ChooseShopItem). Builds the shop window and the item picker. Walks the stock list at
  ds6810 and rewrites each entry's Name into a 30-character field with the name on the left and the
  Count right-justified (a zero Count becomes 1), then draws the "Shop" window (DrawWindow) and runs
  the item picker ovl25_e4 titled "Items: " with a "Buy" button. Action receives the picker's key,
  Head the chosen entry, Selected is set to Head; res12_fn_0442 is called for each entry afterwards.
  Parameters: Action (out, the key), Selected (out, the chosen entry), Head (in/out, the list the
  picker works on), Count (in/out). Side effect: the screen. Called from ovl06_fn_0361 (Buy). }
procedure ChooseShopItem(var Action: Byte; var Selected: PMenuItem; var Head: PMenuItem; var Count: Word);
var
  List, Entry: PMenuItem;
  NumStr: string[16];
  Field: string[30];
  N, I, Flag: Byte;
begin
  Flag := 1;
  Entry := ds6810;
  while Entry <> nil do
  begin
    Field := '                              ';
    if Entry^.Count = 0 then
      Entry^.Count := 1;
    Str(Entry^.Count, NumStr);
    N := Length(NumStr);
    for I := 1 to N do
      Field[30 - N + I] := NumStr[I];
    N := Length(Entry^.Name);
    for I := 1 to N do
      Field[I] := Entry^.Name[I];
    Entry^.Name := Field;
    { QUIRK ovl06:012B: the length is set again although the assignment above already set it to 30 }
    Entry^.Name[0] := #30;
    Entry := Entry^.Next;
  end;
  DrawWindow(1, 1, $26, $16, 0, $0F, 'Shop');
  List := ds6810;
  Action := ovl25_e4('Items: ', 'Buy', $0D, $0A, $0F, 1, 4, $26, $16, List, 1, Flag, Count, Head);
  Selected := Head;
  Entry := ds6810;
  while Entry <> nil do
  begin
    res12_fn_0442(0, Entry, 0, 0, 0, 0);
    Entry := Entry^.Next;
  end;
end;

{ ovl06:0239 (AddInventoryItem). Appends a clone of Item to the list at ds5D92^.Stock while the
  inventory has room. ovl19_e9 (Inventory) checks the list against the item and returns True when it
  is overloaded: OK^ is then 1 and "OverLoaded" is shown. Otherwise OK^ is 0 and a new TMenuItem is
  allocated (New), the item copied into it (record assignment of $3F bytes) and the node linked at the
  end of ds5D92^.Stock; res12_fn_0BB8 then redraws the list. Item is the entry to add, OK receives the
  overload flag (1 = full). Called from ovl05 (TreasureShare) and ovl06_fn_0361 (Buy). }
procedure AddInventoryItem(Item: PMenuItem; OK: PByte);
var
  Tail, NewItem: PMenuItem;
begin
  if ovl19_e9(ds5D92, Item) then
  begin
    res12_fn_1693('OverLoaded');
    OK^ := 1;
  end
  else
  begin
    OK^ := 0;
    Tail := ds5D92^.Stock;
    if Tail = nil then
    begin
      New(Tail);
      Tail^ := Item^;
      Tail^.Next := nil;
      ds5D92^.Stock := Tail;
    end
    else
    begin
      while Tail^.Next <> nil do
        Tail := Tail^.Next;
      New(NewItem);
      NewItem^ := Item^;
      NewItem^.Next := nil;
      Tail^.Next := NewItem;
    end;
    res12_fn_0BB8(ds5D92);
  end;
end;

{ ovl06:0311: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl06_fn_0311; begin end;

{ ovl06:0361: retf 0: 0 bytes of parameters; 40 bytes of locals }
{@stub} procedure ovl06_fn_0361; begin end;

{ ovl06:053E: retf 0: 0 bytes of parameters; 138 bytes of locals }
{@stub} procedure ovl06_e1; begin end;

begin
end.

unit OVL06;
{ Shop: the shopkeeper screen. ShopMain (053E) is the entry: it shows the shop menu
  (Buy/View/Take/Pool/Share/Appraise/Exit) through ovl25_e2 and dispatches each choice.
  ChooseShopItem (0030) lists the shop's stock in the shop window and runs the item picker
  (ovl25_e4); BuyItems (0361) is the Buy flow, AddInventoryItem (0239) adds an item to the
  shop's stock list. Whitepaper section 5.4. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ChooseShopItem(var Action: Char; var Selected: PMenuItem; var Head: PMenuItem; var Count: Word);
procedure AddInventoryItem(Item: PMenuItem; OK: PByte);
procedure BuyItems;
procedure ShopMain;
implementation
uses OVL07, OVL19, OVL21, OVL25, RES06, RES09, RES12;

{ ovl06:0030 (ChooseShopItem). Builds the shop window and the item picker. Walks the stock list at
  ds6810 and rewrites each entry's Name into a 30-character field with the name on the left and the
  Count right-justified (a zero Count becomes 1), then draws the "Shop" window (DrawWindow) and runs
  the item picker ovl25_e4 titled "Items: " with a "Buy" button. Action receives the picker's key,
  Head the chosen entry, Selected is set to Head; res12_fn_0442 is called for each entry afterwards.
  Parameters: Action (out, the key), Selected (out, the chosen entry), Head (in/out, the list the
  picker works on), Count (in/out). Side effect: the screen. Called from BuyItems (Buy). }
procedure ChooseShopItem(var Action: Char; var Selected: PMenuItem; var Head: PMenuItem; var Count: Word);
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
  overload flag (1 = full). Called from ovl05 (TreasureShare) and BuyItems (Buy). }
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

{ ovl06:0361 (BuyItems). The shop's Buy flow, called from ShopMain on the 'B' menu key. It loops on
  ChooseShopItem until the player cancels (any key other than 'B' or Enter). For a chosen entry it
  first checks the party's pool (ovl19_e11 on ds5D92); if the entry's Count fits it adds the entry to
  the inventory (AddInventoryItem) and deducts the amount from the pool (ovl21_e10). Otherwise it
  reads the party's money (ovl21_e12 on ds67F4); if the Count fits it adds the entry and deducts the
  money (ovl21_e11), else it shows "Not enough Money." (res12_fn_1693). No parameters; side effect:
  the inventory and the screen. }
procedure BuyItems;
var
  Selected: PMenuItem;
  Action: Char;
  Flag: Boolean;
  SelCount, Avail: Word;
  Money: LongInt;
  OK: Byte;
  Head: PMenuItem;
  Count: Word;
begin
  Selected := nil;
  Head := ds6810;
  Count := 1;
  repeat
    ChooseShopItem(Action, Selected, Head, Count);
    if (Action <> 'B') and (Action <> #13) then
      Flag := True
    else
    begin
      Flag := False;
      SelCount := Selected^.Count;
      Avail := ovl19_e11(ds5D92);
      if SelCount <= Avail then
      begin
        AddInventoryItem(Selected, @OK);
        if OK = 0 then
        begin
          Avail := Avail - SelCount;
          ovl21_e10(Avail);
        end;
      end
      else
      begin
        Money := ovl21_e12(@ds67F4);
        if SelCount <= Money then
        begin
          AddInventoryItem(Selected, @OK);
          if OK = 0 then
          begin
            Money := Money - SelCount;
            ovl21_e11(Money);
          end;
        end
        else
          res12_fn_1693('Not enough Money.');
      end;
    end;
  until Flag;
end;

{ ovl06:053E (ShopMain). The shop's entry and main loop, called from ovl03 (the area logic) when the
  party enters a shop. It marks the shop open (ds49F3), redraws the shop screen (res12_fn_27D9,
  res12_fn_0767 on ds5D92), clears the money block ds67F4 and clears ds6DC0, then shows the menu
  (ovl25_e2) with a text chosen by ovl21_e9 (the Take/Share entries appear only when it says so)
  and dispatches the key. Done leaves the loop. No parameters; side effects: the screen, the
  inventory and the money through the called routines. }
procedure ShopMain;
var
  MenuText: string[40];
  Unknown2A: Byte;                { Purpose unknown: a byte local between MenuText and Confirmed }
  Confirmed, Flag2, Done: Byte;
  Key: Char;
  Has1, Has2, Choice, Restored: Byte;
  Entry: PMenuItem;
begin
  ds49F3 := 1;
  res12_fn_27D9;
  res12_fn_0767(ds5D92);
  FillChar(ds67F4, $1C, 0);
  Confirmed := 0;
  ds6DC0 := 0;
  Done := 0;
  Entry := ds6810;
  while Entry <> nil do
  begin
    res12_fn_0442(0, Entry, 0, 0, 0, 0);
    Entry := Entry^.Next;
  end;
  repeat
    ovl21_e9(@Has1, @Has2);
    if Has1 <> 0 then
      MenuText := 'Buy View Take Pool Share Appraise Exit'
    else
      MenuText := 'Buy View Pool Appraise Exit';
    Key := ovl25_e2(@Confirmed, MenuText, $D, $A, $F, 1, 0, @Flag2);
    case Key of
      'B': BuyItems;
      'V': ovl19_e5(@Flag2);
      'T': ovl21_e4;
      'P': if Flag2 = 0 then
             ovl21_e2;
      'S': ovl21_e3;
      'A': ovl21_e14(@Restored);
      'E':
        begin
          ovl21_e9(@Has1, @Has2);
          if Has1 <> 0 then
          begin
            MenuText := '~Yes ~No';
            res06_fn_0768(1, $11, $26, $16, $A, 1,
              'As you Leave the Shopkeeper says, "Excuse me but you have Left Some Money here."  ');
            res06_fn_0768(1, $11, $26, $16, $F, 0,
              'Do you want to go back and get your Money?');
            Choice := ovl07_e13(@Confirmed, MenuText, $D, $A, $F, 0, 0);
            if Choice = 1 then
              Done := 1
            else
              res06_fn_0DD3(1, $11, $26, $16);
          end
          else
            Done := 1;
        end;
      'G': ovl19_e10(Ord(Key));
      'O': ovl19_e10(Ord(Key));
    end;
    case Key of
      'B', 'T': res12_fn_27D9;
      'A': if Restored <> 0 then
             res12_fn_27D9;
    end;
    res12_fn_0767(ds5D92);
  until Done <> 0;
end;

begin
end.

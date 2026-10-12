unit OVL06;
{ Shop: the shopkeeper screen. ShopMain (053E) is the entry: it shows the shop menu
  (Buy/View/Take/Pool/Share/Appraise/Exit) through ReadPromptChoice and dispatches each choice.
  ChooseShopItem (0030) lists the shop's stock with its prices in the shop window and runs the item
  picker (ChooseFromList); BuyItems (0361) is the Buy flow, AddInventoryItem (0239) adds an item to the
  selected character's carried items. Items and menu lines share one record, TMenuLine
  (POOLVARS). Whitepaper section 5.4. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ChooseShopItem(var Action: Char; var Selected: PMenuLine; var Head: PMenuLine; var Choice: Integer);
procedure AddInventoryItem(Item: PMenuLine; var Overloaded: Byte);
procedure BuyItems;
procedure ShopMain;
implementation
uses OVL07, OVL19, OVL21, OVL25, RES06, RES09, RES12;

const
  AnswerNo = 1;   { ovl07_e13 returns the 0-based hotkey position: for '~Yes ~No' the second key
                    (No) is 1, the answer ShopMain leaves on }

{ ovl06:0030 (ChooseShopItem). Builds the shop window and the item picker. Walks the stock list at
  ds6810 and rewrites each entry's Text into a 30-character field with the item name on the left
  and its Value (the price, +$3A) right-justified (a zero Value becomes 1, ovl06:0068), then draws
  the "Shop" window (DrawWindow) and runs the item picker ChooseFromList titled "Items: " with a "Buy"
  button. Action receives the picker's key, Head the chosen entry, Selected is set to Head;
  res12_fn_0442 is called for each entry afterwards. Parameters: Action (out, the key), Selected
  (out, the chosen entry), Head (in/out, the list the picker works on), Choice (in/out, the
  picker's position, ChooseFromList's Choice). Side effect: the screen (and the stock entries' Text and
  Value). Called from BuyItems (Buy). }
procedure ChooseShopItem(var Action: Char; var Selected: PMenuLine; var Head: PMenuLine; var Choice: Integer);
var
  List, Entry: PMenuLine;
  NumStr: string[16];
  Field: string[30];
  N, I: Byte;
  MenuFlag: Byte;   { the var Flag of ChooseFromList: set to 1 before the picker, not read here }
begin
  MenuFlag := 1;
  Entry := ds6810;
  while Entry <> nil do
  begin
    Field := '                              ';
    if Entry^.Value = 0 then
      Entry^.Value := 1;
    Str(Entry^.Value, NumStr);
    N := Length(NumStr);
    for I := 1 to N do
      Field[30 - N + I] := NumStr[I];
    N := Length(Entry^.Text);
    for I := 1 to N do
      Field[I] := Entry^.Text[I];
    Entry^.Text := Field;
    { QUIRK ovl06:012B: the length is set again although the assignment above already set it to 30 }
    Entry^.Text[0] := #30;
    Entry := Entry^.Next;
  end;
  DrawWindow(1, 1, $26, $16, 0, $0F, 'Shop');
  List := ds6810;
  Action := ChooseFromList('Items: ', 'Buy', $0D, $0A, $0F, 1, 4, $26, $16, List, 1, MenuFlag, Choice, Head);
  Selected := Head;
  Entry := ds6810;
  while Entry <> nil do
  begin
    res12_fn_0442(0, Entry, 0, 0, 0, 0);
    Entry := Entry^.Next;
  end;
end;

{ ovl06:0239 (AddInventoryItem). Appends a clone of Item to the list at SelectedCharacter^.Items
  while the inventory has room. ovl19_e9 (Inventory) checks the list against the item and returns
  True when it is overloaded: Overloaded is then 1 and "OverLoaded" is shown. Otherwise Overloaded is
  0 and a new TMenuLine is allocated (New), the item copied into it (record assignment of $3F bytes)
  and the node linked at the end of SelectedCharacter^.Items; res12_fn_0BB8 then redraws the list.
  Item is the entry to add; Overloaded receives 1 when the item was refused (ovl06:026D) and 0 when
  it was added (ovl06:0277). Called from ovl05 (TreasureShare) and BuyItems (Buy). }
procedure AddInventoryItem(Item: PMenuLine; var Overloaded: Byte);
var
  Tail, NewItem: PMenuLine;
begin
  if ovl19_e9(SelectedCharacter, Item) then
  begin
    res12_fn_1693('OverLoaded');
    Overloaded := 1;
  end
  else
  begin
    Overloaded := 0;
    Tail := SelectedCharacter^.Items;
    if Tail = nil then
    begin
      New(Tail);
      Tail^ := Item^;
      Tail^.Next := nil;
      SelectedCharacter^.Items := Tail;
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
    res12_fn_0BB8(SelectedCharacter);
  end;
end;

{ ovl06:0361 (BuyItems). The shop's Buy flow, called from ShopMain on the 'B' menu key. It loops on
  ChooseShopItem until the player cancels (any key other than 'B' or Enter). For a chosen entry the
  Price is its Value (+$3A, ovl06:0361). It first reads the selected character's money
  (ovl19_e11); if the Price fits it adds the item to the character's items (AddInventoryItem) and,
  when that worked, stores the money less the Price (ovl21_e10). Otherwise it reads the money pooled
  in the shop (ovl21_e12 on ds67F4); if the Price fits it adds the item and stores the pool less the
  Price (ovl21_e11), else it shows "Not enough Money." (res12_fn_1693). No parameters; side effects:
  the character's items, the money and the screen.
  QUIRK ovl06:03C7: ovl19_e11 returns a LongInt, but Money is a Word, so only AX is kept and a
  character with 65536 or more is compared and charged modulo 65536 (a price can fit when only the
  low word does, or the pool pays when it does not, and ovl21_e10 then stores the low word less the
  price, ovl06:03E7..03F3). QUIRK ovl06:0449: the pool path computes Pooled - Price as a LongInt
  (ovl06:0430..0446) but ovl21_e11(Amount: Word) receives only the low word, so a pool above 65535
  is rewritten with the truncated amount (the same truncations as ovl04's ChargeForCure). }
procedure BuyItems;
var
  Selected: PMenuLine;
  Action: Char;
  Cancelled: Boolean;   { the picker key was neither 'B' nor Enter: leave the Buy loop }
  Price, Money: Word;
  Pooled: LongInt;
  Overloaded: Byte;     { AddInventoryItem's answer: 1 when the item did not fit }
  Head: PMenuLine;
  Choice: Integer;
begin
  Selected := nil;
  Head := ds6810;
  Choice := 1;
  repeat
    ChooseShopItem(Action, Selected, Head, Choice);
    if (Action <> 'B') and (Action <> #13) then
      Cancelled := True
    else
    begin
      Cancelled := False;
      Price := Selected^.Value;
      Money := ovl19_e11(SelectedCharacter);   { QUIRK ovl06:03C7: a LongInt kept in a Word }
      if Price <= Money then
      begin
        AddInventoryItem(Selected, Overloaded);
        if Overloaded = 0 then
        begin
          Money := Money - Price;
          ovl21_e10(Money);
        end;
      end
      else
      begin
        Pooled := ovl21_e12(ds67F4);
        if Price <= Pooled then
        begin
          AddInventoryItem(Selected, Overloaded);
          if Overloaded = 0 then
          begin
            Pooled := Pooled - Price;
            ovl21_e11(Pooled);   { QUIRK ovl06:0449: only the low word of the LongInt is passed }
          end;
        end
        else
          res12_fn_1693('Not enough Money.');
      end;
    end;
  until Cancelled;
end;

{ ovl06:053E (ShopMain). The shop's entry and main loop, called from ovl03 (the area logic) when the
  party enters a shop. It marks the shop open (ds49F3), redraws the shop screen (res12_fn_27D9,
  res12_fn_0767 on SelectedCharacter), clears the money block ds67F4 and clears ds6DC0, then shows the
  menu (ReadPromptChoice) with a text chosen by ovl21_e9 (the Take/Share entries appear only while
  MoneyPooled says money lies in the pool) and dispatches the key: B BuyItems, V ovl19_e5, T ovl21_e4,
  P ovl21_e2 (when MenuFlag is 0), S ovl21_e3, A ovl21_e14 (Appraise), E leaves, and G and O, which
  neither menu text shows, call ovl19_e10 with the key. With money left in the pool, E first asks
  "Do you want to go back and get your Money?" ('~Yes ~No' through ovl07_e13, which returns the
  0-based hotkey position) and the party leaves on No (AnswerNo); Yes clears the message window
  (res06_fn_0DD3) and stays. A second case redraws the screen (res12_fn_27D9) after B and T, and
  after A when Appraised is set. No parameters; side effects: the screen, the items and the money
  through the called routines. }
procedure ShopMain;
var
  MenuText: string[40];
  Title: string[1];
  MenuFlag: Byte;      { the var Flag of ReadPromptChoice: Pool runs only when it is 0, View gets it }
  Done: Byte;
  Key: Char;
  MoneyPooled: Byte;   { nonzero while money lies in the pool (ovl21_e9's first result) }
  PoolSecond: Byte;    { ovl21_e9's second result; not read here }
  LeaveAnswer: Byte;   { the answer to "go back and get your Money?" }
  Appraised: Byte;     { set by Appraise (ovl21_e14); nonzero redraws the view }
  Entry: PMenuLine;
begin
  ds49F3 := 1;
  res12_fn_27D9;
  res12_fn_0767(SelectedCharacter);
  FillChar(ds67F4, SizeOf(ds67F4), 0);
  Title := '';
  ds6DC0 := 0;
  Done := 0;
  Entry := ds6810;
  while Entry <> nil do
  begin
    res12_fn_0442(0, Entry, 0, 0, 0, 0);
    Entry := Entry^.Next;
  end;
  repeat
    ovl21_e9(MoneyPooled, PoolSecond);
    if MoneyPooled <> 0 then
      MenuText := 'Buy View Take Pool Share Appraise Exit'
    else
      MenuText := 'Buy View Pool Appraise Exit';
    Key := ReadPromptChoice(Title, MenuText, $D, $A, $F, 1, 0, MenuFlag);
    case Key of
      'B': BuyItems;
      'V': ovl19_e5(MenuFlag);
      'T': ovl21_e4;
      'P': if MenuFlag = 0 then
             ovl21_e2;
      'S': ovl21_e3;
      'A': ovl21_e14(Appraised);
      'E':
        begin
          ovl21_e9(MoneyPooled, PoolSecond);
          if MoneyPooled <> 0 then
          begin
            MenuText := '~Yes ~No';
            res06_fn_0768(1, $11, $26, $16, $A, 1,
              'As you Leave the Shopkeeper says, "Excuse me but you have Left Some Money here."  ');
            res06_fn_0768(1, $11, $26, $16, $F, 0,
              'Do you want to go back and get your Money?');
            LeaveAnswer := ovl07_e13(Title, MenuText, $D, $A, $F, 0, 0);
            if LeaveAnswer = AnswerNo then
              Done := 1
            else
              res06_fn_0DD3(1, $11, $26, $16);
          end
          else
            Done := 1;
        end;
      'G': ovl19_e10(Key);
      'O': ovl19_e10(Key);
    end;
    case Key of
      'B', 'T': res12_fn_27D9;
      'A': if Appraised <> 0 then
             res12_fn_27D9;
    end;
    res12_fn_0767(SelectedCharacter);
  until Done <> 0;
end;

{ Initialisation (ovl06:0798): empty (55 89 E5 5D CB). }
begin
end.

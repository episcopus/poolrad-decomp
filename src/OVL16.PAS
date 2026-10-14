unit OVL16;
{ CharCreate (overlay 16, whitepaper 5.8): creating and training a party member. Its menus ask
  to pick a race, class, gender and alignment ('Pick Race', 'Pick Class', 'Pick Gender',
  'Pick Alignment' in the literal pools at ovl16:04F1..0516), roll the six ability scores and build
  a TCharacter. FreeCharacter frees a character and everything it owns. In progress: most routines
  are still stubs. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES04, RES06, RES09, RES12, OVL17, OVL19, OVL25;
procedure FreeCharacter(Who: PCharacter);
procedure RunCharacterMenu;
procedure ovl16_fn_056C;
procedure ovl16_fn_07E1;
procedure ovl16_fn_07E5;
procedure ovl16_fn_07EA;
procedure ovl16_fn_07EF;
procedure ovl16_fn_07F4;
procedure ovl16_fn_07F9;
procedure ovl16_fn_0808;
procedure ovl16_fn_080D;
procedure ovl16_fn_0812;
procedure ovl16_fn_0875;
procedure ovl16_fn_087A;
procedure ovl16_fn_087F;
procedure ovl16_fn_0884;
procedure ovl16_fn_0889;
procedure ovl16_fn_08A2;
procedure ovl16_fn_08A7;
procedure ovl16_fn_08AC;
procedure ovl16_fn_0AE5;
procedure ovl16_fn_0AEA;
procedure ovl16_fn_0AEF;
procedure ovl16_fn_0AF4;
procedure ovl16_fn_0B48;
procedure ovl16_fn_0B52;
procedure ovl16_fn_1307;
procedure ovl16_fn_1513;
procedure ovl16_fn_1758;
procedure ovl16_fn_19D3;
procedure ovl16_fn_19FB;
procedure ovl16_fn_1A2A;
procedure ovl16_fn_1A51;
procedure ovl16_fn_1A81;
procedure ovl16_fn_1AA7;
procedure ovl16_fn_1ACE;
procedure ovl16_fn_1AF1;
procedure ovl16_fn_1B1A;
procedure ovl16_fn_1B41;
procedure ovl16_fn_1B64;
procedure ovl16_fn_1BAB;
procedure ovl16_fn_1BD2;
procedure ovl16_fn_1BD7;
procedure ovl16_fn_1BF5;
procedure ovl16_fn_1C1E;
procedure ovl16_fn_1C45;
procedure ovl16_fn_1C68;
procedure ovl16_fn_1CD4;
procedure ovl16_fn_1CFB;
procedure ovl16_fn_1D1E;
procedure ovl16_fn_1D84;
procedure ovl16_fn_1DBA;
procedure ovl16_fn_1DCB;
procedure ovl16_fn_1E34;
procedure ovl16_fn_1E5A;
procedure ovl16_fn_1E7D;
procedure ovl16_fn_1EA3;
procedure ovl16_fn_1EB9;
procedure ovl16_fn_1EC6;
procedure DropCharacter;
procedure ovl16_fn_2033;
procedure ovl16_fn_209F;
procedure ovl16_fn_218B;
procedure ovl16_fn_219B;
procedure ovl16_fn_21DA;
procedure ovl16_fn_21E6;
procedure ovl16_fn_2233;
procedure ovl16_fn_234C;
procedure ovl16_fn_23B6;
procedure ovl16_fn_242D;
procedure ovl16_fn_2639;
procedure ovl16_fn_295B;
procedure ovl16_fn_29AE;
procedure ovl16_fn_306D;
procedure ovl16_e2(Uncounted, FreePicture: Boolean);
procedure ovl16_fn_33E7;
procedure ovl16_fn_34DF;
procedure ovl16_fn_35BE;
procedure ovl16_e3;
procedure ovl16_fn_3C75;
procedure ovl16_fn_3C7A;
procedure ovl16_fn_3C7F;
procedure ovl16_fn_3C84;
procedure ovl16_fn_3C89;
procedure ovl16_fn_3C8E;
procedure ovl16_fn_3C93;
procedure ovl16_fn_3D34;
procedure ovl16_fn_3E2A;
procedure ovl16_fn_3E2F;
procedure ovl16_fn_3EBF;
procedure ovl16_fn_3EC4;
procedure ovl16_fn_3EC9;
procedure ovl16_fn_3F31;
procedure ovl16_fn_3FB3;
procedure ovl16_fn_4047;
procedure ovl16_fn_408C;
procedure ovl16_fn_41F8;
procedure ovl16_fn_4235;
procedure ovl16_fn_42ED;
implementation

const
  CombatRecordSize = $16;   { FreeMem size of TCharacter.Combat (TCombatant) }
  ItemListSize = $3F;       { FreeMem size of one item of TCharacter.Items (TMenuLine) }
  AffectSize = 9;           { FreeMem size of one affect of TCharacter.Affects (TAffect) }
  CharacterSize = $11D;     { FreeMem size of a whole TCharacter }
  MenuLeft = 1;             { the function menu window, drawn by DrawWindow in RunCharacterMenu }
  MenuTop = 1;
  MenuRight = $26;
  MenuBottom = $16;
  MenuFirstRow = $C;        { text row of the first function name in the menu }
  HotKeyColour = $F;        { white: the function name's first (hotkey) letter }
  NameColour = $A;          { green: the rest of the function name }
  ChoiceTitleColour = $D;   { the ReadPromptChoice title colour of the menu }
  Var2OfferModify = 680;    { ds49D6^ word: the modify function is offered while it is above 0; unknown }

{ ovl16:0000. Frees a character and everything it owns: its combat state (Combat, size $16), its
  carried items (the list at Items, size $3F) and its affects (the list at Affects, size 9), then
  the character record itself (size $11D) and clears the caller's pointer (Char := nil). }
procedure FreeCharacter(Who: PCharacter);
var
  CurItem: PItem;
  NextItem: PItem;
  CurAffect: PAffect;
  NextAffect: PAffect;
begin
  with Who^ do
  begin
    if Combat <> nil then
      FreeMem(Combat, CombatRecordSize);
    NextItem := Items;
    while NextItem <> nil do
    begin
      CurItem := NextItem;
      NextItem := NextItem^.Next;
      FreeMem(CurItem, ItemListSize);
    end;
    NextAffect := PAffect(Affects);
    while NextAffect <> nil do
    begin
      CurAffect := NextAffect;
      NextAffect := NextAffect^.Next;
      FreeMem(CurAffect, AffectSize);
    end;
  end;
  FreeMem(Who, CharacterSize);
  Who := nil;
end;
{ ovl16:0161. The main menu of the character-creation / training hall (called by ovl03:2E10). It
  draws the window (DrawWindow) and, when a character is selected, its roster (DrawPartyRoster) and
  the eleven function names of the menu at DS:0619 (the first letter in white, the rest in green,
  DrawTextAt). It then asks ReadPromptChoice for a function key (prompt line 'C D M T V A R L S B E J')
  and dispatches it: C create (ovl16_fn_056C), D drop (DropCharacter), M modify (ovl16_fn_209F),
  T train (ovl16_fn_29AE), V view (ViewSelectedCharacter), A add (ovl16_fn_306D), R remove
  (SaveCharacter then ovl16_e2), L load (LoadGame), S save (SaveGame), B buy/finish (sets ds49F3 to
  Mode 4 and leaves), E exit (AskYesNo, then save and QuitGame), J the STING cheat. An extended key
  G or O selects another party member (UpdateSelectedCharacter); E or S clears the heap retry gate
  ds557D. Mode (4) is the value stored in the view mode ds49F3 on B. Local at [bp-5] is unused; the
  frame needs its 9 bytes. }
procedure RunCharacterMenu;
var
  I: Byte;
  Key: Char;
  ExtKey: Byte;
  Done: Byte;
  Unused: string[8];
  Row: ShortInt;
  Show: Byte;
  Mode: Byte;
begin
  TileSet := 3;
  Mode := 4;
  Show := 1;
  ds470C := 0;
  ds49F3 := 0;
  while True do
  begin
    if Show <> 0 then
    begin
      DrawWindow(MenuLeft, MenuTop, MenuRight, MenuBottom, 0, 0, '');
      if SelectedCharacter <> nil then
      begin
        DrawPartyRoster(SelectedCharacter);
        ds0619[1].Present := 1;
        ds0619[2].Present := 1;
        if (ds49D6^[Var2OfferModify] > 0) or (ds470C <> 0) then
          ds0619[3].Present := 1;
        ds0619[4].Present := 1;
        ds0619[6].Present := 1;
        ds0619[7].Present := 0;
        ds0619[8].Present := 1;
        ds0619[9].Present := 1;
      end
      else
      begin
        ds0619[1].Present := 0;
        ds0619[2].Present := 0;
        ds0619[3].Present := 0;
        ds0619[4].Present := 0;
        ds0619[6].Present := 0;
        ds0619[7].Present := 1;
        ds0619[8].Present := 0;
        ds0619[9].Present := 0;
      end;
      Row := 0;
      for I := 0 to 10 do
        if ds0619[I].Present <> 0 then
        begin
          DrawTextAt(2, Row + MenuFirstRow, HotKeyColour, ds0619[I].Name[1]);
          DrawTextAt(3, Row + MenuFirstRow, NameColour, Copy(ds0619[I].Name, 2, Length(ds0619[I].Name) - 1));
          Inc(Row);
        end;
      Show := 0;
    end;
    Key := ReadPromptChoice('Choose a function ', ds05F0, ChoiceTitleColour, 0, 0, 1, 0, ExtKey);
    ClearPromptLine;
    if ExtKey <> 0 then
    begin
      if Key in ['G', 'O'] then
      begin
        UpdateSelectedCharacter(Key);
        DrawPartyRoster(SelectedCharacter);
      end;
    end
    else
    begin
      if not (Key in ['E', 'S']) then
        ds557D := False;
      case Key of
        'C':
          if ds0619[0].Present <> 0 then
            ovl16_fn_056C;
        'D':
          if ds0619[1].Present <> 0 then
            DropCharacter;
        'M':
          if ds0619[2].Present <> 0 then
            ovl16_fn_209F;
        'T':
          if ds0619[3].Present <> 0 then
            ovl16_fn_29AE;
        'V':
          if ds0619[4].Present <> 0 then
            ViewSelectedCharacter(Done);
        'A':
          if ds0619[5].Present <> 0 then
            ovl16_fn_306D;
        'R':
          if ds0619[6].Present <> 0 then
            if SelectedCharacter <> nil then
            begin
              SaveCharacter(SelectedCharacter, '');
              ovl16_e2(False, True);
            end;
        'L':
          if ds0619[7].Present <> 0 then
          begin
            LoadGame;
            if ds49F3 <> 0 then
            begin
              ds49F8 := 1;
              Exit;
            end;
          end;
        'S':
          if ds0619[8].Present <> 0 then
            if ds5D96 <> 0 then
              SaveGame;
        'B':
          if ds0619[9].Present <> 0 then
            if ds5D96 <> 0 then
            begin
              ds49F3 := Mode;
              ClearPromptLine;
              Exit;
            end;
        'E':
          if ds0619[10].Present <> 0 then
          begin
            Key := AskYesNo('Quit to DOS ', $E, $A, $F);
            if Key = 'Y' then
            begin
              while (not ds557D) and (ds5D96 <> 0) do
                SaveGame;
              QuitGame;
            end;
          end;
        'J':
          if ParamStr(1) = 'STING' then
          begin
            ds470C := 1;
            ShowFlashMessage('I Understand, master...');
          end;
      end;
      Show := 1;
    end;
  end;
end;
{ ovl16:056C: frame not read }
{@stub} procedure ovl16_fn_056C; begin end;
{ ovl16:07E1: frame not read }
{@stub} procedure ovl16_fn_07E1; begin end;
{ ovl16:07E5: frame not read }
{@stub} procedure ovl16_fn_07E5; begin end;
{ ovl16:07EA: frame not read }
{@stub} procedure ovl16_fn_07EA; begin end;
{ ovl16:07EF: frame not read }
{@stub} procedure ovl16_fn_07EF; begin end;
{ ovl16:07F4: frame not read }
{@stub} procedure ovl16_fn_07F4; begin end;
{ ovl16:07F9: frame not read }
{@stub} procedure ovl16_fn_07F9; begin end;
{ ovl16:0808: frame not read }
{@stub} procedure ovl16_fn_0808; begin end;
{ ovl16:080D: frame not read }
{@stub} procedure ovl16_fn_080D; begin end;
{ ovl16:0812: frame not read }
{@stub} procedure ovl16_fn_0812; begin end;
{ ovl16:0875: frame not read }
{@stub} procedure ovl16_fn_0875; begin end;
{ ovl16:087A: frame not read }
{@stub} procedure ovl16_fn_087A; begin end;
{ ovl16:087F: frame not read }
{@stub} procedure ovl16_fn_087F; begin end;
{ ovl16:0884: frame not read }
{@stub} procedure ovl16_fn_0884; begin end;
{ ovl16:0889: frame not read }
{@stub} procedure ovl16_fn_0889; begin end;
{ ovl16:08A2: frame not read }
{@stub} procedure ovl16_fn_08A2; begin end;
{ ovl16:08A7: frame not read }
{@stub} procedure ovl16_fn_08A7; begin end;
{ ovl16:08AC: frame not read }
{@stub} procedure ovl16_fn_08AC; begin end;
{ ovl16:0AE5: frame not read }
{@stub} procedure ovl16_fn_0AE5; begin end;
{ ovl16:0AEA: frame not read }
{@stub} procedure ovl16_fn_0AEA; begin end;
{ ovl16:0AEF: frame not read }
{@stub} procedure ovl16_fn_0AEF; begin end;
{ ovl16:0AF4: frame not read }
{@stub} procedure ovl16_fn_0AF4; begin end;
{ ovl16:0B48: frame not read }
{@stub} procedure ovl16_fn_0B48; begin end;
{ ovl16:0B52: frame not read }
{@stub} procedure ovl16_fn_0B52; begin end;
{ ovl16:1307: frame not read }
{@stub} procedure ovl16_fn_1307; begin end;
{ ovl16:1513: frame not read }
{@stub} procedure ovl16_fn_1513; begin end;
{ ovl16:1758: frame not read }
{@stub} procedure ovl16_fn_1758; begin end;
{ ovl16:19D3: frame not read }
{@stub} procedure ovl16_fn_19D3; begin end;
{ ovl16:19FB: frame not read }
{@stub} procedure ovl16_fn_19FB; begin end;
{ ovl16:1A2A: frame not read }
{@stub} procedure ovl16_fn_1A2A; begin end;
{ ovl16:1A51: frame not read }
{@stub} procedure ovl16_fn_1A51; begin end;
{ ovl16:1A81: frame not read }
{@stub} procedure ovl16_fn_1A81; begin end;
{ ovl16:1AA7: frame not read }
{@stub} procedure ovl16_fn_1AA7; begin end;
{ ovl16:1ACE: frame not read }
{@stub} procedure ovl16_fn_1ACE; begin end;
{ ovl16:1AF1: frame not read }
{@stub} procedure ovl16_fn_1AF1; begin end;
{ ovl16:1B1A: frame not read }
{@stub} procedure ovl16_fn_1B1A; begin end;
{ ovl16:1B41: frame not read }
{@stub} procedure ovl16_fn_1B41; begin end;
{ ovl16:1B64: frame not read }
{@stub} procedure ovl16_fn_1B64; begin end;
{ ovl16:1BAB: frame not read }
{@stub} procedure ovl16_fn_1BAB; begin end;
{ ovl16:1BD2: frame not read }
{@stub} procedure ovl16_fn_1BD2; begin end;
{ ovl16:1BD7: frame not read }
{@stub} procedure ovl16_fn_1BD7; begin end;
{ ovl16:1BF5: frame not read }
{@stub} procedure ovl16_fn_1BF5; begin end;
{ ovl16:1C1E: frame not read }
{@stub} procedure ovl16_fn_1C1E; begin end;
{ ovl16:1C45: frame not read }
{@stub} procedure ovl16_fn_1C45; begin end;
{ ovl16:1C68: frame not read }
{@stub} procedure ovl16_fn_1C68; begin end;
{ ovl16:1CD4: frame not read }
{@stub} procedure ovl16_fn_1CD4; begin end;
{ ovl16:1CFB: frame not read }
{@stub} procedure ovl16_fn_1CFB; begin end;
{ ovl16:1D1E: frame not read }
{@stub} procedure ovl16_fn_1D1E; begin end;
{ ovl16:1D84: retf 8062: 8062 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_1D84; begin end;
{ ovl16:1DBA: frame not read }
{@stub} procedure ovl16_fn_1DBA; begin end;
{ ovl16:1DCB: frame not read }
{@stub} procedure ovl16_fn_1DCB; begin end;
{ ovl16:1E34: frame not read }
{@stub} procedure ovl16_fn_1E34; begin end;
{ ovl16:1E5A: frame not read }
{@stub} procedure ovl16_fn_1E5A; begin end;
{ ovl16:1E7D: frame not read }
{@stub} procedure ovl16_fn_1E7D; begin end;
{ ovl16:1EA3: frame not read }
{@stub} procedure ovl16_fn_1EA3; begin end;
{ ovl16:1EB9: frame not read }
{@stub} procedure ovl16_fn_1EB9; begin end;
{ ovl16:1EC6: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_1EC6; begin end;
{ ovl16:1F37. Drops the selected character from the party, the D function of the training-hall menu
  (RunCharacterMenu, ovl16:0161, whose 'Drop' item dispatches it). It asks AskYesNo "Drop <name>
  forever? " and, only when that is answered Y, a second AskYesNo "Are you sure? ". A no at either
  prompt shows the flash message "<name> breathes a sigh of relief." and does nothing else.
  Otherwise it shows "<name> bids you farewell." when the character still counts for combat and
  experience (Flag10D set; whitepaper 5.8) or "You dump <name> out back." when it does not, then
  removes it from the party through ovl16_e2(False, True). No parameters; reads the global
  SelectedCharacter (nothing happens while it is nil); side effects: a flash message and the drop. }
procedure DropCharacter;
var
  Unused: Byte;      { [bp-1]: never read; the original frame carries this spare byte }
begin
  if SelectedCharacter = nil then Exit;
  with SelectedCharacter^ do
  begin
    if (AskYesNo('Drop ' + Name + ' forever? ', $E, $A, $F) = 'Y')
       and (AskYesNo('Are you sure? ', $E, $A, $F) = 'Y') then
    begin
      if Flag10D = 0 then
        ShowFlashMessage('You dump ' + Name + ' out back.')
      else
        ShowFlashMessage(Name + ' bids you farewell.');
      ovl16_e2(False, True);
    end
    else
      ShowFlashMessage(Name + ' breathes a sigh of relief.');
  end;
end;
{ ovl16:2033: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_2033; begin end;
{ ovl16:209F: frame not read }
{@stub} procedure ovl16_fn_209F; begin end;
{ ovl16:218B: frame not read }
{@stub} procedure ovl16_fn_218B; begin end;
{ ovl16:219B: frame not read }
{@stub} procedure ovl16_fn_219B; begin end;
{ ovl16:21DA: frame not read }
{@stub} procedure ovl16_fn_21DA; begin end;
{ ovl16:21E6: frame not read }
{@stub} procedure ovl16_fn_21E6; begin end;
{ ovl16:2233: frame not read }
{@stub} procedure ovl16_fn_2233; begin end;
{ ovl16:234C: frame not read }
{@stub} procedure ovl16_fn_234C; begin end;
{ ovl16:23B6: frame not read }
{@stub} procedure ovl16_fn_23B6; begin end;
{ ovl16:242D: frame not read }
{@stub} procedure ovl16_fn_242D; begin end;
{ ovl16:2639: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_2639; begin end;
{ ovl16:295B: frame not read }
{@stub} procedure ovl16_fn_295B; begin end;
{ ovl16:29AE: retf 0: 0 bytes of parameters; 546 bytes of locals }
{@stub} procedure ovl16_fn_29AE; begin end;
{ ovl16:306D: retf 0: 0 bytes of parameters; 278 bytes of locals }
{@stub} procedure ovl16_fn_306D; begin end;
{ ovl16:3291: retf 4: 4 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl16_e2(Uncounted, FreePicture: Boolean); begin end;
{ ovl16:33E7: retf 0: 0 bytes of parameters; 24 bytes of locals }
{@stub} procedure ovl16_fn_33E7; begin end;
{ ovl16:34DF: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_34DF; begin end;
{ ovl16:35BE: retf 8: 8 bytes of parameters; 40 bytes of locals }
{@stub} procedure ovl16_fn_35BE; begin end;
{ ovl16:382D: frame not read }
{@stub} procedure ovl16_e3; begin end;
{ ovl16:3C75: frame not read }
{@stub} procedure ovl16_fn_3C75; begin end;
{ ovl16:3C7A: frame not read }
{@stub} procedure ovl16_fn_3C7A; begin end;
{ ovl16:3C7F: frame not read }
{@stub} procedure ovl16_fn_3C7F; begin end;
{ ovl16:3C84: frame not read }
{@stub} procedure ovl16_fn_3C84; begin end;
{ ovl16:3C89: frame not read }
{@stub} procedure ovl16_fn_3C89; begin end;
{ ovl16:3C8E: frame not read }
{@stub} procedure ovl16_fn_3C8E; begin end;
{ ovl16:3C93: frame not read }
{@stub} procedure ovl16_fn_3C93; begin end;
{ ovl16:3D34: frame not read }
{@stub} procedure ovl16_fn_3D34; begin end;
{ ovl16:3E2A: frame not read }
{@stub} procedure ovl16_fn_3E2A; begin end;
{ ovl16:3E2F: frame not read }
{@stub} procedure ovl16_fn_3E2F; begin end;
{ ovl16:3EBF: frame not read }
{@stub} procedure ovl16_fn_3EBF; begin end;
{ ovl16:3EC4: frame not read }
{@stub} procedure ovl16_fn_3EC4; begin end;
{ ovl16:3EC9: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_3EC9; begin end;
{ ovl16:3F31: retf 4: 4 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl16_fn_3F31; begin end;
{ ovl16:3FB3: frame not read }
{@stub} procedure ovl16_fn_3FB3; begin end;
{ ovl16:4047: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_4047; begin end;
{ ovl16:408C: frame not read }
{@stub} procedure ovl16_fn_408C; begin end;
{ ovl16:41F8: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_41F8; begin end;
{ ovl16:4235: retf 6: 6 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl16_fn_4235; begin end;
{ ovl16:42ED: retf 8: 8 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl16_fn_42ED; begin end;

begin
end.

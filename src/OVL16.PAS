unit OVL16;
{ CharCreate (overlay 16, whitepaper 5.8): creating and training a party member. Its menus ask
  to pick a race, class, gender and alignment ('Pick Race', 'Pick Class', 'Pick Gender',
  'Pick Alignment' in the literal pools at ovl16:04F1..0516), roll the six ability scores and build
  a TCharacter. FreeCharacter frees a character and everything it owns. In progress: most routines
  are still stubs. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES04, RES06, RES09, RES12, OVL17, OVL19, OVL23, OVL25, OVL28;
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
procedure ModifyCharacter;
procedure ovl16_fn_295B;
procedure ovl16_fn_29AE;
procedure ovl16_fn_306D;
procedure ovl16_e2(Uncounted, FreePicture: Boolean);
procedure ChooseHeadAndBody;
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
function ovl16_fn_3FB3(Who: PCharacter): Byte;
procedure ovl16_fn_4047;
function ovl16_fn_408C(Who: PCharacter): Byte;
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
  and dispatches it: C create (ovl16_fn_056C), D drop (DropCharacter), M modify (ModifyCharacter),
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
            ModifyCharacter;
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
{ ovl16:209F. The Modify (M) function of the training hall, dispatched by RunCharacterMenu
  (ovl16:0161). It refuses a character that already has experience ('<name> can''t be modified.',
  FlashMessageLine), else draws the character sheet and lets the player raise or lower the six
  ability scores and the hit points. The arrow keys move the cursor (Down/Up through Strength
  ..Charisma and the hit-point line) and adjust the value under it (Right raises, Left lowers); a
  value is held between the per-race limits (ds3DA3) and the per-class minimum (ds3F81), a Wisdom
  change recomputes the cleric bonus spells (AddWisdomBonusSpells), and a hit-point change is
  bounded by fn_3FB3 (floor) and fn_408C (ceiling). 'K' (Keep) accepts the changes and leaves, 'E'
  (Exit, or Escape) restores the saved abilities. The nested ShowStat (ovl16:2033) redraws the
  value under the cursor. A `with SelectedCharacter^` block edits the modified character; its
  Experience, Scores (+$10), StrengthPercent, HpMax, Flag11B, Race, ClassMask, B9E, ClassLevels,
  SpellSlots and HirelingShare are used. }
procedure ModifyCharacter;
const
  AbilityCount = 6;             { Strength..Charisma; the cursor's HitPointIndex is the extra step }
  HitPointIndex = 6;            { the hit-point line below Charisma }
  { The BIOS scan codes ReadPromptChoice returns with ExtKey set for the four arrows. }
  ScanUp = #$48;
  ScanDown = #$50;
  ScanLeft = #$4B;
  ScanRight = #$4D;
  KeyEnter = #13;
  KeyKeep = 'K';                { the 'Keep' word of the prompt: accept the changes }
  KeyExit = 'E';                { the 'Exit' word of the prompt: restore the saved abilities }
  KeyNone = #0;                 { what Escape returns }
  { The prompt line (ReadPromptChoice of ovl25): its title, word and hotkey colours; ExtKeys = 1
    accepts the arrow keys. }
  PromptTitleColour = $D;
  PromptWordColour = $A;
  PromptHotColour = $F;
  AcceptExtendedKeys = 1;
  MessageColour = $E;           { the flash message on an experienced character }
  { the hit-point line the cursor's last step shows (DrawHitPoints of res12) }
  HitPointColumn = 4;
  HitPointRow = $12;
  { the column of each ability's minimum and maximum in a 16-byte row of the per-race limits
    ds3DA3: the Strength columns +0/+2/+4 are RaceStrengthMax and RaceStrengthPercent, and
    Intelligence .. Charisma take the columns +6/+7 .. +14/+15. }
  IntMinOffset = 6;
  IntMaxOffset = 7;
  WisMinOffset = 8;
  WisMaxOffset = 9;
  DexMinOffset = 10;
  DexMaxOffset = 11;
  ConMinOffset = 12;
  ConMaxOffset = 13;
  ChaMinOffset = 14;
  ChaMaxOffset = 15;
  ExceptionalStrength = 18;     { a Strength above this uses the exceptional percentile }
  FighterClass = 2;             { only a fighter raises the Strength percentile }
type
  { The modify target: TCharacter from its ability scores on, with the six scores (Strength ..
    Charisma) as an array so the cursor can index them by stat. The offsets match TCharacter's
    (whitepaper 4.2.5): +$10 the scores, +$16 StrengthPercent, +$2E Race, +$2F ClassMask,
    +$32 HpMax, +$85 HirelingShare, +$96 ClassLevels, +$9E B9E, +$B2 SpellSlots, +$11B Flag11B
    (the current hit points). }
  PModifyTarget = ^TModifyTarget;
  TModifyTarget = record
    Pad0: array[0..$F] of Byte;             { +$00..+$0F: Name and the rest of TCharacter }
    Scores: array[0..5] of Byte;            { +$10: Strength, Intelligence, Wisdom, Dexterity,
                                              Constitution, Charisma }
    StrengthPercent: Byte;                  { +$16 }
    Pad17: array[$17..$2D] of Byte;
    Race: ShortInt;                         { +$2E }
    ClassMask: ShortInt;                    { +$2F }
    Age: Word;                              { +$30 }
    HpMax: Byte;                            { +$32 }
    Pad33: array[$33..$84] of Byte;
    HirelingShare: Byte;                    { +$85 }
    Pad86: array[$86..$95] of Byte;
    ClassLevels: array[0..7] of ShortInt;   { +$96..+$9D }
    B9E: ShortInt;                          { +$9E }
    Pad9F: Byte;                            { +$9F }
    PadA0: array[$A0..$B1] of Byte;
    SpellSlots: array[0..1, 1..3] of Byte;  { +$B2..+$B7 }
    PadB8: array[$B8..$11A] of Byte;
    Flag11B: Byte;                          { +$11B: the current hit points }
  end;
var
  SavedScores: array[0..5] of Byte;   { [bp-6..bp-1]: the scores as they were on entry }
  SavedStrengthPercent: Byte;         { [bp-7]: the exceptional Strength on entry }
  SavedHpMax: Byte;                   { [bp-8]: the maximum hit points on entry }
  Spare: Byte;                        { [bp-9]: the original frame reserves this byte, never read }
  Stat: ShortInt;                     { [bp-0xa]: the ability under the cursor / the restore loop }
  Key: Char;                          { [bp-0xb]: the key ReadPromptChoice returned }
  ExtKey: Byte;                       { [bp-0xc]: nonzero when Key is an extended key }
  StatIndex: Byte;                    { [bp-0xd]: the cursor: 0..5 an ability, 6 the hit-point line }
  Spare2: array[0..6] of Byte;        { [bp-0xe..bp-0x14]: the original frame reserves these, never read }

  { ovl16:2033 (nested). Redraws the value under the cursor: ability StatIndex through
    ShowAbilityScore (ovl19:0901), or the hit-point line through DrawHitPoints (00BA:0973) when
    StatIndex is HitPointIndex. Highlight is passed to both (false clears the highlight). It reads
    the parent's StatIndex and the global SelectedCharacter. }
  procedure ShowStat(Highlight: Boolean);
  begin
    if StatIndex < AbilityCount then
      ShowAbilityScore(StatIndex, Highlight)
    else
      DrawHitPoints(SelectedCharacter, HitPointColumn, HitPointRow, Byte(Highlight));
  end;

begin
  if SelectedCharacter^.Experience > 0 then
  begin
    FlashMessageLine(SelectedCharacter^.Name + ' can''t be modified.', MessageColour);
    Exit;
  end;
  ShowCharacterSheet;
  Move(PModifyTarget(SelectedCharacter)^.Scores, SavedScores, AbilityCount);
  SavedStrengthPercent := SelectedCharacter^.StrengthPercent;
  SavedHpMax := SelectedCharacter^.HpMax;
  StatIndex := HitPointIndex;
  ShowStat(False);
  StatIndex := 0;
  ShowStat(True);
  with PModifyTarget(SelectedCharacter)^ do
  begin
    repeat
    Key := ReadPromptChoice('Modify character: ', 'Keep Exit',
      PromptTitleColour, PromptWordColour, PromptHotColour, AcceptExtendedKeys, 0, ExtKey);
    ShowStat(False);
    if ExtKey <> 0 then
    begin
      case Key of
        ScanDown, KeyEnter:
        begin
          Inc(StatIndex);
          if StatIndex > HitPointIndex then
            StatIndex := 0;
        end;
        ScanUp:
        begin
          Dec(StatIndex);
          if StatIndex = $FF then
            StatIndex := HitPointIndex;
        end;
        ScanLeft:
        begin
          if StatIndex < AbilityCount then
          begin
            Stat := StatIndex;
            Dec(Scores[Stat]);
            case Stat of
              0:
                if StrengthPercent > 0 then
                begin
                  Dec(StrengthPercent);
                  Inc(Scores[Stat]);
                end
                else if (Scores[Stat] < ds3DA3[Race, B9E])
                     or (Scores[Stat] < ds3F81[ClassMask, 0]) then
                  Scores[Stat] := ds3DA3[Race, B9E];
              1:
                if (Scores[Stat] < ds3DA3[Race, IntMinOffset])
                   or (Scores[Stat] < ds3F81[ClassMask, 1]) then
                  Scores[Stat] := ds3DA3[Race, IntMinOffset];
              2:
                begin
                  if (Scores[Stat] < ds3DA3[Race, WisMinOffset])
                     or (Scores[Stat] < ds3F81[ClassMask, 2]) then
                    Scores[Stat] := ds3DA3[Race, WisMinOffset];
                  if SpellSlots[0, 1] > 0 then
                    SpellSlots[0, 1] := 1;
                  AddWisdomBonusSpells(SelectedCharacter);
                end;
              3:
                if (Scores[Stat] < ds3DA3[Race, DexMinOffset])
                   or (Scores[Stat] < ds3F81[ClassMask, 3]) then
                  Scores[Stat] := ds3DA3[Race, DexMinOffset];
              4:
                begin
                  if (Scores[Stat] < ds3DA3[Race, ConMinOffset])
                     or (Scores[Stat] < ds3F81[ClassMask, 4]) then
                    Scores[Stat] := ds3DA3[Race, ConMinOffset];
                  if ovl16_fn_408C(SelectedCharacter) < HpMax then
                    HpMax := ovl16_fn_408C(SelectedCharacter);
                  Flag11B := HpMax;
                  StatIndex := HitPointIndex;
                  ShowStat(False);
                  StatIndex := 4;
                end;
              5:
                if (Scores[Stat] < ds3DA3[Race, ChaMinOffset])
                   or (Scores[Stat] < ds3F81[ClassMask, 5]) then
                  Scores[Stat] := ds3DA3[Race, ChaMinOffset];
            end;
          end
        else
        begin
          Dec(HpMax);
          if ovl16_fn_3FB3(SelectedCharacter) > HpMax then
            HpMax := ovl16_fn_3FB3(SelectedCharacter);
          Flag11B := HpMax;
        end;
      end;
        ScanRight:
        begin
          if StatIndex < AbilityCount then
          begin
            Stat := StatIndex;
            Inc(Scores[Stat]);
            case Stat of
              0:
                if Scores[Stat] > RaceStrengthMax[Race, B9E] then
                begin
                  if (Scores[Stat] > ExceptionalStrength)
                     and (ClassLevels[FighterClass] > 0)
                     and (RaceStrengthPercent[Race, B9E] > StrengthPercent) then
                    Inc(StrengthPercent);
                  Scores[Stat] := RaceStrengthMax[Race, B9E];
                end;
              1:
                if Scores[Stat] > ds3DA3[Race, IntMaxOffset] then
                  Scores[Stat] := ds3DA3[Race, IntMaxOffset];
              2:
                begin
                  if Scores[Stat] > ds3DA3[Race, WisMaxOffset] then
                    Scores[Stat] := ds3DA3[Race, WisMaxOffset];
                  if SpellSlots[0, 1] > 0 then
                    SpellSlots[0, 1] := 1;
                  AddWisdomBonusSpells(SelectedCharacter);
                end;
              3:
                if Scores[Stat] > ds3DA3[Race, DexMaxOffset] then
                  Scores[Stat] := ds3DA3[Race, DexMaxOffset];
              4:
                begin
                  if Scores[Stat] > ds3DA3[Race, ConMaxOffset] then
                    Scores[Stat] := ds3DA3[Race, ConMaxOffset];
                  if ovl16_fn_3FB3(SelectedCharacter) > HpMax then
                    HpMax := ovl16_fn_3FB3(SelectedCharacter);
                  Flag11B := HpMax;
                  StatIndex := HitPointIndex;
                  ShowStat(False);
                  StatIndex := 4;
                end;
              5:
                if Scores[Stat] > ds3DA3[Race, ChaMaxOffset] then
                  Scores[Stat] := ds3DA3[Race, ChaMaxOffset];
            end;
          end
          else
          begin
            Inc(HpMax);
            if ovl16_fn_408C(SelectedCharacter) < HpMax then
              HpMax := ovl16_fn_408C(SelectedCharacter);
            Flag11B := HpMax;
          end;
      end;
      end;
    end
    else
      case Key of
        KeyExit, KeyNone:
        begin
          for Stat := 0 to AbilityCount - 1 do
            PModifyTarget(SelectedCharacter)^.Scores[Stat] := SavedScores[Stat];
          SelectedCharacter^.StrengthPercent := SavedStrengthPercent;
          SelectedCharacter^.HpMax := SavedHpMax;
          SelectedCharacter^.Flag11B := HpMax;
          RecalcCombatValues(SelectedCharacter);
          Exit;
        end;
      end;
    RecalcCombatValues(SelectedCharacter);
    ShowCombatStats;
    ShowStat(True);
    until (ExtKey = 0) and (Key = KeyKeep);
    SelectedCharacter^.HirelingShare := 1;
  end;
end;
{ ovl16:295B: frame not read }
{@stub} procedure ovl16_fn_295B; begin end;
{ ovl16:29AE: retf 0: 0 bytes of parameters; 546 bytes of locals }
{@stub} procedure ovl16_fn_29AE; begin end;
{ ovl16:306D: retf 0: 0 bytes of parameters; 278 bytes of locals }
{@stub} procedure ovl16_fn_306D; begin end;
{ ovl16:3291: retf 4: 4 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl16_e2(Uncounted, FreePicture: Boolean); begin end;
{ ovl16:33E7. The head/body step of character creation (the "Head Body Keep" prompt of the create
  flow, whitepaper 5.8): it shows the selected character's HEAD and BODY pictures (ShowHeadBodyWindow)
  and asks ReadPromptChoice for a key. H or B steps the HeadBank (+$BB) or the BodyBank (+$BC) through
  the picture numbers DS:286F and DS:287D, wrapping above $E and $C back to 1; K keeps the two banks as
  they are now. Any other key (Escape included) leaves the banks alone and shows the prompt again: only
  K leaves the loop. The banks that were current on entry are restored at the end unless the last K
  kept the current ones. No parameters; works on SelectedCharacter. Side effects: the head/body window,
  the prompt line and the two pictures. }
procedure ChooseHeadAndBody;
const
  MaxHeadBank = $E;   { the highest HeadBank the picture table DS:286F (14 entries) offers }
  MaxBodyBank = $C;   { the highest BodyBank the picture table DS:287D offers }
  { The prompt line colours (ReadPromptChoice of ovl25). }
  PromptTitleColour = 0;    { the title is empty, so its colour does not matter }
  PromptWordColour = $F;    { white: the letters of the words 'Head Body Keep' }
  PromptHotColour = $A;     { green: the words' capitals 'H', 'B', 'K' and the highlight }
  PromptExtKeys = 0;        { the extended keys are not accepted }
  PromptAnimate = 0;        { the caller does not ask for the picture animation }
var
  Key: Char;               { [bp-1]: the key ReadPromptChoice returned }
  ExtKey: Byte;            { [bp-2]: nonzero when Key is an extended key }
  SavedHeadBank: Byte;     { [bp-3]: the HeadBank that was current on entry }
  SavedBodyBank: Byte;     { [bp-4]: the BodyBank that was current on entry }
begin
  with SelectedCharacter^ do
  begin
    SavedHeadBank := HeadBank;
    SavedBodyBank := BodyBank;
    repeat
      ShowHeadBodyWindow;
      Key := ReadPromptChoice('', 'Head Body Keep', PromptTitleColour, PromptWordColour,
        PromptHotColour, PromptExtKeys, PromptAnimate, ExtKey);
      if ExtKey = 0 then
        case Key of
          'H':
            if HeadBank < MaxHeadBank then Inc(HeadBank) else HeadBank := 1;
          'B':
            if BodyBank < MaxBodyBank then Inc(BodyBank) else BodyBank := 1;
          'K':
            begin
              SavedHeadBank := HeadBank;
              SavedBodyBank := BodyBank;
            end;
        end;
    until Key = 'K';
    HeadBank := SavedHeadBank;
    BodyBank := SavedBodyBank;
  end;
  ClearPromptLine;
end;
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
{@stub} function ovl16_fn_3FB3(Who: PCharacter): Byte; begin end;
{ ovl16:4047: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_4047; begin end;
{ ovl16:408C: frame not read }
{@stub} function ovl16_fn_408C(Who: PCharacter): Byte; begin end;
{ ovl16:41F8: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl16_fn_41F8; begin end;
{ ovl16:4235: retf 6: 6 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl16_fn_4235; begin end;
{ ovl16:42ED: retf 8: 8 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl16_fn_42ED; begin end;

begin
end.

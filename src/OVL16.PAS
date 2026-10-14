unit OVL16;
{ CharCreate (overlay 16, whitepaper 5.8): creating and training a party member. Its menus ask
  to pick a race, class, gender and alignment ('Pick Race', 'Pick Class', 'Pick Gender',
  'Pick Alignment' in the literal pools at ovl16:04F1..0516), roll the six ability scores and build
  a TCharacter. FreeCharacter frees a character and everything it owns. In progress: most routines
  are still stubs. }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS, RES04, RES06, RES07, RES09, RES12, OVL17, OVL19, OVL23, OVL24, OVL25, OVL28, OVL32;
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
procedure AddSavedCharacters;
procedure RemoveSelectedCharacter(Uncounted, FreePicture: Boolean);
procedure ChooseHeadAndBody;
procedure DrawIconCell(CellCol, CellRow: Byte; StaticLink: Word);
procedure CopyPictureSlot(Source, Dest, Recolor: Byte; StaticLink: Word);
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
function ConstitutionHitPointAdjustment(Who: PCharacter): ShortInt;
function MinHitPoints(Who: PCharacter): Byte;
function MaxHitPoints(Who: PCharacter): Byte;
function RollHitPoints(Who: PCharacter; ClassBits: Byte): Byte;
procedure PayGold(Amount: LongInt; Who: PCharacter);
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
  GoldInCopper = 200;       { one gold piece is 200 copper (CoinCopperValues[GoldCoin]) }

type
  { The five coin kinds, in the order of CoinCopperValues (copper 0 .. platinum 4). The money routine
    42ED walks it with Succ and Pred, which is the enumerated type the original used (its
    `mov al,x; inc al` / `dec al` is the Succ/Pred codegen, tools/re/tp_idioms/ovl16/PAYPRB2.PAS). }
  TCoinKind = (CopperCoin, SilverCoin, ElectrumCoin, GoldCoin, PlatinumCoin);

  { An in-memory picture as ovl32 loads it: the tile byte size at +$11, the pointer to the packed
    pixel buffer at +$13 and the copied tile bytes (the tail) at +$17. The same layout as ovl32's
    private TMemPic, declared here because ovl16 needs it too (like ovl17's copy). }
  PMemPic = ^TMemPic;
  TMemPic = record
    Head: array[0..$10] of Byte;    { +0..+$10: the picture header (height, width, item count) }
    ByteSize: Word;                 { +$11: bytes per tile }
    Pixels: ^Byte;                  { +$13: the packed pixel bytes }
    Tail: array[0..20000] of Byte;  { +$17: the tile bytes, indexed by a byte times ByteSize }
  end;

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
  T train (ovl16_fn_29AE), V view (ViewSelectedCharacter), A add (AddSavedCharacters), R remove
  (SaveCharacter then RemoveSelectedCharacter), L load (LoadGame), S save (SaveGame), B buy/finish (sets ds49F3 to
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
            AddSavedCharacters;
        'R':
          if ds0619[6].Present <> 0 then
            if SelectedCharacter <> nil then
            begin
              SaveCharacter(SelectedCharacter, '');
              RemoveSelectedCharacter(False, True);
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
  removes it from the party through RemoveSelectedCharacter(False, True). No parameters; reads the global
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
      RemoveSelectedCharacter(False, True);
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
                  if MaxHitPoints(SelectedCharacter) < HpMax then
                    HpMax := MaxHitPoints(SelectedCharacter);
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
          if MinHitPoints(SelectedCharacter) > HpMax then
            HpMax := MinHitPoints(SelectedCharacter);
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
                  if MinHitPoints(SelectedCharacter) > HpMax then
                    HpMax := MinHitPoints(SelectedCharacter);
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
            if MaxHitPoints(SelectedCharacter) < HpMax then
              HpMax := MaxHitPoints(SelectedCharacter);
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
{ ovl16:306D. The Add (A) function of the training hall, dispatched by RunCharacterMenu (ovl16:0161):
  it clears the function window, lists the saved characters on disk (ReadSavedCharacterList) and runs
  the menu "Add a character: " with "Add Exit" (ChooseFromList). Enter or A loads the highlighted
  character's record (GetMem, LoadCharacterFile) and, when its menu line does not already start with
  '*', prefixes '* ' and tries to put it in the party. A character already in the party (same Name and
  BAB, +$AB) is refused; a player-run member (B84 below $80) is refused once six are in the party, and
  a computer-run member (B84 $80 and up, a hireling) once the party size ds49D6^[VarPartySize] is
  eight. A refused record is freed (FreeMem); the party records themselves are freed elsewhere. The
  menu repeats until E, Escape or a full party. The edited list is written back
  (RewriteSavedCharacterList, ovl17) and freed (FreeMenuList, ovl25). No parameters; side effects: the
  function window, the menu, the heap and the saved-character list file.
  QUIRK ovl16:30E8: the ChooseFromList WithExit argument is read from [bp-0x14], a local the routine
  never assigns (whatever the previous frame left there). }
procedure AddSavedCharacters;
const
  VarPartySize = 830;           { the party member count, a word of the ds49D6 game variable block }
  ComputerRun = $80;            { high bit of B84: the computer runs the member (hireling) }
  MaxPlayerMembers = 6;         { the menu stops once six player-run members are in the party }
  MaxPartySize = 8;             { the menu stops once the party holds eight members }
  KeyEnter = #13;               { ChooseFromList returns Enter, or the chosen word's letter }
  KeyAdd = 'A';                 { the 'Add' word of the prompt }
  KeyExit = 'E';                { the 'Exit' word of the prompt; Escape returns #0 }
var
  List: PMenuLine;              { [bp-4]: the saved-character list ReadSavedCharacterList built }
  Selected: PMenuLine;          { [bp-8]: the highlighted line of that list }
  NewChar: PCharacter;          { [bp-0xc]: the record GetMem allocated for the chosen character }
  Who: PCharacter;              { [bp-0x10]: the party list walk }
  Choice: Integer;              { [bp-0x12]: ChooseFromList's var Choice }
  Key: Char;                    { [bp-0x13]: the key ChooseFromList returned }
  WithExit: Byte;               { [bp-0x14]: ChooseFromList's WithExit (QUIRK: never assigned) }
  Redraw: Byte;                 { [bp-0x15]: ChooseFromList's var Redraw }
  Count: Byte;                  { [bp-0x16]: the player-run members found in the party list }
begin
  ClearWindow(1, 1, $26, $16);
  ReadSavedCharacterList(List);
  if List = nil then Exit;
  Choice := 0;
  Selected := List;
  Redraw := 1;
  repeat
    Key := ChooseFromList('Add a character: ', 'Add Exit', $D, $A, $F, 1, 2, $26, $16,
      List, WithExit, Redraw, Choice, Selected);
    if (Key = KeyEnter) or (Key = KeyAdd) then
      if Selected^.Text[1] <> '*' then
      begin
        GetMem(NewChar, CharacterSize);
        LoadCharacterFile(Selected^.Text, NewChar, 0, 1);
        Selected^.Text := '* ' + Selected^.Text;
        Count := 0;
        if PCharacter(ds5D96) = nil then
        begin
          ds49D6^[VarPartySize] := 0;
          AddPartyMember(NewChar);
          BuildCharacterIcon(True);
        end
        else
        begin
          Who := PCharacter(ds5D96);
          while (Who <> nil)
                and ((Who^.Name <> NewChar^.Name) or (Who^.BAB <> NewChar^.BAB)) do
          begin
            if Who^.B84 < ComputerRun then
              Inc(Count);
            Who := Who^.Next;
          end;
          if (Who = nil)
             and (((NewChar^.B84 < ComputerRun) and (Count < MaxPlayerMembers))
                  or ((NewChar^.B84 > ComputerRun - 1)
                      and (ds49D6^[VarPartySize] < MaxPartySize))) then
          begin
            AddPartyMember(NewChar);
            BuildCharacterIcon(True);
            if NewChar^.B84 < ComputerRun then
              Inc(Count);
          end
          else
            FreeMem(NewChar, CharacterSize);
        end;
      end;
  until (Key = KeyExit) or (Key = #0) or (Count > MaxPlayerMembers - 1)
    or (ds49D6^[VarPartySize] > MaxPartySize - 1);
  RewriteSavedCharacterList(List);
  FreeMenuList(List);
end;
{ ovl16:3291. Removes a character from the party list (the head is ds5D96, linked by TCharacter.Next
  at +$104) and frees its record. It walks the list from the head to the member before
  SelectedCharacter (or finds SelectedCharacter itself at the head). When Uncounted is false (the
  member counted in the party size), it lowers the party size ds49D6^[VarPartySize]; an extra combatant
  passes Uncounted true and leaves the count alone. FreePicture frees the member's combat icon picture
  slot (CombatIcon, +$BF) first. The head is replaced by its Next; a middle member is unlinked from its
  predecessor, and SelectedCharacter becomes the member that took its place (its successor at the head,
  its predecessor otherwise). Called on drop, load, battle removal and party reorder. }
procedure RemoveSelectedCharacter(Uncounted, FreePicture: Boolean);
const
  VarPartySize = 830;   { the party member count, a word of the ds49D6 game variable block }
var
  Cur: PCharacter;      { [bp-4]: the list node examined; the predecessor when the member is found }
begin
  if PCharacter(ds5D96) = nil then Exit;
  Cur := PCharacter(ds5D96);
  if Cur <> SelectedCharacter then
  begin
    while (Cur^.Next <> SelectedCharacter) and (Cur^.Next <> nil) do
      Cur := Cur^.Next;
    if Cur^.Next <> nil then
    begin
      if FreePicture then
        FreePictureSlot(SelectedCharacter^.CombatIcon);
      Cur^.Next := SelectedCharacter^.Next;
      FreeCharacter(SelectedCharacter);
      SelectedCharacter := Cur;
      if not Uncounted then
        Dec(ds49D6^[VarPartySize]);
    end;
  end
  else
  begin
    if FreePicture then
      FreePictureSlot(SelectedCharacter^.CombatIcon);
    PCharacter(ds5D96) := SelectedCharacter^.Next;
    Cur := SelectedCharacter^.Next;
    FreeCharacter(SelectedCharacter);
    SelectedCharacter := Cur;
    if not Uncounted then
      Dec(ds49D6^[VarPartySize]);
  end;
end;
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
{ ovl16:34DF. Draws one cell of the character-icon editor: it fills the cell (FillPictureRect, 12
  cells wide and 24 pixel rows tall, from the palette at @ds260A into DrawBuf) and draws the two
  mirrored halves of the character's icon (DrawIcon) at columns CellCol and CellCol + 3, row CellRow.
  On the text-only adapter (VideoAdapter 0) the fill uses colour 3 (the icon's ground) and only the
  head pictures (index $C) are drawn; on the other adapters the fill uses colour 0 and the body
  pictures (index $19) are drawn first. FlushPictureChanges shows the result. Called by the icon
  editor ovl16_e3. The original reaches the routine through a nested call (push bp; push cs; call), so
  its last parameter is a static link the body never reads. }
procedure DrawIconCell(CellCol, CellRow: Byte; StaticLink: Word);
const
  IconColsPerCell = 3;    { an icon cell is 3 text columns wide }
  CellWidthCells = $C;    { FillPictureRect width, in 8-pixel cells }
  CellHeightRows = $18;   { FillPictureRect height, in pixel rows }
  SecondHalfCol = 3;      { the mirrored-half icon is 3 columns right }
  GroundColour = 3;       { the icon's ground colour on VideoAdapter 0 }
  BodyPicIndex = $19;     { the BODY picture block of the icon }
  HeadPicIndex = $C;      { the HEAD picture block of the icon }
  IconSet = 0;            { the icon set DrawIcon reads the pictures from }
begin
  if VideoAdapter = 0 then
    FillPictureRect(CellCol * IconColsPerCell, CellRow * CellHeightRows, CellWidthCells,
      CellHeightRows, GroundColour, @ds260A, DrawBuf)
  else
  begin
    FillPictureRect(CellCol * IconColsPerCell, CellRow * CellHeightRows, CellWidthCells,
      CellHeightRows, 0, @ds260A, DrawBuf);
    DrawIcon(CellCol, CellRow, IconSet, 0, BodyPicIndex);
    DrawIcon(CellCol + SecondHalfCol, CellRow, IconSet, 1, BodyPicIndex);
  end;
  DrawIcon(CellCol, CellRow, IconSet, 0, HeadPicIndex);
  DrawIcon(CellCol + SecondHalfCol, CellRow, IconSet, 1, HeadPicIndex);
  FlushPictureChanges;
end;
{ ovl16:35BE. Copies one picture slot of the character-icon table DS:5E5A into another: both halves
  (the identical half at FirstPic and the mirrored half at SecondPic) get their tile bytes (the tail
  at +$17) and their packed pixel bytes (the buffer Pixels points at, +$13) copied from Source into
  Dest. ByteSize (the word at +$11) gives the tile size; on the EGA adapter (VideoAdapter 1) the
  pixel buffer holds a quarter of that. When Recolor is set the copied destination icon is recoloured
  with the selected character's six colour pairs (Figure[1..6] through ds3CF5), exactly the
  recolouring BuildCharacterIcon (ovl17:0482) applies. Called by the icon editor ovl16_e3 (its Source
  is the character's CombatIcon) and by ovl16_fn_3E2F. The original reaches it through a nested call
  (push bp; push cs; call), so its last parameter is a static link the body never reads. }
procedure CopyPictureSlot(Source, Dest, Recolor: Byte; StaticLink: Word);
var
  I: Byte;                          { [bp-1]: loop index over the colour map }
  Spare: Byte;                      { [bp-2]: the original frame reserves this byte, never read }
  MapFrom: array[0..15] of Byte;    { [bp-0x12..bp-3]: the icon's source colours (the identity map) }
  MapTo: array[0..15] of Byte;      { [bp-0x22..bp-0x13]: the destination colour of each source colour }
  PixelBytes: Word;                 { [bp-0x24]: the pixel-buffer size copied }
begin
  PixelBytes := PMemPic(ds5E5A[Dest].FirstPic)^.ByteSize;
  if VideoAdapter = 1 then
    PixelBytes := PixelBytes shr 1 shr 1;
  Move(PMemPic(ds5E5A[Source].FirstPic)^.Tail, PMemPic(ds5E5A[Dest].FirstPic)^.Tail,
    PMemPic(ds5E5A[Dest].FirstPic)^.ByteSize);
  Move(PMemPic(ds5E5A[Source].SecondPic)^.Tail, PMemPic(ds5E5A[Dest].SecondPic)^.Tail,
    PMemPic(ds5E5A[Dest].SecondPic)^.ByteSize);
  Move(PMemPic(ds5E5A[Source].FirstPic)^.Pixels^, PMemPic(ds5E5A[Dest].FirstPic)^.Pixels^, PixelBytes);
  Move(PMemPic(ds5E5A[Source].SecondPic)^.Pixels^, PMemPic(ds5E5A[Dest].SecondPic)^.Pixels^, PixelBytes);
  if Recolor <> 0 then
    with SelectedCharacter^ do
    begin
      for I := 0 to 15 do
      begin
        MapFrom[I] := I;
        MapTo[I] := I;
      end;
      for I := 1 to 6 do
      begin
        MapTo[ds3CF5[I]] := Figure[I] and $0F;
        MapTo[ds3CF5[I] + 8] := (Figure[I] and $F0) shr 4;
      end;
      RemapPictureColours(@MapFrom, @MapTo, 0, 0, ds5E5A[Dest].FirstPic);
      RemapPictureColours(@MapFrom, @MapTo, 0, 0, ds5E5A[Dest].SecondPic);
    end;
end;
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
{ ovl16:3F31. The constitution hit-point adjustment shared by the hit-point floor MinHitPoints and
  the ceiling MaxHitPoints of ModifyCharacter (ovl16:209F). It sums ConstitutionHitPointTable[Constitution] over the
  eight classes the character has a level in (ClassLevels[I], +$96, signed, above 0), then adds the
  fighter bonus: one more for a fighter (ClassMask = 2) above constitution 16 and a second above 17
  (the AD&D 1e fighter constitution bonus). The `with Who^` evaluates the parameter once into a
  hidden local; the result is the signed total (it can be negative for a low constitution). }
function ConstitutionHitPointAdjustment(Who: PCharacter): ShortInt;
var
  Sum: ShortInt;
  I: ShortInt;
  Spare: Byte;   { [bp-4]: the original frame carries this byte, never read or written }
begin
  Sum := 0;
  with Who^ do
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Sum, ConstitutionHitPointTable[Constitution]);
        if Constitution > 16 then
          if ClassMask = 2 then
            Inc(Sum);
        if Constitution > 17 then
          if ClassMask = 2 then
            Inc(Sum);
      end;
  ConstitutionHitPointAdjustment := Sum;
end;
{ ovl16:3FB3. The minimum hit points a character's HpMax may be trained down to; the floor
  counterpart of the ceiling MaxHitPoints, both called by ModifyCharacter (ovl16:209F). Over the
  eight classes the character has a level in (ClassLevels[I], +$96, signed, above 0) it counts the
  hit dice (Count) and totals their levels into Total, adding one level for class 4 and class 7
  (whose maximum die is one higher, see ovl16:408C). It then divides Total plus the constitution
  adjustment (ConstitutionHitPointAdjustment, which may be negative) by Count; a negative adjustment
  Total cannot absorb (Total at most its magnitude plus Count) clamps the result to 1, so the floor
  is never below 1. The `with Who^` evaluates the parameter once. No side effects. }
function MinHitPoints(Who: PCharacter): Byte;
var
  Count: Byte;         { [bp-2]: the classes the character has a level in }
  Adjustment: ShortInt;{ [bp-3]: the constitution hit-point adjustment (ConstitutionHitPointAdjustment) }
  Total: Byte;         { [bp-4]: the summed hit-dice levels, then the divided result }
  I: ShortInt;         { [bp-5]: class index 0..7 }
begin
  with Who^ do
  begin
    Count := 0;
    Total := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Total, ClassLevels[I]);
        Inc(Count);
        case I of
          4: Inc(Total);
          7: Inc(Total);
        end;
      end;
  end;
  Adjustment := ConstitutionHitPointAdjustment(Who);
  if Adjustment < 0 then
  begin
    if Total > Abs(Adjustment) + Count then
      Total := (Total + Adjustment) div Count
    else
      Total := 1;
  end
  else
    Total := (Total + Adjustment) div Count;
  MinHitPoints := Total;
end;
{ ovl16:408C. The maximum hit points of Who, the ceiling counterpart of MinHitPoints
   (ovl16:3FB3) and both called by ModifyCharacter (ovl16:209F). Over the eight classes the
   character has a level in (ClassLevels[I], +$96, signed, above 0) it totals the levels times the
   maximum hit die of each class (8 cleric and druid, 10 fighter and paladin, 8 ranger, 4
   magic-user, 6 thief, 4 monk; one extra die-worth for class 4 ranger and class 7 monk) and counts
   the classes; it then divides the total plus the constitution adjustment by the class count and
   never returns below 1. QUIRK ovl16:41B8: the constitution adjustment is taken from the global
   SelectedCharacter (DS:5D92), not from Who, although every caller passes SelectedCharacter. The
   `with Who^` evaluates the parameter once into a hidden local. No side effects. }
function MaxHitPoints(Who: PCharacter): Byte;
var
  Count: Byte;          { [bp-2]: the classes the character has a level in }
  Total: Byte;          { [bp-3]: the summed maximum hit points, then the divided result }
  Adjustment: ShortInt; { [bp-4]: the constitution hit-point adjustment (ConstitutionHitPointAdjustment) }
  I: ShortInt;          { [bp-5]: class index 0..7 }
begin
  with Who^ do
  begin
    Count := 0;
    Total := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Count);
        case I of
          0: Inc(Total, ClassLevels[I] * 8);
          1: Inc(Total, ClassLevels[I] * 8);
          2: Inc(Total, ClassLevels[I] * 10);
          3: Inc(Total, ClassLevels[I] * 10);
          4: Inc(Total, (ClassLevels[I] + 1) * 8);
          5: Inc(Total, ClassLevels[I] * 4);
          6: Inc(Total, ClassLevels[I] * 6);
          7: Inc(Total, (ClassLevels[I] + 1) * 4);
        end;
      end;
  end;
  Adjustment := ConstitutionHitPointAdjustment(SelectedCharacter);
  if Adjustment < 0 then
  begin
    if Total > Abs(Adjustment) + Count then
      Total := (Total + Adjustment) div Count
    else
      Total := 1;
  end
  else
    Total := (Total + Adjustment) div Count;
  MaxHitPoints := Total;
end;
{ ovl16:4235. Rolls the hit points a level gains for the classes in ClassBits: over the eight classes
   it adds, for each class the character has a level in (ClassLevels, +$96, signed, above 0) whose
   bit is in ClassBits (ds05DE, one bit per class), a roll of ClassHitDiceCount[I] dice of
   ClassHitDieSides[I] sides (RollDice, ovl24:0DE3), where a class at level 1 rolls at least two
   thirds of its hit die (the first-level minimum). The caller divides the sum by the number of
   classes with a level. Called by the training hall (ovl16:29AE, whitepaper 5.8) and the
   create-character run (ovl16:1D1E). No side effects but the random rolls. }
function RollHitPoints(Who: PCharacter; ClassBits: Byte): Byte;
var
  ClassRoll: Byte;   { [bp-2]: the roll for one class }
  Sum: Byte;         { [bp-3]: the summed rolls, the result }
  I: ShortInt;       { [bp-4]: class index 0..7 }
begin
  Sum := 0;
  for I := 0 to 7 do
    if (Who^.ClassLevels[I] > 0) and ((ds05DE[I] and ClassBits) > 0) then
    begin
      ClassRoll := RollDice(ClassHitDiceCount[I], ClassHitDieSides[I]);
      if Who^.ClassLevels[I] = 1 then
        if ClassRoll < (ClassHitDieSides[I] * 2) div 3 then
          ClassRoll := (ClassHitDieSides[I] * 2) div 3;
      Inc(Sum, ClassRoll);
    end;
  RollHitPoints := Sum;
end;
{ ovl16:42ED. Takes Amount gold pieces from Who's money (the training-hall cost, ovl16:29AE): the
   amount is converted to copper (times GoldInCopper), then coin by coin from copper up it hands
   over Amount div CoinCopperValues[Kind] + 1 coins (one more than the remainder needs, so the
   hand-over always overshoots) capped at the coins Who holds, and gives the overshoot back as
   change kind by kind from platinum down (Amount div CoinCopperValues[Kind] coins). QUIRK
   ovl16:432A: the kind is not bounded, so a character who cannot cover the amount walks on into
   Money[5..6] (gems and jewelry) and reads CoinCopperValues past its five entries, and when a kind
   has no coins left the hand-over of zero coins starts the loop again. The `with Who^` evaluates
   the parameter once. }
procedure PayGold(Amount: LongInt; Who: PCharacter);
var
  Coins: Word;       { [bp-2]: the coins of one kind handed over or given back }
  Kind: TCoinKind;   { [bp-3]: the coin kind, copper 0 .. platinum 4 }
begin
  Amount := Amount * GoldInCopper;
  Kind := CopperCoin;
  with Who^ do
  begin
    while Amount > 0 do
    begin
      Coins := Amount div CoinCopperValues[Ord(Kind)] + 1;
      if Coins > Money[Ord(Kind)] then
        Coins := Money[Ord(Kind)];
      Dec(Amount, Coins * CoinCopperValues[Ord(Kind)]);
      Dec(Money[Ord(Kind)], Coins);
      Kind := Succ(Kind);
    end;
    if Amount < 0 then
    begin
      Amount := Abs(Amount);
      Kind := PlatinumCoin;
      while Amount > 0 do
      begin
        Coins := Amount div CoinCopperValues[Ord(Kind)];
        Dec(Amount, Coins * CoinCopperValues[Ord(Kind)]);
        Inc(Money[Ord(Kind)], Coins);
        Kind := Pred(Kind);
      end;
    end;
  end;
end;

begin
end.

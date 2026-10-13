unit OVL15;
{ Camp: the party's camp (whitepaper 5.22). MakeCamp (entry 1, called by ovl03) runs the Camp menu
  'Save View Magic Rest Alter Exit': the Magic menu (CampMagicMenu) casts (CastSpells, also called by
  ovl14's wilderness keys), memorizes (MemorizeSpells), scribes scrolls (ScribeScrolls), lists the
  party's spell effects (DisplaySpellEffects) and rests (RestParty) for as long as the study needs
  (StudyRestMinutes); the Alter menu (AlterMenu) reorders the party (PartyOrderMenu, MoveMemberUp,
  MoveMemberDown), drops a member (DropPartyMember), sets the game speed (CampSpeedMenu) and switches
  the monster pictures and portraits. A spell being memorized is a Spells slot with bit 7 set, a
  scroll spell being scribed an item spell byte with bit 7 set; both are cancelled when the camp
  opens and closes (CancelPartyStudy) and become real only through the rest (ovl20_e2). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
function StudyRestMinutes(Who: PCharacter): Word;
procedure CancelMemorizing(Who: PCharacter);
procedure CancelScribing(Who: PCharacter);
procedure CancelPartyStudy;
function SpellSlotsLeft(SpellLevel, SpellClass: ShortInt): Byte;
function MayUseMagic(Action: Byte): Boolean;
procedure CastSpells;
function ShowSpellSlotsLeft: Boolean;
procedure RestParty(var EndCamp: Byte);
procedure SortMemorizedSpells;
procedure MemorizeSpells;
procedure ScribeScrolls;
procedure DisplaySpellEffects;
procedure CampMagicMenu(var EndCamp: Byte);
procedure MoveMemberUp;
procedure MoveMemberDown;
procedure PartyOrderMenu;
procedure DropPartyMember;
procedure CampSpeedMenu;
procedure AlterMenu;
procedure MakeCamp(var EndCamp: Byte);
implementation
uses RES04, RES06, RES09, RES12, OVL16, OVL17, OVL19, OVL20, OVL22, OVL25;

const
  { Actions of MayUseMagic. }
  ActionCast = 1;
  ActionMemorize = 2;
  ActionScribe = 3;
  VarNoCasting = 229;           { the game variable (+$1CA) that forbids casting here (as in ovl08) }
  LastSpellSlot = 20;            { TCharacter.Spells is 0..20 }
  { Bit 7 of a memorized spell (Spells) or of a scroll's spell byte (TMenuLine.Affects): the spell
    is being memorized or scribed and only becomes real through the rest; the low bits are the
    spell number. }
  Pending = $80;
  SpellMask = $7F;
  ScrollSpells = 3;              { a scroll holds up to three spells (TMenuLine.Affects[1..3]) }
  SpellLevels = 3;               { spell levels 1..3 of SpellSlots }
  ClassCleric = 0;               { the rows of SpellSlots, TSpellEntry.SpellClass }
  ClassMage = 1;
  LastSpell = $38;               { SpellTable and SpellNames hold spells 1..$38 }
  { The rest a study needs (StudyRestMinutes): 4 hours, 6 when a spell is above level 2, plus 15
    minutes per spell level. }
  BaseRestHours = 4;
  LongRestHours = 6;
  LongRestLevel = 2;
  MinutesPerLevel = 15;
  { Colours of the prompt line (ReadPromptChoice, AskYesNo) and of the messages (res12_fn_16EC). }
  TitleColor = 13;
  WordColor = 10;
  HotColor = 15;
  AskColor = 14;
  MessageColor = 10;
  TextColor = 10;                { DrawTextAt colour of the text window lines }
  Yes = 'Y';
  No = 'N';
  KeyNone = #0;                  { leaves a menu, as 'E' (Exit) does }
  KeyEnter = #13;
  ViewModeCamp = 2;              { the view mode (ds49F3) while the party camps }
  MaxGameSpeed = 9;              { GameSpeed runs 0 (fastest) .. 9 (slowest) }
  NoChoice = $FFFF;              { the list position ovl19_e12 starts from }
  { Spell lists of ovl19_e12 (its first argument) as the camp uses them: 0 the memorized spells to
    cast, 1 the spells to memorize, 3 the scroll spells to scribe, 5 and 6 the spells being
    memorized and scribed. }
  ListMemorized = 0;
  ListLearnable = 1;
  ListScrolls = 3;
  ListMemorizing = 5;
  ListScribing = 6;
  { The Display list (DisplaySpellEffects): NewMenuList's 46-byte lines (Text, Flag29, Next of
    TMenuLine, as ovl25 allocates them), the member heading flag, the window ChooseFromList shows
    them in (the full text window, as the Loot window of ovl05) and its colours. }
  MenuLineBytes = $2E;
  HeadingLine = 1;               { Flag29 of a member's name line: a heading ChooseFromList skips }
  PlainLine = 0;
  ListLeft = 1;
  ListTop = 1;
  ListRight = $26;
  ListBottom = $16;
  ListFirstRow = 4;              { the first list row, under the title }
  ListFrameSet = 0;
  ListTitleColor = 15;
  ListHeadingColor = 11;
  ListLineColor = 10;
  ListHighlightColor = 15;
  ListWithExit = 1;
  { The affects the Display names without a spell (the literals of ovl15:0FBC); every other named
    affect is a spell affect looked up in SpellTable (AffectId, byte +$A). }
  AffectStudyingManual = 4;
  AffectTrainingManual = 7;
  AffectFeatherFall = $1B;
  AffectHelpless = $1F;
  AffectPrayer = $23;
  AffectCauseDisease = $2C;
  AffectMummyDisease = $32;
  AffectRepulsed = $36;
  AffectPoisoned = $37;
  AffectRegenerating = $3B;
  AffectFireResistance = $3D;
  AffectInvisible = $47;
  AffectCamouflaged = $48;
  AffectDisplaced = $59;


{ ovl15:0000. Returns the minutes of rest Who's study needs and stores its hours in RestHours: 15
  minutes per spell level of every spell being memorized (a Spells slot with bit 7) and of every
  scroll spell being scribed (bit 7 of a spell byte of an item ovl22_e6 accepts, a scroll), plus
  4 hours when there is any (6 when one of them is above level 2). RestParty rests the party for
  the largest value. }
function StudyRestMinutes(Who: PCharacter): Word;
var
  MaxMemLevel, MaxScribeLevel, MemSum, ScribeSum: Byte;
  Item: PItem;
  I, Level, Hours: Byte;
begin
  MaxMemLevel := 0;
  MaxScribeLevel := 0;
  MemSum := 0;
  ScribeSum := 0;
  for I := 0 to LastSpellSlot do
    if Who^.Spells[I] > SpellMask then
    begin
      Level := SpellTable[Who^.Spells[I] and SpellMask].Level;
      if Level > MaxMemLevel then MaxMemLevel := Level;
      Inc(MemSum, Level);
    end;
  Item := Who^.Items;
  while Item <> nil do
  begin
    if ovl22_e6(Item) then
      for I := 1 to ScrollSpells do
        if Item^.Affects[I] > SpellMask then
        begin
          Level := SpellTable[Item^.Affects[I] and SpellMask].Level;
          if Level > MaxScribeLevel then MaxScribeLevel := Level;
          Inc(ScribeSum, Level);
        end;
    Item := Item^.Next;
  end;
  Hours := 0;
  if (MemSum > 0) or (ScribeSum > 0) then Hours := BaseRestHours;
  if (MaxMemLevel > LongRestLevel) or (MaxScribeLevel > LongRestLevel) then Hours := LongRestHours;
  Who^.RestHours := Hours;
  StudyRestMinutes := Hours * 60 + MemSum * MinutesPerLevel + ScribeSum * MinutesPerLevel;
end;
{ ovl15:0159. Cancels Who's memorizing: every Spells slot still being memorized (bit 7) is emptied
  and RestHours is cleared. The answer No to 'Memorize These Spells?' and CancelPartyStudy. }
procedure CancelMemorizing(Who: PCharacter);
var
  I: Byte;
begin
  for I := 0 to LastSpellSlot do
    if Who^.Spells[I] > SpellMask then Who^.Spells[I] := 0;
  Who^.RestHours := 0;
end;
{ ovl15:019C. Cancels Who's scribing: bit 7 is cleared from the three spell bytes of every scroll
  Who carries (an item ovl22_e6 accepts). The answer No to 'Scribe These Spells?' and
  CancelPartyStudy. }
procedure CancelScribing(Who: PCharacter);
var
  I: Byte;
  Item: PItem;
begin
  Item := Who^.Items;
  while Item <> nil do
  begin
    if ovl22_e6(Item) then
      for I := 1 to ScrollSpells do
        Item^.Affects[I] := Item^.Affects[I] and SpellMask;
    Item := Item^.Next;
  end;
end;
{ ovl15:0214. Cancels the memorizing and scribing of every member of the party list (ds5D96);
  MakeCamp runs it when the camp opens and when it closes, so only a study finished by RestParty
  survives the camp. }
procedure CancelPartyStudy;
var
  Who: PCharacter;
begin
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    CancelMemorizing(Who);
    CancelScribing(Who);
    Who := Who^.Next;
  end;
end;
{ ovl15:025C. Returns the spell slots SelectedCharacter has left for spells of SpellClass (0 cleric,
  1 magic-user) and SpellLevel (1..3): SpellSlots[SpellClass, SpellLevel] minus the spells of that
  class and level in its Spells slots, memorized or still being memorized. }
function SpellSlotsLeft(SpellLevel, SpellClass: ShortInt): Byte;
var
  Count, I: Byte;
begin
  Count := 0;
  for I := 0 to LastSpellSlot do
    if (SelectedCharacter^.Spells[I] > 0) and
       (SpellTable[SelectedCharacter^.Spells[I] and SpellMask].Level = SpellLevel) and
       (SpellTable[SelectedCharacter^.Spells[I] and SpellMask].SpellClass = SpellClass) then
      Inc(Count);
  SpellSlotsLeft := SelectedCharacter^.SpellSlots[SpellClass, SpellLevel] - Count;
end;
{ ovl15:036C. Whether SelectedCharacter may Action (ActionCast, ActionMemorize, ActionScribe): not
  when the game variable VarNoCasting forbids casting here (casting only: 'cannot cast spells in
  this area'), nor when the character's Status is 1 or Flag10D is 0 ('is in no condition to cast
  any spells', 'memorize spells' or 'scribe any scrolls'). The refusal is shown on the message line
  (res12_fn_16EC). }
function MayUseMagic(Action: Byte): Boolean;
var
  Reason: String40;
begin
  Reason := '';
  if (Action = ActionCast) and (GameVars^[VarNoCasting] > 0) then
    Reason := 'cannot cast spells in this area'
  else if (SelectedCharacter^.Status = 1) or (SelectedCharacter^.Flag10D = 0) then
  begin
    Reason := 'is in no condition to ';
    case Action of
      ActionCast: Reason := Reason + 'cast any spells';
      ActionMemorize: Reason := Reason + 'memorize spells';
      ActionScribe: Reason := Reason + 'scribe any scrolls';
    end;
  end;
  if Length(Reason) = 0 then
    MayUseMagic := True
  else
  begin
    MayUseMagic := False;
    res12_fn_16EC(SelectedCharacter, Reason, MessageColor, 1);
  end;
end;
{ ovl15:04A1. The Cast command: when MayUseMagic allows it, repeatedly lists SelectedCharacter's memorized
  spells (ovl19_e12) and casts the chosen one in a cleared text window (ovl22_e5), until the list
  is left; 'has no spells memorized' when there is none. Clears ds6DB5 first and redraws the screen
  (res12_fn_27D9) when something was shown. The camp's Magic menu and ovl14's wilderness keys. }
procedure CastSpells;
var
  Choice: Word;
  Listed, Redraw, Done, Spell: Byte;
begin
  Redraw := 0;
  Choice := NoChoice;
  ds6DB5 := nil;
  if MayUseMagic(ActionCast) then
    repeat
      Spell := ovl19_e12(ListMemorized, 1, Choice, Listed);
      if Spell <> 0 then
      begin
        Redraw := 1;
        DrawWindowFrame(1, $11, $26, $16, 0);
        ClearWindow(1, $11, $26, $16);
        ovl22_e5(Spell, 0, 1, Done);
        Choice := NoChoice;
      end
      else if Listed <> 0 then
        Redraw := 1
      else
        res12_fn_16EC(SelectedCharacter, 'has no spells memorized', MessageColor, 1);
    until Spell = 0;
  if Redraw <> 0 then res12_fn_27D9;
end;
{ ovl15:05A4. Shows the spell slots SelectedCharacter has left for memorizing: 'can memorize:' and,
  per class that has slots, a row '    Cleric Spells:' or 'Magic-User Spells:' with the slots left
  at levels 1..3 (blank where the class has no slot of that level), from text row $14. Returns
  False, showing nothing, when the character has no spell slot at all. }
function ShowSpellSlotsLeft: Boolean;
var
  Line: String40;
  Counts: array[1..3, 0..1] of string[2];
  HasClass: array[0..1] of Boolean;
  SpellClass, SpellLevel: ShortInt;
  Col, Row: Byte;
  Any: Boolean;
begin
  Any := False;
  for SpellClass := ClassCleric to ClassMage do
  begin
    HasClass[SpellClass] := False;
    for SpellLevel := 1 to SpellLevels do
    begin
      Counts[SpellLevel, SpellClass] := res12_fn_1037(SpellSlotsLeft(SpellLevel, SpellClass));
      if SelectedCharacter^.SpellSlots[SpellClass, SpellLevel] = 0 then
        Counts[SpellLevel, SpellClass] := ' '
      else
      begin
        HasClass[SpellClass] := True;
        Any := True;
      end;
    end;
  end;
  if Any then
  begin
    res12_fn_16EC(SelectedCharacter, 'can memorize:', MessageColor, 0);
    Row := 3;
    for SpellClass := ClassCleric to ClassMage do
      if HasClass[SpellClass] then
      begin
        case SpellClass of
          ClassCleric: Line := '    Cleric Spells:';
          ClassMage: Line := 'Magic-User Spells:';
        end;
        DrawTextAt(1, Row + $11, TextColor, Line);
        Col := $13;
        for SpellLevel := 1 to SpellLevels do
        begin
          DrawTextAt(Col + 1, Row + $11, TextColor, Counts[SpellLevel, SpellClass]);
          Inc(Col, 3);
        end;
        Inc(Row);
      end;
  end;
  ShowSpellSlotsLeft := Any;
end;
{ ovl15:077A. The Rest command: sets RestTime to the longest StudyRestMinutes of the party (hours,
  tens of minutes, minutes; the call also stores each member's RestHours), runs the rest
  (ovl20_e2, whose result goes to EndCamp, ending the camp when nonzero), then clears RestTime and
  calls res12_fn_290B. }
procedure RestParty(var EndCamp: Byte);
var
  Who: PCharacter;
  MaxMinutes, Minutes, Unused: Word;
begin
  MaxMinutes := 0;
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    Minutes := StudyRestMinutes(Who);
    if MaxMinutes < Minutes then MaxMinutes := Minutes;
    Who := Who^.Next;
  end;
  RestTime[3] := MaxMinutes div 60;
  RestTime[2] := (MaxMinutes - RestTime[3] * 60) div 10;
  RestTime[1] := MaxMinutes mod 10;
  EndCamp := ovl20_e2;
  FillChar(RestTime, SizeOf(RestTime), 0);
  res12_fn_290B;
end;
{ ovl15:0824. Sorts SelectedCharacter's 21 Spells slots by spell number (bit 7 ignored, empty
  slots first) with an exchange sort; MemorizeSpells calls it after adding a spell. }
procedure SortMemorizedSpells;
var
  I, J, Spell: Byte;
begin
  for I := 0 to LastSpellSlot - 1 do
    for J := I to LastSpellSlot do
      if (SelectedCharacter^.Spells[I] and SpellMask) > (SelectedCharacter^.Spells[J] and SpellMask) then
      begin
        Spell := SelectedCharacter^.Spells[I];
        SelectedCharacter^.Spells[I] := SelectedCharacter^.Spells[J];
        SelectedCharacter^.Spells[J] := Spell;
      end;
end;
{ ovl15:090A. The Memorize command. When spells are still being memorized from before, asks
  'Memorize These Spells? ' (No cancels them, Yes leaves). Then, while slots are left
  (ShowSpellSlotsLeft, else 'cannot memorize any spells'), the chosen spell (ovl19_e12) goes into
  the first empty Spells slot with bit 7 set (being memorized) if its class and level has a slot
  left, and the slots are sorted. After a choice was made it asks 'Memorize these spells? ' over
  the list of spells being memorized; No cancels them. }
procedure MemorizeSpells;
var
  Done: Boolean;
  Listed, Redraw, Spell, Slot: Byte;
  Choice: Word;
begin
  if not MayUseMagic(ActionMemorize) then Exit;
  Done := False;
  Choice := NoChoice;
  Spell := ovl19_e12(ListMemorizing, 0, Choice, Listed);
  Redraw := 1;
  if Listed <> 0 then
  begin
    if AskYesNo('Memorize These Spells? ', AskColor, WordColor, HotColor) = No then
      CancelMemorizing(SelectedCharacter)
    else
      Done := True;
  end
  else
    Redraw := 0;
  Choice := NoChoice;
  while not Done do
  begin
    Done := not ShowSpellSlotsLeft;
    if Done then
      res12_fn_16EC(SelectedCharacter, 'cannot memorize any spells', MessageColor, 1)
    else
    begin
      Spell := ovl19_e12(ListLearnable, 2, Choice, Listed);
      Redraw := 1;
      if Spell = 0 then
        Done := True
      else if SpellSlotsLeft(SpellTable[Spell].Level, SpellTable[Spell].SpellClass) > 0 then
      begin
        Slot := 0;
        while SelectedCharacter^.Spells[Slot] <> 0 do Inc(Slot);
        SelectedCharacter^.Spells[Slot] := Spell + Pending;
        SortMemorizedSpells;
      end;
    end;
  end;
  if Choice <> NoChoice then
  begin
    Choice := NoChoice;
    Spell := ovl19_e12(ListMemorizing, 0, Choice, Listed);
    if Listed <> 0 then
      if AskYesNo('Memorize these spells? ', AskColor, WordColor, HotColor) = No then
        CancelMemorizing(SelectedCharacter);
  end;
  if Redraw <> 0 then res12_fn_27D9;
end;
{ ovl15:0B5B. The Scribe command (a magic-user copying scroll spells into the spell book). When
  scroll spells are still being scribed, asks 'Scribe These Spells? ' (No cancels them, Yes
  leaves). Then, for each scroll spell chosen (ovl19_e12; 'has no copyable scrolls' when there is
  none): 'You already know that spell' when it is in KnownSpells, 'You are already scibing that
  spell' (sic) when a scroll spell byte already has it with bit 7, 'You can not scribe that
  spell.' when the character has no slot of its class and level, else bit 7 is set on the first
  scroll spell byte holding it. After a choice it asks 'Scribe these spells? '; No cancels. }
procedure ScribeScrolls;
var
  Done: Boolean;
  Listed, Redraw, Spell, Unused, I: Byte;
  Choice: Word;
  Item: PItem;
  Found: Boolean;
begin
  if not MayUseMagic(ActionScribe) then Exit;
  Done := False;
  Choice := NoChoice;
  Spell := ovl19_e12(ListScribing, 0, Choice, Listed);
  Redraw := 1;
  if Listed <> 0 then
  begin
    if AskYesNo('Scribe These Spells? ', AskColor, WordColor, HotColor) = No then
      CancelScribing(SelectedCharacter)
    else
      Done := True;
  end
  else
    Redraw := 0;
  Choice := NoChoice;
  while not Done do
  begin
    Spell := ovl19_e12(ListScrolls, 3, Choice, Listed);
    if Spell = 0 then
    begin
      Done := True;
      if Listed = 0 then
        res12_fn_16EC(SelectedCharacter, 'has no copyable scrolls', MessageColor, 1)
      else
        Redraw := 1;
    end
    else
    begin
      Redraw := 1;
      if SelectedCharacter^.KnownSpells[Spell] <> 0 then
        res12_fn_1693('You already know that spell')
      else
      begin
        Item := SelectedCharacter^.Items;
        Found := False;
        while (Item <> nil) and not Found do
        begin
          if ovl22_e6(Item) then
            for I := 1 to ScrollSpells do
              if (Item^.Affects[I] > SpellMask) and ((Item^.Affects[I] and SpellMask) = Spell) then
              begin
                res12_fn_1693('You are already scibing that spell');
                Found := True;
              end;
          Item := Item^.Next;
        end;
        if not Found then
          if SelectedCharacter^.SpellSlots[SpellTable[Spell].SpellClass, SpellTable[Spell].Level] > 0 then
          begin
            Item := SelectedCharacter^.Items;
            while (Item <> nil) and not Found do
            begin
              I := 1;
              repeat
                if Item^.Affects[I] = Spell then
                begin
                  Item^.Affects[I] := Item^.Affects[I] or Pending;
                  Found := True;
                end;
                Inc(I);
              until (I > ScrollSpells) or Found;
              Item := Item^.Next;
            end;
          end
          else
            res12_fn_1693('You can not scribe that spell.');
      end;
    end;
  end;
  if Choice <> NoChoice then
  begin
    Choice := NoChoice;
    Spell := ovl19_e12(ListScribing, 0, Choice, Listed);
    if Listed <> 0 then
      if AskYesNo('Scribe these spells? ', AskColor, WordColor, HotColor) = No then
        CancelScribing(SelectedCharacter);
  end;
  if Redraw <> 0 then res12_fn_27D9;
end;
{ ovl15:0FBC. The camp's Display command: lists every party member (the party list ds5D96, linked
  by Next) as a heading line followed by one line per affect on the member that the game can name,
  or ' <No Spell Effects>' when it names none, then a blank line, and shows the list in the full
  text window titled 'Display' with ChooseFromList (heading colour 11, lines 10, highlight 15,
  with Exit); the list is freed and the screen redrawn (res12_fn_27D9) afterwards. A spell affect
  (the first case list) is named by the first spell 1..$38 whose SpellTable.AffectId is the affect
  (SpellNames), or 'Funky--n' (res12_fn_1037 writes the number) when no spell has it; fourteen
  other affects have fixed names (the Affect* constants); any other affect is left out. The
  list begins with a blank line (line 0, where the highlight starts: Choice 0), so the first
  member's name is line 1. Reads: ds5D96, SpellTable, SpellNames.
  Side effects: the heap (the lines, freed by FreeMenuList), the screen, the key pressed is ignored.
  QUIRK ovl15:0FBC: the local Unused ([bp-$14]) is never read or written; the frame needs its
  byte (Count is at [bp-$13], Found at [bp-$15]). }
procedure DisplaySpellEffects;
var
  Affect: PAffect;              { the affect of Who being named }
  List, Last: PMenuLine;        { the Display lines and the last one (AddDisplayLine appends) }
  Who: PCharacter;              { the party member being listed }
  AffectId: Byte;               { Affect^.Id }
  Spell: Byte;                  { the SpellTable row being searched for AffectId }
  Count: Byte;                  { the lines added for Who; 0 gives ' <No Spell Effects>' }
  Unused: Byte;                 { QUIRK: never used (see above) }
  Found: Byte;                  { 1 once a spell with AffectId is found }
  Known: Byte;                  { 1 when the affect has a name (0 in the case's else) }
  Redraw: Byte;                 { ChooseFromList's redraw flag, set before the call }
  Name: String40;               { the affect's name }
  Choice: Integer;              { the line ChooseFromList starts on (0) }
  Key: Char;                    { the key that left ChooseFromList; ignored }

  { ovl15:0E37. Nested in DisplaySpellEffects (the static link at [bp+6], pushed by the parent):
    allocates a 46-byte menu line after Last, makes it the last line (Next nil) and sets its text
    and heading flag (Flag29: HeadingLine for a member's name, PlainLine for an affect). }
  procedure AddDisplayLine(Flag: Byte; Text: String40);
  begin
    GetMem(Last^.Next, MenuLineBytes);
    Last := Last^.Next;
    Last^.Next := nil;
    Last^.Text := Text;
    Last^.Flag29 := Flag;
  end;

begin
  GetMem(List, MenuLineBytes);
  Last := List;
  Last^.Flag29 := PlainLine;
  Last^.Text := ' ';
  Last^.Next := nil;
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    Count := 0;
    AddDisplayLine(HeadingLine, Who^.Name);
    Affect := Who^.Affects;
    while Affect <> nil do
    begin
      Known := 1;
      AffectId := Affect^.Id;
      case AffectId of
        { The affects spells leave: named by the first spell whose SpellTable.AffectId matches. }
        1, 2, 5, 8..$E, $10, $11, $13..$19, $1C, $1D, $20..$22, $24..$27, $29, $2A, $2D, $2E,
        $31, $33..$35:
          begin
            Spell := 1;
            Found := 0;
            while (Spell <= LastSpell) and (Found = 0) do
              if SpellTable[Spell].AffectId = AffectId then
              begin
                Name := SpellNames[Spell];
                Found := 1;
              end
              else
                Inc(Spell);
            if Found = 0 then Name := 'Funky--' + res12_fn_1037(AffectId);
          end;
        AffectStudyingManual: Name := 'Studying Manual of Bodily Health';
        AffectTrainingManual: Name := 'Training with Manual of Bodily Health';
        AffectFeatherFall: Name := 'Feather Fall';
        AffectHelpless: Name := 'Helpless';
        AffectPrayer: Name := 'Prayer';
        AffectCauseDisease: Name := 'Cause Disease';
        AffectMummyDisease: Name := 'Dreaded Mummy Disease';
        AffectRepulsed: Name := 'Repulsed';
        AffectPoisoned: Name := 'Poisoned';
        AffectRegenerating: Name := 'Regenerating';
        AffectFireResistance: Name := 'Fire Resistance';
        AffectInvisible: Name := 'Invisible';
        AffectCamouflaged: Name := 'Camouflaged';
        AffectDisplaced: Name := 'Displaced';
      else
        Known := 0;
      end;
      if Known <> 0 then
      begin
        Inc(Count);
        AddDisplayLine(PlainLine, ' ' + Name);
      end;
      Affect := Affect^.Next;
    end;
    if Count = 0 then AddDisplayLine(PlainLine, ' <No Spell Effects>');
    AddDisplayLine(PlainLine, ' ');
    Who := Who^.Next;
  end;
  Redraw := 1;
  Choice := 0;
  DrawWindow(ListLeft, ListTop, ListRight, ListBottom, ListFrameSet, ListTitleColor, 'Display');
  Key := ChooseFromList('', '', ListHeadingColor, ListLineColor, ListHighlightColor,
                        ListLeft, ListFirstRow, ListRight, ListBottom, List, ListWithExit,
                        Redraw, Choice, Last);
  FreeMenuList(List);
  res12_fn_27D9;
end;
{ ovl15:13F1. The camp's Magic menu 'Cast Memorize Scribe Display Rest Exit' (CampMagicMenuText)
  until Exit or the rest ends the camp (EndCamp): C CastSpells, M MemorizeSpells, S ScribeScrolls,
  D DisplaySpellEffects, R RestParty; an extended key goes to ovl19_e10 (the character keys) and
  redraws the character (res12_fn_0767). }
procedure CampMagicMenu(var EndCamp: Byte);
var
  Key: Char;
  ExtKey: Byte;
begin
  Key := ' ';
  while (EndCamp = 0) and not (Key in [KeyNone, 'E']) do
  begin
    Key := ReadPromptChoice('', CampMagicMenuText, TitleColor, WordColor, HotColor, 1, 1, ExtKey);
    if ExtKey <> 0 then
    begin
      ovl19_e10(Key);
      res12_fn_0767(SelectedCharacter);
    end
    else
      case Key of
        'C': CastSpells;
        'M': MemorizeSpells;
        'S': ScribeScrolls;
        'D': DisplaySpellEffects;
        'R': RestParty(EndCamp);
      end;
  end;
end;
{ ovl15:14A9. Moves SelectedCharacter one place up the party list (ds5D96, linked by Next): it
  changes places with the member before it, and the first member goes to the end of the list. The
  Party Order menu's G key once a character is picked. }
procedure MoveMemberUp;
var
  Before, Who, After: PCharacter;
begin
  Who := PCharacter(ds5D96);
  Before := nil;
  if Who = SelectedCharacter then
  begin
    while Who^.Next <> nil do Who := Who^.Next;
  end
  else
    while Who^.Next <> SelectedCharacter do
    begin
      Before := Who;
      Who := Who^.Next;
    end;
  After := SelectedCharacter^.Next;
  if PCharacter(ds5D96) = SelectedCharacter then
  begin
    if After <> nil then PCharacter(ds5D96) := After;
    Who^.Next := SelectedCharacter;
    SelectedCharacter^.Next := nil;
  end
  else
  begin
    Who^.Next := After;
    SelectedCharacter^.Next := Who;
    if (Who = PCharacter(ds5D96)) or (Before = nil) then
      PCharacter(ds5D96) := SelectedCharacter
    else
      Before^.Next := SelectedCharacter;
  end;
end;
{ ovl15:1601. Moves SelectedCharacter one place down the party list: it changes places with the
  member after it, and the last member goes to the front. The Party Order menu's O key. }
procedure MoveMemberDown;
var
  Before, After: PCharacter;
begin
  Before := PCharacter(ds5D96);
  if Before <> SelectedCharacter then
    while Before^.Next <> SelectedCharacter do Before := Before^.Next;
  After := SelectedCharacter^.Next;
  if After = nil then
  begin
    SelectedCharacter^.Next := PCharacter(ds5D96);
    PCharacter(ds5D96) := SelectedCharacter;
    Before^.Next := After;
  end
  else
  begin
    SelectedCharacter^.Next := After^.Next;
    if PCharacter(ds5D96) = SelectedCharacter then PCharacter(ds5D96) := After;
    if Before <> SelectedCharacter then Before^.Next := After;
    After^.Next := SelectedCharacter;
  end;
end;
{ ovl15:1780. The Party Order menu 'Party Order: ' with 'Select Exit', then 'Place Exit' once a
  character is picked (Enter, P or S toggle it: 'has been selected'). Before picking, the G and O
  keys choose another character (ovl19_e10); after, they move the picked one up (MoveMemberUp) or
  down (MoveMemberDown). }
procedure PartyOrderMenu;
var
  Picked: Boolean;
  ExtKey: Byte;
  Key: Char;
begin
  Picked := False;
  Key := ' ';
  while not (Key in [KeyNone, 'E']) do
  begin
    Key := ReadPromptChoice('Party Order: ', PartyOrderMenuTexts[Ord(Picked)], TitleColor, WordColor, HotColor, 1, 1, ExtKey);
    if ExtKey <> 0 then
    begin
      if not Picked then
      begin
        ovl19_e10(Key);
        res12_fn_0767(SelectedCharacter);
      end
      else
      begin
        case Key of
          'G': MoveMemberUp;
          'O': MoveMemberDown;
        end;
        res12_fn_0767(SelectedCharacter);
      end;
    end
    else if Key in [KeyEnter, 'P', 'S'] then
    begin
      Picked := not Picked;
      if Picked then
        res12_fn_16EC(SelectedCharacter, 'has been selected', MessageColor, 0)
      else
        res12_fn_17E3;
    end;
  end;
end;
{ ovl15:18E5. The Drop command: with only one member left it asks 'quit TO DOS: ' and quits the
  game on Yes (after removing the member, ovl16_e2). Otherwise 'will be gone' and 'Drop from
  party? ': on Yes the member 'bids you farewell' (Flag10D set) or 'is dumped in a ditch', leaves
  the party (ovl16_e2) and the window at columns $11..$26, rows 1..$B (the portrait) is
  cleared; on No 'Breathes A sigh of relief'. }
procedure DropPartyMember;
begin
  if (SelectedCharacter^.Next = nil) and (SelectedCharacter = PCharacter(ds5D96)) then
  begin
    if AskYesNo('quit TO DOS: ', AskColor, WordColor, HotColor) = Yes then
    begin
      ovl16_e2(False, True);
      QuitGame;
    end
    else
      Exit;
  end
  else
  begin
    res12_fn_16EC(SelectedCharacter, 'will be gone', MessageColor, 0);
    if AskYesNo('Drop from party? ', AskColor, WordColor, HotColor) = Yes then
    begin
      if SelectedCharacter^.Flag10D <> 0 then
        res12_fn_16EC(SelectedCharacter, 'bids you farewell', MessageColor, 1)
      else
        res12_fn_16EC(SelectedCharacter, 'is dumped in a ditch', MessageColor, 1);
      ovl16_e2(False, True);
      ClearWindow($11, 1, $26, $0B);
      res12_fn_0767(SelectedCharacter);
    end
    else
      res12_fn_16EC(SelectedCharacter, 'Breathes A sigh of relief', MessageColor, 1);
  end;
end;
{ ovl15:1A97. The Speed command: shows 'Game Speed = n (0=fastest 9=slowest)' and the choices
  Faster (when GameSpeed is above 0), Slower (below 9) and Exit, moves GameSpeed by one (the down
  and up keys too, kept in 0..9), until Exit. QUIRK ovl15:1BC6: the F and S keys do not test the
  bounds themselves; the prompt only offers them inside 0..9. }
procedure CampSpeedMenu;
var
  Key: Char;
  ExtKey: Byte;
  Prompt: String40;
begin
  repeat
    DrawTextAt(1, $12, TextColor, 'Game Speed = ' + res12_fn_1037(GameSpeed) + ' (0=fastest 9=slowest)');
    Prompt := '';
    if GameSpeed > 0 then Prompt := Prompt + ' Faster';
    if GameSpeed < MaxGameSpeed then Prompt := Prompt + ' Slower';
    Prompt := Prompt + ' Exit';
    Key := ReadPromptChoice('Game Speed:', Prompt, TitleColor, WordColor, HotColor, 1, 1, ExtKey);
    if ExtKey <> 0 then
    begin
      case Key of
        'P': if GameSpeed > 0 then Dec(GameSpeed);
        'H': if GameSpeed < MaxGameSpeed then Inc(GameSpeed);
      end;
    end
    else
      case Key of
        'F': Dec(GameSpeed);
        'S': Inc(GameSpeed);
      end;
  until Key in [KeyNone, 'E'];
  res12_fn_17E3;
end;
{ ovl15:1C59. The camp's Alter menu 'Order Drop Speed Icon Pics Exit' (AlterMenuText): O
  PartyOrderMenu, D DropPartyMember, S CampSpeedMenu, I ovl16_e3 and a redraw, P the submenu that
  toggles the monster pictures (ShowMonsterPics) and the portraits (ShowPortraits). }
procedure AlterMenu;
var
  Key, Choice: Char;
  ExtKey: Byte;
  Prompt: String40;
begin
  Key := ' ';
  while not (Key in [KeyNone, 'E']) do
  begin
    Key := ReadPromptChoice('Alter: ', AlterMenuText, TitleColor, WordColor, HotColor, 1, 1, ExtKey);
    if ExtKey <> 0 then
    begin
      ovl19_e10(Key);
      res12_fn_0767(SelectedCharacter);
    end
    else
      case Key of
        'O': PartyOrderMenu;
        'D': DropPartyMember;
        'S': CampSpeedMenu;
        'I':
          begin
            ovl16_e3;
            res12_fn_27D9;
          end;
        'P':
          repeat
            if ShowMonsterPics <> 0 then
              Prompt := 'Monsters on  '
            else
              Prompt := 'Monsters off  ';
            if ShowPortraits <> 0 then
              Prompt := Prompt + 'Portraits on  '
            else
              Prompt := Prompt + 'Portraits off  ';
            Prompt := Prompt + 'Exit';
            Choice := ReadPromptChoice('', Prompt, TitleColor, WordColor, HotColor, 0, 1, ExtKey);
            case Choice of
              'M': Boolean(ShowMonsterPics) := not Boolean(ShowMonsterPics);
              'P': Boolean(ShowPortraits) := not Boolean(ShowPortraits);
            end;
          until Choice in [KeyNone, 'E'];
      end;
  end;
end;
{ ovl15:1E6F. Entry 1, called by ovl03: the party makes camp. Sets the view mode to ViewModeCamp
  (restored on leaving), clears ds6DD8 and RestTime, shows 'The party makes camp...', cancels any
  unfinished study (CancelPartyStudy, again on leaving) and runs the Camp menu 'Save View Magic
  Rest Alter Exit' (CampMenuText) until Exit or EndCamp: S saves (ovl17_e9) and offers 'Quit TO
  DOS ', V ovl19_e5 (the view), M CampMagicMenu, R RestParty, A AlterMenu. EndCamp is set by a rest
  that ends the camp (ovl20_e2). }
procedure MakeCamp(var EndCamp: Byte);
var
  SavedMode: Byte;
  Key: Char;
  ViewFlag, ExtKey: Byte;
begin
  SavedMode := ds49F3;
  ds49F3 := ViewModeCamp;
  ds6DD8 := 0;
  FillChar(RestTime, SizeOf(RestTime), 0);
  res12_fn_27D9;
  ClearWindow(1, $11, $26, $16);
  DrawTextAt(1, $12, TextColor, 'The party makes camp...');
  CancelPartyStudy;
  EndCamp := 0;
  Key := ' ';
  while (EndCamp = 0) and not (Key in [KeyNone, 'E']) do
  begin
    Key := ReadPromptChoice('Camp: ', CampMenuText, TitleColor, WordColor, HotColor, 1, 1, ExtKey);
    if ExtKey <> 0 then
    begin
      ovl19_e10(Key);
      res12_fn_0767(SelectedCharacter);
    end
    else
      case Key of
        'S':
          begin
            ovl17_e9;
            if AskYesNo('Quit TO DOS ', AskColor, WordColor, HotColor) = Yes then QuitGame;
          end;
        'V': ovl19_e5(ViewFlag);
        'M': CampMagicMenu(EndCamp);
        'R': RestParty(EndCamp);
        'A': AlterMenu;
      end;
  end;
  CancelPartyStudy;
  ds6DB5 := nil;
  ds49F3 := SavedMode;
  res12_fn_290B;
  res12_fn_17E3;
  ClearPromptLine;
end;

begin
end.

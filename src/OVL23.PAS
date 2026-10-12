unit OVL23;
{ ClassStats: recomputes the values a character draws from its class levels (whitepaper 5.6).
  RecalcClassStats sets the to-hit value, the highest level, the fighter's attacks, the cleric
  and magic-user spell slots and the cleric spells known, then the saving throws
  (ComputeSavingThrows) and, for a thief, the thief skills (ComputeThiefSkills);
  AddWisdomBonusSpells adds the wisdom bonus to the cleric spell slots. Every table is a global
  of POOLVARS indexed by class and level (ClassThac0Table, ClericSlotTable, MageSlotTable,
  SavingThrowTable, ThiefSkillTable, ThiefRaceTable, ThiefDexTable, SpellTable). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure RecalcClassStats(Character: PCharacter);
procedure AddWisdomBonusSpells(Character: PCharacter);
procedure ComputeSavingThrows(Character: PCharacter);
procedure ComputeThiefSkills(Character: PCharacter);
implementation
const
  { Indices of TCharacter.ClassLevels: cleric 0 (Turn in combat, whitepaper 5.5), fighter 2
    (whitepaper 5.8, 5.19); magic-user 5 and thief 6 [I] from the tables they select here. }
  ClassCleric = 0;
  ClassFighter = 2;
  ClassMage = 5;
  ClassThief = 6;
  LastClass = 7;
  LastSpell = $38;              { SpellTable and KnownSpells hold spells 1..$38 }
  LastSpellLevel = 3;           { cleric and magic-user spell levels 1..3 }
  ClericSpell = 0;              { TSpellEntry.SpellClass of a cleric spell, the cleric row of SpellSlots }
  MageSpell = 1;                { the magic-user row of TCharacter.SpellSlots }
  FighterExtraAttackLevel = 6;  { above this fighter level Attacks is 3, else 2 }
  FewAttacks = 2;
  MoreAttacks = 3;
  FirstSpellLevel = 1;          { a cleric or magic-user level above this one has spell slots here }
  LastSave = 4;                 { the saving throws are 0..4 }
  WorstSave = 20;               { the value every saving throw starts from }
  LastThiefSkill = 8;
  DexSkills = 5;                { dexterity adjusts the first five thief skills }

{ ovl23:0000. Recomputes what a character draws from its eight class levels (ClassLevels[0..7]):
  Thac0 (cleared first) becomes the best (largest) ClassThac0Table[class, level]; HighestLevel is
  raised to the highest level (it is never lowered here); a fighter gets Attacks 3 above level 6,
  else 2; a cleric above level 1 gets the cleric SpellSlots of ClericSlotTable plus the wisdom bonus
  (AddWisdomBonusSpells) and KnownSpells[n] := 1 for every cleric spell of SpellTable whose level
  has a slot; a magic-user above level 1 gets the magic-user SpellSlots of MageSlotTable. Then the saving
  throws (ComputeSavingThrows) and, when the thief level is above 0, the thief skills
  (ComputeThiefSkills). KnownSpells entries are only ever set, never cleared. Called by ovl12,
  ovl16, ovl17 and ovl22. }
procedure RecalcClassStats(Character: PCharacter);
var
  ClassNo: ShortInt;
  SpellLevel: ShortInt;
  ClassLevel: ShortInt;
  Spell: Byte;
begin
  Character^.Thac0 := 0;
  for ClassNo := 0 to LastClass do
  begin
    ClassLevel := Character^.ClassLevels[ClassNo];
    if ClassThac0Table[ClassNo, ClassLevel] > Character^.Thac0 then
      Character^.Thac0 := ClassThac0Table[ClassNo, ClassLevel];
    if Character^.HighestLevel < ClassLevel then
      Character^.HighestLevel := ClassLevel;
    case ClassNo of
      ClassFighter:
        if ClassLevel > FighterExtraAttackLevel then
          Character^.Attacks := MoreAttacks
        else
          Character^.Attacks := FewAttacks;
      ClassCleric:
        if ClassLevel > FirstSpellLevel then
        begin
          for SpellLevel := 1 to LastSpellLevel do
            Character^.SpellSlots[ClericSpell, SpellLevel] := ClericSlotTable[ClassLevel, SpellLevel];
          AddWisdomBonusSpells(Character);
          for Spell := 1 to LastSpell do
            with SpellTable[Spell] do   { the compiler keeps the row's far address in a temporary }
              if (SpellClass = ClericSpell) and (Character^.SpellSlots[ClericSpell, Level] > 0) then
                Character^.KnownSpells[Spell] := 1;
        end;
      ClassMage:
        if ClassLevel > FirstSpellLevel then
          for SpellLevel := 1 to LastSpellLevel do
            Character^.SpellSlots[MageSpell, SpellLevel] := MageSlotTable[ClassLevel, SpellLevel];
    end;
  end;
  ComputeSavingThrows(Character);
  if Character^.ClassLevels[ClassThief] > 0 then
    ComputeThiefSkills(Character);
end;

{ ovl23:01AF. Adds the wisdom bonus spells to a cleric's slots: SpellSlots[ClericSpell, 1] gains one at
  Wisdom 13 and another at 14, SpellSlots[ClericSpell, 2] one at 15 and one at 16, SpellSlots[ClericSpell, 3] one at 17;
  a level with no slot (0) gains nothing. Called by RecalcClassStats after it fills the slots and
  three times by ovl16. }
procedure AddWisdomBonusSpells(Character: PCharacter);
begin
  with Character^ do
  begin
    if (Wisdom > 12) and (SpellSlots[ClericSpell, 1] > 0) then Inc(SpellSlots[ClericSpell, 1]);
    if (Wisdom > 13) and (SpellSlots[ClericSpell, 1] > 0) then Inc(SpellSlots[ClericSpell, 1]);
    if (Wisdom > 14) and (SpellSlots[ClericSpell, 2] > 0) then Inc(SpellSlots[ClericSpell, 2]);
    if (Wisdom > 15) and (SpellSlots[ClericSpell, 2] > 0) then Inc(SpellSlots[ClericSpell, 2]);
    if (Wisdom > 16) and (SpellSlots[ClericSpell, 3] > 0) then Inc(SpellSlots[ClericSpell, 3]);
  end;
end;

{ ovl23:0255. Sets each of the five SavingThrows to 20 and lowers it to the best (smallest)
  SavingThrowTable[class, level, n] over the classes the character has a level in. Called by
  RecalcClassStats and ovl16. QUIRK ovl23:0258: the frame holds two bytes no code uses (Unused). }
procedure ComputeSavingThrows(Character: PCharacter);
var
  Save: ShortInt;
  ClassNo: ShortInt;
  Unused: Word;
begin
  for Save := 0 to LastSave do
  begin
    Character^.SavingThrows[Save] := WorstSave;
    for ClassNo := 0 to LastClass do
      if Character^.ClassLevels[ClassNo] > 0 then
        if Character^.SavingThrows[Save] > SavingThrowTable[ClassNo, Character^.ClassLevels[ClassNo], Save] then
          Character^.SavingThrows[Save] := SavingThrowTable[ClassNo, Character^.ClassLevels[ClassNo], Save];
  end;
end;

{ ovl23:0329. Computes the eight ThiefSkills from the thief level: ThiefSkillTable[level, n] plus
  the race's ThiefRaceTable[Race, n] (signed), plus ThiefDexTable[Dexterity, n] (signed) for the
  first five; a negative race adjustment larger than the base makes the skill 0 (and skips the
  dexterity). The sums are stored as bytes. Called by RecalcClassStats for a thief and by ovl16. }
procedure ComputeThiefSkills(Character: PCharacter);
var
  Skill: Byte;
begin
  with Character^ do
    for Skill := 1 to LastThiefSkill do
      if (ThiefRaceTable[Race, Skill] < 0)
        and (Abs(ThiefRaceTable[Race, Skill]) > ThiefSkillTable[ClassLevels[ClassThief], Skill]) then
        ThiefSkills[Skill] := 0
      else
      begin
        ThiefSkills[Skill] := ThiefSkillTable[ClassLevels[ClassThief], Skill] + ThiefRaceTable[Race, Skill];
        if Skill < DexSkills + 1 then
          ThiefSkills[Skill] := ThiefSkills[Skill] + ThiefDexTable[Dexterity, Skill];
      end;
end;

begin
end.

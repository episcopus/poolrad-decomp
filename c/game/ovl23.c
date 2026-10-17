#include "game.h"

/* ovl23:0000. Recomputes what a character draws from its eight class levels (ClassLevels[0..7]):
     Thac0 (cleared first) becomes the best (largest) ClassThac0Table[class, level]; HighestLevel is
     raised to the highest level (it is never lowered here); a fighter gets Attacks 3 above level 6,
     else 2; a cleric above level 1 gets the cleric SpellSlots of ClericSlotTable plus the wisdom bonus
     (AddWisdomBonusSpells) and KnownSpells[n] := 1 for every cleric spell of SpellTable whose level
     has a slot; a magic-user above level 1 gets the magic-user SpellSlots of MageSlotTable. Then the saving
     throws (ComputeSavingThrows) and, when the thief level is above 0, the thief skills
     (ComputeThiefSkills). KnownSpells entries are only ever set, never cleared. Called by ovl12,
     ovl16, ovl17 and ovl22. */
void RecalcClassStats(PCharacter Character)
{
  POOL_TRACE("RecalcClassStats");
  s8 ClassNo = 0;
  s8 SpellLevel = 0;
  s8 ClassLevel = 0;
  u8 Spell = 0;
  (*FPD(TCharacter (*), Character)).Thac0 = 0;
  {
    if (0 <= LastClass) {
      ClassNo = 0;
      for (;;) {
          ClassLevel = (*FPD(TCharacter (*), Character)).ClassLevels[ClassNo];
          if (ClassThac0Table[ClassNo][ClassLevel] > (*FPD(TCharacter (*), Character)).Thac0) {
            (*FPD(TCharacter (*), Character)).Thac0 = ClassThac0Table[ClassNo][ClassLevel];
          }
          if ((*FPD(TCharacter (*), Character)).HighestLevel < ClassLevel) {
            (*FPD(TCharacter (*), Character)).HighestLevel = ClassLevel;
          }
          switch (ClassNo) {
          case ClassFighter:
          {
            if (ClassLevel > FighterExtraAttackLevel) {
              (*FPD(TCharacter (*), Character)).Attacks = MoreAttacks;
            } else {
              (*FPD(TCharacter (*), Character)).Attacks = FewAttacks;
            }
            break;
          }
          case ClassCleric:
          {
            if (ClassLevel > FirstSpellLevel) {
              {
                if (1 <= LastSpellLevel) {
                  SpellLevel = 1;
                  for (;;) {
                      (*FPD(TCharacter (*), Character)).SpellSlots[0][SpellLevel - 1] = ClericSlotTable[ClassLevel][SpellLevel - 1];
                    if (SpellLevel == LastSpellLevel) break;
                    SpellLevel++;
                  }
                }
              }
              AddWisdomBonusSpells(Character);
              {
                if (1 <= LastSpell) {
                  Spell = 1;
                  for (;;) {
                      {
                        TSpellEntry *w1 = &SpellTable[Spell];
                          if (((w1->SpellClass == ClericSpell)) && (((*FPD(TCharacter (*), Character)).SpellSlots[0][w1->Level - 1] > 0))) {
                            (*FPD(TCharacter (*), Character)).KnownSpells[Spell - 1] = 1;
                          }
                      }
                    if (Spell == LastSpell) break;
                    Spell++;
                  }
                }
              }
            }
            break;
          }
          case ClassMagicUser:
          {
            if (ClassLevel > FirstSpellLevel) {
              {
                if (1 <= LastSpellLevel) {
                  SpellLevel = 1;
                  for (;;) {
                      (*FPD(TCharacter (*), Character)).SpellSlots[1][SpellLevel - 1] = MageSlotTable[ClassLevel][SpellLevel - 1];
                    if (SpellLevel == LastSpellLevel) break;
                    SpellLevel++;
                  }
                }
              }
            }
            break;
          }
          }
        if (ClassNo == LastClass) break;
        ClassNo++;
      }
    }
  }
  ComputeSavingThrows(Character);
  if ((*FPD(TCharacter (*), Character)).ClassLevels[6] > 0) {
    ComputeThiefSkills(Character);
  }
}

/* ovl23:01AF. Adds the wisdom bonus spells to a cleric's slots: SpellSlots[ClericSpell, 1] gains one at
     Wisdom 13 and another at 14, SpellSlots[ClericSpell, 2] one at 15 and one at 16, SpellSlots[ClericSpell, 3] one at 17;
     a level with no slot (0) gains nothing. Called by RecalcClassStats after it fills the slots and
     three times by ovl16. */
void AddWisdomBonusSpells(PCharacter Character)
{
  POOL_TRACE("AddWisdomBonusSpells");
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Character));
      if (((w1->Wisdom > 12)) && ((w1->SpellSlots[0][0] > 0))) {
        w1->SpellSlots[0][0]++;
      }
      if (((w1->Wisdom > 13)) && ((w1->SpellSlots[0][0] > 0))) {
        w1->SpellSlots[0][0]++;
      }
      if (((w1->Wisdom > 14)) && ((w1->SpellSlots[0][1] > 0))) {
        w1->SpellSlots[0][1]++;
      }
      if (((w1->Wisdom > 15)) && ((w1->SpellSlots[0][1] > 0))) {
        w1->SpellSlots[0][1]++;
      }
      if (((w1->Wisdom > 16)) && ((w1->SpellSlots[0][2] > 0))) {
        w1->SpellSlots[0][2]++;
      }
  }
}

/* ovl23:0255. Sets each of the five SavingThrows to 20 and lowers it to the best (smallest)
     SavingThrowTable[class, level, n] over the classes the character has a level in. Called by
     RecalcClassStats and ovl16. QUIRK ovl23:0258: the frame holds two bytes no code uses (Unused). */
void ComputeSavingThrows(PCharacter Character)
{
  POOL_TRACE("ComputeSavingThrows");
  s8 Save = 0;
  s8 ClassNo = 0;
  u16 Unused = 0;
  {
    if (0 <= LastSave) {
      Save = 0;
      for (;;) {
          (*FPD(TCharacter (*), Character)).SavingThrows[Save] = WorstSave;
          {
            if (0 <= LastClass) {
              ClassNo = 0;
              for (;;) {
                  if ((*FPD(TCharacter (*), Character)).ClassLevels[ClassNo] > 0) {
                    if ((*FPD(TCharacter (*), Character)).SavingThrows[Save] > SavingThrowTable[ClassNo][(*FPD(TCharacter (*), Character)).ClassLevels[ClassNo]][Save]) {
                      (*FPD(TCharacter (*), Character)).SavingThrows[Save] = SavingThrowTable[ClassNo][(*FPD(TCharacter (*), Character)).ClassLevels[ClassNo]][Save];
                    }
                  }
                if (ClassNo == LastClass) break;
                ClassNo++;
              }
            }
          }
        if (Save == LastSave) break;
        Save++;
      }
    }
  }
}

/* ovl23:0329. Computes the eight ThiefSkills from the thief level: ThiefSkillTable[level, n] plus
     the race's ThiefRaceTable[Race, n] (signed), plus ThiefDexTable[Dexterity, n] (signed) for the
     first five; a negative race adjustment larger than the base makes the skill 0 (and skips the
     dexterity). The sums are stored as bytes. Called by RecalcClassStats for a thief and by ovl16. */
void ComputeThiefSkills(PCharacter Character)
{
  POOL_TRACE("ComputeThiefSkills");
  u8 Skill = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Character));
      {
        if (1 <= LastThiefSkill) {
          Skill = 1;
          for (;;) {
              if (((ThiefRaceTable[w1->Race][Skill - 1] < 0)) && ((rtl_abs(ThiefRaceTable[w1->Race][Skill - 1]) > ThiefSkillTable[w1->ClassLevels[6]][Skill - 1]))) {
                w1->ThiefSkills[Skill - 1] = 0;
              } else {
                w1->ThiefSkills[Skill - 1] = ThiefSkillTable[w1->ClassLevels[6]][Skill - 1] + ThiefRaceTable[w1->Race][Skill - 1];
                if (Skill < 6) {
                  w1->ThiefSkills[Skill - 1] = w1->ThiefSkills[Skill - 1] + ThiefDexTable[w1->Dexterity][Skill - 1];
                }
              }
            if (Skill == LastThiefSkill) break;
            Skill++;
          }
        }
      }
  }
}

/* Initialisation part of unit OVL23. */
void init_OVL23(void)
{
  POOL_TRACE("init");
}

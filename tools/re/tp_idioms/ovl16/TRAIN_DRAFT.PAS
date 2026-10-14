{ Draft of ovl16:29AE (the Train function) kept because it did not match (playbook 30: a blocked
  routine keeps its draft). Saved by dec-deepseek-3, batch 13, 2026-10-13. The frame matches (once a
  Spare byte is declared, the original reserves one) and the entry checks match byte for byte, but the
  body is still 36 bytes too long from remaining codegen differences:
   - TP 6.0 writes `A := A + B` on two Bytes as a 16-bit add. The original's `add [bp-0xb],al` is
     8-bit, which `Inc(A, B)` produces (see ClassBitMask and TrainableBits, already fixed here).
   - the ds409B[I, Level + 1] index wants `Level + 1` computed in the byte first
     (`mov al,[bp-0x18]; inc al; cbw; shl ax,1; shl ax,1`); declaring Level as ShortInt and writing
     `Level + 1` gives `cbw; inc ax` instead (the first real remaining diff at 0x12d3).
   - the forward jmps at 0x1191 (0x27 vs 0x2a), 0x1259 (0x125f vs 0x1261) and 0x12cd still differ,
     which is the accumulated body-length difference.
  Also needed: ds05DE (array[0..7] of Byte, the class bit of each class) and ds409B (array[0..7,0..13]
  of LongInt, the experience to reach each level) in POOLVARS, and the ovl16_fn_42ED(Amount: LongInt;
  Who: PCharacter), ovl16_fn_4235(Who: PCharacter; ClassBits: Byte): Byte and
  ovl16_fn_3F31(Who: PCharacter): ShortInt stub signatures. This file is a reference, not compiled. }
procedure ovl16_fn_29AE;
const
  MessageColour = $E;           { yellow: the flash messages of the refusals }
  TrainCost = 1000;             { the gold pieces the training costs }
  VarTrainingClasses = 680;     { ds49D6^[680]: the class bits the hall trains here }
  PromptTitleColour = $D;       { the AskYesNo title colour }
  PromptWordColour = $A;
  PromptHotColour = $F;
  BecomeTextCol = 6;            { the column of the becoming lines }
  BecomeTextColour = $A;        { green }
  FirstBecomeRow = 5;           { the first class's row: 4 is DrawCharacterName's }
var
  AtLimit: Byte;                { [bp-1]: the class is at its racial level limit }
  NewExperience: LongInt;       { [bp-5..bp-2]: the experience the training leaves the character at }
  ClassXp: LongInt;             { [bp-9..bp-6]: a class's ds409B threshold }
  TrainableBits: Byte;          { [bp-0xa]: the class bits with enough experience to train }
  ClassBitMask: Byte;           { [bp-0xb]: the class bits of every class with a level above 0 }
  AllowedBits: Byte;            { [bp-0xc]: the class bits the training may raise }
  TrainedCount: Byte;           { [bp-0xd]: the classes with a level (the hit points are shared) }
  HpRoll: Word;                 { [bp-0xf..bp-0xe]: ovl16_fn_4235's hit-point roll }
  HpGain: Word;                 { [bp-0x11..bp-0x10]: the hit points the rise adds }
  SavedHp: Byte;                { [bp-0x12]: the hit points of the class levels before the rise }
  I: ShortInt;                  { [bp-0x13]: the class loop }
  ConBonus: Word;               { [bp-0x15..bp-0x14]: ovl16_fn_3F31's constitution adjustment }
  Row: Byte;                    { [bp-0x16]: the text row of the becoming list }
  SavedMageLevel: Byte;         { [bp-0x17]: ClassLevels[5] before the rise }
  Level: ShortInt;              { [bp-0x18]: ClassLevels[I] }
  ChosenSpell: Byte;            { [bp-0x19]: the spell ChooseSpellFromList returned }
  Choice: Word;                 { [bp-0x1b..bp-0x1a]: ChooseSpellFromList's choice }
  Listed: Byte;                 { [bp-0x1c]: ChooseSpellFromList's listed flag }
  Spare: Byte;                  { [bp-0x1d]: the original frame reserves this byte, never read }
begin
  if (SelectedCharacter^.Status <> 0) and (ds470C = 0) then
  begin
    FlashMessageLine('we only train conscious people', MessageColour);
    Exit;
  end;
  if (CharacterMoneyValueInGold(SelectedCharacter) < TrainCost) and (ds470C = 0) then
  begin
    FlashMessageLine('Training costs 1000 gp.', MessageColour);
    Exit;
  end;
  TrainableBits := 0;
  ClassBitMask := 0;
  with SelectedCharacter^ do
  begin
    NewExperience := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(ClassBitMask, ds05DE[I]);
        AtLimit := 0;
        Level := ClassLevels[I];
        case Race of
          1:
            if I = 2 then
              if ((Level = 8) and (Strength = 17)) or ((Level = 7) and (Strength < 17)) then
                AtLimit := 1;
          2:
            if I = 2 then
              if (Level = 7) or ((Level = 6) and (Strength = 17))
                 or ((Level = 5) and (Strength < 17)) then
                AtLimit := 1;
          3:
            if I = 2 then
              if (Level = 6) or ((Level = 5) and (Strength < 18)) then
                AtLimit := 1;
          4:
            if I = 0 then
            begin
              if Level = 5 then
                AtLimit := 1;
            end
            else if I = 2 then
              if (Level = 8) or ((Level = 7) and (Strength = 17))
                 or ((Level = 6) and (Strength < 17)) then
                AtLimit := 1;
          5:
            if I = 2 then
              if (Level = 6) or ((Level = 5) and (Strength = 17))
                 or ((Level = 4) and (Strength < 17)) then
                AtLimit := 1;
        end;
        if AtLimit = 0 then
          if ((ds409B[I, Level + 1] <= Experience) or (ds470C <> 0))
             and (ds409B[I, Level + 2] > 0) then
          begin
            Inc(TrainableBits, ds05DE[I]);
            ClassXp := ds409B[I, Level + 2];
            if (ClassXp > 0) and (Experience >= ClassXp) and (ClassXp > NewExperience) then
              NewExperience := ClassXp - 1;
          end;
      end;
    if NewExperience > 0 then
      Experience := NewExperience;
    if ds470C = 0 then
    begin
      if (ds49D6^[VarTrainingClasses] and ClassBitMask) = 0 then
      begin
        FlashMessageLine('We don''t train that class here', MessageColour);
        Exit;
      end;
      if (ds49D6^[VarTrainingClasses] and TrainableBits) = 0 then
      begin
        FlashMessageLine('Not Enough Experience', MessageColour);
        Exit;
      end;
    end;
    if ds470C = 0 then
      AllowedBits := ds49D6^[VarTrainingClasses] and TrainableBits
    else
      AllowedBits := TrainableBits;
    ClearWindow(1, 1, $26, $16);
    Row := 4;
    DrawCharacterName(SelectedCharacter, 0, Row, 4);
    DrawTextAt(Length(Name) + 4, Row, BecomeTextColour, ' will become:');
    for I := 0 to 7 do
      if (ClassLevels[I] > 0) and ((ds05DE[I] and AllowedBits) > 0) then
      begin
        Inc(Row);
        if Row = FirstBecomeRow then
          DrawTextAt(BecomeTextCol, Row, BecomeTextColour,
            '    a level ' + ByteToText(ClassLevels[I] + 1) + ' ' + ClassNames[I])
        else
          DrawTextAt(BecomeTextCol, Row, BecomeTextColour,
            'and a level ' + ByteToText(ClassLevels[I] + 1) + ' ' + ClassNames[I]);
      end;
    if AskYesNo('Do you wish to train? ', PromptTitleColour, PromptWordColour,
      PromptHotColour) <> 'Y' then
      Exit;
    ShowFlashMessage('Congratulations...');
    if ds470C = 0 then
      ovl16_fn_42ED(TrainCost, SelectedCharacter);
    TrainedCount := 0;
    SavedMageLevel := ClassLevels[5];
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(TrainedCount);
        if (ds05DE[I] and AllowedBits) <> 0 then
        begin
          Inc(ClassLevels[I]);
          if Pad74[$74] > 0 then
          begin
            Pad74[$75] := Pad74[$75] - (Pad74[$75] div Pad74[$74]);
            Dec(Pad74[$74]);
          end;
        end;
      end;
    RecalcClassStats(SelectedCharacter);
    if ClassLevels[5] > SavedMageLevel then
    begin
      Choice := $FFFF;
      repeat
        ChosenSpell := ChooseSpellFromList(4, 4, Choice, Listed);
      until (ChosenSpell > 0) or (Listed = 0);
      KnownSpells[ChosenSpell] := 1;
    end;
    HpRoll := ovl16_fn_4235(SelectedCharacter, AllowedBits);
    HpGain := HpRoll div TrainedCount;
    if HpGain = 0 then
      HpGain := 1;
    HpB1 := HpB1 + HpGain;
    ConBonus := ovl16_fn_3F31(SelectedCharacter);
    HpGain := (HpRoll + ConBonus) div TrainedCount;
    if HpGain < 1 then
      HpGain := 1;
    SavedHp := HpMax - Flag11B;
    HpMax := HpMax + HpGain;
    Flag11B := HpMax - SavedHp;
  end;
end;

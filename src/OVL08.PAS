unit OVL08;
{ CombatAI: the combat round loop and the player's combat commands (whitepaper 5.5). RunCombat runs
  rounds until one side is gone; each round every character with a positive initiative gets a turn
  in initiative order (PickNextCombatant, CombatTurn), the computer playing quick characters
  (QuickTurn) and the player the others (PlayerTurn with CombatMenu, MoveCharacter, MeleeAttack,
  EndTurnMenu, GameSpeedMenu). EndCombatRound bleeds dying characters and asks Continue Battle,
  BandageDying and SetQuickCombat serve the commands, EndCombat frees the combat data. }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS;
procedure EndCombat;
procedure RunCombat;
procedure PickNextCombatant(var Best: PCharacter);
procedure CombatTurn(Who: PCharacter);
procedure PlayerTurn(Who: PCharacter);
procedure CombatMenu(Who: PCharacter; var Cmd: Char);
procedure EndCombatRound(var Done: Byte);
procedure MoveCharacter(Who: PCharacter; var Done: Byte);
procedure MeleeAttack(Attacker, Target: PCharacter; var Done: Byte);
procedure EndTurnMenu(Who: PCharacter; var Done: Byte);
function BandageDying(DoIt: Byte): Byte;
procedure GameSpeedMenu;
procedure SetQuickCombat(Who: PCharacter);
implementation
uses RES04, RES07, RES09, RES12, OVL09, OVL10, OVL13, OVL19, OVL20, OVL22, OVL24, OVL25, OVL31, Crt;
const
  StatusBandaged = 4;     { the Status BandageDying gives a dying character }
  StatusDying = 5;        { the Status of a dying character: it bleeds one round per EndCombatRound }
  StatusBledOut = 6;      { the Status after more than LastDyingRound rounds (Raise Dead's StatusGone) }
  LastDyingRound = 9;
  NoInitiative = 0;       { PickNextCombatant: no character is left to act this round }
  InitiativeLast = 1;     { Delay: act after everyone else }
  InitiativeQuickAll = $14; { the Alt-Q quick fight marks the character; CombatTurn turns it into $13 }
  NoDirection = 8;        { MoveCharacter: the key was no direction }
  KeyQuickAll = #16;      { Alt-Q: every character fights by itself (the scan code) }
  KeyAltR = #19;          { Alt-R: accepted by CombatMenu, no command in PlayerTurn }
  KeyAltX = '-';          { Alt-X: GodsIntervene decides (That doesn't work) }
  KeyAltM = '2';          { Alt-M: Magic On / Magic Off }
  { The keypad scan codes MoveCharacter turns into the directions 0 (north) to 7, clockwise. }
  KeyUp = 'H';
  KeyPgUp = 'I';
  KeyRight = 'M';
  KeyPgDn = 'Q';
  KeyDown = 'P';
  KeyEnd = 'O';
  KeyLeft = 'K';
  KeyHome = 'G';
  CombatNodeSize = $13;   { FreeMem size of a DS:6DBB list record }
  CombatMapSize = $4E9;   { FreeMem size of the CombatMap block }
  ViewModeCombat = 5;     { ViewMode while a combat is running (ovl08:0080) }
  MaxGameSpeed = 9;
  VarNoCasting = 229;     { the game variable (+$1CA) that hides Cast in the combat menu }
  VarCombatWord715 = 715; { a word of GameVars2^ RunCombat clears every round (+$596); meaning unknown }
  MenuColors = $F;        { the last ReadPromptChoice/AskYesNo argument of every menu here }

{ ovl08:0000. Frees the combat data after the last round: the DS:6DBB list of $13-byte records,
  the CombatMap block, and the picture DS:6E36 (ReleasePicture). Then RestorePaletteColours0And8, and DS:6B84 becomes
  @ChooseSpellTargets. Called once by RunCombat. The word local is unused; it is there so the frame matches. }
procedure EndCombat;
var
  Next: PCombatNode;
  Unused: Word;
begin
  while CloudList <> nil do
  begin
    Next := CloudList^.Next;
    FreeMem(CloudList, CombatNodeSize);
    CloudList := Next;
  end;
  FreeMem(CombatMap, CombatMapSize);
  CombatMap := nil;
  ReleasePicture(CombatPicture);
  RestorePaletteColours0And8;
  SpellPickerPointer := @ChooseSpellTargets;
end;
{ ovl08:007A. The combat loop. Sets the view mode and DS:6B84 := @SelectSpellTargets, runs StartBattle,
  then rounds until one side's count (PartySideCount or EnemySideCount) is zero or EndCombatRound says so.
  Each round calls RecountCombatSides, StartCombatantRound for every combatant on the party list, then turns in
  initiative order (PickNextCombatant, CombatTurn). EndCombat frees the combat data. The byte
  local is unused; it is there so the frame matches. Called by RunAreaEventCommand. }
procedure RunCombat;
var
  Done: Byte;
  Who: PCharacter;
  Unused: Byte;
begin
  ViewMode := ViewModeCombat;
  SpellPickerPointer := @SelectSpellTargets;
  StartBattle;
  Done := 0;
  if (PartySideCount = 0) or (EnemySideCount = 0) then
    Done := 1;
  while Done = 0 do
  begin
    RecountCombatSides;
    Who := PCharacter(PartyListHead);
    while Who <> nil do
    begin
      StartCombatantRound(Who);
      Who := Who^.Next;
    end;
    GameVars2^[VarCombatWord715] := 0;
    PickNextCombatant(Who);
    while Who <> nil do
    begin
      CombatTurn(Who);
      PickNextCombatant(Who);
    end;
    EndCombatRound(Done);
  end;
  EndCombat;
end;
{ ovl08:0131. Picks the character who acts next: of the party list (PartyListHead, which holds every
  combatant) the one with the highest positive Combat^.Initiative; each candidate rolls 1d100
  (RollDice) and among equal initiatives the higher roll wins. Best is nil when nobody has an
  initiative above 0 any more, which ends the round in RunCombat. }
procedure PickNextCombatant(var Best: PCharacter);
var
  BestInit: Byte;
  BestRoll: Byte;
  Roll: Byte;
  Who: PCharacter;
  Unused: Byte;
begin
  BestInit := 0;
  BestRoll := 0;
  Who := PCharacter(PartyListHead);
  while Who <> nil do
  begin
    Roll := RollDice(1, 100);
    if Who^.Combat^.Initiative > BestInit then BestRoll := Roll;
    if (Who^.Combat^.Initiative >= BestInit) and (Roll >= BestRoll) then
    begin
      BestRoll := Roll;
      BestInit := Who^.Combat^.Initiative;
      Best := Who;
    end;
    Who := Who^.Next;
  end;
  if BestInit = NoInitiative then Best := nil;
end;
{ ovl08:01F6. One combat turn of Who: clears the per-turn fields BF, B12 and B7, runs the
  RunAffectHooks hook 7 and, while Who still has an initiative, selects it (SelectedCharacter), shows it
  (ShowCursorOn, RecalcCombatValues, DrawCharacterPanel), runs hook $F and lets the computer (QuickTurn, quick
  combat) or the player (PlayerTurn) act; then RedrawMapCell at its position (CombatantX, CombatantY).
  An initiative of InitiativeQuickAll (the Alt-Q fight) counts as $13. }
procedure CombatTurn(Who: PCharacter);
var
  Unused: Word;
begin
  Who^.Combat^.BF := 0;
  Who^.Combat^.B12 := 0;
  Who^.Combat^.B7 := 0;
  RunAffectHooks(7, Who);
  if Who^.Combat^.Initiative > 0 then
  begin
    if Who^.Combat^.Initiative = InitiativeQuickAll then Who^.Combat^.Initiative := InitiativeQuickAll - 1;
    SelectedCharacter := Who;
    ShowCursorOn(Who, 2, 1);
    RecalcCombatValues(Who);
    DrawCharacterPanel(Who);
    RunAffectHooks($F, Who);
    if Who^.Combat^.Initiative > 0 then
      if Who^.Quick <> 0 then
        QuickTurn(Who)
      else
        PlayerTurn(Who);
    RedrawMapCell(CombatantX(Who), CombatantY(Who));
  end;
end;
{ ovl08:031A. The player's turn for Who: a character with Flag10D clear ends it at once
  (EndCombatTurn). A pending spell (Combat^.PendingSpell) is cast through CastChosenSpell and ends the
  turn. Otherwise the CombatMenu key is carried out until Done: M Move (MoveCharacter), V View
  (ViewSelectedCharacter), A Aim (RunAimTargets), U Use (RunItemMenu), C Cast (CastCombatSpell), T Turn (TurnUndead), Q
  Quick (SetQuickCombat, the computer finishes the turn), D Done (EndTurnMenu), Space takes
  every character with B84 below $80 out of quick combat, and the Alt keys: Alt-M toggles Magic On/Off
  (MagicToggleOn), Alt-Q makes
  everybody quick, Alt-X asks GodsIntervene. After each command that does not end the turn the
  character is shown again. Done is the turn-ended flag the commands set. }
procedure PlayerTurn(Who: PCharacter);
var
  Cmd: Char;
  Done: Byte;
  Member: PCharacter;
  Aim: array[0..6] of Byte;
  Spell: Byte;
begin
  if Who^.Flag10D <> 0 then
  begin
    if Who^.Combat^.PendingSpell > 0 then
    begin
      Spell := Who^.Combat^.PendingSpell;
      Who^.Combat^.PendingSpell := 0;
      CastChosenSpell(Spell, 0, 1, Done);
      Done := EndCombatTurn(Who);
    end
    else
    begin
      Done := 0;
      while Done = 0 do
      begin
        CombatMenu(Who, Cmd);
        case Cmd of
          'M': MoveCharacter(Who, Done);
          'V':
          begin
            ViewSelectedCharacter(Done);
            RefreshAttacks(Who);
            if Done = 0 then DrawCombatScreen;
          end;
          'A': RunAimTargets(Who, $FF, 1, 0, Done, Aim);
          'U':
          begin
            RunItemMenu(Done);
            RefreshAttacks(Who);
            if Done = 0 then DrawCombatScreen;
          end;
          'C': CastCombatSpell(0, 0, Done);
          'T':
          begin
            TurnUndead(Who);
            Done := EndCombatTurn(Who);
          end;
          'Q':
          begin
            SetQuickCombat(Who);
            ClearPromptLine;
            FlushKeyboard;
            Delay(200);
            Done := 1;
            QuickTurn(Who);
          end;
          'D': EndTurnMenu(Who, Done);
          KeyAltM:
          begin
            MagicToggleOn := not MagicToggleOn;
            if MagicToggleOn then
              ShowFlashMessage('Magic On')
            else
              ShowFlashMessage('Magic Off');
          end;
          ' ':
          begin
            Member := PCharacter(PartyListHead);
            while Member <> nil do
            begin
              if Member^.B84 < $80 then Member^.Quick := 0;
              Member := Member^.Next;
            end;
          end;
          KeyQuickAll:
          begin
            Who^.Combat^.Initiative := InitiativeQuickAll;
            Member := PCharacter(PartyListHead);
            while Member <> nil do
            begin
              SetQuickCombat(Member);
              Member := Member^.Next;
            end;
            ClearPromptLine;
            Delay(200);
            Done := 1;
          end;
          KeyAltX:
            if GodsIntervene then
            begin
              ShowCursorOn(Who, 3, 0);
              Done := 1;
            end
            else
              ShowFlashMessage('That doesn''t work');
        end;
        if Done = 0 then
        begin
          ShowCursorOn(Who, 2, 1);
          DrawCharacterPanel(Who);
        end;
      end;
    end;
  end
  else
    Done := EndCombatTurn(Who);
end;
{ ovl08:0666. Shows the combat menu of Who and returns the key in Cmd: Move while it has moves
  left, View Aim, Use when it carries items, Cast when it has a memorized spell, may cast and the
  game variable VarNoCasting is 0, Turn for a cleric (ClassLevels[0]) that has not turned yet, and
  Quick Done. With the key flag of ReadPromptChoice set only the Alt keys pass; the menu repeats until one
  of the command keys of PlayerTurn comes. Flag first records whether a spell is memorized, then
  holds ReadPromptChoice's key flag. }
procedure CombatMenu(Who: PCharacter; var Cmd: Char);
var
  Menu: string[40];
  I: Byte;
  Flag: Byte;
begin
  RunAffectHooks($F, Who);
  Menu := '';
  if Who^.Combat^.Moves > 0 then Menu := Menu + 'Move ';
  Menu := Menu + 'View Aim ';
  if Who^.ItemCountC7 > 0 then Menu := Menu + 'Use ';
  Flag := 0;
  for I := 0 to 20 do
    if Who^.Spells[I] > 0 then Flag := 1;
  if (Flag <> 0) and (Who^.Combat^.CanCast <> 0) and (GameVars^[VarNoCasting] = 0) then
    Menu := Menu + 'Cast ';
  if (Who^.ClassLevels[0] > 0) and (Who^.Combat^.Turned = 0) then Menu := Menu + 'Turn ';
  Menu := Menu + 'Quick Done';
  repeat
    Cmd := ReadPromptChoice('', Menu, $D, $A, MenuColors, 1, 0, Flag);
    if (Flag <> 0) and not (Cmd in [KeyQuickAll, KeyAltR, KeyAltX, KeyAltM]) then Cmd := #0;
  until Cmd in [KeyQuickAll, KeyAltR, ' ', KeyAltX, KeyAltM, 'A', 'C', 'D', 'M', 'Q', 'T', 'U', 'V'];
end;
{ ovl08:0880. The end of a combat round: AdvanceGameClock(1, 1), the round counter CombatRound, UpdateMonsterMorale,
  then for each character the RunAffectHooks hook $13 and ApplyCloudTile; a dying character (StatusDying)
  bleeds one more round and after LastDyingRound rounds is StatusBledOut. Warns Your Teammate is
  Dying while a party member can be bandaged, redraws the map around the CombatMap view position
  (MoveCombatCursor), and sets Done when one side is empty (PartySideCount or EnemySideCount zero). When only the
  enemies are gone and SuppressContinuePrompt is 0 it asks Continue Battle: and Y clears Done again. Index is
  counted but never used. }
procedure EndCombatRound(var Done: Byte);
var
  Who: PCharacter;
  Unused: Byte;
  Index: Byte;
begin
  AdvanceGameClock(1, 1);
  Inc(CombatRound);
  UpdateMonsterMorale;
  Who := PCharacter(PartyListHead);
  Index := 1;
  while Who <> nil do
  begin
    RunAffectHooks($13, Who);
    ApplyCloudTile(Who);
    if Who^.Status = StatusDying then
    begin
      Inc(Who^.Combat^.DyingRounds);
      if Who^.Combat^.DyingRounds > LastDyingRound then Who^.Status := StatusBledOut;
    end;
    Inc(Index);
    Who := Who^.Next;
  end;
  if BandageDying(0) <> 0 then ShowFlashMessage('Your Teammate is Dying');
  RecountCombatSides;
  MoveCombatCursor(CombatMap^.ViewX + 3, CombatMap^.ViewY + 3, $FF, 8);
  if (PartySideCount = 0) or (EnemySideCount = 0) then Done := 1;
  if (PartySideCount > 0) and (EnemySideCount = 0) and (SuppressContinuePrompt = 0) then
    if AskYesNo('Continue Battle:', $D, $A, MenuColors) = 'Y' then Done := 0;
end;
{ ovl08:09DF. The Move command: while Who has more than one half-move left the prompt Move/Attack,
  Move Left = n takes keypad keys (KeyUp..KeyHome give the directions 0..7). A step towards a
  combatant attacks it (MeleeAttack, CombatantRecord by the number ProbeStep returns); a step off the map
  asks Flee: (TryFlee on Y); a step whose ground costs more than the moves left says Blocked;
  otherwise PartingShots and StepCombatant move the character, and a character whose Flag10D clears or
  for whom IsHelpless says so ends the turn (EndCombatTurn). Key #0 (Esc on the prompt) takes
  the move back: the saved moves, position (PlaceCombatant) and B9 return. Fewer than two half-moves
  left become 0. }
procedure MoveCharacter(Who: PCharacter; var Done: Byte);
var
  SavedMoves: Byte;
  SavedIconSet: Byte;
  Col: Byte;
  Row: Byte;
  Unused: Word;
  Dir: Byte;
  Other: Byte;
  Ground: Byte;
  Key: Char;
begin
  SavedMoves := Who^.Combat^.Moves;
  SavedIconSet := Who^.Combat^.IconSet;
  Col := CombatantX(Who);
  Row := CombatantY(Who);
  Key := ' ';
  Done := 0;
  Dir := NoDirection;
  while (Who^.Combat^.Moves > 1) and (Key <> #0) and (Key <> #13) do
  begin
    ClearWindow($18, $18, $27, $18);
    Key := ReadPromptChoice('Move/Attack, Move Left = ' + ByteToText(Who^.Combat^.Moves shr 1) + ' ', '',
      $A, $A, MenuColors, 1, 0, PromptKeyFlag);
    case Key of
      #0:
      begin
        Who^.Combat^.Moves := SavedMoves;
        RedrawGround(0, 0, CombatantIndex(Who));
        Done := Ord(not PlaceCombatant(Who, Col, Row, 0));
        MoveCombatCursor(CombatantX(Who), CombatantY(Who), 0, 8);
        Who^.Combat^.IconSet := SavedIconSet;
        Dir := NoDirection;
      end;
      KeyUp: Dir := 0;
      KeyPgUp: Dir := 1;
      KeyRight: Dir := 2;
      KeyPgDn: Dir := 3;
      KeyDown: Dir := 4;
      KeyEnd: Dir := 5;
      KeyLeft: Dir := 6;
      KeyHome: Dir := 7;
    else
      Dir := NoDirection;
    end;
    if Dir < NoDirection then
    begin
      SetCombatantIcon(Who, Dir, 0, 0);
      ProbeStep(Who, Dir, Other, Ground);
      if Other > 0 then
        MeleeAttack(Who, CombatantRecord[Other], Done)
      else if Ground = 0 then
        case AskYesNo('Flee:', $D, $A, MenuColors) of
          'Y': Done := TryFlee(Who);
          'N': Done := 0;
        end
      else if CombatTiles[Ground].Cost > Who^.Combat^.Moves then
        ShowFlashMessage('Blocked')
      else
      begin
        PartingShots(Who, Dir);
        if Who^.Flag10D = 0 then
          Done := EndCombatTurn(Who)
        else
        begin
          StepCombatant(Who, Dir);
          if Who^.Flag10D = 0 then Done := EndCombatTurn(Who);
          ApplyCloudTile(Who);
          if IsHelpless(Who) then Done := EndCombatTurn(Who);
        end;
      end;
    end;
  end;
  if Who^.Combat^.Moves < 2 then Who^.Combat^.Moves := 0;
end;
{ ovl08:0D45. Attacker attacks Target in melee: refused with Not with that weapon when
  IsRangedWeapon holds and RangedWeaponCanMelee does not (a weapon that cannot strike in melee, by the
  message); otherwise when ConfirmAttackTarget allows the attack Target becomes Attacker's Combat^.Target and
  either SweepEnemies ends the turn (Done := 1) or NoteAttackBearing and PerformAttack carry the attack out. }
procedure MeleeAttack(Attacker, Target: PCharacter; var Done: Byte);
begin
  if IsRangedWeapon(Attacker) and not RangedWeaponCanMelee(Attacker) then
    ShowFlashMessage('Not with that weapon')
  else if ConfirmAttackTarget(Attacker, Target) then
  begin
    Attacker^.Combat^.Target := Target;
    if SweepEnemies(Attacker, Target) then
      Done := 1
    else
    begin
      NoteAttackBearing(Attacker, Target);
      PerformAttack(Attacker, Target, 0, nil, Done);
    end;
  end;
end;
{ ovl08:0E45. The Done command's menu for Who: Guard (offered unless Not with that weapon would
  apply, GuardTurn), Delay (initiative InitiativeLast: act at the end of the round), Quit (end
  the turn), Bandage (when BandageDying finds a dying party member), Speed (GameSpeedMenu) and
  Exit. Repeats until Exit, Esc or a command that ends the turn. }
procedure EndTurnMenu(Who: PCharacter; var Done: Byte);
var
  Menu: string[40];
  Key: Char;
begin
  Done := 0;
  Menu := '';
  if not IsRangedWeapon(Who) or RangedWeaponCanMelee(Who) then Menu := Menu + 'Guard ';
  Menu := Menu + 'Delay Quit ';
  if BandageDying(0) <> 0 then Menu := Menu + 'Bandage ';
  Menu := Menu + 'Speed Exit';
  Key := ' ';
  while not (Key in [#0, 'E']) and (Done = 0) do
  begin
    Key := ReadPromptChoice('', Menu, $D, $A, MenuColors, 0, 0, PromptKeyFlag);
    case Key of
      'G': Done := GuardTurn(Who);
      'D':
      begin
        Who^.Combat^.Initiative := InitiativeLast;
        Done := 1;
      end;
      'Q': Done := EndCombatTurn(Who);
      'B':
      begin
        Done := BandageDying(1);
        Done := EndCombatTurn(Who);
      end;
      'S': GameSpeedMenu;
    end;
  end;
end;
{ ovl08:0FFF. Returns 1 when a party character (Side 0) is dying (StatusDying) and may be
  bandaged (Combat^.NoBody 0), else 0. With DoIt nonzero the first one found is bandaged: Status
  StatusBandaged, the bleeding count reset and the message is bandaged (ShowCharacterMessage). }
function BandageDying(DoIt: Byte): Byte;
var
  Who: PCharacter;
  Found: Byte;
begin
  Found := 0;
  Who := PCharacter(PartyListHead);
  while Who <> nil do
  begin
    if (Who^.Combat^.NoBody = 0) and (Who^.Side = 0) and (Who^.Status = StatusDying) then
    begin
      Found := 1;
      if DoIt <> 0 then
      begin
        Who^.Status := StatusBandaged;
        Who^.Combat^.DyingRounds := 0;
        ShowCharacterMessage(Who, 'is bandaged', 10, 1);
        DoIt := 0;
      end;
    end;
    Who := Who^.Next;
  end;
  BandageDying := Found;
end;
{ ovl08:10F6. The game speed menu: GameSpeed (n) : with Slower (while below MaxGameSpeed, raises
  GameSpeed), Faster (while above 0, lowers it) and Exit; repeats until Exit or Esc. }
procedure GameSpeedMenu;
var
  Menu: string[40];
  Title: string[40];
  Key: Char;
begin
  Key := ' ';
  while not (Key in [#0, 'E']) do
  begin
    Title := 'GameSpeed (' + ByteToText(GameSpeed) + ') :';
    Menu := ' ';
    if GameSpeed < MaxGameSpeed then Menu := Menu + 'Slower ';
    if GameSpeed > 0 then Menu := Menu + 'Faster ';
    Menu := Menu + 'Exit';
    Key := ReadPromptChoice(Title, Menu, $D, $A, MenuColors, 0, 0, PromptKeyFlag);
    case Key of
      'S': Inc(GameSpeed);
      'F': Dec(GameSpeed);
    end;
  end;
end;
{ ovl08:122B. Puts Who in quick combat (Quick := 1, the computer plays it from now on) and drops
  its remembered Combat^.Target when that target is on its own side. }
procedure SetQuickCombat(Who: PCharacter);
begin
  Who^.Quick := 1;
  if Who^.Combat^.Target <> nil then
    if Who^.Combat^.Target^.Side = Who^.Side then Who^.Combat^.Target := nil;
end;

begin
end.

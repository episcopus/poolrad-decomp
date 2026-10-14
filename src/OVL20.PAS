unit OVL20;
{ PartyHeal (re/units.toml): the camp's rest, 3685 bytes of code. RunRestPeriod is the rest that RestParty (ovl15)
  starts: it keeps the rest clock RestTime, shows the "Rest daYs Hours Mins Inc Dec Exit" menu, heals the party
  and reports interruptions. AdvanceAffectDurations spends elapsed game time on timed affects (whitepaper 5.22.1).
  AdvanceGameClock is the unit's main entry for other units: OVL03, OVL08, OVL14 and RunRestPeriod advance the
  game clock with it. }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS, RES06;
procedure AdvanceAffectDurations(Amount: Byte; Index: ShortInt);
procedure CarryRestClock(var Clock: TRestClock);
procedure NormalizeRestTime;
procedure AdvanceGameClock(Amount: Byte; Index: ShortInt);
procedure SpendRestTime(Amount: Byte; Index: ShortInt);
function TwoDigitText(Number: Byte): String40;
procedure ShowRestTime(Selected: ShortInt);
function RestTimeMenu: Byte;
procedure CheckRestHealing;
function ProcessMemorizedSpell(Who: PCharacter; var Handled: Byte): Byte;
function ProcessPendingScribedSpell(Who: PCharacter; var Handled: Byte): Byte;
procedure AdvanceRestStudies;
procedure AdvanceRestHour(var State: Byte);
function RunRestPeriod: Byte;
implementation
uses Crt, RES04, RES12, OVL22, OVL24, OVL25;
const
  RestLabelColumn = 1;      { the column of the "Rest Time:" label }
  RestFirstColumn = 11;     { the column where the days field starts }
  RestRow = 17;             { the text row of the rest time line }
  RestTextColour = 10;      { EGA colour of the rest time }
  RestSelectedColour = 15;  { EGA colour of the field the player is changing }
  RestCounterBytes = $48;   { bytes reset at ovl20:0CE5 }
  RestCounterInitial = 1;   { initial value stored by that FillChar }
  FirstPartyIndex = 1;      { RestStudyCountdowns is indexed from 1 by the party traversal }
  RestDisplayInterval = 5;  { five rest steps between time-line redraws }
  RestInterruptDice = 1;    { one roll per interruption check }
  RestInterruptSides = 100;
  RestMessageColumn = 1;
  RestMessageRow = $13;
  RestMessageColour = 15;
  RestStepsPerSpellLevel = 3; { ovl20:0B80 multiplies the returned level by three }
  RestMenuInitialSelection = 2; { the minutes field, which RestTimeMenu starts on and wraps to }
  RestHoursField = 3;           { RestTime digit of the hours, the field after the minutes }
  RestDaysField = 4;            { RestTime digit of the days, the last field }
  RestMinuteStep = 5;           { Inc and Dec on the minutes field move five minutes }
  RestTitleColour = 13;
  RestWordColour = 10;
  RestHotColour = 15;
  PendingSpellFlag = $80;
  SpellNumberMask = $7F;
  LastCharacterSpellSlot = 20;
  LastScrollSpellSlot = 3;
  RestStepsPerHour = 12; { ovl20:0BBE advances RestHours every twelve five-minute steps }
  RestHealCheckInterval = $120; { ovl20:0877 waits this many five-minute rest steps }
  ViewModeCamp = 2;          { ds49F3 while the party camps (MakeCamp sets it, ovl15:1E6F) }
  VarPartySize = 830;        { party member count, a word of the ds49D6 block (whitepaper 5.5) }
  MaxAffectStep = 10;        { ovl20:0097 spends elapsed affect time in passes of at most ten units }
  { The first of the seven game-clock words AdvanceGameClock advances, as a VarsAt4900 VM word address:
    the words at 49C6h..49CCh, that is GameVars^[198..204] (whitepaper 5.22.1). }
  GameClockWord = $49C6;

{ ovl20:0000. Spends elapsed game time on the party's timed affects. AdvanceGameClock calls it with the Amount
  and Index just added to the game clock. Those units are scaled down to the smallest digit (each higher
  digit multiplied by ClockRadix), then spent in passes of at most MaxAffectStep. Outside camp every
  member is marked due (FillChar of ds471E). In camp it returns at once when no TimedAffectFlags entry is set. A
  marked member's flag is cleared, then each affect loses the pass or is removed through RemoveAffect
  when its duration does not outlast the pass. Duration 0 is permanent and is left. The flag is set
  again while a timed affect remains. Reads ds49F3, ds49D6 word VarPartySize, ClockRadix and the party
  list ds5D96; changes TimedAffectFlags, ds471E and the affect lists. QUIRK ovl20:0118: NextAffect is loaded from
  the list head before the empty-list test, so a nil list reads through nil and the value is discarded. }
procedure AdvanceAffectDurations(Amount: Byte; Index: ShortInt);
var
  UnitIndex: ShortInt;          { the clock digit still to scale down to the smallest unit }
  PartyIndex: Byte;             { 1-based index of Who in the party list, and of TimedAffectFlags }
  AffectTimeStep: Byte;         { units taken off durations in this pass, at most MaxAffectStep }
  ScaledAmount: Word;           { elapsed time still to spend, in the smallest clock units }
  Who: PCharacter;
  AffectAtTail: Byte;           { 1 once the walk has reached the affect that was last at entry }
  HasTimedAffect: Byte;         { 1 when a camp member already has a TimedAffectFlags flag set }
  TailAffect: PAffect;          { the last affect on entry; removal can move the real tail }
  PreviousAffect: PAffect;      { a node at or before TargetAffect, used after RemoveAffect }
  NextAffect: PAffect;          { the node after the affect RemoveAffect is about to unlink }
  TargetAffect: PAffect;        { the affect this pass is shortening or removing }
begin
  if ds49F3 <> ViewModeCamp then
    FillChar(ds471E, RestCounterBytes, RestCounterInitial)
  else
  begin
    HasTimedAffect := 0;
    PartyIndex := FirstPartyIndex;
    repeat
      if TimedAffectFlags[PartyIndex] <> 0 then
        HasTimedAffect := 1;
      Inc(PartyIndex);
    until (HasTimedAffect <> 0) or (PartyIndex > ds49D6^[VarPartySize]);
    if HasTimedAffect = 0 then
      Exit;
  end;
  ScaledAmount := Amount;
  UnitIndex := Index;
  { Pred, not Dec or minus: ShortInt Pred is mov/dec/mov, and Pred as an index is dec then cwde
    (tools/re/tp_idioms/ovl20/PRB20_A.PAS). }
  while UnitIndex > 1 do
  begin
    ScaledAmount := ScaledAmount * ClockRadix[Pred(UnitIndex)];
    UnitIndex := Pred(UnitIndex);
  end;
  while ScaledAmount > 0 do
  begin
    if ScaledAmount > MaxAffectStep then
      AffectTimeStep := MaxAffectStep
    else
      AffectTimeStep := ScaledAmount;
    PartyIndex := FirstPartyIndex;
    Who := PCharacter(ds5D96);
    while Who <> nil do
    begin
      if TimedAffectFlags[PartyIndex] <> 0 then
      begin
        TimedAffectFlags[PartyIndex] := 0;
        TargetAffect := Who^.Affects;
        TailAffect := Who^.Affects;
        PreviousAffect := Who^.Affects;
        NextAffect := PreviousAffect^.Next;
        if Who^.Affects <> nil then
        begin
          while TailAffect^.Next <> nil do
            TailAffect := TailAffect^.Next;
        end;
        AffectAtTail := 0;
        while (TargetAffect <> nil) and (AffectAtTail = 0) do
        begin
          if TargetAffect = TailAffect then
            AffectAtTail := 1;
          if TargetAffect^.Duration = 0 then
            TargetAffect := TargetAffect^.Next
          else if AffectTimeStep < TargetAffect^.Duration then
          begin
            Dec(TargetAffect^.Duration, AffectTimeStep);
            TimedAffectFlags[PartyIndex] := 1;
            TargetAffect := TargetAffect^.Next;
          end
          else
          begin
            NextAffect := TargetAffect^.Next;
            RemoveAffect(Who, TargetAffect^.Id, TargetAffect);
            if PreviousAffect = Who^.Affects then
              TargetAffect := Who^.Affects
            else
              TargetAffect := NextAffect;
          end;
          PreviousAffect := Who^.Affects;
          while (PreviousAffect <> nil) and (PreviousAffect <> TargetAffect) and
                (PreviousAffect^.Next <> TargetAffect) do
            PreviousAffect := PreviousAffect^.Next;
        end;
        while TargetAffect <> nil do
        begin
          if TargetAffect^.Duration > 0 then
            TimedAffectFlags[PartyIndex] := 1;
          TargetAffect := TargetAffect^.Next;
        end;
      end;
      Inc(PartyIndex);
      Who := Who^.Next;
    end;
    if ScaledAmount > MaxAffectStep then
      Dec(ScaledAmount, MaxAffectStep)
    else
      ScaledAmount := 0;
  end;
end;
{ ovl20:02F2: retf 4: a var pointer to the rest clock (4 bytes of parameters); 6 bytes of locals.
  Carries the clock up its digits: digit I at or above its radix (ClockRadix[I], DS:363A) gives one
  unit to digit I+1 and loses the radix, for digits 0..5. The top digit has no next digit: while it is
  at or above its radix, every character on the party list gains one year of age (TCharacter.Age,
  +$30) and the radix is kept [I]. }
procedure CarryRestClock(var Clock: TRestClock);
var
  Digit: ShortInt;
  Who: PCharacter;
begin
  for Digit := 0 to 6 do
    if Clock[Digit] >= ClockRadix[Digit] then
      if Digit <> 6 then
      begin
        Inc(Clock[Succ(Digit)]);
        Clock[Digit] := Clock[Digit] - ClockRadix[Digit];
      end
      else
      begin
        Who := PCharacter(ds5D96);
        while Who <> nil do
        begin
          Inc(Who^.Age);
          Who := Who^.Next;
        end;
      end;
end;
{ ovl20:03A3: retf 0: no parameters, no locals. Settles the rest time after a change (ovl20:0721 and
  ovl20:047A call it): carries the clock, then turns the months (RestTime[5]) into days at ClockRadix[4],
  30 days a month, and keeps the days (RestTime[4]) at 99 (0x63) or less. }
procedure NormalizeRestTime;
begin
  CarryRestClock(RestTime);
  if RestTime[5] > 0 then
  begin
    Inc(RestTime[4], ClockRadix[4] * RestTime[5]);
    RestTime[5] := 0;
    if RestTime[4] > 99 then
      RestTime[4] := 99;
  end;
end;
{ ovl20:03D5: retf 4: Amount and Index (4 bytes of parameters); 18 bytes of locals. Advances the game clock by
  Amount units of digit Index: copies the seven game-clock words into a local clock, adds one unit per step
  and carries it (CarryRestClock), writes the clock back, then spends the elapsed time on timed affects
  (AdvanceAffectDurations with the same arguments). GameClockWord is the first of the seven words: the VM
  words at 49C6h..49CCh, that is GameVars^[198..204] (whitepaper 5.22.1). This is the unit's main entry for
  other units: EndCombatRound (ovl08:0880) advances it one unit of digit 1 at the end of a combat round,
  MoveParty, CheckMapCell and HandleWildernessKeys (ovl14) advance it during movement, and RunRestPeriod
  five minutes (Index 1) per rest step. Reads and writes VarsAt4900 and, through CarryRestClock, ClockRadix;
  side effects through AdvanceAffectDurations. }
procedure AdvanceGameClock(Amount: Byte; Index: ShortInt);
var
  Clock: TRestClock;
  Digit: ShortInt;
  Step: Byte;
begin
  for Digit := 0 to 6 do
    Clock[Digit] := VarsAt4900^[GameClockWord + Digit];
  for Step := 1 to Amount do
  begin
    Inc(Clock[Index]);
    CarryRestClock(Clock);
  end;
  for Digit := 0 to 6 do
    VarsAt4900^[GameClockWord + Digit] := Clock[Digit];
  AdvanceAffectDurations(Amount, Index);
end;
{ ovl20:047A: retf 4: Amount and Index (4 bytes of parameters); 4 bytes of locals. Takes Amount off the
  rest clock digit Index (the Dec key of the Rest menu, ovl20:0721, and the rest's countdown, RunRestPeriod).
  Nothing happens when the minutes, tens, hours and days (RestTime[1..4]) are all zero. Otherwise, while
  Amount is more than the digit, the next higher digit that is not zero lends one unit to the digits below
  it (each gets its radix, ClockRadix); when no such digit below the months is left, the clock is cleared
  and Amount becomes 0. The digit then loses Amount and the clock is normalized (NormalizeRestTime). }
procedure SpendRestTime(Amount: Byte; Index: ShortInt);
var
  Lender: ShortInt;
  Digit: ShortInt;
begin
  if (RestTime[4] <> 0) or (RestTime[3] <> 0) or (RestTime[2] <> 0) or (RestTime[1] <> 0) then
  begin
    while Amount > RestTime[Index] do
    begin
      Lender := Succ(Index);
      while (RestTime[Lender] = 0) and (Lender < 5) do
        Lender := Succ(Lender);
      if Lender = 5 then
      begin
        FillChar(RestTime, 14, 0);
        Amount := 0;
      end
      else
        for Digit := Lender downto Succ(Index) do
        begin
          Dec(RestTime[Digit]);
          Inc(RestTime[Pred(Digit)], ClockRadix[Pred(Digit)]);
        end;
    end;
    Dec(RestTime[Index], Amount);
    NormalizeRestTime;
  end;
end;
{ ovl20:0565: retf 2: Number (2 bytes of parameters) and the String40 result, which the caller pushes
  before Number; 298 bytes of locals (S and the compiler's string temporary). The result is Number as
  two characters: ByteToText gives its text, a '0' goes in front below 10, the first two are kept. }
function TwoDigitText(Number: Byte): String40;
var
  Digits: String40;
begin
  Digits := ByteToText(Number);
  if Number < 10 then
    Digits := '0' + Digits;
  TwoDigitText := Copy(Digits, 1, 2);
end;
{ ovl20:05F0: retf 2: Selected (2 bytes of parameters); 272 bytes of locals. Draws the rest time on row 17:
  "Rest Time:" and then days and hours as two digits with colons between them, and the minutes (the tens
  and the minutes of RestTime, 10 * RestTime[2] + RestTime[1]). The field Selected is drawn in colour 15,
  the others in 10. }
procedure ShowRestTime(Selected: ShortInt);
var
  Digit: ShortInt;
  Colors: array[0..6] of Word;
  Col: Byte;
begin
  for Digit := 0 to 6 do
    Colors[Digit] := RestTextColour;
  Colors[Selected] := RestSelectedColour;
  DrawTextAt(RestLabelColumn, RestRow, RestTextColour, 'Rest Time:');
  Col := RestFirstColumn;
  for Digit := 4 downto 3 do
  begin
    DrawTextAt(Col + 1, RestRow, Colors[Digit], TwoDigitText(RestTime[Digit]));
    DrawTextAt(Col + 1 + 1 + 1, RestRow, RestTextColour, ':');
    Inc(Col, 3);
  end;
  DrawTextAt(Col + 1, RestRow, Colors[2], TwoDigitText(10 * RestTime[2] + RestTime[1]));
end;
{ ovl20:0721: retf 0, 46 bytes of locals. The rest menu: "Rest daYs Hours Mins Inc Dec Exit" under the
  rest time line, until the player picks Rest (result 1) or Exit or Escape (result 0). Selected is the
  RestTime field being changed (2 minutes, 3 hours, 4 days), drawn highlighted by ShowRestTime. Y, H and
  M choose the field; the left and right arrows move between the fields (wrapping); Inc and Dec, or the
  up and down arrows, change it (five minutes at a time on the minutes field, through SpendRestTime for
  a decrease) and NormalizeRestTime carries the clock. Enter is Rest. Any other extended key does
  nothing. Matched from the expert's diagnosis (case-e3e08f09): the R arm sets the result and falls
  through to the until test, which ends the loop (07D5 jumps to 083D, not to the epilogue). }
function RestTimeMenu: Byte;
var
  ExtendedKey: Byte;
  Key: Char;
  Selected: ShortInt;
begin
  RestTimeMenu := 0;
  Selected := RestMenuInitialSelection;
  repeat
    ShowRestTime(Selected);
    Key := ReadPromptChoice('', 'Rest   daYs Hours Mins   Inc Dec   Exit',
                            RestTitleColour, RestWordColour, RestHotColour, 1, 0, ExtendedKey);
    if ExtendedKey <> 0 then
      case Key of
        'H': Key := 'I';
        'P': Key := 'D';
        'K':
          begin
            Inc(Selected);
            if Selected > RestDaysField then Selected := RestMenuInitialSelection;
            Key := 'X';
          end;
        'M':
          begin
            Dec(Selected);
            if Selected < RestMenuInitialSelection then Selected := RestDaysField;
            Key := 'X';
          end;
      else
        Key := 'X';
      end;
    if Key = #13 then Key := 'R';
    case Key of
      'R': RestTimeMenu := 1;
      'Y': Selected := RestDaysField;
      'H': Selected := RestHoursField;
      'M': Selected := RestMenuInitialSelection;
      'I':
        begin
          if Selected = RestMenuInitialSelection then
            Inc(RestTime[1], RestMinuteStep)
          else
            Inc(RestTime[Selected]);
          NormalizeRestTime;
        end;
      'D':
        begin
          if Selected = RestMenuInitialSelection then
            SpendRestTime(RestMinuteStep, 1)
          else
            SpendRestTime(1, Selected);
          NormalizeRestTime;
        end;
    end;
  until Key in [#0, 'E', 'R'];
end;
{ ovl20:0871: checks the party's healing once ds6DD8 reaches $120 rest steps. It calls HealCharacter for
  every party member, shows "The Whole Party Is Healed", redraws SelectedCharacter if anyone changed,
  delays, clears the message and resets ds6DD8. Reads the party list; changes ds6DD8 and character health;
  side effects are the screen and delay. }
procedure CheckRestHealing;
var
  Healed: Boolean;
  Who: PCharacter;
begin
  Inc(ds6DD8);
  if ds6DD8 >= RestHealCheckInterval then
  begin
    Healed := False;
    Who := PCharacter(ds5D96);
    while Who <> nil do
    begin
      if HealCharacter(Who, 1, 0) then Healed := True;
      Who := Who^.Next;
    end;
    ShowRestTime(0);
    DrawTextAt(RestMessageColumn, RestMessageRow, RestTextColour, 'The Whole Party Is Healed');
    if Healed then DrawPartyRoster(SelectedCharacter);
    DelayByGameSpeed;
    ClearCharacterMessage;
    ds6DD8 := 0;
  end;
end;
{ ovl20:0925: scans Who's 21 spell slots. When Handled is 0, the first spell with bit 7 set is completed:
  the bit is cleared, the rest-time line is redrawn, and ovl22_e8 receives Who, "has memorized" and the
  spell byte; Handled becomes 1. Once one is handled, the function returns the level of the next pending
  spell, or 0 when none remains. Reads SpellTable and changes Who^.Spells and Handled; also draws text. }
function ProcessMemorizedSpell(Who: PCharacter; var Handled: Byte): Byte;
var
  SpellLevel: Byte;
  SpellIndex: Byte;
begin
  SpellLevel := 0;
  SpellIndex := 0;
  while (SpellIndex <= LastCharacterSpellSlot) and (SpellLevel = 0) do
  begin
    if Who^.Spells[SpellIndex] > SpellNumberMask then
      if Handled <> 0 then
        SpellLevel := Byte(SpellTable[Who^.Spells[SpellIndex] and SpellNumberMask].Level)
      else
      begin
        Dec(Who^.Spells[SpellIndex], PendingSpellFlag);
        ShowRestTime(0);
        ovl22_e8(Who, 'has memorized', Who^.Spells[SpellIndex]);
        Handled := 1;
      end;
    Inc(SpellIndex);
  end;
  ProcessMemorizedSpell := SpellLevel;
end;
{ ovl20:09E7: for Who, scans carried scrolls and their three spell bytes for pending scribing (bit 7 set).
  When Handled is 0, it marks the first pending spell known, calls ovl22_e7 to consume it, redraws the
  rest-time line and reports "has scribed" through ovl22_e8; Handled becomes 1. When already handled, it
  returns the level of the next pending scroll spell, or 0. Reads Who^.Items and SpellTable; changes
  Who^.KnownSpells, the scroll and Handled; also changes the screen. }
function ProcessPendingScribedSpell(Who: PCharacter; var Handled: Byte): Byte;
var
  SpellIndex: Byte;
  SpellNumber: Byte;
  SpellLevel: Byte;
  Item: PItem;
begin
  SpellLevel := 0;
  Item := Who^.Items;
  while (Item <> nil) and (SpellLevel = 0) do
  begin
    SpellIndex := 1;
    if ovl22_e6(Item) then
    begin
      while (SpellIndex <= LastScrollSpellSlot) and (SpellLevel = 0) do
      begin
        if Item^.Affects[SpellIndex] > PendingSpellFlag then
          if Handled <> 0 then
            SpellLevel := Byte(SpellTable[Item^.Affects[SpellIndex] and SpellNumberMask].Level)
          else
          begin
            SpellNumber := Item^.Affects[SpellIndex] and SpellNumberMask;
            Who^.KnownSpells[SpellNumber] := 1;
            ovl22_e7(Who, Item, SpellNumber);
            ShowRestTime(0);
            ovl22_e8(Who, 'has scribed', SpellNumber);
            Handled := 1;
          end;
        Inc(SpellIndex);
      end;
    end;
    Item := Item^.Next;
  end;
  ProcessPendingScribedSpell := SpellLevel;
end;
{ ovl20:0B0A: visits each party member and decrements that member's RestStudyCountdowns rest counter. When the counter
  reaches zero and RestHours is zero, it completes a pending scribed spell first, then a memorized spell,
  and sets the counter to three times the next pending spell's level. Reads the party list and RestHours;
  changes RestStudyCountdowns, spell state and the screen through the study helpers. }
procedure AdvanceRestStudies;
var
  PartyIndex: Byte;
  SpellLevel: Byte;
  Who: PCharacter;
  Handled: Byte;
  UnusedFrameByte: Byte; { QUIRK ovl20:0B0A: reserved frame byte at [bp-8], never accessed }
begin
  PartyIndex := FirstPartyIndex;
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    Dec(RestStudyCountdowns[PartyIndex]);
    if RestStudyCountdowns[PartyIndex] = 0 then
      if Who^.RestHours = 0 then
      begin
        Handled := 0;
        SpellLevel := ProcessPendingScribedSpell(Who, Handled);
        if SpellLevel = 0 then
          SpellLevel := ProcessMemorizedSpell(Who, Handled);
        RestStudyCountdowns[PartyIndex] := SpellLevel * RestStepsPerSpellLevel;
      end;
    Who := Who^.Next;
    Inc(PartyIndex);
  end;
end;
{ ovl20:0BB2: counts twelve calls as one rest hour. At that point, it decreases each party member's
  RestHours when positive; on reaching zero, it reads the next pending scribed or memorized spell level
  and sets that member's RestStudyCountdowns entry to three times the level. State is a shared byte
  counter updated by reference. Reads the party list; changes State, RestHours, spell-related counts and
  RestStudyCountdowns. }
procedure AdvanceRestHour(var State: Byte);
var
  PartyIndex: Byte;
  SpellLevel: Byte;
  Who: PCharacter;
  Handled: Byte;
  UnusedFrameByte: Byte; { QUIRK ovl20:0BB2: reserved frame byte at [bp-8], never accessed }
begin
  Inc(State);
  if State >= RestStepsPerHour then
  begin
    State := 0;
    PartyIndex := FirstPartyIndex;
    Who := PCharacter(ds5D96);
    while Who <> nil do
    begin
      if ShortInt(Who^.RestHours) > 0 then
      begin
        Dec(Who^.RestHours);
        if Who^.RestHours = 0 then
        begin
          Handled := 1;
          SpellLevel := ProcessPendingScribedSpell(Who, Handled);
          if SpellLevel = 0 then
            SpellLevel := ProcessMemorizedSpell(Who, Handled);
          RestStudyCountdowns[PartyIndex] := SpellLevel * RestStepsPerSpellLevel;
        end;
      end;
      Who := Who^.Next;
      Inc(PartyIndex);
    end;
  end;
end;
{ ovl20:0C9A: rest countdown and interruptions. RestParty (ovl15:077A) calls this with no parameters and
  uses the byte result to decide whether the camp ends. It reads RestTime, the party list, ds49D6 game
  variables and ds49FB, and changes RestStudyCountdowns, ds471E and ds6DDA. Each five-minute step advances the game
  clock, runs rest effects and may trigger a random interruption. It draws the rest line and messages,
  asks whether to stop when a key is pending, and clears its window on exit. Result 1 means interrupted. }
function RunRestPeriod: Byte;
var
  Who: PCharacter;
  FrameGap: array[0..4] of Byte; { QUIRK ovl20:0C9A: frame bytes [bp-$A..bp-$6] are never accessed }
  PartyIndex: Byte;
  RestCycleCounter: Byte;
  DisplayCounter: Byte;
  EndRest: Byte;
  Unused: Byte;                  { QUIRK ovl20:0CA4: initialized but never read }
begin
  RunRestPeriod := 0;
  Unused := 0;
  PartyIndex := FirstPartyIndex;
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    RestStudyCountdowns[PartyIndex] := 0;
    Inc(PartyIndex);
    Who := Who^.Next;
  end;
  FillChar(ds471E, RestCounterBytes, RestCounterInitial);
  RestCycleCounter := 0;
  DisplayCounter := 0;
  ClearRect(1, $11, $26, $16);
  ShowRestTime(0);
  ds6DDA := 1;
  EndRest := Ord(RestTimeMenu = 0);
  while (EndRest = 0) and
        ((RestTime[4] > 0) or (RestTime[3] > 0) or (RestTime[2] > 0) or (RestTime[1] > 0)) do
  begin
    if KeyPressed then
    begin
      ShowRestTime(0);
      if AskYesNo('Stop Resting? ', 13, 10, 15) = 'Y' then
        EndRest := 1
      else
        ClearPromptLine;
    end;
    if EndRest = 0 then
    begin
      SpendRestTime(5, 1);
      Inc(DisplayCounter);
      if DisplayCounter >= RestDisplayInterval then
      begin
        ShowRestTime(0);
        DisplayCounter := 0;
      end;
      AdvanceGameClock(5, 1);
      CheckRestHealing;
      AdvanceRestStudies;
      AdvanceRestHour(RestCycleCounter);
      if ds49D6^[$2D2] > 0 then
      begin
        Inc(ds49FB);
        if ds49FB >= ds49D6^[$2D2] then
        begin
          ds49FB := 0;
          if RollDice(RestInterruptDice, RestInterruptSides) <= ds49D6^[$2D3] then
          begin
            ClearCharacterMessage;
            ShowRestTime(0);
            DrawTextAt(RestMessageColumn, RestMessageRow, RestMessageColour,
                       'The Party is rudely interrupted!');
            EndRest := 1;
            RunRestPeriod := 1;
            DelayByGameSpeed;
          end;
        end;
      end;
    end;
  end;
  ClearRect(1, $11, $26, $16);
  ds6DDA := 0;
end;

begin
end.

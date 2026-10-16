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
  RestFirstColumn = 11;     { the column before the days field; ShowRestTime draws the first days digit
                              at RestFirstColumn + 1 = 12, then moves right three columns a field }
  RestRow = 17;             { the text row of the rest time line }
  TopClockDigit = 6;        { the top digit of the clock (years); its carry ages the party instead of carrying }
  RestTextColor = 10;      { EGA colour of the rest time }
  RestSelectedColor = 15;  { EGA colour of the field the player is changing }
  TimedAffectFlagCount = $48; { the 72 TimedAffectFlags entries, one per party member (TimedAffectFlagsFrom0 is the same
                                bytes from index 1; the FillChar at ovl20:0000 and ovl20:0CE5 marks them) }
  TimedAffectDue = 1;         { the value that FillChar stores: every member's timed affects are due }
  FirstPartyIndex = 1;      { RestStudyCountdowns is indexed from 1 by the party traversal }
  RestDisplayInterval = 5;  { five rest steps between time-line redraws }
  RestInterruptDice = 1;    { one roll per interruption check }
  RestInterruptSides = 100;
  RestMessageColumn = 1;
  RestMessageRow = $13;
  RestMessageColor = 15;
  RestStepsPerSpellLevel = 3; { ovl20:0B80 multiplies the returned level by three }
  RestMinuteStep = 5;           { Inc and Dec on the minutes field move five minutes }
  RestHealAmount = 1;           { hit points HealCharacter restores at each whole-party heal (ovl20:0871) }
  RestTitleColor = 13;
  RestWordColor = 10;
  RestHotColor = 15;
  { The RestTime digits, the mixed-radix clock ovl20:02F2 carries (whitepaper 5.22.1). These are digit
    names, not menu fields: the menu's Selected is one of them. }
  MinutesDigit = 1;             { RestTime[1]: the minutes, the bottom digit; RestMinuteStep edits it }
  TensOfMinutesDigit = 2;       { RestTime[2]: the tens of minutes; ShowRestTime and the menu's minutes field }
  HoursDigit = 3;               { RestTime[3]: the hours }
  DaysDigit = 4;                { RestTime[4]: the days, kept at MaxRestDays or less }
  MonthsDigit = 5;              { RestTime[5]: the months, turned into days by NormalizeRestTime }
  MaxRestDays = 99;             { NormalizeRestTime keeps the days at this (0x63) or less }
  MinutesPerTensDigit = 10;     { the radix of MinutesDigit (ClockRadix[1], DS:363C); see ShowRestTime }
  { The rest window ovl20:0C9A clears and ShowRestTime draws in (ClearRect and DrawTextAt). }
  RestWindowLeft = 1;
  RestWindowTop = RestRow;
  RestWindowRight = $26;
  RestWindowBottom = $16;
  { The keys of the rest menu (ovl20:0721): the arrows are extended keys and the letters are plain
    keys, so ScanUp and the hours key both hold 'H' but mean different things. }
  KeyEnter = #13;
  KeyEscape = #0;               { the key ReadPromptChoice returns for Escape }
  KeyRest = 'R';
  KeyIgnore = 'X';              { the menu's internal do-nothing key, for the arrows and unknown extended keys }
  ScanUp = 'H';                 { extended key: up arrow, increases the selected field }
  ScanDown = 'P';               { extended key: down arrow, decreases the selected field }
  ScanLeft = 'K';               { extended key: left arrow, the field on the left (wraps) }
  ScanRight = 'M';              { extended key: right arrow, the field on the right (wraps) }
  PendingSpellFlag = $80;
  SpellNumberMask = $7F;
  LastCharacterSpellSlot = 20;
  LastScrollSpellSlot = 3;
  RestStepsPerHour = 12; { ovl20:0BBE advances RestHours every twelve five-minute steps }
  RestHealCheckInterval = $120; { ovl20:0877 waits this many five-minute rest steps }
  VarRestInterruptSteps = $2D2;  { GameVars2 word: rest steps between checks (ovl07:0160 clears it) }
  VarRestInterruptChance = $2D3; { GameVars2 word: percent chance per check, 1d100 (ovl07:0160 clears it) }
  MaxAffectStep = 10;        { ovl20:0097 spends elapsed affect time in passes of at most ten units }
  { The first of the seven game-clock words AdvanceGameClock advances, as a VarsAt4900 VM word address:
    the words at 49C6h..49CCh, that is GameVars^[198..204] (whitepaper 5.22.1). }
  GameClockWord = $49C6;

{ ovl20:0000. Spends elapsed game time on the party's timed affects. AdvanceGameClock calls it with the Amount
  and Index just added to the game clock. Those units are scaled down to the smallest digit (each higher
  digit multiplied by ClockRadix), then spent in passes of at most MaxAffectStep. Outside camp every
  member is marked due (FillChar of TimedAffectFlagsFrom0, the same 72 bytes as TimedAffectFlags from index 1; a port
  should use TimedAffectFlags). In camp it returns at once when no TimedAffectFlags entry is set. A
  marked member's flag is cleared, then each affect loses the pass or is removed through RemoveAffect
  when its duration does not outlast the pass. Duration 0 is permanent and is left. The flag is set
  again while a timed affect remains. Reads ViewMode, GameVars2 word VarPartySize, ClockRadix and the party
  list PartyListHead; changes TimedAffectFlags, TimedAffectFlagsFrom0 and the affect lists. QUIRK ovl20:0118:
  NextAffect is loaded from
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
  if ViewMode <> ViewModeCamp then
    FillChar(TimedAffectFlagsFrom0, TimedAffectFlagCount, TimedAffectDue)
  else
  begin
    HasTimedAffect := 0;
    PartyIndex := FirstPartyIndex;
    repeat
      if TimedAffectFlags[PartyIndex] <> 0 then
        HasTimedAffect := 1;
      Inc(PartyIndex);
    until (HasTimedAffect <> 0) or (PartyIndex > GameVars2^[VarPartySize]);
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
    Who := PCharacter(PartyListHead);
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
  unit to digit I+1 and loses the radix, for digits 0..5. The top digit has no next digit: at or above
  its radix it ages every character on the party list by one year (TCharacter.Age, +$30) and the radix
  is kept [I]. QUIRK ovl20:037B: the top digit is never reduced, so once Clock[TopClockDigit] is at or
  above its radix every later carry call ages the party again (whether the game can reach that is not
  proven). }
procedure CarryRestClock(var Clock: TRestClock);
var
  Digit: ShortInt;
  Who: PCharacter;
begin
  for Digit := 0 to TopClockDigit do
    if Clock[Digit] >= ClockRadix[Digit] then
      if Digit <> TopClockDigit then
      begin
        Inc(Clock[Succ(Digit)]);
        Clock[Digit] := Clock[Digit] - ClockRadix[Digit];
      end
      else
      begin
        Who := PCharacter(PartyListHead);
        while Who <> nil do
        begin
          Inc(Who^.Age);
          Who := Who^.Next;
        end;
      end;
end;
{ ovl20:03A3: retf 0: no parameters, no locals. Settles the rest time after a change (ovl20:0721 and
  ovl20:047A call it): carries the clock, then turns the months (RestTime[MonthsDigit]) into days at
  ClockRadix[DaysDigit], 30 days a month, and keeps the days (RestTime[DaysDigit]) at MaxRestDays or
  less. }
procedure NormalizeRestTime;
begin
  CarryRestClock(RestTime);
  if RestTime[MonthsDigit] > 0 then
  begin
    Inc(RestTime[DaysDigit], ClockRadix[DaysDigit] * RestTime[MonthsDigit]);
    RestTime[MonthsDigit] := 0;
    if RestTime[DaysDigit] > MaxRestDays then
      RestTime[DaysDigit] := MaxRestDays;
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
  Nothing happens when the minutes, tens, hours and days (RestTime[MinutesDigit..DaysDigit]) are all zero.
  Otherwise, while Amount is more than the digit, the next higher digit that is not zero lends one unit to
  the digits below it (each gets its radix, ClockRadix); when no such digit below the months is left, the
  clock is cleared and Amount becomes 0. The digit then loses Amount and the clock is normalized
  (NormalizeRestTime). }
procedure SpendRestTime(Amount: Byte; Index: ShortInt);
var
  Lender: ShortInt;
  Digit: ShortInt;
begin
  if (RestTime[DaysDigit] <> 0) or (RestTime[HoursDigit] <> 0) or
     (RestTime[TensOfMinutesDigit] <> 0) or (RestTime[MinutesDigit] <> 0) then
  begin
    while Amount > RestTime[Index] do
    begin
      Lender := Succ(Index);
      while (RestTime[Lender] = 0) and (Lender < MonthsDigit) do
        Lender := Succ(Lender);
      if Lender = MonthsDigit then
      begin
        FillChar(RestTime, SizeOf(RestTime), 0);
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
  "Rest Time:" and then days and hours as two digits with a colon between them, and the minutes (the tens
  and the minutes of RestTime, MinutesPerTensDigit * RestTime[TensOfMinutesDigit] +
  RestTime[MinutesDigit]). The field Selected is drawn in RestSelectedColor, the others in RestTextColor.
  Selected is a RestTime digit (TensOfMinutesDigit, HoursDigit or DaysDigit) or 0; Colors[0] is never
  drawn, so Selected 0 (every caller but the menu) highlights nothing. }
procedure ShowRestTime(Selected: ShortInt);
var
  Digit: ShortInt;
  Colors: array[0..6] of Word;
  Col: Byte;
begin
  for Digit := 0 to 6 do
    Colors[Digit] := RestTextColor;
  Colors[Selected] := RestSelectedColor;
  DrawTextAt(RestLabelColumn, RestRow, RestTextColor, 'Rest Time:');
  Col := RestFirstColumn;
  for Digit := DaysDigit downto HoursDigit do
  begin
    DrawTextAt(Col + 1, RestRow, Colors[Digit], TwoDigitText(RestTime[Digit]));
    { Col + 1 + 1 + 1 is the original's expression for the colon column, one past the two digits }
    DrawTextAt(Col + 1 + 1 + 1, RestRow, RestTextColor, ':');
    Inc(Col, 3);
  end;
  DrawTextAt(Col + 1, RestRow, Colors[TensOfMinutesDigit],
             TwoDigitText(MinutesPerTensDigit * RestTime[TensOfMinutesDigit] +
                          RestTime[MinutesDigit]));
end;
{ ovl20:0721: retf 0, 46 bytes of locals. The rest menu: "Rest daYs Hours Mins Inc Dec Exit" under the
  rest time line, until the player picks Rest (result 1) or Exit or Escape (result 0). Selected is the
  RestTime digit of the field being changed (TensOfMinutesDigit for the minutes, HoursDigit, DaysDigit),
  drawn highlighted by ShowRestTime. Y, H and M choose the days, hours and minutes field; the arrow keys
  move between the fields (wrapping); Inc and Dec, or the up and down arrows, change the field (five
  minutes at a time on the minutes field, through SpendRestTime for a decrease) and NormalizeRestTime
  carries the clock. Enter is Rest. The arrows and any unknown extended key set KeyIgnore 'X', which no
  case arm handles, so nothing happens. The R arm sets the result and falls through to the until test,
  which ends the loop (07D5 jumps to 083D, not to the epilogue). }
function RestTimeMenu: Byte;
var
  ExtendedKey: Byte;
  Key: Char;
  Selected: ShortInt;
begin
  RestTimeMenu := 0;
  Selected := TensOfMinutesDigit;
  repeat
    ShowRestTime(Selected);
    Key := ReadPromptChoice('', 'Rest   daYs Hours Mins   Inc Dec   Exit',
                            RestTitleColor, RestWordColor, RestHotColor, 1, 0, ExtendedKey);
    if ExtendedKey <> 0 then
      case Key of
        ScanUp: Key := 'I';
        ScanDown: Key := 'D';
        ScanLeft:
          begin
            Inc(Selected);
            if Selected > DaysDigit then Selected := TensOfMinutesDigit;
            Key := KeyIgnore;
          end;
        ScanRight:
          begin
            Dec(Selected);
            if Selected < TensOfMinutesDigit then Selected := DaysDigit;
            Key := KeyIgnore;
          end;
      else
        Key := KeyIgnore;
      end;
    if Key = KeyEnter then Key := KeyRest;
    case Key of
      KeyRest: RestTimeMenu := 1;
      'Y': Selected := DaysDigit;
      'H': Selected := HoursDigit;
      'M': Selected := TensOfMinutesDigit;
      'I':
        begin
          if Selected = TensOfMinutesDigit then
            Inc(RestTime[MinutesDigit], RestMinuteStep)
          else
            Inc(RestTime[Selected]);
          NormalizeRestTime;
        end;
      'D':
        begin
          if Selected = TensOfMinutesDigit then
            SpendRestTime(RestMinuteStep, MinutesDigit)
          else
            SpendRestTime(1, Selected);
          NormalizeRestTime;
        end;
    end;
  until Key in [KeyEscape, KeyExit, KeyRest];
end;
{ ovl20:0871: the whole-party heal of the rest. RestHealCounter counts five-minute rest steps; at
  RestHealCheckInterval ($120, 288 steps, 24 hours) every party member is healed one hit point
  (HealCharacter with RestHealAmount and flag 0, so a member with affect $32 is skipped) and the message
  "The Whole Party Is Healed" is shown. The roster is redrawn only when someone actually healed. It then
  delays, clears the message and resets RestHealCounter. Reads the party list; changes RestHealCounter and
  character health; side effects are the screen and delay. }
procedure CheckRestHealing;
var
  Healed: Boolean;
  Who: PCharacter;
begin
  Inc(RestHealCounter);
  if RestHealCounter >= RestHealCheckInterval then
  begin
    Healed := False;
    Who := PCharacter(PartyListHead);
    while Who <> nil do
    begin
      { RestHealAmount hit points; flag 0, so HealCharacter skips a member with affect $32 (ovl24:175D) }
      if HealCharacter(Who, RestHealAmount, 0) then Healed := True;
      Who := Who^.Next;
    end;
    ShowRestTime(0);
    { the original draws this message in colour 10 (RestTextColor), not the interruption message's
      RestMessageColor 15; the healing itself is what the message claims }
    DrawTextAt(RestMessageColumn, RestMessageRow, RestTextColor, 'The Whole Party Is Healed');
    if Healed then DrawPartyRoster(SelectedCharacter);
    DelayByGameSpeed;
    ClearCharacterMessage;
    RestHealCounter := 0;
  end;
end;
{ ovl20:0925: scans Who's 21 spell slots. When Handled is 0, the first spell with bit 7 set is completed:
  the bit is cleared, the rest-time line is redrawn, and ShowSpellMessage receives Who, "has memorized" and the
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
        ShowSpellMessage(Who, 'has memorized', Who^.Spells[SpellIndex]);
        Handled := 1;
      end;
    Inc(SpellIndex);
  end;
  ProcessMemorizedSpell := SpellLevel;
end;
{ ovl20:09E7: for Who, scans carried scrolls and their three spell bytes for pending scribing (bit 7 set).
  When Handled is 0, it marks the first pending spell known, calls ConsumeScrollSpell to consume it, redraws the
  rest-time line and reports "has scribed" through ShowSpellMessage; Handled becomes 1. When already handled, it
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
    if IsScroll(Item) then
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
            ConsumeScrollSpell(Who, Item, SpellNumber);
            ShowRestTime(0);
            ShowSpellMessage(Who, 'has scribed', SpellNumber);
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
  Who := PCharacter(PartyListHead);
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
    Who := PCharacter(PartyListHead);
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
  uses the byte result to decide whether the camp ends. It reads RestTime, the party list, the GameVars2 game
  words and RestInterruptCounter, and changes RestStudyCountdowns, TimedAffectFlagsFrom0 and RestWindowActive. Each
  five-minute step spends rest time, advances the game clock, runs the rest's healing and study, and may
  trigger a random interruption: while GameVars2 word VarRestInterruptSteps is nonzero it counts the rest
  steps in RestInterruptCounter; at that threshold the counter resets and a 1d100 RollDice no greater than
  GameVars2 word VarRestInterruptChance interrupts. It draws the rest line and messages, asks whether to stop
  when a key is pending, and clears its window on exit. Result 1 means interrupted. }
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
  Who := PCharacter(PartyListHead);
  while Who <> nil do
  begin
    RestStudyCountdowns[PartyIndex] := 0;
    Inc(PartyIndex);
    Who := Who^.Next;
  end;
  FillChar(TimedAffectFlagsFrom0, TimedAffectFlagCount, TimedAffectDue);
  RestCycleCounter := 0;
  DisplayCounter := 0;
  ClearRect(RestWindowLeft, RestWindowTop, RestWindowRight, RestWindowBottom);
  ShowRestTime(0);
  RestWindowActive := 1;
  EndRest := Ord(RestTimeMenu = 0);
  while (EndRest = 0) and
        ((RestTime[DaysDigit] > 0) or (RestTime[HoursDigit] > 0) or
         (RestTime[TensOfMinutesDigit] > 0) or (RestTime[MinutesDigit] > 0)) do
  begin
    if KeyPressed then
    begin
      ShowRestTime(0);
      if AskYesNo('Stop Resting? ', RestTitleColor, RestWordColor, RestHotColor) = 'Y' then
        EndRest := 1
      else
        ClearPromptLine;
    end;
    if EndRest = 0 then
    begin
      SpendRestTime(RestMinuteStep, MinutesDigit);
      Inc(DisplayCounter);
      if DisplayCounter >= RestDisplayInterval then
      begin
        ShowRestTime(0);
        DisplayCounter := 0;
      end;
      AdvanceGameClock(RestMinuteStep, MinutesDigit);
      CheckRestHealing;
      AdvanceRestStudies;
      AdvanceRestHour(RestCycleCounter);
      if GameVars2^[VarRestInterruptSteps] > 0 then
      begin
        Inc(RestInterruptCounter);
        if RestInterruptCounter >= GameVars2^[VarRestInterruptSteps] then
        begin
          RestInterruptCounter := 0;
          if RollDice(RestInterruptDice, RestInterruptSides) <= GameVars2^[VarRestInterruptChance] then
          begin
            ClearCharacterMessage;
            ShowRestTime(0);
            DrawTextAt(RestMessageColumn, RestMessageRow, RestMessageColor,
                       'The Party is rudely interrupted!');
            EndRest := 1;
            RunRestPeriod := 1;
            DelayByGameSpeed;
          end;
        end;
      end;
    end;
  end;
  ClearRect(RestWindowLeft, RestWindowTop, RestWindowRight, RestWindowBottom);
  RestWindowActive := 0;
end;

begin
end.

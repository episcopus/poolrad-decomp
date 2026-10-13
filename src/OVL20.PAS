unit OVL20;
{ PartyHeal (re/units.toml): the camp's rest, 3685 bytes of code. RunRestPeriod is the rest that RestParty (ovl15)
  starts: it keeps the rest clock RestTime, shows the "Rest daYs Hours Mins Inc Dec Exit" menu, heals the party
  and reports interruptions (whitepaper 5.22). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06;
procedure ovl20_fn_0000(Amount: Byte; Index: ShortInt);
procedure CarryRestClock(var Clock: TRestClock);
procedure NormalizeRestTime;
procedure ovl20_e1(Amount: Byte; Index: ShortInt);
procedure SpendRestTime(Amount: Byte; Index: ShortInt);
function TwoDigitText(Number: Byte): String40;
procedure ShowRestTime(Selected: ShortInt);
function ovl20_fn_0721: Byte;
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
  RestMenuInitialSelection = 2;
  RestTitleColour = 13;
  RestWordColour = 10;
  RestHotColour = 15;
  PendingSpellFlag = $80;
  SpellNumberMask = $7F;
  LastCharacterSpellSlot = 20;
  LastScrollSpellSlot = 3;
  RestStepsPerHour = 12; { ovl20:0BBE advances RestHours every twelve five-minute steps }
  RestHealCheckInterval = $120; { ovl20:0877 waits this many five-minute rest steps }

{ ovl20:0000: retf 4: 4 bytes of parameters; 28 bytes of locals }
{@stub} procedure ovl20_fn_0000(Amount: Byte; Index: ShortInt); begin end;
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
  Amount units of digit Index: the seven game variables at 49C6h..49CCh (VarsAt4900, the digits CarryRestClock
  works on) are copied to a local clock, each unit is added and carried, and the clock is written back; then
  ovl20_fn_0000 runs with the same arguments. The camp's rest advances it 5 minutes at a time (RunRestPeriod calls
  it with Index 1 and Amount 5). Purpose unknown: the name stays as the entry other units call (OVL14, OVL15,
  OVL08 and RunRestPeriod reference it, so a rename is a cross-unit change); what the passing time changes is in
  ovl20_fn_0000, not decompiled yet. }
procedure ovl20_e1(Amount: Byte; Index: ShortInt);
var
  Clock: TRestClock;
  Digit: ShortInt;
  Step: Byte;
begin
  for Digit := 0 to 6 do
    Clock[Digit] := VarsAt4900^[$49C6 + Digit];
  for Step := 1 to Amount do
  begin
    Inc(Clock[Index]);
    CarryRestClock(Clock);
  end;
  for Digit := 0 to 6 do
    VarsAt4900^[$49C6 + Digit] := Clock[Digit];
  ovl20_fn_0000(Amount, Index);
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
  two characters: res12_fn_1037 gives its text, a '0' goes in front below 10, the first two are kept. }
function TwoDigitText(Number: Byte): String40;
var
  Digits: String40;
begin
  Digits := res12_fn_1037(Number);
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
{ ovl20:0721: retf 0, 46 bytes of locals; the rest-menu draft and five failed match attempts are in re/symbols.toml. }
{@stub} function ovl20_fn_0721: Byte; begin end;
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
    if Healed then res12_fn_0767(SelectedCharacter);
    DelayByGameSpeed;
    res12_fn_17E3;
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
  EndRest := Ord(ovl20_fn_0721 = 0);
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
      ovl20_e1(5, 1);
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
            res12_fn_17E3;
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

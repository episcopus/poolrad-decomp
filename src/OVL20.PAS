unit OVL20;
{ PartyHeal (re/units.toml): the camp's rest, 3685 bytes of code. ovl20_e2 is the rest that RestParty (ovl15)
  starts: it keeps the rest clock RestTime, shows the "Rest daYs Hours Mins Inc Dec Exit" menu, heals the party
  and reports interruptions (whitepaper 5.22). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ovl20_fn_0000;
procedure CarryRestClock(var Clock: TRestClock);
procedure NormalizeRestTime;
procedure ovl20_e1(A, B: Byte);
procedure ovl20_fn_047A;
procedure ovl20_fn_0565;
procedure ovl20_fn_05F0;
procedure ovl20_fn_0721;
procedure ovl20_fn_0871;
procedure ovl20_fn_0925;
procedure ovl20_fn_099E;
procedure ovl20_fn_09A3;
procedure ovl20_fn_09A8;
procedure ovl20_fn_09E7;
procedure ovl20_fn_0B0A;
procedure ovl20_fn_0B2A;
procedure ovl20_fn_0B48;
procedure ovl20_fn_0B89;
procedure ovl20_fn_0BB2;
function ovl20_e2: Byte;
implementation

{ ovl20:0000: retf 4: 4 bytes of parameters; 28 bytes of locals }
{@stub} procedure ovl20_fn_0000; begin end;
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
{ ovl20:03D5: retf 4: 4 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl20_e1(A, B: Byte); begin end;
{ ovl20:047A: retf 4: 4 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl20_fn_047A; begin end;
{ ovl20:0565: retf 2: 2 bytes of parameters; 298 bytes of locals }
{@stub} procedure ovl20_fn_0565; begin end;
{ ovl20:05F0: retf 2: 2 bytes of parameters; 272 bytes of locals }
{@stub} procedure ovl20_fn_05F0; begin end;
{ ovl20:0721: retf 0: 0 bytes of parameters; 46 bytes of locals }
{@stub} procedure ovl20_fn_0721; begin end;
{ ovl20:0871: retf 0: 0 bytes of parameters; 32 bytes of locals }
{@stub} procedure ovl20_fn_0871; begin end;
{ ovl20:0925: frame not read }
{@stub} procedure ovl20_fn_0925; begin end;
{ ovl20:099E: frame not read }
{@stub} procedure ovl20_fn_099E; begin end;
{ ovl20:09A3: frame not read }
{@stub} procedure ovl20_fn_09A3; begin end;
{ ovl20:09A8: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl20_fn_09A8; begin end;
{ ovl20:09E7: retf 8: 8 bytes of parameters; 20 bytes of locals }
{@stub} procedure ovl20_fn_09E7; begin end;
{ ovl20:0B0A: frame not read }
{@stub} procedure ovl20_fn_0B0A; begin end;
{ ovl20:0B2A: frame not read }
{@stub} procedure ovl20_fn_0B2A; begin end;
{ ovl20:0B48: frame not read }
{@stub} procedure ovl20_fn_0B48; begin end;
{ ovl20:0B89: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl20_fn_0B89; begin end;
{ ovl20:0BB2: retf 4: 4 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl20_fn_0BB2; begin end;
{ ovl20:0C9A: retf 0: 0 bytes of parameters; 48 bytes of locals }
{@stub} function ovl20_e2: Byte; begin end;

begin
end.

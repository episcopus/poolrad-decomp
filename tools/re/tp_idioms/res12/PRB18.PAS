{ Probe for res12:1FEB (playbook 30).
  Question: what nested-loop source produces
    mov [inner],0; jmp body; inc [inner]; body: ...; cmp [inner],3; jne inc
  at the bottom and, for the outer,
    mov al,0; cmp al,[count]; ja end; mov [outer],0; ...; inc [outer];
    cmp [outer],[count]; jne inc
  The original is 00BA:20DE..2161. }
{$F+,S-,R-,I-}
program Res12Probe18;

var
  Count: Byte;
  Outer, Inner: Byte;
  Acc: Byte;

procedure ForZeroToCount;
begin
  for Outer := 0 to Count do
    for Inner := 0 to 3 do
      Acc := Inner;
end;

procedure ForZeroToTwo;
begin
  for Outer := 0 to Count do
    for Inner := 0 to 2 do
      Acc := Inner;
end;

procedure ForOneToThree;
begin
  for Outer := 1 to Count do
    for Inner := 1 to 3 do
      Acc := Inner;
end;

begin
  ForZeroToCount;
  ForZeroToTwo;
  ForOneToThree;
end.

unit OVL23;
{ ovl23: overlay unit, 1123 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure ovl23_e1;
procedure IncrementBonuses(Character: Pointer);
procedure ovl23_e3;
procedure ovl23_e4;
implementation
uses POOLVARS;

{ ovl23:0000: retf 4: 4 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl23_e1; begin end;
{ ovl23:01AF. Bumps the character's Bonus counters when its third ability score passes
  12 to 16: Bonus[1] gains a point at 13 and 14, Bonus[2] at 15 and 16, Bonus[3] at 17, each
  only when already nonzero. Called after the Bonus bytes are seeded (ovl16 three times,
  ovl23_e1). The ability and bonus meanings are still open (whitepaper 5.3). }
procedure IncrementBonuses(Character: Pointer);
begin
  with PCharacter(Character)^ do
  begin
    if (Ability[2] > $0C) and (Bonus[1] > 0) then Inc(Bonus[1]);
    if (Ability[2] > $0D) and (Bonus[1] > 0) then Inc(Bonus[1]);
    if (Ability[2] > $0E) and (Bonus[2] > 0) then Inc(Bonus[2]);
    if (Ability[2] > $0F) and (Bonus[2] > 0) then Inc(Bonus[2]);
    if (Ability[2] > $10) and (Bonus[3] > 0) then Inc(Bonus[3]);
  end;
end;
{ ovl23:0255: retf 4: 4 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl23_e3; begin end;
{ ovl23:0329: retf 4: 4 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl23_e4; begin end;

begin
end.

{ Probe for ovl16:2033 (playbook 30, batch 12). It tests whether the routine that ovl16:209F calls
  with `push ax; push bp; push cs; call` is a nested procedure reading the parent's local at
  [bp-0xd] (static link), or a top-level routine taking a pointer parameter. The nested form should
  put the code in the parent's pre-entry region and read ss:[di-0xd]. Callees in another segment are
  declared in NESTU so they compile to lcall. }
{$A-,O+,F+,S-,R-,G-,I-}
program NestProbe1;

uses NESTU;

procedure Parent;
var
  StatIndex: Byte;
  Highlight: Byte;

  procedure ShowStat(On_: Boolean);
  begin
    if StatIndex < 6 then
      ShowAbilityScore(StatIndex, On_)
    else
      DrawHitPoints(SelectedCharacter, 4, $12, Byte(On_));
  end;

begin
  StatIndex := 6;
  ShowStat(False);
  StatIndex := 0;
  ShowStat(True);
end;

begin
  Parent;
end.

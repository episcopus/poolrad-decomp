{ Probe for the ovl16:3C89..3E2F entries (playbook 30, batch 15). Question: does TP 6.0 start a
  far procedure with no parameters and no locals with a prologue (push bp; mov bp,sp), or can a
  routine begin on an arbitrary instruction? If every routine begins with 55 8b ec / 55 89 e5, then
  the map addresses 3C89 (`c6 85 be 00 1f`), 3C8E (`eb 66`), 3C93 (the disp byte of `75 20`), 3D34
  (`88 46 e7`), 3E2A (`26 8a 85 bf 00`) and 3E2F (`50`), none of which begin with a prologue, cannot
  be routine starts. The unit's own switches are used so the result applies to OVL16. }
{$A-,O+,F+,S-,R-,G-,I-}
program NoProcProbe;

procedure Empty; begin end;

procedure OneLocal;
var B: Byte;
begin
  B := 1;
end;

begin
  Empty;
  OneLocal;
end.

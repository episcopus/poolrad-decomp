(* Probe PRBVIEW (ovl13, 2026-10-13): ovl13:160F reads Target+RearAttack+$111 with a sign-extended
   index: mov al,[bp-0x18]; cwde; les di,[bp+0xc]; add di,ax; mov al,es:[di+0x111].
   Target a pointer to a view record with the pair at +$111 (not changing TCharacter).
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBVIEW.PAS DISASM=1 *)
program PrbView;
{$A-,O+,F-,S-,R-,G-,I-}
type
  TChar = record Pad: array[0..$10F] of Byte; Pair: Byte; end;
  PChar = ^TChar;
  TView = record Pad: array[0..$110] of Byte; Pair: array[0..1] of Byte; end;
  PView = ^TView;
var
  GP: PChar;
  G: Byte;
  Idx: ShortInt;

function A1(P: PChar): Byte;
var
  Idx: ShortInt;
begin
  Idx := 0;
  A1 := PView(P)^.Pair[Idx];
end;

function A2(P: PChar): Byte;
var
  Idx: Byte;
begin
  Idx := 0;
  A2 := PView(P)^.Pair[Idx];
end;

begin
  GP := nil;
  G := 0;
  Idx := 0;
  G := A1(GP) + A2(GP);
end.

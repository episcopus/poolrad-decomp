{ Probe: how InitSpellHandlers (ovl22:3413) assigns @Routine into the DS:6B84 handler block.
  `SpellHandlers[N] := Routine;` (a bare procedural assignment) compiles to
  `mov ax, OFFSET; mov dx, SEG; mov [base+4N], ax; mov [base+4N+2], dx`, the two stores the
  original has. With @ (`:= @Routine`) TP 6.0 gives Error 122 (Invalid variable reference) for a
  procedural-typed destination; @ is only for a Pointer-typed destination (as ovl08's
  `ds6B84 := @ChooseSpellTargets`).
  make tpc SRC=tools/re/tp_idioms/ovl22/HANDLRTB.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
program PrbHandlerTbl;

type
  TSpellHandler = procedure;

var
  SpellHandlers: array[0..$43] of TSpellHandler;
  ds6B84: Pointer absolute SpellHandlers;
  ds6988: Pointer;

procedure CastBless; far;
begin
end;

procedure MonsterBreath; far;
begin
end;

begin
  SpellHandlers[1] := CastBless;          { procedural assignment: no @ }
  SpellHandlers[2] := MonsterBreath;
  ds6988 := @MonsterBreath;               { a Pointer destination does take @ }
end.

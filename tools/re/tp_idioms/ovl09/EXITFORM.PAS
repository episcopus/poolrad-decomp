{ Probe EXITFORM (ovl09, 2026-10-13): two early-exit forms TP 6.0 compiles differently.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl09/EXITFORM.PAS DISASM=1
  Result (TP 6.0 June 1991, default switches):
  - EarlyExit: `if C then Exit;` compiles to `eval C; j!C skip; jmp epilogue; skip:` (two
    branches, like ovl09:0307 jae + 0309 jmp).
  - Wrapped: `if C then begin <rest> end;` as the last statement compiles to a single
    `j!C tail` when the if-body reaches the function tail (like ovl09:0361 jbe 03DB). So an
    original single conditional branch to the tail means the rest was wrapped, not an Exit.
  Found while matching ovl09:02EB (see re/learnings/ovl09.toml#early-exit-vs-wrapper-if). }
program ExitForm;
var
  G: Byte;

function EarlyExit(Limit: Byte): Boolean;
var
  I: Byte;
begin
  EarlyExit := False;
  if Limit <= 0 then
    Exit;
  for I := 1 to Limit do
    if G = 1 then
      Exit;
  EarlyExit := True;
end;

function Wrapped(Limit: Byte): Boolean;
var
  I: Byte;
begin
  Wrapped := False;
  if Limit > 0 then
  begin
    for I := 1 to Limit do
      if G = 1 then
        Exit;
    Wrapped := True;
  end;
end;

begin
  G := 3;
  if EarlyExit(G) = Wrapped(G) then
    G := 0;
end.

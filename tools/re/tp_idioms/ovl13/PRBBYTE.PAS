(* Probe PRBBYTE (ovl13, 2026-10-13): which source makes an update of the byte cell
  CombatantTable[Idx].X by DirStepX[Dir] compile to the original ovl13:0923..0939 shape
  (`mov dl,[DirStepX]; mov al,Idx; xor ah,ah; ...; add byte [table+0],dl`, an 8-bit memory add)
  rather than the 16-bit load/add/store our first draft gave (`mov al,[DirStepX]; cwde; ...;
  add ax,dx; mov dl,al`). DirStepX is ShortInt (StepCombatant sign-extends it: ovl13:0792 cwde).
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBBYTE.PAS DISASM=1 *)
program PrbByte;
{$A-,F+}
type
  TEntrySigned = record X, Y: ShortInt; U, K: Byte; end;
  TEntryByte = record X, Y: Byte; U, K: Byte; end;
var
  TableS: array[0..72] of TEntrySigned;
  TableB: array[0..72] of TEntryByte;
  Step: array[0..8] of ShortInt;
  Idx, Dir: Byte;

procedure SignedAssign;
begin TableS[Idx].X := TableS[Idx].X + Step[Dir]; end;

procedure SignedInc;
begin Inc(TableS[Idx].X, Step[Dir]); end;

procedure SignedCast;
begin TableS[Idx].X := TableS[Idx].X + Byte(Step[Dir]); end;

procedure SignedBothCast;
begin TableS[Idx].X := Byte(TableS[Idx].X) + Byte(Step[Dir]); end;

procedure ByteFieldAssign;
begin TableB[Idx].X := TableB[Idx].X + Step[Dir]; end;

procedure ByteFieldInc;
begin Inc(TableB[Idx].X, Step[Dir]); end;

begin
  SignedAssign; SignedInc; SignedCast; SignedBothCast; ByteFieldAssign; ByteFieldInc;
end.

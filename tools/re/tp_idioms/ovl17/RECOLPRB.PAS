{ Probe for ovl17_e3's recolour block (playbook 30).
  Question: our source's `if Recolor then` block is 2 bytes shorter than the original's
  0x576..0x65A. Which statement differs? }
{$F+,S-,R-,I-}
program RecolorProbe;

type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$BE] of Byte;
    CombatIcon: Byte;
    Figure: array[0..6] of Byte;
  end;

var
  SelectedCharacter: PCharacter;
  ds3CF5: array[0..$F] of Byte;
  ds5E5A: array[0..$F] of Pointer;
  Recolor: Boolean;

procedure res07_fn_1E5C(FromMap, ToMap: Pointer; FirstRow: Integer; Flicker: Byte; Pic: Pointer);
begin
end;

procedure DoIt;
var
  Spare: array[0..2] of Byte;
  MapFrom: array[0..15] of Byte;
  MapTo: array[0..15] of Byte;
  I: Byte;
  Spare2: Byte;
begin
  with SelectedCharacter^ do
  begin
    if Recolor then
    begin
      for I := 0 to 15 do
      begin
        MapFrom[I] := I;
        MapTo[I] := I;
      end;
      for I := 1 to 6 do
      begin
        MapTo[ds3CF5[I]] := Figure[I] and $0F;
        MapTo[ds3CF5[I] + 8] := Figure[I] shr 4;
      end;
      res07_fn_1E5C(@MapFrom, @MapTo, 0, 0, ds5E5A[CombatIcon]);
    end;
  end;
end;

begin
  DoIt;
end.

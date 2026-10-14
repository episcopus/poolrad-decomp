{ Probe for ovl16:382D (EditCharacterIcon). The original saves and restores the character's six colour
  pairs (the bytes at +$C1..+$C6, Figure[1..6]) with a call to 0AF8:0A3F and a constant 6; the
  first draft used Move(Figure[1], Saved, 6), which calls 0AF8:1685 instead, and a variable
  typecast of the single byte `TColours(Figure[1])` is refused (Error 61). A structure assignment
  through a record view of the whole Figure array (`Saved := TFigureView(Figure).Colours`, and the
  reverse) produces the original's call and pushes the source address first, then the destination.
  The with statement keeps the character in a temp, as in the original. }
{$A-,O+,F+,S-,R-,G-,I-}
program FigureCopyProbe;
type
  TColours = array[1..6] of Byte;
  TFigureView = record
    Size: Byte;
    Colours: TColours;
  end;
  PChar_ = ^TChar_;
  TChar_ = record
    Pad: array[0..$BF] of Byte;
    Figure: array[0..6] of Byte;
  end;
var
  Who: PChar_;

procedure UsesMove;
var
  Saved: TColours;
begin
  with Who^ do
    Move(Figure[1], Saved, 6);
end;

procedure UsesAssignment;
var
  Saved: TColours;
begin
  with Who^ do
  begin
    Saved := TFigureView(Figure).Colours;
    TFigureView(Figure).Colours := Saved;
  end;
end;

begin
  UsesMove;
  UsesAssignment;
end.

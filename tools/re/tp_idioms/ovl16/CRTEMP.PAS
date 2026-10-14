{ Probe for ovl16:056C (CreateCharacter). Three idioms the routine needed, all read from `make tpc`
  DISASM=1 and then confirmed by `make match UNIT=ovl16 FN=CreateCharacter`:
  1. A string function called inside an expression gets a hidden 256-byte result temporary, whatever
     the declared result type (String40 here): the frame below is $112 = $11 (the 'Character name: '
     literal copy, 17 bytes) + $100 (the result) + the locals. ovl16:056C's frame is $134 for the same
     reason (the literal temp at [bp-0x34], the result at [bp-0x134]).
  2. `X * 16` compiles to `mov cl,4; shl ax,cl`; `X shl 4` to `mov cx,4; shl ax,cl` (the original has
     the first form: Figure[I] := ds3CF5[I] + (ds3CF5[I] + 8) * 16).
  3. `with Table[Race, Class] do` over a global array of records keeps the element address in a with
     temporary as `mov [bp-x],di; mov [bp-x+2],ds`, and `Base + Sides * Count` loads Count first (into
     cx) and Base last, the order of the original's age arithmetic. }
{$A-,O+,F+,S-,R-,G-,I-}
program CrTemp;

type
  String40 = string[40];
  TAge = record
    Base: Word;
    Count, Sides: Byte;
  end;
  PCharacter = ^TCharacter;
  TCharacter = record
    Name: string[15];
    Age: Word;
  end;

var
  Who: PCharacter;
  Ages: array[0..7, 0..6] of TAge;
  Figures: array[0..6] of Byte;
  Colours: array[0..15] of Byte;
  Race, ClassIndex: ShortInt;
  I: Byte;

function ReadInputLine(Prompt: String40; Color: Byte; MaxLen: Byte): String40;
begin
end;

procedure Probe;
begin
  Who^.Name := ReadInputLine('Character name: ', 13, 15);
  for I := 1 to 6 do
    Figures[I] := Colours[I] + (Colours[I] + 8) * 16;
  with Ages[Race, ClassIndex] do
    Who^.Age := Base + Sides * Count;
end;

begin
  Probe;
end.

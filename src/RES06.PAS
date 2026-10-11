unit RES06;
{$A-,F+,S-,R-,G-,I-}
interface
type
  String40 = string[40];
procedure res06_fn_05EB(A, Row, B, Width: Byte);
procedure res06_fn_0626(A, Row, Color: Byte; Text: string);
procedure res06_fn_0BF5(Color: Byte; Text: String40);
implementation
uses RES04;

{@stub} procedure res06_fn_05EB(A, Row, B, Width: Byte); begin end;
{@stub} procedure res06_fn_0626(A, Row, Color: Byte; Text: string); begin end;

{ Show a one-line message on row 24 and wait for a key. }
procedure res06_fn_0BF5(Color: Byte; Text: String40);
var
  Key: Char;
begin
  res06_fn_05EB(0, 24, 0, 40);
  res06_fn_0626(0, 24, Color, Text);
  Key := res04_fn_0059;
end;

end.

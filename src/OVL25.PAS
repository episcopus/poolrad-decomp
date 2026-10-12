unit OVL25;
{ ovl25: overlay unit, 4682 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06;
procedure ovl25_e1;
procedure ovl25_fn_0067;
procedure ovl25_fn_00CB;
procedure ovl25_fn_01DA;
function ovl25_e2(Title, Prompt: String40; A, B, C, D, E: Byte; var Flag: Byte): Char;
procedure ovl25_e3;
procedure ovl25_fn_0711;
procedure ovl25_fn_07A4;
procedure ovl25_fn_08D7;
procedure ovl25_fn_0923;
procedure ovl25_fn_0969;
procedure ovl25_fn_0A08;
procedure ovl25_fn_0B03;
procedure ovl25_fn_0C33;
procedure ovl25_fn_0CC5;
function ovl25_e4(Title, Prompt: String40; A, B, C, D, E, F, G: Byte; List: PMenuLine; H: Byte;
  var Flag: Byte; var Choice: Integer; var First: PMenuLine): Char;
function ovl25_e5(Prompt: String40; A, B, C: Byte): Char;
procedure ovl25_e6(Count: Word; var List: PMenuLine);
procedure ovl25_e7(var List: PMenuLine);
implementation

{ ovl25:0000: retf 6: 6 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl25_e1; begin end;
{ ovl25:0067: retf 4: 4 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl25_fn_0067; begin end;
{ ovl25:00CB: retf 6: 6 bytes of parameters; 46 bytes of locals }
{@stub} procedure ovl25_fn_00CB; begin end;
{ ovl25:01DA: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl25_fn_01DA; begin end;
{ ovl25:03BD: retf 22; two string[40] values, five bytes and a var byte; returns the key. The
  Temple menu (VisitTemple) calls it. }
{@stub} function ovl25_e2(Title, Prompt: String40; A, B, C, D, E: Byte; var Flag: Byte): Char;
  begin end;
{ ovl25:06FB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl25_e3; begin end;
{ ovl25:0711: retf 8: 8 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl25_fn_0711; begin end;
{ ovl25:07A4: retf 4: 4 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl25_fn_07A4; begin end;
{ ovl25:08D7: retf 6: 6 bytes of parameters; 44 bytes of locals }
{@stub} procedure ovl25_fn_08D7; begin end;
{ ovl25:0923: retf 6: 6 bytes of parameters; 44 bytes of locals }
{@stub} procedure ovl25_fn_0923; begin end;
{ ovl25:0969: retf 4: 4 bytes of parameters; 262 bytes of locals }
{@stub} procedure ovl25_fn_0969; begin end;
{ ovl25:0A08: retf 4: 4 bytes of parameters; 262 bytes of locals }
{@stub} procedure ovl25_fn_0A08; begin end;
{ ovl25:0B03: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl25_fn_0B03; begin end;
{ ovl25:0C33: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl25_fn_0C33; begin end;
{ ovl25:0CC5: retf 4: 4 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl25_fn_0CC5; begin end;
{ ovl25:0D9A: retf 40; a menu over the list List (built by ovl25_e6); returns the key and the
  chosen line in Choice. }
{@stub} function ovl25_e4(Title, Prompt: String40; A, B, C, D, E, F, G: Byte; List: PMenuLine;
  H: Byte; var Flag: Byte; var Choice: Integer; var First: PMenuLine): Char; begin end;
{ ovl25:10D1: retf 10; copies a string[40] and returns the key read (ovl04 compares it with 'Y'). }
{@stub} function ovl25_e5(Prompt: String40; A, B, C: Byte): Char; begin end;
{ ovl25:1140: retf 6; builds a list of Count menu lines into List (ovl04 asks for 10). }
{@stub} procedure ovl25_e6(Count: Word; var List: PMenuLine); begin end;
{ ovl25:11F3: retf 4; ovl04 calls it on the list ovl25_e6 built when it is done with it. }
{@stub} procedure ovl25_e7(var List: PMenuLine); begin end;

begin
end.

program CHARTIT;
{ Probe for ovl03:25CB (ChooseAttitudeCommand). Overlay options ($O+): a literal argument is copied to a
  temporary sized by its length, and a Char passed where a String40 value parameter is expected becomes a
  256-byte temporary filled by 0AF8:0C3B, whose address the callee receives. Assigning the same Char to a
  string local (Title := Blank) adds a second 256-byte temporary and a StrLCopy. The matched form is
  AskMenu(Blank, '~HAUGHTY ...', ...): frame sub sp 0x12e. Run:
  make tpc SRC=tools/re/tp_idioms/ovl03/CHARTIT.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
type
  String40 = string[40];
var
  Dummy: Byte;

function AskMenuX(Title: String40; Text: string; TitleColor, WordColor, HotColor, AcceptEnter,
  Animate: Byte): Byte;
begin
  AskMenuX := 0;
end;

procedure CharArgument;
var
  Choice: Byte;
  Blank: Char;
begin
  Blank := ' ';
  Choice := AskMenuX(Blank, '~HAUGHTY ~SLY ~NICE ~MEEK ~ABUSIVE', 13, 10, 15, 0, 0);
  Dummy := Choice;
end;

procedure CharAssigned;
var
  Choice: Byte;
  Blank: Char;
  Title: string;
begin
  Blank := ' ';
  Title := Blank;
  Choice := AskMenuX(Title, '~HAUGHTY ~SLY ~NICE ~MEEK ~ABUSIVE', 13, 10, 15, 0, 0);
  Dummy := Choice;
end;

begin
  CharArgument;
  CharAssigned;
end.

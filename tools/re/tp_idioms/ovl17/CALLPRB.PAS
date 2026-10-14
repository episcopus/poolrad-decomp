{ Probe for ovl17_e8/e9/e11 (playbook 30).
  Question: under $O+, how does passing a string CONSTANT argument to a routine compile?
  The observed call sites (ovl17:16C2, ovl17:1D5F) build the constant into a stack local with
  System_StrCopy (0AF8:0B0B) and then push only the remaining args. This probe prints the emitted
  code for ReadPromptChoice(Title, 'const', 15, 15, 15, 1, 0, ExtKey) with Title a local string. }
{$A-,O+,F+,S-,R-,G-,I-}
program CallProbe;

type
  String40 = string[40];

function ReadPromptChoice(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char;
begin
  ReadPromptChoice := #0;
end;

procedure Probe;
var
  Key: Char;
  Title: String40;
  ExtKey: Byte;
begin
  Title := '';
  Key := ReadPromptChoice(Title, 'press <enter>/<return> to continue', 15, 15, 15, 1, 0, ExtKey);
end;

begin
  Probe;
end.

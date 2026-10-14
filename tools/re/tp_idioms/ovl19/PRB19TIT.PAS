program PRB19TIT;
{ ovl19:0AB3 and ovl19:0EF8 call ReadPromptChoice (ovl25:03BD) with a string literal as the
  first (Title) argument. The probe asks where the literal goes: a stack temporary copied by
  System_StrCopy, and whether the temporary's pointer is pushed as the argument. }
{$A-,O+,F+,S-,R-,G-,I-}
type
  String40 = string[40];
var
  Menu: String40;
  Flag: Byte;
  Ch: Char;

function ReadPromptChoiceProbe(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char;
begin
  ReadPromptChoiceProbe := Chr(TitleColor + Animate);
end;

procedure ProbeLiteralTitle(var Done: Byte);
begin
  Ch := ReadPromptChoiceProbe('View:', Menu, 13, 10, 15, 0, 0, Flag);
  Done := Ord(Ch);
end;

begin
  ProbeLiteralTitle(Flag);
end.

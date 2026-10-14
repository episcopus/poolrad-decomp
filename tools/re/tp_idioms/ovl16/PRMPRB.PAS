{ Probe for ovl16:209F (playbook 30, batch 12). It shows how TP6 passes two string literals to
  ReadPromptChoice under $O+ (the overlay copies each literal to a stack temporary). Asked because
  ovl16:209F builds 'Modify character: ' and 'Keep Exit' into frame temps [bp-0x2b]/[bp-0x35] and
  then calls ovl25:03BD with only the byte parameters on the stack. }
{$A-,O+,F+,S-,R-,G-,I-}
program PrmProbe;

type
  String40 = string[40];

var
  ExtKey: Byte;
  Key: Char;

function ReadPromptChoice(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char;
begin
end;

begin
  Key := ReadPromptChoice('Modify character: ', 'Keep Exit', 13, 10, 15, 1, 0, ExtKey);
end.

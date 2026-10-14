{ Probe: calling a routine whose first parameter is a value String40 with a literal, in an
  overlay unit ($O+): does the compiler copy the literal to a stack temporary and what is
  pushed (ovl22:0A91 calls res12_fn_2C48 like this). }
{$A-,O+,F+,S-,R-,G-,I-}
program StrArg;

type
  String40 = string[40];
  PCharacter = ^Byte;

procedure Callee(Msg: String40; Flag: Byte; var Who: PCharacter); far;
begin
  if Flag <> 0 then Who := nil;
end;

procedure Caller; far;
var
  Who: PCharacter;
begin
  Callee('Cast Spell on whom', 1, Who);
end;

begin
  Caller;
end.

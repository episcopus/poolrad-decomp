{ Probe helper for ovl16:2033 (nested routine). Its routines live in another segment, so the
  calls compile to lcall (9a) like ShowAbilityScore (ovl19) and DrawHitPoints (res12). }
{$A-,O+,F+,S-,R-,G-,I-}
unit NESTU;

interface

type
  PCharacter = ^TCharacter;
  TCharacter = record
    Name: string[15];
    Pad: array[$10..$11C] of Byte;
  end;

var
  SelectedCharacter: PCharacter;

procedure ShowAbilityScore(Index: ShortInt; Highlight: Boolean);
procedure DrawHitPoints(Who: PCharacter; Col, Row, Flag: Byte);

implementation

procedure ShowAbilityScore(Index: ShortInt; Highlight: Boolean);
begin
end;

procedure DrawHitPoints(Who: PCharacter; Col, Row, Flag: Byte);
begin
end;

end.

program POOL;
{ The main program (segment 0000): the initialisation of every unit, in the original order (the
  compiler emits one call per unit with an initialisation part, in the order of this uses clause),
  then the main block. Evidence: the init chain of start-unpack.exe (build/re/overlays.json). }
{$A-,F+,S-,R-,G-,I-}
uses
  Crt,
  RES02,
  RES03,
  RES04,
  RES05,
  RES06,
  RES07,
  RES08,
  OVL34,
  RES09,
  OVL33,
  RES10,
  OVL32,
  OVL31,
  OVL30,
  RES11,
  OVL29,
  OVL28,
  OVL27,
  OVL26,
  OVL25,
  RES12,
  OVL24,
  OVL23,
  OVL22,
  OVL21,
  OVL20,
  OVL19,
  OVL18,
  OVL17,
  OVL16,
  OVL15,
  OVL14,
  OVL13,
  OVL12,
  OVL11,
  OVL10,
  OVL09,
  OVL08,
  OVL07,
  OVL06,
  OVL05,
  OVL04,
  OVL03,
  OVL02,
  OVL01,
  OVL00;

begin
  StartGame;
  if ParamStr(1) <> 'STING' then
  begin
    ShowTitleScreen;
    CheckCodeWheel;
  end;
  ovl16_e1;
  ovl29_e1(11, 0, 7, 6);
  ovl03_e1;
  QuitGame;
end.

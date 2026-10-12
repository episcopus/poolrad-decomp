unit OVL18;
{ PoolNarrative: the ending narrative and door animation (whitepaper 5.x). ShowEndingNarrative
  shows the dragon's death and the Tyranthraxus and Bane speech as text lines and FINAL pictures,
  running the ovl18_fn_0006 animation between the speech blocks, and ovl18_e2 animates the doors of
  the area view. Both draw through the res07 primitives. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ovl18_fn_0006(A, B: Word; C, D: Byte);
procedure ShowEndingNarrative;
procedure ovl18_e2;
implementation
uses OVL27, OVL28, RES06, RES07, RES12;

{ ovl18:0006: retf 8: 8 bytes of parameters; 82 bytes of locals }
{@stub} procedure ovl18_fn_0006(A, B: Word; C, D: Byte); begin end;
{ ovl18:02A4. The ending narrative (PoolNarrative): it shows the dragon's death and the
  Tyranthraxus and Bane speech as lines of text (res06_fn_0626 on column 1, rows $11 onwards, colour
  10), loads the FINAL<number> pictures (whose number is Str(TileSet) in DS:4713) through
  res07_fn_0111 and draws them with res07_fn_0D71, running the fn_0006 animation between the speech
  blocks, and restores the view mode DS:49F3 at the end. Callers: ovl03:2E10. Gets its picture
  number from DS:4713 and its lines from the code's literal pool. }
procedure ShowEndingNarrative;
begin
  Str(TileSet, ds4713);
  ds4712 := ds49F3;
  ds49F3 := 7;
  ds470E := nil;
  res06_fn_0DD3(1, $11, $26, $16);
  res06_fn_0626(1, $11, $A, 'Mortally wounded, the dragon roars!');
  res06_fn_0626(1, $12, $A, 'The spirit of Tyranthraxus flares up');
  res06_fn_0626(1, $13, $A, 'from the dragon''s body.');
  res12_fn_27D9;
  res07_fn_0111('FINAL' + ds4713, 1, 0, 0, ds470E);
  res07_fn_0D71(0, 0, 0, 0, ds470E, DrawBuf);
  ovl18_fn_0006(3, 5, 2, (10 - ds49E2) * 5 div 2);
  res07_fn_0111('FINAL' + ds4713, 3, 0, 0, ds470E);
  res07_fn_0D71(0, 0, 0, 0, ds470E, DrawBuf);
  if ds49D6^[830] > 1 then
  begin
    res07_fn_0111('FINAL' + ds4713, 4, 0, 0, ds470E);
    res07_fn_0D71(0, $B, 0, 0, ds470E, DrawBuf);
  end;
  if ds49D6^[830] > 2 then
  begin
    res07_fn_0111('FINAL' + ds4713, 5, 0, 0, ds470E);
    res07_fn_0D71($D, 9, 0, 0, ds470E, DrawBuf);
  end;
  if ds49D6^[830] > 3 then
  begin
    res07_fn_0111('FINAL' + ds4713, 6, 0, 0, ds470E);
    res07_fn_0D71(0, 9, 0, 0, ds470E, DrawBuf);
  end;
  res06_fn_0DD3(1, $11, $26, $16);
  res06_fn_0626(1, $11, $A, '"Fools, you have but slain the body');
  res06_fn_0626(1, $12, $A, 'I possessed.  I cannot be defeated!"');
  res06_fn_0626(1, $13, $A, 'With the power of the pool of radiance');
  res06_fn_0626(1, $14, $A, 'which I moved here, to my lair,');
  res06_fn_0626(1, $15, $A, 'I will still rule, by possessing one');
  res06_fn_0626(1, $16, $A, 'of you!"');
  ovl18_fn_0006(3, 1, 7, (10 - ds49E2) * 5 div 2);
  res06_fn_0DD3(1, $11, $26, $16);
  res06_fn_0626(1, $11, $A, '"No Lord Bane!  I can still rule here!');
  res06_fn_0626(1, $12, $A, 'I have not failed.  Do not call me back');
  res06_fn_0626(1, $13, $A, 'through the pool!"');
  res06_fn_0626(1, $14, $A, 'Noooo...');
  ovl18_fn_0006(3, 1, 8, 1);
  res06_fn_0DBE;
  res06_fn_0DBE;
  res06_fn_0DBE;
  ds49F3 := ds4712;
  res12_fn_27D9;
end;
{ ovl18:06B3: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl18_e2; begin end;

begin
end.

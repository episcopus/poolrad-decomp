unit OVL22;
{ CastSpell: the spell study and casting overlay. It builds the spell lists the camp's
  ChooseSpellFromList shows (ovl22_e2 and its helpers, whitepaper 5.22), runs the picker
  (ovl22_e1), gives a spell's area pattern size (SpellAreaSize) and casts, scribes, memorizes
  and learns spells for combat (ovl09) and the camp (ovl15). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06, RES12;
function ovl22_e1(Mode: Byte; var Choice: Word): Byte;
procedure AddSpellMenuLine(Spell: Byte);
procedure ovl22_fn_044E;
procedure ovl22_fn_051C;
function ovl22_e2(Kind: Byte): Byte;
function SpellAreaSize(Spell: Byte): Byte;
procedure ovl22_fn_07D6;
procedure ovl22_fn_08C3;
procedure ovl22_e4;
procedure ovl22_fn_0AE5;
procedure ovl22_fn_0B25;
procedure ovl22_fn_0B2A;
procedure ovl22_fn_0B2F;
procedure ovl22_fn_0B34;
procedure ovl22_fn_0B3E;
procedure ovl22_fn_0B43;
procedure ovl22_fn_0B48;
procedure ovl22_fn_0B4D;
procedure ovl22_fn_0B52;
procedure ovl22_fn_0B5C;
procedure ovl22_fn_0B6B;
procedure ovl22_fn_0B7A;
procedure ovl22_fn_0B7F;
procedure ovl22_fn_0B84;
procedure ovl22_fn_0B89;
procedure ovl22_fn_0B8E;
procedure ovl22_e5(A, B, C: Byte; var Done: Byte);
procedure ovl22_fn_0F4F;
procedure ovl22_e11;
procedure ovl22_e12;
procedure ovl22_e13;
procedure ovl22_e14;
procedure ovl22_e15;
procedure ovl22_e16;
procedure ovl22_e17;
procedure ovl22_e18;
procedure ovl22_e19;
procedure ovl22_e20;
procedure ovl22_e21;
procedure ovl22_e22;
procedure ovl22_e23;
procedure ovl22_e24;
procedure ovl22_e25;
procedure ovl22_e26;
procedure ovl22_e27;
procedure ovl22_fn_1758;
procedure ovl22_e28;
procedure ovl22_e29;
procedure ovl22_e30;
procedure ovl22_e31;
procedure ovl22_e32;
procedure ovl22_e33;
procedure ovl22_e34;
procedure ovl22_e35;
procedure ovl22_e36;
procedure ovl22_e37;
procedure ovl22_e38;
procedure ovl22_fn_202B;
procedure ovl22_e39;
procedure ovl22_fn_20A9;
procedure ovl22_e40;
procedure ovl22_fn_2233;
procedure ovl22_e41;
procedure ovl22_fn_228A;
procedure ovl22_fn_228C;
procedure ovl22_e42;
procedure ovl22_e43;
procedure ovl22_fn_2383;
procedure ovl22_e44;
procedure ovl22_fn_23B6;
procedure ovl22_e45;
procedure ovl22_e9;
procedure ovl22_fn_257E;
procedure ovl22_fn_25C9;
procedure ovl22_e46;
procedure ovl22_e47;
procedure ovl22_e48;
procedure ovl22_fn_2764;
procedure ovl22_e49;
procedure ovl22_fn_28BC;
procedure ovl22_fn_295B;
procedure ovl22_fn_2B8B;
procedure ovl22_e50;
procedure ovl22_e51;
procedure ovl22_e52;
procedure ovl22_fn_2D39;
procedure ovl22_e53;
procedure ovl22_e54;
procedure ovl22_e55;
procedure ovl22_fn_2EEA;
procedure ovl22_e56;
procedure ovl22_fn_2F57;
procedure ovl22_e57;
procedure ovl22_e58;
procedure ovl22_fn_2FD3;
procedure ovl22_e59;
procedure ovl22_e60;
procedure ovl22_e61;
procedure ovl22_e62;
procedure ovl22_e63;
procedure ovl22_fn_31D7;
function ovl22_e6(Item: Pointer): Boolean;
procedure ovl22_fn_3262;
procedure ovl22_e7(Who: PCharacter; Item: PItem; Spell: Byte);
procedure ovl22_e8(Who: PCharacter; Message: String40; Spell: Byte);
procedure ovl22_fn_3379;
procedure ovl22_e10;
implementation

{ ovl22:008A: retf 6: 6 bytes of parameters; 98 bytes of locals }
{@stub} function ovl22_e1(Mode: Byte; var Choice: Word): Byte; begin end;
{ ovl22:028D: retf 2: 2 bytes of parameters; 262 bytes of locals }
{ ovl22:028D. Appends one line for spell Spell to the spell menu list SpellMenuList (ovl22_e2 calls this
  once per spell, in list order). The line's text is ' *' when the pending bit $80 of Spell is set,
  else '  ', followed by SpellNames[Spell and $7F]; when the spell's level differs from the level of
  the previous line a heading line (SpellLevelNames[level]: '1st Level' and so on) is inserted first.
  SpellMenuSpells[Count] keeps the spell number (pending bit cleared) of the line added. Called by ovl22_e2
  and ovl22_fn_044E. }
procedure AddSpellMenuLine(Spell: Byte);
const
  MenuLineBytes = $2E;            { a menu line node: Text, Flag29 and Next, the used part of TMenuLine }
var
  Line: PMenuLine;
  Count: ShortInt;                { ShortInt, not Byte: indexing SpellMenuSpells and the level compare
                                    sign-extend with cwde (ovl22:0304, 035E) }
  PrevLevel: ShortInt;
begin
  Line := SpellMenuList;
  if SpellMenuList = nil then
  begin
    GetMem(Line, MenuLineBytes);
    SpellMenuList := Line;
    PrevLevel := 0;
    Count := 0;
  end
  else
  begin
    Count := 1;
    while Line^.Next <> nil do
    begin
      if Line^.Flag29 = 0 then
        Inc(Count);
      Line := Line^.Next;
    end;
    PrevLevel := SpellTable[SpellMenuSpells[Count - 1]].Level;
    GetMem(Line^.Next, MenuLineBytes);
    Line := Line^.Next;
  end;
  Line^.Next := nil;
  if SpellTable[Spell and $7F].Level <> PrevLevel then
  begin
    Line^.Text := SpellLevelNames[SpellTable[Spell and $7F].Level];
    Line^.Flag29 := 1;
    GetMem(Line^.Next, MenuLineBytes);
    Line := Line^.Next;
    Line^.Next := nil;
  end;
  if Spell > $7F then
    Line^.Text := ' *'
  else
    Line^.Text := '  ';
  Line^.Text := Line^.Text + SpellNames[Spell and $7F];
  Line^.Flag29 := 0;
  SpellMenuSpells[Count] := Spell and $7F;
end;
{ ovl22:044E: retf 2: 2 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl22_fn_044E; begin end;
{ ovl22:051C: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_fn_051C; begin end;
{ ovl22:059C: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} function ovl22_e2(Kind: Byte): Byte; begin end;
{ ovl22:0729: retf 2: 2 bytes of parameters; 2 bytes of locals }
{ ovl22:0729. The size of the area pattern of spell Spell: res12_fn_2433 collects the targets it
  reaches. A 16-byte SpellTable row gives a base (row +2) and a per-level byte (row +3), so the
  result is base + per-level * caster level, the level from res12_fn_26C2 (or * 6 while ds6DBF is
  set). A zero base with row +6 set becomes 1, and $FF (omni) becomes 1 too. Called by SpellAccepted
  (ovl09:02EB) and ovl13:1E16. }
function SpellAreaSize(Spell: Byte): Byte;
var
  Area: Byte;
begin
  if ds6DBF = 0 then
    Area := SpellTable[Spell].Pad2[2] + SpellTable[Spell].Pad2[3] * res12_fn_26C2(Spell)
  else
    Area := SpellTable[Spell].Pad2[3] * 6 + SpellTable[Spell].Pad2[2];
  if Area = 0 then
    if SpellTable[Spell].Pad2[6] <> 0 then
      Area := 1;
  if Area = $FF then
    Area := 1;
  SpellAreaSize := Area;
end;
{ ovl22:07D6: retf 2: 2 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl22_fn_07D6; begin end;
{ ovl22:08C3: retf 14: 14 bytes of parameters; 50 bytes of locals }
{@stub} procedure ovl22_fn_08C3; begin end;
{ ovl22:0A91: frame not read }
{@stub} procedure ovl22_e4; begin end;
{ ovl22:0AE5: frame not read }
{@stub} procedure ovl22_fn_0AE5; begin end;
{ ovl22:0B25: frame not read }
{@stub} procedure ovl22_fn_0B25; begin end;
{ ovl22:0B2A: frame not read }
{@stub} procedure ovl22_fn_0B2A; begin end;
{ ovl22:0B2F: frame not read }
{@stub} procedure ovl22_fn_0B2F; begin end;
{ ovl22:0B34: frame not read }
{@stub} procedure ovl22_fn_0B34; begin end;
{ ovl22:0B3E: frame not read }
{@stub} procedure ovl22_fn_0B3E; begin end;
{ ovl22:0B43: frame not read }
{@stub} procedure ovl22_fn_0B43; begin end;
{ ovl22:0B48: frame not read }
{@stub} procedure ovl22_fn_0B48; begin end;
{ ovl22:0B4D: frame not read }
{@stub} procedure ovl22_fn_0B4D; begin end;
{ ovl22:0B52: frame not read }
{@stub} procedure ovl22_fn_0B52; begin end;
{ ovl22:0B5C: frame not read }
{@stub} procedure ovl22_fn_0B5C; begin end;
{ ovl22:0B6B: frame not read }
{@stub} procedure ovl22_fn_0B6B; begin end;
{ ovl22:0B7A: frame not read }
{@stub} procedure ovl22_fn_0B7A; begin end;
{ ovl22:0B7F: frame not read }
{@stub} procedure ovl22_fn_0B7F; begin end;
{ ovl22:0B84: frame not read }
{@stub} procedure ovl22_fn_0B84; begin end;
{ ovl22:0B89: frame not read }
{@stub} procedure ovl22_fn_0B89; begin end;
{ ovl22:0B8E: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_0B8E; begin end;
{ ovl22:0C20: retf 10: 10 bytes of parameters; 38 bytes of locals }
{@stub} procedure ovl22_e5(A, B, C: Byte; var Done: Byte); begin end;
{ ovl22:0F4F: retf 6: 6 bytes of parameters; 44 bytes of locals }
{@stub} procedure ovl22_fn_0F4F; begin end;
{ ovl22:100F: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e11; begin end;
{ ovl22:1040: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e12; begin end;
{ ovl22:106B: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_e13; begin end;
{ ovl22:10A7: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e14; begin end;
{ ovl22:10E9: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e15; begin end;
{ ovl22:1123: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e16; begin end;
{ ovl22:1162: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e17; begin end;
{ ovl22:1190: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e18; begin end;
{ ovl22:11DD: retf 0: 0 bytes of parameters; 22 bytes of locals }
{@stub} procedure ovl22_e19; begin end;
{ ovl22:12A5: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e20; begin end;
{ ovl22:136E: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e21; begin end;
{ ovl22:13D8: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e22; begin end;
{ ovl22:1439: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e23; begin end;
{ ovl22:1499: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e24; begin end;
{ ovl22:14C7: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e25; begin end;
{ ovl22:151B: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e26; begin end;
{ ovl22:1658: frame not read }
{@stub} procedure ovl22_e27; begin end;
{ ovl22:1758: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_1758; begin end;
{ ovl22:17E9: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e28; begin end;
{ ovl22:1822: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e29; begin end;
{ ovl22:185B: retf 0: 0 bytes of parameters; 20 bytes of locals }
{@stub} procedure ovl22_e30; begin end;
{ ovl22:190F: retf 0: 0 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl22_e31; begin end;
{ ovl22:19C3: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e32; begin end;
{ ovl22:1A16: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e33; begin end;
{ ovl22:1A4F: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e34; begin end;
{ ovl22:1A8A: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e35; begin end;
{ ovl22:1ACC: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e36; begin end;
{ ovl22:1B11: retf 0: 0 bytes of parameters; 42 bytes of locals }
{@stub} procedure ovl22_e37; begin end;
{ ovl22:1F41: frame not read }
{@stub} procedure ovl22_e38; begin end;
{ ovl22:202B: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_202B; begin end;
{ ovl22:206F: frame not read }
{@stub} procedure ovl22_e39; begin end;
{ ovl22:20A9: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_20A9; begin end;
{ ovl22:2217: frame not read }
{@stub} procedure ovl22_e40; begin end;
{ ovl22:2233: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2233; begin end;
{ ovl22:225D: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e41; begin end;
{ ovl22:228A: frame not read }
{@stub} procedure ovl22_fn_228A; begin end;
{ ovl22:228C: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_228C; begin end;
{ ovl22:232F: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e42; begin end;
{ ovl22:234C: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e43; begin end;
{ ovl22:2383: frame not read }
{@stub} procedure ovl22_fn_2383; begin end;
{ ovl22:2385: frame not read }
{@stub} procedure ovl22_e44; begin end;
{ ovl22:23B6: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_23B6; begin end;
{ ovl22:24D6: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e45; begin end;
{ ovl22:2540: frame not read }
{@stub} procedure ovl22_e9; begin end;
{ ovl22:257E: frame not read }
{@stub} procedure ovl22_fn_257E; begin end;
{ ovl22:25C9: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_25C9; begin end;
{ ovl22:2604: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e46; begin end;
{ ovl22:263D: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e47; begin end;
{ ovl22:266B: retf 0: 0 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl22_e48; begin end;
{ ovl22:2764: retf 8: 8 bytes of parameters; 44 bytes of locals }
{@stub} procedure ovl22_fn_2764; begin end;
{ ovl22:2892: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e49; begin end;
{ ovl22:28BC: retf 12: 12 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl22_fn_28BC; begin end;
{ ovl22:295B: frame not read }
{@stub} procedure ovl22_fn_295B; begin end;
{ ovl22:2B8B: frame not read }
{@stub} procedure ovl22_fn_2B8B; begin end;
{ ovl22:2BB7: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e50; begin end;
{ ovl22:2C09: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e51; begin end;
{ ovl22:2C43: frame not read }
{@stub} procedure ovl22_e52; begin end;
{ ovl22:2D39: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2D39; begin end;
{ ovl22:2E02: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e53; begin end;
{ ovl22:2E4D: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e54; begin end;
{ ovl22:2EE5: frame not read }
{@stub} procedure ovl22_e55; begin end;
{ ovl22:2EEA: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2EEA; begin end;
{ ovl22:2F4D: frame not read }
{@stub} procedure ovl22_e56; begin end;
{ ovl22:2F57: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2F57; begin end;
{ ovl22:2F99: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e57; begin end;
{ ovl22:2FD0: frame not read }
{@stub} procedure ovl22_e58; begin end;
{ ovl22:2FD3: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_fn_2FD3; begin end;
{ ovl22:302A: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e59; begin end;
{ ovl22:3058: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e60; begin end;
{ ovl22:3092: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_e61; begin end;
{ ovl22:30A2: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e62; begin end;
{ ovl22:30D9: frame not read }
{@stub} procedure ovl22_e63; begin end;
{ ovl22:31D7: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_31D7; begin end;
{ ovl22:323D: frame not read }
{@stub} function ovl22_e6(Item: Pointer): Boolean; begin end;
{ ovl22:3262: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_3262; begin end;
{ ovl22:328A: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl22_e7(Who: PCharacter; Item: PItem; Spell: Byte); begin end;
{ ovl22:331A: frame not read }
{@stub} procedure ovl22_e8(Who: PCharacter; Message: String40; Spell: Byte); begin end;
{ ovl22:3379: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_3379; begin end;
{ ovl22:3413: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_e10; begin end;

begin
end.

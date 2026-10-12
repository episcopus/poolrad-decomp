unit RES08;
{ Startup: the unit initialisation opens the overlay file, probes and parses POOL.CFG (video
  and sound choice, game and save directories), saves the video mode, sizes the overlay
  buffer and the heap, and starts the sound unit (whitepaper 2.3). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
implementation
uses Dos, Overlay, POOLVARS, RES03, RES04, RES05, RES06, RES07;

{ 042B:00A4. Starts the game: initialises res05, then the overlay manager on GAME.OVR; probes
  pool.cfg (retrying with 'Please insert startup disk.' until it opens) and parses POOL.CFG:
  line 1 the video choice (E: VideoAdapter 1 and EGA mode $0D, T: 2 with a smaller heap,
  else 0), line 2 the sound choice (T: 0, P: 1, else 2), lines 3-4 the game and save
  directories, line 5 the F flag. Gives the overlay buffer $18800 bytes (halting with how
  many more bytes are needed when short), halts on an overlay error, and starts the sound
  unit. Side effects: files, screen, heap, sound, halt on failure. }
begin
  WaitForOverlayDisk;
  OvrInit('GAME.OVR');
  repeat
    Assign(CfgProbe, 'pool.cfg');
    Reset(CfgProbe, $80);
    CfgProbeResult := IOResult;
    if CfgProbeResult <> 0 then
    begin
      WriteLn(Output, 'Please insert startup disk.');
      CfgChar := ReadGameKey;
    end;
  until CfgProbeResult = 0;
  Close(CfgProbe);
  ds84F0 := 0;
  Assign(CfgText, 'POOL.CFG');
  Reset(CfgText);
  if IOResult <> 0 then
  begin
    WriteLn(Output, 'Unable to find POOL.CFG');
    Halt;
  end;
  ReadLn(CfgText, CfgChar);
  Regs.AH := $0F;
  Intr($10, Regs);
  SavedVideoMode := Regs.AL;
  ds4A1D := SavedVideoMode;
  case CfgChar of
    'E':
      begin
        VideoAdapter := 1;
        res07_fn_00CF($0D);
        ds4A1B := 0;
        ds4A1A := 0;
        res06_fn_0071(ds4A1B);
        res06_fn_00A0(ds4A1A);
      end;
    'T':
      begin
        VideoAdapter := 2;
        NewHeapEnd := Ptr(HeapWords[1] - $400, HeapWords[0]);
        HeapEnd := NewHeapEnd;
        res07_fn_00CF(9);
      end;
  else
    begin
      VideoAdapter := 0;
      res07_fn_00CF(4);
    end;
  end;
  if $18800 - OvrGetBuf <= MemAvail then
    OvrSetBuf($18800)
  else
  begin
    res07_fn_00FF;
    WriteLn(Output, 'Not enough memory to run game.  You need ', $18800 - OvrGetBuf,
      ' more bytes.');
    Halt;
  end;
  if ds43DC <> 0 then
  begin
    res07_fn_00FF;
    WriteLn(Output, 'Overlay error, program abort!');
    Halt;
  end;
  ReadLn(CfgText, CfgChar);
  case CfgChar of
    'T': SoundMode := 0;
    'P': SoundMode := 1;
  else
    SoundMode := 2;
  end;
  NewHeapEnd := Ptr(HeapWords[1] - $400, HeapWords[0]);
  HeapEnd := NewHeapEnd;
  res03_fn_017B;
  ReadLn(CfgText, GameDir);
  GameDir := GameDir;
  ReadLn(CfgText, SaveDir);
  SaveDir := SaveDir;
  ReadLn(CfgText, CfgChar);
  if CfgChar = 'F' then
    ds49D1 := 1
  else
    ds49D1 := 0;
  Close(CfgText);
end.

unit RES03;
{ The sound unit: PlaySound, SilenceSound and SetSoundDriverIdle, the Pascal front end the game
  calls, over a hand-written assembly driver linked after the initialisation part (08AE:01D7 to
  the end of the segment: tune tables, the voice records, the INT 08h handler 08AE:13EA, the voice
  steppers for the PC speaker (08AE:1477) and the Tandy SN76489 (08AE:14EC), StartSoundTimer,
  StopSoundTimer and the tune setters). SoundMode (POOL.CFG line 2) picks the device: 0 Tandy,
  1 PC speaker, 2 silent. Whitepaper 5.14. }
{$A-,F+,S-,R-,G-,I-}
interface
function TimeInHundredths: Longint;
procedure WaitHundredths(Hundredths: Word);
procedure PlaySound(Sound: Word);
procedure SilenceSound;
procedure SetSoundDriverIdle(Idle: Word);
procedure TuneData09E3;
procedure TuneData0A27;
procedure TuneData0AD3;
procedure TuneData0C8F;
procedure TuneData0DB1;
procedure TuneData0DCC;
procedure TuneData0DEB;
procedure TuneData0E06;
procedure TuneData0F5B;
procedure TuneData1091;
procedure TuneData1221;
procedure StartSoundTimer;
procedure StopSoundTimer;
procedure SpeakerStep;
procedure TandyStep;
procedure StepVoice;
procedure RunStream;
procedure SetSpeakerTune(Tune: Word);
procedure SetTandyTune(Tune: Word);
procedure SetSoundOutput(Enabled: Word);
implementation
uses Dos, POOLVARS;

const
  SoundTandy = 0;             { SoundMode values (POOL.CFG line 2, whitepaper 3) }
  SoundSpeaker = 1;
  SoundSilent = 2;            { also what Ctrl-S sets (RES04's SoundPaused) }
  HundredthsPerHour = 360000;
  HundredthsPerMinute = 6000;
  HundredthsPerSecond = 100;
  SoundStop = 0;              { PlaySound: silence both devices and turn the output off }
  SoundOutputOn = 1;          { PlaySound: turn the output on }
  SoundQuiet = $FF;           { PlaySound: silence both devices, output flag kept }
  NoTune = 0;
  BriefSoundTime = 10;        { hundredths of a second a sound plays while the driver is idle }

{ 08AE:0000. The time of day in hundredths of a second since midnight (Dos.GetTime).
  QUIRK 08AE:0033: Minute * 6000 and Second * 100 are Word products, so the minutes term
  wraps above 10 minutes; only the hours term is a Longint product. }
function TimeInHundredths: Longint;
var
  Hour, Minute, Second, Sec100: Word;
begin
  GetTime(Hour, Minute, Second, Sec100);
  TimeInHundredths := Hour * HundredthsPerHour + Minute * HundredthsPerMinute +
    Second * HundredthsPerSecond + Sec100;
end;

{ 08AE:006C. Busy-waits Hundredths hundredths of a second on TimeInHundredths. When the clock
  falls back by more than Hundredths (midnight, or the minutes wrap of TimeInHundredths) the wait
  ends at once. }
procedure WaitHundredths(Hundredths: Word);
var
  Target, Now: Longint;
begin
  Target := TimeInHundredths + Hundredths;
  repeat
    Now := TimeInHundredths;
    if Target - Now > Hundredths then
      Now := Target + 1;
  until Now >= Target;
end;

{ 08AE:00DC. Plays a sound or tune. Sound SoundStop sets both devices to NoTune and the output
  off, SoundOutputOn turns the output on, SoundQuiet sets both devices to NoTune; any other n
  starts tune n - 1 on the device of SoundMode (SetSpeakerTune or SetTandyTune). Nothing when
  SoundMode is SoundSilent. While SoundDriverIdle is nonzero the timer driver runs only around
  this call: started first, then after BriefSoundTime both devices are silenced and it stops. }
procedure PlaySound(Sound: Word);
begin
  if SoundMode = SoundSilent then Exit;
  if SoundDriverIdle > 0 then
    StartSoundTimer;
  case Sound of
    SoundStop:
      begin
        SetTandyTune(NoTune);
        SetSpeakerTune(NoTune);
        SetSoundOutput(0);
      end;
    SoundOutputOn: SetSoundOutput(1);
    SoundQuiet:
      begin
        SetTandyTune(NoTune);
        SetSpeakerTune(NoTune);
      end;
  else
    case SoundMode of
      SoundSpeaker: SetSpeakerTune(Sound - 1);
      SoundTandy: SetTandyTune(Sound - 1);
    end;
  end;
  if SoundDriverIdle > 0 then
  begin
    WaitHundredths(BriefSoundTime);
    SetTandyTune(NoTune);
    SetSpeakerTune(NoTune);
    StopSoundTimer;
  end;
end;

{ 08AE:017B. Saves SoundMode in SoundModeBeforePause, then, unless SoundMode is SoundSilent,
  runs the timer driver once to set both devices to NoTune and stops it again. Called by
  res08's initialisation and by ReadGameKey when Ctrl-S resumes the sound. }
procedure SilenceSound;
begin
  SoundModeBeforePause := SoundMode;
  if SoundMode = SoundSilent then Exit;
  StartSoundTimer;
  SetSpeakerTune(NoTune);
  SetTandyTune(NoTune);
  StopSoundTimer;
end;

{ 08AE:01A5. Idle 0 starts the timer driver for good (tunes play in the background); a nonzero
  Idle stops it unless it was already idle, and PlaySound then runs it only around each sound.
  Stores Idle in SoundDriverIdle. Nothing when SoundMode is SoundSilent. Callers pass 100
  (StartGame), 0 and 10 (RemoveCombatant). }
procedure SetSoundDriverIdle(Idle: Word);
begin
  if SoundMode = SoundSilent then Exit;
  if Idle > 0 then
  begin
    if SoundDriverIdle = 0 then
      StopSoundTimer;
  end
  else
    StartSoundTimer;
  SoundDriverIdle := Idle;
end;

{ 08AE:09E3: frame not read }
{@stub} procedure TuneData09E3; begin end;
{ 08AE:0A27: frame not read }
{@stub} procedure TuneData0A27; begin end;
{ 08AE:0AD3: frame not read }
{@stub} procedure TuneData0AD3; begin end;
{ 08AE:0C8F: frame not read }
{@stub} procedure TuneData0C8F; begin end;
{ 08AE:0DB1: frame not read }
{@stub} procedure TuneData0DB1; begin end;
{ 08AE:0DCC: frame not read }
{@stub} procedure TuneData0DCC; begin end;
{ 08AE:0DEB: frame not read }
{@stub} procedure TuneData0DEB; begin end;
{ 08AE:0E06: frame not read }
{@stub} procedure TuneData0E06; begin end;
{ 08AE:0F5B: frame not read }
{@stub} procedure TuneData0F5B; begin end;
{ 08AE:1091: frame not read }
{@stub} procedure TuneData1091; begin end;
{ 08AE:1221: frame not read }
{@stub} procedure TuneData1221; begin end;
{ 08AE:137C: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure StartSoundTimer; begin end;
{ 08AE:13B1: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure StopSoundTimer; begin end;
{ 08AE:1477: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure SpeakerStep; begin end;
{ 08AE:14EC: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure TandyStep; begin end;
{ 08AE:157A: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure StepVoice; begin end;
{ 08AE:160B: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure RunStream; begin end;
{ 08AE:1742: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure SetSpeakerTune(Tune: Word); begin end;
{ 08AE:17AE: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure SetTandyTune(Tune: Word); begin end;
{ 08AE:181A: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure SetSoundOutput(Enabled: Word); begin end;

begin
end.

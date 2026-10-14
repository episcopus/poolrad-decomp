{ PRB16 (res12): which System entry New/GetMem and FreeMem reach, to identify
  0AF8:023F (called with only a size, returns the pointer in ax:dx) and 0AF8:0254.
  res12:15F7 does GetMem-sized alloc then Move then FreeMem. }
program PRB16;
var
  Q: Pointer;
begin
  GetMem(Q, 63);
  FreeMem(Q, 63);
end.

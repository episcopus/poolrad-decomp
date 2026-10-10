{ Overlaid unit for the Turbo Pascal toolchain probe (tools/re/tp_toolchain.py). }
{$O+,F+}
unit OVU;

interface

procedure OvProc(var S: string);

implementation

procedure OvProc(var S: string);
begin
  S := S + '!';
end;

end.

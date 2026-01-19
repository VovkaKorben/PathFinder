library PathFinder;

uses System.SysUtils,

  System.Classes, Vcl.Controls, uPathfinder in 'uPathfinder.pas', uWaypointForm in 'uWaypointForm.pas',
  astar in 'astar.pas';
{$R *.res}

{
  function FindPath(OID: Integer; SX, SY, SZ, EX, EY, EZ: Integer): Integer; stdcall;
  var
  Ctx: PPathContext;
  begin
  Ctx := GetContext(OID);
  Result := Ctx^.DoAStar(tpoint3d.Create(SX, SY, SZ), tpoint3d.Create(EX, EY, EZ));
  end;

  function GetPathNode(OID: Integer; Index: Integer; var Act, X, Y, Z: Integer): Boolean; stdcall;
  var
  Ctx: PPathContext;
  begin
  Ctx := GetContext(OID);
  Result := Ctx^.GetNode(Index, Act, X, Y, Z);
  end;     // ������ ���������� �����, ��� � � ������
  function ShowWaypointDialog(OID: Integer; SX, SY, SZ: Integer; var DestX, DestY, DestZ: Integer): Boolean; stdcall;
  var
  Frm: TWaypointForm;
  begin
  Result := False;
  Frm := TWaypointForm.Create(nil);
  try
  Frm.pctx := GetContext(OID);
  Frm.character_pos := tpoint3d.Create(SX, SY, SZ);
  if Frm.ShowModal = mrOk then
  begin
  Frm.selected_point.CopyTo(DestX, DestY, DestZ);
  Result := True;
  end;
  finally
  Frm.Free;
  end;
  end;
}
procedure FreeActions(OID: Integer); stdcall;
begin
  Release(OID);
end;

procedure StrToDLL(OID: Integer; AText: PAnsiChar); stdcall;
var
  Ctx: PPathContext;
begin
  Ctx := GetContext(OID); // ���� �������� ��������� � ������
  if Ctx <> nil then
    Ctx^.GetText(AText);
end;

function StrFromDLL(OID: Integer): PAnsiChar; stdcall;
var
  Ctx: PPathContext;
begin
  Result := nil;
  Ctx := GetContext(OID);
  if (Ctx <> nil) then
    Result := Ctx^.SendStringAddr;
end;

procedure IntToDLL(OID: Integer; V1, V2, v3: Integer); stdcall;
var
  Ctx: PPathContext;
begin
  Ctx := GetContext(OID);
  if (Ctx <> nil) then
    Ctx^.RecvInt(V1, V2, v3);
end;

{ PathFinder.dpr }

function IntFromDLL(OID: Integer; var Act, X, Y, Z: Integer): boolean; stdcall;
var
  Ctx: PPathContext;
begin
  Result := false;
  Ctx := GetContext(OID);
  if (Ctx <> nil) then
    Result := Ctx^.GetAction(Act, X, Y, Z);

end;

exports StrToDLL, StrFromDLL, IntToDLL, IntFromDLL, FreeActions;

end.

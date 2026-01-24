library PathFinder;

{$R *.dres}

uses
    System.SysUtils,
    System.Classes,
    Vcl.Controls,
    uPathfinder in 'uPathfinder.pas',
    uWaypointForm in 'uWaypointForm.pas',
    astar in 'astar.pas',
    uConstants in 'uConstants.pas';

{$R *.res}

function ShowWaypointDialog(OID: Integer; SX, SY, SZ: Integer): Boolean; stdcall;
var
    Frm: TWaypointForm;
begin
    Result := False;
    Frm := TWaypointForm.Create(nil);
    try
        Frm.ctx := GetContext(OID);
        Frm.ctx.StartPoint := tpoint3d.Create(SX, SY, SZ);
        if Frm.ShowModal = mrOk then
            Result := True;
    finally
        Frm.Free;
    end;
end;

procedure FreeActions(OID: Integer); stdcall;
begin
    Release(OID);
end;

procedure StrToDLL(OID: Integer; AText: PAnsiChar); stdcall;
var
    ctx: TPathContext;
begin
    ctx := GetContext(OID);
    if ctx <> nil then
        ctx.GetText(AText);
end;

function StrFromDLL(OID: Integer): PAnsiChar; stdcall;
var
    ctx: TPathContext;
begin
    Result := nil;
    ctx := GetContext(OID);
    if (ctx <> nil) then
        Result := ctx.SendStringAddr;
end;

procedure IntToDLL(OID: Integer; V1, V2, v3: Integer); stdcall;
var
    ctx: TPathContext;
begin
    ctx := GetContext(OID);
    if (ctx <> nil) then
        ctx.RecvInt(V1, V2, v3);
end;

function IntFromDLL(OID: Integer; var Act, X, Y, Z: Integer): Boolean; stdcall;
var
    ctx: TPathContext;
begin
    Result := False;
    ctx := GetContext(OID);
    if (ctx <> nil) then
        Result := ctx.GetAction(Act, X, Y, Z);

end;

exports ShowWaypointDialog, StrToDLL, StrFromDLL, IntToDLL, IntFromDLL, FreeActions;

end.

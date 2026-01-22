unit uPathfinder;

interface

uses
    Windows, System.SysUtils, System.Classes, System.Generics.Collections, System.Math, System.Diagnostics, astar, AnsiStrings, vcl.forms;

const
    MAX_DLG_BUFFER = 16384;

type

    TSegmentAction = (saStop, saMoving, saParsing);
    TBufferState = (bsIdle, bsWaiting, bsReady);

    PPathContext = ^TPathContext;

    TPathContext = record
    private
        OID: int32;

        FRecv1, FRecv2, FRecv3: int32;
        FWaitState: TBufferState;
        FLastResponse, FOutputBuffer: array [0 .. MAX_DLG_BUFFER] of AnsiChar;

        FSegments: array of TSegmentAction; // заполняется при выборе в окне действия
        FCurrentSegment: int32; // текущий индекс сегмента
        FSteps: TSteps; // шаги из текущего сегмента, то самое, что длл отдает адрику один за одним
        FCurrentStep: int32; // индекс шажочка в FSteps

        {
          выбрали точку на форме - заполнили FSegments всем скриптом





        }

        procedure SetOutputText(const AText: string);

    public
        PointCount, ActionCount: int32;
        Distance, TotalCost: Double;

        procedure GenerateScenario(frm: TForm; PointData: uint32);

        procedure GetText(AText: PAnsiChar);
        function SendStringAddr: PAnsiChar;
        procedure RecvInt(X, Y, Z: Integer);
        function GetAction(var act, X, Y, Z: Integer): boolean;
    end;

var

    Contexts: array of PPathContext;

function GetContext(AOID: int32): PPathContext;
procedure Release(AOID: int32);

implementation

procedure Release(AOID: int32);
var
    i, j: int32;
begin
    for i := 0 to High(Contexts) do
    begin
        if Contexts[i]^.OID = AOID then
        begin

            SetLength(Contexts[i]^.FSteps, 0);
            FreeMem(Contexts[i]);
            for j := i to High(Contexts) - 1 do
                Contexts[j] := Contexts[j + 1];

            SetLength(Contexts, Length(Contexts) - 1);
            Exit;
        end;
    end;
end;

function GetContext(AOID: int32): PPathContext;
var
    i: int32;
begin
    for i := 0 to High(Contexts) do
        if Contexts[i]^.OID = AOID then
        begin
            Result := Contexts[i];
            Exit;
        end;
    GetMem(Result, SizeOf(TPathContext));
    FillChar(Result^, SizeOf(TPathContext), 0); // �������� ��

    Result^.OID := AOID;
    SetLength(Contexts, Length(Contexts) + 1);
    Contexts[High(Contexts)] := Result;
end;

{ TPathContext }
procedure TPathContext.SetOutputText(const AText: string);
begin
    AnsiStrings.StrPLCopy(FOutputBuffer, AnsiString(AText), MAX_DLG_BUFFER - 1);
end;

procedure TPathContext.GenerateScenario(frm: TForm; PointData: uint32);
// TPredefinedAction = (paMove, pa7Signs, paClanBank);
var
    scenario_index: int32;
begin
    PointData := uint32(PointData);
    if (PointData and $80000000) = 0 then
    begin // simple moveto

    end else begin
        scenario_index := PointData and $7FFFFFFF;

    end;
end;

function TPathContext.GetAction(var act, X, Y, Z: Integer): boolean;
begin
    Result := True;

    if FWaitState = bsWaiting then
    begin
        act := 80; // ������� Delay
        X := 100;
        Exit;
    end;

    { 2. ���� ������ ������ (stReady), ���������� ���� � ��� ������ }
    if FWaitState = bsReady then
        FWaitState := bsIdle;

    { 3. �������� ������������������ (��� ������ FFinalPath) }
    case FCurrentStep of
        0:
            begin // ���� ������
                act := 5;
                SetOutputText('DLL: Link test started...'); // ����� ������ � FOutputBuffer
            end;

        1:
            begin // ���� ����� ������ (C -> S)
                act := 31; // ������ ������ �������� DlgText
                FWaitState := bsWaiting;
            end;

        2:
            begin // ���� �������� ������ (S -> C)
                act := 5;
                { ���� ��, ��� ������ ������� �� ���� 1, � ����� ������� ��� Print }
                // SetOutputText('DLL ��������: ' + string(FLastResponse));
                // SetOutputText('DLL ��������: ' + UTF8ToString(PAnsiChar(@FLastResponse[0])));
                // SetOutputText('DLL received HTML. Length: ' + IntToStr(Length(string(FLastResponse))));
                SetOutputText('DLL received HTML. Length: ' + inttostr(Length(string(FLastResponse))));

            end;

        3:
            begin // ���� ����� (C -> S)
                act := 40; // ��������, 40 - ��� ���� �������� ������� �� �����
                FWaitState := bsWaiting;
            end;

        4:
            begin // ���� ������ ���������� �����
                act := 5;

                SetOutputText('Numbers from script: ' + inttostr(FRecv1) + ', ' + inttostr(FRecv2));
            end;

        5:
            begin // ����������
                act := 0; // Stop

                FCurrentStep := 0;
                Result := False;
            end;
    else
        act := 0;
        FCurrentStep := 0;
        Result := False;
    end;
    if Result then
        inc(FCurrentStep);
end;

procedure TPathContext.GetText(AText: PAnsiChar);
begin
    if (AText <> nil) then
        AnsiStrings.StrLCopy(FLastResponse, AText, MAX_DLG_BUFFER - 1)
    else
        FLastResponse[0] := #0;

    FWaitState := bsReady;
end;

function TPathContext.SendStringAddr: PAnsiChar;
begin
    Result := @(FOutputBuffer[0]);
end;

procedure TPathContext.RecvInt(X, Y, Z: Integer);
begin

    FRecv1 := X;
    FRecv2 := Y;
    FRecv3 := Z;
    FWaitState := bsReady;
end;

end.

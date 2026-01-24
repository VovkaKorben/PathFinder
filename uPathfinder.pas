unit uPathfinder;

interface

uses
    Windows, System.SysUtils, System.Classes, System.Generics.Collections,
    System.Math, System.Diagnostics, astar, AnsiStrings, vcl.forms,
    uConstants;

const
    MAX_DLG_BUFFER = 16384;

type
    TPredefinedAction = (paMove, pa7Signs, paClanBank);
    TSegmentAction = (saStop, saMoveTo, saMoving, saParsing, sa7S_getdlg, sa7S_ok,
        sa7S_err, sa7S_already);
    TBufferState = (bsIdle, bsWaiting, bsReady);

    TPathContext = class
    private
        OID: int32;

        FRecv1, FRecv2, FRecv3: int32;
        FWaitState: TBufferState;
        // FLastResponse,
        FOutputBuffer: array[0..MAX_DLG_BUFFER] of AnsiChar;

        FGoalID: uint32;
        FSegments: array of TSegmentAction; // заполняется при выборе в окне действия
        FCurrentSegment: int32; // текущий индекс сегмента
        FSteps: TSteps;
        // шаги из текущего сегмента, то самое, что длл отдает адрику один за одним
        FCurrentStep: int32; // индекс шажочка в FSteps

        procedure SetOutputText(const AText: string);
    public
        StartPoint: TPoint3D;
        Params: TDictionary<string, Variant>;

        procedure GenerateScenario(PointData: uint32);
        procedure GenerateSegment(const SegmentType: TSegmentAction);

        procedure GetText(AText: PAnsiChar);
        function SendStringAddr: PAnsiChar;
        procedure RecvInt(X, Y, Z: Integer);
        function GetAction(var act, X, Y, Z: Integer): boolean;
        constructor Create;
        destructor Destroy; override;
    end;

var

    Contexts: array of TPathContext;

function GetContext(AOID: int32): TPathContext;
procedure Release(AOID: int32);

implementation

constructor TPathContext.Create;
begin
    Params := TDictionary<string, Variant>.Create;
end;

destructor TPathContext.Destroy;
begin
    Params.Free;
    inherited Destroy;
end;

procedure Release(AOID: int32);
var
    i, j: int32;
begin
    for i := 0 to High(Contexts) do
    begin
        if Contexts[i].OID = AOID then
        begin

            // Уничтожаем объект. Это вызовет destructor, где живет Params.Free
            Contexts[i].Free;

            for j := i to High(Contexts) - 1 do
                Contexts[j] := Contexts[j + 1];

            SetLength(Contexts, Length(Contexts) - 1);
            Exit;
        end;
    end;
end;

function GetContext(AOID: int32): TPathContext;
var
    i: int32;
begin
    for i := 0 to High(Contexts) do
        if Contexts[i].OID = AOID then
        begin
            Result := Contexts[i];
            Exit;
        end;
    // Создаем новый экземпляр класса
    Result := TPathContext.Create; // Сработает твой конструктор с Params
    Result.OID := AOID;

    // Добавляем в массив
    SetLength(Contexts, Length(Contexts) + 1);
    Contexts[High(Contexts)] := Result;
end;

procedure TPathContext.SetOutputText(const AText: string);
begin
    AnsiStrings.StrPLCopy(FOutputBuffer, AnsiString(AText), MAX_DLG_BUFFER - 1);
end;

function TPathContext.GetAction(var act, X, Y, Z: Integer): boolean;
begin

    if FCurrentStep >= Length(FSteps) then // current segment is over
    begin
        inc(FCurrentSegment); // При первом запуске -1 станет 0

        // если у нас нет больше сегментов - выходим
        if FCurrentSegment >= Length(FSegments) then
            Exit(false);

        // Генерируем шаги для текущего сегмента
        GenerateSegment(FSegments[FCurrentSegment]);
        FCurrentStep := 0;

        // Если после генерации шагов всё еще 0 (например, А* не нашел путь),
        // цикл уйдет на следующую итерацию и попробует следующий сегмент
    end;

    act := FSteps[FCurrentStep].act;
    X := FSteps[FCurrentStep].data0;
    Y := FSteps[FCurrentStep].data1;
    Z := FSteps[FCurrentStep].data2;
    if FSteps[FCurrentStep].str <> '' then
        SetOutputText(FSteps[FCurrentStep].str);
    inc(FCurrentStep);
    Result := True;
end;

procedure TPathContext.GenerateSegment(const SegmentType: TSegmentAction);
var
    //    TargetID: uint32;
    StartID: Integer;
begin

    try
        case SegmentType of
            saMoveTo:
                begin
                    // if not Params.TryGetValue('TargetID', Variant(TargetID)) then                        raise Exception.Create('TargetID not found in Params');
                    SetLength(FSteps, 1);
                    FSteps[0].act := actStrFromDLL;
                    FSteps[0].str := graph_points[FGoalID].Name;
                    StartID := FindNearestPoint(StartPoint);
                    if StartID = -1 then
                        raise Exception.Create('Start point not found');
                    // Генерируем шаги через А*
                    DoAStar(FSteps, graph_points[StartID], graph_points[FGoalID]);
                end;
            // Тут будут saStop, saParsing и прочие...
        end;
    except
        on E: Exception do
        begin
            SetLength(FSteps, 2);
            FSteps[0].act := actStrFromDLL;
            FSteps[0].str := 'Error: ' + E.Message;
            FSteps[1].act := actStop; // Stop
        end;
    end;

end;

procedure TPathContext.GenerateScenario(PointData: uint32);
begin
    FGoalID := PointData;
    if (FGoalID and $80000000) = 0 then
    begin
        // simple moveto
        SetLength(FSegments, 1);
        FSegments[0] := saMoveTo;

    end
    else
    begin
        // scenario_index := PointData and $7FFFFFFF;
    end;

    // КЛЮЧЕВОЙ МОМЕНТ:
    FCurrentSegment := -1; // Указываем, что мы еще не начали
    FCurrentStep := 0;
    SetLength(FSteps, 0);
    // Очищаем шаги, чтобы GetAction сразу зашел в блок генерации
end;

procedure TPathContext.GetText(AText: PAnsiChar);
begin
    if (AText <> nil) then
        AnsiStrings.StrLCopy(FOutputBuffer, AText, MAX_DLG_BUFFER - 1)
    else
        FOutputBuffer[0] := #0;

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


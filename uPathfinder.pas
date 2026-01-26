unit uPathfinder;

interface

uses
    Windows, System.SysUtils, System.Classes, System.Generics.Collections,
    System.Math, System.Diagnostics, astar, AnsiStrings, vcl.forms,
    uConstants, System.SyncObjs;

const
    MAX_DLG_BUFFER = 16384;

type
    TPredefinedAction = (paMove, pa7Signs, paClanBank, paTest);
    TSegmentAction = (saStop, saMoveTo, saMoving, saTest, //
        sa7S_Init, sa7S_MoveToPriest, sa7S_GetDlg, sa7S_Echo, sa7S_Analyze, sa7S_DoReg, sa7S_Already, sa7S_Error);
    TBufferState = (bsIdle, bsWaiting, bsReady);

    TPathContext = class
    private
        OID: int32;

        FRecv1, FRecv2, FRecv3: int32;
        FOutputBuffer: array[0..MAX_DLG_BUFFER] of AnsiChar;

        FGoalID: uint32;
        FSegments: TArray<TSegmentAction>; // заполняется при выборе в окне действия
        FSegmentIndex: int32; // текущий индекс сегмента
        FSteps: TSteps; // шаги из текущего сегмента, то самое, что длл отдает адрику один за одним
        FCurrentStep: int32; // индекс шажочка в FSteps

        procedure SetOutputText(const AText: string);
        procedure JumpTo(const Action: TSegmentAction);

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
    ContextGuard: TCriticalSection;

function GetContext(AOID: int32): TPathContext;
procedure Release(AOID: int32);

implementation
type
    TPriestData = record
        Loc: string;
        NpcId: Int32;
        PriestType: Int32; // 0 - Dawn, 1 - Dusk
        Pos: TPoint3D;
    end;

const
    PRIESTS: array[0..21] of TPriestData = (
        (Loc: 'Gludin'; NpcId: 31078; PriestType: 0; Pos: (X: - 80555; Y: 150387; Z: - 3040)),
        (Loc: 'Gludio'; NpcId: 31079; PriestType: 0; Pos: (X: - 13953; Y: 121454; Z: - 2984)),
        (Loc: 'Dion'; NpcId: 31080; PriestType: 0; Pos: (X: 16354; Y: 142870; Z: - 2696)),
        (Loc: 'Giran'; NpcId: 31081; PriestType: 0; Pos: (X: 83369; Y: 149273; Z: - 3400)),
        (Loc: 'Innadril'; NpcId: 31082; PriestType: 0; Pos: (X: 111386; Y: 220908; Z: - 3544)),
        (Loc: 'Oren'; NpcId: 31083; PriestType: 0; Pos: (X: 83106; Y: 54015; Z: - 1488)),
        (Loc: 'Aden'; NpcId: 31084; PriestType: 0; Pos: (X: 146983; Y: 26645; Z: - 2200)),
        (Loc: 'Gludin'; NpcId: 31085; PriestType: 1; Pos: (X: - 82368; Y: 151618; Z: - 3120)),
        (Loc: 'Gludio'; NpcId: 31086; PriestType: 1; Pos: (X: - 14748; Y: 124045; Z: - 3112)),
        (Loc: 'Dion'; NpcId: 31087; PriestType: 1; Pos: (X: 18482; Y: 144626; Z: - 3056)),
        (Loc: 'Giran'; NpcId: 31088; PriestType: 1; Pos: (X: 81623; Y: 148606; Z: - 3464)),
        (Loc: 'Innadril'; NpcId: 31089; PriestType: 1; Pos: (X: 112486; Y: 220173; Z: - 3592)),
        (Loc: 'Oren'; NpcId: 31090; PriestType: 1; Pos: (X: 82819; Y: 54657; Z: - 1520)),
        (Loc: 'Aden'; NpcId: 31091; PriestType: 1; Pos: (X: 147570; Y: 28927; Z: - 2264)),
        (Loc: 'Hunters Village'; NpcId: 31168; PriestType: 0; Pos: (X: 115136; Y: 74767; Z: - 2608)),
        (Loc: 'Hunters Village'; NpcId: 31169; PriestType: 1; Pos: (X: 116642; Y: 77560; Z: - 2688)),
        (Loc: 'Godard'; NpcId: 31692; PriestType: 0; Pos: (X: 148256; Y: - 55504; Z: - 2779)),
        (Loc: 'Godard'; NpcId: 31693; PriestType: 1; Pos: (X: 149888; Y: - 56624; Z: - 2979)),
        (Loc: 'Rune'; NpcId: 31694; PriestType: 0; Pos: (X: 45664; Y: - 50368; Z: - 800)),
        (Loc: 'Rune'; NpcId: 31695; PriestType: 1; Pos: (X: 44528; Y: - 48420; Z: - 800)),
        (Loc: 'Schuttgart'; NpcId: 31997; PriestType: 0; Pos: (X: 86816; Y: - 143200; Z: - 1341)),
        (Loc: 'Schuttgart'; NpcId: 31998; PriestType: 1; Pos: (X: 85152; Y: - 142112; Z: - 1542))
        );

function StripHTML(const S: string): string;
var
    i: Integer;
    Tag: Boolean;
begin
    Result := '';
    Tag := False;
    for i := 1 to Length(S) do
    begin
        if S[i] = '<' then
            Tag := True
        else if S[i] = '>' then
            Tag := False
        else if not Tag then
            Result := Result + S[i];
    end;
    Result := Trim(Result);

end;

function FindNearestPriest(const CurrentPos: TPoint3D; Side: Integer): Integer;
var
    i: Integer;
    MinDist, D: Double;
begin
    Result := -1;
    MinDist := 1E30;
    for i := Low(PRIESTS) to High(PRIESTS) do
    begin
        if PRIESTS[i].PriestType = Side then
        begin
            D := CurrentPos.DistanceTo(PRIESTS[i].Pos); // Используем твой TPoint3D
            if D < MinDist then
            begin
                MinDist := D;
                Result := i;
            end;
        end;
    end;
end;

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
    ContextGuard.Enter; // <-- Захват
    try
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
    finally
        ContextGuard.Leave; // <-- Освобождение
    end;
end;

function GetContext(AOID: int32): TPathContext;
var
    i: int32;
begin
    ContextGuard.Enter; // <-- Захват
    try
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
    finally
        ContextGuard.Leave; // <-- Освобождение
    end;
end;

procedure TPathContext.SetOutputText(const AText: string);
begin
    AnsiStrings.StrPLCopy(FOutputBuffer, AnsiString(AText), MAX_DLG_BUFFER - 1);
end;

function TPathContext.GetAction(var act, X, Y, Z: Integer): boolean;
begin
    while (FCurrentStep >= Length(FSteps)) do
    begin
        Inc(FSegmentIndex);

        // Если сценарий закончился — выходим
        if (FSegmentIndex < 0) or (FSegmentIndex >= Length(FSegments)) then
            Exit(False);

        GenerateSegment(FSegments[FSegmentIndex]);
        FCurrentStep := 0;
    end;
    {if FCurrentStep >= Length(FSteps) then
    begin
        inc(FSegmentIndex);
        if FSegmentIndex >= Length(FSegments) then
            Exit(false);
        GenerateSegment(FSegments[FSegmentIndex]);
        FCurrentStep := 0;
    end;}

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

    function GetRandomSealIndex(s1, s2, s3: boolean): int32;
    var
        a: TIntArray;
        c: int32;
    begin
        c := 0;
        if s1 then
        begin
            setlength(a, c + 1);
            a[c] := 1;
            inc(c);
        end;
        if s2 then
        begin
            setlength(a, c + 1);
            a[c] := 2;
            inc(c);
        end;
        if s3 then
        begin
            setlength(a, c + 1);
            a[c] := 3;
        end;
        result := RandomFrom(a);
    end;

var
    DlgRaw: string;
    StartPointID //        targetID
    : int32;
begin

    try
        case SegmentType of
            saMoveTo:
                begin
                    // if not Params.TryGetValue('TargetID', Variant(TargetID)) then                        raise Exception.Create('TargetID not found in Params');
                    SetLength(FSteps, 3);

                    FSteps[0].AssignStr(graph_points[FGoalID].Name); // output goal name
                    FSteps[1].AssignInt(actFaceControl, 0, 0); // disable adr
                    FSteps[2].AssignInt(actSitStand, 1); // stand

                    StartPointID := FindNearestPoint(StartPoint);
                    if StartPointID = -1 then
                        raise Exception.Create('Start point not found');

                    DoAStar(FSteps, graph_points[StartPointID], graph_points[FGoalID]);
                end;
            saTest:
                begin
                    SetLength(FSteps, 1);
                    FSteps[0].act := actDlgTextToDLL;
                end;
            sa7S_Init:
                begin
                    if Params.ContainsKey('rbDusk') and Params['rbDusk'] then
                    begin
                        Params.AddOrSetValue('ss_side', 1);
                        Params.AddOrSetValue('ss_name', 'Dusk');
                    end
                    else
                    begin
                        Params.AddOrSetValue('ss_side', 0);
                        Params.AddOrSetValue('ss_name', 'Down');
                    end;

                    Params.AddOrSetValue('ss_priestindex', FindNearestPriest(StartPoint, int32(Params['ss_side'])));
                    if int32(Params['ss_priestindex']) = -1 then
                        raise Exception.Create('Жрец не найден!');

                    SetLength(FSteps, 1);
                    FSteps[0].AssignStr(//
                        Format('7 Signs: %s from %s', [string(Params['ss_name']), PRIESTS[int32(Params['ss_priestindex'])].Loc]) //
                        );
                end;
            sa7S_MoveToPriest:
                begin
                    SetLength(FSteps, 2);
                    FSteps[0].AssignInt(actFaceControl, 0, 0); // disable adr
                    FSteps[1].AssignInt(actSitStand, 1); // stand

                    if StartPoint.DistanceTo(PRIESTS[int32(Params['ss_priestindex'])].Pos) > 200 then
                    begin

                        StartPointID := FindNearestPoint(StartPoint);
                        if StartPointID = -1 then
                            raise Exception.Create('Start point not found');
                        DoAStar(FSteps, graph_points[StartPointID], PRIESTS[int32(Params['ss_priestindex'])].Pos);
                    end;
                end;
            sa7S_GetDlg:
                begin
                    SetLength(FSteps, 3);
                    FSteps[0].AssignInt(actNpcSel, PRIESTS[int32(Params['ss_priestindex'])].NpcId);
                    FSteps[1].AssignInt(actNpcDlg);
                    FSteps[2].AssignInt(actDlgTextToDLL);
                end;
            sa7S_Echo:
                begin

                    SetLength(FSteps, 1);
                    FSteps[0].AssignStr('echo: ' + StripHTML(string(AnsiString(FOutputBuffer))));
                end;
            sa7S_Analyze:
                begin
                    SetLength(FSteps, 0);
                    DlgRaw := string(AnsiString(FOutputBuffer));

                    if DlgRaw = '' then
                    begin
                        // Может, просто подождем или попробуем еще раз?
                        JumpTo(sa7S_GetDlg);
                        Exit;
                    end;
                    if Pos('Contributing', DlgRaw) > 0 then
                        JumpTo(sa7S_Already)
                    else if Pos('Participation', DlgRaw) > 0 then
                        JumpTo(sa7S_DoReg)
                    else
                        JumpTo(sa7S_Error);
                end;
            sa7S_DoReg:
                begin

                    SetLength(FSteps, 4);
                    FSteps[0].AssignInt(actDlgSel, 4);
                    FSteps[1].AssignInt(actDlgSel, GetRandomSealIndex(boolean(Params['cbSeal1']), boolean(Params['cbSeal2']), boolean(Params['cbSeal3']))); // Печать
                    FSteps[2].AssignInt(actDlgSel, 1);
                    FSteps[3].AssignStr('Registration done!');
                end;
            sa7S_Already:
                begin
                    SetLength(FSteps, 2);
                    FSteps[0].AssignStr('Already registered! Skipping...');
                    FSteps[1].AssignInt(actStop);
                    // Здесь можно добавить JumpTo(saStop) или что-то еще
                end;
            sa7S_Error:
                begin
                    SetLength(FSteps, 2);
                    FSteps[0].AssignStr('Unknown dialog state!');
                    FSteps[1].AssignInt(actStop);
                end;

        end;
    except
        on E: Exception do
        begin

            SetLength(FSteps, 2);
            FSteps[0].AssignStr('Error: ' + E.Message);
            FSteps[1].AssignInt(actStop);
        end;
    end;

end;

procedure TPathContext.GenerateScenario(PointData: uint32);
    procedure FillScenario(const Actions: array of TSegmentAction);
    var
        i: Integer;
    begin
        SetLength(FSegments, Length(Actions));
        for i := 0 to High(Actions) do
            FSegments[i] := Actions[i];

        FSegmentIndex := 0;
        FCurrentStep := 0;
        SetLength(FSteps, 0); // Сбрасываем микро-шаги
    end;
begin
    FGoalID := PointData;
    if (FGoalID and $80000000) = 0 then
    begin
        FillScenario([saMoveTo]);
        // simple moveto
//        SetLength(FSegments, 1);        FSegments[0] := saMoveTo;

    end
    else
        case (FGoalID and $7FFFFFFF) of

            1: // Семь Печатей
                begin
                    // Если rbDusk нажат - сторона 1, иначе 0 (Dawn)
//                    FillScenario([sa7S_Init, sa7S_MoveToPriest, sa7S_GetDlg, sa7S_Echo, sa7S_Analyze, sa7S_DoReg]);
                    FillScenario([sa7S_Init, sa7S_MoveToPriest, sa7S_GetDlg, sa7S_Echo, sa7S_Analyze, sa7S_DoReg, sa7S_Already, sa7S_Error]);
                end;

            3: // Наш Test
                begin
                    FillScenario([saTest]);
                    //    SetLength(FSegments, 1);                    FSegments[0] := saTest;
                end;
        end;

    // КЛЮЧЕВОЙ МОМЕНТ:
    FSegmentIndex := -1; // Указываем, что мы еще не начали
    FCurrentStep := 0;
    SetLength(FSteps, 0);

end;

procedure TPathContext.GetText(AText: PAnsiChar);
begin
    if (AText <> nil) then
        AnsiStrings.StrLCopy(FOutputBuffer, AText, MAX_DLG_BUFFER - 1)
    else
        FOutputBuffer[0] := #0;
end;

procedure TPathContext.JumpTo(const Action: TSegmentAction);
var
    i: Integer;
begin
    for i := 0 to High(FSegments) do
        if FSegments[i] = Action then
        begin
            FSegmentIndex := i;
            FCurrentStep := 0;
            GenerateSegment(FSegments[FSegmentIndex]); // Сразу заряжаем новые шаги
            Exit;
        end;
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
end;

initialization
    ContextGuard := TCriticalSection.Create;
finalization
    ContextGuard.Free;
end.


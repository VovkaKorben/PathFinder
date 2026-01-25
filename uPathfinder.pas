unit uPathfinder;

interface

uses
    Windows, System.SysUtils, System.Classes, System.Generics.Collections,
    System.Math, System.Diagnostics, astar, AnsiStrings, vcl.forms,
    uConstants;

const
    MAX_DLG_BUFFER = 16384;

type
    TPredefinedAction = (paMove, pa7Signs, paClanBank, paTest);
    TSegmentAction = (saStop, saMoveTo, saMoving, sa7S_MoveToPriest, sa7S_ProcessDlg, saTest);
    TBufferState = (bsIdle, bsWaiting, bsReady);

    TPathContext = class
    private
        OID: int32;
        FDialogueEchoed: Boolean;

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

        FSubStep: Integer; // Для шагов регистрации (4 -> seal -> 1)
        FPriestIndex: Integer; // Индекс выбранного непися
        procedure ProcessDialogue(var act, X: Integer); // Под-функция для парсинга

        procedure SetOutputText(const AText: string);
        function StripHTML(const S: string): string;
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

function TPathContext.StripHTML(const S: string): string;
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

function TPathContext.GetAction(var act, X, Y, Z: Integer): boolean;
begin
    // 1. Если ждём ответа от скрипта
    if FWaitState = bsWaiting then
    begin
        act := actDelay;
        X := 100;
        Exit(True);
    end;

    // 2. Если ответ пришёл — парсим его
    if FWaitState = bsReady then
    begin
        FWaitState := bsIdle;
        case FSegments[FCurrentSegment] of
            sa7S_ProcessDlg:
                begin
                    ProcessDialogue(act, X);
                    Exit(True);
                end;
            saTest:
                begin
                    SetOutputText('Message length: ' + IntToStr(Length(string(AnsiString(FOutputBuffer)))));
                    act := actStrFromDLL;
                    Exit(True);
                end;
        end;
    end;

    if FCurrentStep >= Length(FSteps) then
    begin
        inc(FCurrentSegment);
        if FCurrentSegment >= Length(FSegments) then
            Exit(false);
        GenerateSegment(FSegments[FCurrentSegment]);
        FCurrentStep := 0;
    end;

    act := FSteps[FCurrentStep].act;
    X := FSteps[FCurrentStep].data0;
    Y := FSteps[FCurrentStep].data1;
    Z := FSteps[FCurrentStep].data2;
    if FSteps[FCurrentStep].str <> '' then
        SetOutputText(FSteps[FCurrentStep].str);

    // Если действие — запрос текста (act 50), уходим в ожидание
    if act = actDlgTextToDLL then
        FWaitState := bsWaiting;

    inc(FCurrentStep);
    Result := True;
end;

procedure TPathContext.GenerateSegment(const SegmentType: TSegmentAction);
var

    StartID, TargetID: Integer;
begin

    try
        case SegmentType of
            saMoveTo:
                begin
                    // if not Params.TryGetValue('TargetID', Variant(TargetID)) then                        raise Exception.Create('TargetID not found in Params');
                    SetLength(FSteps, 3);
                    // output goal name
                    FSteps[0].act := actStrFromDLL;
                    FSteps[0].str := graph_points[FGoalID].Name;
                    // disable adr
                    FSteps[1].act := actFaceControl;
                    FSteps[1].data0 := 0;
                    FSteps[1].data1 := 0;
                    // stand
                    FSteps[2].act := actSitStand;
                    FSteps[2].data0 := 1;

                    StartID := FindNearestPoint(StartPoint);
                    if StartID = -1 then
                        raise Exception.Create('Start point not found');
                    // Генерируем шаги через А*
                    DoAStar(FSteps, graph_points[StartID], graph_points[FGoalID]);
                end;
            saTest:
                begin
                    SetLength(FSteps, 1);
                    FSteps[0].act := 50; // actDlgTextToDLL — просим скрипт прислать строку
                end;
            sa7S_MoveToPriest:
                begin
                    // Ищем точки в графе для нас и для жреца
                    StartID := FindNearestPoint(StartPoint);
                    TargetID := FindNearestPoint(PRIESTS[FPriestIndex].Pos);

                    if (StartID = -1) or (TargetID = -1) then
                        raise Exception.Create('Точка не найдена в графе');

                    SetLength(FSteps, 0); // Чистим перед генерацией
                    DoAStar(FSteps, graph_points[StartID], graph_points[TargetID]);

                    // Добавляем финальный шаг точно в координаты жреца [cite: 2026-01-24]
                    SetLength(FSteps, Length(FSteps) + 1);
                    with FSteps[High(FSteps)] do
                    begin
                        act := actMove;
                        PRIESTS[FPriestIndex].Pos.CopyTo(data0, data1, data2);
                    end;
                end;
            sa7S_ProcessDlg:
                begin
                    // Готовим серию действий для начала диалога
                    SetLength(FSteps, 3);
                    // 1. Выделить непися
                    FSteps[0].act := actNpcSel;
                    FSteps[0].data0 := PRIESTS[FPriestIndex].NpcId;
                    // 2. Открыть окно разговора
                    FSteps[1].act := actNpcDlg;
                    // 3. Запросить текст (это переведет систему в bsWaiting)
                    FSteps[2].act := actDlgTextToDLL;
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
var
    SideStr: string;
    vSide: int32;
begin
    FGoalID := PointData;
    if (FGoalID and $80000000) = 0 then
    begin
        // simple moveto
        SetLength(FSegments, 1);
        FSegments[0] := saMoveTo;

    end
    else
        case (FGoalID and $7FFFFFFF) of

            1: // Семь Печатей
                begin
                    // Если rbDusk нажат - сторона 1, иначе 0 (Dawn)
                    if Params.ContainsKey('rbDusk') and Params['rbDusk'] then
                    begin
                        vSide := 1;
                        SideStr := 'Dusk';
                    end
                    else
                    begin
                        vSide := 0;
                        SideStr := 'Dawn';
                    end;

                    FPriestIndex := FindNearestPriest(StartPoint, vSide);
                    if FPriestIndex = -1 then
                        raise Exception.Create('Жрец не найден!');

                    SetOutputText(Format('Используем %s, Priest of %s',
                        [PRIESTS[FPriestIndex].Loc, SideStr]));

                    SetLength(FSegments, 2);
                    FSegments[0] := sa7S_MoveToPriest;
                    FSegments[1] := sa7S_ProcessDlg;
                    FSubStep := 0;
                end;

            3: // Наш Test
                begin
                    SetLength(FSegments, 1);
                    FSegments[0] := saTest;
                end;
        end;

    // КЛЮЧЕВОЙ МОМЕНТ:
    FCurrentSegment := -1; // Указываем, что мы еще не начали
    FCurrentStep := 0;
    SetLength(FSteps, 0);
    FDialogueEchoed := False;
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

procedure TPathContext.ProcessDialogue(var act, X: Integer);
var
    DlgRaw, DlgClean: string;
    Available: TList<Integer>;
begin
    DlgRaw := string(AnsiString(FOutputBuffer)); // Берем то, что прислал скрипт
    DlgClean := StripHTML(DlgRaw);

    // --- БЛОК ЭХО (закомментируй это, если надоест лог) ---
    if not FDialogueEchoed then
    begin
        SetOutputText('Echo: ' + DlgClean);
        act := actStrFromDLL; // Код 80: отправляем текст в Адрик
        FDialogueEchoed := True;

        // КЛЮЧЕВОЙ МОМЕНТ: заставляем DLL зайти сюда же на следующем тике
        FWaitState := bsReady;
        Exit;
    end;
    FDialogueEchoed := False;

    // Случай 8: Уже зарегистрированы
    if Pos('Contributing seal stones', DlgRaw) > 0 then
    begin
        SetOutputText('Уже зарегистрированы');
        FCurrentSegment := Length(FSegments); // Стоп машина
        Exit;
    end;

    // Случай 7: Нужно регистрироваться
    if Pos('Participation in the Seven Signs', DlgRaw) > 0 then
    begin
        case FSubStep of
            0:
                begin
                    act := actDlgSel;
                    X := 4;
                    FSubStep := 1;
                    FWaitState := bsWaiting;
                end;
            1:
                begin
                    // Выбираем печать из тех, что ты отметил [cite: 2026-01-24]
                    Available := TList<Integer>.Create;
                    // Проверяем наши чекбоксы по именам
                    if Params.ContainsKey('cbSeal1') and Params['cbSeal1'] then
                        Available.Add(1);
                    if Params.ContainsKey('cbSeal2') and Params['cbSeal2'] then
                        Available.Add(2);
                    if Params.ContainsKey('cbSeal3') and Params['cbSeal3'] then
                        Available.Add(3);

                    if Available.Count = 0 then
                        Available.Add(1); // Заплатка, если ничего не выбрано
                    act := actDlgSel;
                    X := Available[Random(Available.Count)];
                    Available.Free;
                    FSubStep := 2;
                    FWaitState := bsWaiting;
                end;
            2:
                begin
                    act := actDlgSel;
                    X := 1;
                    FSubStep := 3;
                    FWaitState := bsWaiting;
                end;
            3:
                begin
                    SetOutputText('Регистрация ОК');
                    FCurrentSegment := Length(FSegments);
                end;
        end;
        Exit;
    end;

    // Если ничего не подошло
    SetOutputText('Какая-то херня с регистрацией');
    FCurrentSegment := Length(FSegments);
end;
end.


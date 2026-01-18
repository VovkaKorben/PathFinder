unit uPathfinder;

interface

uses
    Windows, System.SysUtils, System.Classes, System.Generics.Collections, System.Math, System.Diagnostics, astar;

const

    MAX_DLG_BUFFER = 16384;
    // Импорты SQLite


    // const    stIdle = 0;    stWaiting = 1;    stReady = 2;

type

    TSegmentAction = (saStop, saMoving, saParsing);
    TBufferState = (bsIdle, bsWaiting, bsReady);

    TResultNode = record
        act, data0, data1, data2: int32;

        procedure AssignFromPoint(const p: TPoint3D);
        procedure AssignAction(const npc_id, a0, a1: int32);
        procedure CopyTo(var aa, ax, ay, az: int32);
    end;

    PPathContext = ^TPathContext; // Указатель для удобства работы

    TPathContext = record
    private
        OID: int32;
        gScore: TDoubleArray; // Стоимость пути от старта
        fScore: TDoubleArray; // Полная оценочная стоимость
        CameFrom: TIntArray; // Карта переходов

        LinkIndexesCount: int32;
        LinkIndexes: TIntArray;

        OpenSetCount: int32;
        OpenSet, OpenSetIndex: array of int32;
        FRecv1, FRecv2, FRecv3: int32;
        FWaitState: TBufferState; // Состояние: 0 - норм, 31 - ждём строку

        FFinalPath: array of TResultNode; // Массив точек найденного маршрута
        FLastResponse, FOutputBuffer: array [0 .. MAX_DLG_BUFFER] of AnsiChar;

        FCurrentStep: int32;
        procedure SetOutputText(const AText: string);
        procedure ReconstructPath(node_id: int32);
        procedure Init;
        procedure Reset;

    public
        PointCount, ActionCount: int32; // Количество узлов в результате
        Distance, TotalCost: Double;

        function GetNode(const Index: int32; var act, X, Y, Z: int32): boolean;
        function DoAStar(start_point, end_point: TPoint3D): int32;

        procedure GetText(AText: PAnsiChar);
        function SendStringAddr: PAnsiChar;
        procedure RecvInt(X, Y, Z: Integer);
        function GetAction(var act, X, Y, Z: Integer): boolean;
    end;

var

    Contexts: array of PPathContext;

    graph_points: array of TPoint3D;
    graph_points_count: int32;

function GetContext(AOID: int32): PPathContext;
function FindNearestPoint(const p: TPoint3D): int32;
procedure Release(AOID: int32);
procedure InitPathfinder(db_path: PAnsiChar); // Переносим заголовок сюда

var
    FullDbPath: string; // Переносим переменную пути в интерфейс

implementation

{ uPathfinder.pas }
{
  function TPathContext.GenerateNextSegment: boolean;
  begin
  Result := True;
  SetLength(FFinalPath, 0); // Чистим старый набор действий перед загрузкой нового

  case FQuestGoal of

  // --- СЦЕНАРИЙ 1: Регистрация в 7 Печатях ---
  qg7SignsReg:
  case FSegmentState of

  saIdle: // ШАГ 1: Нужно дойти до NPC
  begin
  AddSegment_Move(TargetNPC_Pos); // Загружаем кубик "Путь"
  FSegmentState := saMoving; // Следующий раз зайдем уже в стадию движения
  end;

  saMoving: // ШАГ 2: Пришли, надо поговорить
  begin
  AddSegment_Talk(TargetNPC_ID); // Загружаем кубик "Разговор"
  FSegmentState := saTalking;
  FWaitState := stWaiting; // DLL замирает, ждёт HTML от скрипта
  end;

  saParsing: // ШАГ 3: Анализируем то, что прислал скрипт
  begin
  if AnalyzeHTML('Already Registered') then
  AddSegment_Message('Master, you are already in!') // Кубик "Сообщение"
  else
  AddSegment_Click(Bypass_Reg); // Кубик "Клик по кнопке"

  FSegmentState := saFinished;
  end;
  end;

  // --- СЦЕНАРИЙ 2: Другой квест (например, чистка инвентаря) ---
  qgWarehouse:
  // Тут будет такая же структура, но со своими "кубиками"
  // Например: AddSegment_Move(Warehouse_Pos) -> AddSegment_Talk -> saParsing (сдать вещи)
  end;

  FCurrentStep := 0; // Начинаем выполнять свежезагруженный сегмент с начала
  end;
}

procedure Release(AOID: int32);
var
    i, j: int32;
begin
    for i := 0 to High(Contexts) do
    begin
        if Contexts[i]^.OID = AOID then
        begin
            SetLength(Contexts[i]^.gScore, 0);
            SetLength(Contexts[i]^.fScore, 0);
            SetLength(Contexts[i]^.CameFrom, 0);
            SetLength(Contexts[i]^.OpenSet, 0);
            SetLength(Contexts[i]^.OpenSetIndex, 0);
            SetLength(Contexts[i]^.FFinalPath, 0);
            FreeMem(Contexts[i]);
            for j := i to High(Contexts) - 1 do
                Contexts[j] := Contexts[j + 1];

            SetLength(Contexts, Length(Contexts) - 1);
            Exit;
        end;
    end;
end;

function FindNearestPoint(const p: TPoint3D): int32;
var
    MinDist, CurDist: Double;
    j: int32;
begin
    Result := -1;
    MinDist := 1E30;
    for j := 0 to graph_points_count - 1 do
    begin
        if graph_points[j].ID = -1 then
            Continue;

        CurDist := p.DistanceTo(graph_points[j]);
        if CurDist < MinDist then
        begin
            MinDist := CurDist;
            Result := j;
        end;
    end;
end;

// Внутренняя функция: найти контекст или создать новый
function GetContext(AOID: int32): PPathContext;
var
    i: int32;
begin
    Result := nil;

    // 1. Ищем, нет ли уже такого ID в списке
    for i := 0 to High(Contexts) do
        if Contexts[i]^.OID = AOID then
        begin
            Result := Contexts[i];
            Exit;
        end;

    // 2. Если не нашли — создаем новый блок памяти
    GetMem(Result, SizeOf(TPathContext));
    FillChar(Result^, SizeOf(TPathContext), 0); // Обнуляем всё

    Result^.OID := AOID;
    Result^.Init;

    // Добавляем указатель в наш общий список
    SetLength(Contexts, Length(Contexts) + 1);
    Contexts[High(Contexts)] := Result;
end;

{ TPathContext }
procedure TPathContext.SetOutputText(const AText: string);
begin
    StrPLCopy(FOutputBuffer, AnsiString(AText), MAX_DLG_BUFFER - 1);
end;

function TPathContext.GetAction(var act, X, Y, Z: Integer): boolean;
begin
    Result := True; // В тесте всегда возвращаем True, чтобы цикл в скрипте не падал

    { 1. Контролёр ожидания: если ждём данных, скрипт "спит" }
    if FWaitState = bsWaiting then
    begin
        act := 80; // Команда Delay
        X := 100;
        Exit;
    end;

    { 2. Если данные пришли (stReady), сбрасываем флаг и идём дальше }
    if FWaitState = bsReady then
        FWaitState := bsIdle;

    { 3. ТЕСТОВАЯ ПОСЛЕДОВАТЕЛЬНОСТЬ (без всяких FFinalPath) }
    case FCurrentStep of
        0:
            begin // Тест печати
                act := 5;
                SetOutputText('DLL: Link test started...'); // Кладём строку в FOutputBuffer
            end;

        1:
            begin // Тест приёма строки (C -> S)
                act := 31; // Просим скрипт прислать DlgText
                FWaitState := bsWaiting;
            end;

        2:
            begin // Тест возврата строки (S -> C)
                act := 5;
                { Берём то, что скрипт прислал на шаге 1, и отдаём обратно для Print }
                // SetOutputText('DLL получено: ' + string(FLastResponse));
                // SetOutputText('DLL получено: ' + UTF8ToString(PAnsiChar(@FLastResponse[0])));
                // SetOutputText('DLL received HTML. Length: ' + IntToStr(Length(string(FLastResponse))));
                SetOutputText('DLL received HTML. Length: ' + inttostr(Length(string(FLastResponse))));

            end;

        3:
            begin // Тест чисел (C -> S)
                act := 40; // Допустим, 40 - это наша тестовая команда на числа
                FWaitState := bsWaiting;
            end;

        4:
            begin // Тест вывода полученных чисел
                act := 5;

                SetOutputText('Numbers from script: ' + inttostr(FRecv1) + ', ' + inttostr(FRecv2));
            end;

        5:
            begin // Завершение
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

function TPathContext.GetNode(const Index: int32; var act, X, Y, Z: int32): boolean;
begin
    Result := (Index >= 0) and (Index < (PointCount + ActionCount));
    if Result then
        FFinalPath[index].CopyTo(act, X, Y, Z);
end;

procedure TPathContext.GetText(AText: PAnsiChar);
begin
    if (AText <> nil) then
        StrLCopy(FLastResponse, AText, MAX_DLG_BUFFER - 1)
    else
        FLastResponse[0] := #0; // Если пришел nil, просто обнуляем буфер

    FWaitState := bsReady;
end;

procedure TPathContext.Init;

begin
    SetLength(gScore, graph_points_count);
    SetLength(fScore, graph_points_count);
    SetLength(CameFrom, graph_points_count);

    SetLength(OpenSet, graph_points_count);

    SetLength(OpenSetIndex, graph_points_count);

end;

procedure TPathContext.Reset;
var
    i: int32;
begin
    SetLength(FFinalPath, 0);
    OpenSetCount := 0;

    PointCount := 0;
    ActionCount := 0;
    Distance := 0;
    TotalCost := 0;
    for i := 0 to Length(graph_points) - 1 do
    begin
        gScore[i] := 1E30; // Бесконечность
        fScore[i] := 1E30;
        CameFrom[i] := -1; // Предков пока нет
        OpenSetIndex[i] := -1;
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
    FWaitState := bsReady;
end;

{ TResultNode }

procedure TResultNode.AssignAction(const npc_id, a0, a1: int32);
begin
    act := 1;
    data0 := npc_id;
    data1 := a0;
    data2 := a1;
end;

procedure TResultNode.AssignFromPoint(const p: TPoint3D);
begin
    act := 0;
    data0 := p.X;
    data1 := p.Y;
    data2 := p.Z;
end;

procedure TResultNode.CopyTo(var aa, ax, ay, az: int32);
begin
    aa := act;
    ax := data0;
    ay := data1;
    az := data2;
end;

end.

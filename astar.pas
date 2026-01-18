unit astar;

interface

uses Sysutils, Classes;

const
    SQLiteDLL = 'sqlite3.dll';
function sqlite3_open(filename: PAnsiChar; var db: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_close(db: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_prepare_v2(db: Pointer; zSql: PAnsiChar; nByte: int32; var ppStmt: Pointer; pzTail: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_step(pStmt: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_finalize(pStmt: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_column_int(pStmt: Pointer; iCol: int32): int32; cdecl; external SQLiteDLL;
function sqlite3_column_text(pStmt: Pointer; iCol: int32): PAnsiChar; cdecl; external SQLiteDLL;
function sqlite3_errmsg(db: Pointer): PAnsiChar; cdecl; external SQLiteDLL; // Для детальных ошибок

type

    TDoubleArray = array of Double; // Массив для хранения весов и оценок (индекс = ID точки)
    TIntArray = array of int32; // Массив для хранения "предков" (чтобы восстановить путь)

    TLink = record
        ID, Weight, TargetID: int32;
        Distance: Double;
        ActionData: string;
    end;

    TPoint3D = record
        ID: int32;
        X, Y, Z: int32;
        Name: string;
        Links: array of TLink;

        function DistanceTo(const Other: TPoint3D): Double; overload;
        function DistanceTo(const TargetX, TargetY, TargetZ: int32): Double; overload;
        function ToString(const simple: boolean = true): string;
        procedure CopyTo(var tx, ty, tz: int32); overload;

        constructor Create(const tx, ty, tz: int32);

    end;

procedure Log(const Msg: string; const OID: int32 = 0);

implementation

procedure Log(const Msg: string; const OID: int32 = 0);
var
    F: TextFile;
    LName: string;
begin
    try
        if OID = 0 then
            LName := 'pathfinder'
        else
            LName := inttostr(OID);
        LName := ExtractFilePath(GetModuleName(HInstance)) + LName + '.log';
        AssignFile(F, LName);
        if FileExists(LName) then
            Append(F)
        else
            Rewrite(F);
        Writeln(F, '[' + FormatDateTime('hh:nn:ss', Now) + '] ' + Msg);
        CloseFile(F);
    except
        // Если даже лог не пишется, тут мы бессильны
    end;
end;

procedure InitPathfinder(db_path: PAnsiChar);
var
    db, stmt: Pointer;
    pText: PAnsiChar;
    j, t, link_count: int32;
    start_point_id, end_point_id: int32;
    ErrCode: int32;
    tmpLink: TLink;

    function check_DB_error(err_code: int32): boolean;
    begin
        Result := err_code = 0;
        if not Result then
            Log('ОШИБКА PREPARE (Код ' + inttostr(err_code) + '): ' + UTF8ToString(sqlite3_errmsg(db)));
    end;

begin
    SetLength(graph_points, 0);

    if not check_DB_error(sqlite3_open(db_path, db)) then
        Exit;

    try
        try
            // read point max ID
            if not check_DB_error(sqlite3_prepare_v2(db, 'SELECT max(id) FROM point', -1, stmt, nil)) then
                Exit;

            try
                while sqlite3_step(stmt) = 100 do
                    graph_points_count := sqlite3_column_int(stmt, 0) + 1;
                SetLength(graph_points, graph_points_count);
                for j := 0 to graph_points_count - 1 do
                    graph_points[j].ID := -1;

            finally
                sqlite3_finalize(stmt);
            end;

            // load graph_points
            if not check_DB_error(sqlite3_prepare_v2(db, 'SELECT id, x, y, z, name FROM point', -1, stmt, nil)) then
                Exit;

            try
                while sqlite3_step(stmt) = 100 do
                    with graph_points[sqlite3_column_int(stmt, 0)] do
                    begin
                        ID := sqlite3_column_int(stmt, 0);
                        X := sqlite3_column_int(stmt, 1);
                        Y := sqlite3_column_int(stmt, 2);
                        Z := sqlite3_column_int(stmt, 3);
                        pText := sqlite3_column_text(stmt, 4);
                        if pText <> nil then
                            Name := UTF8ToString(pText)
                        else
                            Name := '';
                        SetLength(Links, 0);
                    end;
            finally
                sqlite3_finalize(stmt);
            end;

            // fetch links
            if not check_DB_error(sqlite3_prepare_v2(db, 'SELECT l.id, l.start_point_id, l.end_point_id, l.one_way, e.action_data, e.weight FROM link l LEFT JOIN extra e ON l.id = e.link_id', -1, stmt, nil)) then
                Exit;
            // if not check_DB_error(sqlite3_prepare_v2(db, 'SELECT id,start_point_id, end_point_id, one_way, action_data,weight FROM link', -1, stmt, nil)) then                Exit;

            try

                while sqlite3_step(stmt) = 100 do
                begin
                    start_point_id := sqlite3_column_int(stmt, 1);
                    end_point_id := sqlite3_column_int(stmt, 2);

                    // check for graph_points exists and valid
                    if (start_point_id >= graph_points_count) or (end_point_id >= graph_points_count) then
                        Continue;
                    if (graph_points[start_point_id].ID = -1) or (graph_points[end_point_id].ID = -1) then
                        Continue;

                    // Обновленный блок чтения колонок:
                    tmpLink.ID := sqlite3_column_int(stmt, 0);
                    tmpLink.TargetID := sqlite3_column_int(stmt, 2);

                    pText := sqlite3_column_text(stmt, 4); // Теперь это колонка из таблицы extra
                    if pText <> nil then
                        tmpLink.ActionData := UTF8ToString(pText)
                    else
                        tmpLink.ActionData := '';

                    tmpLink.Weight := sqlite3_column_int(stmt, 5); // Теперь это колонка из таблицы extra

                    {
                      tmpLink.ID := sqlite3_column_int(stmt, 0);
                      tmpLink.TargetID := sqlite3_column_int(stmt, 2);
                      pText := sqlite3_column_text(stmt, 4);
                      if pText <> nil then
                      tmpLink.ActionData := UTF8ToString(pText)
                      else
                      tmpLink.ActionData := '';
                      tmpLink.Weight := sqlite3_column_int(stmt, 5);
                    }

                    tmpLink.Distance := graph_points[start_point_id].DistanceTo(graph_points[end_point_id]);

                    link_count := Length(graph_points[start_point_id].Links);
                    SetLength(graph_points[start_point_id].Links, link_count + 1);
                    graph_points[start_point_id].Links[link_count] := tmpLink;

                    if sqlite3_column_int(stmt, 3) = 0 then
                    begin
                        link_count := Length(graph_points[end_point_id].Links);
                        SetLength(graph_points[end_point_id].Links, link_count + 1);
                        tmpLink.TargetID := start_point_id;
                        graph_points[end_point_id].Links[link_count] := tmpLink;
                    end;

                end;
            finally
                sqlite3_finalize(stmt);
            end;

        except
            on E: Exception do
                Log('КРИТИЧЕСКАЯ ОШИБКА при загрузке: ' + E.Message)
        end;
    finally
        sqlite3_close(db);
    end;
end;

function TPoint3D.DistanceTo(const Other: TPoint3D): Double;
begin
    // Используем формулу Пифагора с приведением к Int64
    Result := Sqrt(Sqr(Int64(Other.X) - X) + Sqr(Int64(Other.Y) - Y) + Sqr(Int64(Other.Z) - Z));
end;

procedure TPoint3D.CopyTo(var tx, ty, tz: int32);
begin
    tx := X;
    ty := Y;
    tz := Z;
end;

constructor TPoint3D.Create(const tx, ty, tz: int32);
begin
    X := tx;
    Y := ty;
    Z := tz;
end;

function TPoint3D.DistanceTo(const TargetX, TargetY, TargetZ: int32): Double;
begin
    Result := Sqrt(Sqr(Int64(TargetX) - X) + Sqr(Int64(TargetY) - Y) + Sqr(Int64(TargetZ) - Z));
end;

function TPoint3D.ToString(const simple: boolean): string;
begin
    if simple then
        Result := Format('%d, %d', [X, Y])
    else
        Result := Format('%d, %d, %d', [X, Y, Z]);

end;

function TPathContext.DoAStar(start_point, end_point: TPoint3D): int32;

    procedure OpenSetAdd(node_id: int32);
    begin
        if OpenSetIndex[node_id] <> -1 then
            Exit;
        OpenSetIndex[node_id] := OpenSetCount;
        OpenSet[OpenSetCount] := node_id;
        inc(OpenSetCount);
    end;
    procedure OpenSetRemove(node_id: int32);
    var
        j, idx: int32;
    begin
        idx := OpenSetIndex[node_id];
        if idx = -1 then
            Exit;

        OpenSetIndex[node_id] := -1;
        dec(OpenSetCount);

        if idx <> OpenSetCount then // put last element in hole
        begin
            OpenSet[idx] := OpenSet[OpenSetCount];
            OpenSetIndex[OpenSet[idx]] := idx;
        end;

    end;

    function GetLowestF(): int32;
    var
        j, idx: int32;
    begin
        idx := 0;
        for j := 1 to OpenSetCount - 1 do
            if fScore[OpenSet[j]] < fScore[OpenSet[idx]] then
                idx := j;
        Result := OpenSet[idx];
    end;

var
    StartID, endID, Current, NeighborID, j: int32;
    TentativeG: Double;
begin
    Result := 0;

    try
        StartID := FindNearestPoint(start_point);
        endID := FindNearestPoint(end_point);

        if (StartID = -1) or (endID = -1) then
        begin
            Log('ОШИБКА: Точки старта или финиша не найдены в базе.');
            Exit;
        end;

        Reset;

        OpenSetAdd(StartID);
        gScore[StartID] := 0;
        fScore[StartID] := graph_points[StartID].DistanceTo(graph_points[endID]);

        while OpenSetCount > 0 do
        begin
            Current := GetLowestF();

            if Current = endID then
            begin
                ReconstructPath(Current);
                Result := Length(FFinalPath);
                Log(Format('Путь найден! Узлов: %d', [Result]));
                Exit;
            end;

            OpenSetRemove(Current);
            for j := 0 to Length(graph_points[Current].Links) - 1 do
            begin
                NeighborID := graph_points[Current].Links[j].TargetID;

                TentativeG := gScore[Current] + graph_points[Current].Links[j].Distance + graph_points[Current].Links[j].Weight;
                if TentativeG < Self.gScore[NeighborID] then
                begin
                    CameFrom[NeighborID] := Current;
                    gScore[NeighborID] := TentativeG;
                    fScore[NeighborID] := TentativeG + graph_points[NeighborID].DistanceTo(graph_points[endID]);

                    OpenSetAdd(NeighborID);
                end;
            end;
        end;
        Log('ВНИМАНИЕ: Путь не найден (граф разорван).', OID);

    except
        on E: Exception do
            Log('КРИТИЧЕСКАЯ ОШИБКА A*: ' + E.Message, OID);
    end;
end;

procedure TPathContext.ReconstructPath(node_id: int32);
    function GetLinkIndex(const start_pt, end_pt: int32): int32;
    var
        j: int32;
    begin
        Result := -1;
        for j := 0 to Length(graph_points[start_pt].Links) - 1 do
            if graph_points[start_pt].Links[j].TargetID = end_pt then
            begin
                Result := j;
                break;
            end;
    end;

var
    // Node: TResultNode;
    // ParentID: int32;
    ActData: string;
    // Lnk: TLink;
    Params: TStringList;
    link_index, temp_id, insert_pos: int32;

begin
    Params := TStringList.Create;
    try
        // setup action parser
        Params.Delimiter := ';';
        Params.StrictDelimiter := true;

        // calculate points count in result
        temp_id := node_id;
        while true do
        begin
            if CameFrom[temp_id] = -1 then
                break;
            inc(PointCount);
            link_index := GetLinkIndex(CameFrom[temp_id], temp_id);
            ActData := graph_points[CameFrom[temp_id]].Links[link_index].ActionData;

            if ActData <> '' then
            begin
                Params.DelimitedText := ActData;
                inc(ActionCount);
                // if Params.Values['return'] = '1' then                    inc(ActionCount);
            end;
            temp_id := CameFrom[temp_id];
        end;
        inc(PointCount);

        // sum pt+actions and setup final array len
        insert_pos := PointCount + ActionCount;
        SetLength(FFinalPath, insert_pos);

        dec(insert_pos); // set pointer to last element
        temp_id := node_id;
        while true do
        begin
            FFinalPath[insert_pos].AssignFromPoint(graph_points[temp_id]);

            dec(insert_pos);
            if CameFrom[temp_id] = -1 then
                break;

            link_index := GetLinkIndex(CameFrom[temp_id], temp_id);

            Distance := Distance + graph_points[CameFrom[temp_id]].Links[link_index].Distance;
            TotalCost := TotalCost + graph_points[CameFrom[temp_id]].Links[link_index].Distance + graph_points[CameFrom[temp_id]].Links[link_index].Weight;

            ActData := graph_points[CameFrom[temp_id]].Links[link_index].ActionData;
            if ActData <> '' then
            begin
                Params.DelimitedText := ActData;
                if Params.Values['return'] = '1' then
                begin
                    FFinalPath[insert_pos].AssignFromPoint(graph_points[CameFrom[temp_id]]);
                    dec(insert_pos);
                end;
                FFinalPath[insert_pos].AssignAction(StrToIntDef(Params.Values['npc_id'], 0), StrToIntDef(Params.Values['act0'], 0), StrToIntDef(Params.Values['act1'], 0));
                dec(insert_pos);
            end;

            temp_id := CameFrom[temp_id];
        end;

    finally
        Params.Free;
    end;
end;

{
  initialization


  FullDbPath := 'C:\la_db\new.db3';

  if FileExists(FullDbPath) then
  begin
  // Загружаем базу при старте DLL
  InitPathfinder(PAnsiChar(AnsiString(FullDbPath)));
  end else begin
  Log('КРИТИЧЕСКАЯ ОШИБКА: Файл базы данных не найден: ' + FullDbPath);
  end;
}
end.

unit astar;

interface

uses Sysutils, Classes, uConstants;

const
    SQLiteDLL = 'sqlite3.dll';
    FullDbPath = 'C:\la_db\new.db3';
function sqlite3_open(filename: PAnsiChar; var db: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_close(db: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_prepare_v2(db: Pointer; zSql: PAnsiChar; nByte: int32; var ppStmt: Pointer; pzTail: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_step(pStmt: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_finalize(pStmt: Pointer): int32; cdecl; external SQLiteDLL;
function sqlite3_column_int(pStmt: Pointer; iCol: int32): int32; cdecl; external SQLiteDLL;
function sqlite3_column_text(pStmt: Pointer; iCol: int32): PAnsiChar; cdecl; external SQLiteDLL;
function sqlite3_errmsg(db: Pointer): PAnsiChar; cdecl; external SQLiteDLL;

type

    TDoubleArray = array of Double;
    TIntArray = array of int32;

    // хранит "микрокод" для действий из ActionData
    TMicrocodeStep = array [0 .. 1] of int32;
    TMicrocodeList = array of TMicrocodeStep;

    TLink = record
        ID, Weight, TargetID: int32;
        Distance: Double;
        ActionData: TMicrocodeList // шаги микрокода
        end;

        TPoint3D = record ID: int32;
        X, Y, Z: int32;
        Name: string;
        Links: array of TLink;

        function DistanceTo(const Other: TPoint3D): Double; overload;
        function DistanceTo(const TargetX, TargetY, TargetZ: int32): Double; overload;
        function ToString(const simple: boolean = true): string;
        procedure CopyTo(var tx, ty, tz: int32); overload;

        constructor Create(const tx, ty, tz: int32);

    end;

    TStep = record
        act, data0, data1, data2: int32;
        str: string;
    end;

    // procedure AssignFromPoint(const p: TPoint3D);    procedure AssignAction(const npc_id, a0, a1: int32);    procedure CopyTo(var aa, ax, ay, az: int32);
    TSteps = array of TStep;

    TPathInfo = record

        PointCount, ActionCount, RawActionCount: int32;
        Distance, TotalCost: Double;

    end;

var
    graph_points: array of TPoint3D;
    graph_points_count: int32;
procedure Log(const Msg: string; const OID: int32 = 0);
function DoAStar(var steps: TSteps; start_point, end_point: TPoint3D): TPathInfo;
function FindNearestPoint(const p: TPoint3D): int32;
procedure InitPathfinder(db_path: string);

implementation

var

    gScore, fScore: TDoubleArray;
    OpenSet, OpenSetIndex, CameFrom: TIntArray;

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
        // ���� ���� ��� �� �������, ��� �� ���������
    end;
end;

function TPoint3D.DistanceTo(const Other: TPoint3D): Double;
begin
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

function DoAStar(var steps: TSteps; start_point, end_point: TPoint3D): TPathInfo;
var


    // LinkIndexesCount: int32;  LinkIndexes: TIntArray;

    OpenSetCount: int32;

    start_point_id, end_point_id, Current, NeighborID, j: int32;
    TentativeG: Double;
    procedure reset_astar;
    var
        i: int32;
    begin
        with Result do
        begin
            PointCount := 0;
            ActionCount := 0;
            RawActionCount := 0;
            Distance := 0.0;
            TotalCost := 0.0;
        end;

        { SetLength(Contexts[i]^.gScore, 0);
          SetLength(Contexts[i]^.fScore, 0);
          SetLength(Contexts[i]^.CameFrom, 0);
          SetLength(Contexts[i]^.OpenSet, 0);
          SetLength(Contexts[i]^.OpenSetIndex, 0);
        }
        // SetLength(FFinalPath, 0);
        OpenSetCount := 0;

        for i := 0 to Length(graph_points) - 1 do
        begin
            gScore[i] := 1E30; // �������������
            fScore[i] := 1E30;
            CameFrom[i] := -1; // ������� ���� ���
            OpenSetIndex[i] := -1;
        end;
    end;
    procedure ReconstructPath(node_id: int32);

        function GetLinkIndex(const start_point_id, end_point_id: int32): int32;
        var
            j: int32;
        begin
            Result := -1;
            for j := 0 to Length(graph_points[start_point_id].Links) - 1 do
                if graph_points[start_point_id].Links[j].TargetID = end_point_id then
                begin
                    Result := j;
                    break;
                end;
        end;

    var
        j, link_index, temp_id, insert_pos, mc_len: int32;
        ActData: TMicrocodeList;

    begin

        // calculate steps count in result ----------------------------------------------------------------
        temp_id := node_id;
        while true do
        begin
            if CameFrom[temp_id] = -1 then
                break;
            inc(Result.PointCount);
            link_index := GetLinkIndex(CameFrom[temp_id], temp_id);
            inc(Result.RawActionCount, Length(graph_points[CameFrom[temp_id]].Links[link_index].ActionData));
            temp_id := CameFrom[temp_id];
        end;
        inc(Result.PointCount);

        // setup final calculation --------------------------------------------------------------------
        // sum pt+actions and setup final array len
        insert_pos := Result.PointCount + Result.RawActionCount;
        SetLength(steps, Length(steps) + insert_pos);

        dec(insert_pos); // set pointer to last element
        temp_id := node_id;

        // fill path with steps --------------------------------------------------------------------
        while true do
        begin

            // insert move point
            with steps[insert_pos] do
            begin
                act := actMove;
                data0 := graph_points[temp_id].X;
                data1 := graph_points[temp_id].Y;
                data2 := graph_points[temp_id].Z;
            end;

            dec(insert_pos);
            if CameFrom[temp_id] = -1 then
                break;

            link_index := GetLinkIndex(CameFrom[temp_id], temp_id);

            Result.Distance := Result.Distance + graph_points[CameFrom[temp_id]].Links[link_index].Distance;
            Result.TotalCost := Result.TotalCost + graph_points[CameFrom[temp_id]].Links[link_index].Distance + graph_points[CameFrom[temp_id]].Links[link_index].Weight;

            // expand microcode to real steps
            ActData := graph_points[CameFrom[temp_id]].Links[link_index].ActionData;
            mc_len := Length(ActData);
            if mc_len > 0 then
            begin
                for j := mc_len - 1 downto 0 do
                begin
                    steps[insert_pos].act := ActData[j][0];
                    case steps[insert_pos].act of
                        actMove:
                            begin
                                steps[insert_pos].data0 := graph_points[ActData[j][1]].X;
                                steps[insert_pos].data1 := graph_points[ActData[j][1]].Y;
                                steps[insert_pos].data2 := graph_points[ActData[j][1]].Z;
                            end;
                        actNpcSel, actNpcDlg:
                            begin
                                steps[insert_pos].data0 := ActData[j][1];
                            end;
                    end;
                    dec(insert_pos);
                end;

            end;

            temp_id := CameFrom[temp_id];
        end;

    end;
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
        idx: int32;
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

begin
    reset_astar();

    try
        start_point_id := FindNearestPoint(start_point);
        end_point_id := FindNearestPoint(end_point);

        if (start_point_id = -1) or (end_point_id = -1) then
        begin
            Log('start or end point not found.');
            Exit;
        end;

        OpenSetAdd(start_point_id);
        gScore[start_point_id] := 0;
        fScore[start_point_id] := graph_points[start_point_id].DistanceTo(graph_points[end_point_id]);

        while OpenSetCount > 0 do
        begin
            Current := GetLowestF();

            if Current = end_point_id then
            begin
                ReconstructPath(Current);
                // Result := Length(FFinalPath);
                // Log(Format('���� ������! �����: %d', [Result]));
                Exit;
            end;

            OpenSetRemove(Current);
            for j := 0 to Length(graph_points[Current].Links) - 1 do
            begin
                NeighborID := graph_points[Current].Links[j].TargetID;

                TentativeG := gScore[Current] + graph_points[Current].Links[j].Distance + graph_points[Current].Links[j].Weight;
                if TentativeG < gScore[NeighborID] then
                begin
                    CameFrom[NeighborID] := Current;
                    gScore[NeighborID] := TentativeG;
                    fScore[NeighborID] := TentativeG + graph_points[NeighborID].DistanceTo(graph_points[end_point_id]);

                    OpenSetAdd(NeighborID);
                end;
            end;
        end;
        // Log('��������: ���� �� ������ (���� ��������).');

    except
        on E: Exception do
            Log('error in A*: ' + E.Message);
    end;
end;

procedure InitPathfinder(db_path: string);
var
    db, stmt: Pointer;
    pText: PAnsiChar;
    j, link_count: int32;
    start_point_id, end_point_id: int32;
    // ErrCode: int32;
    tmpLink: TLink;
    dbp: PAnsiChar;

    function check_DB_error(err_code: int32): boolean;
    begin
        Result := err_code = 0;
        if not Result then
            Log('������ PREPARE (��� ' + inttostr(err_code) + '): ' + UTF8ToString(sqlite3_errmsg(db)));
    end;

    procedure ExpandMicrocode(out mcode: TMicrocodeList; str: string; const start_point_id: int32);
    var
        sl: TStringList;
        actidx, l: int32;
        actname: string;
    begin
        mcode := nil;
        str := trim(str);
        if (str = '') then
            Exit;

        sl := TStringList.Create;
        try

            sl.Delimiter := ';';
            sl.StrictDelimiter := true;
            sl.DelimitedText := str;

            l := 1;
            SetLength(mcode, l);
            mcode[0][0] := actNpcSel;
            mcode[0][1] := StrToIntDef(sl.Values['npc_id'], 0);
            actidx := 0;
            while true do
            begin
                actname := 'act' + inttostr(actidx);
                if (sl.IndexOfName(actname) = -1) then
                    break;
                SetLength(mcode, l + 1);
                mcode[l][0] := actNpcDlg;
                mcode[l][1] := StrToIntDef(sl.Values[actname], 0);
                inc(actidx);
                inc(l);
            end;

            if (StrToIntDef(sl.Values['return'], 0) <> 0) then
            begin
                SetLength(mcode, l + 1);
                mcode[l][0] := actMove;
                mcode[l][1] := start_point_id;
            end;

        finally
            sl.free();
        end;
    end;

begin
    dbp := PAnsiChar(AnsiString(FullDbPath));

    SetLength(graph_points, 0);

    if not check_DB_error(sqlite3_open(dbp, db)) then
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

                    // ����������� ���� ������ �������:
                    tmpLink.ID := sqlite3_column_int(stmt, 0);
                    tmpLink.TargetID := sqlite3_column_int(stmt, 2);

                    // парсим ActionData из extra
                    // делаем для линка "микрокод" из экшенов
                    pText := sqlite3_column_text(stmt, 4);
                    ExpandMicrocode(tmpLink.ActionData, UTF8ToString(pText), tmpLink.ID);

                    tmpLink.Weight := sqlite3_column_int(stmt, 5); // ������ ��� ������� �� ������� extra

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
                Log('error while loading graph: ' + E.Message)
        end;
    finally
        sqlite3_close(db);
    end;

    SetLength(gScore, graph_points_count);
    SetLength(fScore, graph_points_count);
    SetLength(CameFrom, graph_points_count);

    SetLength(OpenSet, graph_points_count);

    SetLength(OpenSetIndex, graph_points_count);
end;

initialization

if FileExists(FullDbPath) then
begin
    InitPathfinder(PAnsiChar(AnsiString(FullDbPath)));
end else begin
    Log('Database not found: ' + FullDbPath);
end;

end.

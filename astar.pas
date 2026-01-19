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
function sqlite3_errmsg(db: Pointer): PAnsiChar; cdecl; external SQLiteDLL; // ��� ��������� ������

type

  TDoubleArray = array of Double; // ������ ��� �������� ����� � ������ (������ = ID �����)
  TIntArray = array of int32; // ������ ��� �������� "�������" (����� ������������ ����)

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

  TStep = record
    act, data0, data1, data2: int32;

    // procedure AssignFromPoint(const p: TPoint3D);    procedure AssignAction(const npc_id, a0, a1: int32);    procedure CopyTo(var aa, ax, ay, az: int32);
  end;

  TSteps = array of TStep;

  TPathInfo = record

    PointCount, ActionCount: int32;
    Distance: Double;

  end;

procedure Log(const Msg: string; const OID: int32 = 0);

implementation

var

  graph_points: array of TPoint3D;
  graph_points_count: int32;

  // function DoAStar(start_point, end_point: TPoint3D): int32;
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

procedure InitPathfinder(db_path: PAnsiChar);
var
  db, stmt: Pointer;
  pText: PAnsiChar;
  j, link_count: int32;
  start_point_id, end_point_id: int32;
  // ErrCode: int32;
  tmpLink: TLink;

  function check_DB_error(err_code: int32): boolean;
  begin
    Result := err_code = 0;
    if not Result then
      Log('������ PREPARE (��� ' + inttostr(err_code) + '): ' + UTF8ToString(sqlite3_errmsg(db)));
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

          // ����������� ���� ������ �������:
          tmpLink.ID := sqlite3_column_int(stmt, 0);
          tmpLink.TargetID := sqlite3_column_int(stmt, 2);

          pText := sqlite3_column_text(stmt, 4); // ������ ��� ������� �� ������� extra
          if pText <> nil then
            tmpLink.ActionData := UTF8ToString(pText)
          else
            tmpLink.ActionData := '';

          tmpLink.Weight := sqlite3_column_int(stmt, 5); // ������ ��� ������� �� ������� extra

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
        Log('����������� ������ ��� ��������: ' + E.Message)
    end;
  finally
    sqlite3_close(db);
  end;
end;

function TPoint3D.DistanceTo(const Other: TPoint3D): Double;
begin
  // ���������� ������� �������� � ����������� � Int64
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
  gScore, fScore: TDoubleArray; // ��������� ���� �� ������

  CameFrom: TIntArray; // ����� ���������

  LinkIndexesCount: int32;
  LinkIndexes: TIntArray;

  OpenSetCount: int32;
  OpenSet, OpenSetIndex: array of int32;
  start_point_id, end_point_id, Current, NeighborID, j: int32;
  TentativeG: Double;
  procedure Reset;
  var
    i: int32;
  begin
    PointCount := 0;
    ActionCount := 0;
    Distance := 0;
    TotalCost := 0;

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
      for j := 0 to Length(graph_points[start_pt].Links) - 1 do
        if graph_points[start_point_id].Links[j].TargetID = end_point_id then
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
        inc(Result.PointCount);
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

begin
  Result := 0;

  try
    start_point_id := FindNearestPoint(start_point);
    end_point_id := FindNearestPoint(end_point);

    if (start_point_id = -1) or (end_point_id = -1) then
    begin
      Log('������: ����� ������ ��� ������ �� ������� � ����.');
      Exit;
    end;

    Reset;

    OpenSetAdd(start_point_id);
    gScore[start_point_id] := 0;
    fScore[start_point_id] := graph_points[start_point_id].DistanceTo(graph_points[end_point_id]);

    while OpenSetCount > 0 do
    begin
      Current := GetLowestF();

      if Current = end_point_id then
      begin
        ReconstructPath(Current);
        Result := Length(FFinalPath);
        Log(Format('���� ������! �����: %d', [Result]));
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
          fScore[NeighborID] := TentativeG + graph_points[NeighborID].DistanceTo(graph_points[end_point_id]);

          OpenSetAdd(NeighborID);
        end;
      end;
    end;
    Log('��������: ���� �� ������ (���� ��������).', OID);

  except
    on E: Exception do
      Log('����������� ������ A*: ' + E.Message, OID);
  end;
end;

initialization

FullDbPath := 'C:\la_db\new.db3';

if FileExists(FullDbPath) then
begin
  InitPathfinder(PAnsiChar(AnsiString(FullDbPath)));
end else begin
  Log('Database not found: ' + FullDbPath);
end;

end.

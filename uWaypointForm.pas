unit uWaypointForm;

interface

uses
    Winapi.Windows, System.SysUtils, System.Classes, Vcl.Graphics,
    Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
    System.Generics.Collections, uPathfinder, System.IniFiles, System.Generics.Defaults,
    Vcl.Buttons;

type
    TWaypointForm = class(TForm)
        GroupBox1: TGroupBox;
        lvWaypoints: TListView;
        GroupBox2: TGroupBox;
        Memo1: TMemo;
        btCancel: TButton;
        btOk: TButton;
        Memo2: TMemo;
        BitBtn1: TBitBtn;
        procedure FormCreate(Sender: TObject);
        procedure lvWaypointsDblClick(Sender: TObject);
        procedure lvWaypointsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
        procedure btOkClick(Sender: TObject);
        procedure lvWaypointsAdvancedCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage; var DefaultDraw: Boolean);
        procedure FormShow(Sender: TObject);
        procedure BitBtn1Click(Sender: TObject);
        procedure RefreshList;
        procedure FormClose(Sender: TObject; var Action: TCloseAction);
    public

        pctx: PPathContext;
        character_pos, selected_point: TPoint3D;
    end;

var
    WaypointForm: TWaypointForm;

implementation

{$R *.dfm}

// 1. В FormCreate оставляем ТОЛЬКО заполнение списка
procedure TWaypointForm.FormClose(Sender: TObject; var Action: TCloseAction);
var
    Ini: TIniFile;
begin
    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    try
        Ini.WriteInteger('Window', 'Left', Self.Left);
        Ini.WriteInteger('Window', 'Top', Self.Top);
        Ini.WriteInteger('Window', 'Width', Self.Width);
        Ini.WriteInteger('Window', 'Height', Self.Height);
    finally
        Ini.Free;
    end;
end;

procedure TWaypointForm.FormCreate(Sender: TObject);
var
    SortedPoints: TList<TPoint3D>;
    P: TPoint3D;
    Item: TListItem;
    CurrentChar, FirstChar: Char;
    j: int32;
begin
    SortedPoints := TList<TPoint3D>.Create;
    try
        for j := 0 to graph_points_count - 1 do
        begin
            if graph_points[j].ID = -1 then
                Continue;
            if graph_points[j].name <> '' then
                SortedPoints.Add(graph_points[j]);
        end;

        SortedPoints.Sort(TComparer<TPoint3D>.Construct(
            function(const L, R: TPoint3D): Integer
            begin
                Result := CompareText(L.name, R.name);
            end));

        lvWaypoints.Items.BeginUpdate;
        try
            lvWaypoints.Items.Clear;
            CurrentChar := #0;
            for P in SortedPoints do
            begin
                FirstChar := UpCase(P.name[1]);
                if FirstChar <> CurrentChar then
                begin
                    CurrentChar := FirstChar;
                    Item := lvWaypoints.Items.Add;
                    Item.Caption := CurrentChar;
                    Item.Data := nil;
                end;
                Item := lvWaypoints.Items.Add;
                Item.Caption := P.name;
                Item.Data := Pointer(P.ID);
            end;
        finally
            lvWaypoints.Items.EndUpdate;
        end;
    finally
        SortedPoints.Free;
    end;
end;

// 2. Новая процедура FormShow - здесь магия восстановления
procedure TWaypointForm.FormShow(Sender: TObject);
var
    Ini: TIniFile;
    LastTarget: string;
    Item: TListItem;
    NearestID, i, link_count: Integer;
    P: TPoint3D;

    Dist: Double;
begin
    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    try
        // Восстанавливаем позицию и размер
        Self.Left := Ini.ReadInteger('Window', 'Left', Self.Left);
        Self.Top := Ini.ReadInteger('Window', 'Top', Self.Top);
        Self.Width := Ini.ReadInteger('Window', 'Width', Self.Width);
        Self.Height := Ini.ReadInteger('Window', 'Height', Self.Height);

        LastTarget := Ini.ReadString('Settings', 'LastTarget', '');
    finally
        Ini.Free;
    end;
    // 1. Ищем ближайшую точку к текущему положению
    NearestID := FindNearestPoint(character_pos);

    Memo2.Lines.BeginUpdate;
    try
        Memo2.Lines.Clear;
        if NearestID <> -1 then
        begin
            P := graph_points[NearestID];
            Dist := P.DistanceTo(character_pos);

            Memo2.Lines.Add(Format('Nearest point ID: %d', [NearestID]));
            Memo2.Lines.Add(Format('Distance: %.0f', [Dist]));
            Memo2.Lines.Add(Format('Pos: %d, %d, %d', [P.X, P.Y, P.Z]));

            link_count := length(graph_points[NearestID].Links);
            Memo2.Lines.Add(Format('Links count: %d', [link_count]));
            for i := 0 to link_count - 1 do
                Memo2.Lines.Add(Format('%d -> Link %d, Point %d, Dist: %f', [i, graph_points[NearestID].Links[i].ID, graph_points[NearestID].Links[i].TargetID, graph_points[NearestID].Links[i].Distance]));
        end
        else
            Memo2.Lines.Add('No points near');

        // Memo2.Lines.Add('-------------------');
        // Memo2.Lines.Add(''); // Отступ перед инфой о маршруте
    finally
        Memo2.Lines.EndUpdate;
    end;

    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    try
        LastTarget := Ini.ReadString('Settings', 'LastTarget', '');
    finally
        Ini.Free;
    end;

    if LastTarget <> '' then
    begin
        for i := 0 to lvWaypoints.Items.Count - 1 do
        begin
            Item := lvWaypoints.Items[i];
            if (Item.Data <> nil) and SameText(Item.Caption, LastTarget) then
            begin
                Item.Selected := True;
                Item.Focused := True;
                Item.MakeVisible(False); // Теперь точно прокрутит
                lvWaypointsSelectItem(lvWaypoints, Item, True); // Теперь координаты уже переданы!
                Break;
            end;
        end;
    end;
end;

procedure TWaypointForm.lvWaypointsAdvancedCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage; var DefaultDraw: Boolean);
begin
    if Item.Data = nil then
    begin
        // Это заголовок алфавита
        Sender.Canvas.Font.Color := clBlue;
        Sender.Canvas.Font.Style := [fsBold];
    end else begin
        // Это обычная точка
        Sender.Canvas.Font.Color := clWindowText;
        Sender.Canvas.Font.Style := [];
    end;
end;

procedure TWaypointForm.lvWaypointsDblClick(Sender: TObject);
begin
    btOkClick(nil);
end;

procedure TWaypointForm.BitBtn1Click(Sender: TObject);
begin

    InitPathfinder(PAnsiChar(AnsiString(FullDbPath)));

    // 2. Обновляем визуальный список в форме
    RefreshList;

    // ShowMessage('Граф успешно перечитан из базы!');
end;

procedure TWaypointForm.btOkClick(Sender: TObject);
var
    PointID: Integer;
    Ini: TIniFile;
begin
    if lvWaypoints.Selected <> nil then
    begin
        // Сохраняем имя выбранной точки в INI
        Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
        try
            Ini.WriteString('Settings', 'LastTarget', lvWaypoints.Selected.Caption);
        finally
            Ini.Free;
        end;
        PointID := Integer(lvWaypoints.Selected.Data);
        selected_point := graph_points[PointID];
        ModalResult := mrOk;
    end;

end;

{
  procedure TWaypointForm.lvWaypointsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
  var

  TargetID, StartID: Integer;
  TotalDist, DistToStart: Double;
  NodeCount, ActionCount, i: Integer;
  X1, Y1, Z1, X2, Y2, Z2, Act: Integer;
  begin
  if (not Selected) or (Item = nil) then
  Exit;

  // 1. Вытягиваем ID точки из Data
  TargetID := Integer(Item.Data);

  // 2. Считаем расстояние до ближайшей «входной» точки графа
  StartID := GPathfinder.FindNearestPoint(current_point);
  if StartID <> -1 then
  DistToStart := GPathfinder.FPoints[StartID].DistanceTo(current_point)
  else
  DistToStart := 0;

  // 3. Просим штурмана построить путь для анализа
  NodeCount := GPathfinder.CalculateAStar(current_point, GPathfinder.FPoints[TargetID]);

  TotalDist := 0;
  ActionCount := 0;

  if NodeCount > 0 then
  begin
  for i := 0 to NodeCount - 1 do
  begin
  if GPathfinder.GetNode(i,Act, X1, Y1, Z1 ) then
  begin
  if Act <> 0 then
  Inc(ActionCount); // Считаем действия (экшены)
  if i > 0 then
  begin
  // Суммируем расстояние между текущей и предыдущей точкой пути
  GPathfinder.GetNode(i - 1,Act, X2, Y2, Z2 );
  TotalDist := TotalDist + Sqrt(Sqr(Int64(X1) - X2) + Sqr(Int64(Y1) - Y2) + Sqr(Int64(Z1) - Z2));
  end;
  end;
  end;
  end;

  // 4. Вывод в Ваш Memo1
  Memo1.Lines.Clear;
  Memo1.Lines.Add(Format('Destination: %s', [Item.Caption]));
  Memo1.Lines.Add(Format('Total Path: %.0f units', [TotalDist]));
  Memo1.Lines.Add(Format('Nodes: %d (Actions: %d)', [NodeCount, ActionCount]));
  Memo1.Lines.Add(Format('Entry dist: %.0f units', [DistToStart]));

  if DistToStart > 1000 then
  Memo1.Lines.Add('!!! WARNING: Too far from entry point !!!');
  end;
}
procedure TWaypointForm.lvWaypointsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
    TargetID, StartID: Integer;
    // TotalDist,
    DistToStart: Double;
    i: Integer;

begin
    Memo1.Lines.BeginUpdate;
    try
        Memo1.Lines.Clear;
        if (not Selected) or (Item = nil) then
            Exit;
        if (Item.Data = nil) then
            Exit;

        // 1. Вытягиваем ID целевой точки
        TargetID := Integer(Item.Data);

        // 2. Считаем расстояние от текущего положения до входа в граф
        StartID := FindNearestPoint(character_pos);
        if StartID <> -1 then
            DistToStart := character_pos.DistanceTo(graph_points[StartID])
        else
        begin
            Memo1.Lines.Add('[lvWaypointsSelectItem] StartID = -1');
            Exit;
        end;

        // 3. Строим путь
        pctx^.DoAStar(graph_points[StartID], graph_points[TargetID]);

        // Вывод информации
        Memo1.Lines.Add('=== ROUTE INFO ===');
        Memo1.Lines.Add(Format('From ID: %d to ID: %d', [StartID, TargetID]));
        Memo1.Lines.Add('-------------------');
        Memo1.Lines.Add(Format('Physical Distance: %.0f units', [pctx^.Distance]));
        Memo1.Lines.Add(Format('Total Path Cost:   %.0f (inc. weights)', [pctx^.TotalCost]));
        Memo1.Lines.Add('-------------------');
        Memo1.Lines.Add(Format('Nodes in Path: %d', [pctx^.PointCount]));
        Memo1.Lines.Add(Format('Actions found: %d', [pctx^.ActionCount]));
        Memo1.Lines.Add(Format('Entry distance: %.0f units', [DistToStart]));

        // TotalDist := 0;

        // 4. Вывод в Ваш Memo1

        { Memo1.Lines.Add(Format('S %d E %d', [StartID, TargetID]));

          Memo1.Lines.Add(Format('Total Path: %.0f units', [pctx^.Distance]));
          Memo1.Lines.Add(Format('Nodes: %d (Actions: %d)', [pctx^.PointCount, pctx^.ActionCount]));
          Memo1.Lines.Add(Format('Entry dist: %.0f units', [DistToStart]));
        }
        if DistToStart > 1000 then
            Memo1.Lines.Add('!!! WARNING: Too far from entry point !!!');

    finally
        Memo1.Lines.EndUpdate;
    end;

end;

procedure TWaypointForm.RefreshList;
begin
    FormCreate(nil);
end;

end.

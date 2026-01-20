unit uWaypointForm;

interface

uses
    Winapi.Windows, System.SysUtils, System.Classes, Vcl.Graphics,
    Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
    System.Generics.Collections, uPathfinder, System.IniFiles, System.Generics.Defaults,
    Vcl.Buttons, astar, frame7Signs,
    frameClanBank, framePathInfo,
    Vcl.Themes, Vcl.Styles;

type
    TWaypointForm = class(TForm)
        GroupBox1: TGroupBox;
        lvWaypoints: TListView;
        frameContainer: TGroupBox;
        btCancel: TButton;
        btOk: TButton;
        BitBtn1: TBitBtn;
    Memo1: TMemo;
        procedure FormCreate(Sender: TObject);
        procedure lvWaypointsDblClick(Sender: TObject);
        procedure lvWaypointsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
        procedure btOkClick(Sender: TObject);
        procedure lvWaypointsAdvancedCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage; var DefaultDraw: Boolean);
        procedure FormShow(Sender: TObject);
        procedure BitBtn1Click(Sender: TObject);
        procedure RefreshList;
        procedure FormClose(Sender: TObject; var Action: TCloseAction);
        procedure FillPoints;
        procedure CreateFrames;
    public

        pctx: PPathContext;
        StartPos, selected_point: TPoint3D;
    end;

    TPredefinedAction = (paMove, pa7Signs, paClanBank);
    TBaseFrameClass = class of TFrame;

    TActionDef = record
        Action: TPredefinedAction;
        Caption: string;
        FrameClass: TBaseFrameClass;
        Instance: TFrame; // Ссылка на живой объект
    end;

var
    WaypointForm: TWaypointForm;
    // Наш реестр «умных» действий
    ActionDefs: array [0 .. 2] of TActionDef = ( //
        (
            Action: paMove; Caption: 'paMove'; FrameClass: TfrPathInfo), //
      (Action: pa7Signs; Caption: 'pa7Signs'; FrameClass: tfr7Signs), //
      (Action: paClanBank; Caption: 'paClanBank'; FrameClass: TfrClanBank));

implementation

{$R *.dfm}

procedure ApplyCarbonStyle;
begin
    try
        if TStyleManager.ActiveStyle.Name <> 'Carbon' then
        begin
            if not TStyleManager.TrySetStyle('Carbon') then
            begin
                // Если не вышло, можно оставить стандартный или выдать лог
            end;
        end;
    except
    end;
end;

procedure TWaypointForm.FormClose(Sender: TObject;

  var Action: TCloseAction);
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

procedure TWaypointForm.FillPoints;

var
    SortedPoints: TList<TPoint3D>;
    P: TPoint3D;
    Item: TListItem;
    CurrentChar, FirstChar: Char;
    j: int32;
    c: uint32;
begin

    SortedPoints := TList<TPoint3D>.Create;
    try
        for j := 0 to graph_points_count - 1 do
        begin
            if graph_points[j].ID = -1 then
                Continue;
            if graph_points[j].Name <> '' then
                SortedPoints.Add(graph_points[j]);
        end;

        SortedPoints.Sort(TComparer<TPoint3D>.Construct(
            function(const L, R: TPoint3D): Integer
            begin
                Result := CompareText(L.Name, R.Name);
            end));

        lvWaypoints.Items.BeginUpdate;
        try
            lvWaypoints.Items.Clear;

            // add predefined actions (7 signs etc)
            Item := lvWaypoints.Items.Add;
            Item.Caption := 'predefined actions';
            Item.Data := nil;

            for c := Low(ActionDefs) + 1 to High(ActionDefs) do
            begin
                Item := lvWaypoints.Items.Add;
                Item.Caption := ActionDefs[c].Caption;
                Item.Data := Pointer(c or $80000000);
            end;

            // add standard points
            CurrentChar := #0;
            for P in SortedPoints do
            begin
                FirstChar := UpCase(P.Name[1]);
                if FirstChar <> CurrentChar then
                begin
                    CurrentChar := FirstChar;
                    Item := lvWaypoints.Items.Add;
                    Item.Caption := CurrentChar;
                    Item.Data := nil;
                end;
                Item := lvWaypoints.Items.Add;
                Item.Caption := P.Name;
                Item.Data := Pointer(P.ID);
            end;
        finally
            lvWaypoints.Items.EndUpdate;
        end;
    finally
        SortedPoints.Free;
    end;
end;

procedure TWaypointForm.FormCreate(Sender: TObject);

begin
    ApplyCarbonStyle;
    FillPoints;
    CreateFrames;
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
    NearestID := FindNearestPoint(StartPos);

    { Memo2.Lines.BeginUpdate;
      try
      Memo2.Lines.Clear;
      if NearestID <> -1 then
      begin
      P := graph_points[NearestID];
      Dist := P.DistanceTo(StartPos);

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
      end; }

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

procedure TWaypointForm.lvWaypointsAdvancedCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; Stage: TCustomDrawStage;

var DefaultDraw: Boolean);
begin
    if Item.Data = nil then
    begin
        Sender.Canvas.Brush.Color := StyleServices.GetStyleColor(scListView);
        Sender.Canvas.FillRect(Item.DisplayRect(drBounds));
        // Это заголовок алфавита
        Sender.Canvas.Font.Color := $00BBFF;
        Sender.Canvas.Font.Style := [fsBold];
        Sender.Canvas.Font.Size := 11;
        Sender.Canvas.TextOut(Item.DisplayRect(drBounds).Left + 2, Item.DisplayRect(drBounds).Top - 2, Item.Caption);

        // Говорим системе, что мы сами всё нарисовали
        DefaultDraw := False;
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
    InitPathfinder(FullDbPath);
    RefreshList;
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

procedure TWaypointForm.CreateFrames;
var
    i: Integer;
begin
    for i := Low(ActionDefs) to High(ActionDefs) do
    begin
        // Создаем экземпляр фрейма по его классу
        ActionDefs[i].Instance := ActionDefs[i].FrameClass.Create(Self);
        with ActionDefs[i].Instance do
        begin
            Parent := frameContainer; // Сажаем на панель [cite: 3]
            Align := alClient;
            Visible := False; // Скрываем до поры до времени
        end;
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
    global_action_index, i: Integer;
    steps: TSteps;
    pi: TPathInfo;
    c: uint32;
begin
    if (not Selected) then
        Exit;

    // hide all frames
    for i := Low(ActionDefs) to High(ActionDefs) do
        if Assigned(ActionDefs[i].Instance) then
            ActionDefs[i].Instance.Visible := False;

    if (Item = nil) then
        Exit;
    if (Item.Data = nil) then
        Exit;

    c := uint32(Item.Data);
    if (c and $80000000) = 0 then
        global_action_index := 0
    else
        global_action_index := c and $7FFFFFFF;
    ActionDefs[global_action_index].Instance.Visible := True;

    if global_action_index = 0 then
//        with TfrPathInfo(ActionDefs[0].Instance).Memo1.Lines do
        with Memo1.Lines do
        begin
            // path info
            BeginUpdate;
            try
                StartID := FindNearestPoint(StartPos);
                TargetID := Integer(Item.Data);
                if StartID <> -1 then
                    DistToStart := StartPos.DistanceTo(graph_points[StartID])
                else
                begin
                    Add('[lvWaypointsSelectItem] StartID = -1');
                    Exit;
                end;

                setlength(steps, 0);
                pi := DoAStar(steps, graph_points[StartID], graph_points[TargetID]);

                Add('Текст для Барина');

            finally
                EndUpdate;
            end;
        end;
    {
      // 1. Вытягиваем ID целевой точки
      TargetID := Integer(Item.Data);

      // 2. Считаем расстояние от текущего положения до входа в граф
      StartID := FindNearestPoint(StartPos);
      if StartID <> -1 then
      DistToStart := StartPos.DistanceTo(graph_points[StartID])
      else
      begin
      Memo1.Lines.Add('[lvWaypointsSelectItem] StartID = -1');
      Exit;
      end;

      // 3. Строим путь
      setlength(steps, 0);
      pi := DoAStar(steps, graph_points[StartID], graph_points[TargetID]);

      // Вывод информации
      Memo1.Lines.Add('=== ROUTE INFO ===');
      Memo1.Lines.Add(Format('From ID: %d to ID: %d', [StartID, TargetID]));
      Memo1.Lines.Add('-------------------');
      Memo1.Lines.Add(Format('Physical Distance: %.0f units', [pi.Distance]));
      Memo1.Lines.Add(Format('Total Path Cost:   %.0f (inc. weights)', [pi.TotalCost]));
      Memo1.Lines.Add('-------------------');
      Memo1.Lines.Add(Format('Nodes in Path: %d', [pi.PointCount]));
      Memo1.Lines.Add(Format('Actions found: %d', [pi.ActionCount]));
      Memo1.Lines.Add(Format('Entry distance: %.0f units', [DistToStart]));

      // TotalDist := 0;

      // 4. Вывод в Ваш Memo1

      { Memo1.Lines.Add(Format('S %d E %d', [StartID, TargetID]));

      Memo1.Lines.Add(Format('Total Path: %.0f units', [pctx^.Distance]));
      Memo1.Lines.Add(Format('Nodes: %d (Actions: %d)', [pctx^.PointCount, pctx^.ActionCount]));
      Memo1.Lines.Add(Format('Entry dist: %.0f units', [DistToStart]));

      if DistToStart > 1000 then
      Memo1.Lines.Add('!!! WARNING: Too far from entry point !!!');
    }

end;

procedure TWaypointForm.RefreshList;
begin
    FillPoints;
end;

end.

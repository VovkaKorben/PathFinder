unit uWaypointForm;

interface

uses
    Winapi.Windows, System.SysUtils, System.Classes, Vcl.Graphics,
    Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
    System.Generics.Collections, uPathfinder, System.IniFiles, System.Generics.Defaults,
    Vcl.Buttons, astar,
    Vcl.Themes, Vcl.Styles, Vcl.ExtCtrls;

type
    TWaypointForm = class(TForm)
        GroupBox1: TGroupBox;
        lvWaypoints: TListView;
        frameContainer: TGroupBox;
        btCancel: TButton;
        btOk: TButton;
        BitBtn1: TBitBtn;
        pan7Signs: TPanel;
        panMove: TPanel;
        panClanbank: TPanel;
        Memo1: TMemo;
        CheckBox1: TCheckBox;
        CheckBox2: TCheckBox;
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
        // procedure CreateFrames;
    public

        pctx: PPathContext;
        StartPoint: TPoint3D;
    end;

    TPredefinedAction = (paMove, pa7Signs, paClanBank);

var
    WaypointForm: TWaypointForm;

    // Наш реестр «умных» действий
const
    ActionCaptions: array [0 .. 2] of string = ('paMove', 'pa7Signs', 'paClanBank');

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

procedure TWaypointForm.FillPoints;

var
    SortedPoints: TList<TPoint3D>;
    P: TPoint3D;
    Item: TListItem;
    CurrentChar, FirstChar: Char;
    j: int32;
    // c: uint32;
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

            for j := Low(ActionCaptions) + 1 to High(ActionCaptions) do
            begin
                Item := lvWaypoints.Items.Add;
                Item.Caption := ActionCaptions[j];
                Item.Data := Pointer(uint32(j) or $80000000);
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
var
    i: int32;
    Pnl: TPanel;
begin
    ApplyCarbonStyle;
    FillPoints;

    for i := 0 to frameContainer.ControlCount - 1 do
        if (frameContainer.Controls[i] is TPanel) then
        begin
            Pnl := TPanel(frameContainer.Controls[i]);

            Pnl.Visible := False;
            Pnl.Align := alClient;
            // Pnl.BevelOuter := bvNone;
            Pnl.Caption := ''; // Обязательно очищаем, чтобы текст панели не лез поверх чекбоксов

            // ИСПРАВЛЕНИЕ ДЛЯ СТИЛЯ CARBON:
            Pnl.ParentBackground := False; // Запрещаем панели "просвечивать" до самого GroupBox
            Pnl.DoubleBuffered := True;
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
    NearestID := FindNearestPoint(StartPoint);

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
    scenario_index, PointData, PointID: int32;
    Ini: TIniFile;

begin
    if lvWaypoints.Selected = nil then
        Exit;
    if lvWaypoints.Selected.Data = nil then
        Exit;

    PointData := uint32(lvWaypoints.Selected.Data);

    // Сохраняем сценарий для выбранной точки в INI
    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    try
        Ini.WriteInteger('Settings', 'LastTarget', PointData);
    finally
        Ini.Free;
    end;

    { if (PointData and $80000000) = 0 then
      scenario_index := 0
      else
      scenario_index := PointData and $7FFFFFFF;

      PointID := Integer(lvWaypoints.Selected.Data);
      selected_point := graph_points[PointID];
    }
    // генерируем сценарий
    // form itself - to read parameters,
    pctx.GenerateScenario(Self, PointData);
    ModalResult := mrOk;

end;

procedure TWaypointForm.lvWaypointsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
    TargetID, StartID: Integer;
    // TotalDist,
    DistToStart: Double;
    PointData, scenario_index, i: Integer;
    steps: TSteps;
    pi: TPathInfo;

begin
    if (not Selected) then
        Exit;
    if (Item = nil) then
        Exit;
    if (Item.Data = nil) then
        Exit;

    PointData := uint32(Item.Data);
    if (PointData and $80000000) = 0 then
        scenario_index := 0
    else
        scenario_index := PointData and $7FFFFFFF;

    for i := 0 to frameContainer.ControlCount - 1 do
        if frameContainer.Controls[i] is TPanel then
            frameContainer.Controls[i].Visible := (frameContainer.Controls[i].Tag = scenario_index);

    if scenario_index = 0 then
        with Memo1.Lines do
        begin
            // path info
            BeginUpdate;
            try
                Clear;
                StartID := FindNearestPoint(StartPoint);
                TargetID := Integer(Item.Data);
                if StartID <> -1 then
                    DistToStart := StartPoint.DistanceTo(graph_points[StartID])
                else
                begin
                    Add('[lvWaypointsSelectItem] StartID = -1');
                    Exit;
                end;

                setlength(steps, 0);
                pi := DoAStar(steps, graph_points[StartID], graph_points[TargetID]);

                Add('=== ROUTE INFO ===');
                Add(Format('From ID: %d to ID: %d', [StartID, TargetID]));
                Add('-------------------');
                Add(Format('Physical Distance: %.0f units', [pi.Distance]));
                if not FloatEqual(pi.TotalCost, pi.Distance) then
                    Add(Format('Total Path Cost:   %.0f (inc. weights)', [pi.TotalCost]));
                Add('-------------------');
                Add(Format('Nodes in Path: %d', [pi.PointCount]));
                Add(Format('Actions found: %d', [pi.ActionCount]));
                Add(Format('Entry distance: %.0f units', [DistToStart]));

            finally
                EndUpdate;
            end;
        end;

end;

procedure TWaypointForm.RefreshList;
begin
    FillPoints;
end;

end.

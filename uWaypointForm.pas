// https://github.com/VovkaKorben/PathFinder.git
unit uWaypointForm;

interface

uses
    Winapi.Windows, System.SysUtils, System.Classes, Vcl.Graphics,
    Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
    System.Generics.Collections, uPathfinder, System.IniFiles, System.Generics.Defaults,
    Vcl.Buttons, astar,
    Vcl.Themes, Vcl.Styles, Vcl.ExtCtrls, System.Variants,
    Vcl.Imaging.jpeg;

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
        Panel1: TPanel;
        Label1: TLabel;
        rbDawn: TRadioButton;
        rbDusk: TRadioButton;
        cbSeal1: TCheckBox;
        cbSeal2: TCheckBox;
        cbSeal3: TCheckBox;
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
        //        procedure ExtractParamsToContext();
        procedure FormDestroy(Sender: TObject);
    private
        FFormParams: TDictionary<string, Variant>;
        procedure SyncUI(ALoadToUI: Boolean);
        procedure LoadSettingsFromIni;
        procedure SaveSettingsToIni;
        procedure ApplyParamsToContext;
    public

        ctx: TPathContext;

    end;

    TPredefinedAction = (paMove, pa7Signs, paClanBank);

var
    WaypointForm: TWaypointForm;

    // Наш реестр «умных» действий
const
    ActionCaptions: array[0..2] of string = ('paMove', 'Seven Signs', 'Clan Warehouse');

implementation

{$R *.dfm}

procedure TWaypointForm.LoadSettingsFromIni;
var
    Ini: TIniFile;
    slKeys: TStringList;
    Key: string;
begin
    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    slKeys := TStringList.Create;
    try
        FFormParams.Clear;
        // Читаем все ключи из секции настроек контролов
        Ini.ReadSection('ControlSettings', slKeys);
        for Key in slKeys do
            FFormParams.AddOrSetValue(Key, Ini.ReadString('ControlSettings', Key, ''));
    finally
        slKeys.Free;
        Ini.Free;
    end;
end;

// 2. Сохранение из локального словаря в INI

procedure TWaypointForm.SaveSettingsToIni;
var
    Ini: TIniFile;
    Key: string;
begin
    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    try
        // Сохраняем контролы
        for Key in FFormParams.Keys do
            Ini.WriteString('ControlSettings', Key, VarToStr(FFormParams[Key]));

        // Сохраняем геометрию окна (перенесено из FormClose)
        Ini.WriteInteger('Window', 'Left', Self.Left);
        Ini.WriteInteger('Window', 'Top', Self.Top);
        Ini.WriteInteger('Window', 'Width', Self.Width);
        Ini.WriteInteger('Window', 'Height', Self.Height);

        // Сохраняем последнюю цель (если она выбрана)
        if lvWaypoints.Selected <> nil then
            Ini.WriteInteger('Settings', 'LastTarget', Integer(uint32(lvWaypoints.Selected.Data)));

    finally
        Ini.Free;
    end;
end;

// 3. Копирование черновика в основной контекст (Транзакция)

procedure TWaypointForm.ApplyParamsToContext;
var
    Pair: TPair<string, Variant>;
begin
    if ctx = nil then
        Exit;

    ctx.Params.Clear; // Очищаем старое
    for Pair in FFormParams do
    begin
        ctx.Params.Add(Pair.Key, Pair.Value); // Заливаем новое
    end;
end;

procedure TWaypointForm.SyncUI(ALoadToUI: Boolean);
var
    i, j: Integer;
    PanelCtrl, SubCtrl: TControl;
    Val: Variant;
begin
    // Бежим по панелям во frameContainer
    for i := 0 to frameContainer.ControlCount - 1 do
    begin
        PanelCtrl := frameContainer.Controls[i];
        if PanelCtrl is TPanel then
        begin
            for j := 0 to TPanel(PanelCtrl).ControlCount - 1 do
            begin
                SubCtrl := TPanel(PanelCtrl).Controls[j];
                if SubCtrl is TMemo then
                    Continue; // Мемо не трогаем

                if ALoadToUI then
                begin
                    // Из словаря -> на Экран [cite: 12]
                    if FFormParams.TryGetValue(SubCtrl.Name, Val) then
                    begin
                        if SubCtrl is TCheckBox then
                            TCheckBox(SubCtrl).Checked := Val
                        else if SubCtrl is TRadioButton then
                            TRadioButton(SubCtrl).Checked := Val
                        else if SubCtrl is TComboBox then
                            TComboBox(SubCtrl).ItemIndex := Val
                        else if SubCtrl is TEdit then
                            TEdit(SubCtrl).Text := Val;
                    end;
                end
                else
                begin
                    // С Экрана -> в словарь [cite: 12, 5]
                    if SubCtrl is TCheckBox then
                        FFormParams.AddOrSetValue(SubCtrl.Name, TCheckBox(SubCtrl).Checked)
                    else if SubCtrl is TRadioButton then
                        FFormParams.AddOrSetValue(SubCtrl.Name, TRadioButton(SubCtrl).Checked)
                    else if SubCtrl is TComboBox then
                        FFormParams.AddOrSetValue(SubCtrl.Name, TComboBox(SubCtrl).ItemIndex)
                    else if SubCtrl is TEdit then
                        FFormParams.AddOrSetValue(SubCtrl.Name, TEdit(SubCtrl).Text);
                end;
            end;
        end;
    end;
end;

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
//var    Ini: TIniFile;
begin
    SyncUI(False);
    SaveSettingsToIni; //  Запоминаем в INI

end;

procedure TWaypointForm.FillPoints;
var
    SortedPoints: TList<TPoint3D>;
    P: TPoint3D;
    Item: TListItem;
    CurrentChar, FirstChar: Char;
    CurrentCategory: string;
    j: int32;
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
                if (L.Category <> '') and (R.Category <> '') then
                begin
                    Result := CompareText(L.Category, R.Category);
                    if Result = 0 then
                    begin
                        Result := CompareText(L.Description, R.Description);
                        if Result = 0 then
                            Result := CompareText(L.Name, R.Name);
                    end;
                end
                else if L.Category <> '' then
                    Result := -1
                else if R.Category <> '' then
                    Result := 1
                else
                    Result := CompareText(L.Name, R.Name);
            end));

        lvWaypoints.Items.BeginUpdate;
        try
            lvWaypoints.Items.Clear;

            Item := lvWaypoints.Items.Add;
            Item.Caption := '***';
            Item.Data := nil;

            for j := Low(ActionCaptions) + 1 to High(ActionCaptions) do
            begin
                Item := lvWaypoints.Items.Add;
                Item.Caption := ActionCaptions[j];
                Item.Data := Pointer(uint32(j) or $80000000);
            end;

            CurrentChar := #0;
            CurrentCategory := '';

            for P in SortedPoints do
            begin
                if P.Category <> '' then
                begin
                    if CompareText(P.Category, CurrentCategory) <> 0 then
                    begin
                        CurrentCategory := P.Category;
                        Item := lvWaypoints.Items.Add;
                        Item.Caption := CurrentCategory;
                        Item.Data := nil;
                    end;
                    Item := lvWaypoints.Items.Add;
                    if P.Description <> '' then
                        Item.Caption := P.Name + ' (' + P.Description + ')'
                    else
                        Item.Caption := P.Name;
                    Item.Data := Pointer(P.ID);
                end
                else
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
                    if P.Description <> '' then
                        Item.Caption := P.Name + ' (' + P.Description + ')'
                    else
                        Item.Caption := format('%s #%d',[P.Name,p.id]);
                    Item.Data := Pointer(P.ID);
                end;
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
    FFormParams := TDictionary<string, Variant>.Create;
    Self.Icon.Handle := LoadIcon(HInstance, 'MAINICON');
    Self.Caption := Self.Caption + ' (' + FullDbPath + ')'; // <-- ДОБАВЛЕНО
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

procedure TWaypointForm.FormDestroy(Sender: TObject);
begin

    FFormParams.Free;
end;

// 2. Новая процедура FormShow - здесь магия восстановления

procedure TWaypointForm.FormShow(Sender: TObject);
var
    Ini: TIniFile;
    // LastTarget: string;
    LastTargetID: uint32;
    Item: TListItem;
    // NearestID,
    i: Integer;
    // P: TPoint3D;

    // Dist: Double;
begin
    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    try
        // Восстанавливаем позицию и размер
        Self.Left := Ini.ReadInteger('Window', 'Left', Self.Left);
        Self.Top := Ini.ReadInteger('Window', 'Top', Self.Top);
        Self.Width := Ini.ReadInteger('Window', 'Width', Self.Width);
        Self.Height := Ini.ReadInteger('Window', 'Height', Self.Height);
        LastTargetID := Cardinal(Ini.ReadInteger('Settings', 'LastTarget', 0));
    finally
        Ini.Free;
    end;

    LoadSettingsFromIni; //  Загружаем из файла в словарь
    SyncUI(True);

    if LastTargetID <> 0 then
    begin
        for i := 0 to lvWaypoints.Items.Count - 1 do
        begin
            Item := lvWaypoints.Items[i];
            if (Item.Data <> nil) and (uint32(Item.Data) = LastTargetID) then
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
    end
    else
    begin
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
    PointData: int32;
    Ini: TIniFile;

begin
    if lvWaypoints.Selected = nil then
        Exit;
    if lvWaypoints.Selected.Data = nil then
        Exit;

    PointData := uint32(lvWaypoints.Selected.Data);
    Ini := TIniFile.Create(ExtractFilePath(GetModuleName(HInstance)) + 'settings.ini');
    try
        Ini.WriteInteger('Settings', 'LastTarget', Integer(PointData));
    finally
        Ini.Free;
    end;

    SyncUI(False); //  Собираем всё с экрана в словарь

    ApplyParamsToContext; //  Выливаем в контекст DLL

    // put scenario to segments
    ctx.GenerateScenario(PointData);
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
    btOk.Enabled := False;
    if (not Selected) then
        Exit;
    if (Item = nil) then
        Exit;
    if (Item.Data = nil) then
        Exit;
    btOk.Enabled := True;
    PointData := uint32(Item.Data);
    if (PointData and $80000000) = 0 then
        scenario_index := 0
    else
        scenario_index := PointData and $7FFFFFFF;

    for i := 0 to frameContainer.ControlCount - 1 do
        if frameContainer.Controls[i] is TPanel then
            frameContainer.Controls[i].Visible := (frameContainer.Controls[i].Tag = scenario_index);

    if not Selected or (Item.Data = nil) or (uint32(Item.Data) >= $80000000) then
        Exit;

    //  P := graph_points[uint32(Item.Data)];

      //    if False then // temporary disable
    if scenario_index = 0 then
        with Memo1.Lines do
        begin
            // path info
            BeginUpdate;
            try
                Clear;
                StartID := FindNearestPoint(ctx.StartPoint);
                TargetID := Integer(Item.Data);
                if StartID <> -1 then
                    DistToStart := ctx.StartPoint.DistanceTo(graph_points[StartID])
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
                Add(Format('Distance: %s units', [FormatFloat('###,##0', pi.Distance)]));
                if not FloatEqual(pi.TotalCost, pi.Distance) then
                    Add(Format('Cost:   %.0f (inc. weights)', [pi.TotalCost]));
                Add('-------------------');
                Add(Format('Nodes: %d', [pi.PointCount]));
                if pi.ActionCount > 0 then
                    Add(Format('Actions: %d', [pi.ActionCount]));
                Add(Format('Entry distance: %s units', [FormatFloat('###,##0', DistToStart)]));

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


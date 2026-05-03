
unit uPathfinder;

interface

uses
    Windows, System.SysUtils, System.Classes, System.Generics.Collections,
    System.Math, System.Diagnostics, astar, AnsiStrings, vcl.forms,
    uConstants, System.SyncObjs, Vcl.Graphics;

const
    MAX_DLG_BUFFER = 16384;

type
    EPathException = class(Exception)
    public
        ErrorCode: integer;
        constructor Create(const Msg: string; ACode: integer);
    end;

    TPredefinedAction = (paMove, pa7Signs, paClanBank, paUnstuck);
    TSegmentAction = (saStop, saMoveTo, saMoving, saTest, //

        // 7 signs
        sa7S_Init, sa7S_Init2, sa7S_MoveToPriest, sa7S_GetDlg, sa7S_Analyze, sa7S_DoReg, sa7S_Already, sa7S_Error, sa7S_DoReg_Init,

        // warehouse
        saWH_Init_1, saWH_Init_2, saWH_ItemGet, saWH_Move, saWH_ItemLog, saWH_SelectNpc, saWH_ItemPut, saWH_OpenDlg, saWH_SendPacket,

        // unstuck
        saUnstuck
        );

    TInventoryItem = record
        id, oid, count: integer;

        constructor Create(aId, aCount, aOid: integer);
    end;

    TPathContext = class
    private
        OID: int32;

        FRecv1, FRecv2, FRecv3: int32;
        FOutputBuffer: array[0..MAX_DLG_BUFFER] of AnsiChar;

        FInventoryCount, FInventoryIndex: integer;
        FInventory: TList<TInventoryItem>;

        ssPriestIndex, whNpcIndex: integer;
        FUserLevel: integer;

        FGoalID: uint32;
        FSegments: TArray<TSegmentAction>; // заполняется при выборе в окне действия
        FSegmentIndex: int32; // текущий индекс сегмента
        FSteps: TSteps; // шаги из текущего сегмента, то самое, что длл отдает адрику один за одним
        FCurrentStep: int32; // индекс шажочка в FSteps

        procedure SetOutputText(const AText: string);
        procedure JumpTo(const Action: TSegmentAction);

    public
        StartPoint: TPoint3D;
        Params: TDictionary<string, variant>;

        procedure GenerateScenario(PointData: uint32);
        procedure GenerateSegment(const SegmentType: TSegmentAction);

        procedure GetText(AText: PAnsiChar);
        function SendStringAddr: PAnsiChar;
        procedure RecvInt(X, Y, Z: integer);
        function GetAction(var act, X, Y, Z: integer): boolean;
        constructor Create;
        destructor Destroy; override;
    end;

var

    Contexts: array of TPathContext;
    ContextGuard: TCriticalSection;

function GetContext(AOID: int32): TPathContext;
procedure Release(AOID: int32);
function GetNearestWHInfo(const CurrentPos: TPoint3D; var Name, Loc: string; var Dist: Double): Boolean;

implementation

type
    TPriestData = record
        Loc: string;
        NpcId: Int32;
        PriestType: Int32; // 0 - Dawn, 1 - Dusk
        Pos: TPoint3D;
    end;

    TWarehouseData = record
        Loc, name: string;
        NpcId: Int32;
        WhType: Int32;
        Pos: TPoint3D;
    end;

const
    { types
      1 taurin (depP/withP/depC/withC)
      2 valkon (depP/withP1/withP2/depC/withC1/withC2)
      3 pochi (P/C -> dep/with)
    }

    WAREHOUSE: array[0..26] of TWarehouseData =
        (
        // Gludin
        (Loc: 'Gludin'; name: 'Norman'; NpcId: 30210; WhType: 2; Pos: (X: - 81857; Y: 153545; Z: - 3171)), // gludio_npc1722_02001
        // Gludio
        (Loc: 'Gludio'; name: 'Haprock'; NpcId: 30255; WhType: 2; Pos: (X: - 13132; Y: 124988; Z: - 3118)), // gludio_npc1921_01901
        // Dion
        (Loc: 'Dion'; name: 'Holvas'; NpcId: 30058; WhType: 2; Pos: (X: 20750; Y: 144432; Z: - 3068)), // dion11_npc2022_0101
        //Giran
        (Loc: 'Giran'; name: 'Randolf'; NpcId: 30095; WhType: 2; Pos: (X: 82405; Y: 149905; Z: - 3520)), // giran11_npc2222_2801
        (Loc: 'Giran'; name: 'Collob'; NpcId: 30092; WhType: 2; Pos: (X: 79248; Y: 149552; Z: - 3531)), // giran11_npc2222_2701
        (Loc: 'Giran'; name: 'Taurin'; NpcId: 30086; WhType: 1; Pos: (X: 80752; Y: 146400; Z: - 3533)), // giran11_npc2222_2601
        (Loc: 'Giran'; name: 'Pochi'; NpcId: 30083; WhType: 3; Pos: (X: 80329; Y: 145482; Z: - 3533)), // giran11_npc2222_2501
        (Loc: 'Giran'; name: 'Valkon'; NpcId: 30103; WhType: 2; Pos: (X: 83264; Y: 146602; Z: - 3464)), // giran11_npc2222_0501
        // heine
        (Loc: 'Heine'; name: 'Mia'; NpcId: 30896; WhType: 3; Pos: (X: 109625; Y: 220238; Z: - 3520)), // innadril09_npc2324_0701
        // Oren
        (Loc: 'Oren'; name: 'Hagger'; NpcId: 30183; WhType: 2; Pos: (X: 81777; Y: 55123; Z: - 1508)), // oren17_npc2219_00901
        // Hunter
        (Loc: 'Hunter Village'; name: 'Sorint'; NpcId: 30232; WhType: 2; Pos: (X: 115271; Y: 76705; Z: - 2650)), // aden14_npc2320_10501
        // Aden
        (Loc: 'Aden'; name: 'Walderal'; NpcId: 30844; WhType: 2; Pos: (X: 148155; Y: 26254; Z: - 2217)), // aden13_npc2418_2401
        // Goddard
        (Loc: 'Goddard'; name: 'Lietta'; NpcId: 31267; WhType: 3; Pos: (X: 146440; Y: - 57500; Z: - 2965)), // godard02_npc2416_0401
        (Loc: 'Goddard'; name: 'Hakon'; NpcId: 31268; WhType: 3; Pos: (X: 146412; Y: - 57484; Z: - 2965)), // godard02_npc2416_0401
        // Rune
        (Loc: 'Rune'; name: 'Hugin'; NpcId: 31311; WhType: 3; Pos: (X: 43556; Y: - 48592; Z: - 800)), // rune02_npc2116_0401
        (Loc: 'Rune'; name: 'Durin'; NpcId: 31312; WhType: 3; Pos: (X: 43348; Y: - 48444; Z: - 800)), // rune02_npc2116_0401
        (Loc: 'Rune'; name: 'Lunin'; NpcId: 31313; WhType: 3; Pos: (X: 43308; Y: - 48444; Z: - 800)), // rune02_npc2116_0401
        // Schuttgart
        (Loc: 'Schuttgart'; name: 'Rydel'; NpcId: 31956; WhType: 3; Pos: (X: 88616; Y: - 141220; Z: - 1525)), // schuttgart20_npc2213_17m1
        (Loc: 'Schuttgart'; name: 'Cherbal'; NpcId: 31957; WhType: 3; Pos: (X: 88656; Y: - 141240; Z: - 1525)), // schuttgart20_npc2213_17m1

        // DE
        (Loc: 'Dark Elven'; name: 'Erviante'; NpcId: 30140; WhType: 2; Pos: (X: 13464; Y: 17751; Z: - 4541)), // oren09_npc2018_00401
        (Loc: 'Dark Elven'; name: 'Dorankus'; NpcId: 30139; WhType: 2; Pos: (X: 13380; Y: 17430; Z: - 4542)), // oren09_npc2018_00401
        // Elven
        (Loc: 'Elven'; name: 'Markius'; NpcId: 30153; WhType: 2; Pos: (X: 47780; Y: 49568; Z: - 2983)), // oren04_npc2119_00201
        (Loc: 'Elven'; name: 'Julia'; NpcId: 30152; WhType: 2; Pos: (X: 47912; Y: 50170; Z: - 2983)), // oren04_npc2119_00301
        // Dwarven
        (Loc: 'Dwarven'; name: 'Airy'; NpcId: 30522; WhType: 2; Pos: (X: 114832; Y: - 179520; Z: - 871)), // schuttgart_npc2312_02101
        // TI
        (Loc: 'Talking Island'; name: 'Wilford'; NpcId: 30005; WhType: 2; Pos: (X: - 81512; Y: 243424; Z: - 3720)), // gludio_npc1725_01101
        (Loc: 'Talking Island'; name: 'Rolfe'; NpcId: 30055; WhType: 2; Pos: (X: - 81840; Y: 243534; Z: - 3721)), // gludio_npc1725_01101

        // orc
        (Loc: 'Orc'; name: 'Grookin'; NpcId: 30562; WhType: 2; Pos: (X: - 43109; Y: - 113770; Z: - 221)) // lyonn_npc1814_00301
        );

    PRIESTS: array[0..21] of TPriestData = (//
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

constructor EPathException.Create(const Msg: string; ACode: integer);
begin
    inherited Create(Msg);
    ErrorCode := ACode;
end;

function StripHTML(const S: string): string;
var
    i: integer;
    Tag: boolean;
begin
    Result := '';
    Tag := false;
    for i := 1 to Length(S) do
    begin
        if S[i] = '<' then
        begin
            Tag := true
        end
        else if S[i] = '>' then
        begin
            Tag := false
        end
        else if not Tag then
        begin
            Result := Result + S[i]
        end;
    end;
    Result := Trim(Result);

end;

function FindNearestWH(const CurrentPos: TPoint3D): integer;
var
    i, start_id: integer;
    MinDist: double;
    steps: TSteps;
    pi: TPathInfo;
begin
    Result := -1;
    MinDist := 1E30;
    start_id := FindNearestPoint(CurrentPos);
    
    for i := Low(WAREHOUSE) to High(WAREHOUSE) do
    begin
        if start_id <> -1 then
        begin
            setlength(steps, 0);
            pi := DoAStar(steps, graph_points[start_id], WAREHOUSE[i].Pos);
            // If A* returns a distance of 0, check if we're already close
            if (pi.Distance > 0) or (CurrentPos.DistanceTo(WAREHOUSE[i].Pos) < 200) then
            begin
                if pi.Distance < MinDist then
                begin
                    MinDist := pi.Distance;
                    Result := i;
                end;
            end;
        end;
    end;
    
    // Fallback if A* fails for all or start point is invalid
    if Result = -1 then
    begin
        for i := Low(WAREHOUSE) to High(WAREHOUSE) do
        begin
            pi.Distance := CurrentPos.DistanceTo(WAREHOUSE[i].Pos);
            if pi.Distance < MinDist then
            begin
                MinDist := pi.Distance;
                Result := i;
            end;
        end;
    end;
end;

function GetNearestWHInfo(const CurrentPos: TPoint3D; var Name, Loc: string; var Dist: Double): Boolean;
var
    i, start_id: integer;
    steps: TSteps;
    pi: TPathInfo;
begin
    Result := False;
    i := FindNearestWH(CurrentPos);
    if i <> -1 then
    begin
        Name := WAREHOUSE[i].Name;
        Loc := WAREHOUSE[i].Loc;
        start_id := FindNearestPoint(CurrentPos);
        if start_id <> -1 then
        begin
            setlength(steps, 0);
            pi := DoAStar(steps, graph_points[start_id], WAREHOUSE[i].Pos);
            Dist := pi.Distance;
        end
        else
            Dist := CurrentPos.DistanceTo(WAREHOUSE[i].Pos);
        Result := True;
    end;
end;

function FindNearestPriest(const CurrentPos: TPoint3D; Side: integer): integer;
var
    i: integer;
    MinDist, D: double;
begin
    Result := -1;
    MinDist := 1E30;
    for i := Low(PRIESTS) to High(PRIESTS) do
    begin
        if PRIESTS[i].PriestType = Side then
        begin
            D := CurrentPos.DistanceTo(PRIESTS[i].Pos);
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
    Params := TDictionary<string, variant>.Create;
    FInventory := TList<TInventoryItem>.create;
end;

destructor TPathContext.Destroy;
begin
    FInventory.Free;
    Params.Free;
    inherited Destroy;
end;

procedure Release(AOID: int32);
var
    i, j: int32;
begin
    ContextGuard.Enter;
    try
        for i := 0 to High(Contexts) do
        begin
            if Contexts[i].OID = AOID then
            begin
                Contexts[i].Free;
                for j := i to High(Contexts) - 1 do
                begin
                    Contexts[j] := Contexts[j + 1]
                end;

                SetLength(Contexts, Length(Contexts) - 1);
                Exit;
            end;
        end;
    finally
        ContextGuard.Leave;
    end;
end;

function GetContext(AOID: int32): TPathContext;
var
    i: int32;
begin
    ContextGuard.Enter;
    try
        for i := 0 to High(Contexts) do
        begin
            if Contexts[i].OID = AOID then
            begin
                Result := Contexts[i];
                Exit;
            end
        end;
        Result := TPathContext.Create;
        Result.OID := AOID;

        SetLength(Contexts, Length(Contexts) + 1);
        Contexts[High(Contexts)] := Result;
    finally
        ContextGuard.Leave;
    end;
end;

procedure TPathContext.SetOutputText(const AText: string);
begin
    AnsiStrings.StrPLCopy(FOutputBuffer, ansistring(AText), MAX_DLG_BUFFER - 1);
end;

function TPathContext.GetAction(var act, X, Y, Z: integer): boolean;
begin
    while (FCurrentStep >= Length(FSteps)) do
    begin
        Inc(FSegmentIndex);
        // leave if scenario finished
        if (FSegmentIndex < 0) or (FSegmentIndex >= Length(FSegments)) then
        begin
            Exit(false)
        end;

        GenerateSegment(FSegments[FSegmentIndex]);
        FCurrentStep := 0;
    end;

    act := FSteps[FCurrentStep].act;
    X := FSteps[FCurrentStep].data0;
    Y := FSteps[FCurrentStep].data1;
    Z := FSteps[FCurrentStep].data2;
    if FSteps[FCurrentStep].str <> '' then
    begin
        SetOutputText(FSteps[FCurrentStep].str)
    end;

    inc(FCurrentStep);
    Result := true;
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

    function IntToHexLE(Value: int32): string;
    begin
        Result := IntToHex(byte(Value), 2) +
            IntToHex(byte(Value shr 8), 2) +
            IntToHex(byte(Value shr 16), 2) +
            IntToHex(byte(Value shr 24), 2);
    end;

    function createWarehousePacket(FInventory: TList<TInventoryItem>): string;
    var
        Item: TInventoryItem;
    begin
        result := '31'; // SendWareHouseDepositList
        result := result + IntToHexLE(FInventory.Count);
        for Item in FInventory do
        begin
            result := result + IntToHexLE(Item.oid);
            result := result + IntToHexLE(Item.Count);
        end;
    end;

var
    DlgRaw, tmpStr, ssName: string;
    StartPointID, tmp, ssSide: int32;
begin

    try
        case SegmentType of

            // ------------------------------------------------------------------------  SIMPLE MOVE
            saMoveTo:
                begin
                    SetLength(FSteps, 3);

                    FSteps[0].AssignMessage(graph_points[FGoalID].Name, msgMoveTo); // output goal name
                    FSteps[1].AssignInt(actFaceControl, 0, 0); // disable adr
                    FSteps[2].AssignInt(actSitStand, 1); // stand

                    StartPointID := FindNearestPoint(StartPoint);
                    if StartPointID = -1 then
                        raise Exception.Create('Start point not found');

                    DoAStar(FSteps, graph_points[StartPointID], graph_points[FGoalID]);
                end;
            // ------------------------------------------------------------------------ UNSTUCK
            saUnstuck:
                begin
                    SetLength(FSteps, 3);
                    FSteps[0].AssignInt(actFaceControl, 0, 0, 0);
                    FSteps[1].AssignInt(actSitStand, 1, 0, 0);
                    FSteps[2].AssignStr(actSay, '/unstuck');
                end;

            // ------------------------------------------------------------------------ WAREHOUSE
            saWH_Init_1:
                begin
                    SetLength(FSteps, 2);
                    FSteps[0].AssignInt(actFaceControl, 0, 0, 0); // disable
                    FSteps[1].AssignInt(actGetInventoryCount, 0, 0);
                end;

            saWH_Init_2:
                begin
                    // prepare to fill
                    FInventoryIndex := 0;
                    FInventoryCount := FRecv1;
                    FInventory.Clear;

                    // output count to user
                    SetLength(FSteps, 1);
                    FSteps[0].AssignMessage(Format('Items count: %d ', [FRecv1]), msgWarehouse);
                end;

            saWH_ItemGet:
                begin

                    // пока не получили всё, выдаем в скрипт индекс предмета
                    // иначе переходим на движение
                    if FInventoryIndex < FInventoryCount then
                    begin
                        SetLength(FSteps, 1);
                        FSteps[0].AssignInt(actGetInventoryByIndex, FInventoryIndex, 0, 0);
                    end
                    else
                    begin
                        JumpTo(saWH_Move)
                    end;
                end;

            saWH_ItemLog:
                begin
                    //                     id =  FRecv1, cnt = FRecv2, oid = FRecv3
                    SetLength(FSteps, 1);
                    tmpStr := Format('Item [%d/%d], id: %d, cnt: %d, oid: %d', [FInventoryIndex + 1, FInventoryCount, FRecv1, FRecv2, FRecv3]);
                    if allowDeposit.BinarySearch(FRecv1, tmp) then
                        tmpStr := '+ ' + tmpStr
                    else
                        tmpStr := '- ' + tmpStr;
                    FSteps[0].AssignMessage(tmpStr, msgWarehouse, $330033);
                end;

            saWH_ItemPut:
                begin
                    if allowDeposit.BinarySearch(FRecv1, tmp) then
                    begin

                        // clip adena to limit
                        if (FRecv1 = 57) then
                        begin
                            if Params.ContainsKey('edAdenaLimit') then
                                tmp := integer(Params['edAdenaLimit'])
                            else
                                tmp := 1000000;
                            FRecv2 := FRecv2 - min(FRecv2, tmp);
                        end;
                        if (FRecv2 > 0) then
                            FInventory.Add(TInventoryItem.Create(FRecv1, FRecv2, FRecv3));
                    end;
                    Inc(FInventoryIndex);
                    JumpTo(saWH_ItemGet);
                end;

            saWH_Move:
                begin
                    if FInventory.count = 0 then
                    begin
                        // store list empty
                        SetLength(FSteps, 2);
                        FSteps[0].AssignMessage('Nothing to store!', msgWarehouse, $11EE11);
                        FSteps[1].AssignInt(actStop);

                    end
                    else
                    begin
                        //
                        whNpcIndex := FindNearestWH(StartPoint);

                        SetLength(FSteps, 2);
                        FSteps[0].AssignMessage(Format('NPC: %s/%s, to store: %d', [WAREHOUSE[whNpcIndex].Loc, WAREHOUSE[whNpcIndex].Name, FInventory.Count]), msgWarehouse, $11EE11);
                        FSteps[1].AssignInt(actSitStand, 1);

                        if StartPoint.DistanceTo(WAREHOUSE[whNpcIndex].Pos) > 200 then
                        begin
                            StartPointID := FindNearestPoint(StartPoint);
                            if StartPointID = -1 then
                                raise EPathException.Create('Start point not found', msgWarehouse);

                            DoAStar(FSteps, graph_points[StartPointID], WAREHOUSE[whNpcIndex].Pos);
                        end;
                    end;
                end;
            saWH_SelectNpc:
                begin
                    SetLength(FSteps, 2);
                    FSteps[0].AssignInt(actNpcSel, WAREHOUSE[whNpcIndex].NpcId);

                    FSteps[1].AssignInt(actNpcDlg);
                end;
            saWH_OpenDlg:
                begin

                    { types
         1 taurin (depP/withP/depC/withC)
         2 valkon (depP/withP1/withP2/depC/withC1/withC2)
         3 pochi (P/C -> dep/with)
       }

                    case WAREHOUSE[whNpcIndex].WhType of
                        1:
                            begin
                                SetLength(FSteps, 1);
                                FSteps[0].AssignInt(actDlgSel, 3);

                            end;
                        2:
                            begin
                                SetLength(FSteps, 1);
                                FSteps[0].AssignInt(actDlgSel, 4);
                            end;
                        3:
                            begin
                                SetLength(FSteps, 2);
                                FSteps[0].AssignInt(actDlgSel, 2);
                                FSteps[1].AssignInt(actDlgSel, 1);
                            end;
                    else
                        raise EPathException.Create('Unknown warehouse type', msgWarehouse, $0000AA);
                    end;

                end;
            saWH_SendPacket:
                begin
                    tmpStr := createWarehousePacket(FInventory);
                    SetLength(FSteps, 2);
                    FSteps[0].AssignStr(actSendPacket, tmpStr);
                    FSteps[1].AssignMessage('Done!', msgWarehouse);
                end;

            // ------------------------------------------------------------------------ SEVEN SIGNS
            //
            sa7S_Init:
                begin
                    SetLength(FSteps, 2);
                    FSteps[0].AssignInt(actFaceControl, 0, 0); // disable adr
                    FSteps[1].AssignInt(actGetLevel); // get level
                end;

            sa7S_Init2:
                begin
                    FUserLevel := FRecv1;
                    if FUserLevel < 20 then
                    begin
                        SetLength(FSteps, 2);
                        FSteps[0].AssignMessage('Allowed if level>=20', msgSevenSigns, clRed);
                        FSteps[1].AssignInt(actStop);
                    end
                    else
                    begin

                        if Params.ContainsKey('rbDusk') and Params['rbDusk'] then
                        begin
                            ssSide := 1;
                            ssName := 'Dusk';
                        end
                        else
                        begin
                            ssSide := 0;
                            ssName := 'Dawn';
                        end;
                        ssPriestIndex := FindNearestPriest(StartPoint, ssSide);
                        if ssPriestIndex = -1 then
                            raise EPathException.Create('Priest not found!', msgSevenSigns);

                        SetLength(FSteps, 2);
                        FSteps[0].AssignInt(actSitStand, 1); // stand
                        FSteps[1].AssignMessage(Format('%s from %s', [ssName, PRIESTS[ssPriestIndex].Loc]), msgSevenSigns, $FF17E4);
                        if StartPoint.DistanceTo(PRIESTS[ssPriestIndex].Pos) > 200 then
                        begin
                            StartPointID := FindNearestPoint(StartPoint);
                            if StartPointID = -1 then
                                raise EPathException.Create('Start point not found', msgSevenSigns);

                            DoAStar(FSteps, graph_points[StartPointID], PRIESTS[ssPriestIndex].Pos);
                        end;

                    end;

                end;

            sa7S_GetDlg:
                begin
                    SetLength(FSteps, 3);
                    FSteps[0].AssignInt(actNpcSel, PRIESTS[ssPriestIndex].NpcId);
                    FSteps[1].AssignInt(actNpcDlg);
                    FSteps[2].AssignInt(actDlgTextToDLL);
                end;

            sa7S_Analyze:
                begin

                    DlgRaw := string(ansistring(FOutputBuffer));

                    if DlgRaw = '' then
                        JumpTo(sa7S_GetDlg)
                    else if Pos('Contributing', DlgRaw) > 0 then
                        JumpTo(sa7S_Already)
                    else if Pos('Participation', DlgRaw) > 0 then
                        JumpTo(sa7S_DoReg_Init)
                    else
                        JumpTo(sa7S_Error);
                end;

            sa7S_DoReg_Init:
                begin
                    // get user adena
                    SetLength(FSteps, 1);
                    FSteps[0].AssignInt(actGetInventoryByID, 57);
                end;

            sa7S_DoReg:
                begin
                    if (FUserLevel >= 40) and (FRecv1 < 50000) then
                    begin
                        SetLength(FSteps, 2);
                        FSteps[0].AssignMessage('Not enough adena!', msgSevenSigns, clRed);
                        FSteps[1].AssignInt(actStop);
                    end
                    else
                    begin
                        SetLength(FSteps, 5);
                        FSteps[0].AssignInt(actDlgSel, 4);
                        FSteps[1].AssignInt(actDlgSel, GetRandomSealIndex(boolean(Params['cbSeal1']), boolean(Params['cbSeal2']), boolean(Params['cbSeal3']))); // Печать
                        FSteps[2].AssignInt(actDlgSel, 1);
                        FSteps[3].AssignMessage('Registration done!', msgSevenSigns, $FF17E4);
                        FSteps[4].AssignInt(actStop);
                    end;
                end;

            sa7S_Already:
                begin
                    SetLength(FSteps, 2);
                    FSteps[0].AssignMessage('Already registered! Skipping...', msgSevenSigns,  $FF17E4);
                    FSteps[1].AssignInt(actStop);
                end;

            sa7S_Error:
                begin
                    SetLength(FSteps, 3);
                    FSteps[0].AssignMessage('Unknown dialog state!',msgSevenSigns, clRed);
                    FSteps[1].AssignMessage(StripHTML( string(ansistring(FOutputBuffer))), msgSevenSigns, $FF17E4);
                    FSteps[2].AssignInt(actStop);
                end;

        end;
    except
        on E: Exception do
        begin
            SetLength(FSteps, 2);
            if E is EPathException then
                FSteps[0].AssignMessage(E.Message, EPathException(E).ErrorCode, clRed)
            else
                FSteps[0].AssignMessage(E.Message, msgError, clRed);
            FSteps[1].AssignInt(actStop);
        end;

    end;

end;

procedure TPathContext.GenerateScenario(PointData: uint32);

    procedure FillScenario(const Actions: array of TSegmentAction);
    var
        i: integer;
    begin
        SetLength(FSegments, Length(Actions));
        for i := 0 to High(Actions) do
        begin
            FSegments[i] := Actions[i]
        end;

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
    begin
        case (FGoalID and $7FFFFFFF) of
            1: // Семь Печатей
                FillScenario([sa7S_Init, sa7S_Init2, sa7S_GetDlg, sa7S_Analyze, sa7S_DoReg_Init, sa7S_DoReg, sa7S_Already, sa7S_Error]);
            2: // WH
                FillScenario([saWH_Init_1, saWH_Init_2, saWH_ItemGet,
                    //saWH_ItemLog,
                    saWH_ItemPut, saWH_Move, saWH_SelectNpc, saWH_OpenDlg, saWH_SendPacket]);
            3: // unstuck
                FillScenario([saUnstuck]);
        end
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
    i: integer;
begin
    for i := 0 to High(FSegments) do
    begin
        if FSegments[i] = Action then
        begin
            FSegmentIndex := i;
            FCurrentStep := 0;
            GenerateSegment(FSegments[FSegmentIndex]);
            // Сразу заряжаем новые шаги
            Exit;
        end
    end;
end;

function TPathContext.SendStringAddr: PAnsiChar;
begin
    Result := @(FOutputBuffer[0]);
end;

procedure TPathContext.RecvInt(X, Y, Z: integer);
begin

    FRecv1 := X;
    FRecv2 := Y;
    FRecv3 := Z;
end;

{ TInventoryItem }

constructor TInventoryItem.Create(aId, aCount, aOid: integer);
begin
    Self.id := aId;
    Self.oid := aOid;
    Self.count := aCount;
end;

initialization
    ContextGuard := TCriticalSection.Create;

finalization
    ContextGuard.Free;
end.


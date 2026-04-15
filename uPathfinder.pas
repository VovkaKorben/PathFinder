

unit uPathfinder;

interface

uses
    Windows, System.SysUtils, System.Classes, System.Generics.Collections,
    System.Math, System.Diagnostics, astar, AnsiStrings, vcl.forms,
    uConstants, System.SyncObjs;

const
    MAX_DLG_BUFFER = 16384;

type
    TPredefinedAction = ( paMove, pa7Signs, paClanBank, paUnstuck );
    TSegmentAction = ( saStop, saMoveTo, saMoving, saTest, //
        sa7S_Init, sa7S_MoveToPriest, sa7S_GetDlg, sa7S_Echo, sa7S_Analyze,
        sa7S_DoReg,
        sa7S_Already, sa7S_Error, // 7 signs
        saWH_Init_1, saWH_Init_2, saWH_ItemGet, saWH_ItemLog, saWH_ItemPut,
        saWH_Move,
                          // warehouse
        saUnstuck
        );

    TInventoryItem = record
        id, oid, count: integer;
    end;

    TPathContext = class
    private
        OID: int32;

        FRecv1, FRecv2, FRecv3: int32;
        FOutputBuffer: array[0..MAX_DLG_BUFFER] of AnsiChar;

        FInventoryIndex: integer;
        FInventory: array of TInventoryItem;


        FGoalID: uint32;
        FSegments: TArray<TSegmentAction>;            // заполняется при выборе в окне действия
        FSegmentIndex: int32; // текущий индекс сегмента
        FSteps:  TSteps;            // шаги из текущего сегмента, то самое, что длл отдает адрику один за одним
        FCurrentStep: int32;  // индекс шажочка в FSteps

        procedure SetOutputText( const AText: string );
        procedure JumpTo( const Action: TSegmentAction );

    public
        StartPoint: TPoint3D;
        Params: TDictionary<string, variant>;

        procedure GenerateScenario( PointData: uint32 );
        procedure GenerateSegment( const SegmentType: TSegmentAction );

        procedure GetText( AText: PAnsiChar );
        function SendStringAddr: PAnsiChar;
        procedure RecvInt( X, Y, Z: integer );
        function GetAction( var act, X, Y, Z: integer ): boolean;
        constructor Create;
        destructor Destroy; override;
    end;

var

    Contexts: array of TPathContext;
    ContextGuard: TCriticalSection;

function GetContext( AOID: int32 ): TPathContext;
procedure Release( AOID: int32 );

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
    WAREHOUSE: array[0..32] of TWarehouseData =
        (
        ( Loc: 'gludio_npc1722_02001'; name: 'Norman'; NpcId: 30210; WhType: -1; Pos: ( X: -81857; Y: 153545; Z: -3171 ) ), // gludio_npc1722_02001
        ( Loc: 'gludio_npc1725_01101'; name: 'Wilford'; NpcId: 30005; WhType: -1; Pos: ( X: -81512; Y: 243424; Z: -3720 ) ), // gludio_npc1725_01101
        ( Loc: 'gludio_npc1725_01101'; name: 'Rant'; NpcId: 30054; WhType: -1; Pos: ( X: -81895; Y: 243917; Z: -3721 ) ), // gludio_npc1725_01101
        ( Loc: 'gludio_npc1725_01101'; name: 'Rolfe'; NpcId: 30055; WhType: -1; Pos: ( X: -81840; Y: 243534; Z: -3721 ) ), // gludio_npc1725_01101
        ( Loc: 'lyonn_npc1814_00301'; name: 'Grookin'; NpcId: 30562; WhType: -1; Pos: ( X: -43109; Y: -113770; Z: -221 ) ), // lyonn_npc1814_00301
        ( Loc: 'gludio_npc1921_01901'; name: 'Haprock'; NpcId: 30255; WhType: -1; Pos: ( X: -13132; Y: 124988; Z: -3118 ) ), // gludio_npc1921_01901
        ( Loc: 'oren09_npc2018_00401'; name: 'Erviante'; NpcId: 30140; WhType: -1; Pos: ( X: 13464; Y: 17751; Z: -4541 ) ), // oren09_npc2018_00401
        ( Loc: 'oren09_npc2018_00401'; name: 'Dorankus'; NpcId: 30139; WhType: -1; Pos: ( X: 13380; Y: 17430; Z: -4542 ) ), // oren09_npc2018_00401
        ( Loc: 'dion11_npc2022_0101'; name: 'Holvas'; NpcId: 30058; WhType: -1; Pos: ( X: 20750; Y: 144432; Z: -3068 ) ), // dion11_npc2022_0101
        ( Loc: 'dion10_npc2023_0101'; name: 'Sonin'; NpcId: 31773; WhType: -1; Pos: ( X: 17788; Y: 169842; Z: -3496 ) ), // dion10_npc2023_0101
        ( Loc: 'rune02_npc2116_0401'; name: 'Hugin'; NpcId: 31311; WhType: -1; Pos: ( X: 43556; Y: -48592; Z: -800 ) ), // rune02_npc2116_0401
        ( Loc: 'rune02_npc2116_0401'; name: 'Durin'; NpcId: 31312; WhType: -1; Pos: ( X: 43348; Y: -48444; Z: -800 ) ), // rune02_npc2116_0401
        ( Loc: 'rune02_npc2116_0401'; name: 'Lunin'; NpcId: 31313; WhType: -1; Pos: ( X: 43308; Y: -48444; Z: -800 ) ), // rune02_npc2116_0401
        ( Loc: 'oren04_npc2119_00201'; name: 'Markius'; NpcId: 30153; WhType: -1; Pos: ( X: 47780; Y: 49568; Z: -2983 ) ), // oren04_npc2119_00201
        ( Loc: 'oren04_npc2119_00301'; name: 'Julia'; NpcId: 30152; WhType: -1; Pos: ( X: 47912; Y: 50170; Z: -2983 ) ), // oren04_npc2119_00301
        ( Loc: 'schuttgart20_npc2213_17m1'; name: 'Rydel'; NpcId: 31956; WhType: -1; Pos: ( X: 88200; Y: -141384; Z: -1536 ) ), // schuttgart20_npc2213_17m1
        ( Loc: 'schuttgart13_npc2215_01m1'; name: 'Snoit'; NpcId: 31955; WhType: -1; Pos: ( X: 87240; Y: -141448; Z: -1536 ) ),  // schuttgart13_npc2215_01m1
        ( Loc: 'goddard02_npc2315_02m1'; name: 'Sandal'; NpcId: 31540; WhType: -1; Pos: ( X: 147552; Y: -56256; Z: -2776 ) ), // goddard02_npc2315_02m1
        ( Loc: 'goddard02_npc2315_02m1'; name: 'Conrad'; NpcId: 31539; WhType: -1; Pos: ( X: 147368; Y: -56168; Z: -2776 ) ), // goddard02_npc2315_02m1
        ( Loc: 'goddard02_npc2315_02m1'; name: 'Dewald'; NpcId: 31538; WhType: -1; Pos: ( X: 147320; Y: -56168; Z: -2776 ) ),// goddard02_npc2315_02m1
        ( Loc: 'giran05_npc2416_0201'; name: 'Kestor'; NpcId: 30181; WhType: -1; Pos: ( X: 80892; Y: 146608; Z: -3528 ) ), // giran05_npc2416_0201
        ( Loc: 'giran05_npc2416_0201'; name: 'Gesto'; NpcId: 30514; WhType: -1; Pos: ( X: 80920; Y: 146200; Z: -3528 ) ), // giran05_npc2416_0201
        ( Loc: 'giran05_npc2416_0201'; name: 'Nixie'; NpcId: 30515; WhType: -1; Pos: ( X: 80648; Y: 146312; Z: -3528 ) ), // giran05_npc2416_0201
        ( Loc: 'giran05_npc2416_0201'; name: 'Bebara'; NpcId: 30516; WhType: -1; Pos: ( X: 80600; Y: 146440; Z: -3528 ) ), // giran05_npc2416_0201
        ( Loc: 'aden10_npc2419_0101'; name: 'Donnal'; NpcId: 30626; WhType: -1; Pos: ( X: 146180; Y: 27124; Z: -2200 ) ), // aden10_npc2419_0101
        ( Loc: 'aden10_npc2419_0101'; name: 'Hofman'; NpcId: 30627; WhType: -1; Pos: ( X: 146132; Y: 27432; Z: -2200 ) ), // aden10_npc2419_0101
        ( Loc: 'aden10_npc2419_0101'; name: 'Carlyle'; NpcId: 30628; WhType: -1; Pos: ( X: 146392; Y: 27288; Z: -2200 ) ), // aden10_npc2419_0101
        ( Loc: 'innadril04_npc2520_0101'; name: 'Custo'; NpcId: 30869; WhType: -1; Pos: ( X: 111160; Y: 218968; Z: -3536 ) ), // innadril04_npc2520_0101
        ( Loc: 'innadril04_npc2520_0101'; name: 'Vatros'; NpcId: 30870; WhType: -1; Pos: ( X: 111304; Y: 219144; Z: -3536 ) ), // innadril04_npc2520_0101
        ( Loc: 'innadril04_npc2520_0101'; name: 'Hofner'; NpcId: 30871; WhType: -1; Pos: ( X: 111016; Y: 219144; Z: -3536 ) ), // innadril04_npc2520_0101
        ( Loc: 'oren09_npc2118_01m1'; name: 'Croop'; NpcId: 30147; WhType: -1; Pos: ( X: 82568; Y: 53128; Z: -1488 ) ), // oren09_npc2118_01m1
        ( Loc: 'oren09_npc2118_01m1'; name: 'Gudis'; NpcId: 30146; WhType: -1; Pos: ( X: 82632; Y: 52920; Z: -1488 ) ), // oren09_npc2118_01m1
        ( Loc: 'oren09_npc2118_01m1'; name: 'Moke'; NpcId: 30148; WhType: -1; Pos: ( X: 82840; Y: 53112; Z: -1488 ) ) // oren09_npc2118_01m1
        );


{var wh_list: array [0..18, 0..1] of integer = (
                (30086, 1), (30103, 2), (30083, 3), (30095, 2), // giran
                (31311, 3), (31312, 3), (31313, 0), // rune
                (30844, 2), (30183, 2), (30232, 2), // aden oren hunter
                (30058, 2), (31267, 3), (31268, 3),           // dion gdd gludio
                  (30255, 2), // gludio
                (30522, 2), // dwarven
                (31956, 3), // shutg
                (30896, 3), // heine
                 (30139, 2), // DE
                 (30153, 2) // elven}

    PRIESTS: array[0..21] of TPriestData = (//
        ( Loc: 'Gludin'; NpcId: 31078; PriestType: 0; Pos: ( X: -80555; Y: 150387; Z: -3040 ) ),
        ( Loc: 'Gludio'; NpcId: 31079; PriestType: 0; Pos: ( X: -13953; Y: 121454; Z: -2984 ) ),
        ( Loc: 'Dion'; NpcId: 31080; PriestType: 0; Pos: ( X: 16354; Y: 142870; Z: -2696 ) ),
        ( Loc: 'Giran'; NpcId: 31081; PriestType: 0; Pos: ( X: 83369; Y: 149273; Z: -3400 ) ),
        ( Loc: 'Innadril'; NpcId: 31082; PriestType: 0; Pos: ( X: 111386; Y: 220908; Z: -3544 ) ),
        ( Loc: 'Oren'; NpcId: 31083; PriestType: 0; Pos: ( X: 83106; Y: 54015; Z: -1488 ) ),
        ( Loc: 'Aden'; NpcId: 31084; PriestType: 0; Pos: ( X: 146983; Y: 26645; Z: -2200 ) ),
        ( Loc: 'Gludin'; NpcId: 31085; PriestType: 1; Pos: ( X: -82368; Y: 151618; Z: -3120 ) ),
        ( Loc: 'Gludio'; NpcId: 31086; PriestType: 1; Pos: ( X: -14748; Y: 124045; Z: -3112 ) ),
        ( Loc: 'Dion'; NpcId: 31087; PriestType: 1; Pos: ( X: 18482; Y: 144626; Z: -3056 ) ),
        ( Loc: 'Giran'; NpcId: 31088; PriestType: 1; Pos: ( X: 81623; Y: 148606; Z: -3464 ) ),
        ( Loc: 'Innadril'; NpcId: 31089; PriestType: 1; Pos: ( X: 112486; Y: 220173; Z: -3592 ) ),
        ( Loc: 'Oren'; NpcId: 31090; PriestType: 1; Pos: ( X: 82819; Y: 54657; Z: -1520 ) ),
        ( Loc: 'Aden'; NpcId: 31091; PriestType: 1; Pos: ( X: 147570; Y: 28927; Z: -2264 ) ),
        ( Loc: 'Hunters Village'; NpcId: 31168; PriestType: 0; Pos: ( X: 115136; Y: 74767; Z: -2608 ) ),
        ( Loc: 'Hunters Village'; NpcId: 31169; PriestType: 1; Pos: ( X: 116642; Y: 77560; Z: -2688 ) ),
        ( Loc: 'Godard'; NpcId: 31692; PriestType: 0; Pos: ( X: 148256; Y: -55504; Z: -2779 ) ),
        ( Loc: 'Godard'; NpcId: 31693; PriestType: 1; Pos: ( X: 149888; Y: -56624; Z: -2979 ) ),
        ( Loc: 'Rune'; NpcId: 31694; PriestType: 0; Pos: ( X: 45664; Y: -50368; Z: -800 ) ),
        ( Loc: 'Rune'; NpcId: 31695; PriestType: 1; Pos: ( X: 44528; Y: -48420; Z: -800 ) ),
        ( Loc: 'Schuttgart'; NpcId: 31997; PriestType: 0; Pos: ( X: 86816; Y: -143200; Z: -1341 ) ),
        ( Loc: 'Schuttgart'; NpcId: 31998; PriestType: 1; Pos: ( X: 85152; Y: -142112; Z: -1542 ) )
        );

function StripHTML( const S: string ): string;
var
    i: integer;
    Tag: boolean;
begin
    Result := '';
    Tag := false;
    for i := 1 to Length( S ) do
    begin
        if S [i] = '<' then
        begin
            Tag := true
        end else if S [i] = '>' then
        begin
            Tag := false
        end else if not Tag then
        begin
            Result := Result + S [i]
        end;
    end;
    Result := Trim( Result );

end;

function FindNearestWH( const CurrentPos: TPoint3D ): integer;
var
    i: integer;
    MinDist, D: double;
begin
    Result := -1;
    MinDist := 1E30;
    for i := Low( WAREHOUSE ) to High( WAREHOUSE ) do
    begin
        D := CurrentPos.DistanceTo( WAREHOUSE [i].Pos );
        if D < MinDist then
        begin
            MinDist := D;
            Result  := i;
        end;

    end;
end;

function FindNearestPriest( const CurrentPos: TPoint3D; Side: integer ): integer;
var
    i: integer;
    MinDist, D: double;
begin
    Result := -1;
    MinDist := 1E30;
    for i := Low( PRIESTS ) to High( PRIESTS ) do
    begin
        if PRIESTS [i].PriestType = Side then
        begin
            D := CurrentPos.DistanceTo( PRIESTS [i].Pos );
            if D < MinDist then
            begin
                MinDist := D;
                Result  := i;
            end;
        end;
    end;
end;


constructor TPathContext.Create;
begin
    Params := TDictionary<string, variant>.Create;
end;


destructor TPathContext.Destroy;
begin
    Params.Free;
    inherited Destroy;
end;

procedure Release( AOID: int32 );
var
    i, j: int32;
begin
    ContextGuard.Enter;
    try
        for i := 0 to High( Contexts ) do
        begin
            if Contexts [i].OID = AOID then
            begin
                Contexts[i].Free;
                for j := i to High( Contexts ) - 1 do
                begin
                    Contexts[j] := Contexts [j + 1]
                end;

                SetLength( Contexts, Length( Contexts ) - 1 );
                Exit;
            end;
        end;
    finally
        ContextGuard.Leave;
    end;
end;

function GetContext( AOID: int32 ): TPathContext;
var
    i: int32;
begin
    ContextGuard.Enter;
    try
        for i := 0 to High( Contexts ) do
        begin
            if Contexts [i].OID = AOID then
            begin
                Result := Contexts [i];
                Exit;
            end
        end;
        Result := TPathContext.Create;
        Result.OID := AOID;

        SetLength( Contexts, Length( Contexts ) + 1 );
        Contexts[High( Contexts )] := Result;
    finally
        ContextGuard.Leave;
    end;
end;

procedure TPathContext.SetOutputText( const AText: string );
begin
    AnsiStrings.StrPLCopy( FOutputBuffer, ansistring( AText ), MAX_DLG_BUFFER - 1 );
end;

function TPathContext.GetAction( var act, X, Y, Z: integer ): boolean;
begin
    while ( FCurrentStep >= Length( FSteps ) ) do
    begin
        Inc( FSegmentIndex );
                    // leave if scenario finished
        if ( FSegmentIndex < 0 ) or ( FSegmentIndex >= Length( FSegments ) ) then
        begin
            Exit( false )
        end;

        GenerateSegment( FSegments [FSegmentIndex] );
        FCurrentStep := 0;
    end;

    act := FSteps [FCurrentStep].act;
    X := FSteps [FCurrentStep].data0;
    Y := FSteps [FCurrentStep].data1;
    Z := FSteps [FCurrentStep].data2;
    if FSteps [FCurrentStep].str <> '' then
    begin
        SetOutputText( FSteps [FCurrentStep].str )
    end;

    inc( FCurrentStep );
    Result := true;
end;

procedure TPathContext.GenerateSegment( const SegmentType: TSegmentAction );

    function GetRandomSealIndex( s1, s2, s3: boolean ): int32;
    var
        a: TIntArray;
        c: int32;
    begin
        c := 0;
        if s1 then
        begin
            setlength( a, c + 1 );
            a[c] := 1;
            inc( c );
        end;
        if s2 then
        begin
            setlength( a, c + 1 );
            a[c] := 2;
            inc( c );
        end;
        if s3 then
        begin
            setlength( a, c + 1 );
            a[c] := 3;
        end;
        result := RandomFrom( a );
    end;

var
    DlgRaw: string;
    StartPointID, tmp: int32;
begin

    try
        case SegmentType of
            saMoveTo: begin
                SetLength( FSteps, 3 );

                FSteps[0].AssignStr( graph_points [FGoalID].Name );                            // output goal name
                FSteps[1].AssignInt( actFaceControl, 0, 0 ); // disable adr
                FSteps[2].AssignInt( actSitStand, 1 ); // stand

                StartPointID := FindNearestPoint( StartPoint );
                if StartPointID = -1 then
                begin
                    raise Exception.Create( 'Start point not found' )
                end;

                DoAStar( FSteps, graph_points [StartPointID], graph_points [FGoalID] );
            end;
            saUnstuck: begin
                SetLength( FSteps, 3 );
                FSteps[0].AssignInt( actFaceControl, 0, 0, 0 );
                FSteps[1].AssignInt( actSitStand, 1, 0, 0 );
                FSteps[2].AssignStr( '/unstuck', actSay );
            end;
            saWH_Init_1: begin
                tmp := FindNearestWH( StartPoint );
                SetLength( FSteps, 5 );
                FSteps[0].AssignInt( actFaceControl, 0, 0, 0 );
                FSteps[1].AssignInt( actSitStand, 1, 0, 0 );
                FSteps[2].AssignStr( Format( 'WH: %s / %s', [WAREHOUSE [tmp].name, WAREHOUSE [tmp].Loc] ) );
                FSteps[3].AssignStr( Format( 'Im at: %s', [StartPoint.ToString( false )] ) );
                FSteps[4].AssignInt( actGetInventoryCount, 0, 0 );

            end;

            saWH_Init_2: begin
                SetLength( FInventory, FRecv1 );
                FInventoryIndex := 0;
                SetLength( FSteps, 1 );
                FSteps[0].AssignStr( Format( 'Items count: %d ', [FRecv1] ) );
            end;

            saWH_ItemGet: begin


                                // пока не получили всё, выдаем в скрипт индекс предмета
                                // иначе переходим на движение
                if FInventoryIndex < Length( FInventory ) then
                begin
                    SetLength( FSteps, 1 );
                    FSteps[0].AssignInt( actGetInventoryItem,
                        FInventoryIndex, 0, 0 );
                end else begin
                    JumpTo( saWH_Move )
                end;
            end;
            saWH_ItemLog: begin
                SetLength( FSteps, 1 );
                FSteps[0].AssignStr( Format(

                    'Item [%d/%d], id: %d, cnt: %d, oid: %d'
                    , [
                    FInventoryIndex + 1, Length( FInventory
                    ), FRecv1, FRecv2,
                    FRecv3] ) );
            end;

            saWH_ItemPut: begin
                FInventory[FInventoryIndex].id := FRecv1;
                FInventory[FInventoryIndex].count := FRecv2;
                FInventory[FInventoryIndex].oid := FRecv3;
                SetLength( FSteps, 1 );

                Inc( FInventoryIndex );
                JumpTo( saWH_ItemGet );
            end;

            saWH_Move: begin
                SetLength( FSteps, 1 );
                FSteps[0].AssignStr( 'saWH_Move' );
            end;

            sa7S_Init: begin
                if Params.ContainsKey( 'rbDusk' ) and Params ['rbDusk'] then
                begin
                    Params.AddOrSetValue( 'ss_side', 1 );
                    Params.AddOrSetValue( 'ss_name', 'Dusk' );
                end else begin
                    Params.AddOrSetValue( 'ss_side', 0 );
                    Params.AddOrSetValue( 'ss_name', 'Down' );
                end;

                Params.AddOrSetValue( 'ss_priestindex', FindNearestPriest( StartPoint, int32( Params ['ss_side'] ) ) );
                if int32( Params ['ss_priestindex'] ) = -1 then
                    raise   Exception.Create( 'Жрец не найден!' );

                SetLength( FSteps, 1 );
                FSteps[0].AssignStr( Format( '7 Signs: %s from %s', [string( Params ['ss_name'] ), PRIESTS [int32( Params ['ss_priestindex'] )].Loc] ) );
            end;
            sa7S_MoveToPriest: begin
                SetLength( FSteps, 2 );
                FSteps[0].AssignInt( actFaceControl, 0, 0 );                                     // disable adr
                FSteps[1].AssignInt( actSitStand, 1 ); // stand

                if StartPoint.DistanceTo( PRIESTS [int32( Params ['ss_priestindex'] )].Pos ) > 200 then
                begin
                    StartPointID := FindNearestPoint(
                        StartPoint );
                    if StartPointID = -1 then

                        raise Exception.Create( 'Start point not found' );

                    DoAStar( FSteps, graph_points [StartPointID], PRIESTS [int32( Params ['ss_priestindex'] )].Pos );
                end;
            end;
            sa7S_GetDlg: begin
                SetLength( FSteps, 3 );
                FSteps[0].AssignInt( actNpcSel, PRIESTS [int32( Params ['ss_priestindex'] )].NpcId );
                FSteps[1].AssignInt( actNpcDlg );
                FSteps[2].AssignInt( actDlgTextToDLL );
            end;

            sa7S_Echo: begin
                SetLength( FSteps, 1 );
                FSteps[0].AssignStr( 'echo: ' + StripHTML( string( ansistring( FOutputBuffer ) ) ) );
            end;

            sa7S_Analyze: begin
                SetLength( FSteps, 0 );
                DlgRaw := string( ansistring( FOutputBuffer ) );

                if DlgRaw = '' then
                begin
                                        // Может, просто подождем или попробуем еще раз?
                    JumpTo( sa7S_GetDlg );
                    Exit;
                end;
                if Pos( 'Contributing', DlgRaw ) > 0 then
                begin
                    JumpTo( sa7S_Already )
                end else if Pos( 'Participation', DlgRaw ) > 0 then
                begin
                    JumpTo( sa7S_DoReg )
                end else begin
                    JumpTo( sa7S_Error )
                end;
            end;
            sa7S_DoReg: begin

                SetLength( FSteps, 4 );
                FSteps[0].AssignInt( actDlgSel, 4 );
                FSteps[1].AssignInt( actDlgSel, GetRandomSealIndex( boolean( Params ['cbSeal1'] ), boolean( Params ['cbSeal2'] ), boolean( Params ['cbSeal3'] ) ) );                              // Печать
                FSteps[2].AssignInt( actDlgSel, 1 );
                FSteps[3].AssignStr( 'Registration done!' );
            end;
            sa7S_Already: begin
                SetLength( FSteps, 2 );
                FSteps[0].AssignStr( 'Already registered! Skipping...' );
                FSteps[1].AssignInt( actStop );


                                // Здесь можно добавить JumpTo(saStop) или что-то еще
            end;
            sa7S_Error: begin
                SetLength( FSteps, 2 );
                FSteps[0].AssignStr( 'Unknown dialog state!' );
                FSteps[1].AssignInt( actStop );
            end;

        end;
    except
        on E: Exception do
        begin

            SetLength( FSteps, 2 );
            FSteps[0].AssignStr( 'Error: ' + E.Message );
            FSteps[1].AssignInt( actStop );
        end;
    end;

end;

procedure TPathContext.GenerateScenario( PointData: uint32 );

    procedure FillScenario( const Actions: array of TSegmentAction );
    var
        i: integer;
    begin
        SetLength( FSegments, Length( Actions ) );
        for i := 0 to High( Actions ) do
        begin
            FSegments[i] := Actions [i]
        end;

        FSegmentIndex := 0;
        FCurrentStep  := 0;
        SetLength( FSteps, 0 ); // Сбрасываем микро-шаги
    end;

begin
    FGoalID := PointData;
    if ( FGoalID and $80000000 ) = 0 then
    begin
        FillScenario( [saMoveTo] );
            // simple moveto
            //        SetLength(FSegments, 1);        FSegments[0] := saMoveTo;

    end else begin
        case ( FGoalID and $7FFFFFFF ) of
            1:     // Семь Печатей
            begin
                     // Если rbDusk нажат - сторона 1, иначе 0 (Dawn)


                     //                    FillScenario([sa7S_Init, sa7S_MoveToPriest, sa7S_GetDlg, sa7S_Echo, sa7S_Analyze, sa7S_DoReg]);
                FillScenario( [sa7S_Init, sa7S_MoveToPriest, sa7S_GetDlg, sa7S_Echo,
                    sa7S_Analyze,
                    sa7S_DoReg, sa7S_Already, sa7S_Error] );
            end;
            2:     // WH
            begin

                FillScenario( [saWH_Init_1, saWH_Init_2, saWH_ItemGet, saWH_ItemLog, saWH_ItemPut, saWH_Move] );

            end;
            3:     // unstuck
            begin
                FillScenario( [saUnstuck] );
            end;
        end
    end;


    // КЛЮЧЕВОЙ МОМЕНТ:
    FSegmentIndex := -1; // Указываем, что мы еще не начали
    FCurrentStep  := 0;
    SetLength( FSteps, 0 );

end;

procedure TPathContext.GetText( AText: PAnsiChar );
begin
    if ( AText <> nil ) then
        AnsiStrings.StrLCopy( FOutputBuffer, AText, MAX_DLG_BUFFER - 1 )
    else
        FOutputBuffer[0] := #0;
end;

procedure TPathContext.JumpTo( const Action: TSegmentAction );
var
    i: integer;
begin
    for i := 0 to High( FSegments ) do
    begin
        if FSegments [i] = Action then
        begin
            FSegmentIndex := i;
            FCurrentStep  := 0;
            GenerateSegment( FSegments [FSegmentIndex] );
                // Сразу заряжаем новые шаги
            Exit;
        end
    end;
end;

function TPathContext.SendStringAddr: PAnsiChar;
begin
    Result := @( FOutputBuffer [0] );
end;

procedure TPathContext.RecvInt( X, Y, Z: integer );
begin

    FRecv1 := X;
    FRecv2 := Y;
    FRecv3 := Z;
end;

initialization
    ContextGuard := TCriticalSection.Create;

finalization
    ContextGuard.Free;
end.
unit uPathfinder;

interface

uses
  Windows, System.SysUtils, System.Classes, System.Generics.Collections, System.Math, System.Diagnostics, astar;

const

  MAX_DLG_BUFFER = 16384;

type

  TSegmentAction = (saStop, saMoving, saParsing);
  TBufferState = (bsIdle, bsWaiting, bsReady);

  

  PPathContext = ^TPathContext; // ��������� ��� �������� ������

  TPathContext = record
  private
    OID: int32;

    FRecv1, FRecv2, FRecv3: int32;
    FWaitState: TBufferState; // ���������: 0 - ����, 31 - ��� ������

    FSteps: TSteps; // ������ ����� ���������� ��������
    FLastResponse, FOutputBuffer: array [0 .. MAX_DLG_BUFFER] of AnsiChar;

    FCurrentStep: int32;
    procedure SetOutputText(const AText: string);

    procedure Init;
    procedure Reset;

  public
    PointCount, ActionCount: int32;
    Distance, TotalCost: Double;

    function GetNode(const Index: int32; var act, X, Y, Z: int32): boolean;

    procedure GetText(AText: PAnsiChar);
    function SendStringAddr: PAnsiChar;
    procedure RecvInt(X, Y, Z: Integer);
    function GetAction(var act, X, Y, Z: Integer): boolean;
  end;

var

  Contexts: array of PPathContext;

function GetContext(AOID: int32): PPathContext;
function FindNearestPoint(const p: TPoint3D): int32;
procedure Release(AOID: int32);
procedure InitPathfinder(db_path: PAnsiChar); // ��������� ��������� ����

var
  FullDbPath: string; // ��������� ���������� ���� � ���������

implementation

{ uPathfinder.pas }
{
  function TPathContext.GenerateNextSegment: boolean;
  begin
  Result := True;
  SetLength(FFinalPath, 0); // ������ ������ ����� �������� ����� ��������� ������

  case FQuestGoal of

  // --- �������� 1: ����������� � 7 ������� ---
  qg7SignsReg:
  case FSegmentState of

  saIdle: // ��� 1: ����� ����� �� NPC
  begin
  AddSegment_Move(TargetNPC_Pos); // ��������� ����� "����"
  FSegmentState := saMoving; // ��������� ��� ������ ��� � ������ ��������
  end;

  saMoving: // ��� 2: ������, ���� ����������
  begin
  AddSegment_Talk(TargetNPC_ID); // ��������� ����� "��������"
  FSegmentState := saTalking;
  FWaitState := stWaiting; // DLL ��������, ��� HTML �� �������
  end;

  saParsing: // ��� 3: ����������� ��, ��� ������� ������
  begin
  if AnalyzeHTML('Already Registered') then
  AddSegment_Message('Master, you are already in!') // ����� "���������"
  else
  AddSegment_Click(Bypass_Reg); // ����� "���� �� ������"

  FSegmentState := saFinished;
  end;
  end;

  // --- �������� 2: ������ ����� (��������, ������ ���������) ---
  qgWarehouse:
  // ��� ����� ����� �� ���������, �� �� ������ "��������"
  // ��������: AddSegment_Move(Warehouse_Pos) -> AddSegment_Talk -> saParsing (����� ����)
  end;

  FCurrentStep := 0; // �������� ��������� ���������������� ������� � ������
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

// ���������� �������: ����� �������� ��� ������� �����
function GetContext(AOID: int32): PPathContext;
var
  i: int32;
begin
  Result := nil;

  // 1. ����, ��� �� ��� ������ ID � ������
  for i := 0 to High(Contexts) do
    if Contexts[i]^.OID = AOID then
    begin
      Result := Contexts[i];
      Exit;
    end;

  // 2. ���� �� ����� � ������� ����� ���� ������
  GetMem(Result, SizeOf(TPathContext));
  FillChar(Result^, SizeOf(TPathContext), 0); // �������� ��

  Result^.OID := AOID;
  Result^.Init;

  // ��������� ��������� � ��� ����� ������
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
  Result := True;

  if FWaitState = bsWaiting then
  begin
    act := 80; // ������� Delay
    X := 100;
    Exit;
  end;

  { 2. ���� ������ ������ (stReady), ���������� ���� � ��� ������ }
  if FWaitState = bsReady then
    FWaitState := bsIdle;

  { 3. �������� ������������������ (��� ������ FFinalPath) }
  case FCurrentStep of
    0:
      begin // ���� ������
        act := 5;
        SetOutputText('DLL: Link test started...'); // ����� ������ � FOutputBuffer
      end;

    1:
      begin // ���� ����� ������ (C -> S)
        act := 31; // ������ ������ �������� DlgText
        FWaitState := bsWaiting;
      end;

    2:
      begin // ���� �������� ������ (S -> C)
        act := 5;
        { ���� ��, ��� ������ ������� �� ���� 1, � ����� ������� ��� Print }
        // SetOutputText('DLL ��������: ' + string(FLastResponse));
        // SetOutputText('DLL ��������: ' + UTF8ToString(PAnsiChar(@FLastResponse[0])));
        // SetOutputText('DLL received HTML. Length: ' + IntToStr(Length(string(FLastResponse))));
        SetOutputText('DLL received HTML. Length: ' + inttostr(Length(string(FLastResponse))));

      end;

    3:
      begin // ���� ����� (C -> S)
        act := 40; // ��������, 40 - ��� ���� �������� ������� �� �����
        FWaitState := bsWaiting;
      end;

    4:
      begin // ���� ������ ���������� �����
        act := 5;

        SetOutputText('Numbers from script: ' + inttostr(FRecv1) + ', ' + inttostr(FRecv2));
      end;

    5:
      begin // ����������
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
    FLastResponse[0] := #0; // ���� ������ nil, ������ �������� �����

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

Uses PacketUnit, SysUtils, Classes, l2types;
{ types
  1 taurin (depP/withP/depC/withC)
  2 valkon (depP/withP1/withP2/depC/withC1/withC2)
  3 pochi (P/C -> dep/with)
}

var
    wh_list: array [0 .. 18, 0 .. 1] of integer = ((30086, 1), (30103, 2), (30083, 3), (30095, 2), // giran
      (31311, 3), (31312, 3), (31313, 0), // rune
      (30844, 2), (30183, 2), (30232, 2), // aden oren hunter
      (30058, 2), (31267, 3), (31268, 3), // dion gdd gludio
      (30255, 2), // gludio
      (30522, 2), // dwarven
      (31956, 3), // shutg
      (30896, 3), // heine
      (30139, 2), // DE
      (30153, 2) // elven
      );

const
    ADENA_LIMIT = 1000000;
    ADENA_ID = 57;
    DLG_DELAY = 500;

function GetNearestWH(): int32;
var
    wh_it, npc_it: int32;
    l2npc: TL2NPC;
    best_dist, dist: int32;
begin
    result := -1;
    for npc_it := 0 to NpcList.Count - 1 do
    begin
        for wh_it := low(wh_list) to high(wh_list) do
        begin
            if (NpcList(npc_it).id = wh_list[wh_it, 0]) then
            begin
                dist := User.DistTo(NpcList(npc_it));
                if result = -1 then
                begin
                    result := wh_it;
                    best_dist := User.DistTo(NpcList(npc_it));
                end
                else if dist < best_dist then
                begin
                    result := wh_it;
                    best_dist := dist;
                end;
            end
        end
    end;
end;

procedure LogMessage(v: String);
var
    filename: string;
    sl: TStringList;
begin
    filename := Script.Path + 'test.txt';
    sl := TStringList.Create;
    Try
        If fileexists(filename) Then
        begin
            sl.loadfromfile(filename)
        end;
        sl.Add(format('[%s] %s', [FormatDateTime('nn:ss:zzz', Now), v]));
        sl.SaveToFile(filename);

    Finally
        sl.free;
    end;
end;

procedure InitWh(wh_index: int32);
// var dlg_index:int32;
begin
    Engine.SetTarget(wh_list[wh_index, 0]);
    Print(format('Warehouse NPC: %s', [user.target.name]));
    Engine.MoveTo(user.target);
    delay(DLG_DELAY);
    Engine.DlgOpen;
    delay(DLG_DELAY);
    case (wh_list[wh_index, 1]) of
        1:
            begin // all items without selection
                Engine.DlgSel(3);
                delay(DLG_DELAY);
            end;
        2:
            begin // all items WITH selection
                Engine.DlgSel(4);
                delay(DLG_DELAY);
            end;
        3:
            begin // first destination, then operation
                Engine.DlgSel(2);
                delay(DLG_DELAY);
                Engine.DlgSel(1);
                delay(DLG_DELAY);
            end;
    else
        begin
            print('Unknown WH type');
            script.stop();
        end;
    end;
end;

procedure InspectInv(var inv_collect: TKeyList);
var
    allowedID: TIntList;
    j, cnt: int32;
begin
    allowedID := TIntList.Create;
    try
        allowedID.LoadFromFile(Script.Path + 'depositID');
        print(format('Loaded %d items', [allowedID.count]));

        for j := 0 to Inventory.User.Count - 1 do
        begin
            if allowedID.find(Inventory.User.Items(j).id) <> -1 then
            begin
                cnt := Inventory.User.Items(j).count;
                if Inventory.User.Items(j).id = ADENA_ID then
                begin
                    cnt := cnt - min(cnt, adena_limit)
                end;
                if cnt > 0 then
                begin
                    // print (format ('ID: %d, %s: %spcs',[Inventory.User.Items(j).id, get_item_name(Inventory.User.Items(j).id), formatfloat( '###,###,###,##0', cnt ) ]));
                    inv_collect[Inventory.User.Items(j).oid] := cnt;
                end;
            end;
        end;

    finally
        allowedID.free;
    end;
end;

procedure SaveInv(const inv_collect: TKeyList);
var
    Pck: TNetworkPacket;
    j: int32;
begin
    // send packet with id/count
    pck := TNetworkPacket.Create;
    try
        pck.WriteC($31); // SendWareHouseDepositList
        pck.WriteD(inv_collect.count);
        for j := 0 to inv_collect.Count - 1 do
        begin
            pck.WriteD(inv_collect.KeyByIndex(j));
            pck.WriteD(inv_collect.ValueByIndex(j));
        end;
        Engine.bypasstoserver('SendToServer ' + Pck.tohex);
        // Engine.SendToServer(Pck.ToHex); // send formatted to HEX packet to the server
    finally
        Pck.Free;
    end;
    {
      Uses PacketUnit, SysUtils;
      var Pck: TNetworkPacket;
      begin
      Pck:= TNetworkPacket.Create;

      Pck.WriteC($38);   //ID
      
      Pck.WriteS('Hello World');
      Pck.WriteD(0);
      Engine.bypasstoserver('SendToServer '+Pck.tohex); 
      Pck.Free;
    }
end;

procedure main();
var
    inv_collect: TKeyList;

    wh_index: int32;
begin

    Engine.FaceControl(0, false); // disable
    if (User.Sitting) then
    begin
        Engine.Stand
    end; // stand

    if (user.ClanID = 0) then
    begin
        print('Character not in clan. Stopped.');
        script.stop();
    end;

    inv_collect := TKeyList.Create;

    try
        wh_index := GetNearestWH();
        if wh_index = -1 then
        begin
            print('None known WH found near. Stopped.');
            script.stop();

        end;

        InspectInv(inv_collect);
        print(format('Items to store: %d', [inv_collect.count]));

        InitWh(wh_index);

        if inv_collect.Count > 0 then
            saveInv(inv_collect)

        else
            print('Nothing to store.');

    finally

        inv_collect.free;
    end;

    print('Done!');
end;

procedure SaveAdena();
var
    Pck: TNetworkPacket;
    s: string;
begin
    print('SaveAdena');
    // send packet with id/count
    pck := TNetworkPacket.Create;
    try
        pck.WriteC($31); // SendWareHouseDepositList
        pck.WriteD(1);
        pck.WriteD(57);
        pck.WriteD(44);

        s := Pck.tohex;
        print(s);
        Engine.bypasstoserver('SendToServer ' + s);
        // Engine.SendToServer(Pck.ToHex); // send formatted to HEX packet to the server
    finally
        Pck.Free;
    end;
    {
      Uses PacketUnit, SysUtils;
      var Pck: TNetworkPacket;
      begin
      Pck:= TNetworkPacket.Create;

      Pck.WriteC($38);   //ID
      
      Pck.WriteS('Hello World');
      Pck.WriteD(0);
      Engine.bypasstoserver('SendToServer '+Pck.tohex); 
      Pck.Free;
    }
end;

begin
    // SaveAdena();
    // dlg := Engine.DlgText;       print(dlg);       LogMessage(dlg);
    { Pck:= TNetworkPacket.Create;
      try
      Pck.WriteC($38);   //ID
      
      Pck.WriteS('жопа');
      Pck.WriteD(0);
      Engine.bypasstoserver('SendToServer '+Pck.tohex);
      finally
      Pck.Free;
      end; }
    main();

end.

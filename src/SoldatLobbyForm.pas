unit SoldatLobbyForm;

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
    StdCtrls, Process, FPHTTPClient, FPJson, JSONParser, RegExpr;

const
    {$IFDEF UNIX}
    SOLDAT_PROGRAM = 'soldat_x64';
    {$ELSE}
    SOLDAT_PROGRAM = 'soldat.exe';
    {$ENDIF}
    SETTINGS_FILE = 'configs/soldatlobby.cfg';

type
    TRequestThread = class(TThread)
    public
        Response: string;
        constructor Create();
        procedure Execute(); override;
    end;

    { TSoldatLobbyForm }

    TSoldatLobbyForm = class(TForm)
        LoadingLabel: TLabel;
        TopPanel: TPanel;
        RefreshBtn: TButton;
        AddressEdit: TEdit;
        JoinBtn: TButton;
        List: TListView;
        procedure FormCreate(Sender: TObject);
        procedure JoinBtnClick(Sender: TObject);
        procedure ListCompare(Sender: TObject; Item1, Item2: TListItem;
            Data: Integer; var Compare: Integer);
        procedure ListSelectItem(Sender: TObject; Item: TListItem;
            Selected: Boolean);
        procedure onActivate(Sender: TObject);
        procedure RefreshBtnClick(Sender: TObject);
    private
        Settings: TStringList;
        RequestThread: TRequestThread;
        LobbyData: TJSONData;
        procedure StartReload();
        procedure OnRequestDone(Sender: TObject);
        procedure StartSoldat(_: PtrInt);
        procedure SavePassword();
    public

    end;


var
    LobbyForm: TSoldatLobbyForm;

implementation

{$R *.lfm}

constructor TRequestThread.Create();
begin
    inherited Create(false);
    FreeOnTerminate := true;
    Response := '';
end;

procedure TRequestThread.Execute();
begin
    try
        Response := TFPCustomHTTPClient.SimpleGet('http://api.soldat.pl/v0/servers');
    finally
    end;
end;

procedure TSoldatLobbyForm.FormCreate(Sender: TObject);
begin
    Settings := TStringList.Create();
    try
        Settings.LoadFromFile(SETTINGS_FILE);
    except
    end;
end;

procedure TSoldatLobbyForm.onActivate(Sender: TObject);
begin
    StartReload();
end;

procedure TSoldatLobbyForm.RefreshBtnClick(Sender: TObject);
begin
    StartReload();
end;

procedure TSoldatLobbyForm.JoinBtnClick(Sender: TObject);
begin
    if AddressEdit.Caption <> '' then
    begin
        SavePassword();
        Visible := false;
        Application.QueueAsyncCall(@StartSoldat, 0);
    end;
end;

procedure TSoldatLobbyForm.StartSoldat(_: PtrInt);
var
    output: string;
begin
    RunCommand(SOLDAT_PROGRAM, ['-joinurl', AddressEdit.Caption], output);
    Visible := true;
end;

procedure TSoldatLobbyForm.SavePassword();
var
    addr: string;
    output: string;
    re: TRegExpr;
    key: string;
    value: string;
    i: integer;
begin
    try
        addr := AddressEdit.Caption;
        re := TRegExpr.Create('(?:soldat://)?([^/=]+)(/.+)?');

        if re.Exec(addr) then
        begin
            key := re.Match[1];
            value := re.Match[2];

            if Length(value) > 1 then
            begin
                Settings.Values[key] := Copy(value, 2, Length(value) - 1);
                Settings.SaveToFile(SETTINGS_FILE);
            end
            else begin
                i := Settings.IndexOfName(key);
                if i >= 0 then
                begin
                    Settings.Delete(i);
                    Settings.SaveToFile(SETTINGS_FILE);
                end;
            end;
        end;
    finally
        re.Free();
    end;
end;

procedure TSoldatLobbyForm.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
    selItem: TListItem;
    data: TJSONObject;
    addr: string;
    key: string;
    pwd: string;
begin
    selItem := List.Selected;
    if selItem <> nil then
    begin
        data := TJSONObject(selItem.Data);

        key := Format('%s:%d', [
            data.Get('IP', ''),
            data.Get('Port', 0)
        ]);

        addr := 'soldat://' + key;

        if data.Get('Private', False) then
        begin
            pwd := Settings.Values[key];
            if pwd <> '' then
                addr += '/' + pwd
            else
                addr += '/PASS';
        end;
        AddressEdit.Text := addr;
    end
    else begin
        AddressEdit.Text := '';
    end;
end;

procedure TSoldatLobbyForm.ListCompare(Sender: TObject; Item1,
    Item2: TListItem; Data: Integer; var Compare: Integer);
var
    a: TJSONObject;
    b: TJSONObject;
    aNum: Integer;
    bNum: Integer;
    aStr: string;
    bStr: string;
begin
    if List.SortColumn = 2 then
    begin
        a := TJSONObject(Item1.Data);
        b := TJSONObject(Item2.Data);
        aNum := a.Get('NumPlayers', 0);
        bNum := b.Get('NumPlayers', 0);
        Compare := aNum - bNum;
    end
    else begin
        if List.SortColumn = 0 then
        begin
            aStr := Item1.Caption;
            bStr := Item2.Caption;
        end
        else begin
            aStr := Item1.SubItems[List.SortColumn - 1];
            bStr := Item2.SubItems[List.SortColumn - 1];
        end;
        Compare := String.Compare(aStr, bStr, true);
    end;

    if List.SortDirection = sdDescending then
    begin
        Compare := -Compare;
    end;

    // sort indicators are wrong...
    if Compare < 0 then
        Compare := 1
    else if Compare > 0 then
        Compare := -1;
end;

procedure TSoldatLobbyForm.StartReload();
begin
    if RefreshBtn.Enabled then
    begin
        RefreshBtn.Enabled := false;
        List.Visible := false;
        LoadingLabel.Visible := true;

        RequestThread := TRequestThread.Create();
        RequestThread.OnTerminate := @OnRequestDone;
    end;
end;

procedure TSoldatLobbyForm.OnRequestDone(Sender: TObject);
var
    data: TJSONObject;
    servers: TJSONArray;
    serverItem: TJSONObject;
    item: TListItem;
    i: integer;
begin
    try
        if LobbyData <> nil then
            LobbyData.Free();

        LobbyData := GetJSON(RequestThread.Response);

        data := LobbyData as TJSONObject;
        servers := data.Arrays['Servers'];

        List.BeginUpdate();
        List.Items.Clear();
        for i := 0 to servers.Count - 1 do
        begin
            item := List.Items.Add();
            item.SubItems.BeginUpdate();
            serverItem := servers.Objects[i];
            item.Data := serverItem;
            item.Caption := serverItem.Get('Name', '');
            item.SubItems.Add(serverItem.Get('GameStyle', ''));
            item.SubItems.Add('%d / %d', [
                serverItem.Get('NumPlayers', 0),
                serverItem.Get('MaxPlayers', 0)
            ]);
            item.SubItems.Add(serverItem.Get('CurrentMap', ''));
            item.SubItems.Add(serverItem.Get('Version', ''));
            item.SubItems.EndUpdate();
        end;
        List.EndUpdate();
    finally
        LoadingLabel.Visible := false;
        List.Visible := true;

        if List.Items.Count > 0 then
        begin
            List.CustomSort(nil, 0);
            List.Selected := List.Items[0];
            List.Items[0].MakeVisible(false);
        end;

        List.SetFocus();
        RefreshBtn.Enabled := true;
    end;
end;

end.

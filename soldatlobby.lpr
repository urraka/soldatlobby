program soldatlobby;

{$mode objfpc}{$H+}

uses
    {$IFDEF UNIX}
    cthreads,
    {$ENDIF}
    {$IFDEF HASAMIGA}
    athreads,
    {$ENDIF}
    Interfaces, // this includes the LCL widgetset
    Forms,
    SoldatLobbyForm;

{$R *.res}

begin
    RequireDerivedFormResource:=True;
    Application.Scaled := True;
    Application.Initialize;
    Application.CreateForm(TSoldatLobbyForm, LobbyForm);
    Application.Run;
end.

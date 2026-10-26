#define SourcePath ".."

#ifndef FLADDER_VERSION
  #define FLADDER_VERSION "latest"
#endif

[Setup]
AppId={{D573EDD5-117A-47AD-88AC-62C8EBD11DC7}
AppName="Valkery Stremio"
AppVersion={#FLADDER_VERSION}
AppPublisher="Valkery"
AppPublisherURL="https://github.com/ValeryJL/Valkery-Stremio-Client"
AppSupportURL="https://github.com/ValeryJL/Valkery-Stremio-Client"
AppUpdatesURL="https://github.com/ValeryJL/Valkery-Stremio-Client"
DefaultDirName={localappdata}\Programs\ValkeryStremio
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=fladder_setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern

SetupLogging=yes
UninstallLogging=yes
UninstallDisplayName="Valkery Stremio"
UninstallDisplayIcon={app}\fladder.exe
SetupIconFile="{#SourcePath}\icons\production\fladder_icon.ico"
LicenseFile="{#SourcePath}\LICENSE"
WizardImageFile={#SourcePath}\assets\windows-installer\fladder-installer-100.bmp,{#SourcePath}\assets\windows-installer\fladder-installer-125.bmp,{#SourcePath}\assets\windows-installer\fladder-installer-150.bmp

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourcePath}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Valkery Stremio"; Filename: "{app}\fladder.exe"
Name: "{autodesktop}\Valkery Stremio"; Filename: "{app}\fladder.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\fladder.exe"; Description: "{cm:LaunchProgram,Valkery Stremio}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  case CurUninstallStep of
    usUninstall:
      begin
        if MsgBox('Would you like to delete the application''s data? This action cannot be undone. Synced files will remain unaffected.', mbConfirmation, MB_YESNO) = IDYES then
        begin
            if DelTree(ExpandConstant('{localappdata}\ValkeryStremio'), True, True, True) = False then
            begin
                Log(ExpandConstant('{localappdata}\ValkeryStremio could not be deleted. Skipping...'));
            end;
        end;
      end;
  end;
end;

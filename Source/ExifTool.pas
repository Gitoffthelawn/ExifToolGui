unit ExifTool;

interface

uses System.Classes, System.Types, System.SyncObjs, Winapi.Windows,
     ExifTool_PipeStream;

const
  CRLF = #13#10;

  GUI_PREF = '-GUI';
  GUI_SEP  = '-GUI-SEP';
  GUI_INV  = '-GUI-INV';
  GUI_HASH_MD5 = '-GUI-HASH-MD5';
  GUI_HASH_SHA1 = '-GUI-HASH-SHA1';
  GUI_HASH_SHA2 = '-GUI-HASH-SHA2';

  VetoTags: array of string = ['-', '--'];
  CmdStr   = '-';

type
  TExecETEvent = procedure(ExecNum: word; EtCmds, EtOuts, EtErrs, StatusLine: string; PopupOnError: boolean) of object;

  TET_OptionsRec = record
    ETLangDef: string;
    ETBackupMode: string;
    ETFileDate: string;
    ETSeparator: string;
    ETMinorError: string;
    ETGpsFormat: string;
    ETShowNumber: string;
    ETCharset: string;
    ETVerbose: integer;
    ETAPIWindowsWideFile: string;
    ETAPIWindowsLongPath: string;
    ETAPILargeFileSupport: string;
    ETGeoDir: string;
    ETCustomOptions: string;
    class operator Initialize (out ET_Options: TET_OptionsRec);
    procedure SetLangDef(UseLangDef: string);
    procedure SetBackupMode(UseBackUpMode: boolean);
    procedure SetFileDate(UseFileDate: boolean);
    procedure SetMinorError(UseMinorError: boolean);
    procedure SetGpsFormat(UseDecimal: boolean);
    procedure SetShowNumber(UseShowNumber: boolean);
    procedure SetVerbose(Level: integer);
    procedure SetApiWindowsWideFile(UseWide: boolean);
    procedure SetApiWindowsLongPath(UseLong: boolean);
    procedure SetApiLargeFileSupport(UseLarge: boolean);
    procedure SetGeoDir(GeoDir: string);
    procedure SetCustomOptions(Custom: string);
    procedure SetSeparator(const Sep: string);

    function GetVerbose: integer;
    function GetGeoDir: string;
    function GetCustomOptions: string;
    function GetOptions(Charset: boolean = true): string;
    function GetSeparator: string;
    function GetSeparatorChar: Char;
  end;

  TExifTool = class(TObject)
  private
    FId: integer;
    FExecETEvent: TExecETEvent;
    FOptionsRec: TET_OptionsRec;
    FETprocessInfo: TProcessInformation;
    FETOutPipe: TPipeStream;
    FETErrPipe: TPipeStream;
    FPipeInRead, FPipeInWrite: THandle;
    FPipeOutRead, FPipeOutWrite: THandle;
    FPipeErrRead, FPipeErrWrite: THandle;
    FETValidWorkingDir: boolean;
    FETWorkingDir: string;
    FETTempFile: string;
    FRecordingFile: string;
    FExecNum: word;
    FCounter: TET_Counter;
    function GetCounter: TET_Counter;
    function GetTempFile: string;
    procedure SetRecordingFile(AFile: string);
  protected
    procedure AddExecNum(var FinalCmd: string);
  public
    constructor Create; overload;
    constructor Create(const Id: integer); overload;
    destructor Destroy; override;

    function StayOpen(WorkingDir: string): boolean;
    function OpenExec(ETcmd: string; FNames: string; var ETouts, ETErrs: string; PopupOnError: boolean = true): boolean; overload;
    function OpenExec(ETcmd: string; FNames: string; ETout: TStrings; PopupOnError: boolean = true): boolean; overload;
    function OpenExec(ETcmd: string; FNames: string; PopupOnError: boolean = true): boolean; overload;
    procedure OpenExit(WaitForClose: boolean = false);

    class function ExecET(ETcmd, FNames, WorkingDir: string; var ETouts, ETErrs: string): boolean; overload;
    class function ExecET(ETcmd, FNames, WorkingDir: string; var ETouts: string): boolean; overload;

    function EmbeddedExecute(const Args, FNames: string): string;
    procedure SetCounter(ACounterETEvent: TCounterETEvent; ACounter: integer);
    property ETWorkingDir: string read FETWorkingDir;
    property ETValidWorkingDir: boolean read FETValidWorkingDir;
    property ETTempFile: string read GetTempFile;
    property ExecETEvent: TExecETEvent read FExecETEvent write FExecETEvent;
    property ExecNum: word read FExecNum;
    property Options: TET_OptionsRec read FOptionsRec;
    property Counter: TET_Counter read GetCounter;
    property RecordingFile: string read FRecordingFile write SetRecordingFile;
  end;

function CmdDateTimeOriginal(const Group: string): string;
function CmdCreateDate(const Group: string): string;
function CmdModifyDate(const Group: string): string;
function ReplaceVetoTag(ATag: string): string;

var
   ET: TExifTool;

implementation

uses
  System.SysUtils, System.IOUtils,
  Main, MainDef, ExifToolsGUI_Utils,
  UnitLangResources;

function CmdDateTimeOriginal(const Group: string): string;
begin
  result := Group + ':DateTimeOriginal';
end;

function CmdCreateDate(const Group: string): string;
begin
  result := Group + ':CreateDate';
end;

function CmdModifyDate(const Group: string): string;
begin
  result := Group + ':ModifyDate';
end;

function ReplaceVetoTag(ATag: string): string;
var
  CurTag: string;
begin
  for CurTag in VetoTags do
    if CurTag = ATag then
      exit(GUI_INV);

  exit(ATag);
end;

const
  SizePipeBuffer = 65535;

{ ET_Options}

class operator TET_OptionsRec.Initialize (out ET_Options: TET_OptionsRec);
begin
  with ET_Options do
  begin
    SetLangDef('');
    SetBackupMode(true);
    SetFileDate(false);
    SetSeparator('*');
    SetMinorError(false);
    SetGpsFormat(true);
    SetShowNumber(false);
    ETCharset := '-CHARSET' + CRLF + 'FILENAME=UTF8'; // UTF8 it is. No choice  (CHARSET UTF8 is Default PH)
    SetVerbose(0);
    SetGeoDir('');
    SetCustomOptions('');
  end;
end;

procedure TET_OptionsRec.SetLangDef(UseLangDef: string);
begin
  if (UseLangDef <> '') then
    ETLangDef := UseLangDef + CRLF
  else
    ETLangDef := '';
end;

procedure TET_OptionsRec.SetBackupMode(UseBackUpMode: boolean);
begin
  if (UseBackUpMode) then
    ETBackupMode := '-overwrite_original' + CRLF
  else
    ETBackupMode := '';
end;

procedure TET_OptionsRec.SetFileDate(UseFileDate: boolean);
begin
  if (UseFileDate) then
    ETFileDate := '-P' + CRLF
  else
    ETFileDate := '';
end;

procedure TET_OptionsRec.SetMinorError(UseMinorError: boolean);
begin
  if (UseMinorError) then
    ETMinorError := '-m' + CRLF
  else
    ETMinorError := '';
end;

procedure TET_OptionsRec.SetGpsFormat(UseDecimal: boolean);
begin
  if UseDecimal then
    ETGpsFormat := '-c' + CRLF + '%.6f' + #$B0 + CRLF
  else
    ETGpsFormat := '-c' + CRLF + '%d' + #$B0 + '%.4f' + CRLF;
end;

procedure TET_OptionsRec.SetShowNumber(UseShowNumber: Boolean);
begin
  if UseShowNumber then
    ETShowNumber := '-n' + CRLF
  else
    ETShowNumber := '';
end;

procedure TET_OptionsRec.SetVerbose(Level: integer);
begin
  ETVerbose := Level;
end;

procedure TET_OptionsRec.SetApiWindowsWideFile(UseWide: boolean);
begin
  if UseWide then
    ETAPIWindowsWideFile := '-API' + CRLF + 'WindowsWideFile=1' + CRLF
  else
    ETAPIWindowsWideFile := '';
end;

procedure TET_OptionsRec.SetApiWindowsLongPath(UseLong: boolean);
begin
  if UseLong then
    ETAPIWindowsLongPath := '-API' + CRLF + 'WindowsLongPath=1' + CRLF
  else
    ETAPIWindowsLongPath := '';
end;

procedure TET_OptionsRec.SetApiLargeFileSupport(UseLarge: boolean);
begin
  if UseLarge then
    ETAPILargeFileSupport  := '-API' + CRLF + 'LargeFileSupport=1' + CRLF
  else
    ETAPILargeFileSupport := '';
end;

procedure TET_OptionsRec.SetGeoDir(GeoDir: string);
begin
  if (GeoDir <> '') then
    ETGeoDir := '-API' + CRLF + 'GeoDir=' + GeoDir + CRLF
  else
    ETGeoDir := '';
end;

procedure TET_OptionsRec.SetCustomOptions(Custom: string);
begin
  ETCustomOptions := Custom;
end;

function TET_OptionsRec.GetVerbose: integer;
begin
  result := ETVerbose;
end;

function TET_OptionsRec.GetCustomOptions: string;
begin
  result := EndsWithCRLF(ArgsFromDirectCmd(ETCustomOptions));
end;

function TET_OptionsRec.GetGeoDir: string;
begin
  result := ETGeoDir;
end;

function TET_OptionsRec.GetOptions(Charset: boolean = true): string;
begin
  result := '';
  if (Charset) then
    result := ETCharset + CRLF;
  result := result + Format('-v%d', [ETVerbose]) + CRLF; // -for file counter!
  if ETLangDef <> '' then
    result := result + '-lang' + CRLF + ETLangDef + CRLF;
  result := result + ETBackupMode;
  result := result + ETSeparator;
  result := result + ETMinorError + ETFileDate;
  result := result + ETGpsFormat + ETShowNumber;
  result := result + ETAPIWindowsWideFile;
  result := result + ETAPIWindowsLongPath;
  result := result + ETAPILargeFileSupport;
  result := result + GetGeoDir;
  result := result + GetCustomOptions;
  // +further options...
end;

function TET_OptionsRec.GetSeparator: string;
var
  ETSep: string;
begin
  ETSep := ETSeparator;
  result := NextField(ETSep, #10);
  result := NextField(ETSep, #13);
end;

function TET_OptionsRec.GetSeparatorChar: Char;
var
  Sep: string;
begin
  result := ' ';
  Sep := GetSeparator;
  if (Length(Sep) > 0) then
    result := Sep[1];
end;

procedure TET_OptionsRec.SetSeparator(const Sep: string);
var
  CorrectSep: string;
begin
  CorrectSep := Sep;
  if (Trim(CorrectSep) = '') then
    CorrectSep := '*';

  ETSeparator := '-sep' + CRLF + CorrectSep + CRLF;
end;

// Add ExecNum to FinalCmd
procedure TExifTool.AddExecNum(var FinalCmd: string);
begin
  // Update Execnum. From 10 to 99.
  Inc(FExecNum);
  if (FExecNum > 99) then
    FExecNum := 10;
              // '-echo4 CRLF {readyxx} CRLF'    Ensures that something is written to StdErr. TSOPipeStream relies on it.
  FinalCmd := Format('-echo4%s{ready%u}%s', [CRLF, FExecNum, CRLF]) +
              FinalCmd +
              // '-executexx CRLF'               The same for STDout.
              Format('-execute%u%s', [FExecNum, CRLF]);
end;


function TExifTool.EmbeddedExecute(const Args, FNames: string): string;
const
  ExecuteCmd = ' -execute';
var
  LwCase: string;
  NamesCmd, OptionsCmd: string;
begin
  result := '';

  NamesCmd := DirectCmdFromArgs(FNames);
  OptionsCmd := DirectCmdFromArgs(Options.GetOptions);
  // Only lowercase -execute. For NextField
  LwCase := ReplaceAll(Args, [ExecuteCmd], [ExecuteCmd], [rfReplaceAll, rfIgnoreCase]);
  repeat
    result := result + NextField(LwCase, ExecuteCmd);
    if (LwCase = '') then
      break;
    result := result + ' ' + NamesCmd + ExecuteCmd + ' ' + OptionsCmd
   until false;
end;

procedure TExifTool.SetCounter(ACounterETEvent: TCounterETEvent; ACounter: integer);
begin
  FCounter.CounterEvent := ACounterETEvent;
  FCounter.Counter := ACounter;
end;

function TExifTool.GetCounter: TET_Counter;
begin
  result := FCounter;
end;

function TExifTool.GetTempFile: string;
begin
  if (FETTempFile = '') then
    FETTempFile := GetExifToolTmp(FId);
  result := FETTempFile;
end;

constructor TExifTool.Create;
begin
  inherited Create;

  FId := 0;
  FExecNum := 10; // From 10 to 99
  FETWorkingDir := '';
  FRecordingFile := '';
  FETTempFile := '';
  FETOutPipe := nil;
  FETErrPipe := nil;
  SetCounter(nil, 0);
end;

constructor TExifTool.Create(const Id: integer);
begin
  Create;
  FId := Id +1;
  FOptionsRec := ET.Options;
end;

destructor TExifTool.Destroy;
begin
  OpenExit(true);

  if Assigned(FETOutPipe) then
    FETOutPipe.Free;
  if Assigned(FETErrPipe) then
    FETErrPipe.Free;
  FETWorkingDir := '';
  FETTempFile := '';
  FRecordingFile := '';

  inherited Destroy;
end;

procedure TExifTool.SetRecordingFile(AFile: string);
begin
  if (FRecordingFile <> AFile) then
  begin
    FRecordingFile := AFile;
    if (FRecordingFile <> '') then
      DeleteFile(FRecordingFile);
  end;
end;

function TExifTool.StayOpen(WorkingDir: string): boolean;
var
  SecurityAttr: TSecurityAttributes;
  StartupInfo: TStartupInfo;
  ETcmd: string;
begin
  result := true;
  if (FETWorkingDir = WorkingDir) then
    exit;

  OpenExit; // -changing WorkingDir OnTheFly requires Exit first

  FETValidWorkingDir := DirectoryExists(WorkingDir);
  if not FETValidWorkingDir then
    exit(FETValidWorkingDir);

  ETcmd := GUIsettings.ETOverrideDir + 'exiftool ' + GUIsettings.GetCustomConfig + ' -stay_open True -@ -';
  FillChar(FETprocessInfo, SizeOf(TProcessInformation), #0);
  FillChar(SecurityAttr, SizeOf(TSecurityAttributes), #0);
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := true;
  SecurityAttr.lpSecurityDescriptor := nil;
  CreatePipe(FPipeInRead, FPipeInWrite, @SecurityAttr, 0);
  CreatePipe(FPipeOutRead, FPipeOutWrite, @SecurityAttr, 0);
  CreatePipe(FPipeErrRead, FPipeErrWrite, @SecurityAttr, 0);
  FillChar(StartupInfo, SizeOf(TStartupInfo), #0);
  StartupInfo.cb := SizeOf(StartupInfo);
  with StartupInfo do
  begin
    hStdInput := FPipeInRead;
    hStdOutput := FPipeOutWrite;
    hStdError := FPipeErrWrite;
    wShowWindow := SW_HIDE;
    dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
  end;

  if (CreateProcess(nil, PChar(ETcmd), nil, nil, true,
                   CREATE_DEFAULT_ERROR_MODE or CREATE_NEW_CONSOLE or NORMAL_PRIORITY_CLASS,
                   nil, PChar(WorkingDir),
    StartupInfo, FETprocessInfo)) then
  begin
    CloseHandle(FPipeInRead);
    CloseHandle(FPipeOutWrite);
    CloseHandle(FPipeErrWrite);

    if Assigned(FETOutPipe) then
      FreeAndNil(FETOutPipe);
    FETOutPipe := TPipeStream.Create(FPipeOutRead, SizePipeBuffer);

    if Assigned(FETErrPipe) then
      FreeAndNil(FETErrPipe);
    FETErrPipe := TPipeStream.Create(FPipeErrRead, SizePipeBuffer);

    FETWorkingDir := WorkingDir;
  end
  else
  begin
    CloseHandle(FPipeInRead);
    CloseHandle(FPipeInWrite);
    CloseHandle(FPipeOutRead);
    CloseHandle(FPipeOutWrite);
    CloseHandle(FPipeErrRead);
    CloseHandle(FPipeErrWrite);
  end;
  result := (FETWorkingDir <> '');
end;

procedure TExifTool.OpenExit(WaitForClose: boolean = false);
const
  ExitCmd: AnsiString = '-stay_open' + CRLF + 'False' + CRLF; // Can not be Unicode
var
  BytesCount: Dword;
begin
  if (FETWorkingDir <> '') then
  begin
    WriteFile(FPipeInWrite, ExitCmd[1], Length(ExitCmd), BytesCount, nil);
    FlushFileBuffers(FPipeInWrite);

    if (WaitForClose) then
      WaitForSingleObject(FETprocessInfo.hProcess, GUIsettings.ETTimeOut);

    CloseHandle(FETprocessInfo.hThread);
    CloseHandle(FETprocessInfo.hProcess);
    CloseHandle(FPipeInWrite);
    CloseHandle(FPipeOutRead);
    CloseHandle(FPipeErrRead);
    FETWorkingDir := '';
  end;
end;

function TExifTool.OpenExec(ETcmd: string; FNames: string; var ETouts, ETErrs: string; PopupOnError: boolean = true): boolean;
var
  ReadOut: TSOReadPipeThread;
  ReadErr: TSOReadPipeThread;
  FinalCmd: string;
  StatusLine: string;
  LengthReady: integer;
  Call_ET: AnsiString; // Can not be Unicode. Only holds the -@ <argsfilename> so no international chars expected
  BytesCount: Dword;
  CanUseUtf8: boolean;
  CrWait, CrNormal: HCURSOR;
begin
  result := false;

  if (FETWorkingDir <> '') and
     (Length(ETcmd) > 1) then
  begin
    CrWait := LoadCursor(0, IDC_WAIT);
    CrNormal := SetCursor(CrWait);

    TMonitor.Enter(Self);
    try
      // Dont know what it's for!
      ETcmd := ReplaceAll(ETcmd, ['||'], [CRLF]);

      // Also probably not needed, since all is UTF8
      CanUseUtf8 := (pos('-L' + CRLF, ETcmd) = 0);

      // Create TempFile with commands and filenames
      FinalCmd := EndsWithCRLF(Options.GetOptions(CanUseUtf8) + ETcmd);
      if FNames <> '' then
        FinalCmd := EndsWithCRLF(FinalCmd + FNames);

      // Add Execnum, also to stderr!
      AddExecNum(FinalCmd);

      // Create tempfile
      WriteArgsFile(FinalCmd, ETTempFile);
      Call_ET := EndsWithCRLF('-@' + CRLF + ETTempFile);

      // Write command to Pipe. Triggers ExifTool execution
      WriteFile(FPipeInWrite, Call_ET[1], ByteLength(Call_ET), BytesCount, nil);
      FlushFileBuffers(FPipeInWrite);

      // Read StdOut and stdErr
      FETOutPipe.SetCounter(Counter);
      ReadOut := TSOReadPipeThread.Create(FETOutPipe, FExecNum);
      ReadErr := TSOReadPipeThread.Create(FETErrPipe, FExecNum);
      try
        ReadOut.WaitFor;
        ReadErr.WaitFor;
      finally
        SetCounter(nil, 0);
        ReadOut.Free;
        ReadErr.Free;
      end;
      ETouts := FETOutPipe.AnalyseResult(StatusLine, LengthReady);
      FETOutPipe.Clear;

      ETErrs := FETErrPipe.AnalyseError;
      FETErrPipe.Clear;

      // Callback for Logging
      if Assigned(ExecETEvent) then
        ExecETEvent(FExecNum, FinalCmd, ETouts, ETErrs, StatusLine, PopupOnError);

      // Return result without {readyxx}#13#10
      SetLength(ETouts, Length(ETouts) - LengthReady);

      // Record?
      if (PopupOnError) and
         (FRecordingFile <> '') then
        TFile.AppendAllText(FRecordingFile, ETouts, TEncoding.UTF8);

      result := true;
    finally
      TMonitor.Exit(Self);
      SetCursor(CrNormal);
    end;
  end;
end;

function TExifTool.OpenExec(ETcmd: string; FNames: string; ETout: TStrings; PopupOnError: boolean = true): boolean;
var
  ETouts, ETErrs: string;
begin
  result := OpenExec(ETcmd, FNames, ETouts, ETErrs, PopupOnError);
  ETout.Text := ETouts;
end;

function TExifTool.OpenExec(ETcmd: string; FNames: string; PopupOnError: boolean = true): boolean;
var
  ETouts, ETErrs: string;
begin
  result := OpenExec(ETcmd, FNames, ETouts, ETErrs, PopupOnError);
end;

// Executes ExifTool as a separate process,
// but needs the ExifTool object for Execnum, Options, tempfile and counter
class function TExifTool.ExecET(ETcmd, FNames, WorkingDir: string; var ETouts, ETErrs: string): boolean;
var
  ReadOut: TReadPipeThread;
  ReadErr: TReadPipeThread;
  ProcessInfo: TProcessInformation;
  SecurityAttr: TSecurityAttributes;
  StartupInfo: TStartupInfo;
  PipeOutRead, PipeOutWrite: THandle;
  PipeErrRead, PipeErrWrite: THandle;
  FinalCmd: string;
  StatusLine: string;
  LengthReady: integer;
  Call_ET: string;
  PWorkingDir: PChar;
  CanUseUtf8: boolean;
  CrWait, CrNormal: HCURSOR;
begin

  CrWait := LoadCursor(0, IDC_WAIT);
  CrNormal := SetCursor(CrWait);

  try
    FillChar(ProcessInfo, SizeOf(TProcessInformation), #0);
    FillChar(SecurityAttr, SizeOf(TSecurityAttributes), #0);
    SecurityAttr.nLength := SizeOf(SecurityAttr);
    SecurityAttr.bInheritHandle := true;
    SecurityAttr.lpSecurityDescriptor := nil;
    CreatePipe(PipeOutRead, PipeOutWrite, @SecurityAttr, 0);
    CreatePipe(PipeErrRead, PipeErrWrite, @SecurityAttr, 0);
    FillChar(StartupInfo, SizeOf(TStartupInfo), #0);
    StartupInfo.cb := SizeOf(StartupInfo);
    with StartupInfo do
    begin
      hStdInput := 0;
      hStdOutput := PipeOutWrite;
      hStdError := PipeErrWrite;
      wShowWindow := SW_HIDE;
      dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
    end;
    if not DirectoryExists(WorkingDir) then
      PWorkingDir := nil
    else
      PWorkingDir := PChar(WorkingDir);

    CanUseUtf8 := (Pos('-L ', ETcmd) = 0);

    FinalCmd := EndsWithCRLF(ET.Options.GetOptions(CanUseUtf8) + ArgsFromDirectCmd(ETcmd));
    FinalCmd := EndsWithCRLF(FinalCmd + FNames);

    ET.AddExecNum(FinalCmd);

    WriteArgsFile(FinalCmd, ET.ETTempFile);
    Call_ET := GUIsettings.ETOverrideDir + 'exiftool ' + GUIsettings.GetCustomConfig + ' -@ "' + ET.ETTempFile + '"';

    result := CreateProcess(nil, PChar(Call_ET), nil, nil, true,
                            CREATE_DEFAULT_ERROR_MODE or CREATE_NEW_CONSOLE or NORMAL_PRIORITY_CLASS,
                            nil, PWorkingDir, StartupInfo, ProcessInfo);
    CloseHandle(PipeOutWrite);
    CloseHandle(PipeErrWrite);
    if result then
    begin
      // ========= Read StdOut and stdErr =======================
      ReadOut := TReadPipeThread.Create(PipeOutRead, SizePipeBuffer);
      ReadOut.PipeStream.SetCounter(ET.Counter);
      ReadErr := TReadPipeThread.Create(PipeErrRead, SizePipeBuffer);
      try
        ReadOut.WaitFor;
        ETouts := ReadOut.PipeStream.AnalyseResult(StatusLine, LengthReady);

        ReadErr.WaitFor;
        ETErrs := ReadErr.PipeStream.AnalyseError;
      finally
        ReadOut.Free;
        ReadErr.Free;
        ET.SetCounter(nil, 0);
      end;

      // ----------------------------------------------
      WaitForSingleObject(ProcessInfo.hProcess, GUIsettings.ETTimeOut);
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);

      // Callback for Logging
      if Assigned(ET.ExecETEvent) then
        ET.ExecETEvent(ET.ExecNum, FinalCmd, ETouts, ETErrs, StatusLine, true);

      // Return result without {readyxx}#13#10
      // Although this call will never have it.
      SetLength(ETouts, Length(ETouts) - LengthReady);
      result := true;
    end;
  finally
    CloseHandle(PipeOutRead);
    CloseHandle(PipeErrRead);
    SetCursor(CrNormal);
  end;
end;

class function TexifTool.ExecET(ETcmd, FNames, WorkingDir: string; var ETouts: string): boolean;
var
  ETErrs: string;
begin
  result := ExecET(ETcmd, FNames, WorkingDir, ETouts, ETErrs);
end;

initialization
begin
  ET := TExifTool.Create;
end;

finalization
begin
  ET.Free;
end;

end.

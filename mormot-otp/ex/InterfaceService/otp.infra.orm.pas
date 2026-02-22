unit otp.infra.orm;

{$I mormot.defines.inc}

interface

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.json,
  mormot.core.unicode,
  mormot.orm.core,
  mormot.rest.sqlite3,
  mormot.rest.server,
  otp.domain,
  otp.infra;

type
  /// ORM-based implementation of IOtpPersistence
  TOtpPersistence = class(TInterfacedObject, IOtpPersistence)
  private
    fRest: TRestServerDB;
    fOrm: IRestOrm;
  public
    constructor Create(const aFileName: TFileName; const aRoot: RawUtf8 = 'root');

    /// Clean up resources
    destructor Destroy; override;

    // IOtpPersistence implementation
    function UserExists(const Username: RawUtf8): boolean;
    function GetUser(UserId: TOtpUserID): TDomOtpUser;
    function GetUserByUsername(const Username: RawUtf8): TDomOtpUser;
    function CreateUser(User: TDomOtpUser): TOtpUserID;
    function UpdateUser(User: TDomOtpUser): boolean;
    function LogAttempt(Log: TDomOtpLog): TOtpLogID;
    function CountLogs(UserId: TOtpUserID): Integer;
    function GetRecentLogs(UserId: TOtpUserID; MaxCount: Integer): TDomOtpLogObjArray;

    property Server: TRestServerDB read fRest;
  end;

implementation

{ TOtpPersistence }

constructor TOtpPersistence.Create(const aFileName: TFileName; const aRoot: RawUtf8);
var
  model: TOrmModel;
begin
  inherited Create;
  fRest := TRestServerDB.CreateSqlite3([TDomOtpUser, TDomOtpLog], aFileName, aRoot);
  fRest.NoAjaxJson := true;
  fOrm := fRest.ORM;
end;

destructor TOtpPersistence.Destroy;
begin
  fOrm := nil; // Release interface before freeing server
  FreeAndNil(fRest);
  inherited;
end;

function TOtpPersistence.UserExists(const Username: RawUtf8): boolean;
begin
  result := fOrm.OneFieldValueInt64(TDomOtpUser, 'ID', FormatSql('Username=?', [], [Username])) <> 0;
end;

function TOtpPersistence.GetUser(UserId: TOtpUserID): TDomOtpUser;
begin
  result := TDomOtpUser.Create;
  if not fOrm.Retrieve(UserId, result) then
    FreeAndNilSafe(result);
end;

function TOtpPersistence.GetUserByUsername(const Username: RawUtf8): TDomOtpUser;
begin
  result := TDomOtpUser.CreateAndFillPrepare(fOrm, 'Username=?', [Username]);
  if not result.FillOne then
    FreeAndNilSafe(result);
end;

function TOtpPersistence.CreateUser(User: TDomOtpUser): TOtpUserID;
begin
  if not User.HasAllNeededFields then begin
    result := 0;
    exit;
  end;

  result := TOtpUserID(fOrm.Add(User, true));
end;

function TOtpPersistence.UpdateUser(User: TDomOtpUser): boolean;
begin
  if not User.HasAllNeededFields then begin
    result := false;
    exit;
  end;

  result := fOrm.Update(User);
end;

function TOtpPersistence.LogAttempt(Log: TDomOtpLog): TOtpLogID;
begin
  if not Log.HasAllNeededFields then begin
    result := 0;
    exit;
  end;

  // Set timestamp if not already set
  if Log.Timestamp = 0 then
    Log.Timestamp := UnixMSTimeUtc;

  result := TOtpLogID(fOrm.Add(Log, true));
end;

function TOtpPersistence.CountLogs(UserId: TOtpUserID): Integer;
var
  tmp: TDomOtpLog;
begin
  tmp := TDomOtpLog.CreateAndFillPrepare(fOrm, 'UserId=?', [UserId]);
  try
    result := tmp.FillTable.RowCount;
  finally
    tmp.Free;
  end;
end;

function TOtpPersistence.GetRecentLogs(UserId: TOtpUserID; MaxCount: Integer): TDomOtpLogObjArray;
var
  log: TDomOtpLog;
begin
  SetLength(result, 0);
  log := TDomOtpLog.CreateAndFillPrepare(fOrm, 'UserId=? ORDER BY Timestamp DESC LIMIT ?', [UserId, MaxCount]);
  try
    // CreateCopy ownership transfers to result; caller must call ObjArrayClear(result)
    while log.FillOne do
      ObjArrayAdd(result, log.CreateCopy);
  finally
    log.Free;
  end;
end;

end.

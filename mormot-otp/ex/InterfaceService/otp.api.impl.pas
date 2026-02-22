unit otp.api.impl;

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.ext.otp,
  otp.api,
  otp.domain,
  otp.infra;

type
  /// Implementation of IOtpAuthService
  TOtpAuthService = class(TInterfacedObject, IOtpAuthService)
  private
    fPersistence: IOtpPersistence;
    fOtpProvider: IOtpProvider;
    fSecretGenerator: ISecretGenerator;
    procedure LogToDto(const Log: TDomOtpLog; out Entry: TAuthLogEntry);
  public
    constructor Create(const persist: IOtpPersistence;
      const otpProvider: IOtpProvider;
      const secretGen: ISecretGenerator);
    // IOtpAuthService
    function RegisterUser(const Username, Email: RawUtf8): TUserRegistrationResult;
    function ValidateToken(const Username, Token: RawUtf8;
      const IpAddress: RawUtf8 = '';
      const UserAgent: RawUtf8 = ''): TOtpValidationResult;
    function GetAuthStats(const Username: RawUtf8): TAuthStats;
    function GetRecentLogs(const Username: RawUtf8;
      MaxCount: Integer = 10): TAuthLogEntryDynArray;
    function ResetFailedAttempts(const Username: RawUtf8): Boolean;
    function SetOtpEnabled(const Username: RawUtf8; Enabled: Boolean): Boolean;
  end;


implementation

const
  OTP_ISSUER = 'mORMot2-OTP';


{ TOtpAuthService }

constructor TOtpAuthService.Create(const persist: IOtpPersistence;
  const otpProvider: IOtpProvider; const secretGen: ISecretGenerator);
begin
  inherited Create;
  fPersistence    := persist;
  fOtpProvider    := otpProvider;
  fSecretGenerator := secretGen;
end;

procedure TOtpAuthService.LogToDto(const Log: TDomOtpLog; out Entry: TAuthLogEntry);
begin
  Entry.Timestamp  := Log.Timestamp;
  Entry.Success    := Log.Success;
  Entry.IpAddress  := Log.IpAddress;
  Entry.UserAgent  := Log.UserAgent;
end;

function TOtpAuthService.RegisterUser(const Username, Email: RawUtf8): TUserRegistrationResult;
var
  user: TDomOtpUser;
  secret: RawUtf8;
begin
  Finalize(result);
  result.Success := false;

  if (Username = '') or (Email = '') then
  begin
    result.ErrorMessage := 'Username and email are required';
    exit;
  end;

  if fPersistence.UserExists(Username) then
  begin
    result.ErrorMessage := 'Username already exists';
    exit;
  end;

  // 32 Base32 chars = 20 bytes = 160-bit key; must be a multiple of 8
  secret := fSecretGenerator.GenerateSecret(32);

  user := TDomOtpUser.Create;
  try
    user.Username       := Username;
    user.Email          := Email;
    user.OtpSecret      := secret;
    user.OtpEnabled     := true;
    user.FailedAttempts := 0;

    result.UserId := fPersistence.CreateUser(user);
    if result.UserId = 0 then
    begin
      result.ErrorMessage := 'Failed to create user';
      exit;
    end;

    result.QrCodeUrl := FormatUtf8('otpauth://totp/%:%?secret=%&issuer=%',
      [OTP_ISSUER, Username, secret, OTP_ISSUER]);
    result.OtpSecret := secret;
    result.Success   := true;
  finally
    user.Free;
  end;
end;

function TOtpAuthService.ValidateToken(const Username, Token: RawUtf8;
  const IpAddress: RawUtf8 = ''; const UserAgent: RawUtf8 = ''): TOtpValidationResult;
var
  user: TDomOtpUser;
  log: TDomOtpLog;
  tokenInt: integer;
  isValid: boolean;
begin
  Finalize(result);
  result.Success := false;

  if (Username = '') or (Token = '') then
  begin
    result.ErrorMessage := 'Username and token are required';
    exit;
  end;

  tokenInt := GetInteger(pointer(Token));
  if (tokenInt < 0) or (tokenInt > 999999) then
  begin
    result.ErrorMessage := 'Invalid token format';
    exit;
  end;

  user := fPersistence.GetUserByUsername(Username);
  if user = nil then
  begin
    result.ErrorMessage := 'User not found';
    exit;
  end;

  try
    if not user.OtpEnabled then
    begin
      result.ErrorMessage := 'OTP is not enabled for this user';
      exit;
    end;

    if user.IsLocked then
    begin
      result.ErrorMessage := 'Account is locked due to too many failed attempts';
      exit;
    end;

    user.LastLoginAttempt := NowUtc;
    isValid := fOtpProvider.ValidateTOTP(user.OtpSecret, tokenInt, 1);

    log := TDomOtpLog.Create;
    try
      log.UserId    := TOtpUserID(user.ID);
      log.Success   := isValid;
      log.IpAddress := IpAddress;
      log.UserAgent := UserAgent;
      log.Timestamp := UnixMSTimeUtc;
      fPersistence.LogAttempt(log);
    finally
      log.Free;
    end;

    if isValid then
    begin
      user.ResetFailedAttempts;
      result.Success := true;
    end
    else
    begin
      user.IncrementFailedAttempts;
      result.ErrorMessage := 'Invalid token';
    end;

    fPersistence.UpdateUser(user);
  finally
    user.Free;
  end;
end;

function TOtpAuthService.GetAuthStats(const Username: RawUtf8): TAuthStats;
var
  user: TDomOtpUser;
  logs: TDomOtpLogObjArray;
  i: integer;
  lastTime: TUnixMSTime;
begin
  result := Default(TAuthStats);

  user := fPersistence.GetUserByUsername(Username);
  if user = nil then
    exit;

  try
    result.IsAccountLocked := user.IsLocked;

    logs := fPersistence.GetRecentLogs(TOtpUserID(user.ID), 1000);
    try
      result.TotalAttempts := Length(logs);
      lastTime := 0;
      for i := 0 to High(logs) do
      begin
        if logs[i].Success then
          Inc(result.SuccessfulAttempts)
        else
          Inc(result.FailedAttempts);
        if logs[i].Timestamp > lastTime then
          lastTime := logs[i].Timestamp;
      end;
      result.LastAttemptTime := lastTime;
    finally
      ObjArrayClear(logs);
    end;
  finally
    user.Free;
  end;
end;

function TOtpAuthService.GetRecentLogs(const Username: RawUtf8;
  MaxCount: Integer): TAuthLogEntryDynArray;
var
  user: TDomOtpUser;
  logs: TDomOtpLogObjArray;
  i: integer;
begin
  SetLength(result, 0);

  user := fPersistence.GetUserByUsername(Username);
  if user = nil then
    exit;

  try
    logs := fPersistence.GetRecentLogs(TOtpUserID(user.ID), MaxCount);
    try
      SetLength(result, Length(logs));
      for i := 0 to High(logs) do
        LogToDto(logs[i], result[i]);
    finally
      ObjArrayClear(logs);
    end;
  finally
    user.Free;
  end;
end;

function TOtpAuthService.ResetFailedAttempts(const Username: RawUtf8): Boolean;
var
  user: TDomOtpUser;
begin
  result := false;
  user := fPersistence.GetUserByUsername(Username);
  if user = nil then
    exit;
  try
    user.ResetFailedAttempts;
    result := fPersistence.UpdateUser(user);
  finally
    user.Free;
  end;
end;

function TOtpAuthService.SetOtpEnabled(const Username: RawUtf8;
  Enabled: Boolean): Boolean;
var
  user: TDomOtpUser;
begin
  result := false;
  user := fPersistence.GetUserByUsername(Username);
  if user = nil then
    exit;
  try
    user.OtpEnabled := Enabled;
    result := fPersistence.UpdateUser(user);
  finally
    user.Free;
  end;
end;


end.

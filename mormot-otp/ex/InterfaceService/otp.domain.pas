unit otp.domain;

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.orm.base,
  mormot.orm.core;

type
  /// Strong typing for OTP User ID
  TOtpUserID = type TID;
  
  /// Strong typing for OTP Log ID
  TOtpLogID = type TID;

  /// Domain entity: OTP User
  // - Represents a user with two-factor authentication capability
  // - Contains business validation logic
  TDomOtpUser = class(TOrm)
  protected
    fUsername: RawUtf8;
    fEmail: RawUtf8;
    fOtpSecret: RawUtf8;
    fOtpEnabled: Boolean;
    fLastLoginAttempt: TDateTime;
    fFailedAttempts: Integer;
  public
    /// Normalize field values (trim whitespace, etc.)
    procedure Normalize; virtual;
    
    /// Validate that all required fields are present
    // - Returns false if username, email, or secret is empty
    function HasAllNeededFields: boolean; virtual;
    
    /// Check if account is locked due to failed attempts
    // - Returns true if failed attempts >= 5
    function IsLocked: boolean; virtual;
    
    /// Reset failed attempt counter
    procedure ResetFailedAttempts;
    
    /// Increment failed attempt counter
    procedure IncrementFailedAttempts;
  published
    /// Unique username for authentication
    property Username: RawUtf8 
      read fUsername write fUsername stored AS_UNIQUE;
      
    /// User's email address
    property Email: RawUtf8 
      read fEmail write fEmail;
      
    /// Base32-encoded OTP secret
    // - Should be encrypted in production
    property OtpSecret: RawUtf8 
      read fOtpSecret write fOtpSecret;
      
    /// Whether OTP authentication is enabled for this user
    property OtpEnabled: Boolean 
      read fOtpEnabled write fOtpEnabled;
      
    /// Timestamp of last login attempt (for rate limiting)
    property LastLoginAttempt: TDateTime 
      read fLastLoginAttempt write fLastLoginAttempt;
      
    /// Count of consecutive failed authentication attempts
    property FailedAttempts: Integer 
      read fFailedAttempts write fFailedAttempts;
  end;
  
  TDomOtpUserObjArray = array of TDomOtpUser;

  /// Domain entity: OTP Authentication Log
  // - Audit trail for OTP validation attempts
  TDomOtpLog = class(TOrm)
  protected
    fUserId: TOtpUserID;
    fSuccess: Boolean;
    fIpAddress: RawUtf8;
    fUserAgent: RawUtf8;
    fTimestamp: TUnixMSTime;
  public
    /// Validate that all required fields are present
    function HasAllNeededFields: boolean; virtual;
  published
    /// Reference to user who attempted authentication
    property UserId: TOtpUserID 
      read fUserId write fUserId;
      
    /// Whether the authentication attempt succeeded
    property Success: Boolean 
      read fSuccess write fSuccess;
      
    /// IP address of authentication attempt
    property IpAddress: RawUtf8 
      read fIpAddress write fIpAddress;
      
    /// User agent string of client
    property UserAgent: RawUtf8 
      read fUserAgent write fUserAgent;
      
    /// Millisecond Unix timestamp of attempt
    property Timestamp: TUnixMSTime 
      read fTimestamp write fTimestamp;
  end;
  
  TDomOtpLogObjArray = array of TDomOtpLog;


implementation


{ TDomOtpUser }

procedure TDomOtpUser.Normalize;
begin
  TrimSelf(fUsername);
  TrimSelf(fEmail);
end;

function TDomOtpUser.HasAllNeededFields: boolean;
begin
  result := false;
  Normalize;
  if (fUsername = '') or 
     (fEmail = '') or 
     (fOtpSecret = '') then
    exit;
  result := true;
end;

function TDomOtpUser.IsLocked: boolean;
const
  MAX_FAILED_ATTEMPTS = 5;
begin
  result := fFailedAttempts >= MAX_FAILED_ATTEMPTS;
end;

procedure TDomOtpUser.ResetFailedAttempts;
begin
  fFailedAttempts := 0;
end;

procedure TDomOtpUser.IncrementFailedAttempts;
begin
  Inc(fFailedAttempts);
end;


{ TDomOtpLog }

function TDomOtpLog.HasAllNeededFields: boolean;
begin
  // IpAddress is optional (may be empty for direct/internal calls)
  result := fUserId <> 0;
end;


end.

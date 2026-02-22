unit otp.api;

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.text,
  mormot.core.rtti,
  mormot.core.interfaces;

type
  /// Result of user registration with OTP
  TUserRegistrationResult = packed record
    Success: Boolean;
    UserId: TID;
    OtpSecret: RawUtf8;
    QrCodeUrl: RawUtf8;
    ErrorMessage: RawUtf8;
  end;

  /// Result of OTP token validation
  TOtpValidationResult = packed record
    Success: Boolean;
    ErrorMessage: RawUtf8;
  end;

  /// Authentication statistics for a user
  TAuthStats = packed record
    TotalAttempts: Integer;
    SuccessfulAttempts: Integer;
    FailedAttempts: Integer;
    LastAttemptTime: TUnixMSTime;
    IsAccountLocked: Boolean;
  end;

  /// Recent authentication log entry
  TAuthLogEntry = packed record
    Timestamp: TUnixMSTime;
    Success: Boolean;
    IpAddress: RawUtf8;
    UserAgent: RawUtf8;
  end;
  
  TAuthLogEntryDynArray = array of TAuthLogEntry;

  /// OTP Authentication Service API
  // - Interface for two-factor authentication operations
  // - Can be exposed via REST, WebSockets, etc.
  IOtpAuthService = interface(IInvokable)
    ['{3B7C9E2F-4A8D-4E6B-9F1C-5D8A7B3E2C1F}']
    
    /// Register a new user with OTP authentication
    // - Generates OTP secret automatically
    // - Returns QR code URL for mobile app enrollment
    function RegisterUser(const Username, Email: RawUtf8): TUserRegistrationResult;
    
    /// Validate an OTP token for a user
    // - Logs the authentication attempt
    // - Updates user's failed attempt counter
    // - Supports both TOTP (time-based) tokens
    function ValidateToken(const Username, Token: RawUtf8; 
      const IpAddress: RawUtf8 = ''; 
      const UserAgent: RawUtf8 = ''): TOtpValidationResult;
    
    /// Get authentication statistics for a user
    function GetAuthStats(const Username: RawUtf8): TAuthStats;
    
    /// Get recent authentication log entries for a user
    function GetRecentLogs(const Username: RawUtf8; 
      MaxCount: Integer = 10): TAuthLogEntryDynArray;
    
    /// Reset failed authentication attempts for a user
    // - Unlocks the account if it was locked
    function ResetFailedAttempts(const Username: RawUtf8): Boolean;
    
    /// Enable or disable OTP authentication for a user
    function SetOtpEnabled(const Username: RawUtf8; Enabled: Boolean): Boolean;
  end;


implementation

initialization
  // Register DTOs for JSON serialization
  Rtti.RegisterFromText(TypeInfo(TUserRegistrationResult),
    'Success:boolean UserId:TID OtpSecret:RawUtf8 ' +
    'QrCodeUrl:RawUtf8 ErrorMessage:RawUtf8');
    
  Rtti.RegisterFromText(TypeInfo(TOtpValidationResult),
    'Success:boolean ErrorMessage:RawUtf8');
    
  Rtti.RegisterFromText(TypeInfo(TAuthStats),
    'TotalAttempts:integer SuccessfulAttempts:integer ' +
    'FailedAttempts:integer LastAttemptTime:TUnixMSTime ' +
    'IsAccountLocked:boolean');
    
  Rtti.RegisterFromText(TypeInfo(TAuthLogEntry),
    'Timestamp:TUnixMSTime Success:boolean ' +
    'IpAddress:RawUtf8 UserAgent:RawUtf8');
  
  // Register interface for service resolution
  TInterfaceFactory.RegisterInterfaces([
    TypeInfo(IOtpAuthService)
  ]);

end.

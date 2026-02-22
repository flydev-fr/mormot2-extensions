unit otp.infra;

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.text,
  otp.domain;

type
  /// Persistence abstraction for OTP system  
  IOtpPersistence = interface(IInvokable)
    ['{8F2A4D6C-1B3E-4F7A-9C5D-2E8B6A4F1C3D}']
    
    /// Check if a username already exists
    // - Returns true if user with given username exists
    function UserExists(const Username: RawUtf8): boolean;
    
    /// Retrieve user by ID
    // - Returns nil if user not found
    // - Caller is responsible for freeing the returned instance
    function GetUser(UserId: TOtpUserID): TDomOtpUser;
    
    /// Retrieve user by username
    // - Returns nil if user not found
    // - Caller is responsible for freeing the returned instance
    function GetUserByUsername(const Username: RawUtf8): TDomOtpUser;
    
    /// Create a new user
    // - Returns the ID of the created user, or 0 on failure
    function CreateUser(User: TDomOtpUser): TOtpUserID;
    
    /// Update existing user
    // - Returns true on success
    function UpdateUser(User: TDomOtpUser): boolean;
    
    /// Log an authentication attempt
    // - Returns the ID of the created log entry, or 0 on failure
    function LogAttempt(Log: TDomOtpLog): TOtpLogID;
    
    /// Count authentication attempts for a user
    // - Returns total number of log entries for given user
    function CountLogs(UserId: TOtpUserID): Integer;
    
    /// Get recent authentication attempts for a user
    // - Returns array of recent logs (newest first), limited by MaxCount
    // - Caller is responsible for freeing the returned instances
    function GetRecentLogs(UserId: TOtpUserID; MaxCount: Integer): TDomOtpLogObjArray;
  end;


implementation

end.

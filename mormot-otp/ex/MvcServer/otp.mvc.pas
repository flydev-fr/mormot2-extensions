unit otp.mvc;

{$I mormot.defines.inc}

/// MVC Controller for the OTP Authentication Web Application
// - Demonstrates mORMot2 MVC with TOTP two-factor authentication

interface

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.json,
  mormot.core.data,
  mormot.core.variants,
  mormot.core.rtti,
  mormot.core.mvc,
  mormot.rest.core,
  mormot.rest.server,
  mormot.rest.mvc,
  mormot.ext.otp,
  otp.domain,
  otp.infra,
  otp.infra.orm,
  otp.api,
  otp.api.impl;

type
  /// Session data stored as AES-GCM-128 signed client-side cookie
  // - No server-side storage needed; the cookie is tamper-evident
  TOtpCookieData = packed record
    Username: RawUtf8;
    UserId:   integer;
  end;

  IOtpMvcApp = interface(IMvcApplication)
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']

    /// GET /otp/login — displays the TOTP login form
    // - ErrorMsg is forwarded from DoLogin on failure (query string param)
    procedure Login(const ErrorMsg: RawUtf8);

    /// POST /otp/doLogin — validates username + TOTP token
    // - On success: creates session cookie and redirects to Dashboard
    // - On failure: redirects back to Login with error message
    function DoLogin(const Username, Token: RawUtf8): TMvcAction;

    /// GET /otp/dashboard — protected page, requires active session
    // - Redirects to Login if no valid session cookie is present
    procedure Dashboard(out Info: variant);

    /// GET /otp/logout — destroys the session cookie
    function Logout: TMvcAction;

    /// GET /otp/register — displays the user registration form
    // - ErrorMsg shows validation errors; OtpSecret/OtpUrl shown after success
    procedure Register(const OtpSecret, OtpUrl: RawUtf8; out Scope: variant);

    /// POST /otp/doRegister — creates a new user account with OTP secret
    // - On success: redirects to Register showing the OTP enrollment URL
    // - On failure: redirects to Register with error message
    function DoRegister(const Username, Email: RawUtf8): TMvcAction;
  end;

  /// MVC Application implementing IOtpMvcApp
  // - Wires the OTP service layer into the mORMot MVC framework
  TOtpMvcApp = class(TMvcApplicationRest, IOtpMvcApp)
  private
    fPersistence:     IOtpPersistence;
    fAuthService:     IOtpAuthService;
    fAuthServiceImpl: TOtpAuthService; // concrete ref (for potential direct access)
  protected
    /// Injects session info into every view's data context under 'main'
    // - Templates access it as {{main.session.Username}} etc.
    procedure GetViewInfo(MethodIndex: integer; out info: variant); override;
  public
    /// Initialize and wire all layers; call after construction
    // - aServer:          the REST/ORM server (owns the SQLite database)
    // - aTemplatesFolder: path to the Views/ folder with Mustache .html files
    // - aPersistence:     IOtpPersistence providing user/log storage
    procedure Start(aServer: TRest; const aTemplatesFolder: TFileName;
      aPersistence: IOtpPersistence); reintroduce;

    // IOtpMvcApp - published views
    procedure Default(var Scope: variant);
    procedure Login(const ErrorMsg: RawUtf8);
    function DoLogin(const Username, Token: RawUtf8): TMvcAction;
    procedure Dashboard(out Info: variant);
    function Logout: TMvcAction;
    procedure Register(const OtpSecret, OtpUrl: RawUtf8; out Scope: variant);
    function DoRegister(const Username, Email: RawUtf8): TMvcAction;
  end;


implementation

{ TOtpMvcApp }

procedure TOtpMvcApp.Start(aServer: TRest; const aTemplatesFolder: TFileName;
  aPersistence: IOtpPersistence);
var
  run: TMvcRunOnRestServer;
begin
  fPersistence     := aPersistence;
  fAuthServiceImpl := TOtpAuthService.Create(
    aPersistence,
    TOtpFactory.CreateDefault,
    TOtpFactory.CreateSecretGenerator);
  fAuthService := fAuthServiceImpl;

  // Wire the MVC framework: registers IOtpMvcApp methods as URI routes
  inherited Start(aServer, TypeInfo(IOtpMvcApp));

  // Create Mustache-based view runner pointing at our Views/ folder
  run := TMvcRunOnRestServer.Create(self, aTemplatesFolder);
  fMainRunner := run; // owned by this application instance
end;

procedure TOtpMvcApp.GetViewInfo(MethodIndex: integer; out info: variant);
begin
  inherited GetViewInfo(MethodIndex, info);
  // Inject session data so every template can check {{main.session}}
  _ObjAddProps([
    'session', CurrentSession.CheckAndRetrieveInfo(TypeInfo(TOtpCookieData))
  ], info);
end;


{ IOtpMvcApp — Controller Methods }

procedure TOtpMvcApp.Default(var Scope: variant);
var
  session: TOtpCookieData;
begin
  // If logged in, redirect directly to dashboard
  if CurrentSession.CheckAndRetrieve(@session, TypeInfo(TOtpCookieData)) > 0 then
    RedirectView('Dashboard', []);
  // Otherwise Default.html shows login/register links
end;

procedure TOtpMvcApp.Login(const ErrorMsg: RawUtf8);
var
  session: TOtpCookieData;
begin
  // Bounce already-logged-in users to the dashboard
  if CurrentSession.CheckAndRetrieve(@session, TypeInfo(TOtpCookieData)) > 0 then
    RedirectView('Dashboard', []);
  // Otherwise Login.html renders with {{ErrorMsg}} from query string
end;

function TOtpMvcApp.DoLogin(const Username, Token: RawUtf8): TMvcAction;
var
  vr:      TOtpValidationResult;
  user:    TDomOtpUser;
  session: TOtpCookieData;
begin
  if (Username = '') or (Token = '') then
  begin
    GotoView(result, 'Login', ['ErrorMsg', 'Username and token are required']);
    exit;
  end;

  vr := fAuthService.ValidateToken(Username, Token);
  if not vr.Success then
  begin
    GotoView(result, 'Login', ['ErrorMsg', vr.ErrorMessage]);
    exit;
  end;

  // Build session record from the validated user
  user := fPersistence.GetUserByUsername(Username);
  if user = nil then
  begin
    GotoView(result, 'Login', ['ErrorMsg', 'User not found']);
    exit;
  end;
  try
    session.Username := Username;
    session.UserId   := integer(user.ID); // IDs are small for a demo
  finally
    user.Free;
  end;
  CurrentSession.Initialize(@session, TypeInfo(TOtpCookieData));
  GotoView(result, 'Dashboard', []);
end;

procedure TOtpMvcApp.Dashboard(out Info: variant);
var
  session: TOtpCookieData;
  stats:   TAuthStats;
  logs:    TAuthLogEntryDynArray;
  logsArr: TDocVariantData;
  i:       integer;
begin
  // Require a valid session
  if CurrentSession.CheckAndRetrieve(@session, TypeInfo(TOtpCookieData)) = 0 then
  begin
    RedirectView('Login', ['ErrorMsg', 'Please log in to access the dashboard']);
    exit;
  end;

  stats := fAuthService.GetAuthStats(session.Username);
  logs  := fAuthService.GetRecentLogs(session.Username, 10);

  // Convert log entries to a DocVariant array for Mustache rendering
  logsArr.InitArray([], JSON_OPTIONS_FAST);
  for i := 0 to High(logs) do
    logsArr.AddItem(_ObjFast([
      'Timestamp', logs[i].Timestamp,
      'Success',   logs[i].Success,
      'IpAddress', logs[i].IpAddress,
      'UserAgent', logs[i].UserAgent
    ]));

  _ObjAddProps([
    'Username',           session.Username,
    'TotalAttempts',      stats.TotalAttempts,
    'SuccessfulAttempts', stats.SuccessfulAttempts,
    'FailedAttempts',     stats.FailedAttempts,
    'IsAccountLocked',    stats.IsAccountLocked,
    'RecentLogs',         variant(logsArr)
  ], info);
end;

function TOtpMvcApp.Logout: TMvcAction;
begin
  CurrentSession.Finalize;
  GotoDefault(result);
end;

procedure TOtpMvcApp.Register(const OtpSecret, OtpUrl: RawUtf8; out Scope: variant);
begin
  SetVariantNull(Scope);

  if (OtpSecret <> '') and (OtpUrl <> '') then
    _ObjAddProps(['OtpSecret', OtpSecret, 'OtpUrl', OtpUrl], Scope);
end;

function TOtpMvcApp.DoRegister(const Username, Email: RawUtf8): TMvcAction;
var
  reg: TUserRegistrationResult;
begin
  if (Username = '') or (Email = '') then
  begin
    GotoError(result, 'Username and email are required');
    exit;
  end;

  reg := fAuthService.RegisterUser(Username, Email);
  if reg.Success then
    GotoView(result, 'Register', [
      'OtpSecret', reg.OtpSecret,
      'OtpUrl',    reg.QrCodeUrl
    ])
  else
    GotoError(result, reg.ErrorMessage);
end;


initialization
  // Register session record for binary/JSON serialization in cookies
  Rtti.RegisterFromText(TypeInfo(TOtpCookieData),
    'username:RawUtf8 user_id:integer');

end.

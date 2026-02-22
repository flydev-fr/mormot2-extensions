program OtpMvcServer;

{$I mormot.defines.inc}

{$ifdef OSWINDOWS}
  {$apptype console}
{$endif}

{$define WITH_LOGS}

uses
  {$I mormot.uses.inc}
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.log,
  mormot.rest.http.server,
  mormot.db.raw.sqlite3.static,
  mormot.ext.otp,
  otp.domain    in '../InterfaceService/otp.domain.pas',
  otp.infra     in '../InterfaceService/otp.infra.pas',
  otp.infra.orm in '../InterfaceService/otp.infra.orm.pas',
  otp.api       in '../InterfaceService/otp.api.pas',
  otp.api.impl  in '../InterfaceService/otp.api.impl.pas',
  otp.mvc       in 'otp.mvc.pas';

const
  HTTP_PORT = '8093';

var
  persistImpl: TOtpPersistence;
  persistence:  IOtpPersistence;
  application:  TOtpMvcApp;
  httpServer:   TRestHttpServer;
  viewsFolder:  TFileName;

begin
{$ifdef WITH_LOGS}
  with TSynLog.Family do
  begin
    Level := LOG_VERBOSE;
    EchoToConsoleBackground := True;
    EchoToConsole := LOG_VERBOSE;
  end;
{$endif}

  WriteLn('=============================================================');
  WriteLn('OTP Authentication MVC Web Server');
  WriteLn('=============================================================');
  WriteLn;

  // Layer 1: Persistence (owns the SQLite TRestServerDB internally)
  WriteLn('Initializing persistence layer (SQLite)...');
  // 'otp' becomes the URL prefix: /otp/login, /otp/dashboard, etc.
  persistImpl := TOtpPersistence.Create('otpmvc.db', 'otp');
  persistence := persistImpl; // interface ref keeps object alive

  // Layer 2 + 3: MVC Application (wires auth service + Mustache views)
  WriteLn('Starting MVC application...');
  application := TOtpMvcApp.Create;
  try
    // Locate the Views/ folder: try beside the exe, then exe/Views subdir
    if not DirectoryExistsMake(
        [Executable.ProgramFilePath, 'Views'], @viewsFolder) then
      DirectoryExistsMake(
        [Executable.ProgramFilePath, 'exe', 'Views'], @viewsFolder);

    // Wire everything: registers IOtpMvcApp routes on persistImpl.Server
    application.Start(persistImpl.Server, viewsFolder, persistence);

    // Layer 4: HTTP server — uses the same TRestServerDB as the MVC app
    WriteLn('Starting HTTP server on port ', HTTP_PORT, '...');
    httpServer := TRestHttpServer.Create(
      HTTP_PORT, [persistImpl.Server], '+', HTTP_DEFAULT_MODE);
    try
      // Redirect bare / and /otp to the Default controller action
      httpServer.RootRedirectToURI('otp/default');
      persistImpl.Server.RootRedirectGet := 'otp/default';
      httpServer.AccessControlAllowOrigin := '*';

      WriteLn;
      WriteLn('MVC server running on http://localhost:', HTTP_PORT);
      WriteLn;
      WriteLn('Available pages:');
      WriteLn('  http://localhost:', HTTP_PORT, '/              → welcome page');
      WriteLn('  http://localhost:', HTTP_PORT, '/otp/register  → create account');
      WriteLn('  http://localhost:', HTTP_PORT, '/otp/login     → TOTP login');
      WriteLn('  http://localhost:', HTTP_PORT, '/otp/dashboard → auth statistics');
      WriteLn('  http://localhost:', HTTP_PORT, '/otp/mvc-info  → MVC debug info');
      WriteLn;
      WriteLn('Quick start:');
      WriteLn('  1. Open /otp/register and create an account');
      WriteLn('  2. Copy the otpauth:// URL into Google Authenticator or Authy');
      WriteLn('  3. Open /otp/login and enter your username + 6-digit TOTP code');
      WriteLn;
      WriteLn('Press [Enter] to stop the server.');
      WriteLn;

      ReadLn;

      WriteLn('Shutting down...');
    finally
      httpServer.Free;
    end;
  finally
    application.Free;
    persistence := nil; // releases TOtpPersistence (and its TRestServerDB)
  end;

  WriteLn('Bye!');
end.

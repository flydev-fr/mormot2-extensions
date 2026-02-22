program OtpServer;

{$I mormot.defines.inc}

{$APPTYPE CONSOLE}

uses
  {$I mormot.uses.inc}
  System.SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.log,
  mormot.db.raw.sqlite3.static,
  mormot.rest.http.server,
  mormot.ext.otp,
  otp.domain    in 'otp.domain.pas',
  otp.infra     in 'otp.infra.pas',
  otp.infra.orm in 'otp.infra.orm.pas',
  otp.api       in 'otp.api.pas',
  otp.api.impl  in 'otp.api.impl.pas';

var
  // Typed references needed for server wiring (no unsafe interface cast)
  PersistImpl:     TOtpPersistence;
  AuthServiceImpl: TOtpAuthService;
  // Interface references keep the objects alive through ref-counting
  Persistence:  IOtpPersistence;
  OtpProvider:  IOtpProvider;
  SecretGen:    ISecretGenerator;
  AuthService:  IOtpAuthService;
  // HTTP server
  HttpServer: TRestHttpServer;

begin
  try
    TSynLog.Family.Level := LOG_VERBOSE;

    WriteLn('=============================================================');
    WriteLn('OTP Authentication Server - Clean Architecture');
    WriteLn('=============================================================');
    WriteLn;

    // Layer 1: Infrastructure — SQLite persistence
    WriteLn('Initializing persistence layer...');
    PersistImpl := TOtpPersistence.Create('otp.db');
    Persistence := PersistImpl; // interface ref keeps it alive

    // Layer 2: Domain — OTP provider + secret generator
    WriteLn('Initializing OTP provider...');
    OtpProvider := TOtpFactory.CreateDefault;
    SecretGen   := TOtpFactory.CreateSecretGenerator;

    // Layer 3: Application — service wired with DI
    WriteLn('Creating authentication service...');
    AuthServiceImpl := TOtpAuthService.Create(Persistence, OtpProvider, SecretGen);
    AuthService := AuthServiceImpl; // interface ref keeps it alive

    // Layer 4: Presentation — HTTP REST server
    WriteLn('Starting HTTP server on port 8080...');
    HttpServer := TRestHttpServer.Create(
      '8080', [PersistImpl.Server], '+', HTTP_DEFAULT_MODE);
    try
      // Register the service as a singleton on the inner REST server
      PersistImpl.Server.ServiceDefine(AuthServiceImpl, [IOtpAuthService]);
      HttpServer.AccessControlAllowOrigin := '*'; // CORS for testing

      WriteLn;
      WriteLn('Server is running!');
      WriteLn;
      WriteLn('Available endpoints:');
      WriteLn('  POST http://localhost:8080/root/OtpAuthService.RegisterUser');
      WriteLn('       { "username": "john", "email": "john@example.com" }');
      WriteLn;
      WriteLn('  POST http://localhost:8080/root/OtpAuthService.ValidateToken');
      WriteLn('       { "username": "john", "token": "123456" }');
      WriteLn;
      WriteLn('  GET  http://localhost:8080/root/OtpAuthService.GetAuthStats');
      WriteLn('       ?username=john');
      WriteLn;
      WriteLn('  GET  http://localhost:8080/root/OtpAuthService.GetRecentLogs');
      WriteLn('       ?username=john&maxCount=10');
      WriteLn;
      WriteLn('  POST http://localhost:8080/root/OtpAuthService.ResetFailedAttempts');
      WriteLn('       { "username": "john" }');
      WriteLn;
      WriteLn('  POST http://localhost:8080/root/OtpAuthService.SetOtpEnabled');
      WriteLn('       { "username": "john", "enabled": false }');
      WriteLn;
      WriteLn('Press [Enter] to stop the server.');
      WriteLn;

      ReadLn;

      WriteLn('Shutting down...');
    finally
      HttpServer.Free;
    end;

    WriteLn('Server stopped.');

  except
    on E: Exception do
    begin
      WriteLn('ERROR: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

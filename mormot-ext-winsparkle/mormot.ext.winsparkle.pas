unit mormot.ext.winsparkle;

interface

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.interfaces,
  mormot.core.log;

const
  DefaultSparkleCheckInterval = 86400; // 24 hours

type
  /// <summary>
  /// Interface for receiving callback events from WinSparkle.
  /// Implement this interface and pass it to IWinSparkleUpdater.SetEventHandler.
  /// Note: These methods may be called from different threads. Ensure your
  /// implementation is thread-safe or marshals calls to the main thread if
  /// interacting with UI elements (e.g., using TThread.Queue).
  /// </summary>
  IWinSparkleEvents = interface(IInvokable)
  ['{DAF1C1B8-B6D9-4A8E-8B4C-1D2A9A0F3C8E}']
    /// <summary>Called when WinSparkle encounters an error.</summary>
    procedure OnError;
    /// <summary>
    /// Called when WinSparkle wants to shutdown the application for update.
    /// Return False to prevent the shutdown, True to allow it.
    /// </summary>
    function CanShutdown: Boolean;
    /// <summary>Called when WinSparkle requests application shutdown.</summary>
    procedure OnShutdownRequest;
    /// <summary>Called when an update is found.</summary>
    procedure OnDidFindUpdate;
    /// <summary>Called when no update is found.</summary>
    procedure OnDidNotFindUpdate;
    /// <summary>Called when the user cancels the update process.</summary>
    procedure OnUpdateCancelled;
    // Add other callbacks here if needed (e.g., user runs installer)
  end;

  /// <summary>Interface for wrapping the WinSparkle update client</summary>
  IWinSparkleUpdater = interface(IInvokable)
  ['{6398AB4C-BF92-433F-995A-C76F765EAF2D}']
    /// <summary>Configure the application info used by WinSparkle.</summary>
    procedure ConfigureApp(const CompanyName, AppName, AppVersion: RawUtf8);
    /// <summary>Define the URL of the AppCast feed (must be HTTPS).</summary>
    procedure SetAppcastURL(const URL: RawUtf8);
    /// <summary>Set an explicit build version.</summary>
    procedure SetBuildVersion(const Build: RawUtf8);
    /// <summary>Set registry path to override default storage location.</summary>
    procedure SetRegistryPath(const Path: RawUtf8);
    /// <summary>Set preferred language (e.g. 'en', 'fr').</summary>
    procedure SetLanguage(const Lang: RawUtf8);
    /// <summary>Enable or disable automatic update checks (with optional interval in seconds).</summary>
    procedure EnableAutoCheck(Auto: boolean; IntervalSeconds: integer = DefaultSparkleCheckInterval);
    /// <summary>Trigger a manual update check.</summary>
    procedure CheckUpdates(Silent: boolean = false; AutoInstall: boolean = false);
    /// <summary>Set the handler for WinSparkle callback events.</summary>
    procedure SetEventHandler(const Handler: IWinSparkleEvents);
    /// <summary>Get the last update check timestamp (Unix timestamp as Int64).</summary>
    function GetLastCheckTime: Int64;
    /// <summary>Get the current update check interval in seconds.</summary>
    function GetUpdateInterval: integer;
  end;

function CreateWinSparkleUpdater: IWinSparkleUpdater;

implementation

const
  DLL = 'WinSparkle.dll';

// --- WinSparkle Callback Type Definitions ---
type
  TWinSparkleCallbackVoid = procedure; cdecl;
  TWinSparkleCallbackCanShutdown = function: LongBool; cdecl;
  // Add other callback types if WinSparkle defines them differently

// --- WinSparkle Function Imports ---
procedure win_sparkle_init; cdecl; external DLL;
procedure win_sparkle_cleanup; cdecl; external DLL;
procedure win_sparkle_set_app_details(company_name, app_name, app_version: PWideChar); cdecl; external DLL;
procedure win_sparkle_set_appcast_url(url: PAnsiChar); cdecl; external DLL;
procedure win_sparkle_set_app_build_version(build: PWideChar); cdecl; external DLL;
procedure win_sparkle_set_registry_path(path: PAnsiChar); cdecl; external DLL;
procedure win_sparkle_set_lang(lang: PAnsiChar); cdecl; external DLL;
procedure win_sparkle_set_automatic_check_for_updates(state: LongBool); cdecl; external DLL;
procedure win_sparkle_set_update_check_interval(interval: Int32); cdecl; external DLL;
function win_sparkle_get_update_check_interval: Int32; cdecl; external DLL;
function win_sparkle_get_last_check_time: Int64; cdecl; external DLL; // Assuming it returns time_t (Int64)
procedure win_sparkle_check_update_with_ui; cdecl; external DLL;
procedure win_sparkle_check_update_with_ui_and_install; cdecl; external DLL;
procedure win_sparkle_check_update_without_ui; cdecl; external DLL;

// Callback Setters
procedure win_sparkle_set_error_callback(callback: TWinSparkleCallbackVoid); cdecl; external DLL;
procedure win_sparkle_set_can_shutdown_callback(callback: TWinSparkleCallbackCanShutdown); cdecl; external DLL;
procedure win_sparkle_set_shutdown_request_callback(callback: TWinSparkleCallbackVoid); cdecl; external DLL;
procedure win_sparkle_set_did_find_update_callback(callback: TWinSparkleCallbackVoid); cdecl; external DLL;
procedure win_sparkle_set_did_not_find_update_callback(callback: TWinSparkleCallbackVoid); cdecl; external DLL;
procedure win_sparkle_set_update_cancelled_callback(callback: TWinSparkleCallbackVoid); cdecl; external DLL;
// Add other callback setters if available/needed

// --- Global Variable for the Single Event Handler ---
// Assumes only one active WinSparkle instance/session per application.
var
  gEventHandler: IWinSparkleEvents = nil;

// --- Bridge Functions (Called by WinSparkle, Forward to Handler) ---

procedure DoOnError; cdecl;
begin
  // Important: Callbacks can happen on any thread.
  // Log directly or let the handler manage threading.
  TSynLog.Add.Log(sllDebug, 'WinSparkle Callback: OnError');
  if Assigned(gEventHandler) then
    gEventHandler.OnError; // Handler must be thread-safe
end;

function DoOnCanShutDown: LongBool; cdecl;
begin
  TSynLog.Add.Log(sllDebug, 'WinSparkle Callback: CanShutdown Check');
  if Assigned(gEventHandler) then
    Result := LongBool(gEventHandler.CanShutdown) // Handler must be thread-safe
  else
    Result := True; // Default to allowing shutdown if no handler
  TSynLog.Add.Log(sllDebug, 'WinSparkle Callback: CanShutdown Result: %', [Result]);
end;

procedure DoOnShutdownRequest; cdecl;
begin
  TSynLog.Add.Log(sllDebug, 'WinSparkle Callback: OnShutdownRequest');
  if Assigned(gEventHandler) then
    gEventHandler.OnShutdownRequest; // Handler must be thread-safe
end;

procedure DoOnDidFindUpdate; cdecl;
begin
  TSynLog.Add.Log(sllDebug, 'WinSparkle Callback: OnDidFindUpdate');
  if Assigned(gEventHandler) then
    gEventHandler.OnDidFindUpdate; // Handler must be thread-safe
end;

procedure DoOnDidNotFindUpdate; cdecl;
begin
  TSynLog.Add.Log(sllDebug, 'WinSparkle Callback: OnDidNotFindUpdate');
  if Assigned(gEventHandler) then
    gEventHandler.OnDidNotFindUpdate; // Handler must be thread-safe
end;

procedure DoOnUpdateCancelled; cdecl;
begin
  TSynLog.Add.Log(sllDebug, 'WinSparkle Callback: OnUpdateCancelled');
  if Assigned(gEventHandler) then
    gEventHandler.OnUpdateCancelled; // Handler must be thread-safe
end;

// --- TWinSparkleUpdater Implementation ---
type
  TWinSparkleUpdater = class(TInterfacedObject, IWinSparkleUpdater)
  private
    fInitialized: Boolean;
    fEventHandler: IWinSparkleEvents; // Store the handler instance
    procedure CheckInitialized;
    procedure RegisterCallbacks; // Helper to set callbacks
  public
    constructor Create;
    destructor Destroy; override;
    procedure ConfigureApp(const CompanyName, AppName, AppVersion: RawUtf8);
    procedure SetAppcastURL(const URL: RawUtf8);
    procedure SetBuildVersion(const Build: RawUtf8);
    procedure SetRegistryPath(const Path: RawUtf8);
    procedure SetLanguage(const Lang: RawUtf8);
    procedure EnableAutoCheck(Auto: boolean; IntervalSeconds: integer = DefaultSparkleCheckInterval);
    procedure CheckUpdates(Silent: boolean = false; AutoInstall: boolean = false);
    procedure SetEventHandler(const Handler: IWinSparkleEvents);
    function GetLastCheckTime: Int64;
    function GetUpdateInterval: integer;
  end;

function CreateWinSparkleUpdater: IWinSparkleUpdater;
begin
  Result := TWinSparkleUpdater.Create;
end;

{ TWinSparkleUpdater }

constructor TWinSparkleUpdater.Create;
begin
  inherited Create;
  fEventHandler := nil; // Ensure handler is nil initially
  try
    win_sparkle_init;
    fInitialized := True;
    TSynLog.Add.Log(sllInfo, 'WinSparkle initialized successfully.');
    // Optionally register default (nil) callbacks here, or wait for SetEventHandler
    // RegisterCallbacks; // Can be called here if desired
  except
    on E: Exception do
    begin
      fInitialized := False;
      TSynLog.Add.Log(sllError, 'WinSparkle initialization failed: %', [E.Message]);
      raise; // Re-raise
    end;
  end;
end;

destructor TWinSparkleUpdater.Destroy;
begin
  // Clear the global handler reference *before* cleanup,
  // just in case cleanup triggers a final callback (unlikely but safe).
  if Assigned(fEventHandler) and (gEventHandler = fEventHandler) then
     gEventHandler := nil;

  if fInitialized then
  begin
    // Optionally unregister callbacks explicitly if WinSparkle provides such functions,
    // otherwise cleanup should handle it.
    // win_sparkle_set_error_callback(nil); // Example if unregister needed
    win_sparkle_cleanup;
    TSynLog.Add.Log(sllInfo, 'WinSparkle cleaned up.');
  end;
  inherited Destroy;
end;

procedure TWinSparkleUpdater.CheckInitialized;
begin
  if not fInitialized then
    // Use EInvalidOperation from SysUtils unit
    raise EInvalidOpException.Create('WinSparkle updater is not initialized.');
end;

procedure TWinSparkleUpdater.RegisterCallbacks;
begin
  // Pass the addresses of our global bridge functions to WinSparkle
  win_sparkle_set_error_callback(@DoOnError);
  win_sparkle_set_can_shutdown_callback(@DoOnCanShutDown);
  win_sparkle_set_shutdown_request_callback(@DoOnShutdownRequest);
  win_sparkle_set_did_find_update_callback(@DoOnDidFindUpdate);
  win_sparkle_set_did_not_find_update_callback(@DoOnDidNotFindUpdate);
  win_sparkle_set_update_cancelled_callback(@DoOnUpdateCancelled);
  // Register others if needed
  TSynLog.Add.Log(sllDebug, 'WinSparkle callbacks registered.');
end;

procedure TWinSparkleUpdater.SetEventHandler(const Handler: IWinSparkleEvents);
begin
  CheckInitialized;
  // Store the handler instance
  fEventHandler := Handler;
  // Update the global handler reference
  gEventHandler := fEventHandler; // Assign the new handler (can be nil)

  // Register the bridge functions with WinSparkle now that we might have a handler
  // (Or re-register them to ensure they point correctly if called multiple times)
  RegisterCallbacks;

  if Assigned(Handler) then
    TSynLog.Add.Log(sllInfo, 'WinSparkle event handler set.')
  else
    TSynLog.Add.Log(sllInfo, 'WinSparkle event handler cleared.');
end;

procedure TWinSparkleUpdater.ConfigureApp(const CompanyName, AppName, AppVersion: RawUtf8);
begin
  CheckInitialized;
  win_sparkle_set_app_details(
    PWideChar(Utf8ToString(CompanyName)),
    PWideChar(Utf8ToString(AppName)),
    PWideChar(Utf8ToString(AppVersion)));
end;

procedure TWinSparkleUpdater.SetAppcastURL(const URL: RawUtf8);
var
  utf8: UTF8String;
begin
  CheckInitialized;
  utf8 := UTF8String(URL);
  win_sparkle_set_appcast_url(PAnsiChar(utf8));
end;

procedure TWinSparkleUpdater.SetBuildVersion(const Build: RawUtf8);
begin
  CheckInitialized;
  win_sparkle_set_app_build_version(PWideChar(Utf8ToString(Build)));
end;

procedure TWinSparkleUpdater.SetRegistryPath(const Path: RawUtf8);
var
  utf8: UTF8String;
begin
  CheckInitialized;
  utf8 := UTF8String(Path);
  win_sparkle_set_registry_path(PAnsiChar(utf8));
end;

procedure TWinSparkleUpdater.SetLanguage(const Lang: RawUtf8);
var
  utf8: UTF8String;
begin
  CheckInitialized;
  utf8 := UTF8String(Lang);
  win_sparkle_set_lang(PAnsiChar(utf8));
end;

procedure TWinSparkleUpdater.EnableAutoCheck(Auto: boolean; IntervalSeconds: integer);
begin
  CheckInitialized;
  win_sparkle_set_automatic_check_for_updates(LongBool(Auto));
  win_sparkle_set_update_check_interval(IntervalSeconds);
end;

procedure TWinSparkleUpdater.CheckUpdates(Silent, AutoInstall: boolean);
begin
  CheckInitialized;
  TSynLog.Add.Log(sllInfo, 'WinSparkle checking for updates (Silent: %, AutoInstall: %)', [Silent, AutoInstall]);
  if AutoInstall then
    win_sparkle_check_update_with_ui_and_install
  else if Silent then
    win_sparkle_check_update_without_ui
  else
    win_sparkle_check_update_with_ui;
end;

function TWinSparkleUpdater.GetLastCheckTime: Int64;
begin
  CheckInitialized;
  Result := win_sparkle_get_last_check_time;
end;

function TWinSparkleUpdater.GetUpdateInterval: integer;
begin
  CheckInitialized;
  Result := win_sparkle_get_update_check_interval;
end;

initialization
  // Ensure the global handler is nil when the application starts
  gEventHandler := nil;

finalization
  // Ensure the global handler is nil when the application terminates
  gEventHandler := nil; // Should be handled in Destroy

end.

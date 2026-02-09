# WinSparkle Integration 

This unit provides a high-level object-oriented wrapper around the [WinSparkle](https://winsparkle.org/) library (`WinSparkle.dll`) for integrating application update checks into Delphi/Lazarus applications using the mORMot 2 framework.

It simplifies the usage of WinSparkle's C API by providing:

*   An interface-based approach (`IWinSparkleUpdater`).
*   Automatic initialization and cleanup.
*   Support for WinSparkle callbacks via a dedicated event interface (`IWinSparkleEvents`).
*   Getter methods for retrieving information like the last check time.

## Features

*   Easy initialization and cleanup managed by the object lifetime.
*   Configuration of application details (Company, Name, Version).
*   Setting the Appcast URL.
*   Setting custom build versions and registry paths.
*   Language selection for WinSparkle UI.
*   Enabling/disabling automatic update checks with configurable intervals.
*   Manual update checks (silent, with UI, or with UI and auto-install).
*   Callback mechanism to react to WinSparkle events (update found, cancelled, errors, etc.).
*   Methods to retrieve the last check time and update interval.
*   Logging of initialization status and errors using `TSynLog`.

## Signing updates

Please read the the doc on winsparkle repo: ["Companion tool"](https://github.com/vslavik/winsparkle?tab=readme-ov-file#signing-updates)

## Requirements

*   Delphi 10.x and up.
*   [mORMot 2 Framework](https://github.com/synopse/mORMot2).
*   `WinSparkle.dll` (Version 0.9.2 or later recommended). Download the appropriate 32-bit or 64-bit DLL from the [WinSparkle Releases page](https://github.com/vslavik/winsparkle/releases).
*   Only the DLL released on this repo provide **Silent** install feature

## Installation

1.  **Add the Unit:** Place the `mormot.ext.winsparkle.pas` file into your project's source path.
2.  **Get the DLL:** Download the correct `WinSparkle.dll` (32-bit or 64-bit) matching your application's target platform.
3.  **Deploy the DLL:** Place the `WinSparkle.dll` in the same directory as your application's executable (`.exe`). The wrapper uses static linking (`external DLL`), so the DLL must be present for the application to load.

## Basic Usage

```delphi
program MyApp;

uses
  SysUtils,
  mormot.core.log, // For TSynLog
  mormot.ext.winsparkle;

var
  Updater: IWinSparkleUpdater;
  Log: TSynLog; // Example: Use application log instance

begin
  // Initialize logging
  with TSynLog.Family do
  begin
    Level := LOG_VERBOSE; // Show Info/Debug messages from the wrapper
    EchoToConsole := LOG_VERBOSE;
    EchoToConsoleBackground := True; // Log to console for testing
  end;

  // Create the updater instance (handles win_sparkle_init)
  try
    Updater := CreateWinSparkleUpdater;
  except
    on E: Exception do
    begin
      // Initialization failed (DLL missing, init function error)
      TSynLog.Add.Log(sllFatal, 'Failed to initialize WinSparkle: %', [E.Message]);
      Exit; // Cannot proceed
    end;
  end;

  // Configure WinSparkle (must be done before checking)
  try
    Updater.ConfigureApp('My Company Name', 'My Awesome App', '1.0.0');
    Updater.SetAppcastURL('https://myupdateserver.com/myapp/appcast.xml'); // Use HTTPS!

    // Optional: Configure other settings if needed
    // Updater.SetLanguage('en');
    // Updater.EnableAutoCheck(True, DefaultSparkleCheckInterval); // Check once a day

    // Perform an update check (with default UI)
    Updater.CheckUpdates;

    // --- Your application logic continues here ---

    // Example: Get last check time
    TSynLog.Add.Log(sllInfo, 'Last update check time (Unix timestamp): %', [Updater.GetLastCheckTime]);

  except
    on E: Exception do
    begin
      // Handle errors during configuration or check
      TSynLog.Add.Log(sllError, 'WinSparkle operation failed: %', [E.Message]);
    end;
  end;

  // Updater instance goes out of scope here (or when application exits).
  // Its destructor automatically calls win_sparkle_cleanup.

  // --- Application runs ...
end.
```

## API Reference

### `CreateWinSparkleUpdater: IWinSparkleUpdater;`

Factory function to create and initialize the WinSparkle updater instance.

*   **Returns:** An `IWinSparkleUpdater` interface reference.
*   **Behavior:** Calls `win_sparkle_init()` internally.
*   **Exceptions:** Raises an exception if `WinSparkle.dll` cannot be loaded or if `win_sparkle_init()` fails. Logs errors via `TSynLog`.

### `IWinSparkleUpdater` Interface

This is the main interface for interacting with the updater.

*   `procedure ConfigureApp(const CompanyName, AppName, AppVersion: RawUtf8);`  
    Sets the application details used by WinSparkle (e.g., in registry keys and UI).
*   `procedure SetAppcastURL(const URL: RawUtf8);`  
    Sets the URL for the Appcast feed (XML file describing updates). **Must use HTTPS.**
*   `procedure SetBuildVersion(const Build: RawUtf8);`  
    Sets an optional, more specific build version string.
*   `procedure SetRegistryPath(const Path: RawUtf8);`  
    Overrides the default registry path (`Software\CompanyName\AppName`) where WinSparkle stores its settings.
*   `procedure SetLanguage(const Lang: RawUtf8);`  
    Sets the preferred language for the WinSparkle UI (e.g., 'en', 'fr', 'de'). WinSparkle must include resources for the specified language.
*   `procedure EnableAutoCheck(Auto: boolean; IntervalSeconds: integer = DefaultSparkleCheckInterval);`  
    Enables or disables automatic background checks for updates. `DefaultSparkleCheckInterval` is 86400 seconds (24 hours).
*   `procedure CheckUpdates(Silent: boolean = false; AutoInstall: boolean = false);`
    Initiates an update check.
    *   `Silent = false`, `AutoInstall = false` (Default): Checks and shows UI if an update is found or an error occurs.
    *   `Silent = true`: 
    Checks in the background. No UI is shown unless an update is found *and* automatic checks are enabled (WinSparkle's behavior). Errors are typically silent.  
    Use callbacks (`OnDidFindUpdate`, `OnDidNotFindUpdate`, `OnError`) to monitor results.
    *   `AutoInstall = true`: Checks, shows UI, and attempts to automatically download and install the update if found.
*   `procedure SetEventHandler(const Handler: IWinSparkleEvents);`  
    Registers an object that implements the `IWinSparkleEvents` interface to receive callbacks. Pass `nil` to clear the handler.
*   `function GetLastCheckTime: Int64;`  
    Returns the timestamp of the last successful update check as a Unix timestamp (`time_t`). Returns -1 if no check has been performed or on error.
*   `function GetUpdateInterval: integer;`  
    Returns the currently configured update check interval in seconds.

### `IWinSparkleEvents` Interface

Implement this interface to handle callbacks from WinSparkle.

```delphi
type
  IWinSparkleEvents = interface(IInvokable)
  ['{DAF1C1B8-B6D9-4A8E-8B4C-1D2A9A0F3C8E}']
    procedure OnError;
    function CanShutdown: Boolean;
    procedure OnShutdownRequest;
    procedure OnDidFindUpdate;
    procedure OnDidNotFindUpdate;
    procedure OnUpdateCancelled;
  end;
```

*   `OnError`: Called when WinSparkle encounters an error during the update check or process.
*   `CanShutdown`: Called before WinSparkle attempts to close the application to install an update. Return `True` to allow shutdown, `False` to prevent it (e.g., if the user has unsaved work).
*   `OnShutdownRequest`: Called when WinSparkle is ready to initiate the application shutdown for the update.
*   `OnDidFindUpdate`: Called when an update is successfully found.
*   `OnDidNotFindUpdate`: Called when the check completes but no update is available.
*   `OnUpdateCancelled`: Called if the user cancels the update process through the WinSparkle UI.

**Important Threading Note:** WinSparkle callbacks can occur on background threads. If your implementation of these methods needs to interact with UI elements or other non-thread-safe components, you **must** marshal the call back to the main application thread (e.g., using `TThread.Queue` or `TThread.Synchronize`).

## Advanced Usage

### Using Callbacks

1.  **Define an Implementation Class:**

    ```delphi
    uses
      mormot.core.base,
      mormot.core.os,
      mormot.ext.winsparkle, 
      mormot.core.log;

    type
      TMySparkleHandler = class(TInterfacedObject, IWinSparkleEvents)
      public
        // IWinSparkleEvents
        procedure OnError;
        function CanShutdown: Boolean;
        procedure OnShutdownRequest;
        procedure OnDidFindUpdate;
        procedure OnDidNotFindUpdate;
        procedure OnUpdateCancelled;
      end;

    { TMySparkleHandler }

    procedure TMySparkleHandler.OnError;
    begin
      // Log error (already on a potentially background thread)
      TSynLog.Add.Log(sllWarning, 'WinSparkle reported an error during update check.');
      // If UI update needed: TThread.Queue(nil, procedure begin ... end);
    end;

    function TMySparkleHandler.CanShutdown: Boolean;
    begin
      TSynLog.Add.Log(sllInfo, 'WinSparkle asking if shutdown is allowed.');
      // Example: Check for unsaved data here (might need marshalling)
      Result := True; // Allow shutdown by default
    end;

    procedure TMySparkleHandler.OnShutdownRequest;
    begin
      TSynLog.Add.Log(sllInfo, 'WinSparkle requesting application shutdown.');
      // Perform cleanup, maybe marshal to main thread to close forms gracefully
      TThread.Queue(nil, procedure
      begin
        // Application.MainForm.Close; // Example: Close main form from main thread
      end);
    end;

    procedure TMySparkleHandler.OnDidFindUpdate;
    begin
      TSynLog.Add.Log(sllInfo, 'WinSparkle found an update!');
    end;

    procedure TMySparkleHandler.OnDidNotFindUpdate;
    begin
      TSynLog.Add.Log(sllInfo, 'WinSparkle did not find an update.');
    end;

    procedure TMySparkleHandler.OnUpdateCancelled;
    begin
      TSynLog.Add.Log(sllInfo, 'WinSparkle update was cancelled by the user.');
    end;
    ```

2.  **Register the Handler:**

    ```delphi
    var
      Updater: IWinSparkleUpdater;
      Handler: IWinSparkleEvents;
    begin
      Updater := CreateWinSparkleUpdater;
      // ... Configure Updater ...

      Handler := TMySparkleHandler.Create;
      Updater.SetEventHandler(Handler);

      // Now, when CheckUpdates is called (especially silent ones),
      // the methods in TMySparkleHandler will be invoked.
      Updater.CheckUpdates(Silent := True);

      // Handler will be kept alive as long as Updater holds a reference,
      // or manage its lifetime separately if needed.
    end;
    ```

### Using Getters

```delphi
var
  Updater: IWinSparkleUpdater;
  LastCheck: Int64;
  Interval: Integer;
  LastCheckDateTime: TDateTime;
begin
  Updater := CreateWinSparkleUpdater;
  // ... Configure ...

  LastCheck := Updater.GetLastCheckTime;
  Interval := Updater.GetUpdateInterval;

  if LastCheck > 0 then
    LastCheckDateTime := UnixToDateTime(LastCheck) // From SysUtils
  else
    LastCheckDateTime := 0;

  TSynLog.Add.Log(sllInfo, 'Last Check: %, Interval: % seconds', [DateTimeToStr(LastCheckDateTime), Interval]);
end;
```

## Error Handling

*   **Initialization:** `CreateWinSparkleUpdater` raises an exception if `WinSparkle.dll` is missing/invalid or `win_sparkle_init` fails. It logs details using `TSynLog`.
*   **Method Calls:** All methods on `IWinSparkleUpdater` first check if initialization was successful. If not, they raise an `EInvalidOperation` exception ('WinSparkle updater is not initialized.').
*   **Runtime Errors:** Errors during the update check process itself (network issues, invalid appcast) are generally handled internally by WinSparkle (often showing UI or failing silently for background checks). The `OnError` callback can be used to get notified of these.

## Threading Considerations

*   The `TWinSparkleUpdater` object itself is not inherently thread-safe if multiple threads call its methods concurrently. Create and use instances from a single thread context or implement external locking.
*   **Crucially:** Any WinSparkle function that might display UI (`CheckUpdates` without `Silent=true`) or interact heavily with the registry **must** be called from the application's **main UI thread**.
*   Callbacks defined in `IWinSparkleEvents` can be triggered by WinSparkle on **background threads**. Implementations **must** be thread-safe or use `TThread.Queue`/`TThread.Synchronize` to marshal calls to the main thread if interacting with UI or non-thread-safe application state.


## Limitations

*   **Single Callback Handler:** Due to the nature of the WinSparkle C API callbacks (which lack user data pointers), this wrapper uses a global internal variable (`gEventHandler`) to route callbacks. This means only one `IWinSparkleEvents` handler instance can be effectively active across the entire application at any given time. Setting a handler on a new `IWinSparkleUpdater` instance will replace the handler for any previous instance. This is usually acceptable as most applications only manage one update process.
*   **Static Linking:** The current implementation uses static linking (`external DLL`). The application will fail to start if `WinSparkle.dll` is not found. Dynamic loading (`LoadLibrary`/`GetProcAddress`) could be implemented for more resilience but adds complexity.

## License

The wrapper can be used under the terms of the [MIT License](https://opensource.org/licenses/MIT).


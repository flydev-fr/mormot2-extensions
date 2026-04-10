# mORMot2 External Process

A small extension for `mormot.core.os` introducing `TExternalProcess` class and `RunRedirect` overload for interactive bidirectional stdin/stdout pipes with child processes. 
Use it to start, write, read, and gracefully stop external programs (FFmpeg, Node.js, Claude Code, etc.) independently.

## API Cheat Sheet

### `RunRedirect` overload with `stdinput`

```pascal
// from mormot.ext.os — overloads mormot.core.os.RunRedirect
function RunRedirect(const cmd: TRunArg;
  const stdinput: RawByteString; 
  exitcode: PLongint = nil;
  const onoutput: TOnRedirect = nil;
  waitfordelayms: cardinal = INFINITE;
  setresult: boolean = true;
  const wrkdir: TFileName = '';
  options: TExtProcessOptions = []): RawByteString; overload;
```

```pascal
// uses our overload (second arg is a string)
output := RunRedirect('sort', 'cherry'#10'apple'#10'banana'#10, @exitcode);

// uses vanilla RunRedirect (second arg is PInteger)
output := RunRedirect('cmd /c echo hello', @exitcode);
```

Uses `TExternalProcess` internally so the background reader thread
prevents pipe-buffer deadlocks even when both input and output are large.

### `TExternalProcess` — Class API

```pascal
TExternalProcess = class(TSynPersistent)
public
  function Start(const cmd: TRunArg; const env: TRunArg = '';
    const wrkdir: TFileName = '';
    options: TExtProcessOptions = []): boolean;
  function Write(const data: RawByteString): boolean; overload;
  function Write(p: pointer; len: PtrInt): boolean; overload;
  function WriteAndCloseStdin(const data: RawByteString): boolean;
  procedure CloseStdin;
  function ReadAvailable: RawByteString;
  function HasDataAvailable: boolean;
  function Terminate(waitms: cardinal = 5000): boolean;
  procedure Kill;
  function WaitFor(waitms: cardinal = INFINITE): integer;
  property Running: boolean read GetRunning;
  property ExitCode: integer read fExitCode;
  property Pid: cardinal read GetPid;
  property OnOutput: TOnRedirect read fOnOutput write fOnOutput;
end;
```

Typical lifecycle:

```pascal
proc := TExternalProcess.Create;
try
  proc.Start('some-tool --flag value');
  proc.Write('input line 1' + #10);
  proc.Write('input line 2' + #10);
  // ... later ...
  while proc.Running do
  begin
    Application.ProcessMessages;
    output := output + proc.ReadAvailable;
    SleepHiRes(50);
  end;
  // ExitCode is automatically captured when the child exits naturally
  if proc.ExitCode <> 0 then
    raise Exception.CreateFmt('tool failed: %d', [proc.ExitCode]);
finally
  proc.Free;
end;
```

Key things to know:

- A **background reader thread** is started by `Start()` and continuously
  drains the child's stdout into an internal buffer, preventing the
  classic pipe-buffer deadlock when the child produces output while the
  parent is busy writing.
- `ReadAvailable` **consumes** the buffer and returns everything since
  the last call. Use `HasDataAvailable` for non-destructive polling.
- Polling `Running` is safe and captures `ExitCode` automatically when
  the child exits on its own — you do not have to call `WaitFor` for
  that.
- `Terminate(waitms)` tries a graceful shutdown first (WM_QUIT on
  Windows / SIGTERM on POSIX), then falls back to hard kill if the
  process does not exit within the timeout.
- `Kill` is an immediate hard kill (`TerminateProcess` / `SIGKILL`).
- The destructor terminates any still-running child, closes stdin,
  waits briefly for the reader thread to drain, and frees all handles.
  It is always safe to `Free` a running process.
- `OnOutput` is called **from the reader thread**, not the main thread.
  Keep it short and thread-safe. Set it **before** calling `Start()`.

### `TExtProcessOptions` Flags

| Flag | Meaning |
|---|---|
| `epoEnvAddExisting` | Merge given `env` with the current process's environment |
| `epoJobCloseChildren` | Wrap the child in a Windows Job Object so it is auto-closed when the parent dies |
| `epoNewConsole` | Give the child its own console window |
| `epoNewProcessGroup` | Create the child in its own Windows process group so `CTRL_BREAK_EVENT` can be targeted at it alone |

## Graceful Shutdown Patterns

The "how do I stop one process cleanly among many siblings" problem has
several solutions depending on how the target child behaves:

1. **Child reads stdin for shutdown commands** (FFmpeg `q`, some
   daemons) — easiest, most portable. Just `Write('q' + #10)` on the
   specific `TExternalProcess` instance. This is what the FFmpeg demo
   uses.
2. **Child exits on EOF of stdin** (`cat`, shell pipelines) — call
   `CloseStdin` on the specific instance.
3. **Child responds to SIGTERM / Ctrl+Break** — call `Terminate(waitms)`
   on the specific instance. On Windows, for process-group isolation,
   create the child with `epoNewProcessGroup`.
4. **Child is truly unresponsive** — call `Kill` (hard).

The key invariant is that each `TExternalProcess` owns its own stdin,
stdout, and process handle. Stopping one never affects its siblings.

## Known Limitations

- **Windows `Ctrl+C` vs redirected stdin**: `CTRL_C_EVENT` via
  `GenerateConsoleCtrlEvent` targets the entire process group, so it
  cannot safely stop one child among many. The demos use stdin commands
  (`q`, EOF) instead, which are targeted and portable.
- **POSIX Delphi**: `TExternalProcess` is FPC-only on POSIX. Need to be tested by the community on Delphi's linux compiler.


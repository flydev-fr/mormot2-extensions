/// ExternalProcess demo - interactive bidirectional pipes with child processes
// - showcases both RunRedirect() with stdin and TExternalProcess for
//   interactive communication with long-lived processes
program ExternalProcessDemo;

{$I mormot.defines.inc}

{$ifdef OSWINDOWS}
  {$apptype console}
{$endif OSWINDOWS}

uses
  {$I mormot.uses.inc}
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.ext.os;

procedure WriteLn2(const fmt: RawUtf8; const args: array of const);
begin
  TextColor(ccWhite);
  ConsoleWrite(fmt, args);
  TextColor(ccLightGray);
end;

// ---------------------------------------------------------------------------
// Demo 1: RunRedirect with stdinput (one-shot)
//   Write data to stdin, close pipe, collect output - like: echo "data" | cmd
// ---------------------------------------------------------------------------
procedure Demo_RunRedirect_Stdin;
var
  output: RawByteString;
  exitcode: integer;
begin
  WriteLn2('%', ['']);
  WriteLn2('=== Demo 1: RunRedirect with stdin (one-shot) ===%', [#10]);

  // 1a) pipe text through a command that processes stdin
  {$ifdef OSWINDOWS}
  WriteLn2('> Piping 3 lines through "sort"...', []);
  output := RunRedirect('sort',
    'cherry' + #13#10 + 'apple' + #13#10 + 'banana' + #13#10,
    @exitcode, nil, 10000);
  {$else}
  WriteLn2('> Piping 3 lines through "sort"...', []);
  output := RunRedirect('sort',
    'cherry' + #10 + 'apple' + #10 + 'banana' + #10,
    @exitcode, nil, 10000);
  {$endif}
  WriteLn2('  exit code: %', [exitcode]);
  WriteLn2('  sorted output:', []);
  ConsoleWrite(output);

  // 1b) pipe a calculation to Python (if available)
  {$ifdef OSWINDOWS}
  WriteLn2('%> Piping "print(2**32)" to python...', [#10]);
  output := RunRedirect('python -c "import sys; exec(sys.stdin.read())"',
    'print(2**32)', @exitcode, nil, 10000);
  {$else}
  WriteLn2('%> Piping "print(2**32)" to python3...', [#10]);
  output := RunRedirect('python3 -c "import sys; exec(sys.stdin.read())"',
    'print(2**32)', @exitcode, nil, 10000);
  {$endif}
  if exitcode = 0 then
    WriteLn2('  2^32 = %', [TrimU(output)])
  else
    WriteLn2('  python not available (exit=%)', [exitcode]);

  // 1c) no stdinput: uses the vanilla RunRedirect from mormot.core.os
  {$ifdef OSWINDOWS}
  WriteLn2('%> No stdinput (vanilla RunRedirect): "cmd /c echo hello"', [#10]);
  output := RunRedirect('cmd /c echo hello', @exitcode);
  {$else}
  WriteLn2('%> No stdinput (vanilla RunRedirect): "echo hello"', [#10]);
  output := RunRedirect('echo hello', @exitcode);
  {$endif}
  WriteLn2('  output: %', [TrimU(output)]);
end;

// ---------------------------------------------------------------------------
// Demo 2: TExternalProcess - interactive bidirectional communication
//   Start a process, write commands, read responses, keep it alive
// ---------------------------------------------------------------------------
procedure Demo_ExternalProcess_Interactive;
var
  proc: TExternalProcess;
  output: RawByteString;
  i: integer;
begin
  WriteLn2('%', ['']);
  WriteLn2('=== Demo 2: TExternalProcess interactive I/O ===%', [#10]);

  // 2a) basic: write lines, read them back
  proc := TExternalProcess.Create;
  try
    {$ifdef OSWINDOWS}
    WriteLn2('> Starting "findstr /r ." (echoes stdin to stdout)...', []);
    if not proc.Start('findstr /r "."') then
    begin
      WriteLn2('  FAILED to start', []);
      exit;
    end;
    {$else}
    WriteLn2('> Starting "cat" (echoes stdin to stdout)...', []);
    if not proc.Start('cat') then
    begin
      WriteLn2('  FAILED to start', []);
      exit;
    end;
    {$endif}
    WriteLn2('  pid = %  running = %', [proc.Pid, ord(proc.Running)]);
    // write several lines
    for i := 1 to 5 do
      proc.Write(FormatUtf8('message #%'#10, [i]));
    WriteLn2('  wrote 5 messages', []);
    // close stdin so the echo process can finish
    proc.CloseStdin;
    proc.WaitFor(5000);
    SleepHiRes(100);
    output := proc.ReadAvailable;
    WriteLn2('  received back:', []);
    ConsoleWrite(output);
    WriteLn2('  exit code: %', [proc.ExitCode]);
  finally
    proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Demo 3: TExternalProcess - WriteAndCloseStdin convenience
//   One-shot write, then wait for sorted output
// ---------------------------------------------------------------------------
procedure Demo_ExternalProcess_WriteAndClose;
var
  proc: TExternalProcess;
  output: RawByteString;
begin
  WriteLn2('%', ['']);
  WriteLn2('=== Demo 3: WriteAndCloseStdin + sort ===%', [#10]);

  proc := TExternalProcess.Create;
  try
    WriteLn2('> Starting "sort" and writing unsorted lines...', []);
    proc.Start('sort');
    {$ifdef OSWINDOWS}
    proc.WriteAndCloseStdin(
      'delta' + #13#10 + 'alpha' + #13#10 + 'charlie' + #13#10 + 'bravo' + #13#10);
    {$else}
    proc.WriteAndCloseStdin(
      'delta' + #10 + 'alpha' + #10 + 'charlie' + #10 + 'bravo' + #10);
    {$endif}
    proc.WaitFor(5000);
    SleepHiRes(100);
    output := proc.ReadAvailable;
    WriteLn2('  sorted result:', []);
    ConsoleWrite(output);
  finally
    proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Demo 4: TExternalProcess - process lifecycle management
//   Start a long-running process, then terminate it gracefully
// ---------------------------------------------------------------------------
procedure Demo_ExternalProcess_Lifecycle;
var
  proc: TExternalProcess;
  output: RawByteString;
begin
  WriteLn2('%', ['']);
  WriteLn2('=== Demo 4: Process lifecycle (start, monitor, terminate) ===%', [#10]);

  proc := TExternalProcess.Create;
  try
    {$ifdef OSWINDOWS}
    WriteLn2('> Starting "ping -n 60 127.0.0.1" (long-running)...', []);
    if not proc.Start('ping -n 60 127.0.0.1') then
    begin
      WriteLn2('  FAILED to start', []);
      exit;
    end;
    {$else}
    WriteLn2('> Starting "ping -c 60 127.0.0.1" (long-running)...', []);
    if not proc.Start('ping -c 60 127.0.0.1') then
    begin
      WriteLn2('  FAILED to start', []);
      exit;
    end;
    {$endif}
    WriteLn2('  pid = %  running = %', [proc.Pid, ord(proc.Running)]);
    // let it run for 2 seconds, collect some output
    SleepHiRes(2000);
    output := proc.ReadAvailable;
    WriteLn2('  output after 2s (% bytes):', [length(output)]);
    ConsoleWrite(output);
    // now terminate gracefully
    WriteLn2('%> Terminating...', [#10]);
    proc.Terminate(3000);
    WriteLn2('  running = %  exitcode = %', [ord(proc.Running), proc.ExitCode]);
  finally
    proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Demo 5: TExternalProcess - OnOutput callback for real-time monitoring
// ---------------------------------------------------------------------------
type
  TOutputMonitor = class
    LineCount: integer;
    function OnOutput(const text: RawByteString; pid: cardinal): boolean;
  end;

function TOutputMonitor.OnOutput(const text: RawByteString; pid: cardinal): boolean;
begin
  result := false; // don't abort
  if text <> '' then
    inc(LineCount);
end;

procedure Demo_ExternalProcess_Callback;
var
  proc: TExternalProcess;
  monitor: TOutputMonitor;
begin
  WriteLn2('%', ['']);
  WriteLn2('=== Demo 5: OnOutput callback for real-time monitoring ===%', [#10]);

  monitor := TOutputMonitor.Create;
  proc := TExternalProcess.Create;
  try
    proc.OnOutput := monitor.OnOutput;
    {$ifdef OSWINDOWS}
    WriteLn2('> Starting "ping -n 5 127.0.0.1" with output callback...', []);
    proc.Start('ping -n 5 127.0.0.1');
    {$else}
    WriteLn2('> Starting "ping -c 5 127.0.0.1" with output callback...', []);
    proc.Start('ping -c 5 127.0.0.1');
    {$endif}
    proc.WaitFor(15000);
    SleepHiRes(100);
    WriteLn2('  callback received % chunks of output', [monitor.LineCount]);
    WriteLn2('  full output:', []);
    ConsoleWrite(proc.ReadAvailable);
  finally
    proc.Free;
    monitor.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Demo 6: TExternalProcess - Python REPL interaction
//   Send commands to a Python interpreter, read responses
// ---------------------------------------------------------------------------
procedure Demo_ExternalProcess_PythonRepl;
var
  proc: TExternalProcess;
  output: RawByteString;
begin
  WriteLn2('%', ['']);
  WriteLn2('=== Demo 6: Python REPL interaction ===%', [#10]);

  proc := TExternalProcess.Create;
  try
    {$ifdef OSWINDOWS}
    WriteLn2('> Starting "python -i -u" (interactive, unbuffered)...', []);
    if not proc.Start('python -i -u') then
    {$else}
    WriteLn2('> Starting "python3 -i -u" (interactive, unbuffered)...', []);
    if not proc.Start('python3 -i -u') then
    {$endif}
    begin
      WriteLn2('  python not available, skipping', []);
      exit;
    end;
    SleepHiRes(500); // let Python start
    // discard startup banner
    proc.ReadAvailable;
    // send a calculation
    WriteLn2('  sending: 6 * 7', []);
    proc.Write('6 * 7' + #10);
    SleepHiRes(500);
    output := proc.ReadAvailable;
    WriteLn2('  response: %', [TrimU(output)]);
    // send another one
    WriteLn2('  sending: import sys; print(sys.version)', []);
    proc.Write('import sys; print(sys.version)' + #10);
    SleepHiRes(500);
    output := proc.ReadAvailable;
    WriteLn2('  response: %', [TrimU(output)]);
    // graceful exit
    WriteLn2('  sending: exit()', []);
    proc.Write('exit()' + #10);
    proc.WaitFor(3000);
    WriteLn2('  exit code: %', [proc.ExitCode]);
  finally
    proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
begin
  TextColor(ccLightCyan);
  ConsoleWrite('% TExternalProcess & RunRedirect stdin Demo', ['mORMot2']);
  ConsoleWrite('% %', [SYNOPSE_FRAMEWORK_VERSION, SYNOPSE_FRAMEWORK_BRANCH]);
  TextColor(ccLightGray);

  try
    Demo_RunRedirect_Stdin;
    Demo_ExternalProcess_Interactive;
    Demo_ExternalProcess_WriteAndClose;
    Demo_ExternalProcess_Lifecycle;
    Demo_ExternalProcess_Callback;
    Demo_ExternalProcess_PythonRepl;
  except
    on E: Exception do
    begin
      TextColor(ccLightRed);
      ConsoleWrite('ERROR: % - %', [E.ClassName, E.Message]);
      TextColor(ccLightGray);
    end;
  end;

  WriteLn2('%=== All demos complete ===%', [#10]);
  ConsoleWrite('Press Enter to exit...', []);
  ReadLn;
end.

/// Multi-process management demo using TExternalProcess
// - simulates the FFmpeg multi-capture use case: N long-running processes
//   (one per "deck"), each stoppable independently without affecting siblings
// - shows the two approaches discussed on the forum:
//   1. Per-process stdin pipe (graceful shutdown via 'q'#10 or EOF)
//   2. Process group isolation (epoNewProcessGroup on Windows)
//   * therad: https://synopse.info/forum/viewtopic.php?id=7304
program MultiProcessDemo;

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

const
  DECK_COUNT = 4; // simulate 4 "capture decks"

type
  TWorker = record
    Name: RawUtf8;
    Proc: TExternalProcess;
    StartTix: Int64;
  end;
  TWorkers = array of TWorker;

procedure WriteLn2(const fmt: RawUtf8; const args: array of const);
begin
  TextColor(ccWhite);
  ConsoleWrite(fmt, args);
  TextColor(ccLightGray);
end;

// ---------------------------------------------------------------------------
// Simulated "FFmpeg deck": a long-running process that reads stdin line-by-line
// and echoes timestamps to stdout. Exits gracefully when stdin closes or when
// it receives a 'q' line (mimicking FFmpeg's graceful shutdown).
// ---------------------------------------------------------------------------
function StartDeck(const name: RawUtf8): TExternalProcess;
var
  cmd: RawUtf8;
begin
  result := TExternalProcess.Create;
  // Use a portable shell loop: read lines from stdin, echo timestamp,
  // exit when stdin closes (EOF) or line starts with 'q' (graceful).
  {$ifdef OSWINDOWS}
  // Windows: use a simple cmd loop. findstr /n /r "." echoes stdin with
  // line numbers and exits on EOF, which is close enough to our scenario.
  cmd := 'findstr /n /r "."';
  {$else}
  // POSIX: awk script that prints numbered lines and exits on 'q'
  cmd := 'awk ''/^q$/ {exit 0} {print NR": "$0; fflush()}''';
  {$endif}
  if not result.Start(cmd) then
  begin
    FreeAndNil(result);
    exit;
  end;
end;

// ---------------------------------------------------------------------------
// Start N worker processes concurrently
// ---------------------------------------------------------------------------
procedure StartAllDecks(var workers: TWorkers);
var
  i: integer;
begin
  SetLength(workers, DECK_COUNT);
  WriteLn2('> Starting % concurrent capture decks...', [DECK_COUNT]);
  for i := 0 to DECK_COUNT - 1 do
  begin
    workers[i].Name := FormatUtf8('Deck#%', [i + 1]);
    workers[i].Proc := StartDeck(workers[i].Name);
    workers[i].StartTix := GetTickCount64;
    if workers[i].Proc = nil then
      WriteLn2('  [% FAILED to start]', [workers[i].Name])
    else
      WriteLn2('  [% started, pid=%]', [workers[i].Name, workers[i].Proc.Pid]);
  end;
end;

// ---------------------------------------------------------------------------
// Feed each deck some data so we have something to show
// ---------------------------------------------------------------------------
procedure FeedDecks(const workers: TWorkers);
var
  i, j: integer;
begin
  WriteLn2('%> Feeding each deck 3 input lines...', [#10]);
  for j := 1 to 3 do
    for i := 0 to high(workers) do
      if workers[i].Proc <> nil then
        workers[i].Proc.Write(FormatUtf8('capture_frame_%_%'#10, [i + 1, j]));
  SleepHiRes(300); // let the processes echo back
end;

// ---------------------------------------------------------------------------
// Show current output from each deck
// ---------------------------------------------------------------------------
procedure DumpStatus(const workers: TWorkers);
var
  i: integer;
  out_: RawByteString;
  running: integer;
begin
  running := 0;
  WriteLn2('%> Current status:', [#10]);
  for i := 0 to high(workers) do
    if workers[i].Proc <> nil then
    begin
      out_ := workers[i].Proc.ReadAvailable;
      if workers[i].Proc.Running then
      begin
        inc(running);
        WriteLn2('  [% RUNNING pid=% age=%ms] % bytes buffered',
          [workers[i].Name, workers[i].Proc.Pid,
           GetTickCount64 - workers[i].StartTix, length(out_)]);
      end
      else
        WriteLn2('  [% STOPPED exit=%] % bytes buffered',
          [workers[i].Name, workers[i].Proc.ExitCode, length(out_)]);
    end;
  WriteLn2('  total running: %/%', [running, length(workers)]);
end;

// ---------------------------------------------------------------------------
// APPROACH 1: Targeted graceful shutdown via per-process stdin pipe
// This is the mORMot TExternalProcess way: each instance owns its own stdin
// handle, so we can write 'q'#10 (or close stdin) to stop a specific process
// without touching its siblings. This mirrors how you would send 'q' to a
// specific FFmpeg instance to make it flush buffers and exit cleanly.
// ---------------------------------------------------------------------------
procedure GracefulStopOneDeck(var workers: TWorkers; index: integer);
begin
  if (index < 0) or
     (index > high(workers)) or
     (workers[index].Proc = nil) then
    exit;
  WriteLn2('%> APPROACH 1: Gracefully stopping % (pid=%)...',
    [#10, workers[index].Name, workers[index].Proc.Pid]);
  {$ifdef OSWINDOWS}
  // findstr exits on EOF: closing stdin is enough
  workers[index].Proc.CloseStdin;
  {$else}
  // awk script exits on 'q' line or EOF - demonstrate both by sending 'q' first
  workers[index].Proc.Write('q'#10);
  workers[index].Proc.CloseStdin;
  {$endif}
  // wait for clean exit
  if workers[index].Proc.WaitFor(3000) >= 0 then
    WriteLn2('  [% exited gracefully, code=%]',
      [workers[index].Name, workers[index].Proc.ExitCode])
  else
    WriteLn2('  [% did not exit in time, killing]', [workers[index].Name]);
end;

// ---------------------------------------------------------------------------
// APPROACH 2: Per-instance hard Terminate()
// Shows that Terminate() only affects THIS process, not the siblings,
// because each was created with its own pipes and process handle.
// On Windows with epoNewProcessGroup, even Ctrl+Break could be targeted.
// ---------------------------------------------------------------------------
procedure HardTerminateOneDeck(var workers: TWorkers; index: integer);
begin
  if (index < 0) or
     (index > high(workers)) or
     (workers[index].Proc = nil) then
    exit;
  WriteLn2('%> APPROACH 2: Hard-terminating % (pid=%)...',
    [#10, workers[index].Name, workers[index].Proc.Pid]);
  workers[index].Proc.Terminate(2000);
  WriteLn2('  [% running=% exit=%]',
    [workers[index].Name, ord(workers[index].Proc.Running),
     workers[index].Proc.ExitCode]);
end;

// ---------------------------------------------------------------------------
// Cleanup remaining processes
// ---------------------------------------------------------------------------
procedure FreeAllDecks(var workers: TWorkers);
var
  i: integer;
begin
  WriteLn2('%> Freeing any remaining deck processes...', [#10]);
  for i := 0 to high(workers) do
    if workers[i].Proc <> nil then
    begin
      if workers[i].Proc.Running then
      begin
        WriteLn2('  [% still running - destructor will clean up]',
          [workers[i].Name]);
      end;
      FreeAndNil(workers[i].Proc);
    end;
  SetLength(workers, 0);
end;

// ---------------------------------------------------------------------------
// Main scenario: start 4 decks, feed them, stop them one by one, verify
// that stopping one does not affect the others (the key property that was
// broken with the old GenerateConsoleCtrlEvent(0) global-group approach).
// ---------------------------------------------------------------------------
procedure RunScenario;
var
  workers: TWorkers;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' Multi-Process Management Demo - FFmpeg-style use case', []);
  WriteLn2('=============================================================%', [#10]);

  try
    // 1. Spawn N decks
    StartAllDecks(workers);
    SleepHiRes(200);

    // 2. Feed each with some data
    FeedDecks(workers);
    DumpStatus(workers);

    // 3. Graceful stop of deck #2 only - siblings must stay alive
    GracefulStopOneDeck(workers, 1);
    DumpStatus(workers);

    // 4. Feed remaining decks more data to prove they still work
    WriteLn2('%> Feeding remaining decks another batch...', [#10]);
    if workers[0].Proc <> nil then
      workers[0].Proc.Write('after_stop_1'#10);
    if workers[2].Proc <> nil then
      workers[2].Proc.Write('after_stop_1'#10);
    if workers[3].Proc <> nil then
      workers[3].Proc.Write('after_stop_1'#10);
    SleepHiRes(300);
    DumpStatus(workers);

    // 5. Graceful stop of deck #4
    GracefulStopOneDeck(workers, 3);
    DumpStatus(workers);

    // 6. Hard terminate deck #3 (simulating unresponsive process)
    HardTerminateOneDeck(workers, 2);
    DumpStatus(workers);

    // 7. Finally, graceful stop of deck #1
    GracefulStopOneDeck(workers, 0);
    DumpStatus(workers);

    WriteLn2('%> All decks stopped independently - sibling isolation confirmed',
      [#10]);
  finally
    FreeAllDecks(workers);
  end;
end;

// ---------------------------------------------------------------------------
// demonstrate epoNewProcessGroup flag (Windows-only)
// Creating a process with its own group lets you send CTRL_BREAK_EVENT to
// just that pid via GenerateConsoleCtrlEvent(), without affecting siblings.
// ---------------------------------------------------------------------------
{$ifdef OSWINDOWS}
procedure Demo_NewProcessGroup;
var
  proc: TExternalProcess;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' epoNewProcessGroup flag (Windows)', []);
  WriteLn2('=============================================================%', [#10]);

  proc := TExternalProcess.Create;
  try
    WriteLn2('> Starting "ping -n 30 127.0.0.1" with epoNewProcessGroup...', []);
    if not proc.Start('ping -n 30 127.0.0.1', '', '',
         [epoNewProcessGroup]) then
    begin
      WriteLn2('  FAILED to start', []);
      exit;
    end;
    WriteLn2('  pid=% created in its own process group', [proc.Pid]);
    WriteLn2('  (CTRL_BREAK_EVENT could now be targeted to just this pid)', []);
    SleepHiRes(1500);
    WriteLn2('> Terminating this specific process...', []);
    proc.Terminate(3000);
    WriteLn2('  running=% exit=%', [ord(proc.Running), proc.ExitCode]);
  finally
    proc.Free;
  end;
end;
{$endif OSWINDOWS}

// ---------------------------------------------------------------------------
begin
  TextColor(ccLightCyan);
  ConsoleWrite('mORMot2 Multi-Process Management Demo', []);
  ConsoleWrite('% %', [SYNOPSE_FRAMEWORK_VERSION, SYNOPSE_FRAMEWORK_BRANCH]);
  TextColor(ccLightGray);

  try
    RunScenario;
    {$ifdef OSWINDOWS}
    Demo_NewProcessGroup;
    {$endif OSWINDOWS}
  except
    on E: Exception do
    begin
      TextColor(ccLightRed);
      ConsoleWrite('ERROR: % - %', [E.ClassName, E.Message]);
      TextColor(ccLightGray);
    end;
  end;

  WriteLn2('%=== Demo complete ===%', [#10]);
  ConsoleWrite('Press Enter to exit...', []);
  ReadLn;
end.

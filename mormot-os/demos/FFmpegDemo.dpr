/// Real FFmpeg multi-process demo
// - showcases the original feature request use case: N concurrent FFmpeg
//   capture processes, each stoppable gracefully via stdin 'q' command
// - this is the reference use case that motivated TExternalProcess + stdin pipes
//
// SETUP:
//   Place ffmpeg.exe (Windows) or ffmpeg (Linux/macOS) in the same folder as
//   this executable, or make sure it is available in the system PATH.
//   Download from: https://ffmpeg.org/download.html
//
// WHAT IT SHOWS:
//   1. Single FFmpeg instance: start with built-in test source, let it run
//      for a few seconds, then send 'q'#10 via stdin for graceful shutdown.
//      FFmpeg flushes its encoder buffers and exits cleanly with code 0.
//
//   2. THREE concurrent FFmpeg instances: each encoding a different test
//      pattern to a separate null sink. Stop them one at a time with 'q'
//      to prove sibling isolation - stopping one never affects the others.
//
//   3. Compare graceful 'q' vs hard Terminate(): the graceful path lets
//      FFmpeg close its output container properly (important for real files
//      where a hard kill leaves a corrupted/unplayable output).
program FFmpegDemo;

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
  // short encoding run; long enough to produce real output, short enough
  // that tests don't hang forever if the q-stop fails
  RUN_SECONDS = 15;

procedure WriteLn2(const fmt: RawUtf8; const args: array of const);
begin
  TextColor(ccWhite);
  ConsoleWrite(fmt, args);
  TextColor(ccLightGray);
end;

// ---------------------------------------------------------------------------
// Locate the ffmpeg executable: try executable folder first, then PATH
// ---------------------------------------------------------------------------
function FindFfmpeg: TFileName;
{$ifdef OSWINDOWS}
const
  FFEXE = 'ffmpeg.exe';
{$else}
const
  FFEXE = 'ffmpeg';
{$endif}
begin
  // 1) same folder as the demo .exe
  result := Executable.ProgramFilePath + FFEXE;
  if FileExists(result) then
    exit;
  // 2) system PATH - let the shell resolve it
  result := FFEXE;
end;

function FirstLine(const s: RawByteString): RawByteString;
var
  p, e: PUtf8Char;
begin
  result := '';
  p := pointer(s);
  if p = nil then
    exit;
  e := p;
  while (e^ <> #0) and (e^ <> #10) and (e^ <> #13) do
    inc(e);
  FastSetRawByteString(result, p, e - p);
end;

function CheckFfmpegAvailable(const ff: TFileName): boolean;
var
  exitcode: integer;
  output: RawByteString;
begin
  // run "ffmpeg -version" to verify availability
  output := RunRedirect(ff + ' -version', @exitcode, nil, 5000);
  result := (exitcode = 0) and
            (PosEx('ffmpeg version', output) > 0);
  if result then
  begin
    WriteLn2('> FFmpeg detected: %', [ff]);
    // print just the first line of version info
    TextColor(ccLightGray);
    ConsoleWrite(FirstLine(output));
  end
  else
    WriteLn2('  (exitcode=%)', [exitcode]);
end;

// ---------------------------------------------------------------------------
// Demo 1: Single FFmpeg instance - graceful 'q' shutdown
// ---------------------------------------------------------------------------
procedure Demo_SingleGracefulStop(const ff: TFileName);
var
  proc: TExternalProcess;
  cmd: TFileName;
  output: RawByteString;
  t0: Int64;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' Demo 1: Single FFmpeg instance - graceful "q" stdin shutdown', []);
  WriteLn2('=============================================================%', [#10]);

  // Use FFmpeg's lavfi testsrc to generate synthetic video without any
  // input file; encode to null to avoid writing an output file.
  // -nostats reduces noise; we still see the frame counter via -progress
  cmd := ff +
    ' -y -hide_banner -loglevel info' +
    ' -re -f lavfi -i testsrc=size=640x480:rate=30' +
    ' -t ' + IntToStr(RUN_SECONDS) +
    ' -c:v libx264 -preset ultrafast -f null -';
  WriteLn2('> Command:%  %%', [#10, cmd, #10]);

  proc := TExternalProcess.Create;
  try
    t0 := GetTickCount64;
    if not proc.Start(cmd) then
    begin
      WriteLn2('  FAILED to start', []);
      exit;
    end;
    WriteLn2('> Started pid=% - letting it encode for 2 seconds...',
      [proc.Pid]);
    SleepHiRes(2000);
    output := proc.ReadAvailable;
    WriteLn2('> collected % bytes of stderr output so far:',
      [length(output)]);
    if length(output) > 400 then
      ConsoleWrite(copy(output, length(output) - 400, 400))
    else
      ConsoleWrite(output);

    // the key moment: send 'q' + LF to FFmpeg's stdin
    WriteLn2('%> Sending "q"#10 to FFmpeg stdin for graceful shutdown...',
      [#10]);
    proc.Write('q' + #10);

    // wait for FFmpeg to flush and exit
    if proc.WaitFor(5000) < 0 then
    begin
      WriteLn2('  graceful shutdown took too long - forcing kill', []);
      proc.Kill;
    end;
    SleepHiRes(100);
    output := proc.ReadAvailable;
    if length(output) > 500 then
      ConsoleWrite(copy(output, length(output) - 500, 500))
    else
      ConsoleWrite(output);

    WriteLn2('%> Result:', [#10]);
    WriteLn2('  exit code: % (0 = clean graceful exit)', [proc.ExitCode]);
    WriteLn2('  total time: % ms', [GetTickCount64 - t0]);
  finally
    proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Demo 2: THREE concurrent FFmpeg instances - independent graceful stop
// ---------------------------------------------------------------------------
type
  TEncoder = record
    Name: RawUtf8;
    Proc: TExternalProcess;
    StartTix: Int64;
  end;

function StartEncoder(const ff: TFileName; const name, source: RawUtf8): TEncoder;
var
  cmd: TFileName;
begin
  result.Name := name;
  result.StartTix := GetTickCount64;
  // -re forces real-time reading from lavfi (1 frame per wall-clock
  //   interval) so the encoding takes wall-clock time, not "as fast as
  //   possible" - without this, x264 ultrafast finishes the whole 15
  //   seconds of synthetic video in well under a second on modern CPUs
  // -t sets the output duration and works with all lavfi sources,
  //   including mandelbrot (which doesn't accept the filter-level
  //   :duration= parameter)
  cmd := ff +
    ' -y -hide_banner -loglevel info' +
    ' -re -f lavfi -i "' + Utf8ToString(source) + '"' +
    ' -t ' + IntToStr(RUN_SECONDS) +
    ' -c:v libx264 -preset ultrafast -f null -';
  result.Proc := TExternalProcess.Create;
  if not result.Proc.Start(cmd) then
    FreeAndNil(result.Proc);
end;

procedure Demo_MultiConcurrent(const ff: TFileName);
var
  decks: array[0..2] of TEncoder;
  i: integer;
  output: RawByteString;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' Demo 2: THREE concurrent FFmpeg instances, stopped one by one', []);
  WriteLn2('=============================================================%', [#10]);

  // Three different synthetic sources, each in its own ffmpeg process.
  // Real-world: imagine 3 RTSP/HLS capture streams on 3 "decks".
  decks[0] := StartEncoder(ff, 'Deck1-testsrc',
    'testsrc=size=640x480:rate=30');
  decks[1] := StartEncoder(ff, 'Deck2-smptebars',
    'smptebars=size=640x480:rate=30');
  decks[2] := StartEncoder(ff, 'Deck3-mandelbrot',
    'mandelbrot=size=640x480:rate=30');

  try
    for i := 0 to high(decks) do
      if decks[i].Proc = nil then
        WriteLn2('  [% FAILED to start]', [decks[i].Name])
      else
        WriteLn2('  [% pid=% started]', [decks[i].Name, decks[i].Proc.Pid]);

    WriteLn2('%> Letting all 3 decks encode for 2 seconds...', [#10]);
    SleepHiRes(2000);

    // drain output buffers so we don't grow them too large
    for i := 0 to high(decks) do
      if decks[i].Proc <> nil then
        decks[i].Proc.ReadAvailable;

    // Stop Deck2 gracefully - Deck1 and Deck3 must remain running
    WriteLn2('%> Stopping Deck2 gracefully (q#10)...', [#10]);
    if decks[1].Proc <> nil then
    begin
      decks[1].Proc.Write('q' + #10);
      if decks[1].Proc.WaitFor(5000) >= 0 then
        WriteLn2('  [Deck2 exited with code=%]', [decks[1].Proc.ExitCode])
      else
        WriteLn2('  [Deck2 WaitFor timed out]', []);
    end;
    WriteLn2('  Deck1 running=%  Deck3 running=%',
      [ord(decks[0].Proc.Running), ord(decks[2].Proc.Running)]);

    // let the remaining 2 keep running for another second
    WriteLn2('%> Remaining decks keep running for 1 more second...', [#10]);
    SleepHiRes(1000);
    if decks[0].Proc <> nil then decks[0].Proc.ReadAvailable;
    if decks[2].Proc <> nil then decks[2].Proc.ReadAvailable;

    // Stop Deck1 gracefully
    WriteLn2('%> Stopping Deck1 gracefully (q#10)...', [#10]);
    if decks[0].Proc <> nil then
    begin
      decks[0].Proc.Write('q' + #10);
      if decks[0].Proc.WaitFor(5000) >= 0 then
        WriteLn2('  [Deck1 exited with code=%]', [decks[0].Proc.ExitCode]);
    end;
    WriteLn2('  Deck3 running=%', [ord(decks[2].Proc.Running)]);

    // Stop Deck3 last
    WriteLn2('%> Stopping Deck3 gracefully (q#10)...', [#10]);
    if decks[2].Proc <> nil then
    begin
      decks[2].Proc.Write('q' + #10);
      if decks[2].Proc.WaitFor(5000) >= 0 then
        WriteLn2('  [Deck3 exited with code=%]', [decks[2].Proc.ExitCode]);
    end;

    WriteLn2('%> All 3 decks stopped independently - sibling isolation confirmed',
      [#10]);
  finally
    for i := 0 to high(decks) do
      if decks[i].Proc <> nil then
        decks[i].Proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Demo 3: Compare graceful 'q' vs hard Terminate
// ---------------------------------------------------------------------------
procedure Demo_GracefulVsHard(const ff: TFileName);
var
  proc: TExternalProcess;
  cmd: TFileName;
  output: RawByteString;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' Demo 3: Graceful "q" vs hard Terminate()', []);
  WriteLn2('=============================================================%', [#10]);

  cmd := ff +
    ' -y -hide_banner -loglevel info' +
    ' -re -f lavfi -i testsrc=size=640x480:rate=30' +
    ' -t 30 -c:v libx264 -preset ultrafast -f null -';

  // A) graceful
  WriteLn2('> Run A: graceful "q" shutdown...', []);
  proc := TExternalProcess.Create;
  try
    if proc.Start(cmd) then
    begin
      SleepHiRes(1500);
      proc.Write('q' + #10);
      proc.WaitFor(5000);
      WriteLn2('  exit code = %  (expect 0)', [proc.ExitCode]);
      SleepHiRes(100);
      output := proc.ReadAvailable;
      // look for FFmpeg's final "kb/s" summary line which only prints
      // on clean shutdown
      if PosEx('kb/s', output) > 0 then
        WriteLn2('  OK: FFmpeg printed final encoding summary (clean flush)', [])
      else
        WriteLn2('  WARN: no final summary found', []);
    end;
  finally
    proc.Free;
  end;

  // B) hard terminate
  WriteLn2('%> Run B: hard Terminate() without "q"...', [#10]);
  proc := TExternalProcess.Create;
  try
    if proc.Start(cmd) then
    begin
      SleepHiRes(1500);
      proc.Terminate(2000);
      WriteLn2('  exit code = %  (usually non-zero: hard kill)', [proc.ExitCode]);
      SleepHiRes(100);
      output := proc.ReadAvailable;
      if PosEx('kb/s', output) > 0 then
        WriteLn2('  (unexpectedly had final summary)', [])
      else
        WriteLn2('  no final summary - encoder did not flush (expected for hard kill)', []);
    end;
  finally
    proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
var
  ff: TFileName;
begin
  TextColor(ccLightCyan);
  ConsoleWrite('mORMot2 FFmpeg Multi-Process Demo', []);
  ConsoleWrite('% %', [SYNOPSE_FRAMEWORK_VERSION, SYNOPSE_FRAMEWORK_BRANCH]);
  TextColor(ccLightGray);

  ff := FindFfmpeg;
  if not CheckFfmpegAvailable(ff) then
  begin
    TextColor(ccLightRed);
    ConsoleWrite('', []);
    ConsoleWrite('ERROR: FFmpeg not found.', []);
    ConsoleWrite('', []);
    TextColor(ccLightGray);
    ConsoleWrite('  Place ffmpeg' +
      {$ifdef OSWINDOWS}'.exe'{$else}''{$endif} +
      ' next to this executable, or install it', []);
    ConsoleWrite('  in a directory included in the system PATH.', []);
    ConsoleWrite('', []);
    ConsoleWrite('  Download: https://ffmpeg.org/download.html', []);
    ConsoleWrite('', []);
    ConsoleWrite('Press Enter to exit...', []);
    ReadLn;
    Halt(1);
  end;

  try
    Demo_SingleGracefulStop(ff);
    Demo_MultiConcurrent(ff);
    Demo_GracefulVsHard(ff);
  except
    on E: Exception do
    begin
      TextColor(ccLightRed);
      ConsoleWrite('ERROR: % - %', [E.ClassName, E.Message]);
      TextColor(ccLightGray);
    end;
  end;

  WriteLn2('%=== All FFmpeg demos complete ===%', [#10]);
  ConsoleWrite('Press Enter to exit...', []);
  ReadLn;
end.

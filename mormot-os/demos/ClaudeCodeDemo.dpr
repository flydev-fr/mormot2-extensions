/// Claude Code CLI orchestration demo
// - showcases driving one or more "claude" CLI instances from mORMot2 via
//   TExternalProcess and RunRedirect stdin pipes
// - three scenarios:
//     1) One-shot: pipe a code snippet to `claude -p --output-format json`
//        via stdin and parse the JSON response
//     2) Parallel: run THREE concurrent Claude instances answering
//        independent questions, collect results as they complete
//     3) Streaming: drive `claude -p --output-format stream-json` and parse
//        the newline-delimited JSON events in real time via OnOutput callback
//
// PREREQUISITES:
//   - Claude Code CLI installed and authenticated.
//
// NOTE: The exact CLI flag names and JSON schema may evolve between Claude
// Code releases. If a demo breaks, run `claude --help` and adjust the
// command lines below accordingly.
program ClaudeCodeDemo;

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
  mormot.core.variants,
  mormot.core.json,
  mormot.ext.os;

procedure WriteLn2(const fmt: RawUtf8; const args: array of const);
begin
  TextColor(ccWhite);
  ConsoleWrite(fmt, args);
  TextColor(ccLightGray);
end;

// ---------------------------------------------------------------------------
// Quote a path with embedded spaces so Windows CreateProcessW / POSIX shell
// parse it as a single token
// ---------------------------------------------------------------------------
function QuoteCmd(const path: TFileName): TFileName;
begin
  if (path <> '') and
     (Pos(' ', path) > 0) and
     (path[1] <> '"') then
    result := '"' + path + '"'
  else
    result := path;
end;

// ---------------------------------------------------------------------------
// Locate the claude executable
//  1) next to the demo .exe (any known extension)
//  2) via `where claude` on Windows / `command -v claude` on POSIX (respects
//     PATH and PATHEXT, finds .exe / .cmd / .bat / no-extension installs)
//  3) fall back to bare "claude" and hope the OS resolves it..
// ---------------------------------------------------------------------------
function FindClaude: TFileName;
{$ifdef OSWINDOWS}
const
  EXTS: array[0..2] of TFileName = ('.exe', '.cmd', '.bat');
{$endif}
var
  output: RawByteString;
  exitcode: integer;
  nl: PtrInt;
  line: RawUtf8;
  {$ifdef OSWINDOWS}
  i: integer;
  {$endif}
begin
  {$ifdef OSWINDOWS}
  // 1) same folder as the demo .exe, any known extension
  for i := 0 to high(EXTS) do
  begin
    result := Executable.ProgramFilePath + 'claude' + EXTS[i];
    if FileExists(result) then
      exit;
  end;
  // 2) use `where` to let Windows resolve PATH + PATHEXT
  output := RunRedirect('where claude', @exitcode, nil, 5000);
  if exitcode = 0 then
  begin
    // `where` prints one full path per line; take the first
    nl := PosEx(#10, RawUtf8(output));
    if nl = 0 then
      line := TrimU(RawUtf8(output))
    else
      line := TrimU(copy(RawUtf8(output), 1, nl - 1));
    if (line <> '') and
       FileExists(TFileName(line)) then
    begin
      result := TFileName(line);
      exit;
    end;
  end;
  // 3) last resort - bare name, CreateProcessW will append .exe and search PATH
  result := 'claude';
  {$else}
  // POSIX: same folder first
  result := Executable.ProgramFilePath + 'claude';
  if FileExists(result) then
    exit;
  // then use `command -v` to find it
  output := RunRedirect('/bin/sh -c "command -v claude"', @exitcode, nil, 5000);
  if exitcode = 0 then
  begin
    line := TrimU(RawUtf8(output));
    if (line <> '') and
       FileExists(TFileName(line)) then
    begin
      result := TFileName(line);
      exit;
    end;
  end;
  result := 'claude';
  {$endif}
end;

function CheckClaudeAvailable(const cli: TFileName): boolean;
var
  exitcode: integer;
  output: RawByteString;
  fullcmd: TFileName;
begin
  fullcmd := QuoteCmd(cli) + ' --version';
  output := RunRedirect(fullcmd, @exitcode, nil, 10000);
  result := exitcode = 0;
  if result then
  begin
    WriteLn2('> Claude Code detected: %', [cli]);
    TextColor(ccLightGray);
    ConsoleWrite(TrimU(output));
  end
  else
  begin
    TextColor(ccLightRed);
    ConsoleWrite('  Tried: %', [fullcmd]);
    ConsoleWrite('  exit=%  output-bytes=%', [exitcode, length(output)]);
    if length(output) > 0 then
      ConsoleWrite(TrimU(copy(output, 1, 500)));
    TextColor(ccLightGray);
  end;
end;

// ---------------------------------------------------------------------------
// Small helper: extract the "result" field from a claude -p JSON envelope
// - claude -p --output-format json returns something like
//   {"type":"result","subtype":"success","result":"...","cost_usd":...}
// - tolerates leading noise before the JSON (e.g. warnings on stderr that
//   got merged into the same pipe) by scanning for the first '{'
// - falls back to the raw trimmed output if JSON parsing still fails
// ---------------------------------------------------------------------------
function ExtractResult(const jsonOutput: RawByteString): RawUtf8;
var
  doc: TDocVariantData;
  raw: RawUtf8;
  start: PtrInt;
begin
  raw := TrimU(RawUtf8(jsonOutput));
  // skip any non-JSON preamble (warnings, debug lines, etc.)
  start := PosEx('{', raw);
  if start > 1 then
    raw := copy(raw, start, maxInt);
  if doc.InitJson(raw, JSON_FAST) and
     (doc.GetValueIndex('result') >= 0) then
    result := TrimU(doc.U['result'])
  else
    result := TrimU(RawUtf8(jsonOutput)); // show something even if parse fails
end;

// ---------------------------------------------------------------------------
// Demo 1: One-shot with stdin pipe
//   We pipe a code snippet to Claude via stdin and ask it to find the bug.
//   This uses the RunRedirect overload from mormot.ext.os - perfect for the
//   "send data, collect one answer" pattern.
// ---------------------------------------------------------------------------
procedure Demo_OneShotStdin(const cli: TFileName);
const
  BUGGY_CODE: RawUtf8 =
    'function add(a, b) {' + #10 +
    '  return a - b; // <-- there is a bug here' + #10 +
    '}';
var
  output: RawByteString;
  exitcode: integer;
  answer: RawUtf8;
  t0: Int64;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' Demo 1: One-shot - pipe code snippet to Claude via stdin', []);
  WriteLn2('=============================================================%', [#10]);
  WriteLn2('> Code to analyze (sent via stdin):', []);
  ConsoleWrite(BUGGY_CODE);
  WriteLn2('%> Running: claude -p "..." --output-format json', [#10]);

  t0 := GetTickCount64;
  // The prompt is on the command line, the code snippet is on stdin.
  // Uses the RunRedirect overload from mormot.ext.os that accepts stdinput
  // as the second parameter (works with vanilla mORMot2, no patch needed).
  output := RunRedirect(
    QuoteCmd(cli) + ' -p "Find the bug in the JavaScript code above and ' +
    'reply in one short sentence." --output-format json',
    {stdinput=} BUGGY_CODE,
    @exitcode, nil,
    {waitfordelayms=} 120000);

  WriteLn2('> Elapsed: % ms', [GetTickCount64 - t0]);
  if exitcode <> 0 then
  begin
    WriteLn2('  FAILED exit=%', [exitcode]);
    if length(output) > 0 then
      ConsoleWrite(TrimU(copy(output, 1, 500)));
    exit;
  end;
  answer := ExtractResult(output);
  WriteLn2('%> Claude says:', [#10]);
  TextColor(ccLightGreen);
  ConsoleWrite(answer);
  TextColor(ccLightGray);
end;

// ---------------------------------------------------------------------------
// Demo 2: Three parallel Claude instances
//   Three simple independent questions answered concurrently by three
//   separate claude processes. This is the "parallel code review" pattern.
// ---------------------------------------------------------------------------
type
  TWorker = record
    Name: RawUtf8;
    Prompt: RawUtf8;
    Proc: TExternalProcess;
    StartTix: Int64;
    EndTix: Int64;
    Answer: RawUtf8;
  end;

procedure Demo_Parallel(const cli: TFileName);
var
  workers: array[0..2] of TWorker;
  i, done: integer;
  output: RawByteString;
  t0: Int64;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' Demo 2: Three parallel Claude instances (fan-out)', []);
  WriteLn2('=============================================================%', [#10]);

  workers[0].Name   := 'GeoBot';
  workers[0].Prompt := 'What is the capital of France? Reply with just the city name.';
  workers[1].Name   := 'MathBot';
  workers[1].Prompt := 'What is 7 times 8? Reply with just the number.';
  workers[2].Name   := 'ColorBot';
  workers[2].Prompt := 'Name one primary color. Reply with just the word.';

  t0 := GetTickCount64;
  // start all 3 workers concurrently
  for i := 0 to high(workers) do
  begin
    workers[i].Proc := TExternalProcess.Create;
    workers[i].StartTix := GetTickCount64;
    if workers[i].Proc.Start(
         QuoteCmd(cli) + ' -p "' + workers[i].Prompt +
         '" --output-format json') then
    begin
      // immediately close stdin so claude does not wait 3s for piped input
      workers[i].Proc.CloseStdin;
      WriteLn2('  [% started pid=%]', [workers[i].Name, workers[i].Proc.Pid]);
    end
    else
    begin
      WriteLn2('  [% FAILED to start]', [workers[i].Name]);
      FreeAndNil(workers[i].Proc);
    end;
  end;

  try
    // poll until all workers have finished (up to 2 minutes total)
    done := 0;
    while (done < length(workers)) and
          (GetTickCount64 - t0 < 120000) do
    begin
      for i := 0 to high(workers) do
        if (workers[i].Proc <> nil) and
           (workers[i].EndTix = 0) and
           not workers[i].Proc.Running then
        begin
          workers[i].EndTix := GetTickCount64;
          output := workers[i].Proc.ReadAvailable;
          workers[i].Answer := ExtractResult(output);
          inc(done);
          WriteLn2('  [% finished in % ms: %]',
            [workers[i].Name,
             workers[i].EndTix - workers[i].StartTix,
             workers[i].Answer]);
        end;
      SleepHiRes(100);
    end;

    WriteLn2('%> Summary:', [#10]);
    for i := 0 to high(workers) do
      if workers[i].Proc <> nil then
      begin
        TextColor(ccLightGreen);
        ConsoleWrite('  % -> %', [workers[i].Name, workers[i].Answer]);
        TextColor(ccLightGray);
      end;
    WriteLn2('  total wall-clock: % ms (all 3 ran concurrently)',
      [GetTickCount64 - t0]);
  finally
    for i := 0 to high(workers) do
      if workers[i].Proc <> nil then
        workers[i].Proc.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Demo 3: Streaming stream-json via OnOutput callback
//   Drive claude -p with --output-format stream-json and parse the
//   newline-delimited JSON events as they arrive. Each event is processed
//   live by a callback running in TExternalProcess's reader thread.
// ---------------------------------------------------------------------------
type
  TStreamParser = class
  private
    fBuffer: RawUtf8;
    fEventCount: integer;
    fEventTypes: TRawUtf8DynArray;
  public
    function OnOutput(const text: RawByteString; pid: cardinal): boolean;
    property EventCount: integer read fEventCount;
  end;

function TStreamParser.OnOutput(const text: RawByteString;
  pid: cardinal): boolean;
var
  nl: PtrInt;
  line: RawUtf8;
  doc: TDocVariantData;
  evt: RawUtf8;
begin
  result := false;
  if text = '' then
    exit;
  // append to buffer and process complete lines (stream-json is NDJSON)
  fBuffer := fBuffer + RawUtf8(text);
  repeat
    nl := PosEx(#10, fBuffer);
    if nl = 0 then
      break;
    line := copy(fBuffer, 1, nl - 1);
    delete(fBuffer, 1, nl);
    line := TrimU(line);
    if line = '' then
      continue;
    if not doc.InitJson(line, JSON_FAST) then
      continue;
    inc(fEventCount);
    evt := doc.U['type'];
    AddRawUtf8(fEventTypes, evt);
    // show a live progress line
    TextColor(ccLightBlue);
    ConsoleWrite('  [event #% type=%]', [fEventCount, evt]);
    TextColor(ccLightGray);
  until false;
end;

procedure Demo_Streaming(const cli: TFileName);
var
  proc: TExternalProcess;
  parser: TStreamParser;
  t0: Int64;
begin
  WriteLn2('%', ['']);
  WriteLn2('=============================================================', []);
  WriteLn2(' Demo 3: Streaming stream-json events via OnOutput callback', []);
  WriteLn2('=============================================================%', [#10]);

  parser := TStreamParser.Create;
  proc := TExternalProcess.Create;
  try
    proc.OnOutput := parser.OnOutput;
    t0 := GetTickCount64;
    // --verbose is required on recent Claude Code for stream-json to emit
    // intermediate events instead of just the final result
    WriteLn2('> Running: claude -p "..." --output-format stream-json --verbose', []);
    if not proc.Start(QuoteCmd(cli) +
         ' -p "Explain what TCP is in 2 sentences." ' +
         '--output-format stream-json --verbose') then
    begin
      WriteLn2('  FAILED to start', []);
      exit;
    end;
    // immediately close stdin so claude does not wait 3s for piped input
    proc.CloseStdin;
    proc.WaitFor(120000);
    SleepHiRes(300); // let the reader thread drain any trailing data
    WriteLn2('%> Total events received: %   elapsed: % ms',
      [#10, parser.EventCount, GetTickCount64 - t0]);
    WriteLn2('  exit code: %', [proc.ExitCode]);
  finally
    proc.Free;
    parser.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
var
  cli: TFileName;
begin
  TextColor(ccLightCyan);
  ConsoleWrite('mORMot2 Claude Code CLI Orchestration Demo', []);
  ConsoleWrite('% %', [SYNOPSE_FRAMEWORK_VERSION, SYNOPSE_FRAMEWORK_BRANCH]);
  TextColor(ccLightGray);

  cli := FindClaude;
  if not CheckClaudeAvailable(cli) then
  begin
    TextColor(ccLightRed);
    ConsoleWrite('', []);
    ConsoleWrite('ERROR: Claude Code CLI not found or not working.', []);
    TextColor(ccLightGray);
    ConsoleWrite('', []);
    ConsoleWrite('  Install Claude Code:', []);
    ConsoleWrite('    https://docs.claude.com/en/docs/claude-code', []);
    ConsoleWrite('', []);
    ConsoleWrite('  Then run `claude login` to authenticate before using', []);
    ConsoleWrite('  this demo. Place `claude` in PATH or next to this exe.', []);
    ConsoleWrite('', []);
    ConsoleWrite('Press Enter to exit...', []);
    ReadLn;
    Halt(1);
  end;

  try
    Demo_OneShotStdin(cli);
    Demo_Parallel(cli);
    Demo_Streaming(cli);
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

# mORMot2 External Process Samples

This folder contains working examples of the `mormot.ext.os` standalone
extension unit, which provides:

- **`TExternalProcess` class** — a long-lived wrapper around a child
  process with bidirectional stdin/stdout pipes, a background reader
  thread, and lifecycle control (Start / Write / Read / Terminate / Kill /
  WaitFor). Designed for interactive and multi-process scenarios.
- **`RunRedirect` overload with `stdinput`** — one-shot execution that
  pipes data into a child process's stdin, reads its stdout, and returns
  the exit code, all in a single call.

Both features are cross-platform (Windows via `CreateProcessW` + anonymous
pipes, POSIX via `fork` + `pipe` + `execve`) and work on FPC (Lazarus) and
Delphi. Just add `mormot.ext.os` to your `uses` clause.

## Standalone Extension Files

Copy these three files into your project or mORMot extensions folder:

| File | Purpose |
|---|---|
| `mormot.ext.os.pas` | Interface + cross-platform `RunRedirect` overload |
| `mormot.ext.os.windows.inc` | Windows implementation (CreateProcessW, pipes, reader thread) |
| `mormot.ext.os.posix.inc` | POSIX FPC implementation (fork, pipe, execve, reader thread) |

Dependencies: `mormot.core.base` and `mormot.core.os`.

## Demo Projects

Each demo has both a Delphi `.dpr` and a Lazarus `.lpi` project file.
Open the project you prefer, hit Build & Run.

### 1. `ExternalProcessDemo` — Feature Tour

Six small scenarios showing the basic API surface:

1. `RunRedirect` with stdin (one-shot sort / python)
2. `TExternalProcess` interactive write + read (echo)
3. `WriteAndCloseStdin` convenience method
4. Process lifecycle (Start, monitor output, Terminate)
5. `OnOutput` callback for real-time monitoring
6. Python REPL interactive session

No external tools needed besides the standard OS commands (`sort`,
`findstr`/`cat`). If Python is installed, one of the demos uses it.

### 2. `MultiProcessDemo` — FFmpeg-style Multi-Process Management

Simulates managing N concurrent long-running "capture decks" (4 in the
demo, up to 8 in production). Each deck is an independent child process
that can be:

- **Gracefully stopped** by closing stdin (or writing `q\n`) — only the
  targeted process exits, siblings keep running.
- **Hard-killed** via `Terminate()` for unresponsive children.

This is the motivating use case for the original feature request: stopping
one FFmpeg among several running instances, without affecting siblings.
The demo uses portable commands (`findstr`/`awk`) so no external tools
are required.

A bonus section demonstrates the `epoNewProcessGroup` option which
creates the child in its own Windows process group, allowing
`CTRL_BREAK_EVENT` to be targeted at a specific PID.

### 3. `FFmpegDemo` — Real FFmpeg

Uses a real `ffmpeg` binary (not included — drop it next to the
executable or put it on `PATH`). Three scenarios:

1. **Single instance with graceful `q` shutdown** — starts encoding a
   synthetic test source, lets it run for a few seconds, writes `q\n` to
   stdin, and verifies that FFmpeg flushes its encoder buffers and exits
   cleanly with code 0.
2. **Three concurrent FFmpeg instances** (`testsrc`, `smptebars`,
   `mandelbrot`) encoding in parallel, stopped one at a time with `q`
   to prove sibling isolation.
3. **Graceful `q` vs hard `Terminate()`** — shows that the graceful
   path lets FFmpeg print its final `kb/s` encoding summary, while a
   hard kill leaves the output incomplete and would corrupt real files.

The demo auto-detects FFmpeg in the executable folder first, then on
`PATH`, and prints a helpful message if neither is found.

### 4. `ClaudeCodeDemo` — Claude Code CLI Orchestration

Drives the [Claude Code](https://docs.claude.com/en/docs/claude-code)
CLI from Pascal. Requires `claude` to be installed and authenticated
(`claude login`).

Three scenarios:

1. **One-shot with stdin** — pipes a buggy JavaScript snippet to
   `claude -p --output-format json` via the `RunRedirect` stdinput
   overload, parses the JSON envelope, prints Claude's answer.
2. **Parallel fan-out** — runs three concurrent Claude instances
   (`GeoBot`, `MathBot`, `ColorBot`) asking independent questions, polls
   them via `Running`, and collects each result as it completes. Shows
   the total wall-clock time is much less than 3x serial because all
   three ran in parallel.
3. **Streaming `stream-json`** — runs Claude with
   `--output-format stream-json --verbose` and parses the newline-
   delimited JSON events live in an `OnOutput` callback. Counts events
   by type as they arrive.

This demo is a proof of concept for orchestrating AI agents from a
Pascal application: parallel code review, test generation, multi-agent
pipelines, long-running background investigations, etc.

// - transport tests for mormot.ext.mcp
unit test.mcp.transports;

interface

{$I mormot.defines.inc}

uses
  {$I mormot.uses.inc}
  sysutils, classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers,
  mormot.core.rtti,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.test,
  mormot.net.sock,
  mormot.net.http,
  mormot.net.client,
  mormot.ext.mcp,
  mormot.ext.mcp.server,
  mormot.ext.mcp.stdio;

const
  HTTP_KEEPALIVE_MS = 10000;

type
  {$ifdef FPC}
  TMcpTextRec = TextRec;
  {$else}
  TMcpTextRec = TTextRec;
  {$endif}

  TCalcParams = packed record
    A: integer;
    B: integer;
    Enabled: boolean;
    Name: RawUtf8;
  end;

  TCalcTool = class(TMcpToolBase<TCalcParams>)
  protected
    function ExecuteTyped(const aParams: TCalcParams;
      const aAuthCtx: TMcpAuthContext): variant; override;
  end;

  TTestMcpTransports = class(TSynTestCase)
  protected
    procedure EnsureCalcParamsRtti;
    function VariantToInt64Loose(const V: variant; out aValue: Int64): boolean;
    function StartHttpTransport(const aServer: TMcpServer;
      out aTransport: TMcpHttpTransport): integer;
    function StartSseTransport(const aServer: TMcpServer;
      out aTransport: TMcpSseTransport): integer;
    procedure BackupStdIo(out aInput, aOutput: TMcpTextRec);
    procedure RestoreStdIo(const aInput, aOutput: TMcpTextRec);
    function WaitForFileNotEmpty(const aFileName: TFileName;
      aTimeoutMs: integer): boolean;
    function WaitForFileLineCount(const aFileName: TFileName;
      aLines, aTimeoutMs: integer): boolean;
  published
    procedure HttpTransportPost;
    procedure HttpTransportAcceptHeader;
    procedure HttpTransportOptions;
    procedure HttpTransportWarpSequence;
    procedure HttpTransportNotification;
    procedure HttpTransportBadJson;
    procedure HttpTransportInvalidMethod;
    procedure SseTransportHandshake;
    procedure SseTransportMessages;
    procedure SseTransportOptions;
    procedure SseTransportMissingSession;
    procedure SseTransportUnknownSession;
    procedure SseTransportConcurrentPosts;
    procedure StdioTransportProcess;
    procedure StdioTransportMultiple;
    procedure StdioTransportBadJson;
  end;

implementation

{ TCalcTool }

function TCalcTool.ExecuteTyped(const aParams: TCalcParams;
  const aAuthCtx: TMcpAuthContext): variant;
var
  builder: TMcpResponseBuilder;
begin
  builder := TMcpResponseBuilder.Create;
  try
    builder.AddText(FormatUtf8('% + % = %', [aParams.A, aParams.B, aParams.A + aParams.B]));
    result := builder.Build;
  finally
    builder.Free;
  end;
end;

{ TTestMcpTransports }

procedure TTestMcpTransports.EnsureCalcParamsRtti;
begin
  //{$ifndef HASEXTRECORDRTTI}
  if not RecordHasFields(TypeInfo(TCalcParams)) then
    Rtti.RegisterFromText(TypeInfo(TCalcParams),
      'A,B:integer Enabled:boolean Name:RawUtf8');
  //{$endif HASEXTRECORDRTTI}
end;

function TTestMcpTransports.VariantToInt64Loose(const V: variant; out aValue: Int64): boolean;
var
  d: double;
  s: RawUtf8;
  wasString: boolean;
begin
  result := VariantToInt64(V, aValue);
  if result then
    exit;
  if VariantToDouble(V, d) then
  begin
    aValue := trunc(d);
    exit(true);
  end;
  VariantToUtf8(V, s, wasString);
  s := TrimU(s);
  if s = '' then
    exit(false);
  if ToInt64(s, aValue) then
    exit(true);
  if ToDouble(s, d) then
  begin
    aValue := trunc(d);
    exit(true);
  end;
  result := false;
end;

function TTestMcpTransports.StartHttpTransport(const aServer: TMcpServer;
  out aTransport: TMcpHttpTransport): integer;
var
  i: integer;
  port: integer;
  base: integer;
  transport: TMcpHttpTransport;
begin
  aTransport := nil;
  base := 18000 + integer(GetTickCount64 mod 1000);
  for i := 0 to 19 do
  begin
    port := base + i;
    try
      transport := TMcpHttpTransport.Create(aServer);
      transport.Port := port;
      transport.Start;
      aTransport := transport;
      result := port;
      exit;
    except
      on Exception do
      begin
        transport.Free;
        continue;
      end;
    end;
  end;
  result := 0;
  Check(false, 'Unable to start HTTP transport on an available port');
end;

function TTestMcpTransports.StartSseTransport(const aServer: TMcpServer;
  out aTransport: TMcpSseTransport): integer;
var
  i: integer;
  port: integer;
  base: integer;
  transport: TMcpSseTransport;
begin
  aTransport := nil;
  base := 19000 + integer(GetTickCount64 mod 1000);
  for i := 0 to 19 do
  begin
    port := base + i;
    try
      transport := TMcpSseTransport.Create(aServer);
      transport.Port := port;
      transport.Start;
      aTransport := transport;
      result := port;
      exit;
    except
      on Exception do
      begin
        transport.Free;
        continue;
      end;
    end;
  end;
  result := 0;
  Check(false, 'Unable to start SSE transport on an available port');
end;

procedure TTestMcpTransports.BackupStdIo(out aInput, aOutput: TMcpTextRec);
begin
  aInput := TMcpTextRec(Input);
  aOutput := TMcpTextRec(Output);
end;

procedure TTestMcpTransports.RestoreStdIo(const aInput, aOutput: TMcpTextRec);
begin
  TMcpTextRec(Input) := aInput;
  TMcpTextRec(Output) := aOutput;
end;

function TTestMcpTransports.WaitForFileNotEmpty(const aFileName: TFileName;
  aTimeoutMs: integer): boolean;
var
  endTick: Int64;
begin
  endTick := GetTickCount64 + aTimeoutMs;
  repeat
    if FileSize(aFileName) > 0 then
      exit(true);
    SleepHiRes(10);
  until GetTickCount64 > endTick;
  result := false;
end;

function TTestMcpTransports.WaitForFileLineCount(const aFileName: TFileName;
  aLines, aTimeoutMs: integer): boolean;
var
  endTick: Int64;
  content: RawUtf8;
  i, lines: integer;
begin
  endTick := GetTickCount64 + aTimeoutMs;
  repeat
    content := StringFromFile(aFileName);
    lines := 0;
    for i := 1 to length(content) do
      if content[i] = #10 then
        inc(lines);
    if (content <> '') and (content[length(content)] <> #10) then
      inc(lines);
    if lines >= aLines then
      exit(true);
    SleepHiRes(10);
  until GetTickCount64 > endTick;
  result := false;
end;
procedure TTestMcpTransports.HttpTransportPost;
var
  server: TMcpServer;
  transport: TMcpHttpTransport;
  port: integer;
  tool: IMcpTool;
  client: THttpClientSocket;
  status: integer;
  request: RawUtf8;
  doc, resultDoc, contentDoc, itemDoc: PDocVariantData;
  docVar, resultVar, contentVar, itemVar: variant;
  tmp: RawUtf8;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('HttpTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    server.RegisterTool(tool);
    server.Start;

    port := StartHttpTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    request := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":5,"b":3,"enabled":true,"name":"x"}}}';
    status := client.Post('/mcp', request, JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_SUCCESS);
    docVar := _JsonFast(client.Content);
    doc := _Safe(docVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    contentVar := resultDoc^.GetValueOrNull('content');
    contentDoc := _Safe(contentVar);
    if CheckFailed(contentDoc^.IsArray, 'content not array') then
      exit;
    if CheckFailed(contentDoc^.Count > 0, 'content empty') then
      exit;
    itemVar := contentDoc^.Values[0];
    if CheckFailed(_Safe(itemVar, itemDoc), 'content[0] not object') then
      exit;
    if CheckFailed(itemDoc^.IsObject, 'content[0] not object') then
      exit;
    Check(itemDoc^.GetAsRawUtf8('text', tmp));
    CheckEqual(tmp, '5 + 3 = 8');
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.HttpTransportAcceptHeader;
var
  server: TMcpServer;
  transport: TMcpHttpTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
  request: RawUtf8;
  doc, resultDoc, capsDoc: PDocVariantData;
  docVar, resultVar: variant;
  tmp: RawUtf8;
begin
  server := TMcpServer.Create('HttpTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartHttpTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    request := '{"jsonrpc":"2.0","id":0,"method":"initialize","params":' +
      '{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":' +
      '{"name":"dev.warp.Warp","version":"v0.2026.01.28.08.14.stable_04"}}}';
    status := client.Post('/mcp', request, JSON_CONTENT_TYPE,
      HTTP_KEEPALIVE_MS, 'Accept: text/event-stream, application/json');
    CheckEqual(status, HTTP_SUCCESS);
    docVar := _JsonFast(client.Content);
    doc := _Safe(docVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    Check(resultDoc^.IsObject);
    Check(resultDoc^.GetAsRawUtf8('protocolVersion', tmp));
    CheckEqual(tmp, MCP_PROTOCOL_VERSION);
    capsDoc := _Safe(resultDoc^.GetValueOrNull('capabilities'));
    Check(capsDoc^.IsObject);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.HttpTransportOptions;
var
  server: TMcpServer;
  transport: TMcpHttpTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
begin
  server := TMcpServer.Create('HttpTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartHttpTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    status := client.Request('/mcp', 'OPTIONS', HTTP_KEEPALIVE_MS, JSON_CONTENT_TYPE_HEADER);
    CheckEqual(status, HTTP_NOCONTENT);
    Check(PosEx('Access-Control-Allow-Origin', client.Headers) > 0);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.HttpTransportWarpSequence;
var
  server: TMcpServer;
  transport: TMcpHttpTransport;
  port: integer;
  tool: IMcpTool;
  client: THttpClientSocket;
  status: integer;
  request: RawUtf8;
  doc, resultDoc, listDoc, itemDoc: PDocVariantData;
  tmp: RawUtf8;
  docVar, resultVar, listVar, itemVar: variant;
begin
  server := TMcpServer.Create('HttpTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    tool := TCalcTool.Create('add', 'Add two numbers');
    server.RegisterTool(tool);
    server.Start;
    port := StartHttpTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));

    request := '{"jsonrpc":"2.0","id":0,"method":"initialize","params":' +
      '{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":' +
      '{"name":"dev.warp.Warp","version":"v0.2026.01.28.08.14.stable_04"}}}';
    status := client.Post('/mcp', request, JSON_CONTENT_TYPE,
      HTTP_KEEPALIVE_MS, 'Accept: text/event-stream, application/json');
    CheckEqual(status, HTTP_SUCCESS);
    docVar := _JsonFast(client.Content);
    doc := _Safe(docVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    Check(resultDoc^.IsObject);

    request := '{"jsonrpc":"2.0","method":"notifications/initialized"}';
    status := client.Post('/mcp', request, JSON_CONTENT_TYPE,
      HTTP_KEEPALIVE_MS, 'Accept: text/event-stream, application/json');
    CheckEqual(status, HTTP_NOCONTENT);

    request := '{"jsonrpc":"2.0","id":1,"method":"resources/list","params":' +
      '{"_meta":{"progressToken":0}}}';
    status := client.Post('/mcp', request, JSON_CONTENT_TYPE,
      HTTP_KEEPALIVE_MS, 'Accept: text/event-stream, application/json');
    CheckEqual(status, HTTP_SUCCESS);
    docVar := _JsonFast(client.Content);
    doc := _Safe(docVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('resources');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);

    request := '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":' +
      '{"_meta":{"progressToken":1}}}';
    status := client.Post('/mcp', request, JSON_CONTENT_TYPE,
      HTTP_KEEPALIVE_MS, 'Accept: text/event-stream, application/json');
    CheckEqual(status, HTTP_SUCCESS);
    docVar := _JsonFast(client.Content);
    doc := _Safe(docVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('tools');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);
    if listDoc^.Count > 0 then
    begin
      itemVar := listDoc^.Values[0];
      if CheckFailed(_Safe(itemVar, itemDoc), 'tools[0] not object') then
        exit;
      Check(itemDoc^.GetAsRawUtf8('name', tmp));
      CheckEqual(tmp, 'add');
    end;
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.HttpTransportNotification;
var
  server: TMcpServer;
  transport: TMcpHttpTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
  request: RawUtf8;
begin
  server := TMcpServer.Create('HttpTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartHttpTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    request := '{"jsonrpc":"2.0","method":"notifications/initialized"}';
    status := client.Post('/mcp', request, JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_NOCONTENT);
    Check(TrimU(client.Content) = '');
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.HttpTransportBadJson;
var
  server: TMcpServer;
  transport: TMcpHttpTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
  doc, errDoc: PDocVariantData;
  docVar, errVar: variant;
  code: integer;
  code64: Int64;
  okCode: boolean;
  codeVar: variant;
begin
  server := TMcpServer.Create('HttpTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartHttpTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    status := client.Post('/mcp', '{', JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_SUCCESS);
    docVar := _JsonFast(client.Content);
    doc := _Safe(docVar);
    errVar := doc^.GetValueOrNull('error');
    errDoc := _Safe(errVar);
    Check(errDoc^.IsObject);
    codeVar := errDoc^.GetValueOrDefault('code', Null);
    okCode := VariantToInt64Loose(codeVar, code64);
    if okCode then
      code := integer(code64)
    else
      code := 0;
    Check(code <> 0);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.HttpTransportInvalidMethod;
var
  server: TMcpServer;
  transport: TMcpHttpTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
begin
  server := TMcpServer.Create('HttpTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartHttpTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    status := client.Request('/mcp', 'DELETE', HTTP_KEEPALIVE_MS, JSON_CONTENT_TYPE_HEADER);
    CheckEqual(status, HTTP_BADREQUEST);
    Check(PosEx('Only POST method supported', client.Content) > 0);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.SseTransportHandshake;
var
  server: TMcpServer;
  transport: TMcpSseTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
  content: RawUtf8;
begin
  server := TMcpServer.Create('SseTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartSseTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    status := client.Get('/sse', HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_SUCCESS);
    CheckEqual(client.ContentType, 'text/event-stream');
    content := client.Content;
    Check(PosEx('event: endpoint', content) > 0);
    Check(PosEx('session_id=', content) > 0);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.SseTransportMessages;
var
  server: TMcpServer;
  transport: TMcpSseTransport;
  port: integer;
  tool: IMcpTool;
  clientGet, clientPost: THttpClientSocket;
  status: integer;
  content, sessionId, url: RawUtf8;
  encodedSessionId: RawUtf8;
  p, eol: integer;
  request: RawUtf8;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('SseTestServer', '1.0');
  transport := nil;
  clientGet := nil;
  clientPost := nil;
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    server.RegisterTool(tool);
    server.Start;
    port := StartSseTransport(server, transport);

    clientGet := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    status := clientGet.Get('/sse', HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_SUCCESS);
    content := clientGet.Content;
    p := PosEx('session_id=', content);
    Check(p > 0);
    if p <= 0 then
      exit;
    inc(p, length('session_id='));
    eol := PosEx(#10, content, p);
    if eol = 0 then
      eol := length(content) + 1;
    sessionId := copy(content, p, eol - p);
    sessionId := TrimU(sessionId);
    Check(sessionId <> '');
    Check(sessionId[1] <> '=');

    clientPost := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    request := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":2,"b":4,"enabled":true,"name":"x"}}}';
    url := '/messages?session_id=' + sessionId;
    status := clientPost.Post(url, request, JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_ACCEPTED);
    Check(PosEx('accepted', clientPost.Content) > 0);

    encodedSessionId := UrlEncode(sessionId);
    url := '/messages?session_id=' + encodedSessionId + '&foo=bar';
    status := clientPost.Post(url, request, JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_ACCEPTED);
  finally
    clientPost.Free;
    clientGet.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.SseTransportOptions;
var
  server: TMcpServer;
  transport: TMcpSseTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
begin
  server := TMcpServer.Create('SseTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartSseTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    status := client.Request('/sse', 'OPTIONS', HTTP_KEEPALIVE_MS, JSON_CONTENT_TYPE_HEADER);
    CheckEqual(status, HTTP_NOCONTENT);
    Check(PosEx('Access-Control-Allow-Origin', client.Headers) > 0);
    status := client.Request('/messages', 'OPTIONS', HTTP_KEEPALIVE_MS, JSON_CONTENT_TYPE_HEADER);
    CheckEqual(status, HTTP_NOCONTENT);
    Check(PosEx('Access-Control-Allow-Origin', client.Headers) > 0);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.SseTransportMissingSession;
var
  server: TMcpServer;
  transport: TMcpSseTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
  request: RawUtf8;
begin
  server := TMcpServer.Create('SseTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartSseTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    request := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}';
    status := client.Post('/messages', request, JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_BADREQUEST);
    Check(PosEx('Missing session_id', client.Content) > 0);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.SseTransportUnknownSession;
var
  server: TMcpServer;
  transport: TMcpSseTransport;
  port: integer;
  client: THttpClientSocket;
  status: integer;
  request: RawUtf8;
begin
  server := TMcpServer.Create('SseTestServer', '1.0');
  transport := nil;
  client := nil;
  try
    server.Start;
    port := StartSseTransport(server, transport);
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    request := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}';
    status := client.Post('/messages?session_id=unknown', request,
      JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_NOTFOUND);
    Check(PosEx('Session not found', client.Content) > 0);
  finally
    client.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

type
  TSsePostThread = class(TThread)
  private
    fPort: integer;
    fUrl: RawUtf8;
    fRequest: RawUtf8;
    fStatus: integer;
  protected
    procedure Execute; override;
  public
    constructor Create(aPort: integer; const aUrl, aRequest: RawUtf8);
    property Status: integer read fStatus;
  end;

constructor TSsePostThread.Create(aPort: integer; const aUrl, aRequest: RawUtf8);
begin
  inherited Create(true);
  FreeOnTerminate := false;
  fPort := aPort;
  fUrl := aUrl;
  fRequest := aRequest;
  fStatus := 0;
  Resume;
end;

procedure TSsePostThread.Execute;
var
  client: THttpClientSocket;
begin
  client := nil;
  try
    client := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(fPort));
    fStatus := client.Post(fUrl, fRequest, JSON_CONTENT_TYPE, HTTP_KEEPALIVE_MS);
  finally
    client.Free;
  end;
end;

procedure TTestMcpTransports.SseTransportConcurrentPosts;
var
  server: TMcpServer;
  transport: TMcpSseTransport;
  port: integer;
  tool: IMcpTool;
  clientGet: THttpClientSocket;
  status: integer;
  content, sessionId, url: RawUtf8;
  p, eol: integer;
  request: RawUtf8;
  th1, th2: TSsePostThread;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('SseTestServer', '1.0');
  transport := nil;
  clientGet := nil;
  th1 := nil;
  th2 := nil;
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    server.RegisterTool(tool);
    server.Start;
    port := StartSseTransport(server, transport);

    clientGet := THttpClientSocket.Open('127.0.0.1', UInt32ToUtf8(port));
    status := clientGet.Get('/sse', HTTP_KEEPALIVE_MS);
    CheckEqual(status, HTTP_SUCCESS);
    content := clientGet.Content;
    p := PosEx('session_id=', content);
    Check(p > 0);
    if p <= 0 then
      exit;
    inc(p, length('session_id='));
    eol := PosEx(#10, content, p);
    if eol = 0 then
      eol := length(content) + 1;
    sessionId := copy(content, p, eol - p);
    sessionId := TrimU(sessionId);
    Check(sessionId <> '');

    request := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":2,"b":4,"enabled":true,"name":"x"}}}';
    url := '/messages?session_id=' + sessionId;
    th1 := TSsePostThread.Create(port, url, request);
    th2 := TSsePostThread.Create(port, url, request);
    th1.WaitFor;
    th2.WaitFor;
    CheckEqual(th1.Status, HTTP_ACCEPTED);
    CheckEqual(th2.Status, HTTP_ACCEPTED);
  finally
    th2.Free;
    th1.Free;
    clientGet.Free;
    if transport <> nil then
      transport.Stop;
    transport.Free;
    server.Free;
  end;
end;

procedure TTestMcpTransports.StdioTransportProcess;
var
  server: TMcpServer;
  transport: TMcpStdioTransport;
  tool: IMcpTool;
  inputFile, outputFile: TFileName;
  request, requestLine, responseText: RawUtf8;
  doc, resultDoc: PDocVariantData;
  docVar, resultVar: variant;
  inputBackup, outputBackup: TMcpTextRec;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('StdioTestServer', '1.0');
  transport := nil;
  inputFile := TemporaryFileName;
  outputFile := TemporaryFileName;
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    server.RegisterTool(tool);
    server.Start;

    request := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":2,"b":4,"enabled":true,"name":"x"}}}'#13#10;
    requestLine := TrimU(request);
    Check(FileFromString(request, inputFile));
    Check(FileFromString('', outputFile));

    BackupStdIo(inputBackup, outputBackup);
    AssignFile(Input, inputFile);
    Reset(Input);
    AssignFile(Output, outputFile);
    Rewrite(Output);
    try
      transport := TMcpStdioTransport.Create(server);
      transport.Start;
      if RunFromSynTests then
        transport.ProcessRequest(requestLine);
      Check(WaitForFileNotEmpty(outputFile, 5000));
      CloseFile(Input);   // unblock ReadLn before Stop/WaitFor
      CloseFile(Output);
      transport.Stop;
    finally
      RestoreStdIo(inputBackup, outputBackup);
    end;
    responseText := StringFromFile(outputFile);
    responseText := TrimU(responseText);
    if PosEx(#10, responseText) > 0 then
      responseText := Copy(responseText, LastDelimiter(#10, responseText) + 1, MaxInt);
    responseText := TrimU(responseText);
    docVar := _JsonFast(responseText);
    doc := _Safe(docVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    Check(resultDoc^.IsObject);
  finally
    transport.Free;
    server.Free;
    DeleteFile(inputFile);
    DeleteFile(outputFile);
  end;
end;

procedure TTestMcpTransports.StdioTransportMultiple;
var
  server: TMcpServer;
  transport: TMcpStdioTransport;
  tool: IMcpTool;
  inputFile, outputFile: TFileName;
  request1, request2, responseText: RawUtf8;
  inputBackup, outputBackup: TMcpTextRec;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('StdioTestServer', '1.0');
  transport := nil;
  inputFile := TemporaryFileName;
  outputFile := TemporaryFileName;
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    server.RegisterTool(tool);
    server.Start;

    request1 := '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":2,"b":4,"enabled":true,"name":"x"}}}'#13#10;
    request2 := '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":10,"b":5,"enabled":true,"name":"x"}}}'#13#10;
    Check(FileFromString(request1 + request2, inputFile));
    Check(FileFromString('', outputFile));

    BackupStdIo(inputBackup, outputBackup);
    AssignFile(Input, inputFile);
    Reset(Input);
    AssignFile(Output, outputFile);
    Rewrite(Output);
    try
      transport := TMcpStdioTransport.Create(server);
      transport.Start;
      if RunFromSynTests then
      begin
        transport.ProcessRequest(TrimU(request1));
        transport.ProcessRequest(TrimU(request2));
      end;
      Check(WaitForFileLineCount(outputFile, 2, 5000));
      CloseFile(Input);   // unblock ReadLn before Stop/WaitFor
      CloseFile(Output);
      transport.Stop;
    finally
      RestoreStdIo(inputBackup, outputBackup);
    end;

    responseText := StringFromFile(outputFile);
    Check(PosEx('2 + 4 = 6', responseText) > 0);
    Check(PosEx('10 + 5 = 15', responseText) > 0);
  finally
    transport.Free;
    server.Free;
    DeleteFile(inputFile);
    DeleteFile(outputFile);
  end;
end;

procedure TTestMcpTransports.StdioTransportBadJson;
var
  server: TMcpServer;
  transport: TMcpStdioTransport;
  inputFile, outputFile: TFileName;
  responseText: RawUtf8;
  doc, errDoc: PDocVariantData;
  docVar, errVar: variant;
  code: integer;
  code64: Int64;
  okCode: boolean;
  inputBackup, outputBackup: TMcpTextRec;
begin
  server := TMcpServer.Create('StdioTestServer', '1.0');
  transport := nil;
  inputFile := TemporaryFileName;
  outputFile := TemporaryFileName;
  try
    server.Start;
    Check(FileFromString('{'#13#10, inputFile));
    Check(FileFromString('', outputFile));

    BackupStdIo(inputBackup, outputBackup);
    AssignFile(Input, inputFile);
    Reset(Input);
    AssignFile(Output, outputFile);
    Rewrite(Output);
    try
      transport := TMcpStdioTransport.Create(server);
      transport.Start;
      if RunFromSynTests then
        transport.ProcessRequest('{');
      Check(WaitForFileNotEmpty(outputFile, 5000));
      CloseFile(Input);   // unblock ReadLn before Stop/WaitFor
      CloseFile(Output);
      transport.Stop;
    finally
      RestoreStdIo(inputBackup, outputBackup);
    end;

    responseText := StringFromFile(outputFile);
    responseText := TrimU(responseText);
    docVar := _JsonFast(responseText);
    doc := _Safe(docVar);
    errVar := doc^.GetValueOrNull('error');
    errDoc := _Safe(errVar);
    Check(errDoc^.IsObject);
    okCode := VariantToInt64Loose(errDoc^.GetValueOrDefault('code', Null), code64);
    if okCode then
      code := integer(code64)
    else
      code := 0;
    Check(code <> 0);
  finally
    transport.Free;
    server.Free;
    DeleteFile(inputFile);
    DeleteFile(outputFile);
  end;
end;

end.

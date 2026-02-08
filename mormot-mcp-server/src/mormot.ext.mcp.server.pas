/// MCP Transport Layer - HTTP and SSE Implementations
// - this unit is part of the mormot-mcp-server project
// - licensed under MPL/GPL/LGPL three license
unit mormot.ext.mcp.server;

{
  *****************************************************************************

   MCP Server Transport Implementations
    - Abstract Transport Base Class
    - HTTP Transport using THttpAsyncServer
    - SSE Transport with Session Management

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

{$define WITH_LOGS}

uses
  classes,
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.rtti,
  mormot.core.log,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers,
  mormot.core.json,
  mormot.core.data,
  mormot.core.variants,
  mormot.core.perf,
  mormot.core.collections,
  mormot.core.threads,
  mormot.net.sock,
  mormot.net.http,
  mormot.net.server,
  mormot.net.async,
  mormot.ext.mcp;


{ ************ Abstract Transport Base }

type
  /// Abstract base class for MCP transports
  TMcpTransportBase = class(TInterfacedObject)
  protected
    fServer: TMcpServer;
    fActive: boolean;
    fPort: integer;
    fHost: RawUtf8;
  public
    /// initialize with MCP server instance
    constructor Create(aServer: TMcpServer); reintroduce; virtual;
    /// start the transport
    procedure Start; virtual; abstract;
    /// stop the transport
    procedure Stop; virtual; abstract;
    /// check if transport is active
    function IsActive: boolean;
    /// the port number
    property Port: integer read fPort write fPort;
    /// the host address
    property Host: RawUtf8 read fHost write fHost;
  end;


{ ************ HTTP Transport }

type
  /// HTTP transport using mORMot's async HTTP server
  // - handles POST requests with JSON-RPC payload
  // - supports CORS for browser clients
  {$M+}
  TMcpHttpTransport = class(TMcpTransportBase)
  private
    fHttpServer: THttpAsyncServer;
    fEndpoint: RawUtf8;
    fCorsEnabled: boolean;
    fCorsOrigins: RawUtf8;
    procedure SetCorsHeaders(var Ctxt: THttpServerRequest);
  public
    /// initialize HTTP transport
    constructor Create(aServer: TMcpServer); override;
    /// finalize and cleanup
    destructor Destroy; override;
    /// start HTTP server
    procedure Start; override;
    /// stop HTTP server
    procedure Stop; override;
    /// the endpoint path for MCP requests (default: '/mcp')
    property Endpoint: RawUtf8 read fEndpoint write fEndpoint;
    /// enable/disable CORS support
    property CorsEnabled: boolean read fCorsEnabled write fCorsEnabled;
    /// allowed CORS origins ('*' for all)
    property CorsOrigins: RawUtf8 read fCorsOrigins write fCorsOrigins;

  published
    // all service URI are implemented by these published methods using RTTI
    function mcp(ctxt: THttpServerRequest): cardinal;
  end;


{ ************ SSE Transport with Session Management }

type
  /// SSE session information
  TMcpSseSession = class
  public
    /// unique session identifier
    SessionId: RawUtf8;
    /// async connection handle for the active SSE stream (0 if none)
    ConnectionHandle: TConnectionAsyncHandle;
    /// message queue for this session (tofo: migrate to IKeyValue)
    MessageQueue: TRawUtf8DynArray;
    /// lock for thread-safe queue access
    QueueLock: TLightLock;
    /// last activity timestamp
    LastActivity: TDateTime;
    /// initialize session
    constructor Create(const aSessionId: RawUtf8);
    /// cleanup
    destructor Destroy; override;
    /// enqueue a message
    procedure EnqueueMessage(const aMessage: RawUtf8);
    /// dequeue all messages
    function DequeueMessages: TRawUtf8DynArray;
  end;

  /// SSE transport with session management
  // - uses Server-Sent Events for streaming responses
  // - maintains sessions for async communication
  TMcpSseTransport = class(TMcpTransportBase)
  private
    fHttpServer: THttpAsyncServer;
    fSessions: IKeyValue<RawUtf8, TMcpSseSession>;  // sessionId -> TMcpSseSession
    fSseEndpoint: RawUtf8;
    fMessagesEndpoint: RawUtf8;
    fCorsEnabled: boolean;
    fCorsOrigins: RawUtf8;
    function MatchesSseEndpoint(const aUrl: RawUtf8): boolean;
    function AcceptsEventStream(const aHeaders: RawUtf8): boolean;
    function BuildSseHeaders: RawUtf8;
    function BuildSseEvent(const aEvent, aData: RawUtf8): RawUtf8;
    function BuildSseChunk(const aData: RawUtf8): RawUtf8;
    function BuildSseResponse(const aSessionId: RawUtf8;
      const aQueued: TRawUtf8DynArray): RawUtf8;
    function TrySendSessionMessage(aSession: TMcpSseSession;
      const aMessage: RawUtf8): boolean;
    procedure AttachSessionConnection(const aSessionId: RawUtf8;
      aHandle: TConnectionAsyncHandle);
    procedure DetachSessionConnection(const aSessionId: RawUtf8);
    procedure RemoveSession(const aSessionId: RawUtf8);
    procedure ClearSessions;
    function OnSseConnect(Ctxt: THttpServerRequestAbstract): cardinal;
    function OnPostMessage(Ctxt: THttpServerRequestAbstract): cardinal;
    function OnSseOptions(Ctxt: THttpServerRequestAbstract): cardinal;
    function OnMessagesOptions(Ctxt: THttpServerRequestAbstract): cardinal;

    procedure SetCorsHeaders(var Ctxt: THttpServerRequestAbstract);
    function GetOrCreateSession(const aSessionId: RawUtf8): TMcpSseSession;
    procedure CleanupExpiredSessions;
  public
    /// initialize SSE transport
    constructor Create(aServer: TMcpServer); override;
    /// finalize and cleanup
    destructor Destroy; override;
    /// start SSE server
    procedure Start; override;
    /// stop SSE server
    procedure Stop; override;
    /// push notification to a specific session
    procedure PushNotification(const aSessionId, aNotification: RawUtf8);
    /// SSE endpoint path (default: '/sse')
    property SseEndpoint: RawUtf8 read fSseEndpoint write fSseEndpoint;
    /// messages endpoint path (default: '/messages')
    property MessagesEndpoint: RawUtf8 read fMessagesEndpoint write fMessagesEndpoint;
    /// enable/disable CORS support
    property CorsEnabled: boolean read fCorsEnabled write fCorsEnabled;
    /// allowed CORS origins
    property CorsOrigins: RawUtf8 read fCorsOrigins write fCorsOrigins;
  end;


implementation

type
  TMcpSseAsyncServer = class(THttpAsyncServer)
  public
    Transport: TMcpSseTransport;
    constructor Create(const aPort: RawUtf8; const OnStart, OnStop: TOnNotifyThread;
      const ProcessName: RawUtf8; ServerThreadPoolCount: integer = 32;
      KeepAliveTimeOut: integer = 30000; ProcessOptions: THttpServerOptions = [];
      aLog: TSynLogClass = nil); override;
  end;

  TMcpSseAsyncConnection = class(THttpAsyncServerConnection)
  protected
    fSessionId: RawUtf8;
    function DecodeHeaders: integer; override;
    function OnRead: TPollAsyncSocketOnReadWrite; override;
    function AfterWrite: TPollAsyncSocketOnReadWrite; override;
    procedure OnClose; override;
  end;


{ ************ TMcpTransportBase }

constructor TMcpTransportBase.Create(aServer: TMcpServer);
begin
  inherited Create;
  fServer := aServer;
  fActive := false;
  fPort := 3000;
  fHost := 'localhost';
end;

function TMcpTransportBase.IsActive: boolean;
begin
  result := fActive;
end;

{ ************ TMcpSseAsyncServer / TMcpSseAsyncConnection }

constructor TMcpSseAsyncServer.Create(const aPort: RawUtf8;
  const OnStart, OnStop: TOnNotifyThread; const ProcessName: RawUtf8;
  ServerThreadPoolCount: integer; KeepAliveTimeOut: integer;
  ProcessOptions: THttpServerOptions; aLog: TSynLogClass);
begin
  fConnectionClass := TMcpSseAsyncConnection; // must be set before inherited
  inherited Create(aPort, OnStart, OnStop, ProcessName, ServerThreadPoolCount,
    KeepAliveTimeOut, ProcessOptions, aLog);
end;

function TMcpSseAsyncConnection.DecodeHeaders: integer;
var
  serv: TMcpSseAsyncServer;
  transport: TMcpSseTransport;
  session: TMcpSseSession;
  sessionId: RawUtf8;
  queued: TRawUtf8DynArray;
  response: RawUtf8;
begin
  result := inherited DecodeHeaders;
  if result <> HTTP_SUCCESS then
    exit;

  serv := fServer as TMcpSseAsyncServer;
  transport := serv.Transport;
  if (transport = nil) or
     (fHttp.CommandMethod <> 'GET') or
     not transport.MatchesSseEndpoint(fHttp.CommandUri) or
     not transport.AcceptsEventStream(fHttp.Headers) then
    exit;

  sessionId := ToUtf8(RandomGuid);
  session := transport.GetOrCreateSession(sessionId);
  transport.AttachSessionConnection(sessionId, Handle);
  fSessionId := sessionId;

  queued := session.DequeueMessages;
  response := transport.BuildSseResponse(sessionId, queued);

  fHttp.State := hrsUpgraded;
  include(fInternalFlags, ifSeparateWLock); // allow async writes while idle
  if not fOwner.WriteString(self, response, 1000) then
    result := HTTP_BADREQUEST;
end;

function TMcpSseAsyncConnection.OnRead: TPollAsyncSocketOnReadWrite;
begin
  if fHttp.State <> hrsUpgraded then
    result := inherited OnRead
  else
  begin
    fRd.Reset; // ignore any input on SSE stream
    result := soContinue;
  end;
end;

function TMcpSseAsyncConnection.AfterWrite: TPollAsyncSocketOnReadWrite;
begin
  if fHttp.State <> hrsUpgraded then
    result := inherited AfterWrite
  else
    result := soContinue;
end;

procedure TMcpSseAsyncConnection.OnClose;
var
  serv: TMcpSseAsyncServer;
begin
  inherited OnClose;
  if fSessionId = '' then
    exit;
  serv := fServer as TMcpSseAsyncServer;
  if serv.Transport <> nil then
    serv.Transport.DetachSessionConnection(fSessionId);
  fSessionId := '';
end;


{ ************ TMcpHttpTransport }

constructor TMcpHttpTransport.Create(aServer: TMcpServer);
begin
  inherited Create(aServer);
  fEndpoint := '/mcp';
  fCorsEnabled := true;
  fCorsOrigins := '*';
end;

destructor TMcpHttpTransport.Destroy;
begin
  Stop;
  inherited;
end;

procedure TMcpHttpTransport.SetCorsHeaders(var Ctxt: THttpServerRequest);
begin
  if not fCorsEnabled then
    exit;
    
  Ctxt.OutCustomHeaders := Ctxt.OutCustomHeaders +
    'Access-Control-Allow-Origin: ' + fCorsOrigins + #13#10 +
    'Access-Control-Allow-Methods: POST, GET, OPTIONS' + #13#10 +
    'Access-Control-Allow-Headers: Content-Type' + #13#10 +
    'Access-Control-Max-Age: 86400' + #13#10;
end;

function TMcpHttpTransport.mcp(ctxt: THttpServerRequest): cardinal;
var
  requestBody, responseBody: RawUtf8;
begin
  // Set CORS headers
  SetCorsHeaders(Ctxt);

  // Handle OPTIONS preflight
  if Ctxt.Method = 'OPTIONS' then
    exit(HTTP_NOCONTENT);

  // Handle GET for server info
  if Ctxt.Method = 'GET' then
  begin
    result := Ctxt.SetOutJson('{"status":"active","protocol":"MCP"}');
    exit;
  end;

  // Handle POST for JSON-RPC
  if Ctxt.Method <> 'POST' then
  begin
    Ctxt.SetOutJson('{"error":"Only POST method supported"}');
    exit(HTTP_BADREQUEST);
  end;

  // Read request body
  requestBody := Ctxt.InContent;
  
  // Execute MCP request
  responseBody := fServer.ExecuteRequest(requestBody, '');
  
  // Send response
  if responseBody = '' then
    exit(HTTP_NOCONTENT);

  result := Ctxt.SetOutJson(responseBody);
end;

procedure TMcpHttpTransport.Start;
begin
  if fActive then
    exit;

  // Create and start HTTP server
  fHttpServer := THttpAsyncServer.Create(
    ToUtf8(fPort), nil, nil, 'mcp', 32,
    5 * 60 * 1000,         // 5 minutes keep alive connections
    [hsoNoXPoweredHeader,  // not needed for a benchmark
     //hsoHeadersInterning,  // reduce memory contention for /plaintext and /json
     hsoNoStats,           // disable low-level statistic counters
     //hsoThreadCpuAffinity, // worse scaling on multi-servers
     hsoThreadSmooting,    // seems a good option, even if not magical
     hsoEnablePipelining,  // as expected by /plaintext
     {$ifdef WITH_LOGS}
     hsoLogVerbose,
     {$endif WITH_LOGS}
     hsoIncludeDateHeader  // required by TFB General Test Requirements #5
    ]);
  //  if pin2Core <> -1 then
  //    fHttpServer.Async.SetCpuAffinity(pin2Core);
  fHttpServer.HttpQueueLength := 10000; // needed e.g. from wrk/ab benchmarks
  fHttpServer.ServerName := 'MMCP-HTTP';
  // use default routing using RTTI on the TRawAsyncServer published methods
  fHttpServer.Route.RunMethods(
    [urmGet, urmPost, urmOptions, urmPut, urmDelete, urmPatch], self);
  // wait for the server to be ready and raise exception e.g. on binding issue
  fHttpServer.WaitStarted;
  
  fActive := true;
end;

procedure TMcpHttpTransport.Stop;
begin
  if not fActive then
    exit;
    
  if fHttpServer <> nil then
  begin
    fHttpServer.Shutdown;
    FreeAndNil(fHttpServer);
  end;
  
  fActive := false;
end;


{ ************ TMcpSseSession }

constructor TMcpSseSession.Create(const aSessionId: RawUtf8);
begin
  inherited Create;
  SessionId := aSessionId;
  ConnectionHandle := 0;
  QueueLock.Init;
  LastActivity := NowUtc;
end;

destructor TMcpSseSession.Destroy;
begin
  QueueLock.Done;
  inherited;
end;

procedure TMcpSseSession.EnqueueMessage(const aMessage: RawUtf8);
begin
  QueueLock.Lock;
  try
    AddRawUtf8(MessageQueue, aMessage);
    LastActivity := NowUtc;
  finally
    QueueLock.UnLock;
  end;
end;

function TMcpSseSession.DequeueMessages: TRawUtf8DynArray;
begin
  QueueLock.Lock;
  try
    result := MessageQueue;
    MessageQueue := nil;
    LastActivity := NowUtc;
  finally
    QueueLock.UnLock;
  end;
end;


{ ************ TMcpSseTransport }

constructor TMcpSseTransport.Create(aServer: TMcpServer);
begin
  inherited Create(aServer);
  fSseEndpoint := '/sse';
  fMessagesEndpoint := '/messages';
  fCorsEnabled := true;
  fCorsOrigins := '*';
  fSessions := Collections.NewPlainKeyValue<RawUtf8, TMcpSseSession>(
    [kvoThreadSafe], 60);
end;

destructor TMcpSseTransport.Destroy;
begin
  Stop;
  ClearSessions;
  fSessions := nil;
  inherited;
end;

procedure TMcpSseTransport.SetCorsHeaders(var Ctxt: THttpServerRequestAbstract);
begin
  if not fCorsEnabled then
    exit;
    
  Ctxt.OutCustomHeaders := Ctxt.OutCustomHeaders +
    'Access-Control-Allow-Origin: ' + fCorsOrigins + #13#10 +
    'Access-Control-Allow-Methods: POST, GET, OPTIONS' + #13#10 +
    'Access-Control-Allow-Headers: Content-Type' + #13#10;
end;

function TMcpSseTransport.MatchesSseEndpoint(const aUrl: RawUtf8): boolean;
var
  len: integer;
begin
  result := false;
  len := length(fSseEndpoint);
  if (len = 0) or (aUrl = '') then
    exit;
  if length(aUrl) = len then
    result := (aUrl = fSseEndpoint)
  else if (length(aUrl) > len) and
          (CompareMem(pointer(aUrl), pointer(fSseEndpoint), len)) and
          (aUrl[len + 1] = '?') then
    result := true;
end;

function TMcpSseTransport.AcceptsEventStream(const aHeaders: RawUtf8): boolean;
var
  p: PUtf8Char;
  len: PtrInt;
  value: RawUtf8;
begin
  result := true; // be lenient if Accept header is missing
  if aHeaders = '' then
    exit;
  p := FindNameValuePointer(pointer(aHeaders), 'ACCEPT: ', len);
  if p = nil then
    p := FindNameValuePointer(pointer(aHeaders), 'ACCEPT:', len);
  if p = nil then
    exit;
  FastSetString(value, p, len);
  value := LowerCaseU(value);
  result := PosEx('text/event-stream', value) > 0;
end;

function TMcpSseTransport.BuildSseHeaders: RawUtf8;
begin
  result :=
    'HTTP/1.1 200 OK'#13#10 +
    'Content-Type: text/event-stream'#13#10 +
    'Cache-Control: no-cache'#13#10 +
    'Connection: keep-alive'#13#10 +
    'X-Accel-Buffering: no'#13#10 +
    'Transfer-Encoding: chunked'#13#10;
  if fCorsEnabled then
    result := result +
      'Access-Control-Allow-Origin: ' + fCorsOrigins + #13#10 +
      'Access-Control-Allow-Methods: POST, GET, OPTIONS' + #13#10 +
      'Access-Control-Allow-Headers: Content-Type' + #13#10;
  result := result + #13#10;
end;

function TMcpSseTransport.BuildSseEvent(const aEvent, aData: RawUtf8): RawUtf8;
var
  i, start: integer;
begin
  result := '';
  if aEvent <> '' then
    result := 'event: ' + aEvent + #13#10;
  if aData = '' then
    result := result + 'data:' + #13#10
  else
  begin
    start := 1;
    for i := 1 to length(aData) do
      if aData[i] = #10 then
      begin
        result := result + 'data: ' + copy(aData, start, i - start) + #13#10;
        start := i + 1;
      end;
    if start <= length(aData) then
      result := result + 'data: ' + copy(aData, start, MaxInt) + #13#10;
  end;
  result := result + #13#10;
end;

function TMcpSseTransport.BuildSseChunk(const aData: RawUtf8): RawUtf8;
begin
  result := StringToUtf8(IntToHex(length(aData), 1)) + #13#10 +
    aData + #13#10;
end;

function TMcpSseTransport.BuildSseResponse(const aSessionId: RawUtf8;
  const aQueued: TRawUtf8DynArray): RawUtf8;
var
  i: integer;
  endpointUrl: RawUtf8;
  payload: RawUtf8;
begin
  result := BuildSseHeaders;
  endpointUrl := FormatUtf8('%?session_id=%', [fMessagesEndpoint, aSessionId]);
  payload := BuildSseEvent('endpoint', endpointUrl);
  result := result + BuildSseChunk(payload);
  for i := 0 to length(aQueued) - 1 do
  begin
    payload := BuildSseEvent('message', aQueued[i]);
    result := result + BuildSseChunk(payload);
  end;
end;

function TMcpSseTransport.TrySendSessionMessage(aSession: TMcpSseSession;
  const aMessage: RawUtf8): boolean;
var
  handle: TConnectionAsyncHandle;
  conn: TAsyncConnection;
  payload: RawUtf8;
begin
  result := false;
  if (aSession = nil) or (fHttpServer = nil) then
    exit;
  aSession.QueueLock.Lock;
  try
    handle := aSession.ConnectionHandle;
  finally
    aSession.QueueLock.UnLock;
  end;
  if handle = 0 then
    exit;
  conn := TAsyncConnection(fHttpServer.Async.ConnectionFindAndWaitLock(handle, true, 40));
  if conn = nil then
    exit;
  try
    payload := BuildSseChunk(BuildSseEvent('message', aMessage));
    result := fHttpServer.Async.WriteString(conn, payload, 1000);
  finally
    conn.UnLock(true);
  end;
end;

procedure TMcpSseTransport.AttachSessionConnection(const aSessionId: RawUtf8;
  aHandle: TConnectionAsyncHandle);
var
  session: TMcpSseSession;
begin
  if fSessions.TryGetValue(aSessionId, session) then
  begin
    session.QueueLock.Lock;
    try
      session.ConnectionHandle := aHandle;
      session.LastActivity := NowUtc;
    finally
      session.QueueLock.UnLock;
    end;
  end;
end;

procedure TMcpSseTransport.DetachSessionConnection(const aSessionId: RawUtf8);
var
  session: TMcpSseSession;
begin
  if fSessions.TryGetValue(aSessionId, session) then
  begin
    session.QueueLock.Lock;
    try
      session.ConnectionHandle := 0;
      session.LastActivity := NowUtc;
    finally
      session.QueueLock.UnLock;
    end;
  end;
end;

procedure TMcpSseTransport.RemoveSession(const aSessionId: RawUtf8);
var
  session: TMcpSseSession;
begin
  if fSessions.Extract(aSessionId, session) then
    session.Free;
end;

procedure TMcpSseTransport.ClearSessions;
var
  i: PtrInt;
  session: TMcpSseSession;
begin
  if fSessions = nil then
    exit;

  fSessions.Clear;
end;

function TMcpSseTransport.GetOrCreateSession(const aSessionId: RawUtf8): TMcpSseSession;
var
  session: TMcpSseSession;
begin
  if not fSessions.TryGetValue(aSessionId, result) then
  begin
    session := TMcpSseSession.Create(aSessionId);
    fSessions.Add(aSessionId, session);
    result := session;
  end;
end;

procedure TMcpSseTransport.CleanupExpiredSessions;
begin
  fSessions.DeleteDeprecated;
end;

function TMcpSseTransport.OnSseConnect(Ctxt: THttpServerRequestAbstract): cardinal;
var
  sessionId, endpointUrl: RawUtf8;
  handshake: RawUtf8;
begin
  // Set SSE headers
  SetCorsHeaders(Ctxt);
  Ctxt.OutContentType := 'text/event-stream';
  Ctxt.OutCustomHeaders := Ctxt.OutCustomHeaders +
    'Cache-Control: no-cache' + #13#10 +
    'Connection: keep-alive' + #13#10;

  // Generate session ID
  sessionId := ToUtf8(RandomGuid);
  
  // Create session
  GetOrCreateSession(sessionId);
  
  // Send endpoint handshake
  endpointUrl := FormatUtf8('%?session_id=%', [fMessagesEndpoint, sessionId]);
  handshake := FormatUtf8('event: endpoint'#13#10'data: %'#13#10#13#10, [endpointUrl]);
  
  Ctxt.OutContent := handshake;
  Ctxt.RespStatus := HTTP_SUCCESS;
  result := HTTP_SUCCESS;
end;

function TMcpSseTransport.OnPostMessage(Ctxt: THttpServerRequestAbstract): cardinal;
var
  sessionId, requestBody, responseBody: RawUtf8;
  session: TMcpSseSession;
begin
  // Set CORS headers
  SetCorsHeaders(Ctxt);

  // Get session ID from query (accept both session_id and sessionId)
  Ctxt.UrlParam('SESSION_ID=', sessionId);
  if sessionId = '' then
    Ctxt.UrlParam('SESSIONID=', sessionId);
  if sessionId = '' then
  begin
    Ctxt.SetOutJson('{"error":"Missing session_id"}');
    exit(HTTP_BADREQUEST);
  end;

  // Find session
  if not fSessions.TryGetValue(sessionId, session) then
  begin
    Ctxt.SetOutJson('{"error":"Session not found"}');
    exit(HTTP_NOTFOUND);
  end;

  // Read request
  requestBody := Ctxt.InContent;
  
  // Execute MCP request
  responseBody := fServer.ExecuteRequest(requestBody, sessionId);
  
  // Send or enqueue response for SSE delivery
  if responseBody <> '' then
    if not TrySendSessionMessage(session, responseBody) then
      session.EnqueueMessage(responseBody);
  
  // Send accepted response
  Ctxt.SetOutJson('{"status":"accepted"}');
  result := HTTP_ACCEPTED;
end;

function TMcpSseTransport.OnSseOptions(Ctxt: THttpServerRequestAbstract): cardinal;
begin
  SetCorsHeaders(Ctxt);
  result := HTTP_NOCONTENT;
end;

function TMcpSseTransport.OnMessagesOptions(Ctxt: THttpServerRequestAbstract): cardinal;
begin
  SetCorsHeaders(Ctxt);
  result := HTTP_NOCONTENT;
end;

procedure TMcpSseTransport.PushNotification(const aSessionId, aNotification: RawUtf8);
var
  session: TMcpSseSession;
begin
  if fSessions.TryGetValue(aSessionId, session) then
    if not TrySendSessionMessage(session, aNotification) then
      session.EnqueueMessage(aNotification);
end;

procedure TMcpSseTransport.Start;
begin
  if fActive then
    exit;

  // Create and start HTTP server
  fHttpServer := TMcpSseAsyncServer.Create(
    ToUtf8(fPort), nil, nil, 'mcp', 32,
    5 * 60 * 1000,         // 5 minutes keep alive connections
    [hsoNoXPoweredHeader,  // not needed for a benchmark
     //hsoHeadersInterning,  // reduce memory contention for /plaintext and /json
     hsoNoStats,           // disable low-level statistic counters
     //hsoThreadCpuAffinity, // worse scaling on multi-servers
     hsoThreadSmooting,    // seems a good option, even if not magical
     {$ifdef WITH_LOGS}
     hsoLogVerbose,
     {$endif WITH_LOGS}
     hsoIncludeDateHeader  // required by TFB General Test Requirements #5
    ]);
  fHttpServer.ServerName := 'MMCP-SSE';

  TMcpSseAsyncServer(fHttpServer).Transport := self;

  // Register endpoints
  fHttpServer.Route.Get(fSseEndpoint, OnSseConnect);
  fHttpServer.Route.Post(fMessagesEndpoint, OnPostMessage);
  fHttpServer.Route.Options(fSseEndpoint, OnSseOptions);
  fHttpServer.Route.Options(fMessagesEndpoint, OnMessagesOptions);

  fHttpServer.WaitStarted;
  
  fActive := true;
end;

procedure TMcpSseTransport.Stop;
begin
  if not fActive then
    exit;
    
  if fHttpServer <> nil then
  begin
    fHttpServer.Shutdown;
    FreeAndNil(fHttpServer);
  end;
  
  // Clear sessions
  ClearSessions;
  
  fActive := false;
end;


end.

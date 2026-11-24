// - regression tests for mormot.ext.mcp
unit test.mcp.core;

interface

{$I mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers,
  mormot.core.rtti,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.test,
  mormot.ext.mcp;

type
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

  /// raises a different exception depending on the Name argument
  TFailTool = class(TMcpToolBase<TCalcParams>)
  protected
    function ExecuteTyped(const aParams: TCalcParams;
      const aAuthCtx: TMcpAuthContext): variant; override;
  end;

  TVersionResource = class(TMcpResourceBase)
  protected
    function GetContent: RawUtf8; override;
  end;

  TTestMcpCore = class(TSynTestCase)
  protected
    procedure EnsureCalcParamsRtti;
    function VariantToInt64Loose(const V: variant; out aValue: Int64): boolean;
    procedure CheckErrorResponse(const aResponse: RawUtf8;
      aExpectedCode: integer; const aMessageContains: RawUtf8);
    function DocPropType(const props: PDocVariantData;
      const propName: RawUtf8): RawUtf8;
    function NewServer: TMcpServer;
    // - aIdJson is the expected JSON of the "id" member, or '' if it must be absent
    procedure CheckError(aServer: TMcpServer; const aRequest: RawUtf8;
      aExpectedCode: integer; const aIdJson: RawUtf8;
      const aMessageContains: RawUtf8 = '');
  published
    procedure SchemaFromRecord;
    procedure JsonRpcProcessor;
    procedure ServerToolsResources;
    procedure ResponseBuilderTextAndFile;
    procedure ServerNotActive;
    procedure BadRequests;
    procedure NotificationsNoResponse;
    procedure ParseErrors;
    procedure InvalidRequests;
    procedure RequestIdEchoed;
    procedure ClientResponsesIgnored;
    procedure MissingParams;
    procedure ResourceNotFoundData;
    procedure ToolExceptions;
    procedure NotificationWhileStopped;
    procedure NotificationMethodAsRequest;
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

{ TFailTool }

function TFailTool.ExecuteTyped(const aParams: TCalcParams;
  const aAuthCtx: TMcpAuthContext): variant;
begin
  if aParams.Name = 'convert' then
    raise EConvertError.Create('secret /etc/passwd')
  else if aParams.Name = 'plain' then
    raise EMcpException.Create('secret plain')
  else if aParams.Name = 'coded' then
    raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS, 'bad %', ['input']);
  result := _ObjFast(['content', _ArrFast([])]);
end;

{ TVersionResource }

function TVersionResource.GetContent: RawUtf8;
begin
  result := '{"version":"1.0.0","protocol":"MCP"}';
end;

{ TTestMcpCore }

procedure TTestMcpCore.EnsureCalcParamsRtti;
begin
  //{$ifndef HASEXTRECORDRTTI}
  if not RecordHasFields(TypeInfo(TCalcParams)) then
    Rtti.RegisterFromText(TypeInfo(TCalcParams),
      'A,B:integer Enabled:boolean Name:RawUtf8');
  //{$endif HASEXTRECORDRTTI}
end;

function TTestMcpCore.VariantToInt64Loose(const V: variant; out aValue: Int64): boolean;
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

procedure TTestMcpCore.CheckErrorResponse(const aResponse: RawUtf8;
  aExpectedCode: integer; const aMessageContains: RawUtf8);
var
  doc, errDoc: PDocVariantData;
  docVar, errVar: variant;
  code: integer;
  code64: Int64;
  okCode: boolean;
  msg: RawUtf8;
begin
  docVar := _JsonFast(aResponse);
  doc := _Safe(docVar);
  errVar := doc^.GetValueOrNull('error');
  errDoc := _Safe(errVar);
  Check(errDoc^.IsObject);
  okCode := VariantToInt64Loose(errDoc^.GetValueOrDefault('code', 0), code64);
  if okCode then
    code := integer(code64)
  else
    code := 0;
  if aExpectedCode <> 0 then
    CheckEqual(code, aExpectedCode)
  else
    Check(code <> 0);
  if aMessageContains <> '' then
  begin
    errDoc^.GetAsRawUtf8('message', msg);
    Check(PosEx(aMessageContains, msg) > 0);
  end;
end;

function TTestMcpCore.DocPropType(const props: PDocVariantData;
  const propName: RawUtf8): RawUtf8;
var
  prop: variant;
  propDoc: PDocVariantData;
begin
  result := '';
  if (props = nil) or not props^.IsObject then
    exit;
  prop := props^.GetValueOrNull(propName);
  propDoc := _Safe(prop);
  if propDoc^.IsObject then
    propDoc^.GetAsRawUtf8('type', result);
end;

function TTestMcpCore.NewServer: TMcpServer;
begin
  EnsureCalcParamsRtti;
  result := TMcpServer.Create('TestServer', '1.0');
  result.RegisterTool(TCalcTool.Create('calc', 'Add two numbers'));
  result.RegisterTool(TFailTool.Create('fail', 'Raise an exception'));
  result.RegisterResource(TVersionResource.Create('version://info', 'Version',
    'Server version information', 'application/json'));
  result.Start;
end;

procedure TTestMcpCore.CheckError(aServer: TMcpServer; const aRequest: RawUtf8;
  aExpectedCode: integer; const aIdJson: RawUtf8; const aMessageContains: RawUtf8);
var
  response: RawUtf8;
  doc: TDocVariantData;
  ndx: PtrInt;
begin
  response := aServer.ExecuteRequest(aRequest);
  CheckErrorResponse(response, aExpectedCode, aMessageContains);
  if CheckFailed(doc.InitJson(response, JSON_FAST_FLOAT), aRequest) then
    exit;
  ndx := doc.GetValueIndex('id');
  if aIdJson = '' then
    Check(ndx < 0, 'id must be absent')
  else if not CheckFailed(ndx >= 0, 'id missing') then
    CheckEqual(VariantSaveJson(doc.Values[ndx]), aIdJson, 'id');
end;

procedure TTestMcpCore.SchemaFromRecord;
var
  schema: variant;
  doc, props, req: PDocVariantData;
  propsVar: variant;
  typ: RawUtf8;
begin
  EnsureCalcParamsRtti;
  schema := TMcpSchemaGenerator.GenerateSchema(TypeInfo(TCalcParams));
  doc := _Safe(schema);
  Check(doc^.IsObject);
  Check(doc^.GetAsRawUtf8('type', typ));
  CheckEqual(typ, 'object');

  propsVar := doc^.GetValueOrNull('properties');
  props := _Safe(propsVar);
  Check(props^.IsObject);
  CheckEqual(DocPropType(props, 'a'), 'integer');
  CheckEqual(DocPropType(props, 'b'), 'integer');
  CheckEqual(DocPropType(props, 'enabled'), 'boolean');
  CheckEqual(DocPropType(props, 'name'), 'string');
end;

procedure TTestMcpCore.JsonRpcProcessor;
var
  proc: TMcpJsonRpcProcessor;
  msg: TMcpJsonRpcMessage;
  response: RawUtf8;
  doc, resultDoc: PDocVariantData;
  responseVar, resultVar: variant;
  jsonrpc: RawUtf8;
  v: variant;
  okFlag: boolean;
begin
  proc := TMcpJsonRpcProcessor.Create('TestServer', '1.0');
  try
    Check(proc.ParseMessage('{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}',
      msg) = mmkRequest);
    CheckEqual(msg.Method, 'ping');
    Check(VariantToIntegerDef(msg.Id, 0) = 1);

    v := _ObjFast(['ok', true]);
    response := proc.CreateSuccessResponse(msg.Id, v);
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    Check(doc^.GetAsRawUtf8('jsonrpc', jsonrpc));
    CheckEqual(jsonrpc, '2.0');
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    Check(resultDoc^.IsObject);
    Check(resultDoc^.GetAsBoolean('ok', okFlag));
    Check(okFlag);
  finally
    proc.Free;
  end;
end;

procedure TTestMcpCore.ServerToolsResources;
var
  server: TMcpServer;
  tool: IMcpTool;
  res: IMcpResource;
  response: RawUtf8;
  doc, resultDoc, listDoc, itemDoc, contentDoc: PDocVariantData;
  responseVar, resultVar, listVar, contentVar, itemVar: variant;
  toolName: RawUtf8;
  tmp: RawUtf8;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('TestServer', '1.0');
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    res := TVersionResource.Create('version://info', 'Version',
      'Server version information', 'application/json');
    server.RegisterTool(tool);
    server.RegisterResource(res);
    server.Start;

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('tools');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);
    Check(listDoc^.Count >= 1);
    itemVar := listDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('name', toolName));
    CheckEqual(toolName, 'calc');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":5,"b":3,"enabled":true,"name":"x"}}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    contentVar := resultDoc^.GetValueOrNull('content');
    contentDoc := _Safe(contentVar);
    Check(contentDoc^.IsArray);
    Check(contentDoc^.Count = 1);
    itemVar := contentDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('type', tmp));
    CheckEqual(tmp, 'text');
    Check(itemDoc^.GetAsRawUtf8('text', tmp));
    CheckEqual(tmp, '5 + 3 = 8');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('resources');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);
    Check(listDoc^.Count = 1);
    itemVar := listDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('uri', tmp));
    CheckEqual(tmp, 'version://info');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"version://info"}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('contents');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);
    itemVar := listDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('uri', tmp));
    CheckEqual(tmp, 'version://info');
    Check(itemDoc^.GetAsRawUtf8('text', tmp));
    Check(tmp <> '');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ResponseBuilderTextAndFile;
var
  builder: TMcpResponseBuilder;
  response: variant;
  doc, contentDoc, itemDoc: PDocVariantData;
  contentVar, itemVar: variant;
  tmpFile: TFileName;
  content: RawByteString;
  base64: RawUtf8;
  tmp: RawUtf8;
begin
  tmpFile := TemporaryFileName;
  content := 'mcp-test';
  Check(FileFromString(content, tmpFile));
  try
    builder := TMcpResponseBuilder.Create;
    try
      builder.AddText('hello');
      builder.AddFile(StringToUtf8(tmpFile));
      response := builder.Build;
    finally
      builder.Free;
    end;

    doc := _Safe(response);
    contentVar := doc^.GetValueOrNull('content');
    contentDoc := _Safe(contentVar);
    if CheckFailed(contentDoc^.IsArray, 'content not array') then
      exit;
    if CheckFailed(contentDoc^.Count >= 2, 'content count < 2') then
      exit;

    itemVar := contentDoc^.Values[0];
    if CheckFailed(_Safe(itemVar, itemDoc), 'content[0] not object') then
      exit;
    Check(itemDoc^.GetAsRawUtf8('type', tmp));
    CheckEqual(tmp, 'text');
    Check(itemDoc^.GetAsRawUtf8('text', tmp));
    CheckEqual(tmp, 'hello');

    itemVar := contentDoc^.Values[1];
    if CheckFailed(_Safe(itemVar, itemDoc), 'content[1] not object') then
      exit;
    Check(itemDoc^.GetAsRawUtf8('type', tmp));
    CheckEqual(tmp, 'resource');
    base64 := BinToBase64(content);
    Check(itemDoc^.GetAsRawUtf8('data', tmp));
    CheckEqual(tmp, base64);
    Check(itemDoc^.GetAsRawUtf8('mimeType', tmp));
    Check(tmp <> '');
    Check(itemDoc^.GetAsRawUtf8('fileName', tmp));
    Check(tmp <> '');
  finally
    DeleteFile(tmpFile);
  end;
end;

procedure TTestMcpCore.ServerNotActive;
var
  server: TMcpServer;
  response: RawUtf8;
  doc, errDoc: PDocVariantData;
  docVar, errVar: variant;
  code: integer;
begin
  server := TMcpServer.Create('TestServer', '1.0');
  try
    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}');
    docVar := _JsonFast(response);
    doc := _Safe(docVar);
    errVar := doc^.GetValueOrNull('error');
    errDoc := _Safe(errVar);
    Check(errDoc^.IsObject);
    code := errDoc^.GetValueOrDefault('code', 0);
    Check(code = JSONRPC_INTERNAL_ERROR);
    CheckEqual(VariantToIntegerDef(doc^.GetValueOrNull('id'), 0), 1, 'id echoed');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.BadRequests;
var
  server: TMcpServer;
  tool: IMcpTool;
  res: IMcpResource;
  response: RawUtf8;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('TestServer', '1.0');
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    res := TVersionResource.Create('version://info', 'Version',
      'Server version information', 'application/json');
    server.RegisterTool(tool);
    server.RegisterResource(res);
    server.Start;

    response := server.ExecuteRequest('{');
    CheckErrorResponse(response, JSONRPC_PARSE_ERROR, '');

    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":1}');
    CheckErrorResponse(response, JSONRPC_INVALID_REQUEST, '');

    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":2,"method":"nope"}');
    CheckErrorResponse(response, JSONRPC_METHOD_NOT_FOUND, 'Method not found');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{}}');
    CheckErrorResponse(response, JSONRPC_INVALID_PARAMS, 'Missing tool name');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"missing","arguments":{}}}');
    CheckErrorResponse(response, JSONRPC_INVALID_PARAMS, 'Tool not found');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{}}');
    CheckErrorResponse(response, JSONRPC_INVALID_PARAMS, 'Missing uri');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"missing://info"}}');
    CheckErrorResponse(response, MCP_RESOURCE_NOT_FOUND, 'Resource not found');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.NotificationsNoResponse;
var
  server: TMcpServer;
  response: RawUtf8;
begin
  server := TMcpServer.Create('TestServer', '1.0');
  try
    server.Start;
    response := server.ExecuteRequest('{"jsonrpc":"2.0","method":"ping","params":{}}');
    Check(TrimU(response) = '');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ParseErrors;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    CheckError(server, '{', JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":', JSONRPC_PARSE_ERROR, '');
    CheckError(server, 'xx', JSONRPC_PARSE_ERROR, '');
    CheckError(server, '', JSONRPC_PARSE_ERROR, '');
    // not strict JSON: trailing text, extended syntax, comments
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"ping"} garbage',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"ping"}{"x":1}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{jsonrpc:"2.0",id:1,method:"ping"}', JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{''jsonrpc'':''2.0'',''id'':1,''method'':''ping''}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0",/*c*/"id":1,"method":"ping"}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"ping",}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0","id":01,"method":"ping"}',
      JSONRPC_PARSE_ERROR, '');
    // surrounding whitespace is fine
    CheckEqual(server.ExecuteRequest(' {"jsonrpc":"2.0","id":1,"method":"ping"}'#13#10),
      '{"jsonrpc":"2.0","id":1,"result":{}}');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.InvalidRequests;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    // not an object (batches are not supported)
    CheckError(server, '[]', JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '[{"jsonrpc":"2.0","id":1,"method":"ping"}]',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '"ping"', JSONRPC_INVALID_REQUEST, '');
    CheckError(server, ' 1 ', JSONRPC_INVALID_REQUEST, '');
    // wrong or missing jsonrpc version: id is echoed when it is valid
    CheckError(server, '{"jsonrpc":"1.0","id":1,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '1');
    CheckError(server, '{"id":2,"method":"ping"}', JSONRPC_INVALID_REQUEST, '2');
    CheckError(server, '{"jsonrpc":2,"id":3,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '3');
    // invalid id: must be a string or an integer, never null
    CheckError(server, '{"jsonrpc":"2.0","id":null,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":2.5,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":1e5,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":true,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":{},"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":[1],"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    // method must be a string
    CheckError(server, '{"jsonrpc":"2.0","id":4,"method":5}',
      JSONRPC_INVALID_REQUEST, '4');
    CheckError(server, '{"jsonrpc":"2.0","id":5,"method":null}',
      JSONRPC_INVALID_REQUEST, '5');
    // params must be an object when present
    CheckError(server, '{"jsonrpc":"2.0","id":6,"method":"ping","params":[1]}',
      JSONRPC_INVALID_REQUEST, '6');
    CheckError(server, '{"jsonrpc":"2.0","id":7,"method":"ping","params":"x"}',
      JSONRPC_INVALID_REQUEST, '7');
    // neither a request nor a response
    CheckError(server, '{"jsonrpc":"2.0","id":8}', JSONRPC_INVALID_REQUEST, '8');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.RequestIdEchoed;
var
  server: TMcpServer;
  response: RawUtf8;
begin
  server := NewServer;
  try
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":"abc","method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":"abc","result":{}}');
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":"1","method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":"1","result":{}}');
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":-3,"method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":-3,"result":{}}');
    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":9007199254740993,"method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":9007199254740993,"result":{}}');
    // message is JSON-escaped (no string concatenation)
    CheckError(server, '{"jsonrpc":"2.0","id":"q\"","method":"a\"b"}',
      JSONRPC_METHOD_NOT_FOUND, '"q\""', 'a"b');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ClientResponsesIgnored;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","id":1,"result":{}}'), '');
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":"x","error":{"code":-32601,"message":"no"}}'), '');
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","error":{"code":-32700,"message":"parse"}}'), '');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.MissingParams;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    // regression: tools/call without params dereferenced a nil document
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"tools/call"}',
      JSONRPC_INVALID_PARAMS, '1', 'Missing tool name');
    CheckError(server, '{"jsonrpc":"2.0","id":2,"method":"resources/read"}',
      JSONRPC_INVALID_PARAMS, '2', 'Missing uri');
    CheckError(server, '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":5}}',
      JSONRPC_INVALID_PARAMS, '3');
    CheckError(server, '{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":[]}}',
      JSONRPC_INVALID_PARAMS, '4');
    // the server still works afterwards
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","id":5,"method":"ping"}'),
      '{"jsonrpc":"2.0","id":5,"result":{}}');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ResourceNotFoundData;
var
  server: TMcpServer;
  response, uri: RawUtf8;
  doc: TDocVariantData;
begin
  server := NewServer;
  try
    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"nope://x"}}');
    CheckErrorResponse(response, MCP_RESOURCE_NOT_FOUND, 'Resource not found');
    Check(doc.InitJson(response, JSON_FAST));
    Check(doc.O['error']^.O['data']^.GetAsRawUtf8('uri', uri), 'error.data.uri');
    CheckEqual(uri, 'nope://x');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ToolExceptions;
var
  server: TMcpServer;
  response: RawUtf8;
begin
  server := NewServer;
  try
    // not an ESynException: caught, generic message, no internal details
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":1,"method":"tools/call",' +
      '"params":{"name":"fail","arguments":{"name":"convert"}}}');
    CheckErrorResponse(response, JSONRPC_INTERNAL_ERROR, 'Internal error');
    Check(PosEx('secret', response) = 0, 'no exception message leaked');
    // EMcpException without a code: not meant for the client either
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":2,"method":"tools/call",' +
      '"params":{"name":"fail","arguments":{"name":"plain"}}}');
    CheckErrorResponse(response, JSONRPC_INTERNAL_ERROR, 'Internal error');
    Check(PosEx('secret', response) = 0, 'no exception message leaked');
    // EMcpException with a code: raised on purpose, message kept
    CheckError(server, '{"jsonrpc":"2.0","id":3,"method":"tools/call",' +
      '"params":{"name":"fail","arguments":{"name":"coded"}}}',
      JSONRPC_INVALID_PARAMS, '3', 'bad input');
    // a notification never gets an answer, even when it fails
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","method":"tools/call",' +
      '"params":{"name":"fail","arguments":{"name":"convert"}}}'), '');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.NotificationWhileStopped;
var
  server: TMcpServer;
begin
  server := TMcpServer.Create('TestServer', '1.0');
  try
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","method":"notifications/initialized"}'), '');
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","id":1,"result":{}}'), '');
    CheckError(server, '{"jsonrpc":"2.0","id":"s","method":"ping"}',
      JSONRPC_INTERNAL_ERROR, '"s"', 'Server not active');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.NotificationMethodAsRequest;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    // as a notification: no response
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","method":"notifications/initialized"}'), '');
    // as a request: not a known method (and never "result": null)
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"notifications/initialized"}',
      JSONRPC_METHOD_NOT_FOUND, '1');
  finally
    server.Free;
  end;
end;

end.
/// Model Context Protocol (MCP) Server Implementation for mORMot v2
// - this unit is part of the mormot-mcp-server project
// - licensed under MPL/GPL/LGPL three license
unit mormot.ext.mcp;

{
  *****************************************************************************

    - Core Types and Authentication Context
    - IInvokable Interfaces for Tools and Resources
    - RTTI-based Schema Generation
    - JSON-RPC 2.0 Protocol Processor
    - Generic Tool and Resource Base Classes
    - Main MCP Server with Tool/Resource Registry

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.rtti,
  mormot.core.buffers,
  mormot.core.data,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.collections,
  mormot.core.threads,
  mormot.core.interfaces,
  mormot.core.log;


{ ************ Core Types and Authentication Context }

const
  /// MCP Protocol Version
  MCP_PROTOCOL_VERSION = '2024-11-05';

  /// MCP Protocol Version (2025-03-26 - Streamable HTTP)
  MCP_PROTOCOL_VERSION_20250326 = '2025-03-26';

  /// JSON-RPC 2.0 Error Codes
  JSONRPC_PARSE_ERROR = -32700;
  JSONRPC_INVALID_REQUEST = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS = -32602;
  JSONRPC_INTERNAL_ERROR = -32603;

  /// MCP error code for an unknown resource in resources/read
  // - a SHOULD in the 2025-11-25 specification, which also expects
  // error.data.uri; the 2026-07-28 revision uses JSONRPC_INVALID_PARAMS instead
  MCP_RESOURCE_NOT_FOUND = -32002;

type
  /// Authentication context passed to tool/resource execution
  // - provides user identity and authorization information
  TMcpAuthContext = packed record
    /// whether the request has been authenticated
    IsAuthenticated: boolean;
    /// unique user identifier
    UserID: RawUtf8;
    /// user display name
    UserName: RawUtf8;
    /// assigned roles for authorization
    Roles: TRawUtf8DynArray;
  end;

  /// MCP-specific error information
  TMcpError = packed record
    /// JSON-RPC error code
    Code: integer;
    /// human-readable error message
    Message: RawUtf8;
    /// optional additional error data
    Data: variant;
  end;

  /// MCP-specific exception class
  // - raise it with CreateCode() for an error meant for the client: its code,
  // message and Data are sent back as the JSON-RPC error
  // - any other exception, including an EMcpException without a Code, is
  // answered with a generic JSONRPC_INTERNAL_ERROR and only logged
  EMcpException = class(ESynException)
  protected
    fCode: integer;
    fData: variant;
  public
    /// raise an error meant for the client, with its JSON-RPC error code
    constructor CreateCode(aCode: integer; const aFormat: RawUtf8;
      const aArgs: array of const);
    /// the JSON-RPC error code, or 0 if the error is not meant for the client
    property Code: integer
      read fCode;
    /// optional value sent as the "data" member of the JSON-RPC error
    property Data: variant
      read fData write fData;
  end;

  /// the kinds of incoming JSON-RPC message, as identified by
  // TMcpJsonRpcProcessor.ParseMessage
  // - mmkParseError: the input is not valid JSON
  // - mmkInvalid: valid JSON, but not a valid JSON-RPC 2.0 message
  // - mmkRequest: has a method and an id, and expects a response
  // - mmkNotification: has a method but no id, and expects no response
  // - mmkResponse: a response from the client (result or error, no method)
  TMcpMessageKind = (
    mmkParseError,
    mmkInvalid,
    mmkRequest,
    mmkNotification,
    mmkResponse);

  /// an incoming JSON-RPC message, as parsed by TMcpJsonRpcProcessor.ParseMessage
  TMcpJsonRpcMessage = record
    /// what kind of message this is
    Kind: TMcpMessageKind;
    /// the method name of a request or notification
    Method: RawUtf8;
    /// the params object, or Unassigned if absent
    Params: variant;
    /// the request id (an integer or a string), or Unassigned if absent
    // or invalid
    Id: variant;
    /// why the message is invalid, for mmkParseError and mmkInvalid
    Error: RawUtf8;
  end;


{ ************ IInvokable Interfaces for Tools and Resources }

type
  /// MCP Tool interface - represents an executable operation
  IMcpTool = interface(IInvokable)
    ['{8F3C5A1D-9E2B-4F7C-A6D8-3B9E4C5F6A7D}']
    /// return the unique tool name
    function GetName: RawUtf8;
    /// return the human-readable description
    function GetDescription: RawUtf8;
    /// return the JSON schema for input parameters as TDocVariant
    function GetInputSchema: variant;
    /// execute the tool with given arguments and auth context
    // - Args is a TDocVariantData containing the input parameters
    // - returns a TDocVariantData with 'content' array field
    function Execute(const Args: variant; const AuthCtx: TMcpAuthContext): variant;
  end;

  /// MCP Resource interface - represents readable data
  IMcpResource = interface(IInvokable)
    ['{7E4D3B2C-8A1F-4E9D-B5C6-2A8E3D4F5B6C}']
    /// return the unique resource URI
    function GetUri: RawUtf8;
    /// return the human-readable name
    function GetName: RawUtf8;
    /// return the resource description
    function GetDescription: RawUtf8;
    /// return the MIME type of the resource content
    function GetMimeType: RawUtf8;
    /// read and return the resource content
    function Read: RawUtf8;
  end;


{ ************ RTTI-based Schema Generation }

type
  /// Generate JSON schema from Object RTTI
  // - generates basic schema with type, properties, and required fields
  TMcpSchemaGenerator = class
  public
    /// Returns a TDocVariantData with schema structure
    class function GenerateSchema(aTypeInfo: PRttiInfo): variant;
  end;


{ ************ JSON-RPC 2.0 Protocol Processor }

type
  /// Stateless JSON-RPC 2.0 request/response processor for MCP
  // - handles all MCP protocol methods
  TMcpJsonRpcProcessor = class
  private
    fServerName: RawUtf8;
    fServerVersion: RawUtf8;
    fProtocolVersion: RawUtf8;
  public
    /// initialize with server information
    constructor Create(const aServerName, aServerVersion: RawUtf8);
    /// parse and validate one incoming JSON-RPC message
    // - never raises: returns mmkParseError or mmkInvalid (with aMessage.Error)
    // for input which is not a valid JSON-RPC 2.0 message
    class function ParseMessage(const aJson: RawUtf8;
      out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
    /// parse a JSON-RPC body, which may be a JSON object or a JSON array
    // - the input must be strict JSON: trailing text, comments or unquoted
    // names are a parse error
    // - returns false, with aMessage.Kind set to mmkParseError or mmkInvalid,
    // if aJson is not a JSON object or array
    class function ParseJson(const aJson: RawUtf8; var aDoc: TDocVariantData;
      out aMessage: TMcpJsonRpcMessage): boolean;
    /// validate one already parsed JSON-RPC message
    // - aDoc should have been parsed with JSON_FAST_FLOAT, so that a floating
    // point id is not mistaken for a string
    class function ParseMessageDoc(const aDoc: TDocVariantData;
      out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
    /// create a successful JSON-RPC response
    class function CreateSuccessResponse(const aRequestId, aResult: variant): RawUtf8;
    /// create an error JSON-RPC response
    // - the "id" member is omitted if aRequestId is Unassigned or Null
    // - the "data" member is omitted if aData is Unassigned or Null
    class function CreateError(const aRequestId: variant; aErrorCode: integer;
      const aErrorMsg: RawUtf8; const aData: variant): RawUtf8; overload;
    /// create an error JSON-RPC response, with no "data" member
    class function CreateError(const aRequestId: variant; aErrorCode: integer;
      const aErrorMsg: RawUtf8): RawUtf8; overload;
    /// create the error response for a mmkParseError or mmkInvalid message
    // - JSONRPC_PARSE_ERROR or JSONRPC_INVALID_REQUEST, with the id if readable
    class function CreateMessageError(const aMessage: TMcpJsonRpcMessage): RawUtf8;
    /// handle 'initialize' method
    function HandleInitialize(const aParams: variant): variant;
    /// handle 'ping' method
    function HandlePing: variant;
    /// the server name exposed in initialize response
    property ServerName: RawUtf8 read fServerName write fServerName;
    /// the server version exposed in initialize response
    property ServerVersion: RawUtf8 read fServerVersion write fServerVersion;
  end;


{ ************ Generic Tool Base Class }

type
  /// Generic base class for strongly-typed MCP tools
  // - T is the input parameters record type
  // - automatically generates JSON schema from T's RTTI
  TMcpToolBase<T: record> = class(TInterfacedObject, IMcpTool)
  protected
    fName: RawUtf8;
    fDescription: RawUtf8;
    /// override this to implement tool logic
    function ExecuteTyped(const aParams: T; const aAuthCtx: TMcpAuthContext): variant; virtual; abstract;
  public
    /// initialize with tool name and description
    constructor Create(const aName, aDescription: RawUtf8); virtual;
    /// IMcpTool implementation
    function GetName: RawUtf8;
    function GetDescription: RawUtf8;
    function GetInputSchema: variant;
    function Execute(const aArgs: variant; const aAuthCtx: TMcpAuthContext): variant;
  end;


{ ************ Resource Base Class }

type
  /// Abstract base class for MCP resources
  TMcpResourceBase = class(TInterfacedObject, IMcpResource)
  protected
    fUri: RawUtf8;
    fName: RawUtf8;
    fDescription: RawUtf8;
    fMimeType: RawUtf8;
    /// override this to provide resource content
    function GetContent: RawUtf8; virtual; abstract;
  public
    /// initialize with resource metadata
    constructor Create(const aUri, aName, aDescription, aMimeType: RawUtf8); virtual;
    /// IMcpResource implementation
    function GetUri: RawUtf8;
    function GetName: RawUtf8;
    function GetDescription: RawUtf8;
    function GetMimeType: RawUtf8;
    function Read: RawUtf8;
  end;


{ ************ Main MCP Server with Registry }

type
  /// Main MCP server with tool/resource registry
  // - thread-safe registration and execution
  // - processes JSON-RPC requests
  TMcpServer = class(TSynPersistent)
  private
    fTools: IKeyValue<RawUtf8, IMcpTool>; // name -> IMcpTool
    fResources: IKeyValue<RawUtf8, IMcpResource>; // uri -> IMcpResource
    fProcessor: TMcpJsonRpcProcessor;
    fActive: boolean;
    fSafe: TLightLock;
    function ExecuteToolCall(const aParams: variant; const aAuthCtx: TMcpAuthContext): variant;
    function ExecuteResourceRead(const aParams: variant): variant;
    function ListTools: variant;
    function ListResources: variant;
    function ExceptionToError(E: Exception;
      const aMessage: TMcpJsonRpcMessage): RawUtf8;
  public
    /// initialize the MCP server
    constructor Create(const aServerName: RawUtf8 = 'M-MCP-Server';
      const aServerVersion: RawUtf8 = '1.0.0'); reintroduce;
    /// finalize and release resources
    destructor Destroy; override;
    /// register a tool implementation
    // - thread-safe, can be called before or after Start
    procedure RegisterTool(const aTool: IMcpTool);
    /// register a resource implementation
    // - thread-safe
    procedure RegisterResource(const aResource: IMcpResource);
    /// unregister a tool by name
    function UnregisterTool(const aName: RawUtf8): boolean;
    /// unregister a resource by URI
    function UnregisterResource(const aUri: RawUtf8): boolean;
    /// start the server (activates tool/resource access)
    procedure Start;
    /// stop the server
    procedure Stop;
    /// process a JSON-RPC request and return JSON response
    // - aSessionId can be used for session-specific operations
    function ExecuteRequest(const aRequestJson: RawUtf8; 
      const aSessionId: RawUtf8 = ''): RawUtf8;
    /// check if server is active
    function IsActive: boolean;
  end;


{ ************ Response Builder Helper }

type
  /// Helper to build MCP tool responses with content array
  TMcpResponseBuilder = class
  private
    fContent: TDocVariantData;
  public
    /// initialize builder
    constructor Create;
    /// add text content block
    function AddText(const aText: RawUtf8): TMcpResponseBuilder;
    /// add base64-encoded file content
    function AddFile(const aFilePath: RawUtf8; const aFileName: RawUtf8 = ''): TMcpResponseBuilder;
    /// build final response as variant
    function Build: variant;
  end;


implementation


{ ************ EMcpException }

constructor EMcpException.CreateCode(aCode: integer; const aFormat: RawUtf8;
  const aArgs: array of const);
begin
  CreateUtf8(aFormat, aArgs);
  fCode := aCode;
end;


{ ************ TMcpSchemaGenerator Implementation }

class function TMcpSchemaGenerator.GenerateSchema(aTypeInfo: PRttiInfo): variant;
var
  rc: TRttiCustom;
  prop: PRttiCustomProp;
  props, schema: TDocVariantData;
  required: TDocVariantData;
  i: PtrInt;
  propSchema: TDocVariantData;
  jsonType: RawUtf8;

  function JsonTypeFromRtti(const aRtti: TRttiCustom): RawUtf8;
  begin
    if aRtti = nil then
    begin
      result := 'string';
      exit;
    end;
    case aRtti.Parser of
      ptBoolean:
        result := 'boolean';
      ptByte, ptCardinal, ptInt64, ptInteger, ptQWord, ptWord, ptOrm:
        result := 'integer';
      ptCurrency, ptDouble, ptExtended, ptSingle, ptDateTime, ptDateTimeMS,
      ptUnixTime, ptUnixMSTime:
        result := 'number';
      ptRawByteString, ptRawJson, ptRawUtf8, ptString, ptSynUnicode,
      ptUnicodeString, ptWideString, ptWinAnsi, ptGuid, ptHash128, ptHash256,
      ptHash512, ptTimeLog, ptPUtf8Char, ptEnumeration:
        result := 'string';
      ptSet, ptArray, ptDynArray:
        result := 'array';
      ptRecord, ptClass, ptInterface:
        result := 'object';
      ptVariant, ptCustom:
        result := 'object';
    else
      result := 'string';
    end;
  end;
begin
  // Initialize schema structure
  schema.InitObject(['type', 'object'], JSON_FAST);
  props.InitObject([], JSON_FAST);
  required.InitArray([], JSON_FAST);

  // Get RTTI context for the supplied type
  if aTypeInfo = nil then
  begin
    result := variant(schema);
    exit;
  end;
  rc := Rtti.RegisterType(aTypeInfo);
  if rc = nil then
  begin
    result := variant(schema);
    exit;
  end;

  // Iterate through properties
  for i := 0 to rc.Props.Count - 1 do
  begin
    prop := @rc.Props.List[i];
    if prop.Name = '' then
      continue;

    // Initialize property schema
    propSchema.InitObject([], JSON_FAST);

    // Determine JSON type from RTTI
    jsonType := JsonTypeFromRtti(prop.Value);

    propSchema.AddValue('type', jsonType);

    // Add to properties
    props.AddValue(LowerCaseU(prop.Name), variant(propSchema));

    // All properties are required (no optional metadata available)
    required.AddItem(LowerCaseU(prop.Name));
  end;

  schema.AddValue('properties', variant(props));
  if required.Count > 0 then
    schema.AddValue('required', variant(required));

  result := variant(schema);
end;


{ ************ TMcpJsonRpcProcessor Implementation }

constructor TMcpJsonRpcProcessor.Create(const aServerName, aServerVersion: RawUtf8);
begin
  inherited Create;
  fServerName := aServerName;
  fServerVersion := aServerVersion;
  fProtocolVersion := MCP_PROTOCOL_VERSION;
end;

// true if aName is a JSON string member of aDoc (numbers are not converted)
function GetStringValue(const aDoc: TDocVariantData; const aName: RawUtf8;
  out aValue: RawUtf8): boolean;
var
  v: PVariant;
begin
  result := aDoc.GetAsPVariant(aName, v) and VarIsString(v^);
  if result then
    aValue := VariantToUtf8(v^);
end;

// write '{"jsonrpc":"2.0"' and the "id" member, if any
procedure AddMessageStart(W: TJsonWriter; const aRequestId: variant);
begin
  W.AddShort('{"jsonrpc":"2.0"');
  if VarIsEmptyOrNull(aRequestId) then
    exit;
  W.AddShort(',"id":');
  W.AddVariant(aRequestId);
end;

class function TMcpJsonRpcProcessor.ParseMessage(const aJson: RawUtf8;
  out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
var
  doc: TDocVariantData;
begin
  if ParseJson(aJson, doc, aMessage) then
    result := ParseMessageDoc(doc, aMessage)
  else
    result := aMessage.Kind;
end;

class function TMcpJsonRpcProcessor.ParseJson(const aJson: RawUtf8;
  var aDoc: TDocVariantData; out aMessage: TMcpJsonRpcMessage): boolean;
var
  valid: boolean;
begin
  // InitJson alone accepts trailing text, comments and unquoted names:
  // check the whole input as strict JSON first
  valid := IsValidJson(aJson, {strict=}true);
  // JSON_FAST_FLOAT: with JSON_FAST, 1e5 would be parsed as a string
  result := valid and
            aDoc.InitJson(aJson, JSON_FAST_FLOAT);
  if result then
    exit;
  if valid and
     not (GotoNextNotSpace(pointer(aJson))^ in ['{', '[']) then
  begin
    // valid JSON, but neither an object nor an array (e.g. "ping" or 1)
    aMessage.Kind := mmkInvalid;
    aMessage.Error := 'Invalid Request: not a JSON object';
  end
  else
  begin
    aMessage.Kind := mmkParseError;
    aMessage.Error := 'Parse error';
  end;
end;

class function TMcpJsonRpcProcessor.ParseMessageDoc(const aDoc: TDocVariantData;
  out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
var
  v: PVariant;
  hasId: boolean;
  version: RawUtf8;
begin
  result := mmkInvalid;
  aMessage.Kind := mmkInvalid;
  if not aDoc.IsObject then
  begin
    aMessage.Error := 'Invalid Request: not a JSON object';
    exit;
  end;
  // read the id first, so that it can be echoed in an error response
  hasId := aDoc.GetAsPVariant('id', v);
  if hasId then
    case TVarData(v^).VType of
      varInteger, varInt64, varString:
        aMessage.Id := v^;
    end;
  if not GetStringValue(aDoc, 'jsonrpc', version) or
     (version <> '2.0') then
    aMessage.Error := 'Invalid Request: jsonrpc must be "2.0"'
  else if not aDoc.GetAsPVariant('method', v) then
    if aDoc.Exists('result') or
       aDoc.Exists('error') then
      result := mmkResponse
    else
      aMessage.Error := 'Invalid Request: missing method'
  else if not VarIsString(v^) then
    aMessage.Error := 'Invalid Request: method must be a string'
  else if hasId and VarIsEmptyOrNull(aMessage.Id) then
    aMessage.Error := 'Invalid Request: id must be a string or an integer'
  else
  begin
    aMessage.Method := VariantToUtf8(v^);
    if aDoc.GetAsPVariant('params', v) then
      if _Safe(v^)^.IsObject then
        aMessage.Params := v^
      else
      begin
        aMessage.Error := 'Invalid Request: params must be an object';
        exit;
      end;
    if hasId then
      result := mmkRequest
    else
      result := mmkNotification;
  end;
  aMessage.Kind := result;
end;

class function TMcpJsonRpcProcessor.CreateSuccessResponse(
  const aRequestId, aResult: variant): RawUtf8;
var
  W: TJsonWriter;
  tmp: TTextWriterStackBuffer;
begin
  W := TJsonWriter.CreateOwnedStream(tmp);
  try
    AddMessageStart(W, aRequestId);
    W.AddShort(',"result":');
    W.AddVariant(aResult);
    W.AddDirect('}');
    W.SetText(result);
  finally
    W.Free;
  end;
end;

class function TMcpJsonRpcProcessor.CreateError(const aRequestId: variant;
  aErrorCode: integer; const aErrorMsg: RawUtf8; const aData: variant): RawUtf8;
var
  W: TJsonWriter;
  tmp: TTextWriterStackBuffer;
begin
  W := TJsonWriter.CreateOwnedStream(tmp);
  try
    AddMessageStart(W, aRequestId);
    W.AddShort(',"error":{"code":');
    W.Add(aErrorCode);
    W.AddShort(',"message":');
    W.AddJsonString(aErrorMsg);
    if not VarIsEmptyOrNull(aData) then
    begin
      W.AddShort(',"data":');
      W.AddVariant(aData);
    end;
    W.AddDirect('}', '}');
    W.SetText(result);
  finally
    W.Free;
  end;
end;

class function TMcpJsonRpcProcessor.CreateError(const aRequestId: variant;
  aErrorCode: integer; const aErrorMsg: RawUtf8): RawUtf8;
begin
  result := CreateError(aRequestId, aErrorCode, aErrorMsg, Null);
end;

class function TMcpJsonRpcProcessor.CreateMessageError(
  const aMessage: TMcpJsonRpcMessage): RawUtf8;
begin
  if aMessage.Kind = mmkParseError then
    result := CreateError(Unassigned, JSONRPC_PARSE_ERROR, aMessage.Error)
  else
    result := CreateError(aMessage.Id, JSONRPC_INVALID_REQUEST, aMessage.Error);
end;

function TMcpJsonRpcProcessor.HandleInitialize(const aParams: variant): variant;
var
  result_doc, capabilities, serverInfo: TDocVariantData;
begin
  result_doc.InitObject(['protocolVersion', fProtocolVersion], JSON_FAST);
  
  // Add capabilities
  capabilities.InitObject([], JSON_FAST);
  capabilities.AddValue('tools', _ObjFast([]));
  capabilities.AddValue('resources', _ObjFast([]));
  result_doc.AddValue('capabilities', variant(capabilities));
  
  // Add server info
  serverInfo.InitObject(['name', fServerName, 'version', fServerVersion], JSON_FAST);
  result_doc.AddValue('serverInfo', variant(serverInfo));
  
  result := variant(result_doc);
end;

function TMcpJsonRpcProcessor.HandlePing: variant;
begin
  result := _Obj([]);
end;


{ ************ TMcpToolBase<T> Implementation }

constructor TMcpToolBase<T>.Create(const aName, aDescription: RawUtf8);
begin
  inherited Create;
  fName := aName;
  fDescription := aDescription;
end;

function TMcpToolBase<T>.GetName: RawUtf8;
begin
  result := fName;
end;

function TMcpToolBase<T>.GetDescription: RawUtf8;
begin
  result := fDescription;
end;

function TMcpToolBase<T>.GetInputSchema: variant;
var
  typeInfo: PRttiInfo;
begin
  typeInfo := System.TypeInfo(T);
  result := TMcpSchemaGenerator.GenerateSchema(typeInfo);
end;

function TMcpToolBase<T>.Execute(const aArgs: variant; 
  const aAuthCtx: TMcpAuthContext): variant;
var
  params: T;
  doc: PDocVariantData;
  json: RawUtf8;
begin
  // Deserialize arguments into typed record
  if _Safe(aArgs, doc) then
    json := doc^.ToJson
  else
    json := '{}';
  RecordLoadJson(params, json, TypeInfo(T));
  
  // Execute typed implementation
  result := ExecuteTyped(params, aAuthCtx);
end;


{ ************ TMcpResourceBase Implementation }

constructor TMcpResourceBase.Create(const aUri, aName, aDescription, aMimeType: RawUtf8);
begin
  inherited Create;
  fUri := aUri;
  fName := aName;
  fDescription := aDescription;
  fMimeType := aMimeType;
end;

function TMcpResourceBase.GetUri: RawUtf8;
begin
  result := fUri;
end;

function TMcpResourceBase.GetName: RawUtf8;
begin
  result := fName;
end;

function TMcpResourceBase.GetDescription: RawUtf8;
begin
  result := fDescription;
end;

function TMcpResourceBase.GetMimeType: RawUtf8;
begin
  result := fMimeType;
end;

function TMcpResourceBase.Read: RawUtf8;
begin
  result := GetContent;
end;


{ ************ TMcpServer Implementation }

constructor TMcpServer.Create(const aServerName, aServerVersion: RawUtf8);
begin
  inherited Create;
  fSafe.Init;
  fProcessor := TMcpJsonRpcProcessor.Create(aServerName, aServerVersion);
  fTools := Collections.NewPlainKeyValue<RawUtf8, IMcpTool>;
  fResources := Collections.NewPlainKeyValue<RawUtf8, IMcpResource>;
  fActive := false;
end;

destructor TMcpServer.Destroy;
begin
  Stop;
  fTools := nil;
  fResources := nil;
  fProcessor.Free;
  fSafe.Done;
  inherited;
end;

procedure TMcpServer.RegisterTool(const aTool: IMcpTool);
var
  name: RawUtf8;
begin
  if aTool = nil then
    exit;
  name := aTool.GetName;
  fSafe.Lock;
  try
    fTools.Add(name, aTool);
  finally
    fSafe.UnLock;
  end;
end;

procedure TMcpServer.RegisterResource(const aResource: IMcpResource);
var
  uri: RawUtf8;
begin
  if aResource = nil then
    exit;
  uri := aResource.GetUri;
  fSafe.Lock;
  try
    fResources.Add(uri, aResource);
  finally
    fSafe.UnLock;
  end;
end;

function TMcpServer.UnregisterTool(const aName: RawUtf8): boolean;
begin
  fSafe.Lock;
  try
    result := fTools.Remove(aName);
  finally
    fSafe.UnLock;
  end;
end;

function TMcpServer.UnregisterResource(const aUri: RawUtf8): boolean;
begin
  fSafe.Lock;
  try
    result := fResources.Remove(aUri);
  finally
    fSafe.UnLock;
  end;
end;

procedure TMcpServer.Start;
begin
  fSafe.Lock;
  try
    fActive := true;
  finally
    fSafe.UnLock;
  end;
end;

procedure TMcpServer.Stop;
begin
  fSafe.Lock;
  try
    fActive := false;
  finally
    fSafe.UnLock;
  end;
end;

function TMcpServer.IsActive: boolean;
begin
  result := fActive;
end;

function TMcpServer.ListTools: variant;
var
  doc, toolsList: TDocVariantData;
  toolObj: TDocVariantData;
  pair: TPair<RawUtf8, IMcpTool>;
begin
  doc.InitObject([], JSON_FAST);
  toolsList.InitArray([], JSON_FAST);

  fSafe.Lock;
  try
    for pair in fTools do
    begin
      toolObj.InitObject([
        'name', pair.Key,
        'description', pair.Value.GetDescription,
        'inputSchema', pair.Value.GetInputSchema
      ], JSON_FAST);
      toolsList.AddItem(variant(toolObj));
    end;
  finally
    fSafe.UnLock;
  end;

  doc.AddValue('tools', variant(toolsList));
  result := variant(doc);
end;

function TMcpServer.ListResources: variant;
var
  doc, resourcesList: TDocVariantData;
  resourceObj: TDocVariantData;
  pair: TPair<RawUtf8, IMcpResource>;
begin
  doc.InitObject([], JSON_FAST);
  resourcesList.InitArray([], JSON_FAST);

  fSafe.Lock;
  try
    for pair in fResources do
    begin
      resourceObj.InitObject([
        'uri', pair.Value.GetUri,
        'name', pair.Value.GetName,
        'description', pair.Value.GetDescription,
        'mimeType', pair.Value.GetMimeType
      ], JSON_FAST);
      resourcesList.AddItem(variant(resourceObj));
    end;
  finally
    fSafe.UnLock;
  end;

  doc.AddValue('resources', variant(resourcesList));
  result := variant(doc);
end;

function TMcpServer.ExecuteToolCall(const aParams: variant;
  const aAuthCtx: TMcpAuthContext): variant;
var
  doc: PDocVariantData;
  toolName: RawUtf8;
  args: variant;
  tool: IMcpTool;
begin
  doc := _Safe(aParams);
  if not GetStringValue(doc^, 'name', toolName) then
    raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS,
      'Missing tool name in tools/call', []);

  args := doc^.GetValueOrDefault('arguments', Null);

  fSafe.Lock;
  try
    if not fTools.TryGetValue(toolName, tool) then
      raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS,
        'Tool not found: %', [toolName]);
  finally
    fSafe.UnLock;
  end;

  result := tool.Execute(args, aAuthCtx);
end;

function TMcpServer.ExecuteResourceRead(const aParams: variant): variant;
var
  doc: PDocVariantData;
  uri, content: RawUtf8;
  resource: IMcpResource;
  result_doc, contentsList, contentItem: TDocVariantData;
  notFound: EMcpException;
begin
  doc := _Safe(aParams);
  if not GetStringValue(doc^, 'uri', uri) then
    raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS,
      'Missing uri in resources/read', []);

  fSafe.Lock;
  try
    if not fResources.TryGetValue(uri, resource) then
    begin
      notFound := EMcpException.CreateCode(MCP_RESOURCE_NOT_FOUND,
        'Resource not found: %', [uri]);
      notFound.Data := _ObjFast(['uri', uri]);
      raise notFound;
    end;
  finally
    fSafe.UnLock;
  end;

  content := resource.Read;

  // Build response
  result_doc.InitObject([], JSON_FAST);
  contentsList.InitArray([], JSON_FAST);
  
  contentItem.InitObject([
    'uri', uri,
    'mimeType', resource.GetMimeType,
    'text', content
  ], JSON_FAST);
  
  contentsList.AddItem(variant(contentItem));
  result_doc.AddValue('contents', variant(contentsList));
  
  result := variant(result_doc);
end;

function TMcpServer.ExecuteRequest(const aRequestJson, aSessionId: RawUtf8): RawUtf8;
var
  msg: TMcpJsonRpcMessage;
  resultData: variant;
  authCtx: TMcpAuthContext;
begin
  result := '';
  case fProcessor.ParseMessage(aRequestJson, msg) of
    mmkParseError, mmkInvalid:
      result := fProcessor.CreateMessageError(msg);
    mmkResponse:
      ; // this server sends no requests yet, so there is nothing to match
    mmkRequest, mmkNotification:
      if not fActive then
      begin
        // notifications MUST NOT receive a response
        if msg.Kind = mmkRequest then
          result := fProcessor.CreateError(msg.Id, JSONRPC_INTERNAL_ERROR,
            'Server not active');
      end
      else
        try
          // Setup auth context (stub for now)
          FillCharFast(authCtx, SizeOf(authCtx), 0);
          authCtx.IsAuthenticated := (aSessionId <> '');
          authCtx.UserID := aSessionId;

          // Dispatch to handler
          if msg.Method = 'initialize' then
            resultData := fProcessor.HandleInitialize(msg.Params)
          else if msg.Method = 'ping' then
            resultData := fProcessor.HandlePing
          else if msg.Method = 'tools/list' then
            resultData := ListTools
          else if msg.Method = 'tools/call' then
            resultData := ExecuteToolCall(msg.Params, authCtx)
          else if msg.Method = 'resources/list' then
            resultData := ListResources
          else if msg.Method = 'resources/read' then
            resultData := ExecuteResourceRead(msg.Params)
          else if msg.Kind = mmkNotification then
            // e.g. notifications/initialized: nothing to do yet
            resultData := Null
          else
            raise EMcpException.CreateCode(JSONRPC_METHOD_NOT_FOUND,
              'Method not found: %', [msg.Method]);

          if msg.Kind = mmkRequest then
            result := fProcessor.CreateSuccessResponse(msg.Id, resultData);
        except
          on E: Exception do
            result := ExceptionToError(E, msg);
        end;
  end;
end;

function TMcpServer.ExceptionToError(E: Exception;
  const aMessage: TMcpJsonRpcMessage): RawUtf8;
begin
  result := '';
  if (E is EMcpException) and
     (EMcpException(E).Code <> 0) then
  begin
    // raised on purpose for the client: send its code, message and data
    if aMessage.Kind = mmkRequest then
      result := fProcessor.CreateError(aMessage.Id, EMcpException(E).Code,
        StringToUtf8(E.Message), EMcpException(E).Data);
  end
  else
  begin
    // unexpected: the details may be internal, so they only go to the log
    TSynLog.Add.Log(sllError, '% %: % raised %',
      [aMessage.Method, aMessage.Id, ClassNameShort(E)^, E.Message], self);
    if aMessage.Kind = mmkRequest then
      result := fProcessor.CreateError(aMessage.Id, JSONRPC_INTERNAL_ERROR,
        'Internal error');
  end;
end;


{ ************ TMcpResponseBuilder Implementation }

constructor TMcpResponseBuilder.Create;
begin
  inherited Create;
  fContent.InitArray([], JSON_FAST);
end;

function TMcpResponseBuilder.AddText(const aText: RawUtf8): TMcpResponseBuilder;
var
  textItem: TDocVariantData;
begin
  textItem.InitObject(['type', 'text', 'text', aText], JSON_FAST);
  fContent.AddItem(variant(textItem));
  result := self;
end;

function TMcpResponseBuilder.AddFile(const aFilePath, aFileName: RawUtf8): TMcpResponseBuilder;
var
  fileItem: variant;
  content: RawByteString;
  base64: RawUtf8;
  mimeType, fileName: RawUtf8;
begin
  if not FileExists(Utf8ToString(aFilePath)) then
    raise EMcpException.CreateUtf8('File not found: %', [aFilePath]);

  content := StringFromFile(Utf8ToString(aFilePath));
  base64 := BinToBase64(content);
  
  if aFileName = '' then
    fileName := ExtractNameU(aFilePath)
  else
    fileName := aFileName;
    
  mimeType := GetMimeContentType(content, Utf8ToString(aFilePath));

  fileItem := _ObjFast([
    'type', 'resource',
    'mimeType', mimeType,
    'data', base64,
    'fileName', fileName
  ]);
  
  fContent.AddItem(fileItem);
  result := self;
end;

function TMcpResponseBuilder.Build: variant;
var
  contentCopy: TDocVariantData;
  i: integer;
begin
  SetVariantNull(result);

  contentCopy.InitArray([], JSON_FAST);
  for i := 0 to fContent.Count - 1 do
    contentCopy.AddItem(fContent.Values[i]);

  _ObjAddProp('content', contentCopy, result);
end;


end.

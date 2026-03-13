/// Markdown to HTML processor using mORMot v2 primitives
unit mormot.ext.markdown;

{$I mormot.defines.inc}

interface

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers;

type
  TMarkdownDialect = (
    mdDaringFireball,
    mdTxtMark,
    mdCommonMark,
    mdGitHub);

  TMarkdownLineType = (
    mltEmpty,
    mltOther,
    mltHeadline,
    mltHeadline1,
    mltHeadline2,
    mltCode,
    mltUnorderedList,
    mltOrderedList,
    mltBlockQuote,
    mltHorizontalRule,
    mltXml,
    mltFencedCode,
    mltTable);

  TMarkdownBlockType = (
    mbtNone,
    mbtBlockQuote,
    mbtCode,
    mbtFencedCode,
    mbtHeadline,
    mbtListItem,
    mbtOrderedList,
    mbtParagraph,
    mbtRuler,
    mbtUnorderedList,
    mbtXml,
    mbtTable);

  TMarkdownToken = (
    mtNone,
    mtEmStar,
    mtEmUnderscore,
    mtSubTilde,
    mtStrongStar,
    mtStrongUnderscore,
    mtStrikeTilde,
    mtInsPlus,
    mtMarkEqual,
    mtMathDollar,
    mtCodeSingle,
    mtCodeDouble,
    mtLink,
    mtHtml,
    mtImage,
    mtEntity,
    mtEscape,
    mtSuper,
    mtXCopy,
    mtXReg,
    mtXTrade,
    mtXLaquo,
    mtXRaquo,
    mtXNdash,
    mtXMdash,
    mtXHellip,
    mtXRdquo,
    mtXLdquo,
    mtXLinkOpen,
    mtXLinkClose,
    mtAutoLink);

  TMarkdownTableAlign = (
    mtaDefault,
    mtaLeft,
    mtaCenter,
    mtaRight);
  TMarkdownTableAlignDynArray = array of TMarkdownTableAlign;

  /// a single line in the markdown source
  TMarkdownLine = record
    Value: RawUtf8;
    Leading: integer;
    Trailing: integer;
    IsEmpty: boolean;
    PrevEmpty: boolean;
    NextEmpty: boolean;
    XmlEndLineIndex: integer;  // index of the line ending an XML block (-1 = none)
  end;
  PMarkdownLine = ^TMarkdownLine;
  TMarkdownLineDynArray = array of TMarkdownLine;

  /// a link reference definition [id]: url "title"
  TMarkdownLinkRef = record
    Link: RawUtf8;
    Title: RawUtf8;
    IsAbbrev: boolean;
  end;
  PMarkdownLinkRef = ^TMarkdownLinkRef;
  TMarkdownLinkRefDynArray = array of TMarkdownLinkRef;

  TMarkdownBlock = class;
  TMarkdownProcessor = class;

  /// block in the markdown AST (tree structure)
  TMarkdownBlock = class
  private
    fType: TMarkdownBlockType;
    fLines: TMarkdownLineDynArray;
    fLineCount: integer;
    fBlocks: array of TMarkdownBlock;
    fBlockCount: integer;
    fHlDepth: integer;
    fId: RawUtf8;
    fMeta: RawUtf8;
  public
    destructor Destroy; override;
    procedure AppendLine(const aLine: TMarkdownLine);
    function Split(aLineIndex: integer): TMarkdownBlock;
    procedure RemoveLine(aIndex: integer);
    procedure RemoveLeadingEmptyLines;
    procedure RemoveTrailingEmptyLines;
    procedure RemoveSurroundingEmptyLines;
    procedure RemoveBlockQuotePrefix;
    procedure RemoveListIndent(aDialect: TMarkdownDialect);
    procedure TransformHeadline;
    procedure ExpandListParagraphs;
    function HasLines: boolean;
    procedure SetLineEmpty(aIndex: integer);
    function StripId(aLineIndex: integer): RawUtf8;
    function CheckHtml(aLineIndex: integer): boolean;
    function ReadXmlComment(aFirstLineIndex, aStart: integer): integer;
    function GetLineType(aIndex: integer; aDialect: TMarkdownDialect;
      aAllowSpacesInFenced: boolean): TMarkdownLineType;
    // table helpers
    function TableHasFormatChars(aIndex: integer; out aCols: integer): integer;
    function TableColCount(aIndex: integer): integer;
    function TableIsRow(aIndex: integer; aCols: integer): boolean;
    property BlockType: TMarkdownBlockType read fType write fType;
    property Lines: TMarkdownLineDynArray read fLines;
    property LineCount: integer read fLineCount;
    property BlockCount: integer read fBlockCount;
    property HlDepth: integer read fHlDepth write fHlDepth;
    property Id: RawUtf8 read fId write fId;
    property Meta: RawUtf8 read fMeta write fMeta;
  end;

  /// customizable HTML decorator - override virtual methods to change output
  TMarkdownDecorator = class
  public
    procedure OpenParagraph(W: TTextWriter); virtual;
    procedure CloseParagraph(W: TTextWriter); virtual;
    procedure OpenBlockQuote(W: TTextWriter); virtual;
    procedure CloseBlockQuote(W: TTextWriter); virtual;
    procedure OpenCodeBlock(W: TTextWriter); virtual;
    procedure OpenFencedCodeBlock(W: TTextWriter; const aClass: RawUtf8); virtual;
    procedure CloseCodeBlock(W: TTextWriter); virtual;
    procedure OpenCodeSpan(W: TTextWriter); virtual;
    procedure CloseCodeSpan(W: TTextWriter); virtual;
    procedure OpenHeadline(W: TTextWriter; aLevel: integer); virtual;
    procedure CloseHeadline(W: TTextWriter; aLevel: integer); virtual;
    procedure OpenStrong(W: TTextWriter); virtual;
    procedure CloseStrong(W: TTextWriter); virtual;
    procedure OpenEmphasis(W: TTextWriter); virtual;
    procedure CloseEmphasis(W: TTextWriter); virtual;
    procedure OpenStrike(W: TTextWriter); virtual;
    procedure CloseStrike(W: TTextWriter); virtual;
    procedure OpenIns(W: TTextWriter); virtual;
    procedure CloseIns(W: TTextWriter); virtual;
    procedure OpenMark(W: TTextWriter); virtual;
    procedure CloseMark(W: TTextWriter); virtual;
    procedure OpenSuper(W: TTextWriter); virtual;
    procedure CloseSuper(W: TTextWriter); virtual;
    procedure OpenSub(W: TTextWriter); virtual;
    procedure CloseSub(W: TTextWriter); virtual;
    procedure OpenOrderedList(W: TTextWriter); virtual;
    procedure CloseOrderedList(W: TTextWriter); virtual;
    procedure OpenUnorderedList(W: TTextWriter); virtual;
    procedure CloseUnorderedList(W: TTextWriter); virtual;
    procedure OpenListItem(W: TTextWriter); virtual;
    procedure CloseListItem(W: TTextWriter); virtual;
    procedure CheckedItem(W: TTextWriter); virtual;
    procedure UncheckedItem(W: TTextWriter); virtual;
    procedure HorizontalRuler(W: TTextWriter); virtual;
    procedure OpenLink(W: TTextWriter); virtual;
    procedure CloseLink(W: TTextWriter); virtual;
    procedure OpenImage(W: TTextWriter); virtual;
    procedure CloseImage(W: TTextWriter); virtual;
  end;

  /// main markdown-to-HTML processor
  TMarkdownProcessor = class
  private
    fDialect: TMarkdownDialect;
    fDecorator: TMarkdownDecorator;
    fOwnDecorator: boolean;
    fSafeMode: boolean;
    fAllowSpacesInFencedDelimiters: boolean;
    fUseExtensions: boolean;
    // link references: sorted keys + parallel values
    fLinkRefKeys: TRawUtf8DynArray;
    fLinkRefValues: TMarkdownLinkRefDynArray;
    fLinkRefCount: integer;
    // internal methods
    function ReadLines(const aSource: RawUtf8): TMarkdownBlock;
    procedure Recurse(aRoot: TMarkdownBlock; aListMode: boolean);
    procedure InitListBlock(aRoot: TMarkdownBlock);
    procedure AddLinkRef(const aKey: RawUtf8; const aRef: TMarkdownLinkRef);
    function FindLinkRef(const aKey: RawUtf8; out aRef: TMarkdownLinkRef): boolean;
    // emission
    procedure EmitBlock(W: TTextWriter; aBlock: TMarkdownBlock);
    procedure EmitLines(W: TTextWriter; aBlock: TMarkdownBlock);
    procedure EmitCodeLines(W: TTextWriter; aBlock: TMarkdownBlock; aRemoveIndent: boolean);
    procedure EmitRawLines(W: TTextWriter; aBlock: TMarkdownBlock);
    procedure EmitMarkedLines(W: TTextWriter; aBlock: TMarkdownBlock);
    procedure EmitTableLines(W: TTextWriter; aBlock: TMarkdownBlock);
    function RecursiveEmitLine(W: TTextWriter; const s: RawUtf8;
      aStart: integer; aToken: TMarkdownToken): integer;
    function GetToken(const s: RawUtf8; aPos: integer): TMarkdownToken;
    function FindToken(const s: RawUtf8; aStart: integer;
      aToken: TMarkdownToken): integer;
    function CheckLink(W: TTextWriter; const s: RawUtf8;
      aStart: integer; aToken: TMarkdownToken): integer;
    function CheckHtml(W: TTextWriter; const s: RawUtf8;
      aStart: integer): integer;
    function CheckEntity(W: TTextWriter; const s: RawUtf8;
      aStart: integer): integer;
    function CheckMathCode(W: TTextWriter; const s: RawUtf8;
      aStart: integer): integer;
  public
    constructor Create(aDialect: TMarkdownDialect = mdCommonMark;
      aDecorator: TMarkdownDecorator = nil);
    destructor Destroy; override;
    /// process markdown source and return HTML
    function Process(const aSource: RawUtf8): RawUtf8;
    property Dialect: TMarkdownDialect read fDialect write fDialect;
    property SafeMode: boolean read fSafeMode write fSafeMode;
    property AllowSpacesInFencedDelimiters: boolean
      read fAllowSpacesInFencedDelimiters write fAllowSpacesInFencedDelimiters;
  end;

/// one-call convenience function
function MarkdownToHtml(const aSource: RawUtf8;
  aDialect: TMarkdownDialect = mdCommonMark): RawUtf8;


implementation

const
  ENTITY_NAMES: array[0..249] of RawUtf8 = (
    '&Acirc;', '&acirc;', '&acute;', '&AElig;', '&aelig;', '&Agrave;',
    '&agrave;', '&alefsym;', '&Alpha;', '&alpha;', '&amp;', '&and;', '&ang;',
    '&apos;', '&Aring;', '&aring;', '&asymp;', '&Atilde;', '&atilde;',
    '&Auml;', '&auml;', '&bdquo;', '&Beta;', '&beta;', '&brvbar;', '&bull;',
    '&cap;', '&Ccedil;', '&ccedil;', '&cedil;', '&cent;', '&Chi;', '&chi;',
    '&circ;', '&clubs;', '&cong;', '&copy;', '&crarr;', '&cup;', '&curren;',
    '&Dagger;', '&dagger;', '&dArr;', '&darr;', '&deg;', '&Delta;', '&delta;',
    '&diams;', '&divide;', '&Eacute;', '&eacute;', '&Ecirc;', '&ecirc;',
    '&Egrave;', '&egrave;', '&empty;', '&emsp;', '&ensp;', '&Epsilon;',
    '&epsilon;', '&equiv;', '&Eta;', '&eta;', '&ETH;', '&eth;', '&Euml;',
    '&euml;', '&euro;', '&exist;', '&fnof;', '&forall;', '&frac12;',
    '&frac14;', '&frac34;', '&frasl;', '&Gamma;', '&gamma;', '&ge;', '&gt;',
    '&hArr;', '&harr;', '&hearts;', '&hellip;', '&Iacute;', '&iacute;',
    '&Icirc;', '&icirc;', '&iexcl;', '&Igrave;', '&igrave;', '&image;',
    '&infin;', '&int;', '&Iota;', '&iota;', '&iquest;', '&isin;', '&Iuml;',
    '&iuml;', '&Kappa;', '&kappa;', '&Lambda;', '&lambda;', '&lang;',
    '&laquo;', '&lArr;', '&larr;', '&lceil;', '&ldquo;', '&le;', '&lfloor;',
    '&lowast;', '&loz;', '&lrm;', '&lsaquo;', '&lsquo;', '&lt;', '&macr;',
    '&mdash;', '&micro;', '&middot;', '&minus;', '&Mu;', '&mu;', '&nabla;',
    '&nbsp;', '&ndash;', '&ne;', '&ni;', '&not;', '&notin;', '&nsub;',
    '&Ntilde;', '&ntilde;', '&Nu;', '&nu;', '&Oacute;', '&oacute;', '&Ocirc;',
    '&ocirc;', '&OElig;', '&oelig;', '&Ograve;', '&ograve;', '&oline;',
    '&Omega;', '&omega;', '&Omicron;', '&omicron;', '&oplus;', '&or;',
    '&ordf;', '&ordm;', '&Oslash;', '&oslash;', '&Otilde;', '&otilde;',
    '&otimes;', '&Ouml;', '&ouml;', '&para;', '&part;', '&permil;', '&perp;',
    '&Phi;', '&phi;', '&Pi;', '&pi;', '&piv;', '&plusmn;', '&pound;',
    '&Prime;', '&prime;', '&prod;', '&prop;', '&Psi;', '&psi;', '&quot;',
    '&radic;', '&rang;', '&raquo;', '&rArr;', '&rarr;', '&rceil;', '&rdquo;',
    '&real;', '&reg;', '&rfloor;', '&Rho;', '&rho;', '&rlm;', '&rsaquo;',
    '&rsquo;', '&sbquo;', '&Scaron;', '&scaron;', '&sdot;', '&sect;', '&shy;',
    '&Sigma;', '&sigma;', '&sigmaf;', '&sim;', '&spades;', '&sub;', '&sube;',
    '&sum;', '&sup;', '&sup1;', '&sup2;', '&sup3;', '&supe;', '&szlig;',
    '&Tau;', '&tau;', '&there4;', '&Theta;', '&theta;', '&thetasym;',
    '&thinsp;', '&thorn;', '&tilde;', '&times;', '&trade;', '&Uacute;',
    '&uacute;', '&uArr;', '&uarr;', '&Ucirc;', '&ucirc;', '&Ugrave;',
    '&ugrave;', '&uml;', '&upsih;', '&Upsilon;', '&upsilon;', '&Uuml;',
    '&uuml;', '&weierp;', '&Xi;', '&xi;', '&Yacute;', '&yacute;', '&yen;',
    '&Yuml;', '&yuml;', '&Zeta;', '&zeta;', '&zwj;', '&zwnj;');

  LINK_PREFIXES: array[0..3] of RawUtf8 = ('http', 'https', 'ftp', 'ftps');

  BLOCK_ELEMENT_NAMES: array[0..20] of RawUtf8 = (
    'address', 'blockquote', 'del', 'div', 'dl', 'fieldset', 'form',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'ins', 'noscript',
    'ol', 'p', 'pre', 'table', 'ul');

  UNSAFE_ELEMENT_NAMES: array[0..8] of RawUtf8 = (
    'applet', 'body', 'frame', 'frameset', 'head', 'html', 'iframe',
    'object', 'script');

function IsEntity(const s: RawUtf8): boolean;
begin
  result := FindPropName(ENTITY_NAMES, s) >= 0;
end;

function IsHtmlBlockElement(const aTag: RawUtf8): boolean;
var
  i: integer;
begin
  for i := 0 to High(BLOCK_ELEMENT_NAMES) do
    if IdemPropNameU(aTag, BLOCK_ELEMENT_NAMES[i]) then
      exit(true);
  result := false;
end;

function IsUnsafeHtmlElement(const aTag: RawUtf8): boolean;
var
  i: integer;
begin
  for i := 0 to High(UNSAFE_ELEMENT_NAMES) do
    if IdemPropNameU(aTag, UNSAFE_ELEMENT_NAMES[i]) then
      exit(true);
  result := false;
end;

function IsLinkPrefix(const s: RawUtf8): boolean;
var
  i: integer;
begin
  for i := 0 to High(LINK_PREFIXES) do
    if IdemPropNameU(s, LINK_PREFIXES[i]) then
      exit(true);
  result := false;
end;

function WhitespaceToSpace(c: AnsiChar): AnsiChar;
  {$ifdef HASINLINE} inline; {$endif}
begin
  if c in [' ', #9, #10, #13] then
    result := ' '
  else
    result := c;
end;

function SkipSpacesAt(const s: RawUtf8; start: integer): integer;
var
  L: integer;
begin
  L := length(s);
  result := start;
  while (result <= L) and (s[result] in [' ', #10]) do
    inc(result);
  if result > L then
    result := -1;
end;

function EscapeChar(W: TTextWriter; ch: AnsiChar; position: integer): integer;
begin
  if ch in ['\', '[', ']', '(', ')', '{', '}', '#', '"', '''', '.', '>', '<',
            '*', '+', '-', '_', '!', '`', '^'] then
  begin
    W.Add(ch);
    result := position + 1;
  end
  else
  begin
    W.Add('\');
    result := position;
  end;
end;

function ReadUntilSet(W: TTextWriter; const s: RawUtf8; start: integer;
  const cend: TSysCharSet): integer;
var
  p, L: integer;
  ch: AnsiChar;
begin
  p := start;
  L := length(s);
  while p <= L do
  begin
    ch := s[p];
    if (ch = '\') and (p + 1 <= L) then
    begin
      p := EscapeChar(W, s[p + 1], p);
      inc(p);
      continue;
    end;
    if ch in cend then
      break;
    W.Add(ch);
    inc(p);
  end;
  if p > L then
    result := -1
  else
    result := p;
end;

function ReadUntilChar(W: TTextWriter; const s: RawUtf8; start: integer;
  cend: AnsiChar): integer;
var
  p, L: integer;
  ch: AnsiChar;
begin
  p := start;
  L := length(s);
  while p <= L do
  begin
    ch := s[p];
    if (ch = '\') and (p + 1 <= L) then
    begin
      p := EscapeChar(W, s[p + 1], p);
      inc(p);
      continue;
    end;
    if ch = cend then
      break;
    W.Add(ch);
    inc(p);
  end;
  if p > L then
    result := -1
  else
    result := p;
end;

function ReadMdLink(W: TTextWriter; const s: RawUtf8; start: integer): integer;
var
  p, L, counter: integer;
  ch: AnsiChar;
begin
  p := start;
  L := length(s);
  counter := 1;
  while p <= L do
  begin
    ch := s[p];
    if (ch = '\') and (p + 1 <= L) then
    begin
      p := EscapeChar(W, s[p + 1], p);
      inc(p);
      continue;
    end;
    case ch of
      '(':
        inc(counter);
      ' ':
        if counter = 1 then
          break;
      ')':
        begin
          dec(counter);
          if counter = 0 then
            break;
        end;
    end;
    W.Add(ch);
    inc(p);
  end;
  if p > L then
    result := -1
  else
    result := p;
end;

function ReadMdLinkId(W: TTextWriter; const s: RawUtf8; start: integer): integer;
var
  p, L, counter: integer;
  ch: AnsiChar;
begin
  p := start;
  L := length(s);
  counter := 1;
  while p <= L do
  begin
    ch := s[p];
    case ch of
      #10:
        W.Add(' ');
      '[':
        begin
          inc(counter);
          W.Add(ch);
        end;
      ']':
        begin
          dec(counter);
          if counter = 0 then
            break;
          W.Add(ch);
        end;
    else
      W.Add(ch);
    end;
    inc(p);
  end;
  if p > L then
    result := -1
  else
    result := p;
end;

function ReadRawUntilSet(W: TTextWriter; const s: RawUtf8; start: integer;
  const cend: TSysCharSet): integer;
var
  p, L: integer;
begin
  p := start;
  L := length(s);
  while p <= L do
  begin
    if s[p] in cend then
      break;
    W.Add(s[p]);
    inc(p);
  end;
  if p > L then
    result := -1
  else
    result := p;
end;

function ReadRawUntilChar(W: TTextWriter; const s: RawUtf8; start: integer;
  cend: AnsiChar): integer;
var
  p, L: integer;
begin
  p := start;
  L := length(s);
  while p <= L do
  begin
    if s[p] = cend then
      break;
    W.Add(s[p]);
    inc(p);
  end;
  if p > L then
    result := -1
  else
    result := p;
end;

function ReadXmlUntil(W: TTextWriter; const s: RawUtf8; start: integer;
  const cend: TSysCharSet): integer;
var
  p, L: integer;
  ch, stringChar: AnsiChar;
  inString: boolean;
begin
  p := start;
  L := length(s);
  inString := false;
  stringChar := #0;
  while p <= L do
  begin
    ch := s[p];
    if inString then
    begin
      if ch = '\' then
      begin
        W.Add(ch);
        inc(p);
        if p <= L then
        begin
          W.Add(s[p]);
          inc(p);
        end;
        continue;
      end;
      if ch = stringChar then
      begin
        inString := false;
        W.Add(ch);
        inc(p);
        continue;
      end;
    end;
    if ch in ['"', ''''] then
    begin
      inString := true;
      stringChar := ch;
    end;
    if (not inString) and (ch in cend) then
      break;
    W.Add(ch);
    inc(p);
  end;
  if p > L then
    result := -1
  else
    result := p;
end;

procedure AppendCode(W: TTextWriter; const s: RawUtf8; aFrom, aTo: integer);
var
  i: integer;
begin
  for i := aFrom to aTo do
    case s[i] of
      '&': W.AddShorter('&amp;');
      '<': W.AddShorter('&lt;');
      '>': W.AddShorter('&gt;');
    else
      W.Add(s[i]);
    end;
end;

procedure AppendValue(W: TTextWriter; const s: RawUtf8; aFrom, aTo: integer);
var
  i: integer;
begin
  for i := aFrom to aTo do
    case s[i] of
      '&': W.AddShorter('&amp;');
      '<': W.AddShorter('&lt;');
      '>': W.AddShorter('&gt;');
      '"': W.AddShorter('&quot;');
      '''': W.AddShorter('&apos;');
    else
      W.Add(s[i]);
    end;
end;

procedure AppendDecEntity(W: TTextWriter; c: AnsiChar);
begin
  W.AddShorter('&#');
  W.AddU(ord(c));
  W.Add(';');
end;

procedure AppendHexEntity(W: TTextWriter; c: AnsiChar);
var
  hex: string[4];
begin
  W.AddShorter('&#x');
  hex := ShortString(IntToHex(ord(c), 2));
  W.AddShort(hex);
  W.Add(';');
end;

procedure AppendMailto(W: TTextWriter; const s: RawUtf8; aFrom, aTo: integer);
var
  i: integer;
  c: AnsiChar;
begin
  for i := aFrom to aTo do
  begin
    c := s[i];
    if c in ['a'..'z', 'A'..'Z', '0'..'9', '&', '<', '>', '"', '''', '@'] then
    begin
      if Random32 and 1 = 0 then
        AppendHexEntity(W, c)
      else
        AppendDecEntity(W, c);
    end
    else
      W.Add(c);
  end;
end;

procedure GetXmlTag(W: TTextWriter; const s: RawUtf8);
var
  p, L: integer;
begin
  L := length(s);
  if L < 2 then
    exit;
  p := 2; // skip '<'
  if s[p] = '/' then
    inc(p);
  while (p <= L) and (s[p] in ['a'..'z', 'A'..'Z', '0'..'9']) do
  begin
    W.Add(s[p]);
    inc(p);
  end;
end;

function ReadXml(W: TTextWriter; const s: RawUtf8; start: integer;
  aSafeMode: boolean): integer;
var
  p: integer;
  isCloseTag: boolean;
  tmp: TTextWriterStackBuffer;
  tag: TTextWriter;
  tagStr: RawUtf8;
begin
  if start + 1 > length(s) then
    exit(-1);
  if s[start + 1] = '/' then
  begin
    isCloseTag := true;
    p := start + 2;
  end
  else if s[start + 1] = '!' then
  begin
    W.AddShorter('<!');
    exit(start + 1);
  end
  else
  begin
    isCloseTag := false;
    p := start + 1;
  end;
  if aSafeMode then
  begin
    tag := TTextWriter.CreateOwnedStream(tmp);
    try
      p := ReadXmlUntil(tag, s, p, [' ', '/', '>']);
      if p = -1 then
        exit(-1);
      tag.SetText(tagStr);
      tagStr := LowerCaseU(TrimU(tagStr));
      if IsUnsafeHtmlElement(tagStr) then
        W.AddShorter('&lt;')
      else
        W.Add('<');
      if isCloseTag then
        W.Add('/');
      W.AddString(tagStr);
    finally
      tag.Free;
    end;
  end
  else
  begin
    W.Add('<');
    if isCloseTag then
      W.Add('/');
    p := ReadXmlUntil(W, s, p, [' ', '/', '>']);
  end;
  if p = -1 then
    exit(-1);
  p := ReadXmlUntil(W, s, p, ['/', '>']);
  if p = -1 then
    exit(-1);
  if s[p] = '/' then
  begin
    W.AddShorter(' /');
    p := ReadXmlUntil(W, s, p + 1, ['>']);
    if p = -1 then
      exit(-1);
  end;
  if s[p] = '>' then
  begin
    W.Add('>');
    exit(p);
  end;
  result := -1;
end;

procedure CodeEncode(W: TTextWriter; const s: RawUtf8; aFrom: integer);
var
  i: integer;
begin
  for i := aFrom to length(s) do
    case s[i] of
      '&': W.AddShorter('&amp;');
      '<': W.AddShorter('&lt;');
      '>': W.AddShorter('&gt;');
      '+': W.AddShorter('%2b');
    else
      W.Add(s[i]);
    end;
end;

function GetMetaFromFence(const aFenceLine: RawUtf8): RawUtf8;
var
  i, L: integer;
begin
  L := length(aFenceLine);
  for i := 1 to L do
    if not (aFenceLine[i] in [' ', #9, #10, #13, '`', '~']) then
      exit(TrimU(copy(aFenceLine, i, maxInt)));
  result := '';
end;

{ Line init helpers }

procedure LineInit(var L: TMarkdownLine);
var
  len: integer;
begin
  len := length(L.Value);
  L.Leading := 0;
  while (L.Leading < len) and (L.Value[L.Leading + 1] = ' ') do
    inc(L.Leading);
  if L.Leading = len then
  begin
    L.Value := '';
    L.Leading := 0;
    L.Trailing := 0;
    L.IsEmpty := true;
  end
  else
  begin
    L.IsEmpty := false;
    L.Trailing := 0;
    while L.Value[len - L.Trailing] = ' ' do
      inc(L.Trailing);
  end;
end;

procedure LineInitLeading(var L: TMarkdownLine);
var
  len: integer;
begin
  len := length(L.Value);
  L.Leading := 0;
  while (L.Leading < len) and (L.Value[L.Leading + 1] = ' ') do
    inc(L.Leading);
  if L.Leading = len then
  begin
    L.Value := '';
    L.Leading := 0;
    L.Trailing := 0;
    L.IsEmpty := true;
  end;
end;

function LineCountChars(const L: TMarkdownLine; ch: AnsiChar): integer;
var
  i, len: integer;
  c: AnsiChar;
begin
  result := 0;
  len := length(L.Value);
  for i := 1 to len do
  begin
    c := L.Value[i];
    if c = ' ' then
      continue;
    if c = ch then
    begin
      inc(result);
      continue;
    end;
    result := 0;
    break;
  end;
end;

function LineCountCharsStart(const L: TMarkdownLine; ch: AnsiChar;
  aAllowSpaces: boolean): integer;
var
  i, len: integer;
  c: AnsiChar;
begin
  result := 0;
  len := length(L.Value);
  for i := 1 to len do
  begin
    c := L.Value[i];
    if (c = ' ') and aAllowSpaces then
      continue;
    if c = ch then
      inc(result)
    else
      break;
  end;
end;

function LineReadUntil(var L: TMarkdownLine; const chend: TSysCharSet): RawUtf8;
var
  tmp: TTextWriterStackBuffer;
  W: TTextWriter;
  p, len: integer;
  ch, c: AnsiChar;
begin
  W := TTextWriter.CreateOwnedStream(tmp);
  try
    p := L.Leading + 1; // 1-based position
    len := length(L.Value);
    while p <= len do
    begin
      ch := L.Value[p];
      if (ch = '\') and (p + 1 <= len) then
      begin
        c := L.Value[p + 1];
        if c in ['\', '[', ']', '(', ')', '{', '}', '#', '"', '''', '.', '>',
                 '*', '+', '-', '_', '!', '`', '~'] then
        begin
          W.Add(c);
          inc(p);
        end
        else
        begin
          W.Add(ch);
          break;
        end;
      end
      else if ch in chend then
        break
      else
        W.Add(ch);
      inc(p);
    end;
    if p <= len then
      ch := L.Value[p]
    else
      ch := #10;
    if ch in chend then
    begin
      L.Leading := p - 1; // update position (0-based leading)
      W.SetText(result);
    end
    else
      result := '';
  finally
    W.Free;
  end;
end;

{ TMarkdownDecorator }

procedure TMarkdownDecorator.OpenParagraph(W: TTextWriter);
begin
  W.AddShorter('<p>');
end;

procedure TMarkdownDecorator.CloseParagraph(W: TTextWriter);
begin
  W.AddShort('</p>'#10);
end;

procedure TMarkdownDecorator.OpenBlockQuote(W: TTextWriter);
begin
  W.AddShort('<blockquote>');
end;

procedure TMarkdownDecorator.CloseBlockQuote(W: TTextWriter);
begin
  W.AddShort('</blockquote>'#10);
end;

procedure TMarkdownDecorator.OpenCodeBlock(W: TTextWriter);
begin
  W.AddShort('<pre><code>');
end;

procedure TMarkdownDecorator.OpenFencedCodeBlock(W: TTextWriter; const aClass: RawUtf8);
begin
  W.AddShort('<pre><code class="');
  W.AddString(aClass);
  W.AddShorter('">');
end;

procedure TMarkdownDecorator.CloseCodeBlock(W: TTextWriter);
begin
  W.AddShort('</code></pre>'#10);
end;

procedure TMarkdownDecorator.OpenCodeSpan(W: TTextWriter);
begin
  W.AddShorter('<code>');
end;

procedure TMarkdownDecorator.CloseCodeSpan(W: TTextWriter);
begin
  W.AddShort('</code>');
end;

procedure TMarkdownDecorator.OpenHeadline(W: TTextWriter; aLevel: integer);
begin
  W.AddShorter('<h');
  W.AddU(aLevel);
end;

procedure TMarkdownDecorator.CloseHeadline(W: TTextWriter; aLevel: integer);
begin
  W.AddShorter('</h');
  W.AddU(aLevel);
  W.AddShorter('>'#10);
end;

procedure TMarkdownDecorator.OpenStrong(W: TTextWriter);
begin
  W.AddShort('<strong>');
end;

procedure TMarkdownDecorator.CloseStrong(W: TTextWriter);
begin
  W.AddShort('</strong>');
end;

procedure TMarkdownDecorator.OpenEmphasis(W: TTextWriter);
begin
  W.AddShorter('<em>');
end;

procedure TMarkdownDecorator.CloseEmphasis(W: TTextWriter);
begin
  W.AddShort('</em>');
end;

procedure TMarkdownDecorator.OpenStrike(W: TTextWriter);
begin
  W.AddShorter('<del>');
end;

procedure TMarkdownDecorator.CloseStrike(W: TTextWriter);
begin
  W.AddShorter('</del>');
end;

procedure TMarkdownDecorator.OpenIns(W: TTextWriter);
begin
  W.AddShorter('<ins>');
end;

procedure TMarkdownDecorator.CloseIns(W: TTextWriter);
begin
  W.AddShorter('</ins>');
end;

procedure TMarkdownDecorator.OpenMark(W: TTextWriter);
begin
  W.AddShorter('<mark>');
end;

procedure TMarkdownDecorator.CloseMark(W: TTextWriter);
begin
  W.AddShort('</mark>');
end;

procedure TMarkdownDecorator.OpenSuper(W: TTextWriter);
begin
  W.AddShorter('<sup>');
end;

procedure TMarkdownDecorator.CloseSuper(W: TTextWriter);
begin
  W.AddShorter('</sup>');
end;

procedure TMarkdownDecorator.OpenSub(W: TTextWriter);
begin
  W.AddShorter('<sub>');
end;

procedure TMarkdownDecorator.CloseSub(W: TTextWriter);
begin
  W.AddShorter('</sub>');
end;

procedure TMarkdownDecorator.OpenOrderedList(W: TTextWriter);
begin
  W.AddShort('<ol>'#10);
end;

procedure TMarkdownDecorator.CloseOrderedList(W: TTextWriter);
begin
  W.AddShort('</ol>'#10);
end;

procedure TMarkdownDecorator.OpenUnorderedList(W: TTextWriter);
begin
  W.AddShort('<ul>'#10);
end;

procedure TMarkdownDecorator.CloseUnorderedList(W: TTextWriter);
begin
  W.AddShort('</ul>'#10);
end;

procedure TMarkdownDecorator.OpenListItem(W: TTextWriter);
begin
  W.AddShorter('<li');
end;

procedure TMarkdownDecorator.CloseListItem(W: TTextWriter);
begin
  W.AddShort('</li>'#10);
end;

procedure TMarkdownDecorator.CheckedItem(W: TTextWriter);
begin
  W.AddShort('<input checked disabled type="checkbox"> ');
end;

procedure TMarkdownDecorator.UncheckedItem(W: TTextWriter);
begin
  W.AddShort('<input disabled type="checkbox"> ');
end;

procedure TMarkdownDecorator.HorizontalRuler(W: TTextWriter);
begin
  W.AddShort('<hr />'#10);
end;

procedure TMarkdownDecorator.OpenLink(W: TTextWriter);
begin
  W.AddShorter('<a');
end;

procedure TMarkdownDecorator.CloseLink(W: TTextWriter);
begin
  W.AddShorter('</a>');
end;

procedure TMarkdownDecorator.OpenImage(W: TTextWriter);
begin
  W.AddShorter('<img');
end;

procedure TMarkdownDecorator.CloseImage(W: TTextWriter);
begin
  W.AddShorter('/>');
end;

{ TMarkdownBlock }

destructor TMarkdownBlock.Destroy;
var
  i: integer;
begin
  for i := 0 to fBlockCount - 1 do
    fBlocks[i].Free;
  inherited;
end;

procedure TMarkdownBlock.AppendLine(const aLine: TMarkdownLine);
begin
  if fLineCount >= length(fLines) then
    SetLength(fLines, NextGrow(fLineCount));
  fLines[fLineCount] := aLine;
  if fLineCount > 0 then
  begin
    fLines[fLineCount - 1].NextEmpty := aLine.IsEmpty;
    fLines[fLineCount].PrevEmpty := fLines[fLineCount - 1].IsEmpty;
  end;
  inc(fLineCount);
end;

function TMarkdownBlock.Split(aLineIndex: integer): TMarkdownBlock;
var
  newBlock: TMarkdownBlock;
  remaining, i: integer;
begin
  newBlock := TMarkdownBlock.Create;
  // copy lines 0..aLineIndex to new block (proper copy for managed types)
  newBlock.fLineCount := aLineIndex + 1;
  SetLength(newBlock.fLines, newBlock.fLineCount);
  for i := 0 to aLineIndex do
    newBlock.fLines[i] := fLines[i];
  // shift remaining lines down
  remaining := fLineCount - aLineIndex - 1;
  if remaining > 0 then
  begin
    for i := 0 to remaining - 1 do
      fLines[i] := fLines[aLineIndex + 1 + i];
    fLineCount := remaining;
    SetLength(fLines, fLineCount);
    fLines[0].PrevEmpty := false;
  end
  else
  begin
    fLineCount := 0;
    fLines := nil;
  end;
  // add as child block
  if fBlockCount >= length(fBlocks) then
    SetLength(fBlocks, NextGrow(fBlockCount));
  fBlocks[fBlockCount] := newBlock;
  inc(fBlockCount);
  result := newBlock;
end;

procedure TMarkdownBlock.RemoveLine(aIndex: integer);
var
  i: integer;
begin
  if (aIndex < 0) or (aIndex >= fLineCount) then
    exit;
  for i := aIndex to fLineCount - 2 do
    fLines[i] := fLines[i + 1];
  dec(fLineCount);
  SetLength(fLines, fLineCount);
  // fix adjacency
  if (aIndex > 0) and (aIndex < fLineCount) then
  begin
    fLines[aIndex - 1].NextEmpty := fLines[aIndex].IsEmpty;
    fLines[aIndex].PrevEmpty := fLines[aIndex - 1].IsEmpty;
  end;
end;

procedure TMarkdownBlock.RemoveLeadingEmptyLines;
begin
  while (fLineCount > 0) and fLines[0].IsEmpty do
    RemoveLine(0);
end;

procedure TMarkdownBlock.RemoveTrailingEmptyLines;
begin
  while (fLineCount > 0) and fLines[fLineCount - 1].IsEmpty do
  begin
    dec(fLineCount);
    SetLength(fLines, fLineCount);
  end;
end;

procedure TMarkdownBlock.RemoveSurroundingEmptyLines;
begin
  if fLineCount > 0 then
  begin
    RemoveTrailingEmptyLines;
    RemoveLeadingEmptyLines;
  end;
end;

procedure TMarkdownBlock.RemoveBlockQuotePrefix;
var
  i, rem: integer;
begin
  for i := 0 to fLineCount - 1 do
    if not fLines[i].IsEmpty then
      if (fLines[i].Leading < length(fLines[i].Value)) and
         (fLines[i].Value[fLines[i].Leading + 1] = '>') then
      begin
        rem := fLines[i].Leading + 1;
        if (rem + 1 <= length(fLines[i].Value)) and
           (fLines[i].Value[rem + 1] = ' ') then
          inc(rem);
        fLines[i].Value := copy(fLines[i].Value, rem + 1, maxInt);
        LineInitLeading(fLines[i]);
      end;
end;

procedure TMarkdownBlock.RemoveListIndent(aDialect: TMarkdownDialect);
var
  i: integer;
  lt: TMarkdownLineType;
  dotPos, minLead: integer;
begin
  for i := 0 to fLineCount - 1 do
    if not fLines[i].IsEmpty then
    begin
      lt := GetLineType(i, aDialect, true);
      case lt of
        mltUnorderedList:
          fLines[i].Value := copy(fLines[i].Value, fLines[i].Leading + 3, maxInt);
        mltOrderedList:
          begin
            dotPos := PosExChar('.', fLines[i].Value);
            if dotPos > 0 then
              fLines[i].Value := copy(fLines[i].Value, dotPos + 2, maxInt);
          end;
      else
        begin
          minLead := fLines[i].Leading + 1;
          if minLead > 5 then
            minLead := 5;
          fLines[i].Value := copy(fLines[i].Value, minLead, maxInt);
        end;
      end;
      LineInitLeading(fLines[i]);
    end;
end;

procedure TMarkdownBlock.TransformHeadline;
var
  level, startPos, endPos, len: integer;
begin
  if fHlDepth > 0 then
    exit;
  if (fLineCount = 0) or fLines[0].IsEmpty then
    exit;
  level := 0;
  startPos := fLines[0].Leading + 1;
  len := length(fLines[0].Value);
  while (startPos <= len) and (fLines[0].Value[startPos] = '#') do
  begin
    inc(level);
    inc(startPos);
  end;
  while (startPos <= len) and (fLines[0].Value[startPos] = ' ') do
    inc(startPos);
  if startPos > len then
  begin
    SetLineEmpty(0);
  end
  else
  begin
    endPos := len - fLines[0].Trailing;
    while (endPos >= startPos) and (fLines[0].Value[endPos] = '#') do
      dec(endPos);
    while (endPos >= startPos) and (fLines[0].Value[endPos] = ' ') do
      dec(endPos);
    if (endPos < len) and (fLines[0].Value[endPos + 1] <> ' ') then
      endPos := len;
    fLines[0].Value := copy(fLines[0].Value, startPos, endPos - startPos + 1);
    fLines[0].Leading := 0;
    fLines[0].Trailing := 0;
  end;
  if level > 6 then
    level := 6;
  fHlDepth := level;
end;

procedure TMarkdownBlock.ExpandListParagraphs;
var
  i, j: integer;
  hasParagraph: boolean;
begin
  if not (fType in [mbtOrderedList, mbtUnorderedList]) then
    exit;
  hasParagraph := false;
  for i := 0 to fBlockCount - 1 do
    if fBlocks[i].fType = mbtListItem then
      for j := 0 to fBlocks[i].fBlockCount - 1 do
        if fBlocks[i].fBlocks[j].fType = mbtParagraph then
        begin
          hasParagraph := true;
          break;
        end;
  if hasParagraph then
    for i := 0 to fBlockCount - 1 do
      if fBlocks[i].fType = mbtListItem then
        for j := 0 to fBlocks[i].fBlockCount - 1 do
          if fBlocks[i].fBlocks[j].fType = mbtNone then
            fBlocks[i].fBlocks[j].fType := mbtParagraph;
end;

function TMarkdownBlock.HasLines: boolean;
begin
  result := fLineCount > 0;
end;

procedure TMarkdownBlock.SetLineEmpty(aIndex: integer);
begin
  if (aIndex < 0) or (aIndex >= fLineCount) then
    exit;
  fLines[aIndex].Value := '';
  fLines[aIndex].Leading := 0;
  fLines[aIndex].Trailing := 0;
  fLines[aIndex].IsEmpty := true;
  if aIndex > 0 then
    fLines[aIndex - 1].NextEmpty := true;
  if aIndex + 1 < fLineCount then
    fLines[aIndex + 1].PrevEmpty := true;
end;

function TMarkdownBlock.StripId(aLineIndex: integer): RawUtf8;
var
  p, startPos, len: integer;
  found: boolean;
  v: RawUtf8;
begin
  result := '';
  if (aLineIndex < 0) or (aLineIndex >= fLineCount) then
    exit;
  v := fLines[aLineIndex].Value;
  len := length(v);
  if fLines[aLineIndex].IsEmpty or (len = 0) then
    exit;
  if v[len - fLines[aLineIndex].Trailing] <> '}' then
    exit;
  p := fLines[aLineIndex].Leading + 1;
  found := false;
  while (p <= len) and not found do
    case v[p] of
      '\':
        begin
          if (p + 1 <= len) and (v[p + 1] = '{') then
            inc(p);
          inc(p);
          break;
        end;
      '{':
        begin
          found := true;
          break;
        end;
    else
      inc(p);
    end;
  if found then
  begin
    found := false;
    if (p + 1 <= len) and (v[p + 1] = '#') then
    begin
      startPos := p + 2;
      p := startPos;
      while (p <= len) and not found do
        case v[p] of
          '\':
            begin
              if (p + 1 <= len) and (v[p + 1] = '}') then
                inc(p);
              inc(p);
              break;
            end;
          '}':
            begin
              found := true;
              break;
            end;
        else
          inc(p);
        end;
    end;
  end;
  if found then
  begin
    result := TrimU(copy(v, startPos, p - startPos));
    if fLines[aLineIndex].Leading > 0 then
      fLines[aLineIndex].Value := copy(v, 1, fLines[aLineIndex].Leading) +
        TrimU(copy(v, fLines[aLineIndex].Leading + 1, startPos - fLines[aLineIndex].Leading - 2))
    else
      fLines[aLineIndex].Value := TrimU(copy(v, 1, startPos - 2));
    fLines[aLineIndex].Trailing := 0;
  end;
end;

function TMarkdownBlock.ReadXmlComment(aFirstLineIndex, aStart: integer): integer;
var
  lineIdx, p, len: integer;
begin
  result := -1;
  if aFirstLineIndex >= fLineCount then
    exit;
  len := length(fLines[aFirstLineIndex].Value);
  if aStart + 3 > len then
    exit;
  if (fLines[aFirstLineIndex].Value[aStart + 1] <> '-') or
     (fLines[aFirstLineIndex].Value[aStart + 2] <> '-') then
    exit;
  lineIdx := aFirstLineIndex;
  p := aStart + 3;
  while lineIdx < fLineCount do
  begin
    len := length(fLines[lineIdx].Value);
    while (p <= len) and (fLines[lineIdx].Value[p] <> '-') do
      inc(p);
    if p > len then
    begin
      inc(lineIdx);
      p := 1;
    end
    else
    begin
      if (p + 2 <= len) and (fLines[lineIdx].Value[p + 1] = '-') and
         (fLines[lineIdx].Value[p + 2] = '>') then
      begin
        fLines[aFirstLineIndex].XmlEndLineIndex := lineIdx;
        exit(p + 3);
      end;
      inc(p);
    end;
  end;
end;

function TMarkdownBlock.CheckHtml(aLineIndex: integer): boolean;
var
  tagStack: array of RawUtf8;
  tagCount: integer;
  tmp: TTextWriterStackBuffer;
  tempW, tagW: TTextWriter;
  element, tag: RawUtf8;
  lineIdx, pos_, newPos, len: integer;

  procedure PushTag(const t: RawUtf8);
  begin
    if tagCount >= length(tagStack) then
      SetLength(tagStack, NextGrow(tagCount));
    tagStack[tagCount] := t;
    inc(tagCount);
  end;

  procedure PopTag;
  begin
    if tagCount > 0 then
      dec(tagCount);
  end;

begin
  result := false;
  if (aLineIndex < 0) or (aLineIndex >= fLineCount) then
    exit;
  tagCount := 0;
  tempW := TTextWriter.CreateOwnedStream(tmp);
  try
    pos_ := fLines[aLineIndex].Leading + 1;
    len := length(fLines[aLineIndex].Value);
    // check for XML comment
    if (pos_ + 1 <= len) and (fLines[aLineIndex].Value[pos_ + 1] = '!') then
    begin
      if ReadXmlComment(aLineIndex, pos_ + 1) > 0 then
        exit(true);
    end;
    // read first XML element
    pos_ := ReadXml(tempW, fLines[aLineIndex].Value, fLines[aLineIndex].Leading + 1, false);
    if pos_ <= 0 then
      exit;
    tempW.SetText(element);
    tagW := TTextWriter.CreateOwnedStream(tmp);
    try
      GetXmlTag(tagW, element);
      tagW.SetText(tag);
    finally
      tagW.Free;
    end;
    tag := LowerCaseU(tag);
    if not IsHtmlBlockElement(tag) then
      exit(false);
    if (tag = 'hr') or ((length(element) >= 2) and
       (element[length(element) - 1] = '/') and (element[length(element)] = '>')) then
    begin
      fLines[aLineIndex].XmlEndLineIndex := aLineIndex;
      exit(true);
    end;
    PushTag(tag);
    lineIdx := aLineIndex;
    while lineIdx < fLineCount do
    begin
      len := length(fLines[lineIdx].Value);
      while (pos_ <= len) and (fLines[lineIdx].Value[pos_] <> '<') do
        inc(pos_);
      if pos_ > len then
      begin
        inc(lineIdx);
        pos_ := 1;
      end
      else
      begin
        tempW.CancelAll;
        newPos := ReadXml(tempW, fLines[lineIdx].Value, pos_, false);
        if newPos > 0 then
        begin
          tempW.SetText(element);
          tagW := TTextWriter.CreateOwnedStream(tmp);
          try
            GetXmlTag(tagW, element);
            tagW.SetText(tag);
          finally
            tagW.Free;
          end;
          tag := LowerCaseU(tag);
          if IsHtmlBlockElement(tag) and (tag <> 'hr') and
             not ((length(element) >= 2) and (element[length(element) - 1] = '/') and
                  (element[length(element)] = '>')) then
          begin
            if (length(element) >= 2) and (element[2] = '/') then
            begin
              if (tagCount > 0) and (tagStack[tagCount - 1] <> tag) then
                exit(false);
              PopTag;
            end
            else
              PushTag(tag);
          end;
          if tagCount = 0 then
          begin
            fLines[aLineIndex].XmlEndLineIndex := lineIdx;
            break;
          end;
          pos_ := newPos;
        end
        else
          inc(pos_);
      end;
    end;
    result := (tagCount = 0);
  finally
    tempW.Free;
  end;
end;

function TMarkdownBlock.TableHasFormatChars(aIndex: integer;
  out aCols: integer): integer;
var
  i, j, len: integer;
begin
  result := 0;
  aCols := 0;
  if (aIndex < 0) or (aIndex >= fLineCount) or fLines[aIndex].IsEmpty then
    exit;
  i := fLines[aIndex].Leading + 1;
  len := length(fLines[aIndex].Value) - fLines[aIndex].Trailing;
  if i > 4 then
    exit;
  if fLines[aIndex].Value[i] = '|' then
    inc(i);
  if fLines[aIndex].Value[len] = '|' then
    dec(len);
  j := i;
  while j <= len do
  begin
    if not (fLines[aIndex].Value[j] in [' ', '|', '-', ':']) then
      exit(0);
    if fLines[aIndex].Value[j] = '|' then
      inc(result);
    inc(j);
  end;
  aCols := result;
end;

function TMarkdownBlock.TableColCount(aIndex: integer): integer;
var
  i, j, len, r: integer;
begin
  result := 0;
  if (aIndex < 0) or (aIndex >= fLineCount) or fLines[aIndex].IsEmpty then
    exit;
  r := 0;
  i := fLines[aIndex].Leading + 1;
  len := length(fLines[aIndex].Value) - fLines[aIndex].Trailing;
  if i > 4 then
    exit;
  if fLines[aIndex].Value[i] = '|' then
    inc(i);
  if fLines[aIndex].Value[len] = '|' then
    dec(len);
  j := i;
  while j <= len do
  begin
    if (fLines[aIndex].Value[j] = '|') and
       ((j = 1) or (fLines[aIndex].Value[j - 1] <> '\')) then
      inc(r);
    inc(j);
  end;
  result := r;
end;

function TMarkdownBlock.TableIsRow(aIndex, aCols: integer): boolean;
var
  c: integer;
begin
  c := TableColCount(aIndex);
  result := (c > 0);
end;

function TMarkdownBlock.GetLineType(aIndex: integer; aDialect: TMarkdownDialect;
  aAllowSpacesInFenced: boolean): TMarkdownLineType;
var
  i, len, cols: integer;
  v: RawUtf8;
begin
  if (aIndex < 0) or (aIndex >= fLineCount) then
    exit(mltEmpty);
  if fLines[aIndex].IsEmpty then
    exit(mltEmpty);
  v := fLines[aIndex].Value;
  len := length(v);
  if fLines[aIndex].Leading > 3 then
    exit(mltCode);
  // ATX headline
  if v[fLines[aIndex].Leading + 1] = '#' then
  begin
    if aDialect in [mdCommonMark, mdGitHub] then
    begin
      i := fLines[aIndex].Leading + 2;
      while (i <= len) and (v[i] = '#') do
        inc(i);
      if (i <= len) and (v[i] = ' ') then
        exit(mltHeadline);
    end
    else
      exit(mltHeadline);
  end;
  // block quote
  if v[fLines[aIndex].Leading + 1] = '>' then
    exit(mltBlockQuote);
  // fenced code
  if aDialect in [mdTxtMark, mdCommonMark, mdGitHub] then
    if len - fLines[aIndex].Leading - fLines[aIndex].Trailing > 2 then
    begin
      if (v[fLines[aIndex].Leading + 1] = '`') and
         (LineCountCharsStart(fLines[aIndex], '`', aAllowSpacesInFenced) >= 3) then
        exit(mltFencedCode);
      if (v[fLines[aIndex].Leading + 1] = '~') and
         (LineCountCharsStart(fLines[aIndex], '~', aAllowSpacesInFenced) >= 3) then
        exit(mltFencedCode);
    end;
  // horizontal rule
  if (len - fLines[aIndex].Leading - fLines[aIndex].Trailing > 2) and
     (v[fLines[aIndex].Leading + 1] in ['*', '-', '_']) then
    if LineCountChars(fLines[aIndex], v[fLines[aIndex].Leading + 1]) >= 3 then
      exit(mltHorizontalRule);
  // unordered list
  if (len - fLines[aIndex].Leading >= 2) and
     (v[fLines[aIndex].Leading + 2] = ' ') and
     (v[fLines[aIndex].Leading + 1] in ['*', '-', '+']) then
    exit(mltUnorderedList);
  // ordered list
  if (len - fLines[aIndex].Leading >= 3) and
     (v[fLines[aIndex].Leading + 1] in ['0'..'9']) then
  begin
    i := fLines[aIndex].Leading + 2;
    while (i <= len) and (v[i] in ['0'..'9']) do
      inc(i);
    if (i + 1 <= len) and (v[i] = '.') and (v[i + 1] = ' ') then
      exit(mltOrderedList);
  end;
  // HTML block
  if v[fLines[aIndex].Leading + 1] = '<' then
    if CheckHtml(aIndex) then
      exit(mltXml);
  // setext headlines (check next line)
  if (aIndex + 1 < fLineCount) and not fLines[aIndex + 1].IsEmpty then
  begin
    i := 1;
    if aDialect in [mdCommonMark, mdGitHub] then
      while (i <= length(fLines[aIndex + 1].Value)) and
            not (fLines[aIndex + 1].Value[i] in ['-', '=']) do
        inc(i);
    if (i < 5) and (i <= length(fLines[aIndex + 1].Value)) then
    begin
      if (fLines[aIndex + 1].Value[i] = '-') and
         (LineCountChars(fLines[aIndex + 1], '-') > 0) then
        exit(mltHeadline2);
      if (fLines[aIndex + 1].Value[i] = '=') and
         (LineCountChars(fLines[aIndex + 1], '=') > 0) then
        exit(mltHeadline1);
    end;
  end;
  // table
  if (aDialect in [mdCommonMark, mdGitHub]) and (aIndex + 1 < fLineCount) and
     not fLines[aIndex + 1].IsEmpty then
  begin
    if (TableHasFormatChars(aIndex + 1, cols) > 0) and
       (TableColCount(aIndex) = cols) then
      exit(mltTable);
  end;
  result := mltOther;
end;


{ TMarkdownProcessor }

constructor TMarkdownProcessor.Create(aDialect: TMarkdownDialect;
  aDecorator: TMarkdownDecorator);
begin
  inherited Create;
  fDialect := aDialect;
  fAllowSpacesInFencedDelimiters := true;
  fSafeMode := true;
  if aDecorator <> nil then
  begin
    fDecorator := aDecorator;
    fOwnDecorator := false;
  end
  else
  begin
    fDecorator := TMarkdownDecorator.Create;
    fOwnDecorator := true;
  end;
end;

destructor TMarkdownProcessor.Destroy;
begin
  if fOwnDecorator then
    fDecorator.Free;
  inherited;
end;

procedure TMarkdownProcessor.AddLinkRef(const aKey: RawUtf8;
  const aRef: TMarkdownLinkRef);
var
  k: RawUtf8;
  i: PtrInt;
begin
  k := LowerCaseU(aKey);
  // try to find existing entry
  i := FastFindPUtf8CharSorted(
    pointer(fLinkRefKeys), fLinkRefCount - 1, pointer(k));
  if i >= 0 then
    // update existing
    fLinkRefValues[i] := aRef
  else
  begin
    // insert new: use AddSortedRawUtf8 to maintain sort order
    // first ensure fLinkRefValues has enough room
    if fLinkRefCount >= length(fLinkRefValues) then
      SetLength(fLinkRefValues, NextGrow(fLinkRefCount));
    i := AddSortedRawUtf8(fLinkRefKeys, fLinkRefCount, k);
    if i >= 0 then
    begin
      // shift values array to match
      if i < fLinkRefCount - 1 then
      begin
        MoveFast(fLinkRefValues[i], fLinkRefValues[i + 1],
          (fLinkRefCount - 1 - i) * SizeOf(TMarkdownLinkRef));
        FillCharFast(fLinkRefValues[i], SizeOf(TMarkdownLinkRef), 0);
      end;
      fLinkRefValues[i] := aRef;
    end;
  end;
end;

function TMarkdownProcessor.FindLinkRef(const aKey: RawUtf8;
  out aRef: TMarkdownLinkRef): boolean;
var
  i: PtrInt;
  k: RawUtf8;
begin
  k := LowerCaseU(aKey);
  i := FastFindPUtf8CharSorted(
    pointer(fLinkRefKeys), fLinkRefCount - 1, pointer(k));
  result := (i >= 0);
  if result then
    aRef := fLinkRefValues[i];
end;

function TMarkdownProcessor.Process(const aSource: RawUtf8): RawUtf8;
var
  tmp: TTextWriterStackBuffer;
  W: TTextWriter;
  root: TMarkdownBlock;
  i: integer;
begin
  fUseExtensions := fDialect in [mdTxtMark, mdCommonMark, mdGitHub];
  fLinkRefCount := 0;
  fLinkRefKeys := nil;
  fLinkRefValues := nil;
  root := ReadLines(aSource);
  try
    root.RemoveSurroundingEmptyLines;
    Recurse(root, false);
    W := TTextWriter.CreateOwnedStream(tmp);
    try
      for i := 0 to root.fBlockCount - 1 do
        EmitBlock(W, root.fBlocks[i]);
      W.SetText(result);
    finally
      W.Free;
    end;
  finally
    root.Free;
  end;
end;

function TMarkdownProcessor.ReadLines(const aSource: RawUtf8): TMarkdownBlock;
var
  block: TMarkdownBlock;
  p, L: integer;
  c: AnsiChar;
  lineBuf: RawUtf8;
  linePos: integer;
  line: TMarkdownLine;
  isLinkRef: boolean;
  id, link, comment: RawUtf8;
  ch: AnsiChar;
  lr: TMarkdownLinkRef;
  lastLinkRefIndex: integer;
  hasLastLinkRef: boolean;

  procedure BuildLine;
  var
    tmp: TTextWriterStackBuffer;
    W: TTextWriter;
    tabSpaces, curPos: integer;
  begin
    W := TTextWriter.CreateOwnedStream(tmp);
    try
      curPos := 0;
      while p <= L do
      begin
        c := aSource[p];
        case c of
          #0:
            break;
          #10:
            begin
              inc(p);
              if (p <= L) and (aSource[p] = #13) then
                inc(p);
              break;
            end;
          #13:
            begin
              inc(p);
              if (p <= L) and (aSource[p] = #10) then
                inc(p);
              break;
            end;
          #9:
            begin
              tabSpaces := 4 - (curPos and 3);
              while tabSpaces > 0 do
              begin
                W.Add(' ');
                inc(curPos);
                dec(tabSpaces);
              end;
              inc(p);
            end;
        else
          W.Add(c);
          inc(curPos);
          inc(p);
        end;
      end;
      W.SetText(lineBuf);
    finally
      W.Free;
    end;
  end;

  function LineSkipSpaces(var aLine: TMarkdownLine; var aPos: integer): boolean;
  var
    vlen: integer;
  begin
    vlen := length(aLine.Value);
    while (aPos <= vlen) and (aLine.Value[aPos] = ' ') do
      inc(aPos);
    result := aPos <= vlen;
  end;

  function LineReadUntilSet(var aLine: TMarkdownLine; var aPos: integer;
    const cend: TSysCharSet): RawUtf8;
  var
    vlen: integer;
    tmp2: TTextWriterStackBuffer;
    W2: TTextWriter;
    cc: AnsiChar;
  begin
    W2 := TTextWriter.CreateOwnedStream(tmp2);
    try
      vlen := length(aLine.Value);
      while aPos <= vlen do
      begin
        cc := aLine.Value[aPos];
        if (cc = '\') and (aPos + 1 <= vlen) then
        begin
          if aLine.Value[aPos + 1] in ['\', '[', ']', '(', ')', '{', '}', '#', '"',
               '''', '.', '>', '*', '+', '-', '_', '!', '`', '~'] then
          begin
            W2.Add(aLine.Value[aPos + 1]);
            inc(aPos, 2);
            continue;
          end
          else
          begin
            W2.Add(cc);
            break;
          end;
        end;
        if cc in cend then
          break;
        W2.Add(cc);
        inc(aPos);
      end;
      W2.SetText(result);
    finally
      W2.Free;
    end;
  end;

begin
  block := TMarkdownBlock.Create;
  lastLinkRefIndex := -1;
  hasLastLinkRef := false;
  p := 1;
  L := length(aSource);
  while p <= L do
  begin
    BuildLine;
    // init line
    FillCharFast(line, SizeOf(line), 0);
    line.Value := lineBuf;
    line.XmlEndLineIndex := -1;
    LineInit(line);
    // check for link reference definition
    isLinkRef := false;
    id := '';
    link := '';
    comment := '';
    if (not line.IsEmpty) and (line.Leading < 4) and
       (line.Leading + 1 <= length(line.Value)) and
       (line.Value[line.Leading + 1] = '[') then
    begin
      linePos := line.Leading + 2;
      id := LineReadUntilSet(line, linePos, [']']);
      if (id <> '') and (linePos + 2 <= length(line.Value)) then
      begin
        if line.Value[linePos + 1] = ':' then
        begin
          linePos := linePos + 2;
          if LineSkipSpaces(line, linePos) then
          begin
            if line.Value[linePos] = '<' then
            begin
              inc(linePos);
              link := LineReadUntilSet(line, linePos, ['>']);
              inc(linePos);
            end
            else
              link := LineReadUntilSet(line, linePos, [' ', #10]);
            if link <> '' then
            begin
              if LineSkipSpaces(line, linePos) then
              begin
                ch := line.Value[linePos];
                if ch in ['"', '''', '('] then
                begin
                  inc(linePos);
                  if ch = '(' then
                    comment := LineReadUntilSet(line, linePos, [')'])
                  else
                    comment := LineReadUntilSet(line, linePos, [ch]);
                  if comment <> '' then
                    isLinkRef := true;
                end;
              end
              else
                isLinkRef := true;
            end;
          end;
        end;
      end;
    end;
    if isLinkRef then
    begin
      if LowerCaseU(id) = '$profile$' then
      begin
        if LowerCaseU(link) = 'extended' then
        begin
          fUseExtensions := true;
          fDialect := mdTxtMark;
        end;
        hasLastLinkRef := false;
      end
      else
      begin
        lr.Link := link;
        lr.Title := comment;
        lr.IsAbbrev := (comment <> '') and (length(link) = 1) and (link[1] = '*');
        AddLinkRef(id, lr);
        if comment = '' then
        begin
          hasLastLinkRef := true;
          lastLinkRefIndex := fLinkRefCount - 1;
        end
        else
          hasLastLinkRef := false;
      end;
    end
    else
    begin
      comment := '';
      if (not line.IsEmpty) and hasLastLinkRef then
      begin
        linePos := line.Leading + 1;
        if (linePos <= length(line.Value)) and
           (line.Value[linePos] in ['"', '''', '(']) then
        begin
          ch := line.Value[linePos];
          inc(linePos);
          if ch = '(' then
            comment := LineReadUntilSet(line, linePos, [')'])
          else
            comment := LineReadUntilSet(line, linePos, [ch]);
        end;
        if (comment <> '') and (lastLinkRefIndex >= 0) and
           (lastLinkRefIndex < fLinkRefCount) then
          fLinkRefValues[lastLinkRefIndex].Title := comment;
        hasLastLinkRef := false;
      end;
      if comment = '' then
        block.AppendLine(line);
    end;
  end;
  result := block;
end;

procedure TMarkdownProcessor.InitListBlock(aRoot: TMarkdownBlock);
var
  i: integer;
  t: TMarkdownLineType;
begin
  i := 1;
  while i < aRoot.fLineCount do
  begin
    t := aRoot.GetLineType(i, fDialect, fAllowSpacesInFencedDelimiters);
    if (t in [mltOrderedList, mltUnorderedList]) or
       (not aRoot.fLines[i].IsEmpty and aRoot.fLines[i].PrevEmpty and
        (aRoot.fLines[i].Leading = 0) and
        not (t in [mltOrderedList, mltUnorderedList])) then
    begin
      aRoot.Split(i - 1).fType := mbtListItem;
      i := 1;
      continue;
    end;
    inc(i);
  end;
  if aRoot.fLineCount > 0 then
    aRoot.Split(aRoot.fLineCount - 1).fType := mbtListItem;
end;

procedure TMarkdownProcessor.Recurse(aRoot: TMarkdownBlock; aListMode: boolean);
var
  i: integer;
  lineType, t: TMarkdownLineType;
  block, list: TMarkdownBlock;
  wasEmpty: boolean;
  bt: TMarkdownBlockType;
  j, cols: integer;
  s: RawUtf8;
begin
  if aListMode then
  begin
    aRoot.RemoveListIndent(fDialect);
    if fUseExtensions and (aRoot.fLineCount > 0) and
       (aRoot.GetLineType(0, fDialect, fAllowSpacesInFencedDelimiters) <> mltCode) then
      aRoot.fId := aRoot.StripId(0);
    // task list detection (GFM / CommonMark)
    if (fDialect in [mdCommonMark, mdGitHub]) and (aRoot.fLineCount > 0) then
    begin
      s := TrimU(aRoot.fLines[0].Value);
      if (length(s) >= 4) and (s[1] = '[') and (s[3] = ']') and (s[4] = ' ') then
        if s[2] in ['x', 'X', ' '] then
        begin
          if s[2] in ['x', 'X'] then
            aRoot.fMeta := 'x'
          else
            aRoot.fMeta := ' ';
          aRoot.fLines[0].Value := copy(s, 5, maxInt);
          LineInitLeading(aRoot.fLines[0]);
        end;
    end;
  end;
  // skip leading empty lines
  i := 0;
  while (i < aRoot.fLineCount) and aRoot.fLines[i].IsEmpty do
    inc(i);
  if i >= aRoot.fLineCount then
    exit;
  while i < aRoot.fLineCount do
  begin
    lineType := aRoot.GetLineType(i, fDialect, fAllowSpacesInFencedDelimiters);
    case lineType of
      mltOther:
        begin
          wasEmpty := (i > 0) and aRoot.fLines[i].PrevEmpty;
          while (i < aRoot.fLineCount) and not aRoot.fLines[i].IsEmpty do
          begin
            t := aRoot.GetLineType(i, fDialect, fAllowSpacesInFencedDelimiters);
            if (aListMode or fUseExtensions) and (t in [mltOrderedList, mltUnorderedList]) then
              break;
            if fUseExtensions and (t in [mltCode, mltFencedCode]) then
              break;
            if t in [mltHeadline, mltHeadline1, mltHeadline2, mltHorizontalRule,
                     mltBlockQuote, mltXml, mltTable] then
              break;
            inc(i);
          end;
          if (i < aRoot.fLineCount) and not aRoot.fLines[i].IsEmpty then
          begin
            if aListMode and not wasEmpty then
              bt := mbtNone
            else
              bt := mbtParagraph;
            aRoot.Split(i - 1).fType := bt;
            aRoot.RemoveLeadingEmptyLines;
          end
          else
          begin
            if aListMode and ((i >= aRoot.fLineCount) or not aRoot.fLines[i].IsEmpty) and
               not wasEmpty then
              bt := mbtNone
            else
              bt := mbtParagraph;
            aRoot.RemoveLeadingEmptyLines;
            if aRoot.fLineCount > 0 then
            begin
              if i - 1 >= aRoot.fLineCount then
                aRoot.Split(aRoot.fLineCount - 1).fType := bt
              else if i > 0 then
                aRoot.Split(i - 1).fType := bt
              else
                aRoot.Split(aRoot.fLineCount - 1).fType := bt;
            end;
          end;
          i := 0;
        end;
      mltCode:
        begin
          while (i < aRoot.fLineCount) and
                (aRoot.fLines[i].IsEmpty or (aRoot.fLines[i].Leading > 3)) do
            inc(i);
          if i > 0 then
          begin
            if i >= aRoot.fLineCount then
              block := aRoot.Split(aRoot.fLineCount - 1)
            else
              block := aRoot.Split(i - 1);
            block.fType := mbtCode;
            block.RemoveSurroundingEmptyLines;
          end;
          i := 0;
        end;
      mltXml:
        begin
          if i > 0 then
            aRoot.Split(i - 1);
          // find xml end line index
          j := aRoot.fLines[0].XmlEndLineIndex;
          if (j < 0) then
            j := 0;
          // make it relative to current root
          aRoot.Split(j).fType := mbtXml;
          aRoot.RemoveLeadingEmptyLines;
          i := 0;
        end;
      mltBlockQuote:
        begin
          while i < aRoot.fLineCount do
          begin
            if not aRoot.fLines[i].IsEmpty and aRoot.fLines[i].PrevEmpty and
               (aRoot.fLines[i].Leading = 0) and
               (aRoot.GetLineType(i, fDialect, fAllowSpacesInFencedDelimiters) <> mltBlockQuote) then
              break;
            inc(i);
          end;
          if i > 0 then
          begin
            if i >= aRoot.fLineCount then
              block := aRoot.Split(aRoot.fLineCount - 1)
            else
              block := aRoot.Split(i - 1);
            block.fType := mbtBlockQuote;
            block.RemoveSurroundingEmptyLines;
            block.RemoveBlockQuotePrefix;
            Recurse(block, false);
          end;
          i := 0;
        end;
      mltHorizontalRule:
        begin
          if i > 0 then
            aRoot.Split(i - 1);
          aRoot.Split(0).fType := mbtRuler;
          aRoot.RemoveLeadingEmptyLines;
          i := 0;
        end;
      mltFencedCode:
        begin
          j := i + 1;
          while j < aRoot.fLineCount do
          begin
            if aRoot.GetLineType(j, fDialect, fAllowSpacesInFencedDelimiters) = mltFencedCode then
              break;
            inc(j);
          end;
          if j < aRoot.fLineCount then
            inc(j); // skip closing fence
          if j > 0 then
          begin
            if i > 0 then
              aRoot.Split(i - 1); // lines before fence
            if j - i >= aRoot.fLineCount then
              block := aRoot.Split(aRoot.fLineCount - 1)
            else
              block := aRoot.Split(j - i - 1);
            block.RemoveSurroundingEmptyLines;
            block.fType := mbtFencedCode;
            if block.fLineCount > 0 then
            begin
              block.fMeta := GetMetaFromFence(block.fLines[0].Value);
              block.SetLineEmpty(0);
              if (block.fLineCount > 0) and
                 (block.GetLineType(block.fLineCount - 1, fDialect, fAllowSpacesInFencedDelimiters) = mltFencedCode) then
                block.SetLineEmpty(block.fLineCount - 1);
            end;
            block.RemoveSurroundingEmptyLines;
          end;
          i := 0;
        end;
      mltHeadline, mltHeadline1, mltHeadline2:
        begin
          if i > 0 then
            aRoot.Split(i - 1);
          if lineType <> mltHeadline then
            if (aRoot.fLineCount > 1) then
              aRoot.SetLineEmpty(1);
          block := aRoot.Split(0);
          block.fType := mbtHeadline;
          if lineType <> mltHeadline then
          begin
            if lineType = mltHeadline1 then
              block.fHlDepth := 1
            else
              block.fHlDepth := 2;
          end;
          if fUseExtensions then
            block.fId := block.StripId(0);
          block.TransformHeadline;
          aRoot.RemoveLeadingEmptyLines;
          i := 0;
        end;
      mltOrderedList, mltUnorderedList:
        begin
          while i < aRoot.fLineCount do
          begin
            t := aRoot.GetLineType(i, fDialect, fAllowSpacesInFencedDelimiters);
            if not aRoot.fLines[i].IsEmpty and aRoot.fLines[i].PrevEmpty and
               (aRoot.fLines[i].Leading = 0) and (t <> lineType) then
              break;
            inc(i);
          end;
          if i > 0 then
          begin
            if i >= aRoot.fLineCount then
              list := aRoot.Split(aRoot.fLineCount - 1)
            else
              list := aRoot.Split(i - 1);
            if lineType = mltOrderedList then
              list.fType := mbtOrderedList
            else
              list.fType := mbtUnorderedList;
            if list.fLineCount > 0 then
            begin
              list.fLines[0].PrevEmpty := false;
              list.fLines[list.fLineCount - 1].NextEmpty := false;
            end;
            list.RemoveSurroundingEmptyLines;
            if list.fLineCount > 0 then
            begin
              list.fLines[list.fLineCount - 1].NextEmpty := false;
              list.fLines[0].PrevEmpty := list.fLines[list.fLineCount - 1].NextEmpty;
            end;
            InitListBlock(list);
            for j := 0 to list.fBlockCount - 1 do
              Recurse(list.fBlocks[j], true);
            list.ExpandListParagraphs;
          end;
          i := 0;
        end;
      mltTable:
        begin
          cols := 0;
          aRoot.TableHasFormatChars(i + 1, cols);
          while i < aRoot.fLineCount do
          begin
            if not aRoot.TableIsRow(i, cols) then
              break;
            inc(i);
          end;
          if i > 0 then
          begin
            if i >= aRoot.fLineCount then
              block := aRoot.Split(aRoot.fLineCount - 1)
            else
              block := aRoot.Split(i - 1);
            block.RemoveSurroundingEmptyLines;
            block.fType := mbtTable;
          end;
          i := 0;
        end;
    else
      inc(i);
    end;
  end;
end;

procedure TMarkdownProcessor.EmitBlock(W: TTextWriter; aBlock: TMarkdownBlock);
var
  i: integer;
begin
  aBlock.RemoveSurroundingEmptyLines;
  case aBlock.fType of
    mbtRuler:
      begin
        fDecorator.HorizontalRuler(W);
        exit;
      end;
    mbtNone, mbtXml:
      ; // no open tag
    mbtHeadline:
      begin
        fDecorator.OpenHeadline(W, aBlock.fHlDepth);
        if fUseExtensions and (aBlock.fId <> '') then
        begin
          W.AddShorter(' id="');
          AppendCode(W, aBlock.fId, 1, length(aBlock.fId));
          W.Add('"');
        end;
        W.Add('>');
      end;
    mbtParagraph:
      fDecorator.OpenParagraph(W);
    mbtCode:
      fDecorator.OpenCodeBlock(W);
    mbtFencedCode:
      if aBlock.fMeta <> '' then
        fDecorator.OpenFencedCodeBlock(W, aBlock.fMeta)
      else
        fDecorator.OpenCodeBlock(W);
    mbtBlockQuote:
      fDecorator.OpenBlockQuote(W);
    mbtUnorderedList:
      fDecorator.OpenUnorderedList(W);
    mbtOrderedList:
      fDecorator.OpenOrderedList(W);
    mbtListItem:
      begin
        fDecorator.OpenListItem(W);
        if fUseExtensions and (aBlock.fId <> '') then
        begin
          W.AddShorter(' id="');
          AppendCode(W, aBlock.fId, 1, length(aBlock.fId));
          W.Add('"');
        end;
        W.Add('>');
        // task list checkbox (GFM / CommonMark) - fMeta set during Recurse
        if aBlock.fMeta = 'x' then
          fDecorator.CheckedItem(W)
        else if aBlock.fMeta = ' ' then
          fDecorator.UncheckedItem(W);
      end;
  end;
  if aBlock.HasLines then
    EmitLines(W, aBlock)
  else
    for i := 0 to aBlock.fBlockCount - 1 do
      EmitBlock(W, aBlock.fBlocks[i]);
  case aBlock.fType of
    mbtRuler, mbtNone, mbtXml:
      ; // no close tag
    mbtHeadline:
      fDecorator.CloseHeadline(W, aBlock.fHlDepth);
    mbtParagraph:
      fDecorator.CloseParagraph(W);
    mbtCode, mbtFencedCode:
      fDecorator.CloseCodeBlock(W);
    mbtBlockQuote:
      fDecorator.CloseBlockQuote(W);
    mbtUnorderedList:
      fDecorator.CloseUnorderedList(W);
    mbtOrderedList:
      fDecorator.CloseOrderedList(W);
    mbtListItem:
      fDecorator.CloseListItem(W);
  end;
end;

procedure TMarkdownProcessor.EmitLines(W: TTextWriter; aBlock: TMarkdownBlock);
begin
  case aBlock.fType of
    mbtCode:
      EmitCodeLines(W, aBlock, true);
    mbtFencedCode:
      EmitCodeLines(W, aBlock, false);
    mbtXml:
      EmitRawLines(W, aBlock);
    mbtTable:
      EmitTableLines(W, aBlock);
  else
    EmitMarkedLines(W, aBlock);
  end;
end;

procedure TMarkdownProcessor.EmitCodeLines(W: TTextWriter;
  aBlock: TMarkdownBlock; aRemoveIndent: boolean);
var
  i, j, sp, len: integer;
begin
  for i := 0 to aBlock.fLineCount - 1 do
  begin
    if not aBlock.fLines[i].IsEmpty then
    begin
      if aRemoveIndent then
        sp := 5  // skip 4 leading spaces (1-based = start at 5)
      else
        sp := 1;
      len := length(aBlock.fLines[i].Value);
      for j := sp to len do
        case aBlock.fLines[i].Value[j] of
          '&': W.AddShorter('&amp;');
          '<': W.AddShorter('&lt;');
          '>': W.AddShorter('&gt;');
        else
          W.Add(aBlock.fLines[i].Value[j]);
        end;
    end;
    W.Add(#10);
  end;
end;

procedure TMarkdownProcessor.EmitRawLines(W: TTextWriter;
  aBlock: TMarkdownBlock);
var
  i: integer;
  s, xmlFrag: RawUtf8;
  p, t, L: integer;
  tmp: TTextWriterStackBuffer;
  tempW: TTextWriter;
begin
  if fSafeMode then
  begin
    tempW := TTextWriter.CreateOwnedStream(tmp);
    try
      for i := 0 to aBlock.fLineCount - 1 do
      begin
        if not aBlock.fLines[i].IsEmpty then
          tempW.AddString(aBlock.fLines[i].Value);
        tempW.Add(#10);
      end;
      tempW.SetText(s);
    finally
      tempW.Free;
    end;
    L := length(s);
    p := 1;
    tempW := TTextWriter.CreateOwnedStream(tmp);
    try
      while p <= L do
      begin
        if s[p] = '<' then
        begin
          tempW.CancelAll;
          t := ReadXml(tempW, s, p, fSafeMode);
          if t > 0 then
          begin
            tempW.SetText(xmlFrag);
            W.AddString(xmlFrag);
            p := t;
          end
          else
            W.Add(s[p]);
        end
        else
          W.Add(s[p]);
        inc(p);
      end;
    finally
      tempW.Free;
    end;
  end
  else
  begin
    for i := 0 to aBlock.fLineCount - 1 do
    begin
      if not aBlock.fLines[i].IsEmpty then
        W.AddString(aBlock.fLines[i].Value);
      W.Add(#10);
    end;
  end;
end;

procedure TMarkdownProcessor.EmitMarkedLines(W: TTextWriter;
  aBlock: TMarkdownBlock);
var
  tmp: TTextWriterStackBuffer;
  sW: TTextWriter;
  i: integer;
  s: RawUtf8;
begin
  sW := TTextWriter.CreateOwnedStream(tmp);
  try
    for i := 0 to aBlock.fLineCount - 1 do
    begin
      if not aBlock.fLines[i].IsEmpty then
      begin
        sW.AddString(copy(aBlock.fLines[i].Value,
          aBlock.fLines[i].Leading + 1,
          length(aBlock.fLines[i].Value) - aBlock.fLines[i].Trailing));
        if aBlock.fLines[i].Trailing >= 2 then
          sW.AddShort('<br/>');
      end;
      if i + 1 < aBlock.fLineCount then
        sW.Add(#10);
    end;
    sW.SetText(s);
  finally
    sW.Free;
  end;
  RecursiveEmitLine(W, s, 1, mtNone);
end;

procedure TMarkdownProcessor.EmitTableLines(W: TTextWriter;
  aBlock: TMarkdownBlock);

  procedure RowSplit(const aInput: RawUtf8; out aCells: TRawUtf8DynArray);
  var
    i, j, L, cnt: integer;
    cell: RawUtf8;
  begin
    aCells := nil;
    cnt := 0;
    L := length(aInput);
    i := 1;
    j := L;
    if (i <= L) and (aInput[i] = '|') then
      inc(i);
    if (j >= 1) and (aInput[j] = '|') and ((j = 1) or (aInput[j - 1] <> '\')) then
      dec(j);
    cell := '';
    while i <= j do
    begin
      if (aInput[i] = '|') and ((i = 1) or (aInput[i - 1] <> '\')) then
      begin
        if cnt >= length(aCells) then
          SetLength(aCells, cnt + 8);
        aCells[cnt] := cell;
        inc(cnt);
        cell := '';
      end
      else
        Append(cell, aInput[i]);
      inc(i);
    end;
    if cnt >= length(aCells) then
      SetLength(aCells, cnt + 1);
    aCells[cnt] := cell;
    inc(cnt);
    SetLength(aCells, cnt);
  end;

  procedure GetAlignments(const aFormatRow: RawUtf8; out aAligns: TRawUtf8DynArray);
  var
    cells: TRawUtf8DynArray;
    i: integer;
    s: RawUtf8;
  begin
    s := TrimU(aFormatRow);
    if (length(s) > 0) and (s[1] = '|') then
      s := copy(s, 2, maxInt);
    if (length(s) > 0) and (s[length(s)] = '|') then
      s := copy(s, 1, length(s) - 1);
    RowSplit(s, cells);
    SetLength(aAligns, length(cells));
    for i := 0 to High(cells) do
    begin
      if (PosEx(':-', cells[i]) > 0) and (PosEx('-:', cells[i]) > 0) then
        aAligns[i] := ' align="center">'
      else if PosEx(':-', cells[i]) > 0 then
        aAligns[i] := ' align="left">'
      else if PosEx('-:', cells[i]) > 0 then
        aAligns[i] := ' align="right">'
      else
        aAligns[i] := '>';
    end;
  end;

var
  i, col, numCols: integer;
  cells, aligns: TRawUtf8DynArray;
  first: boolean;
  tableHtml: RawUtf8;
  tmp2: TTextWriterStackBuffer;
  tW: TTextWriter;
begin
  tW := TTextWriter.CreateOwnedStream(tmp2);
  try
    first := true;
    numCols := 0;
    i := 0;
    while i < aBlock.fLineCount do
    begin
      if aBlock.fLines[i].IsEmpty then
      begin
        inc(i);
        continue;
      end;
      RowSplit(TrimU(aBlock.fLines[i].Value), cells);
      if first then
      begin
        // header row: get alignments from next line (format row)
        numCols := length(cells);
        if i + 1 < aBlock.fLineCount then
          GetAlignments(aBlock.fLines[i + 1].Value, aligns);
        tW.AddShort('<thead>'#10'  <tr>'#10);
        for col := 0 to numCols - 1 do
        begin
          tW.AddShort('    <th');
          if col < length(aligns) then
            tW.AddString(aligns[col])
          else
            tW.Add('>');
          tW.AddString(TrimU(cells[col]));
          tW.AddShort('</th>'#10);
        end;
        tW.AddShort('  </tr>'#10'</thead>'#10'<tbody>'#10);
        first := false;
        inc(i, 2); // skip format row
        continue;
      end
      else
      begin
        tW.AddShort('  <tr>'#10);
        // clamp to numCols (truncate excess, pad missing)
        for col := 0 to numCols - 1 do
        begin
          tW.AddShort('    <td');
          if col < length(aligns) then
            tW.AddString(aligns[col])
          else
            tW.Add('>');
          if col < length(cells) then
            tW.AddString(TrimU(cells[col]));
          tW.AddShort('</td>'#10);
        end;
        tW.AddShort('  </tr>'#10);
      end;
      inc(i);
    end;
    if not first then
      tW.AddShort('</tbody>'#10);
    tW.SetText(tableHtml);
  finally
    tW.Free;
  end;
  // wrap in <table> and emit through recursive line processing
  tableHtml := '<table>'#10 + tableHtml + '</table>'#10;
  RecursiveEmitLine(W, tableHtml, 1, mtNone);
end;

function TMarkdownProcessor.GetToken(const s: RawUtf8;
  aPos: integer): TMarkdownToken;
var
  c0, c, c1, c2, c3: AnsiChar;
  L: integer;
begin
  result := mtNone;
  L := length(s);
  if aPos > L then
    exit;
  if aPos > 1 then
    c0 := WhitespaceToSpace(s[aPos - 1])
  else
    c0 := ' ';
  c := WhitespaceToSpace(s[aPos]);
  if aPos + 1 <= L then
    c1 := WhitespaceToSpace(s[aPos + 1])
  else
    c1 := ' ';
  if aPos + 2 <= L then
    c2 := WhitespaceToSpace(s[aPos + 2])
  else
    c2 := ' ';
  if aPos + 3 <= L then
    c3 := WhitespaceToSpace(s[aPos + 3])
  else
    c3 := ' ';
  case c of
    '*':
      if c1 = '*' then
      begin
        if (c0 <> ' ') or (c2 <> ' ') then
          exit(mtStrongStar);
      end
      else if (c0 <> ' ') or (c1 <> ' ') then
        exit(mtEmStar);
    '_':
      if c1 = '_' then
      begin
        if (c0 <> ' ') or (c2 <> ' ') then
          exit(mtStrongUnderscore);
      end
      else if fDialect in [mdTxtMark, mdCommonMark, mdGitHub] then
      begin
        if (c0 in ['a'..'z', 'A'..'Z', '0'..'9']) and (c0 <> '_') and
           (c1 in ['a'..'z', 'A'..'Z', '0'..'9']) then
          exit(mtNone)
        else
          exit(mtEmUnderscore);
      end
      else if (c0 <> ' ') or (c1 <> ' ') then
        exit(mtEmUnderscore);
    '!':
      if c1 = '[' then
        exit(mtImage);
    '[':
      if (fDialect in [mdTxtMark, mdCommonMark, mdGitHub]) and (c1 = '[') then
        exit(mtXLinkOpen)
      else
        exit(mtLink);
    ']':
      if (fDialect in [mdTxtMark, mdCommonMark, mdGitHub]) and (c1 = ']') then
        exit(mtXLinkClose);
    '`':
      if c1 = '`' then
        exit(mtCodeDouble)
      else
        exit(mtCodeSingle);
    '\':
      if c1 in ['\', '[', ']', '(', ')', '{', '}', '#', '"', '''', '.', '>',
                '<', '*', '+', '-', '_', '!', '`', '~', '^', '$', '|'] then
        exit(mtEscape);
    '<':
      if (fDialect in [mdTxtMark, mdCommonMark, mdGitHub]) and (c1 = '<') then
        exit(mtXLaquo)
      else
        exit(mtHtml);
    '&':
      exit(mtEntity);
  else
    if fDialect in [mdTxtMark, mdCommonMark, mdGitHub] then
      case c of
        '-':
          if (c1 = '-') and (c2 = '-') then
            exit(mtXMdash)
          else if c1 = '-' then
            exit(mtXNdash);
        '^':
          if (c0 = '^') or (c1 = '^') then
            exit(mtNone)
          else
            exit(mtSuper);
        '>':
          if c1 = '>' then
            exit(mtXRaquo);
        '.':
          if (c1 = '.') and (c2 = '.') then
            exit(mtXHellip);
        '(':
          begin
            if (c1 = 'C') and (c2 = ')') then
              exit(mtXCopy);
            if (c1 = 'R') and (c2 = ')') then
              exit(mtXReg);
            if (c1 = 'T') and (c2 = 'M') and (c3 = ')') then
              exit(mtXTrade);
          end;
        '"':
          begin
            if not (c0 in ['a'..'z', 'A'..'Z', '0'..'9']) and (c1 <> ' ') then
              exit(mtXLdquo);
            if (c0 <> ' ') and not (c1 in ['a'..'z', 'A'..'Z', '0'..'9']) then
              exit(mtXRdquo);
          end;
      end;
    if fDialect in [mdCommonMark, mdGitHub] then
      case c of
        '~':
          if c1 = '~' then
          begin
            if (c0 <> ' ') or (c2 <> ' ') then
              exit(mtStrikeTilde);
          end
          else if fDialect = mdCommonMark then
            if (c0 <> ' ') or (c1 <> ' ') then
              exit(mtSubTilde);
      end;
    if fDialect = mdCommonMark then
      case c of
        '+':
          if (c1 = '+') and ((c0 <> ' ') or (c2 <> ' ')) then
            exit(mtInsPlus);
        '=':
          if (c1 = '=') and ((c0 <> ' ') or (c2 <> ' ')) then
            exit(mtMarkEqual);
        '$':
          if (c0 <> ' ') or (c1 <> ' ') then
            exit(mtMathDollar);
      end;
    // bare URL autolinks (GFM extension)
    if fDialect = mdGitHub then
      if c = 'h' then
      begin
        if (aPos + 7 <= L) and (s[aPos + 1] = 't') and (s[aPos + 2] = 't') and
           (s[aPos + 3] = 'p') then
          if (s[aPos + 4] = 's') and (s[aPos + 5] = ':') and
             (s[aPos + 6] = '/') and (s[aPos + 7] = '/') then
          begin
            if (aPos = 1) or not (c0 in ['a'..'z', 'A'..'Z', '0'..'9']) then
              exit(mtAutoLink);
          end
          else if (s[aPos + 4] = ':') and (s[aPos + 5] = '/') and
                  (s[aPos + 6] = '/') then
          begin
            if (aPos = 1) or not (c0 in ['a'..'z', 'A'..'Z', '0'..'9']) then
              exit(mtAutoLink);
          end;
      end
      else if c = 'w' then
      begin
        if (aPos + 3 <= L) and (s[aPos + 1] = 'w') and
           (s[aPos + 2] = 'w') and (s[aPos + 3] = '.') then
          if (aPos = 1) or not (c0 in ['a'..'z', 'A'..'Z', '0'..'9']) then
            exit(mtAutoLink);
      end;
  end;
end;

function TMarkdownProcessor.FindToken(const s: RawUtf8; aStart: integer;
  aToken: TMarkdownToken): integer;
var
  p: integer;
begin
  p := aStart;
  while p <= length(s) do
  begin
    if GetToken(s, p) = aToken then
      exit(p);
    inc(p);
  end;
  result := -1;
end;

function TMarkdownProcessor.CheckLink(W: TTextWriter; const s: RawUtf8;
  aStart: integer; aToken: TMarkdownToken): integer;
var
  isAbbrev, useLt, hasLink: boolean;
  p, oldPos: integer;
  tmp: TTextWriterStackBuffer;
  tempW: TTextWriter;
  name, link, comment, refId: RawUtf8;
  lr: TMarkdownLinkRef;
begin
  result := -1;
  if aToken = mtLink then
    p := aStart + 1
  else
    p := aStart + 2;
  isAbbrev := false;
  tempW := TTextWriter.CreateOwnedStream(tmp);
  try
    p := ReadMdLinkId(tempW, s, p);
    if p < aStart then
      exit;
    tempW.SetText(name);
    link := '';
    hasLink := false;
    comment := '';
    oldPos := p;
    inc(p);
    p := SkipSpacesAt(s, p);
    if p < aStart then
    begin
      if FindLinkRef(name, lr) then
      begin
        isAbbrev := lr.IsAbbrev;
        link := lr.Link;
        hasLink := true;
        comment := lr.Title;
        p := oldPos;
      end
      else
        exit;
    end
    else if s[p] = '(' then
    begin
      inc(p);
      p := SkipSpacesAt(s, p);
      if p < aStart then
        exit;
      tempW.CancelAll;
      useLt := (s[p] = '<');
      if useLt then
        p := ReadUntilChar(tempW, s, p + 1, '>')
      else
        p := ReadMdLink(tempW, s, p);
      if p < aStart then
        exit;
      if useLt then
        inc(p);
      tempW.SetText(link);
      hasLink := true;
      if s[p] = ' ' then
      begin
        p := SkipSpacesAt(s, p);
        if (p > aStart) and (s[p] = '"') then
        begin
          inc(p);
          tempW.CancelAll;
          p := ReadUntilChar(tempW, s, p, '"');
          if p < aStart then
            exit;
          tempW.SetText(comment);
          inc(p);
          p := SkipSpacesAt(s, p);
          if p = -1 then
            exit;
        end;
      end;
      if s[p] <> ')' then
        exit;
    end
    else if s[p] = '[' then
    begin
      inc(p);
      tempW.CancelAll;
      p := ReadRawUntilChar(tempW, s, p, ']');
      if p < aStart then
        exit;
      tempW.SetText(refId);
      if refId = '' then
        refId := name;
      if FindLinkRef(refId, lr) then
      begin
        link := lr.Link;
        hasLink := true;
        comment := lr.Title;
      end;
    end
    else
    begin
      if FindLinkRef(name, lr) then
      begin
        isAbbrev := lr.IsAbbrev;
        link := lr.Link;
        hasLink := true;
        comment := lr.Title;
        p := oldPos;
      end
      else
        exit;
    end;
    if not hasLink then
      exit;
    if aToken = mtLink then
    begin
      if isAbbrev and (comment <> '') then
      begin
        W.AddShort('<abbr title:="');
        AppendValue(W, comment, 1, length(comment));
        W.AddShorter('">');
        RecursiveEmitLine(W, name, 1, mtNone);
        W.AddShort('</abbr>');
      end
      else
      begin
        fDecorator.OpenLink(W);
        W.AddShort(' href="');
        CodeEncode(W, link, 1);
        W.Add('"');
        if comment <> '' then
        begin
          W.AddShort(' title="');
          AppendValue(W, comment, 1, length(comment));
          W.Add('"');
        end;
        W.Add('>');
        RecursiveEmitLine(W, name, 1, mtNone);
        fDecorator.CloseLink(W);
      end;
    end
    else
    begin
      fDecorator.OpenImage(W);
      W.AddShort(' src="');
      CodeEncode(W, link, 1);
      W.AddShort('" alt="');
      AppendValue(W, name, 1, length(name));
      W.Add('"');
      if comment <> '' then
      begin
        W.AddShort(' title="');
        AppendValue(W, comment, 1, length(comment));
        W.Add('"');
      end;
      fDecorator.CloseImage(W);
    end;
    result := p;
  finally
    tempW.Free;
  end;
end;

function TMarkdownProcessor.CheckHtml(W: TTextWriter; const s: RawUtf8;
  aStart: integer): integer;
var
  tmp: TTextWriterStackBuffer;
  tempW: TTextWriter;
  p: integer;
  link: RawUtf8;
begin
  result := -1;
  tempW := TTextWriter.CreateOwnedStream(tmp);
  try
    // check for auto links
    p := ReadUntilSet(tempW, s, aStart + 1, [':', ' ', '>', #10]);
    if (p > 0) and (p <= length(s)) and (s[p] = ':') then
    begin
      p := ReadUntilSet(tempW, s, p, ['>']);
      if p > 0 then
      begin
        tempW.SetText(link);
        fDecorator.OpenLink(W);
        W.AddShort(' href="');
        CodeEncode(W, link, 1);
        W.AddShorter('">');
        AppendValue(W, link, 1, length(link));
        fDecorator.CloseLink(W);
        exit(p);
      end;
    end;
    // check for mailto
    tempW.CancelAll;
    p := ReadUntilSet(tempW, s, aStart + 1, ['@', ' ', '>', #10]);
    if (p > 0) and (p <= length(s)) and (s[p] = '@') then
    begin
      p := ReadUntilChar(tempW, s, p, '>');
      if p > 0 then
      begin
        tempW.SetText(link);
        fDecorator.OpenLink(W);
        W.AddShort(' href="');
        AppendMailto(W, 'mailto:', 1, 7);
        AppendMailto(W, link, 1, length(link));
        W.AddShorter('">');
        AppendMailto(W, link, 1, length(link));
        fDecorator.CloseLink(W);
        exit(p);
      end;
    end;
    // check for inline html
    if aStart + 2 <= length(s) then
      exit(ReadXml(W, s, aStart, fSafeMode));
  finally
    tempW.Free;
  end;
end;

function TMarkdownProcessor.CheckEntity(W: TTextWriter; const s: RawUtf8;
  aStart: integer): integer;
var
  tmp: TTextWriterStackBuffer;
  tempW: TTextWriter;
  p, i: integer;
  c: AnsiChar;
  entity, fullEntity: RawUtf8;
begin
  result := -1;
  tempW := TTextWriter.CreateOwnedStream(tmp);
  try
    // aStart points to '&', read from next char until ';'
    p := ReadUntilChar(tempW, s, aStart + 1, ';');
    tempW.SetText(entity);
    if (p < 0) or (length(entity) < 1) then
      exit;
    if entity[1] = '#' then
    begin
      if (length(entity) >= 2) and ((entity[2] = 'x') or (entity[2] = 'X')) then
      begin
        if length(entity) < 3 then
          exit;
        for i := 3 to length(entity) do
        begin
          c := entity[i];
          if not (c in ['0'..'9', 'a'..'f', 'A'..'F']) then
            exit;
        end;
      end
      else
        for i := 2 to length(entity) do
          if not (entity[i] in ['0'..'9']) then
            exit;
      W.Add('&');
      W.AddString(entity);
      W.Add(';');
    end
    else
    begin
      for i := 1 to length(entity) do
        if not (entity[i] in ['a'..'z', 'A'..'Z', '0'..'9']) then
          exit;
      fullEntity := '&' + entity + ';';
      if not IsEntity(fullEntity) then
        exit;
      W.AddString(fullEntity);
    end;
    result := p;
  finally
    tempW.Free;
  end;
end;

function TMarkdownProcessor.CheckMathCode(W: TTextWriter; const s: RawUtf8;
  aStart: integer): integer;
var
  tmp: TTextWriterStackBuffer;
  tempW: TTextWriter;
  p: integer;
  code: RawUtf8;
begin
  result := -1;
  tempW := TTextWriter.CreateOwnedStream(tmp);
  try
    p := ReadUntilSet(tempW, s, aStart + 1, [' ', '$', #10]);
    if (p > 0) and (p <= length(s)) and (s[p] = '$') and
       ((p = 1) or (s[p - 1] <> '\')) then
    begin
      tempW.SetText(code);
      W.AddShort('<img src="https://chart.googleapis.com/chart?cht=tx&chl=');
      CodeEncode(W, code, 1);
      W.AddShort('" alt="');
      AppendValue(W, code, 1, length(code));
      W.AddShort(' "/>');
      exit(p);
    end;
  finally
    tempW.Free;
  end;
end;

function TMarkdownProcessor.RecursiveEmitLine(W: TTextWriter; const s: RawUtf8;
  aStart: integer; aToken: TMarkdownToken): integer;
var
  p, a, b, i, L: integer;
  tmp: TTextWriterStackBuffer;
  tempW: TTextWriter;
  mt: TMarkdownToken;
  tempStr: RawUtf8;
begin
  p := aStart;
  L := length(s);
  tempW := TTextWriter.CreateOwnedStream(tmp);
  try
    while p <= L do
    begin
      mt := GetToken(s, p);
      if (aToken <> mtNone) and
         ((mt = aToken) or
          ((aToken = mtEmStar) and (mt = mtStrongStar)) or
          ((aToken = mtEmUnderscore) and (mt = mtStrongUnderscore))) then
        exit(p);
      case mt of
        mtImage, mtLink:
          begin
            tempW.CancelAll;
            b := CheckLink(tempW, s, p, mt);
            if b > 0 then
            begin
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              p := b;
            end
            else
              W.Add(s[p]);
          end;
        mtEmStar, mtEmUnderscore:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 1, mt);
            if b > 0 then
            begin
              fDecorator.OpenEmphasis(W);
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              fDecorator.CloseEmphasis(W);
              p := b;
            end
            else
              W.Add(s[p]);
          end;
        mtStrongStar, mtStrongUnderscore:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 2, mt);
            if b > 0 then
            begin
              fDecorator.OpenStrong(W);
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              fDecorator.CloseStrong(W);
              p := b + 1;
            end
            else
              W.Add(s[p]);
          end;
        mtStrikeTilde:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 2, mt);
            if b > 0 then
            begin
              fDecorator.OpenStrike(W);
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              fDecorator.CloseStrike(W);
              p := b + 1;
            end
            else
              W.Add(s[p]);
          end;
        mtInsPlus:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 2, mt);
            if b > 0 then
            begin
              fDecorator.OpenIns(W);
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              fDecorator.CloseIns(W);
              p := b + 1;
            end
            else
              W.Add(s[p]);
          end;
        mtMarkEqual:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 2, mt);
            if b > 0 then
            begin
              fDecorator.OpenMark(W);
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              fDecorator.CloseMark(W);
              p := b + 1;
            end
            else
              W.Add(s[p]);
          end;
        mtSuper:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 1, mt);
            if b > 0 then
            begin
              fDecorator.OpenSuper(W);
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              fDecorator.CloseSuper(W);
              p := b;
            end
            else
              W.Add(s[p]);
          end;
        mtSubTilde:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 1, mt);
            if b > 0 then
            begin
              fDecorator.OpenSub(W);
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              fDecorator.CloseSub(W);
              p := b;
            end
            else
              W.Add(s[p]);
          end;
        mtCodeSingle, mtCodeDouble:
          begin
            if mt = mtCodeDouble then
              a := p + 2
            else
              a := p + 1;
            b := FindToken(s, a, mt);
            if b > 0 then
            begin
              if mt = mtCodeDouble then
                p := b + 1
              else
                p := b;
              while (a < b) and (s[a] = ' ') do
                inc(a);
              if a < b then
                while s[b - 1] = ' ' do
                  dec(b);
              fDecorator.OpenCodeSpan(W);
              AppendCode(W, s, a, b - 1);
              fDecorator.CloseCodeSpan(W);
            end
            else
              W.Add(s[p]);
          end;
        mtHtml:
          begin
            tempW.CancelAll;
            b := CheckHtml(tempW, s, p);
            if b > 0 then
            begin
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              p := b;
            end
            else
              W.AddShorter('&lt;');
          end;
        mtEntity:
          begin
            tempW.CancelAll;
            b := CheckEntity(tempW, s, p);
            if b > 0 then
            begin
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              p := b;
            end
            else
              W.AddShorter('&amp;');
          end;
        mtXLinkOpen:
          begin
            tempW.CancelAll;
            b := RecursiveEmitLine(tempW, s, p + 2, mtXLinkClose);
            if b > 0 then
              p := b + 1  // skip ]]
            else
              W.Add(s[p]);
          end;
        mtXCopy:
          begin
            W.AddShort('&copy;');
            inc(p, 2);
          end;
        mtXReg:
          begin
            W.AddShorter('&reg;');
            inc(p, 2);
          end;
        mtXTrade:
          begin
            W.AddShort('&trade;');
            inc(p, 3);
          end;
        mtXNdash:
          begin
            W.AddShort('&ndash;');
            inc(p);
          end;
        mtXMdash:
          begin
            W.AddShort('&mdash;');
            inc(p, 2);
          end;
        mtXHellip:
          begin
            W.AddShort('&hellip;');
            inc(p, 2);
          end;
        mtXLaquo:
          begin
            W.AddShort('&laquo;');
            inc(p);
          end;
        mtXRaquo:
          begin
            W.AddShort('&raquo;');
            inc(p);
          end;
        mtXRdquo:
          W.AddShort('&rdquo;');
        mtXLdquo:
          W.AddShort('&ldquo;');
        mtEscape:
          begin
            inc(p);
            if p <= L then
              W.Add(s[p]);
          end;
        mtMathDollar:
          begin
            tempW.CancelAll;
            b := CheckMathCode(tempW, s, p);
            if b > 0 then
            begin
              tempW.SetText(tempStr);
              W.AddString(tempStr);
              p := b;
            end
            else
              W.Add('$');
          end;
        mtAutoLink:
          begin
            // scan to end of URL (whitespace, < or end of string)
            b := p;
            while (b <= L) and not (s[b] in [' ', #9, #10, #13, '<']) do
              inc(b);
            // parenthesis balancing: strip excess closing parens
            a := 0; // balance counter
            for i := p to b - 1 do
              if s[i] = '(' then
                inc(a)
              else if s[i] = ')' then
                dec(a);
            while (a < 0) and (b > p) and (s[b - 1] = ')') do
            begin
              dec(b);
              inc(a);
            end;
            // trim trailing punctuation per GFM spec
            while (b > p) and (s[b - 1] in ['.', ',', ';', ':', '!', '?',
                  '''', '*', '_', '~']) do
              dec(b);
            tempStr := copy(s, p, b - p);
            W.AddShort('<a href="');
            if (length(tempStr) >= 4) and (tempStr[1] = 'w') and
               (tempStr[2] = 'w') and (tempStr[3] = 'w') and
               (tempStr[4] = '.') then
              W.AddShort('http://');
            AppendValue(W, tempStr, 1, length(tempStr));
            W.AddShorter('">');
            AppendValue(W, tempStr, 1, length(tempStr));
            W.AddShort('</a>');
            p := b - 1; // -1 because inc(p) at end of loop
          end;
      else
        W.Add(s[p]);
      end;
      inc(p);
    end;
    result := -1;
  finally
    tempW.Free;
  end;
end;

function MarkdownToHtml(const aSource: RawUtf8;
  aDialect: TMarkdownDialect): RawUtf8;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(aDialect);
  try
    result := md.Process(aSource);
  finally
    md.Free;
  end;
end;

end.

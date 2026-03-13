/// regression tests for mormot.ext.markdown
unit mormot.ext.markdown.test;

{$I mormot.defines.inc}

interface

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.test,
  mormot.ext.markdown;

type
  TTestMarkdown = class(TSynTestCase)
  published
    // --- core tests ---
    procedure Headings;
    procedure Paragraphs;
    procedure EmphasisAndStrong;
    procedure CodeSpans;
    procedure CodeBlocks;
    procedure Lists;
    procedure BlockQuotes;
    procedure HorizontalRules;
    procedure Links;
    procedure Images;
    procedure Tables;
    procedure HtmlEntities;
    procedure RawHtml;
    procedure SmartTypography;
    procedure ExtendedFormatting;
    procedure EscapedCharacters;
    procedure NestedFormatting;
    procedure EdgeCases;
    procedure Dialects;
    procedure SafeMode;
    procedure LinkReferences;
    procedure FencedCodeMeta;
    procedure ConvenienceFunction;
    // --- advanced block-level ---
    procedure HeadingsAdvanced;
    procedure ParagraphsAdvanced;
    procedure CodeBlocksAdvanced;
    procedure ListsAdvanced;
    procedure BlockQuotesAdvanced;
    procedure HorizontalRulesAdvanced;
    procedure LineBreaks;
    // --- advanced inline ---
    procedure EmphasisAdvanced;
    procedure LinksAdvanced;
    procedure ImagesAdvanced;
    procedure AutoLinks;
    procedure EscapedCharactersAdvanced;
    procedure NestedConstructs;
    // --- tables & formatting ---
    procedure TablesAdvanced;
    procedure EntitiesAdvanced;
    // --- safe mode & stress ---
    procedure SafeModeAdvanced;
    procedure StressTests;
    procedure MalformedInput;
    // --- spec compliance ---
    procedure ThematicBreakVariants;
    procedure AtxHeadingEdgeCases;
    procedure SetextHeadingEdgeCases;
    procedure IndentedCodePreservation;
    procedure FencedCodeFenceRules;
    procedure ListLooseAndMarkers;
    procedure BackslashEscapeSet;
    procedure CodeSpanHtmlEscape;
    procedure HeadingIdStripping;
    procedure TabExpansion;
    procedure TxtMarkDialect;
    procedure ConvenienceFunctionDialect;
    procedure StrikethroughDialectScope;
    procedure TableEscapedPipes;
    procedure SmartTypographyCaseSensitivity;
    procedure ProfileExtended;
    procedure FencedCodeNoLang;
    procedure LinkAngleBracketUrl;
    // --- GFM dialect ---
    procedure GitHubDialect;
    procedure TaskLists;
    procedure GfmStrikethrough;
    procedure GfmAutolinks;
    procedure GfmTables;
  end;

  TTestMarkdownSuite = class(TSynTests)
  published
    procedure MarkdownProcessing;
  end;

implementation

{ TTestMarkdownSuite }

procedure TTestMarkdownSuite.MarkdownProcessing;
begin
  AddCase([TTestMarkdown]);
end;

{ TTestMarkdown }

// ===== CORE TESTS =====

procedure TTestMarkdown.Headings;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    CheckEqual(md.Process('# H1'), '<h1>H1</h1>'#10);
    CheckEqual(md.Process('## H2'), '<h2>H2</h2>'#10);
    CheckEqual(md.Process('### H3'), '<h3>H3</h3>'#10);
    CheckEqual(md.Process('#### H4'), '<h4>H4</h4>'#10);
    CheckEqual(md.Process('##### H5'), '<h5>H5</h5>'#10);
    CheckEqual(md.Process('###### H6'), '<h6>H6</h6>'#10);
    CheckEqual(md.Process('## H2 ##'), '<h2>H2</h2>'#10);
    CheckEqual(md.Process('H1'#10'=='), '<h1>H1</h1>'#10);
    CheckEqual(md.Process('H2'#10'--'), '<h2>H2</h2>'#10);
    Check(PosEx('id="my-id"', md.Process('# Heading {#my-id}')) > 0,
      'heading id extraction');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.Paragraphs;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('Hello world');
    CheckEqual(r, '<p>Hello world</p>'#10);
    r := md.Process('Para 1'#10#10'Para 2');
    Check(PosEx('<p>Para 1</p>', r) > 0, 'para 1');
    Check(PosEx('<p>Para 2</p>', r) > 0, 'para 2');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.EmphasisAndStrong;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<em>italic</em>', md.Process('*italic*')) > 0, '*em*');
    Check(PosEx('<em>italic</em>', md.Process('_italic_')) > 0, '_em_');
    Check(PosEx('<strong>bold</strong>', md.Process('**bold**')) > 0, '**strong**');
    Check(PosEx('<strong>bold</strong>', md.Process('__bold__')) > 0, '__strong__');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.CodeSpans;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<code>code</code>', md.Process('`code`')) > 0, 'single backtick');
    Check(PosEx('<code>', md.Process('``code with ` backtick``')) > 0,
      'double backtick');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.CodeBlocks;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('    code line');
    Check(PosEx('<pre><code>', r) > 0, 'indented code');
    Check(PosEx('code line', r) > 0, 'indented code content');
    r := md.Process('```'#10'fenced'#10'```');
    Check(PosEx('<pre><code>', r) > 0, 'fenced code');
    Check(PosEx('fenced', r) > 0, 'fenced code content');
    r := md.Process('~~~'#10'tilde fenced'#10'~~~');
    Check(PosEx('<pre><code>', r) > 0, 'tilde fenced code');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.Lists;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('* item 1'#10'* item 2');
    Check(PosEx('<ul>', r) > 0, 'ul open');
    Check(PosEx('<li', r) > 0, 'li');
    Check(PosEx('item 1', r) > 0, 'item 1');
    Check(PosEx('item 2', r) > 0, 'item 2');
    r := md.Process('1. first'#10'2. second');
    Check(PosEx('<ol>', r) > 0, 'ol open');
    Check(PosEx('first', r) > 0, 'first');
    Check(PosEx('second', r) > 0, 'second');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.BlockQuotes;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('> quoted text');
    Check(PosEx('<blockquote>', r) > 0, 'blockquote open');
    Check(PosEx('quoted text', r) > 0, 'quoted content');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.HorizontalRules;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<hr />', md.Process('---')) > 0, '--- rule');
    Check(PosEx('<hr />', md.Process('***')) > 0, '*** rule');
    Check(PosEx('<hr />', md.Process('___')) > 0, '___ rule');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.Links;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('[text](http://example.com)');
    Check(PosEx('href="http://example.com"', r) > 0, 'inline link href');
    Check(PosEx('>text</a>', r) > 0, 'inline link text');
    r := md.Process('[text](http://example.com "Title")');
    Check(PosEx('title="Title"', r) > 0, 'link title');
    r := md.Process('<http://example.com>');
    Check(PosEx('href="http://example.com"', r) > 0, 'auto link');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.Images;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('![alt text](image.png "Title")');
    Check(PosEx('<img', r) > 0, 'img tag');
    Check(PosEx('src="image.png"', r) > 0, 'img src');
    Check(PosEx('alt="alt text"', r) > 0, 'img alt');
    Check(PosEx('title="Title"', r) > 0, 'img title');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.Tables;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process(
      '| H1 | H2 |'#10 +
      '| --- | --- |'#10 +
      '| A | B |');
    Check(PosEx('<table>', r) > 0, 'table tag');
    Check(PosEx('<th', r) > 0, 'th tag');
    Check(PosEx('<td', r) > 0, 'td tag');
    Check(PosEx('H1', r) > 0, 'header content');
    Check(PosEx('A', r) > 0, 'cell content');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.HtmlEntities;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('&amp;');
    Check(PosEx('&amp;', r) > 0, '&amp; entity');
    r := md.Process('&copy;');
    Check(PosEx('&copy;', r) > 0, '&copy; entity');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.RawHtml;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    md.SafeMode := false;
    r := md.Process('<div>hello</div>');
    Check(PosEx('<div>hello</div>', r) > 0, 'raw html passthrough');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.SmartTypography;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('&copy;', md.Process('(C)')) > 0, '(C)');
    Check(PosEx('&reg;', md.Process('(R)')) > 0, '(R)');
    Check(PosEx('&trade;', md.Process('(TM)')) > 0, '(TM)');
    Check(PosEx('&ndash;', md.Process('a--b')) > 0, '--');
    Check(PosEx('&mdash;', md.Process('a---b')) > 0, '---');
    Check(PosEx('&hellip;', md.Process('...')) > 0, '...');
    Check(PosEx('&laquo;', md.Process('a<<b')) > 0, '<<');
    Check(PosEx('&raquo;', md.Process('a>>b')) > 0, '>>');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ExtendedFormatting;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<del>', md.Process('~~strike~~')) > 0, '~~strike~~');
    Check(PosEx('<ins>', md.Process('++insert++')) > 0, '++insert++');
    Check(PosEx('<mark>', md.Process('==mark==')) > 0, '==mark==');
    Check(PosEx('<sub>', md.Process('~sub~')) > 0, '~sub~');
    Check(PosEx('<sup>', md.Process('^sup^')) > 0, '^sup^');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.EscapedCharacters;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('\*not italic\*');
    Check(PosEx('<em>', r) = 0, 'escaped star should not produce em');
    Check(PosEx('*not italic*', r) > 0, 'escaped chars preserved');
    r := md.Process('\[not a link\]');
    Check(PosEx('<a', r) = 0, 'escaped bracket should not produce link');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.NestedFormatting;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('**_bold italic_**');
    Check(PosEx('<strong>', r) > 0, 'nested strong');
    Check(PosEx('<em>', r) > 0, 'nested em inside strong');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.EdgeCases;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    CheckEqual(md.Process(''), '', 'empty input');
    CheckEqual(md.Process('   '), '', 'whitespace only');
    CheckEqual(md.Process(#10), '', 'single newline');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.Dialects;
var
  df, cm: TMarkdownProcessor;
begin
  df := TMarkdownProcessor.Create(mdDaringFireball);
  cm := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<h1>', df.Process('#H1')) > 0, 'DF no space after #');
    Check(PosEx('<h1>', cm.Process('#H1')) = 0, 'CM requires space after #');
    Check(PosEx('<h1>', cm.Process('# H1')) > 0, 'CM with space after #');
  finally
    df.Free;
    cm.Free;
  end;
end;

procedure TTestMarkdown.SafeMode;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    md.SafeMode := true;
    r := md.Process('<script>alert("xss")</script>');
    Check(PosEx('<script>', r) = 0, 'script tag blocked in safe mode');
    md.SafeMode := false;
    r := md.Process('<div>safe content</div>');
    Check(PosEx('<div>', r) > 0, 'div allowed in unsafe mode');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.LinkReferences;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('[link text][ref]'#10#10'[ref]: http://example.com "Title"');
    Check(PosEx('href="http://example.com"', r) > 0, 'ref link href');
    Check(PosEx('title="Title"', r) > 0, 'ref link title');
    Check(PosEx('>link text</a>', r) > 0, 'ref link text');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.FencedCodeMeta;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('```python'#10'x = 1'#10'```');
    Check(PosEx('class="python"', r) > 0, 'fenced code language class');
    Check(PosEx('x = 1', r) > 0, 'fenced code content');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ConvenienceFunction;
var
  r: RawUtf8;
begin
  r := MarkdownToHtml('# Hello');
  Check(PosEx('<h1>', r) > 0, 'MarkdownToHtml convenience');
  Check(PosEx('Hello', r) > 0, 'MarkdownToHtml content');
end;

// ===== ADVANCED BLOCK-LEVEL =====

procedure TTestMarkdown.HeadingsAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<h1>', md.Process('  # H1')) > 0, 'ATX 2 leading spaces');
    r := md.Process('Title'#10'=====');
    Check(PosEx('<h1>', r) > 0, 'setext h1 long underline');
    r := md.Process('Title'#10'-----');
    Check(PosEx('<h2>', r) > 0, 'setext h2 long underline');
    r := md.Process('Title'#10'=');
    Check(PosEx('<h1>', r) > 0, 'setext h1 single =');
    r := md.Process('# H1'#10#10'Paragraph');
    Check(PosEx('<h1>', r) > 0, 'heading then para h1');
    Check(PosEx('<p>Paragraph</p>', r) > 0, 'heading then para p');
    r := md.Process('# H1'#10#10'## H2'#10#10'### H3');
    Check(PosEx('<h1>H1</h1>', r) > 0, 'multi h1');
    Check(PosEx('<h2>H2</h2>', r) > 0, 'multi h2');
    Check(PosEx('<h3>H3</h3>', r) > 0, 'multi h3');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ParagraphsAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('One'#10#10'Two'#10#10'Three');
    Check(PosEx('<p>One</p>', r) > 0, 'three paras first');
    Check(PosEx('<p>Two</p>', r) > 0, 'three paras second');
    Check(PosEx('<p>Three</p>', r) > 0, 'three paras third');
    r := md.Process('Hello **world**');
    Check(PosEx('<p>', r) > 0, 'para with strong p');
    Check(PosEx('<strong>world</strong>', r) > 0, 'para with strong');
    r := md.Process('A'#10#10#10#10'B');
    Check(PosEx('<p>A</p>', r) > 0, 'multi blank A');
    Check(PosEx('<p>B</p>', r) > 0, 'multi blank B');
    r := md.Process('Line 1'#13#10#13#10'Line 2');
    Check(PosEx('<p>Line 1</p>', r) > 0, 'CRLF para 1');
    Check(PosEx('<p>Line 2</p>', r) > 0, 'CRLF para 2');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.CodeBlocksAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('```'#10'line 1'#10'line 2'#10'line 3'#10'```');
    Check(PosEx('<pre><code>', r) > 0, 'multi-line fenced');
    Check(PosEx('line 1', r) > 0, 'fenced line 1');
    Check(PosEx('line 3', r) > 0, 'fenced line 3');
    r := md.Process('```'#10'<script>alert(1)</script>'#10'```');
    Check(PosEx('<script>', r) = 0, 'fenced escapes script');
    Check(PosEx('&lt;script&gt;', r) > 0, 'fenced has entities');
    r := md.Process('    line 1'#10'    line 2');
    Check(PosEx('<pre><code>', r) > 0, 'multi-line indented');
    r := md.Process('```javascript'#10'var x = 1;'#10'```');
    Check(PosEx('class="javascript"', r) > 0, 'js class');
    r := md.Process('~~~ruby'#10'puts "hi"'#10'~~~');
    Check(PosEx('class="ruby"', r) > 0, 'ruby class tilde');
    r := md.Process('    <div>test</div>');
    Check(PosEx('<div>', r) = 0, 'indented escapes html');
    Check(PosEx('&lt;div&gt;', r) > 0, 'indented entity escapes');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ListsAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('- item A'#10'- item B');
    Check(PosEx('<ul>', r) > 0, 'dash ul');
    Check(PosEx('item A', r) > 0, 'dash A');
    r := md.Process('+ item A'#10'+ item B');
    Check(PosEx('<ul>', r) > 0, 'plus ul');
    Check(PosEx('item A', r) > 0, 'plus A');
    r := md.Process('1. one'#10'2. two'#10'3. three');
    Check(PosEx('<ol>', r) > 0, 'ol 3');
    Check(PosEx('three', r) > 0, 'ol three');
    r := md.Process('* **bold item**'#10'* *italic item*');
    Check(PosEx('<strong>bold item</strong>', r) > 0, 'list bold');
    Check(PosEx('<em>italic item</em>', r) > 0, 'list italic');
    r := md.Process('* `code item`'#10'* normal');
    Check(PosEx('<code>code item</code>', r) > 0, 'list code');
    r := md.Process('* [link](http://example.com)');
    Check(PosEx('href="http://example.com"', r) > 0, 'list link');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.BlockQuotesAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('> line 1'#10'> line 2');
    Check(PosEx('<blockquote>', r) > 0, 'multi-line bq');
    Check(PosEx('line 1', r) > 0, 'bq line 1');
    Check(PosEx('line 2', r) > 0, 'bq line 2');
    r := md.Process('> **bold** quote');
    Check(PosEx('<strong>bold</strong>', r) > 0, 'bq strong');
    r := md.Process('> # Heading');
    Check(PosEx('<blockquote>', r) > 0, 'bq heading open');
    Check(PosEx('<h1>', r) > 0, 'bq heading h1');
    r := md.Process('> > nested');
    Check(PosEx('<blockquote>', r) > 0, 'nested bq');
    Check(PosEx('nested', r) > 0, 'nested bq content');
    // blockquote ends at blank line
    r := md.Process('> quoted'#10#10'not quoted');
    Check(PosEx('<blockquote>', r) > 0, 'bq before blank');
    Check(PosEx('<p>not quoted</p>', r) > 0, 'para after bq');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.HorizontalRulesAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<hr />', md.Process('----')) > 0, '---- rule');
    Check(PosEx('<hr />', md.Process('****')) > 0, '**** rule');
    Check(PosEx('<hr />', md.Process('____')) > 0, '____ rule');
    Check(PosEx('<hr />', md.Process('- - -')) > 0, '- - - rule');
    Check(PosEx('<hr />', md.Process('* * *')) > 0, '* * * rule');
    r := md.Process('Before'#10#10'---'#10#10'After');
    Check(PosEx('<hr />', r) > 0, 'hr between paras');
    Check(PosEx('Before', r) > 0, 'hr before');
    Check(PosEx('After', r) > 0, 'hr after');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.LineBreaks;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // hard line break: two trailing spaces
    r := md.Process('line 1  '#10'line 2');
    Check((PosEx('<br/>', r) > 0) or (PosEx('<br />', r) > 0),
      'hard break 2 spaces');
    Check(PosEx('line 1', r) > 0, 'hard break line 1');
    Check(PosEx('line 2', r) > 0, 'hard break line 2');
    // three trailing spaces also work
    r := md.Process('line 1   '#10'line 2');
    Check((PosEx('<br/>', r) > 0) or (PosEx('<br />', r) > 0),
      'hard break 3 spaces');
    // no trailing spaces = soft break
    r := md.Process('line 1'#10'line 2');
    Check((PosEx('<br/>', r) = 0) and (PosEx('<br />', r) = 0),
      'soft break no br');
    Check(PosEx('line 1', r) > 0, 'soft break line 1');
    Check(PosEx('line 2', r) > 0, 'soft break line 2');
  finally
    md.Free;
  end;
end;

// ===== ADVANCED INLINE =====

procedure TTestMarkdown.EmphasisAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('***bold italic***');
    Check(PosEx('<strong>', r) > 0, '*** strong');
    Check(PosEx('<em>', r) > 0, '*** em');
    r := md.Process('Hello *world* today');
    Check(PosEx('<em>world</em>', r) > 0, 'em in para');
    r := md.Process('Hello **world** today');
    Check(PosEx('<strong>world</strong>', r) > 0, 'strong in para');
    r := md.Process('*a* and *b*');
    Check(PosEx('<em>a</em>', r) > 0, 'adjacent em a');
    Check(PosEx('<em>b</em>', r) > 0, 'adjacent em b');
    r := md.Process('**_mixed_**');
    Check(PosEx('<strong>', r) > 0, 'mixed strong');
    Check(PosEx('<em>', r) > 0, 'mixed em');
    // _**strong em**_
    r := md.Process('_**strong em**_');
    Check(PosEx('<em>', r) > 0, 'outer em');
    Check(PosEx('<strong>', r) > 0, 'inner strong');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.LinksAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('[**bold link**](http://example.com)');
    Check(PosEx('<strong>bold link</strong>', r) > 0, 'bold link text');
    Check(PosEx('href="http://example.com"', r) > 0, 'bold link href');
    r := md.Process('[text](/path/to/page)');
    Check(PosEx('href="/path/to/page"', r) > 0, 'relative path');
    // case-insensitive ref links
    r := md.Process('[link text][REF]'#10#10'[ref]: http://example.com');
    Check(PosEx('href="http://example.com"', r) > 0, 'ref case insensitive');
    // multiple ref links
    r := md.Process(
      '[link1][a] and [link2][b]'#10#10 +
      '[a]: http://a.com'#10 +
      '[b]: http://b.com');
    Check(PosEx('href="http://a.com"', r) > 0, 'multi ref a');
    Check(PosEx('href="http://b.com"', r) > 0, 'multi ref b');
    // ref link with single-quote title
    r := md.Process('[text][ref]'#10#10'[ref]: http://example.com ''Title''');
    Check(PosEx('href="http://example.com"', r) > 0, 'single-quote ref href');
    Check(PosEx('title="Title"', r) > 0, 'single-quote ref title');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ImagesAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('![alt](img.png)');
    Check(PosEx('<img', r) > 0, 'img no title');
    Check(PosEx('src="img.png"', r) > 0, 'img no title src');
    r := md.Process('![](img.png)');
    Check(PosEx('<img', r) > 0, 'img empty alt');
    Check(PosEx('src="img.png"', r) > 0, 'img empty alt src');
    r := md.Process('Before ![alt](img.png) after');
    Check(PosEx('<img', r) > 0, 'img inline');
    Check(PosEx('Before', r) > 0, 'img before');
    Check(PosEx('after', r) > 0, 'img after');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.AutoLinks;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('<http://example.com>');
    Check(PosEx('href="http://example.com"', r) > 0, 'http autolink');
    Check(PosEx('>http://example.com</a>', r) > 0, 'http autolink text');
    r := md.Process('<https://example.com>');
    Check(PosEx('href="https://example.com"', r) > 0, 'https autolink');
    // email autolink (obfuscated)
    r := md.Process('<user@example.com>');
    Check(PosEx('<a', r) > 0, 'email autolink a tag');
    Check(PosEx('href="', r) > 0, 'email autolink href');
    Check(PosEx('</a>', r) > 0, 'email autolink closes');
    // plain email not auto-linked
    r := md.Process('user@example.org');
    Check(PosEx('<a', r) = 0, 'bare email not linked');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.EscapedCharactersAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('\# not a heading');
    Check(PosEx('<h1>', r) = 0, 'escaped hash no heading');
    Check(PosEx('# not a heading', r) > 0, 'escaped hash literal');
    r := md.Process('\`not code\`');
    Check(PosEx('<code>', r) = 0, 'escaped backtick no code');
    r := md.Process('\_not italic\_');
    Check(PosEx('<em>', r) = 0, 'escaped underscore no em');
    r := md.Process('a \| b');
    Check(PosEx('|', r) > 0, 'escaped pipe literal');
    // backslash inside code span is literal
    r := md.Process('`\*`');
    Check(PosEx('<code>', r) > 0, 'code with backslash');
    Check(PosEx('\*', r) > 0, 'backslash literal in code');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.NestedConstructs;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('> * item 1'#10'> * item 2');
    Check(PosEx('<blockquote>', r) > 0, 'bq list blockquote');
    Check(PosEx('<ul>', r) > 0, 'bq list ul');
    Check(PosEx('item 1', r) > 0, 'bq list item 1');
    r := md.Process('# Title'#10#10'* item 1'#10'* item 2');
    Check(PosEx('<h1>', r) > 0, 'heading then list h1');
    Check(PosEx('<ul>', r) > 0, 'heading then list ul');
    r := md.Process('Before'#10#10'---'#10#10'After');
    Check(PosEx('<p>Before</p>', r) > 0, 'p-hr-p before');
    Check(PosEx('<hr />', r) > 0, 'p-hr-p hr');
    Check(PosEx('<p>After</p>', r) > 0, 'p-hr-p after');
    r := md.Process('~~**bold strike**~~');
    Check(PosEx('<del>', r) > 0, 'bold strike del');
    Check(PosEx('<strong>', r) > 0, 'bold strike strong');
    r := md.Process('*[link](http://example.com)*');
    Check(PosEx('<em>', r) > 0, 'link in em');
    Check(PosEx('href="http://example.com"', r) > 0, 'link in em href');
    r := md.Process('[![img](pic.png)](http://example.com)');
    Check(PosEx('<a ', r) > 0, 'img in link a');
    Check(PosEx('<img', r) > 0, 'img in link img');
    Check(PosEx('href="http://example.com"', r) > 0, 'img in link href');
  finally
    md.Free;
  end;
end;

// ===== TABLES & ENTITIES =====

procedure TTestMarkdown.TablesAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // alignment
    r := md.Process(
      '| Left | Center | Right |'#10 +
      '| :--- | :---: | ---: |'#10 +
      '| L | C | R |');
    Check(PosEx('align="left"', r) > 0, 'left align');
    Check(PosEx('align="center"', r) > 0, 'center align');
    Check(PosEx('align="right"', r) > 0, 'right align');
    // inline formatting in cells
    r := md.Process(
      '| H1 | H2 |'#10 +
      '| --- | --- |'#10 +
      '| **bold** | *italic* |');
    Check(PosEx('<strong>bold</strong>', r) > 0, 'bold in cell');
    Check(PosEx('<em>italic</em>', r) > 0, 'italic in cell');
    // code in cells
    r := md.Process(
      '| H1 | H2 |'#10 +
      '| --- | --- |'#10 +
      '| `code` | text |');
    Check(PosEx('<code>code</code>', r) > 0, 'code in cell');
    // link in cell
    r := md.Process(
      '| H1 |'#10 +
      '| --- |'#10 +
      '| [link](http://example.com) |');
    Check(PosEx('href="http://example.com"', r) > 0, 'link in cell');
    // multiple data rows
    r := md.Process(
      '| H1 | H2 |'#10 +
      '| --- | --- |'#10 +
      '| A1 | A2 |'#10 +
      '| B1 | B2 |'#10 +
      '| C1 | C2 |');
    Check(PosEx('A1', r) > 0, 'multi-row A1');
    Check(PosEx('C2', r) > 0, 'multi-row C2');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.EntitiesAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('&lt;', md.Process('&lt;')) > 0, '&lt; entity');
    Check(PosEx('&gt;', md.Process('&gt;')) > 0, '&gt; entity');
    Check(PosEx('&nbsp;', md.Process('&nbsp;')) > 0, '&nbsp; entity');
    Check(PosEx('&euro;', md.Process('&euro;')) > 0, '&euro; entity');
    Check(PosEx('&mdash;', md.Process('&mdash;')) > 0, '&mdash; entity');
    r := md.Process('&#65;');
    Check(PosEx('&#65;', r) > 0, 'decimal entity &#65;');
    r := md.Process('&#x41;');
    Check(PosEx('&#x41;', r) > 0, 'hex entity &#x41;');
    r := md.Process('Copyright &copy; 2024');
    Check(PosEx('&copy;', r) > 0, 'entity in para');
    Check(PosEx('Copyright', r) > 0, 'text before entity');
    Check(PosEx('2024', r) > 0, 'text after entity');
    r := md.Process('&unknown;');
    Check(PosEx('&amp;unknown;', r) > 0, 'unknown entity escaped');
  finally
    md.Free;
  end;
end;

// ===== SAFE MODE & STRESS =====

procedure TTestMarkdown.SafeModeAdvanced;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    md.SafeMode := true;
    r := md.Process('<iframe src="evil.html"></iframe>');
    Check(PosEx('<iframe', r) = 0, 'iframe blocked');
    r := md.Process('<object data="evil.swf"></object>');
    Check(PosEx('<object', r) = 0, 'object blocked');
    r := md.Process('<body>content</body>');
    Check(PosEx('<body>', r) = 0, 'body blocked');
    r := md.Process('<html><head></head></html>');
    Check(PosEx('<html>', r) = 0, 'html blocked');
    Check(PosEx('<head>', r) = 0, 'head blocked');
    r := md.Process('<applet>x</applet>');
    Check(PosEx('<applet', r) = 0, 'applet blocked');
    r := md.Process('<span>hello</span>');
    Check(PosEx('<span>hello</span>', r) > 0, 'span allowed');
    r := md.Process('```'#10'<script>alert(1)</script>'#10'```');
    Check(PosEx('<script>', r) = 0, 'fenced code script escaped');
    r := md.Process('    <script>bad</script>');
    Check(PosEx('<script>', r) = 0, 'indented code script escaped');
    md.SafeMode := false;
    r := md.Process('<script>alert(1)</script>');
    Check(PosEx('<script>', r) > 0, 'unsafe: script passes');
    r := md.Process('<iframe src="x"></iframe>');
    Check(PosEx('<iframe', r) > 0, 'unsafe: iframe passes');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.StressTests;
var
  md: TMarkdownProcessor;
  r, big: RawUtf8;
  i: integer;
  t0: Int64;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // deeply nested blockquotes
    big := '';
    for i := 1 to 50 do
      big := big + '> ';
    big := big + 'deep';
    r := md.Process(big);
    Check(length(r) > 0, 'deep bq output');
    Check(PosEx('<blockquote>', r) > 0, 'deep bq tag');
    Check(PosEx('deep', r) > 0, 'deep bq content');
    // very long line
    big := '';
    for i := 1 to 16384 do
      Append(big, 'a');
    t0 := GetTickCount64;
    r := md.Process(big);
    Check(GetTickCount64 - t0 < 5000, 'long line within 5s');
    Check(PosEx('<p>', r) > 0, 'long line para');
    // large document
    big := '';
    for i := 1 to 1000 do
      Append(big, RawUtf8('Para ' + UInt32ToUtf8(i) + #10#10));
    t0 := GetTickCount64;
    r := md.Process(big);
    Check(GetTickCount64 - t0 < 10000, 'large doc within 10s');
    Check(PosEx('<p>Para 1</p>', r) > 0, 'large doc first');
    Check(PosEx('<p>Para 1000</p>', r) > 0, 'large doc last');
    // wide table
    big := '|';
    for i := 1 to 32 do
      Append(big, RawUtf8(' H' + UInt32ToUtf8(i) + ' |'));
    Append(big, #10'|');
    for i := 1 to 32 do
      Append(big, ' --- |');
    Append(big, #10'|');
    for i := 1 to 32 do
      Append(big, RawUtf8(' D' + UInt32ToUtf8(i) + ' |'));
    r := md.Process(big);
    Check(PosEx('<table>', r) > 0, 'wide table tag');
    Check(PosEx('H32', r) > 0, 'wide table H32');
    Check(PosEx('D32', r) > 0, 'wide table D32');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.MalformedInput;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('line1'#13'line2');
    Check(length(r) > 0, 'bare CR produces output');
    r := md.Process('*unclosed emphasis');
    Check(length(r) > 0, 'unclosed em output');
    r := md.Process('[unclosed link');
    Check(length(r) > 0, 'unclosed bracket output');
    r := md.Process('[text]()');
    Check(length(r) > 0, 'empty link URL output');
    r := md.Process('[[[nested]]]');
    Check(length(r) > 0, 'nested brackets output');
    r := md.Process('```'#10'no closing fence');
    Check(PosEx('<pre><code>', r) > 0, 'unclosed fence opens');
    r := md.Process('Heading'#10 + StringOfChar(AnsiChar('='), 1000));
    Check(PosEx('<h1>', r) > 0, 'long setext h1');
    r := md.Process(
      '| A | B | C |'#10 +
      '| --- | --- |'#10 +
      '| 1 | 2 | 3 | 4 |');
    Check(length(r) > 0, 'mismatched table cols');
    r := md.Process('Heading'#10'---');
    Check(PosEx('<h2>', r) > 0, 'setext h2 not hr');
    Check(PosEx('<hr', r) = 0, 'no spurious hr');
    r := md.Process('a');
    Check(PosEx('a', r) > 0, 'single char');
    r := md.Process('#');
    Check(length(r) > 0, 'lone hash');
    r := md.Process('>');
    Check(length(r) > 0, 'lone gt');
  finally
    md.Free;
  end;
end;

// ===== SPEC COMPLIANCE =====

procedure TTestMarkdown.ThematicBreakVariants;
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    Check(PosEx('<hr />', md.Process('- - -')) > 0, 'spaced dashes');
    Check(PosEx('<hr />', md.Process('*  *  *')) > 0, 'multi-space stars');
    Check(PosEx('<hr />', md.Process('_ _ _')) > 0, 'spaced underscores');
    Check(PosEx('<hr />', md.Process('-----')) > 0, 'five dashes');
    Check(PosEx('<hr />', md.Process('*****')) > 0, 'five stars');
    Check(PosEx('<hr />', md.Process('   ---')) > 0, 'indented rule');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.AtxHeadingEdgeCases;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // CM: no space = not heading
    r := md.Process('#NoSpace');
    Check(PosEx('<h1>', r) = 0, 'no space no h1');
    // 7 hashes clamp to h6
    r := md.Process('####### H7');
    Check(PosEx('<h6>', r) > 0, '7 hashes clamp h6');
    Check(PosEx('<h7>', r) = 0, 'no h7');
    // unequal closing hashes stripped
    CheckEqual(md.Process('## H2 ###'), '<h2>H2</h2>'#10, 'unequal closing');
    CheckEqual(md.Process('### H3 #'), '<h3>H3</h3>'#10, 'single closing');
    // leading spaces allowed
    r := md.Process('   ## Indented');
    Check(PosEx('<h2>', r) > 0, '3-space indent valid');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.SetextHeadingEdgeCases;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('Title'#10'=');
    Check(PosEx('<h1>', r) > 0, 'single = h1');
    r := md.Process('Title'#10'-');
    Check(PosEx('<h2>', r) > 0, 'single - h2');
    r := md.Process('Section'#10'========');
    Check(PosEx('<h1>', r) > 0, 'many = h1');
    r := md.Process('Section'#10'--------');
    Check(PosEx('<h2>', r) > 0, 'many - h2');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.IndentedCodePreservation;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('        deep');
    Check(PosEx('<pre><code>', r) > 0, '8-space code block');
    Check(PosEx('    deep', r) > 0, '4 spaces preserved');
    r := md.Process('    line1'#10#10'    line2');
    Check(PosEx('<pre><code>', r) > 0, 'blank in code block');
    Check(PosEx('line1', r) > 0, 'code line1');
    Check(PosEx('line2', r) > 0, 'code line2');
    r := md.Process('   not code');
    Check(PosEx('<pre>', r) = 0, '3 spaces not code');
    Check(PosEx('<p>', r) > 0, '3 spaces paragraph');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.FencedCodeFenceRules;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // backtick fence cannot be closed by tilde
    r := md.Process('```'#10'mixed'#10'~~~');
    Check(PosEx('mixed', r) > 0, 'unclosed backtick content');
    // HTML in fenced code escaped
    r := md.Process('```'#10'a < b && b > c'#10'```');
    Check(PosEx('&lt;', r) > 0, '< escaped in fenced');
    Check(PosEx('&gt;', r) > 0, '> escaped in fenced');
    // unclosed fence still opens
    r := md.Process('```'#10'no close');
    Check(PosEx('<pre><code>', r) > 0, 'unclosed fence opens');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ListLooseAndMarkers;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // tight list: no <p> around items
    r := md.Process('- alpha'#10'- beta'#10'- gamma');
    Check(PosEx('<ul>', r) > 0, 'tight ul');
    Check(PosEx('<p>', r) = 0, 'tight no p');
    Check(PosEx('alpha', r) > 0, 'tight alpha');
    // loose list: blank line between items wraps in <p>
    r := md.Process('- alpha'#10#10'- beta');
    Check(PosEx('<ul>', r) > 0, 'loose ul');
    Check(PosEx('<p>', r) > 0, 'loose has p');
    // ordered list
    r := md.Process('1. first'#10'2. second'#10'3. third');
    Check(PosEx('<ol>', r) > 0, 'ol');
    Check(PosEx('third', r) > 0, 'ol third');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.BackslashEscapeSet;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('\*not italic\*');
    Check(PosEx('<em>', r) = 0, 'esc star no em');
    Check(PosEx('*not italic*', r) > 0, 'esc star literal');
    r := md.Process('\_not italic\_');
    Check(PosEx('<em>', r) = 0, 'esc underscore no em');
    Check(PosEx('_not italic_', r) > 0, 'esc underscore literal');
    r := md.Process('\`not code\`');
    Check(PosEx('<code>', r) = 0, 'esc backtick no code');
    r := md.Process('\[not a link\](http://example.com)');
    Check(PosEx('<a', r) = 0, 'esc bracket no link');
    r := md.Process('\# not a heading');
    Check(PosEx('<h1>', r) = 0, 'esc hash no heading');
    r := md.Process('\\');
    Check(PosEx('\', r) > 0, 'esc backslash literal');
    r := md.Process('\|');
    Check(PosEx('|', r) > 0, 'esc pipe literal');
    // backslash inside code span is literal
    r := md.Process('`\*`');
    Check(PosEx('<code>', r) > 0, 'code with backslash');
    Check(PosEx('\*', r) > 0, 'backslash literal in code');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.CodeSpanHtmlEscape;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('`a < b && b > c`');
    Check(PosEx('&lt;', r) > 0, '< escaped in code span');
    Check(PosEx('&gt;', r) > 0, '> escaped in code span');
    Check(PosEx('&amp;', r) > 0, '& escaped in code span');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.HeadingIdStripping;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('## Section Title {#sec-2}');
    Check(PosEx('id="sec-2"', r) > 0, 'id attribute');
    Check(PosEx('{#sec-2}', r) = 0, 'raw id stripped');
    Check(PosEx('Section Title', r) > 0, 'heading text preserved');
    // setext heading with id
    r := md.Process('My Title {#sec-1}'#10'=================');
    Check(PosEx('id="sec-1"', r) > 0, 'setext id');
    Check(PosEx('My Title', r) > 0, 'setext text');
    Check(PosEx('<h1', r) > 0, 'setext h1');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.TabExpansion;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // tab at start = 4 spaces = code block
    r := md.Process(#9'tabbed code');
    Check(PosEx('<pre><code>', r) > 0, 'tab becomes code block');
    Check(PosEx('tabbed code', r) > 0, 'tab content');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.TxtMarkDialect;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdTxtMark);
  try
    r := md.Process('Hello');
    Check(PosEx('<p>Hello</p>', r) > 0, 'txtmark paragraph');
    r := md.Process('```'#10'code'#10'```');
    Check(PosEx('<pre><code>', r) > 0, 'txtmark fenced code');
    // smart typography (enabled in TxtMark)
    r := md.Process('(C)');
    Check(PosEx('&copy;', r) > 0, 'txtmark smart typography');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ConvenienceFunctionDialect;
var
  r: RawUtf8;
begin
  // DaringFireball no space after #
  r := MarkdownToHtml('#Title', mdDaringFireball);
  Check(PosEx('<h1>', r) > 0, 'convenience DF heading');
  r := MarkdownToHtml('~~strike~~', mdCommonMark);
  Check(PosEx('<del>', r) > 0, 'convenience CM strike');
end;

procedure TTestMarkdown.StrikethroughDialectScope;
var
  df, cm: TMarkdownProcessor;
  r: RawUtf8;
begin
  df := TMarkdownProcessor.Create(mdDaringFireball);
  cm := TMarkdownProcessor.Create(mdCommonMark);
  try
    // DaringFireball has no ~~strike~~
    r := df.Process('~~strike~~');
    Check(PosEx('<del>', r) = 0, 'DF no strikethrough');
    // CommonMark has it
    r := cm.Process('~~strike~~');
    Check(PosEx('<del>', r) > 0, 'CM has strikethrough');
  finally
    df.Free;
    cm.Free;
  end;
end;

procedure TTestMarkdown.TableEscapedPipes;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process(
      '| H1 | H2 |'#10 +
      '| --- | --- |'#10 +
      '| a\|b | c |');
    Check(PosEx('<table>', r) > 0, 'escaped pipe table');
    Check(PosEx('a|b', r) > 0, 'escaped pipe literal');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.SmartTypographyCaseSensitivity;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    // uppercase only: (C), (R), (TM)
    Check(PosEx('&copy;', md.Process('(C)')) > 0, '(C) upper');
    Check(PosEx('&reg;', md.Process('(R)')) > 0, '(R) upper');
    Check(PosEx('&trade;', md.Process('(TM)')) > 0, '(TM) upper');
    // lowercase should NOT produce smart typography
    r := md.Process('(c)');
    Check(PosEx('&copy;', r) = 0, '(c) lower no copy');
    r := md.Process('(r)');
    Check(PosEx('&reg;', r) = 0, '(r) lower no reg');
    r := md.Process('(tm)');
    Check(PosEx('&trade;', r) = 0, '(tm) lower no trade');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.ProfileExtended;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdDaringFireball);
  try
    // $profile$ extended enables extensions on DF dialect
    r := md.Process(
      '[$profile$]: extended'#10 +
      #10 +
      'a---b');
    Check(PosEx('&mdash;', r) > 0, 'mdash after $profile$ extended');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.FencedCodeNoLang;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('```'#10'plain'#10'```');
    Check(PosEx('<pre><code>', r) > 0, 'no-lang fenced opens');
    Check(PosEx('class=', r) = 0, 'no class without lang');
    Check(PosEx('plain', r) > 0, 'no-lang content');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.LinkAngleBracketUrl;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('[text](<http://example.com/a b>)');
    Check(PosEx('href="http://example.com/a b"', r) > 0, 'angle bracket URL spaces');
    Check(PosEx('>text</a>', r) > 0, 'angle bracket link text');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.GitHubDialect;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdGitHub);
  try
    // strikethrough works
    r := md.Process('~~strike~~');
    Check(PosEx('<del>', r) > 0, 'GFM strikethrough open');
    Check(PosEx('</del>', r) > 0, 'GFM strikethrough close');
    // tables work
    r := md.Process('| A | B |'#10'|---|---|'#10'| 1 | 2 |');
    Check(PosEx('<table>', r) > 0, 'GFM tables');
    // fenced code works
    r := md.Process('```pascal'#10'code'#10'```');
    Check(PosEx('<code', r) > 0, 'GFM fenced code');
    // bare URL autolinks
    r := md.Process('see https://example.com here');
    Check(PosEx('<a href="https://example.com">', r) > 0, 'GFM https autolink');
    Check(PosEx('>https://example.com</a>', r) > 0, 'GFM autolink text');
    r := md.Process('visit www.example.com today');
    Check(PosEx('<a href="http://www.example.com">', r) > 0, 'GFM www autolink prepends http');
    Check(PosEx('>www.example.com</a>', r) > 0, 'GFM www autolink text');
    // ATX headings require space after #
    r := md.Process('# H1');
    Check(PosEx('<h1>', r) > 0, 'GFM ATX with space');
    r := md.Process('#NoSpace');
    Check(PosEx('<h1>', r) = 0, 'GFM ATX requires space');
    // extended formatting NOT available (++ins++, ==mark==, ~sub~, $math$)
    CheckEqual(md.Process('++ins++'), '<p>++ins++</p>'#10, 'GFM no ins');
    CheckEqual(md.Process('==mark=='), '<p>==mark==</p>'#10, 'GFM no mark');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.TaskLists;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdGitHub);
  try
    // checked item
    r := md.Process('- [x] done');
    Check(PosEx('<input checked disabled type="checkbox">', r) > 0, 'checked item');
    // unchecked item
    r := md.Process('- [ ] pending');
    Check(PosEx('<input disabled type="checkbox">', r) > 0, 'unchecked item');
    // uppercase [X]
    r := md.Process('- [X] done');
    Check(PosEx('<input checked disabled type="checkbox">', r) > 0, 'uppercase X');
    // mixed list
    r := md.Process('- [x] done'#10'- [ ] pending'#10'- normal');
    Check(PosEx('checked', r) > 0, 'mixed list checked');
    Check(PosEx('<input disabled type="checkbox"> pending', r) > 0, 'mixed list unchecked');
    Check(PosEx('normal', r) > 0, 'mixed list normal');
    // ordered list with task items
    r := md.Process('1. [x] ordered done'#10'2. [ ] ordered todo');
    Check(PosEx('<input checked disabled type="checkbox">', r) > 0, 'ordered checked');
    Check(PosEx('<input disabled type="checkbox">', r) > 0, 'ordered unchecked');
    // invalid markers should NOT produce checkboxes
    r := md.Process('- [v] not a task');
    Check(PosEx('checkbox', r) = 0, 'invalid marker [v]');
    r := md.Process('- [x]no space after');
    Check(PosEx('checkbox', r) = 0, 'no space after ]');
    // DaringFireball should NOT produce checkboxes
    md.Free;
    md := TMarkdownProcessor.Create(mdDaringFireball);
    r := md.Process('- [x] done');
    Check(PosEx('checkbox', r) = 0, 'DF no task lists');
  finally
    md.Free;
  end;
  // also works with CommonMark
  md := TMarkdownProcessor.Create(mdCommonMark);
  try
    r := md.Process('- [x] done');
    Check(PosEx('<input checked disabled type="checkbox">', r) > 0, 'CM checked item');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.GfmStrikethrough;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdGitHub);
  try
    // multi-word strikethrough
    r := md.Process('~~foo bar baz~~');
    Check(PosEx('<del>foo bar baz</del>', r) > 0, 'multi-word strike');
    // single tilde does NOT strikethrough in GFM
    r := md.Process('~text~');
    Check(PosEx('<del>', r) = 0, 'single tilde no strike');
    Check(PosEx('<sub>', r) = 0, 'single tilde no sub in GFM');
    // unmatched opening ~~
    r := md.Process('~~no close');
    Check(PosEx('<del>', r) = 0, 'unmatched opening ~~');
    // adjacent strikethroughs
    r := md.Process('~~one~~ and ~~two~~');
    Check(PosEx('<del>one</del>', r) > 0, 'adjacent strike 1');
    Check(PosEx('<del>two</del>', r) > 0, 'adjacent strike 2');
    // strikethrough inside emphasis
    r := md.Process('*~~text~~*');
    Check(PosEx('<em><del>text</del></em>', r) > 0, 'strike inside em');
    // emphasis inside strikethrough
    r := md.Process('~~**bold**~~');
    Check(PosEx('<del><strong>bold</strong></del>', r) > 0, 'bold inside strike');
    // escaped tilde
    r := md.Process('\~~not struck~~');
    Check(PosEx('<del>', r) = 0, 'escaped tilde');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.GfmAutolinks;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdGitHub);
  try
    // basic https
    r := md.Process('see https://example.com here');
    Check(PosEx('<a href="https://example.com">https://example.com</a>', r) > 0,
      'basic https autolink');
    // basic http
    r := md.Process('see http://example.com here');
    Check(PosEx('<a href="http://example.com">http://example.com</a>', r) > 0,
      'basic http autolink');
    // www prepends http://
    r := md.Process('visit www.example.com now');
    Check(PosEx('<a href="http://www.example.com">www.example.com</a>', r) > 0,
      'www prepends http');
    // trailing period stripped
    r := md.Process('see https://example.com.');
    Check(PosEx('href="https://example.com"', r) > 0, 'trailing period stripped');
    // trailing comma stripped
    r := md.Process('see https://example.com, please');
    Check(PosEx('href="https://example.com"', r) > 0, 'trailing comma stripped');
    // preceded by word char: NO autolink
    r := md.Process('foohttps://example.com');
    Check(PosEx('<a ', r) = 0, 'word char before https blocks');
    r := md.Process('xwww.example.com');
    Check(PosEx('<a ', r) = 0, 'word char before www blocks');
    // preceded by punctuation: autolink
    r := md.Process('(https://example.com)');
    Check(PosEx('href="https://example.com"', r) > 0, 'paren before URL ok');
    // parenthesis balancing: URL with balanced parens
    r := md.Process('see https://en.wikipedia.org/wiki/Foo_(bar) end');
    Check(PosEx('href="https://en.wikipedia.org/wiki/Foo_(bar)"', r) > 0,
      'balanced parens included');
    // parenthesis balancing: URL in parens
    r := md.Process('(https://example.com/path)');
    Check(PosEx('href="https://example.com/path"', r) > 0,
      'outer parens not part of URL');
    // < terminates URL
    r := md.Process('https://example.com<br>');
    Check(PosEx('href="https://example.com"', r) > 0, '< terminates URL');
    // autolink should NOT trigger inside code span
    r := md.Process('`https://example.com`');
    Check(PosEx('<a ', r) = 0, 'no autolink in code span');
    // URL at start of line
    r := md.Process('https://example.com is great');
    Check(PosEx('<a href="https://example.com"', r) > 0, 'URL at line start');
    // URL with path
    r := md.Process('see https://example.com/path/to/page here');
    Check(PosEx('href="https://example.com/path/to/page"', r) > 0, 'URL with path');
  finally
    md.Free;
  end;
end;

procedure TTestMarkdown.GfmTables;
var
  md: TMarkdownProcessor;
  r: RawUtf8;
begin
  md := TMarkdownProcessor.Create(mdGitHub);
  try
    // basic table has thead/tbody
    r := md.Process('| A | B |'#10'|---|---|'#10'| 1 | 2 |');
    Check(PosEx('<thead>', r) > 0, 'thead present');
    Check(PosEx('</thead>', r) > 0, 'thead closed');
    Check(PosEx('<tbody>', r) > 0, 'tbody present');
    Check(PosEx('</tbody>', r) > 0, 'tbody closed');
    Check(PosEx('<th', r) > 0, 'th in header');
    Check(PosEx('<td', r) > 0, 'td in body');
    // column alignment
    r := md.Process('| L | C | R |'#10'|:---|:---:|---:|'#10'| a | b | c |');
    Check(PosEx('align="left"', r) > 0, 'left align');
    Check(PosEx('align="center"', r) > 0, 'center align');
    Check(PosEx('align="right"', r) > 0, 'right align');
    // fewer columns in data row: padded with empty td
    r := md.Process('| A | B | C |'#10'|---|---|---|'#10'| 1 | 2 |');
    Check(PosEx('<td></td>', r) > 0, 'fewer cols padded');
    // more columns in data row: excess truncated
    r := md.Process('| A | B |'#10'|---|---|'#10'| 1 | 2 | 3 | 4 |');
    Check(PosEx('>3<', r) = 0, 'excess cols truncated');
    Check(PosEx('>4<', r) = 0, 'excess cols truncated 2');
    // empty cells
    r := md.Process('| A | B |'#10'|---|---|'#10'| | x |');
    Check(PosEx('<td>', r) > 0, 'empty cell');
    Check(PosEx('>x<', r) > 0, 'non-empty cell');
    // inline formatting in cells
    r := md.Process('| A |'#10'|---|'#10'| **bold** |');
    Check(PosEx('<strong>bold</strong>', r) > 0, 'bold in cell');
  finally
    md.Free;
  end;
end;

end.

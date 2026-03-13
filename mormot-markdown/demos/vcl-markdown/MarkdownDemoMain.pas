unit MarkdownDemoMain;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.OleCtrls,
  SHDocVw,
  mormot.core.base,
  mormot.core.unicode,
  mormot.ext.markdown;

type
  TFormMarkdownDemo = class(TForm)
    PanelLeft: TPanel;
    PanelRight: TPanel;
    Splitter: TSplitter;
    MemoMarkdown: TMemo;
    WebBrowser: TWebBrowser;
    PanelTop: TPanel;
    BtnConvert: TButton;
    ComboDialect: TComboBox;
    CheckSafe: TCheckBox;
    LabelDialect: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure BtnConvertClick(Sender: TObject);
  end;

var
  FormMarkdownDemo: TFormMarkdownDemo;

implementation

{$R *.dfm}

const
  SAMPLE_MARKDOWN =
    '# mormot.ext.markdown Demo' + #13#10 +
    '' + #13#10 +
    'This is a **live preview** of the markdown processor.' + #13#10 +
    '' + #13#10 +
    ' ![](./mormotsaurus.png)' + #13#10 +
    '## Features' + #13#10 +
    '' + #13#10 +
    '- *Italic*, **bold**, ~~strikethrough~~' + #13#10 +
    '- [Links](https://github.com/synopse/mORMot2)' + #13#10 +
    '- `inline code`' + #13#10 +
    '- Tables, fenced code blocks, and more' + #13#10 +
    '' + #13#10 +
    '## Code example' + #13#10 +
    '' + #13#10 +
    '```pascal' + #13#10 +
    'html := MarkdownToHtml(''# Hello'');' + #13#10 +
    '```' + #13#10 +
    '' + #13#10 +
    '## Table' + #13#10 +
    '' + #13#10 +
    '| Dialect | Description |' + #13#10 +
    '|---------|-------------|' + #13#10 +
    '| DaringFireball | Original spec |' + #13#10 +
    '| TxtMark | Extended |' + #13#10 +
    '| CommonMark | Modern standard |' + #13#10 +
    '| GitHub | GFM extensions |' + #13#10 +
    '' + #13#10 +
    '> Blockquote: enjoy!' + #13#10 +
    '' + #13#10 +
    '## GFM Extensions (select GitHub dialect)' + #13#10 +
    '' + #13#10 +
    '### Task Lists' + #13#10 +
    '' + #13#10 +
    '- [x] Strikethrough support' + #13#10 +
    '- [x] Tables support' + #13#10 +
    '- [x] Task lists' + #13#10 +
    '- [ ] Bare URL autolinks' + #13#10 +
    '- [ ] World domination' + #13#10 +
    '' + #13#10 +
    '### Bare URL Autolinks' + #13#10 +
    '' + #13#10 +
    'Visit https://synopse.info or www.freepascal.org for more info.' + #13#10 +
    '' + #13#10 +
    '### Strikethrough' + #13#10 +
    '' + #13#10 +
    'This is ~~no longer relevant~~ still important.' + #13#10;

procedure TFormMarkdownDemo.FormCreate(Sender: TObject);
begin
  MemoMarkdown.Text := SAMPLE_MARKDOWN;
  ComboDialect.Items.Add('CommonMark');
  ComboDialect.Items.Add('Daring Fireball');
  ComboDialect.Items.Add('TxtMark');
  ComboDialect.Items.Add('GitHub (GFM)');
  ComboDialect.ItemIndex := 3;
  // trigger initial render
  BtnConvertClick(nil);
end;

procedure TFormMarkdownDemo.BtnConvertClick(Sender: TObject);
const
  DIALECTS: array[0..3] of TMarkdownDialect = (
    mdCommonMark, mdDaringFireball, mdTxtMark, mdGitHub);
  HTML_HEAD: RawUtf8 =
    '<html><head><meta charset="utf-8">' +
    '<style>' +
    'body { font-family: Segoe UI, sans-serif; margin: 16px; line-height: 1.5; color: #333; }' +
    'h1, h2, h3 { color: #1a1a1a; }' +
    'code { background: #f0f0f0; padding: 2px 5px; border-radius: 3px; font-size: 90%; }' +
    'pre { background: #f6f6f6; padding: 12px; border-radius: 5px; overflow-x: auto; }' +
    'pre code { background: none; padding: 0; }' +
    'blockquote { border-left: 4px solid #ddd; margin: 0; padding: 8px 16px; color: #666; }' +
    'table { border-collapse: collapse; }' +
    'th, td { border: 1px solid #ddd; padding: 6px 12px; }' +
    'th { background: #f0f0f0; }' +
    'a { color: #0366d6; }' +
    'del { color: #999; }' +
    'input[type="checkbox"] { margin-right: 6px; }' +
    'li:has(> input[type="checkbox"]) { list-style: none; margin-left: -20px; }' +
    '</style>' +
    '</head><body>';
  HTML_TAIL: RawUtf8 = '</body></html>';
var
  md: TMarkdownProcessor;
  html, page: RawUtf8;
  doc: Variant;
  idx: integer;
begin
  idx := ComboDialect.ItemIndex;
  if idx < 0 then
    idx := 0;
  md := TMarkdownProcessor.Create(DIALECTS[idx]);
  try
    md.SafeMode := CheckSafe.Checked;
    html := md.Process(StringToUtf8(MemoMarkdown.Text));
  finally
    md.Free;
  end;
  page := HTML_HEAD + html + HTML_TAIL;
  // render in WebBrowser
  WebBrowser.Navigate('about:blank');
  while WebBrowser.ReadyState < READYSTATE_INTERACTIVE do
    Application.ProcessMessages;
  doc := WebBrowser.Document;
  doc.open;
  doc.write(Utf8ToString(page));
  doc.close;
end;

end.

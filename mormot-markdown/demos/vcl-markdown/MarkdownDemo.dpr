program MarkdownDemo;

uses
  Vcl.Forms,
  mormot.ext.markdown in '..\..\src\mormot.ext.markdown.pas',
  MarkdownDemoMain in 'MarkdownDemoMain.pas' {FormMarkdownDemo};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFormMarkdownDemo, FormMarkdownDemo);
  Application.Run;
end.

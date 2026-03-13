program mormot.ext.markdown.tests;

{$I mormot.defines.inc}

{$ifdef OSWINDOWS}
  {$APPTYPE CONSOLE}
{$endif OSWINDOWS}

uses
  {$I mormot.uses.inc}
  sysutils,
  mormot.core.base,
  mormot.core.log,
  mormot.core.test,
  mormot.ext.markdown.test;

begin
  TTestMarkdownSuite.RunAsConsole('mormot.ext.markdown Tests', LOG_VERBOSE);
end.

program OtpTests;

{$I mormot.defines.inc}

{$ifdef OSWINDOWS}
  {$APPTYPE CONSOLE}
{$endif OSWINDOWS}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.log,
  mormot.core.test,
  mormot.ext.otp in '..\mormot.ext.otp.pas',
  otp.tests in 'otp.tests.pas';
  
begin
  // Run all OTP tests
  TOtpTests.RunAsConsole('mORMot OTP Extension - Tests', LOG_VERBOSE);
end.

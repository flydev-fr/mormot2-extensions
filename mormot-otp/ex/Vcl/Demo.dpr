program Demo;

uses
  Vcl.Forms,
  Form in 'Form.pas' {FormOTP},
  mormot.ext.otp;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'OTP Clean Architecture Example';
  Application.CreateForm(TFormOTP, FormOTP);
  Application.Run;
end.

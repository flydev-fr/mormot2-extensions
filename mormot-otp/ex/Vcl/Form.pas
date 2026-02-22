unit Form;

{$I mormot.defines.inc}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Clipbrd, Vcl.Graphics,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.buffers,
  mormot.ext.otp;

type
  TFormOTP = class(TForm)
    GrpSecret: TGroupBox;
    LblKey: TLabel;
    EdtKey: TEdit;
    BtnNewKey: TButton;
    LblUrl: TLabel;
    EdtOtpUrl: TEdit;
    BtnCopyUrl: TButton;
    GrpTOTP: TGroupBox;
    LblTOTPCaption: TLabel;
    LblTOTPCode: TLabel;
    LblTimeCaption: TLabel;
    PrgTime: TProgressBar;
    LblTimeRemaining: TLabel;
    GrpHOTP: TGroupBox;
    LblCounterCaption: TLabel;
    EdtCounter: TEdit;
    BtnCalcHOTP: TButton;
    LblHOTPCaption: TLabel;
    EdtHOTPResult: TEdit;
    GrpValidate: TGroupBox;
    LblTokenCaption: TLabel;
    EdtValidToken: TEdit;
    BtnValidate: TButton;
    LblValidResult: TLabel;
    Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure EdtKeyChange(Sender: TObject);
    procedure BtnNewKeyClick(Sender: TObject);
    procedure BtnCopyUrlClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure BtnCalcHOTPClick(Sender: TObject);
    procedure BtnValidateClick(Sender: TObject);
  private
    fOtpProvider: IOtpProvider;
    fSecretGenerator: ISecretGenerator;
    procedure UpdateOtpUrl;
    procedure UpdateTOTP;
  end;

var
  FormOTP: TFormOTP;

implementation

{$R *.dfm}

const
  OTP_ISSUER  = 'mORMot';
  OTP_ACCOUNT = 'user';

{ TFormOTP }

procedure TFormOTP.FormCreate(Sender: TObject);
begin
  fOtpProvider    := TOtpFactory.CreateDefault;
  fSecretGenerator := TOtpFactory.CreateSecretGenerator;
  UpdateOtpUrl;
  Timer1Timer(nil); // immediate first refresh
end;

procedure TFormOTP.FormDestroy(Sender: TObject);
begin
  fOtpProvider    := nil;
  fSecretGenerator := nil;
end;

procedure TFormOTP.UpdateOtpUrl;
var
  Secret: string;
begin
  Secret := Trim(EdtKey.Text);
  if Secret = '' then
    EdtOtpUrl.Text := ''
  else
    EdtOtpUrl.Text :=
      'otpauth://totp/' + OTP_ISSUER + ':' + OTP_ACCOUNT +
      '?secret='  + Secret +
      '&issuer='  + OTP_ISSUER +
      '&digits=6&period=30';
end;

procedure TFormOTP.UpdateTOTP;
var
  Secret: RawUtf8;
  Code, Remaining: Integer;
begin
  Remaining := 30 - Integer(UnixTimeUtc mod 30);
  PrgTime.Position := Remaining;
  LblTimeRemaining.Caption := IntToStr(Remaining) + ' s';

  Secret := StringToUtf8(Trim(EdtKey.Text));
  if Secret = '' then
  begin
    LblTOTPCode.Caption    := '------';
    LblTOTPCode.Font.Color := clGray;
    Exit;
  end;

  try
    Code := fOtpProvider.ComputeTOTP(Secret, 6, 30);
    LblTOTPCode.Caption := Format('%.6d', [Code]);
    if Remaining <= 5 then
      LblTOTPCode.Font.Color := clRed
    else
      LblTOTPCode.Font.Color := clNavy;
  except
    LblTOTPCode.Caption    := 'Error';
    LblTOTPCode.Font.Color := clRed;
  end;
end;

procedure TFormOTP.EdtKeyChange(Sender: TObject);
begin
  UpdateOtpUrl;
  UpdateTOTP;
  // clear stale results from other sections
  LblValidResult.Caption := '';
  EdtHOTPResult.Text     := '';
end;

procedure TFormOTP.BtnNewKeyClick(Sender: TObject);
begin
  // 32 Base32 chars = 20 bytes = 160-bit key; triggers EdtKeyChange automatically
  EdtKey.Text := string(fSecretGenerator.GenerateSecret(32));
end;

procedure TFormOTP.BtnCopyUrlClick(Sender: TObject);
begin
  if EdtOtpUrl.Text <> '' then
  begin
    Clipboard.AsText := EdtOtpUrl.Text;
    EdtOtpUrl.SelectAll;
    EdtOtpUrl.SetFocus;
  end;
end;

procedure TFormOTP.Timer1Timer(Sender: TObject);
begin
  UpdateTOTP;
end;

procedure TFormOTP.BtnCalcHOTPClick(Sender: TObject);
var
  Secret: RawUtf8;
  SecretBin: RawByteString;
  Counter: Int64;
  Code: Integer;
begin
  Secret := StringToUtf8(Trim(EdtKey.Text));
  if Secret = '' then
  begin
    EdtHOTPResult.Text := 'No key';
    Exit;
  end;
  SecretBin := Base32ToBin(Secret);
  if SecretBin = '' then
  begin
    EdtHOTPResult.Text := 'Bad Base32';
    Exit;
  end;
  if not TryStrToInt64(EdtCounter.Text, Counter) then
    Counter := 0;
  Code := fOtpProvider.ComputeOTP(SecretBin, Counter, 6);
  EdtHOTPResult.Text := Format('%.6d', [Code]);
end;

procedure TFormOTP.BtnValidateClick(Sender: TObject);
var
  Secret: RawUtf8;
  Token: Integer;
begin
  Secret := StringToUtf8(Trim(EdtKey.Text));
  if Secret = '' then
  begin
    LblValidResult.Caption    := 'No secret key entered.';
    LblValidResult.Font.Color := clGray;
    Exit;
  end;
  if Trim(EdtValidToken.Text) = '' then
  begin
    LblValidResult.Caption    := 'Enter a token to validate.';
    LblValidResult.Font.Color := clGray;
    Exit;
  end;
  if not TryStrToInt(Trim(EdtValidToken.Text), Token) then
  begin
    LblValidResult.Caption    := 'Token must be a number.';
    LblValidResult.Font.Color := clGray;
    Exit;
  end;

  if fOtpProvider.ValidateTOTP(Secret, Token, 1) then
  begin
    LblValidResult.Caption    := #$2713 + ' Valid — authentication successful';
    LblValidResult.Font.Color := clGreen;
  end
  else
  begin
    LblValidResult.Caption    := #$2717 + ' Invalid — token does not match';
    LblValidResult.Font.Color := clRed;
  end;
end;

end.

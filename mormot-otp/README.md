# mormot-ext-otp

RFC 4226/6238-compatible HOTP/TOTP unit (HMAC-SHA1 profile).

## Quick Start
1. Add `mormot.ext.otp` to your `uses`.
2. Generate a secret at enrollment, then verify the codes typed by the user.

```pascal
uses
  mormot.core.base,
  mormot.core.os,
  mormot.core.buffers,
  mormot.ext.otp;

var
  Otp: IOtpProvider;
  Gen: ISecretGenerator;
  Secret: RawUtf8;
  SecretBin: RawByteString;
  Uri: RawUtf8;
  MatchedStep: Int64;
begin
  Otp := TOtpFactory.CreateDefault;
  Gen := TOtpFactory.CreateSecretGenerator;

  // enrollment: 32 Base32 chars = 160 bits from the TAesPrng CSPRNG
  Secret := Gen.GenerateSecret(32);
  Uri := BuildOtpAuthUri('MyApp', 'alice@example.com', Secret); // for the QR code

  // authentication: Code is the text typed by the user, e.g. '081804'
  SecretBin := Base32ToBin(Secret);
  if Otp.VerifyTOTPStep(SecretBin, Code, UnixTimeUtc, 1, 1, MatchedStep) and
     (MatchedStep > User.LastOtpStep) then
  begin
    User.LastOtpStep := MatchedStep; // persist it: a code can not be replayed
    // valid
  end;
  FillZero(SecretBin);
end;
```

## API notes
- `VerifyTOTPStep` is the function to use for authentication: it takes the code
  as text (exactly *Digits* ASCII digits, so leading zeros are enforced), bounds
  the window to `OTP_MAX_WINDOW_STEPS` steps in each direction, evaluates every
  step without early exit, and returns the matched time step so the caller can
  refuse replays.
- `ParseOtpCode` / `FormatOtpCode` convert between the typed code and its value.
- `BuildOtpAuthUri` percent-encodes the issuer and account, so a user-supplied
  account name can not inject parameters into the `otpauth://` URI.
- `ComputeOTP` / `ComputeTOTP` return `-1` on any failure (invalid digits or
  interval, undecodable secret, unusable HMAC). They never return `0` as a
  failure value, since `000000` is a valid code.
- `ValidateTOTP` is kept for compatibility. Its Boolean result can not prevent
  replay and its Integer token can not enforce leading zeros; it refuses windows
  outside `0..OTP_MAX_WINDOW_STEPS`.
- `GenerateSecret` never returns less than 32 Base32 characters (160 bits).

## Demos
- VCL demo (fastest to inspect): `ex/Vcl/Form.pas`
- MVC server demo: `ex/MvcServer/otp.mvc.pas`
- Interface service demo: `ex/InterfaceService/otp.api.impl.pas`


## Preview

![VCL Demo](https://github.com/user-attachments/assets/d1b70179-45bd-480e-a1e2-276d0b6e5c5f)
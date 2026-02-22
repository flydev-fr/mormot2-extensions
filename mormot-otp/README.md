# mormot-ext-otp

RFC 4226/6238-compatible HOTP/TOTP unit (HMAC-SHA1 profile).

## Quick Start
1. Add `mormot.ext.otp` to your `uses`.
2. Create a provider and generate/validate codes.

```pascal
uses
  mormot.core.base,
  mormot.ext.otp;

var
  Otp: IOtpProvider;
  Gen: ISecretGenerator;
  Secret: RawUtf8;
  Code: Integer;
begin
  Otp := TOtpFactory.CreateDefault;
  Gen := TOtpFactory.CreateSecretGenerator;

  Secret := Gen.GenerateSecret(32);
  Code := Otp.ComputeTOTP(Secret, 6, 30);

  if Otp.ValidateTOTP(Secret, Code, 1) then
    ; // valid
end;
```

## Demos
- VCL demo (fastest to inspect): `ex/Vcl/Form.pas`
- MVC server demo: `ex/MvcServer/otp.mvc.pas`
- Interface service demo: `ex/InterfaceService/otp.api.impl.pas`

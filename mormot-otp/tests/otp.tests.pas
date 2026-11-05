unit otp.tests;

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.text,
  mormot.core.test,
  mormot.core.buffers,
  mormot.crypt.core,
  mormot.crypt.secure,
  mormot.ext.otp;

type
  TOtpTests = class(TSynTestsLogged)
  published
    procedure Infrastructure;
    procedure ComputeOtp;
    procedure ComputeTotp;
    procedure ValidateTotp;
    procedure VerifyTotpStep;
    procedure ParseCode;
    procedure OtpAuthUri;
    procedure Factory;
  end;

  TOtpInfrastructureTests = class(TSynTestCase)
  published
    procedure TimeProvider_ReturnsFixedUnixTime;
    procedure SecretGenerator_RespectsLengthRules;
    procedure SecretGenerator_UsesOnlyBase32Alphabet;
    procedure SecretGenerator_DecodesToExpectedByteCount;
    procedure SecretGenerator_SuccessiveSecretsDiffer;
  end;

  TOtpComputeOtpTests = class(TSynTestCase)
  published
    procedure ComputeOtp_Rfc4226_TestVectors_6Digits;
    procedure ComputeOtp_DigitsOutOfRange_ReturnsMinusOne;
    procedure ComputeOtp_ShortHash_ReturnsMinusOne;
    procedure ComputeOtp_DynamicTruncation_OffsetBoundary0;
    procedure ComputeOtp_DynamicTruncation_OffsetBoundary15;
    procedure ComputeOtp_DeterministicForSameInputs;
  end;

  TOtpComputeTotpTests = class(TSynTestCase)
  published
    procedure ComputeTotp_Rfc6238_8DigitVectors;
    procedure ComputeTotp_NonPositiveInterval_ReturnsMinusOne;
    procedure ComputeTotp_InvalidDigits_ReturnsMinusOne;
    procedure ComputeTotp_InvalidBase32Secret_ReturnsMinusOne;
    procedure ComputeTotp_EmptySecret_ReturnsMinusOne;
  end;

  TOtpValidateTotpTests = class(TSynTestCase)
  published
    procedure ValidateTotp_AcceptsCurrentStep_WithWindow0;
    procedure ValidateTotp_AcceptsAdjacentStep_WithWindow1;
    procedure ValidateTotp_RejectsAdjacentStep_WithWindow0;
    procedure ValidateTotp_NegativeWindow_ReturnsFalse;
    procedure ValidateTotp_WindowAboveMax_ReturnsFalse;
    procedure ValidateTotp_InvalidToken_ReturnsFalse;
    procedure ValidateTotp_TokenOutOfDigitsRange_ReturnsFalse;
    procedure ValidateTotp_ShortHash_RejectsZeroToken;
    procedure ValidateTotp_EmptyOrInvalidSecret_ReturnsFalse;
    procedure ValidateTotp_HonoursDigitsAndInterval;
  end;

  TOtpVerifyTotpStepTests = class(TSynTestCase)
  published
    procedure VerifyTotpStep_Rfc6238Vector_ReportsMatchedStep;
    procedure VerifyTotpStep_AdjacentSteps_ReportMatchedStep;
    procedure VerifyTotpStep_OutsideWindow_ReturnsFalse;
    procedure VerifyTotpStep_MalformedCodes_ReturnFalse;
    procedure VerifyTotpStep_8Digits;
    procedure VerifyTotpStep_InvalidParameters_ReturnFalse;
    procedure VerifyTotpStep_ShortHash_RejectsZeroCode;
    procedure VerifyTotpStep_EvaluatesEveryStep;
  end;

  TOtpParseCodeTests = class(TSynTestCase)
  published
    procedure ParseOtpCode_AcceptsExactDigits;
    procedure ParseOtpCode_RejectsMalformedInput;
    procedure ParseOtpCode_RejectsInvalidDigits;
    procedure FormatOtpCode_PadsWithLeadingZeros;
  end;

  TOtpAuthUriTests = class(TSynTestCase)
  published
    procedure BuildOtpAuthUri_PlainValues;
    procedure BuildOtpAuthUri_EncodesLabelAndIssuer;
    procedure BuildOtpAuthUri_WithoutIssuer;
    procedure BuildOtpAuthUri_InvalidInput_ReturnsEmpty;
  end;

  TOtpFactoryTests = class(TSynTestCase)
  published
    procedure Factory_CreateDefault_ReturnsWorkingProvider;
    procedure Factory_CreateWithProviders_UsesInjectedDependencies;
  end;

  TFixedTimeProvider = class(TInterfacedObject, ITimeProvider)
  private
    fFixedTime: Int64;
    fCallCount: Integer;
  public
    constructor Create(AFixedTime: Int64);
    function GetCurrentUnixTime: Int64;
    property CallCount: Integer read fCallCount;
  end;

  TMormotSha1CryptoProvider = class(TInterfacedObject, ICryptoProvider)
  public
    function ComputeHmac(const Key: RawByteString; const Data; DataLen: Integer): RawByteString;
  end;

  TMormotBase32EncodingProvider = class(TInterfacedObject, IEncodingProvider)
  public
    function Base32Decode(const Encoded: RawUtf8): RawByteString;
    function Base32Encode(const Data: RawByteString): RawUtf8;
  end;

  TConstantCryptoProvider = class(TInterfacedObject, ICryptoProvider)
  private
    fHash: RawByteString;
    fCallCount: Integer;
    fLastKey: RawByteString;
    fLastDataLen: Integer;
  public
    constructor Create(const AHash: RawByteString);
    function ComputeHmac(const Key: RawByteString; const Data; DataLen: Integer): RawByteString;
    property CallCount: Integer read fCallCount;
    property LastKey: RawByteString read fLastKey;
    property LastDataLen: Integer read fLastDataLen;
  end;

  TSpyEncodingProvider = class(TInterfacedObject, IEncodingProvider)
  private
    fDecoded: RawByteString;
    fDecodeCallCount: Integer;
    fEncodeCallCount: Integer;
    fLastEncodedInput: RawUtf8;
  public
    constructor Create(const ADecoded: RawByteString);
    function Base32Decode(const Encoded: RawUtf8): RawByteString;
    function Base32Encode(const Data: RawByteString): RawUtf8;
    property Decoded: RawByteString read fDecoded;
    property DecodeCallCount: Integer read fDecodeCallCount;
    property EncodeCallCount: Integer read fEncodeCallCount;
    property LastEncodedInput: RawUtf8 read fLastEncodedInput;
  end;

implementation

const
  TEST_SECRET_BASE32: RawUtf8 = 'JBSWY3DPEHPK3PXP';
  RFC4226_SECRET_ASCII: RawByteString = '12345678901234567890';
  RFC6238_SECRET_BASE32: RawUtf8 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  RFC6238_SECRET_BIN: RawByteString = '12345678901234567890';

function BuildHashForOffset(Offset: Byte; B1, B2, B3, B4: Byte): RawByteString;
begin
  SetLength(Result, 20);
  FillChar(pointer(Result)^, 20, 0);
  Result[Offset + 1] := AnsiChar(B1);
  Result[Offset + 2] := AnsiChar(B2);
  Result[Offset + 3] := AnsiChar(B3);
  Result[Offset + 4] := AnsiChar(B4);
  Result[20] := AnsiChar(Offset and $0f);
end;

function CreateDeterministicOtp(UnixTime: Int64): IOtpProvider;
begin
  Result := TOtpFactory.CreateWithProviders(
    TFixedTimeProvider.Create(UnixTime),
    TMormotSha1CryptoProvider.Create,
    TMormotBase32EncodingProvider.Create
  );
end;


{ TOtpTests }

procedure TOtpTests.Infrastructure;
begin
  AddCase([TOtpInfrastructureTests]);
end;

procedure TOtpTests.ComputeOtp;
begin
  AddCase([TOtpComputeOtpTests]);
end;

procedure TOtpTests.ComputeTotp;
begin
  AddCase([TOtpComputeTotpTests]);
end;

procedure TOtpTests.ValidateTotp;
begin
  AddCase([TOtpValidateTotpTests]);
end;

procedure TOtpTests.VerifyTotpStep;
begin
  AddCase([TOtpVerifyTotpStepTests]);
end;

procedure TOtpTests.ParseCode;
begin
  AddCase([TOtpParseCodeTests]);
end;

procedure TOtpTests.OtpAuthUri;
begin
  AddCase([TOtpAuthUriTests]);
end;

procedure TOtpTests.Factory;
begin
  AddCase([TOtpFactoryTests]);
end;

{ TOtpInfrastructureTests }

procedure TOtpInfrastructureTests.TimeProvider_ReturnsFixedUnixTime;
var
  TimeProvider: TFixedTimeProvider;
begin
  TimeProvider := TFixedTimeProvider.Create(1732276800);
  CheckEqual(TimeProvider.GetCurrentUnixTime, 1732276800, 'fixed unix time');
  CheckEqual(TimeProvider.GetCurrentUnixTime, 1732276800, 'time remains fixed');
  CheckEqual(TimeProvider.CallCount, 2, 'time provider call count');
end;

procedure TOtpInfrastructureTests.SecretGenerator_RespectsLengthRules;
var
  Generator: ISecretGenerator;
begin
  Generator := TOtpFactory.CreateSecretGenerator;
  CheckEqual(Length(Generator.GenerateSecret(32)), 32, 'length=32');
  CheckEqual(Length(Generator.GenerateSecret(40)), 40, 'length=40');
  CheckEqual(Length(Generator.GenerateSecret(24)), 32, 'length=24 raised to 160-bit minimum');
  CheckEqual(Length(Generator.GenerateSecret(16)), 32, 'length=16 raised to 160-bit minimum');
  CheckEqual(Length(Generator.GenerateSecret(1)), 32, 'small length raised to minimum');
  CheckEqual(Length(Generator.GenerateSecret(0)), 32, 'zero length raised to minimum');
  CheckEqual(Length(Generator.GenerateSecret(-5)), 32, 'negative length raised to minimum');
  CheckEqual(Length(Generator.GenerateSecret(33)), 40, 'length rounds to next multiple of 8');
end;

procedure TOtpInfrastructureTests.SecretGenerator_UsesOnlyBase32Alphabet;
var
  Generator: ISecretGenerator;
  Secret: RawUtf8;
  i: Integer;
const
  BASE32_CHARS: RawUtf8 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
begin
  Generator := TOtpFactory.CreateSecretGenerator;
  Secret := Generator.GenerateSecret(32);

  for i := 1 to Length(Secret) do
    Check(
      PosEx(Secret[i], BASE32_CHARS) > 0,
      FormatString('invalid char at position %', [i])
    );
end;

procedure TOtpInfrastructureTests.SecretGenerator_DecodesToExpectedByteCount;
var
  Generator: ISecretGenerator;
  Secret32, Secret40: RawUtf8;
  Decoded32, Decoded40: RawByteString;
begin
  Generator := TOtpFactory.CreateSecretGenerator;

  Secret32 := Generator.GenerateSecret(32);
  Decoded32 := Base32ToBin(Secret32);
  CheckEqual(Length(Decoded32), 20, '32 base32 chars -> 20 bytes');

  Secret40 := Generator.GenerateSecret(40);
  Decoded40 := Base32ToBin(Secret40);
  CheckEqual(Length(Decoded40), 25, '40 base32 chars -> 25 bytes');
end;

procedure TOtpInfrastructureTests.SecretGenerator_SuccessiveSecretsDiffer;
var
  Generator: ISecretGenerator;
  Previous, Current: RawUtf8;
  i: Integer;
begin
  Generator := TOtpFactory.CreateSecretGenerator;
  Previous := Generator.GenerateSecret(32);
  for i := 1 to 20 do
  begin
    Current := Generator.GenerateSecret(32);
    Check(Current <> Previous, 'successive secrets differ');
    Previous := Current;
  end;
end;

{ TOtpComputeOtpTests }

procedure TOtpComputeOtpTests.ComputeOTP_RFC4226_TestVectors_6Digits;
var
  Otp: IOtpProvider;
  Expected: array[0..9] of Integer;
  i: Integer;
begin
  Expected[0] := 755224;
  Expected[1] := 287082;
  Expected[2] := 359152;
  Expected[3] := 969429;
  Expected[4] := 338314;
  Expected[5] := 254676;
  Expected[6] := 287922;
  Expected[7] := 162583;
  Expected[8] := 399871;
  Expected[9] := 520489;

  Otp := TOtpFactory.CreateDefault;

  for i := 0 to 9 do
    CheckEqual(
      Otp.ComputeOTP(RFC4226_SECRET_ASCII, i, 6),
      Expected[i],
      FormatUtf8('RFC4226 vector %', [i]));
end;

procedure TOtpComputeOtpTests.ComputeOTP_DigitsOutOfRange_ReturnsMinusOne;
var
  Otp: IOtpProvider;
const
  COUNTER = 7;
begin
  Otp := TOtpFactory.CreateDefault;
  CheckEqual(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, 0), -1, 'digits=0');
  CheckEqual(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, -1), -1, 'digits<0');
  CheckEqual(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, 10), -1, 'digits>9');
  Check(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, 1) >= 0, 'digits=1 accepted');
  Check(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, 9) >= 0, 'digits=9 accepted');
end;

procedure TOtpComputeOtpTests.ComputeOTP_ShortHash_ReturnsMinusOne;
var
  Otp: IOtpProvider;
  Crypto: TConstantCryptoProvider;
begin
  Crypto := TConstantCryptoProvider.Create('abc');
  Otp := TOtpFactory.CreateWithProviders(
    TFixedTimeProvider.Create(0),
    Crypto,
    TMormotBase32EncodingProvider.Create
  );

  CheckEqual(Otp.ComputeOTP('binary-secret', 42, 6), -1, 'short hash fails closed');
  CheckEqual(Crypto.CallCount, 1, 'crypto called');
  CheckEqual(Crypto.LastDataLen, SizeOf(Int64), 'counter size');
end;

procedure TOtpComputeOtpTests.ComputeOTP_DynamicTruncation_OffsetBoundary0;
var
  Otp: IOtpProvider;
begin
  Otp := TOtpFactory.CreateWithProviders(
    TFixedTimeProvider.Create(0),
    TConstantCryptoProvider.Create(BuildHashForOffset(0, $7f, $12, $34, $56)),
    TMormotBase32EncodingProvider.Create
  );

  CheckEqual(Otp.ComputeOTP('binary-secret', 0, 6), 899478, 'offset=0');
end;

procedure TOtpComputeOtpTests.ComputeOTP_DynamicTruncation_OffsetBoundary15;
var
  Otp: IOtpProvider;
begin
  Otp := TOtpFactory.CreateWithProviders(
    TFixedTimeProvider.Create(0),
    TConstantCryptoProvider.Create(BuildHashForOffset(15, $01, $23, $45, $67)),
    TMormotBase32EncodingProvider.Create
  );

  CheckEqual(Otp.ComputeOTP('binary-secret', 0, 6), 88743, 'offset=15');
end;

procedure TOtpComputeOtpTests.ComputeOTP_DeterministicForSameInputs;
var
  Otp: IOtpProvider;
  Code1, Code2: Integer;
begin
  Otp := TOtpFactory.CreateDefault;
  Code1 := Otp.ComputeOTP(RFC4226_SECRET_ASCII, 12345, 6);
  Code2 := Otp.ComputeOTP(RFC4226_SECRET_ASCII, 12345, 6);
  CheckEqual(Code1, Code2, 'same input -> same output');
end;

{ TOtpComputeTotpTests }

procedure TOtpComputeTotpTests.ComputeTOTP_RFC6238_8DigitVectors;
const
  RFC_TIMES: array[0..5] of Int64 = (
    59, 1111111109, 1111111111,
    1234567890, 2000000000, 20000000000
  );
  RFC_EXPECTED: array[0..5] of Integer = (
    94287082, 7081804, 14050471,
    89005924, 69279037, 65353130
  );
var
  Otp: IOtpProvider;
  i: Integer;
begin
  for i := 0 to High(RFC_TIMES) do
  begin
    Otp := CreateDeterministicOtp(RFC_TIMES[i]);
    CheckEqual(
      Otp.ComputeTOTP(RFC6238_SECRET_BASE32, 8, 30),
      RFC_EXPECTED[i],
      FormatUtf8('RFC6238 vector %', [i]));
  end;
end;

procedure TOtpComputeTotpTests.ComputeTOTP_NonPositiveInterval_ReturnsMinusOne;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276815);
  CheckEqual(Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 0), -1, 'interval=0');
  CheckEqual(Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, -30), -1, 'interval<0');
  Check(Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 60) >= 0, 'interval=60 accepted');
end;

procedure TOtpComputeTotpTests.ComputeTOTP_InvalidDigits_ReturnsMinusOne;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276815);
  CheckEqual(Otp.ComputeTOTP(TEST_SECRET_BASE32, 0, 30), -1, 'digits=0');
  CheckEqual(Otp.ComputeTOTP(TEST_SECRET_BASE32, 10, 30), -1, 'digits=10');
end;

procedure TOtpComputeTotpTests.ComputeTOTP_InvalidBase32Secret_ReturnsMinusOne;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  CheckEqual(Otp.ComputeTOTP('INVALID!!!', 6, 30), -1, 'invalid base32 secret');
end;

procedure TOtpComputeTotpTests.ComputeTOTP_EmptySecret_ReturnsMinusOne;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  CheckEqual(Otp.ComputeTOTP('', 6, 30), -1, 'empty secret');
end;

{ TOtpValidateTotpTests }

procedure TOtpValidateTotpTests.ValidateTOTP_AcceptsCurrentStep_WithWindow0;
var
  Otp: IOtpProvider;
  Token: Integer;
begin
  Otp := CreateDeterministicOtp(1732276800);
  Token := Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);
  Check(Otp.ValidateTOTP(TEST_SECRET_BASE32, Token, 0), 'current step is valid');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_AcceptsAdjacentStep_WithWindow1;
var
  OtpCurrent, OtpPrevious, OtpNext: IOtpProvider;
  TokenPrevious, TokenNext: Integer;
const
  BASE_TIME = 1732276800;
begin
  OtpCurrent := CreateDeterministicOtp(BASE_TIME);
  OtpPrevious := CreateDeterministicOtp(BASE_TIME - 30);
  OtpNext := CreateDeterministicOtp(BASE_TIME + 30);

  TokenPrevious := OtpPrevious.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);
  TokenNext := OtpNext.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);

  Check(OtpCurrent.ValidateTOTP(TEST_SECRET_BASE32, TokenPrevious, 1), 'previous step accepted');
  Check(OtpCurrent.ValidateTOTP(TEST_SECRET_BASE32, TokenNext, 1), 'next step accepted');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_RejectsAdjacentStep_WithWindow0;
var
  OtpCurrent, OtpPrevious, OtpNext: IOtpProvider;
  TokenPrevious, TokenNext: Integer;
const
  BASE_TIME = 1732276800;
begin
  OtpCurrent := CreateDeterministicOtp(BASE_TIME);
  OtpPrevious := CreateDeterministicOtp(BASE_TIME - 30);
  OtpNext := CreateDeterministicOtp(BASE_TIME + 30);

  TokenPrevious := OtpPrevious.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);
  TokenNext := OtpNext.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);

  Check(not OtpCurrent.ValidateTOTP(TEST_SECRET_BASE32, TokenPrevious, 0), 'previous step rejected');
  Check(not OtpCurrent.ValidateTOTP(TEST_SECRET_BASE32, TokenNext, 0), 'next step rejected');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_NegativeWindow_ReturnsFalse;
var
  Otp: IOtpProvider;
  Token: Integer;
const
  BASE_TIME = 1732276800;
begin
  Otp := CreateDeterministicOtp(BASE_TIME);
  Token := Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);
  Check(Otp.ValidateTOTP(TEST_SECRET_BASE32, Token, 1), 'window=1 accepted');
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, Token, -1), 'window=-1 refused');
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, Token, Low(Integer)), 'window=Low(Integer) refused');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_WindowAboveMax_ReturnsFalse;
var
  Otp: IOtpProvider;
  Token: Integer;
const
  BASE_TIME = 1732276800;
begin
  Otp := CreateDeterministicOtp(BASE_TIME);
  Token := Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);
  Check(Otp.ValidateTOTP(TEST_SECRET_BASE32, Token, OTP_MAX_WINDOW_STEPS), 'max window accepted');
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, Token, OTP_MAX_WINDOW_STEPS + 1), 'max+1 window refused');
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, Token, 100000), 'huge window refused');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_InvalidToken_ReturnsFalse;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, -1, 0), 'invalid token');
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, Low(Integer), 1), 'Low(Integer) token');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_TokenOutOfDigitsRange_ReturnsFalse;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, 1000000, 1), '7-digit token with digits=6');
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, High(Integer), 1), 'High(Integer) token');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_ShortHash_RejectsZeroToken;
var
  Otp: IOtpProvider;
begin
  // a failing crypto provider used to make ComputeOTP() return 0, so that the
  // token 0 ("000000") was accepted: it must fail closed
  Otp := TOtpFactory.CreateWithProviders(
    TFixedTimeProvider.Create(1732276800),
    TConstantCryptoProvider.Create('abc'),
    TMormotBase32EncodingProvider.Create
  );
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, 0, 1), 'token 0 refused on short hash');
  CheckEqual(Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 30), -1, 'short hash -> -1');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_EmptyOrInvalidSecret_ReturnsFalse;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  Check(not Otp.ValidateTOTP('', 123456, 1), 'empty secret');
  Check(not Otp.ValidateTOTP('INVALID!!!', 123456, 1), 'invalid secret');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_HonoursDigitsAndInterval;
var
  Otp: IOtpProvider;
begin
  // RFC 6238 Appendix B: T=1111111109 -> 07081804 (8 digits, 30 s)
  Otp := CreateDeterministicOtp(1111111109);
  Check(Otp.ValidateTOTP(RFC6238_SECRET_BASE32, 7081804, 0, 8, 30), '8 digits accepted');
  Check(Otp.ValidateTOTP(RFC6238_SECRET_BASE32, 81804, 0, 6, 30), 'last 6 digits accepted');
  Check(not Otp.ValidateTOTP(RFC6238_SECRET_BASE32, 7081804, 0, 6, 30), '8-digit code refused with digits=6');
  Check(not Otp.ValidateTOTP(RFC6238_SECRET_BASE32, 81804, 0, 8, 30), '6-digit code refused with digits=8');
  Check(not Otp.ValidateTOTP(RFC6238_SECRET_BASE32, 81804, 0, 6, 60), 'other interval refused');
  Check(not Otp.ValidateTOTP(RFC6238_SECRET_BASE32, 81804, 0, 6, 0), 'interval=0 refused');
  Check(not Otp.ValidateTOTP(RFC6238_SECRET_BASE32, 81804, 0, 0, 30), 'digits=0 refused');
end;

{ TOtpVerifyTotpStepTests }

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_Rfc6238Vector_ReportsMatchedStep;
var
  Otp: IOtpProvider;
  Step: Int64;
const
  T = 1111111109; // RFC 6238 Appendix B -> 07081804
begin
  Otp := TOtpFactory.CreateDefault;
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 1, 1, Step), 'vector accepted');
  CheckEqual(Step, T div 30, 'matched step is the current one');
  CheckEqual(Step, 37037036, 'matched step value');
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 0, 0, Step), 'window 0 accepted');
  CheckEqual(Step, 37037036, 'matched step value with window 0');
end;

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_AdjacentSteps_ReportMatchedStep;
var
  Otp: IOtpProvider;
  Step: Int64;
  Previous, Next: RawUtf8;
const
  T = 1732276800;
begin
  Otp := TOtpFactory.CreateDefault;
  Previous := FormatOtpCode(Otp.ComputeOTP(RFC6238_SECRET_BIN, T div 30 - 1, 6), 6);
  Next := FormatOtpCode(Otp.ComputeOTP(RFC6238_SECRET_BIN, T div 30 + 1, 6), 6);
  CheckEqual(Length(Previous), 6);
  CheckEqual(Length(Next), 6);

  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, Previous, T, 1, 0, Step), 'previous step accepted');
  CheckEqual(Step, T div 30 - 1, 'previous step reported');
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, Next, T, 0, 1, Step), 'next step accepted');
  CheckEqual(Step, T div 30 + 1, 'next step reported');

  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, Previous, T, 0, 1, Step), 'previous refused without StepsBack');
  CheckEqual(Step, 0, 'no step reported on failure');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, Next, T, 1, 0, Step), 'next refused without StepsForward');
  CheckEqual(Step, 0, 'no step reported on failure');
end;

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_OutsideWindow_ReturnsFalse;
var
  Otp: IOtpProvider;
  Step: Int64;
  Code: RawUtf8;
const
  T = 1732276800;
begin
  Otp := TOtpFactory.CreateDefault;
  Code := FormatOtpCode(Otp.ComputeOTP(RFC6238_SECRET_BIN, T div 30 + 2, 6), 6);
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, Code, T, 1, 1, Step), 'T+2 refused with window 1');
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, Code, T, 1, 2, Step), 'T+2 accepted with StepsForward=2');
  CheckEqual(Step, T div 30 + 2, 'T+2 step reported');
  Code := FormatOtpCode(Otp.ComputeOTP(RFC6238_SECRET_BIN, T div 30 - 10, 6), 6);
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, Code, T, 10, 0, Step), 'T-10 accepted with StepsBack=10');
  CheckEqual(Step, T div 30 - 10, 'T-10 step reported');
end;

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_MalformedCodes_ReturnFalse;
var
  Otp: IOtpProvider;
  Step: Int64;
  i: Integer;
const
  T = 1111111109; // valid code is 081804
  BAD: array[0..11] of RawUtf8 = (
    '81804', '+081804', ' 081804', '081804 ', '081804a', '0081804',
    '18446744073709633420', '0x13F8C', '$13F8C', '4295049100', '', '08180');
begin
  Otp := TOtpFactory.CreateDefault;
  for i := 0 to High(BAD) do
  begin
    Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, BAD[i], T, 1, 1, Step),
      FormatString('malformed code [%] refused', [BAD[i]]));
    CheckEqual(Step, 0, 'no step on failure');
  end;
end;

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_8Digits;
var
  Otp: IOtpProvider;
  Step: Int64;
const
  T = 1234567890; // RFC 6238 Appendix B -> 89005924
begin
  Otp := TOtpFactory.CreateDefault;
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '89005924', T, 1, 1, Step, 8, 30), '8 digits accepted');
  CheckEqual(Step, T div 30, '8-digit matched step');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '005924', T, 1, 1, Step, 8, 30), '6 digits refused with Digits=8');
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '005924', T, 1, 1, Step, 6, 30), '6 digits accepted with Digits=6');
end;

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_InvalidParameters_ReturnFalse;
var
  Otp: IOtpProvider;
  Step: Int64;
const
  T = 1111111109;
begin
  Otp := TOtpFactory.CreateDefault;
  Check(not Otp.VerifyTOTPStep('', '081804', T, 1, 1, Step), 'empty secret');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', -1, 1, 1, Step), 'negative time');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, -1, 1, Step), 'negative StepsBack');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 1, -1, Step), 'negative StepsForward');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, OTP_MAX_WINDOW_STEPS + 1, 1, Step), 'StepsBack above max');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 1, OTP_MAX_WINDOW_STEPS + 1, Step), 'StepsForward above max');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 1, 1, Step, 6, 0), 'interval=0');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 1, 1, Step, 6, -30), 'interval<0');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 1, 1, Step, 0, 30), 'digits=0');
  Check(not Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '0000081804', T, 1, 1, Step, 10, 30), 'digits=10');
  CheckEqual(Step, 0, 'no step on failure');
  Check(Otp.VerifyTOTPStep(RFC6238_SECRET_BIN, '081804', T, 1, 1, Step), 'valid parameters still accepted');
end;

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_ShortHash_RejectsZeroCode;
var
  Otp: IOtpProvider;
  Step: Int64;
begin
  Otp := TOtpFactory.CreateWithProviders(
    TFixedTimeProvider.Create(0),
    TConstantCryptoProvider.Create('abc'),
    TMormotBase32EncodingProvider.Create
  );
  Check(not Otp.VerifyTOTPStep('binary-secret', '000000', 1732276800, 1, 1, Step), '000000 refused on short hash');
  CheckEqual(Step, 0, 'no step on failure');
end;

procedure TOtpVerifyTotpStepTests.VerifyTotpStep_EvaluatesEveryStep;
var
  Otp: IOtpProvider;
  Crypto: TConstantCryptoProvider;
  Step: Int64;
const
  T = 1732276800;
begin
  // constant hash -> every step yields the same code 899478: the whole window
  // must be evaluated (no early exit) and the first matching step reported
  Crypto := TConstantCryptoProvider.Create(BuildHashForOffset(0, $7f, $12, $34, $56));
  Otp := TOtpFactory.CreateWithProviders(
    TFixedTimeProvider.Create(T), Crypto, TMormotBase32EncodingProvider.Create);
  Check(Otp.VerifyTOTPStep('binary-secret', '899478', T, 2, 3, Step), 'accepted');
  CheckEqual(Crypto.CallCount, 6, 'all 6 steps of the window were computed');
  CheckEqual(Step, T div 30 - 2, 'first matching step reported');
  Check(not Otp.VerifyTOTPStep('binary-secret', '899479', T, 2, 3, Step), 'refused');
  CheckEqual(Crypto.CallCount, 12, 'all 6 steps computed on failure too');
end;

{ TOtpParseCodeTests }

procedure TOtpParseCodeTests.ParseOtpCode_AcceptsExactDigits;
var
  Value: Integer;
begin
  Check(ParseOtpCode('081804', 6, Value), '6 digits');
  CheckEqual(Value, 81804);
  Check(ParseOtpCode('000000', 6, Value), 'all zeros');
  CheckEqual(Value, 0);
  Check(ParseOtpCode('999999', 6, Value), 'all nines');
  CheckEqual(Value, 999999);
  Check(ParseOtpCode('07081804', 8, Value), '8 digits');
  CheckEqual(Value, 7081804);
  Check(ParseOtpCode('7', 1, Value), '1 digit');
  CheckEqual(Value, 7);
  Check(ParseOtpCode('999999999', 9, Value), '9 digits');
  CheckEqual(Value, 999999999);
end;

procedure TOtpParseCodeTests.ParseOtpCode_RejectsMalformedInput;
var
  Value: Integer;
  i: Integer;
const
  BAD: array[0..13] of RawUtf8 = (
    '81804', '+081804', '-081804', ' 081804', '081804 ', '081804a', '0081804',
    '0x13F8', '$13F8C', '', '08180', '08 804', '08'#9'804', '0818O4');
begin
  for i := 0 to High(BAD) do
  begin
    Check(not ParseOtpCode(BAD[i], 6, Value), FormatString('[%] refused', [BAD[i]]));
    CheckEqual(Value, -1, 'value is -1 on failure');
  end;
  // non-ASCII digits (e.g. Arabic-Indic U+0661) are refused
  Check(not ParseOtpCode('08180'#$D9#$A1, 6, Value), 'non-ASCII digit refused');
  CheckEqual(Value, -1);
end;

procedure TOtpParseCodeTests.ParseOtpCode_RejectsInvalidDigits;
var
  Value: Integer;
begin
  Check(not ParseOtpCode('081804', 0, Value), 'digits=0');
  CheckEqual(Value, -1);
  Check(not ParseOtpCode('0000081804', 10, Value), 'digits=10');
  CheckEqual(Value, -1);
  Check(not ParseOtpCode('081804', -6, Value), 'digits<0');
  CheckEqual(Value, -1);
end;

procedure TOtpParseCodeTests.FormatOtpCode_PadsWithLeadingZeros;
begin
  Check(FormatOtpCode(81804, 6) = '081804', '081804');
  Check(FormatOtpCode(0, 6) = '000000', '000000');
  Check(FormatOtpCode(7081804, 8) = '07081804', '07081804');
  Check(FormatOtpCode(999999, 6) = '999999', '999999');
  Check(FormatOtpCode(1000000, 6) = '', 'too large');
  Check(FormatOtpCode(-1, 6) = '', 'negative');
  Check(FormatOtpCode(1, 0) = '', 'digits=0');
  Check(FormatOtpCode(1, 10) = '', 'digits=10');
end;

{ TOtpAuthUriTests }

procedure TOtpAuthUriTests.BuildOtpAuthUri_PlainValues;
begin
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', TEST_SECRET_BASE32),
    'otpauth://totp/mORMot:user?secret=JBSWY3DPEHPK3PXP&issuer=mORMot&algorithm=SHA1&digits=6&period=30');
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', TEST_SECRET_BASE32, 8, 60),
    'otpauth://totp/mORMot:user?secret=JBSWY3DPEHPK3PXP&issuer=mORMot&algorithm=SHA1&digits=8&period=60');
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', 'JB======'),
    'otpauth://totp/mORMot:user?secret=JB&issuer=mORMot&algorithm=SHA1&digits=6&period=30',
    'padding removed');
end;

procedure TOtpAuthUriTests.BuildOtpAuthUri_EncodesLabelAndIssuer;
begin
  CheckEqual(BuildOtpAuthUri('Example Bank', 'eve+x@evil.example&issuer=Bank#', TEST_SECRET_BASE32),
    'otpauth://totp/Example%20Bank:eve%2Bx%40evil.example%26issuer%3DBank%23' +
    '?secret=JBSWY3DPEHPK3PXP&issuer=Example%20Bank&algorithm=SHA1&digits=6&period=30');
  CheckEqual(BuildOtpAuthUri('a:b/c?d', 'john.doe_1~', TEST_SECRET_BASE32),
    'otpauth://totp/a%3Ab%2Fc%3Fd:john.doe_1~?secret=JBSWY3DPEHPK3PXP&issuer=a%3Ab%2Fc%3Fd' +
    '&algorithm=SHA1&digits=6&period=30');
  CheckEqual(BuildOtpAuthUri('', #$C3#$A9, TEST_SECRET_BASE32),
    'otpauth://totp/%C3%A9?secret=JBSWY3DPEHPK3PXP&algorithm=SHA1&digits=6&period=30',
    'UTF-8 bytes percent-encoded');
end;

procedure TOtpAuthUriTests.BuildOtpAuthUri_WithoutIssuer;
begin
  CheckEqual(BuildOtpAuthUri('', 'user', TEST_SECRET_BASE32),
    'otpauth://totp/user?secret=JBSWY3DPEHPK3PXP&algorithm=SHA1&digits=6&period=30');
end;

procedure TOtpAuthUriTests.BuildOtpAuthUri_InvalidInput_ReturnsEmpty;
begin
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', ''), '', 'empty secret');
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', '===='), '', 'padding only');
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', TEST_SECRET_BASE32, 0, 30), '', 'digits=0');
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', TEST_SECRET_BASE32, 10, 30), '', 'digits=10');
  CheckEqual(BuildOtpAuthUri('mORMot', 'user', TEST_SECRET_BASE32, 6, 0), '', 'period=0');
end;

{ TOtpFactoryTests }

procedure TOtpFactoryTests.Factory_CreateDefault_ReturnsWorkingProvider;
var
  Otp: IOtpProvider;
  Code: Integer;
begin
  Otp := TOtpFactory.CreateDefault;
  Check(Assigned(Otp), 'default provider is assigned');

  Code := Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);
  Check(Code >= 0, 'code is non-negative');
  Check(Code < 1000000, 'code is 6 digits');
end;

procedure TOtpFactoryTests.Factory_CreateWithProviders_UsesInjectedDependencies;
var
  Otp: IOtpProvider;
  TimeProvider: TFixedTimeProvider;
  CryptoProvider: TConstantCryptoProvider;
  EncodingProvider: TSpyEncodingProvider;
  Code: Integer;
  InjectedSecret: RawByteString;
begin
  InjectedSecret := 'raw-secret';
  TimeProvider := TFixedTimeProvider.Create(600);
  CryptoProvider := TConstantCryptoProvider.Create(BuildHashForOffset(0, $7f, $12, $34, $56));
  EncodingProvider := TSpyEncodingProvider.Create(InjectedSecret);

  Otp := TOtpFactory.CreateWithProviders(TimeProvider, CryptoProvider, EncodingProvider);
  Code := Otp.ComputeTOTP('CUSTOMSECRET', 6, 30);

  CheckEqual(Code, 899478, 'code comes from injected crypto provider');
  CheckEqual(EncodingProvider.DecodeCallCount, 1, 'injected encoding provider used');
  Check(EncodingProvider.LastEncodedInput = 'CUSTOMSECRET', 'input passed to decoder');
  CheckEqual(TimeProvider.CallCount, 1, 'injected time provider used');
  CheckEqual(CryptoProvider.CallCount, 1, 'injected crypto provider used');
  Check(CryptoProvider.LastKey = InjectedSecret, 'decoded secret passed to crypto');
  CheckEqual(CryptoProvider.LastDataLen, SizeOf(Int64), 'counter size passed to crypto');
end;

{ TFixedTimeProvider }

constructor TFixedTimeProvider.Create(AFixedTime: Int64);
begin
  inherited Create;
  fFixedTime := AFixedTime;
end;

function TFixedTimeProvider.GetCurrentUnixTime: Int64;
begin
  Inc(fCallCount);
  Result := fFixedTime;
end;

{ TMormotSha1CryptoProvider }

function TMormotSha1CryptoProvider.ComputeHmac(const Key: RawByteString;
  const Data; DataLen: Integer): RawByteString;
var
  Hash: THash512Rec;
begin
  Hmac(saSha1, pointer(Key), @Data, Length(Key), DataLen, @Hash);
  SetLength(Result, 20);
  MoveFast(Hash, pointer(Result)^, 20);
end;

{ TMormotBase32EncodingProvider }

function TMormotBase32EncodingProvider.Base32Decode(const Encoded: RawUtf8): RawByteString;
begin
  Result := Base32ToBin(Encoded);
end;

function TMormotBase32EncodingProvider.Base32Encode(const Data: RawByteString): RawUtf8;
begin
  Result := BinToBase32(Data);
end;

{ TConstantCryptoProvider }

constructor TConstantCryptoProvider.Create(const AHash: RawByteString);
begin
  inherited Create;
  fHash := AHash;
end;

function TConstantCryptoProvider.ComputeHmac(const Key: RawByteString;
  const Data; DataLen: Integer): RawByteString;
begin
  Inc(fCallCount);
  fLastKey := Key;
  fLastDataLen := DataLen;
  Result := fHash;
end;

{ TSpyEncodingProvider }

constructor TSpyEncodingProvider.Create(const ADecoded: RawByteString);
begin
  inherited Create;
  fDecoded := ADecoded;
end;

function TSpyEncodingProvider.Base32Decode(const Encoded: RawUtf8): RawByteString;
begin
  Inc(fDecodeCallCount);
  fLastEncodedInput := Encoded;
  Result := fDecoded;
end;

function TSpyEncodingProvider.Base32Encode(const Data: RawByteString): RawUtf8;
begin
  Inc(fEncodeCallCount);
  Result := BinToBase32(Data);
end;

end.

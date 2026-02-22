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
    procedure Factory;
  end;

  TOtpInfrastructureTests = class(TSynTestCase)
  published
    procedure TimeProvider_ReturnsFixedUnixTime;
    procedure SecretGenerator_RespectsLengthRules;
    procedure SecretGenerator_UsesOnlyBase32Alphabet;
    procedure SecretGenerator_DecodesToExpectedByteCount;
  end;

  TOtpComputeOtpTests = class(TSynTestCase)
  published
    procedure ComputeOtp_Rfc4226_TestVectors_6Digits;
    procedure ComputeOtp_DigitsOutOfRange_FallsBackTo6;
    procedure ComputeOtp_ShortHash_ReturnsZero;
    procedure ComputeOtp_DynamicTruncation_OffsetBoundary0;
    procedure ComputeOtp_DynamicTruncation_OffsetBoundary15;
    procedure ComputeOtp_DeterministicForSameInputs;
  end;

  TOtpComputeTotpTests = class(TSynTestCase)
  published
    procedure ComputeTotp_Rfc6238_8DigitVectors;
    procedure ComputeTotp_NonPositiveInterval_FallsBackTo30;
    procedure ComputeTotp_InvalidBase32Secret_ReturnsZero;
    procedure ComputeTotp_EmptySecret_ReturnsZero;
  end;

  TOtpValidateTotpTests = class(TSynTestCase)
  published
    procedure ValidateTotp_AcceptsCurrentStep_WithWindow0;
    procedure ValidateTotp_AcceptsAdjacentStep_WithWindow1;
    procedure ValidateTotp_RejectsAdjacentStep_WithWindow0;
    procedure ValidateTotp_NegativeWindow_EqualsPositiveWindow;
    procedure ValidateTotp_InvalidToken_ReturnsFalse;
    procedure ValidateTotp_EmptyOrInvalidSecret_ReturnsFalse;
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
  CheckEqual(Length(Generator.GenerateSecret(24)), 24, 'length=24');
  CheckEqual(Length(Generator.GenerateSecret(1)), 32, 'small length falls back to default');
  CheckEqual(Length(Generator.GenerateSecret(25)), 32, 'length rounds to next multiple of 8');
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
      Utf8ToString(FormatUtf8('invalid char at position %', [i]))
    );
end;

procedure TOtpInfrastructureTests.SecretGenerator_DecodesToExpectedByteCount;
var
  Generator: ISecretGenerator;
  Secret32, Secret24: RawUtf8;
  Decoded32, Decoded24: RawByteString;
begin
  Generator := TOtpFactory.CreateSecretGenerator;

  Secret32 := Generator.GenerateSecret(32);
  Decoded32 := Base32ToBin(Secret32);
  CheckEqual(Length(Decoded32), 20, '32 base32 chars -> 20 bytes');

  Secret24 := Generator.GenerateSecret(24);
  Decoded24 := Base32ToBin(Secret24);
  CheckEqual(Length(Decoded24), 15, '24 base32 chars -> 15 bytes');
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

procedure TOtpComputeOtpTests.ComputeOTP_DigitsOutOfRange_FallsBackTo6;
var
  Otp: IOtpProvider;
  Expected: Integer;
const
  COUNTER = 7;
begin
  Otp := TOtpFactory.CreateDefault;
  Expected := Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, 6);

  CheckEqual(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, 0), Expected, 'digits=0');
  CheckEqual(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, -1), Expected, 'digits<0');
  CheckEqual(Otp.ComputeOTP(RFC4226_SECRET_ASCII, COUNTER, 10), Expected, 'digits>9');
end;

procedure TOtpComputeOtpTests.ComputeOTP_ShortHash_ReturnsZero;
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

  CheckEqual(Otp.ComputeOTP('binary-secret', 42, 6), 0, 'short hash');
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

procedure TOtpComputeTotpTests.ComputeTOTP_NonPositiveInterval_FallsBackTo30;
var
  Otp: IOtpProvider;
  Expected: Integer;
begin
  Otp := CreateDeterministicOtp(1732276815);
  Expected := Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);

  CheckEqual(Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, 0), Expected, 'interval=0');
  CheckEqual(Otp.ComputeTOTP(TEST_SECRET_BASE32, 6, -30), Expected, 'interval<0');
end;

procedure TOtpComputeTotpTests.ComputeTOTP_InvalidBase32Secret_ReturnsZero;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  CheckEqual(Otp.ComputeTOTP('INVALID!!!', 6, 30), 0, 'invalid base32 secret');
end;

procedure TOtpComputeTotpTests.ComputeTOTP_EmptySecret_ReturnsZero;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  CheckEqual(Otp.ComputeTOTP('', 6, 30), 0, 'empty secret');
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

procedure TOtpValidateTotpTests.ValidateTOTP_NegativeWindow_EqualsPositiveWindow;
var
  OtpCurrent, OtpPrevious: IOtpProvider;
  TokenPrevious: Integer;
  NegativeResult, PositiveResult: Boolean;
const
  BASE_TIME = 1732276800;
begin
  OtpCurrent := CreateDeterministicOtp(BASE_TIME);
  OtpPrevious := CreateDeterministicOtp(BASE_TIME - 30);
  TokenPrevious := OtpPrevious.ComputeTOTP(TEST_SECRET_BASE32, 6, 30);

  NegativeResult := OtpCurrent.ValidateTOTP(TEST_SECRET_BASE32, TokenPrevious, -1);
  PositiveResult := OtpCurrent.ValidateTOTP(TEST_SECRET_BASE32, TokenPrevious, 1);
  Check(NegativeResult = PositiveResult, 'negative and positive window are equivalent');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_InvalidToken_ReturnsFalse;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  Check(not Otp.ValidateTOTP(TEST_SECRET_BASE32, -1, 0), 'invalid token');
end;

procedure TOtpValidateTotpTests.ValidateTOTP_EmptyOrInvalidSecret_ReturnsFalse;
var
  Otp: IOtpProvider;
begin
  Otp := CreateDeterministicOtp(1732276800);
  Check(not Otp.ValidateTOTP('', 123456, 1), 'empty secret');
  Check(not Otp.ValidateTOTP('INVALID!!!', 123456, 1), 'invalid secret');
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

unit mormot.ext.otp;

// -----------------------------------------------------------------------------
// RFC 4226/6238-compatible HOTP/TOTP unit (HMAC-SHA1 profile)
// -----------------------------------------------------------------------------

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.buffers,
  mormot.crypt.core,
  mormot.crypt.secure;

const
  /// default number of digits of a HOTP/TOTP code
  OTP_DEFAULT_DIGITS = 6;
  /// default TOTP time step, in seconds
  OTP_DEFAULT_INTERVAL = 30;
  /// smallest Base32 secret length produced by ISecretGenerator.GenerateSecret
  // - 32 Base32 characters = 20 bytes = 160 bits, as recommended by RFC 4226 R6
  // (which requires at least 128 bits)
  OTP_MIN_SECRET_CHARS = 32;
  /// widest TOTP verification window accepted, in time steps, in each direction
  // - bounds the number of HMAC computations per verification, and the
  // period during which a code remains valid (10 steps of 30 s = 5 minutes)
  OTP_MAX_WINDOW_STEPS = 10;

type
  /// Time provider abstraction for testability
  // - Allows injection of mock time providers in tests
  ITimeProvider = interface
    ['{F5C61042-13DD-4DEE-B161-3AF893418791}']
    /// Returns current Unix timestamp in seconds
    function GetCurrentUnixTime: Int64;
  end;

  /// Cryptographic operations abstraction
  // - Decouples OTP logic from specific crypto implementations
  // - Enables testing with mock crypto or alternative algorithms
  ICryptoProvider = interface
    ['{92BD74C0-2661-40B5-91D1-C433AE2EAB12}']
    /// Computes HMAC hash of data with given key
    // - Returns raw hash bytes (20 bytes for SHA1, 32 for SHA256, etc.)
    function ComputeHmac(const Key: RawByteString; const Data; DataLen: Integer): RawByteString;
  end;

  /// Base32 encoding/decoding abstraction
  // - RFC 4648 Base32 encoding for OTP secrets
  IEncodingProvider = interface
    ['{9C2F045F-926E-4178-88DF-48BE8D9EA084}']
    /// Decodes Base32 string to binary
    // - returns '' if the input is not valid Base32
    function Base32Decode(const Encoded: RawUtf8): RawByteString;
    /// Encodes binary to Base32 string
    function Base32Encode(const Data: RawByteString): RawUtf8;
  end;

  /// Secret generator abstraction
  // - Generates cryptographically secure random secrets
  ISecretGenerator = interface
    ['{9CF6CF4B-F089-4EBE-81D6-DA974B326B68}']
    /// Generates a Base32-encoded secret of specified length
    // - Length: number of Base32 characters, rounded up to a multiple of 8
    // (8 Base32 characters encode exactly 5 bytes = 40 bits)
    // - any value below OTP_MIN_SECRET_CHARS (32 characters = 160 bits) is
    // raised to OTP_MIN_SECRET_CHARS, so the result never has less entropy
    // than RFC 4226 R6 requires
    function GenerateSecret(Length: Integer): RawUtf8;
  end;

  /// Main OTP provider interface
  // - Core abstraction for all OTP operations
  // - Supports both HOTP (counter-based) and TOTP (time-based)
  // - every function returning a code returns -1 on failure (invalid Digits,
  // undecodable secret, unusable HMAC...): -1 is never a valid code, whereas
  // 0 would be accepted as the valid code "000000"
  IOtpProvider = interface
    ['{947C6356-B67F-4232-93F7-0A8CF697C0F2}']
    /// Computes HOTP (counter-based OTP) from binary secret
    // - Secret: raw binary key (already decoded from Base32)
    // - Counter: counter value (for HOTP) or time step (for TOTP)
    // - Digits: number of digits in result (1..9, typically 6 or 8)
    // - returns -1 if Digits is out of range or the HMAC could not be computed
    function ComputeOTP(const Secret: RawByteString; Counter: Int64; Digits: Integer): Integer;

    /// Computes TOTP (time-based OTP) from Base32 secret
    // - Secret: Base32-encoded key string
    // - Digits: number of digits (default 6)
    // - Interval: time step in seconds (default 30)
    // - returns -1 if the secret, Digits or Interval is invalid
    function ComputeTOTP(const Secret: RawUtf8; Digits: Integer = OTP_DEFAULT_DIGITS;
      Interval: Integer = OTP_DEFAULT_INTERVAL): Integer;

    /// Verifies a user-supplied TOTP code and returns the time step it matched
    // - this is the function to use for authentication
    // - Secret: raw binary key (already decoded from Base32)
    // - Code: the code as typed by the user: exactly Digits ASCII digits, so
    // leading zeros are enforced and no sign, space or prefix is accepted
    // - UnixTime: the current time in seconds, supplied by the caller so that
    // the application clock can be used (must be >= 0)
    // - StepsBack/StepsForward: number of time steps accepted before/after the
    // current one (0..OTP_MAX_WINDOW_STEPS each, else the code is refused)
    // - MatchedStep: on success, the time step (UnixTime div Interval + delta)
    // that matched; the caller should persist it and refuse any later code
    // whose MatchedStep is not greater, which prevents replay of a code
    // - every step of the window is evaluated, with no early exit, so the
    // execution time does not reveal which step matched
    // - returns false if any parameter is invalid or no step matched
    function VerifyTOTPStep(const Secret: RawByteString; const Code: RawUtf8;
      UnixTime: Int64; StepsBack, StepsForward: Integer; out MatchedStep: Int64;
      Digits: Integer = OTP_DEFAULT_DIGITS; Interval: Integer = OTP_DEFAULT_INTERVAL): Boolean;

    /// Validates a TOTP token against a Base32 secret, at the provider time
    // - Secret: Base32-encoded key string
    // - Token: user-provided OTP code, as a number in 0..10^Digits-1
    // - WindowSize: number of time steps to check before and after the
    // current one (0..OTP_MAX_WINDOW_STEPS, else the token is refused)
    // - Returns True if token matches within the window
    // - a Boolean result cannot prevent the replay of a code during its
    // validity window, and an Integer token cannot enforce leading zeros:
    // prefer VerifyTOTPStep() + ParseOtpCode() for authentication
    function ValidateTOTP(const Secret: RawUtf8; Token: Integer; WindowSize: Integer = 1;
      Digits: Integer = OTP_DEFAULT_DIGITS; Interval: Integer = OTP_DEFAULT_INTERVAL): Boolean;
  end;


type
  /// Factory for creating OTP provider instances
  // - Provides convenient methods for common scenarios
  // - Supports full dependency injection for testing
  TOtpFactory = class
  public
    /// Creates OTP provider with default mORMot-based implementations
    // - Uses real time, HMAC-SHA1, mORMot Base32
    class function CreateDefault: IOtpProvider;

    /// Creates OTP provider with custom dependency implementations
    // - Allows injection of mock providers for testing
    // - TimeProvider: custom time source
    // - CryptoProvider: custom HMAC implementation
    // - EncodingProvider: custom Base32 encoder/decoder
    class function CreateWithProviders(
      ATimeProvider: ITimeProvider;
      ACryptoProvider: ICryptoProvider;
      AEncodingProvider: IEncodingProvider): IOtpProvider;

    /// Creates standalone secret generator, using the TAesPrng CSPRNG
    class function CreateSecretGenerator: ISecretGenerator;
  end;

/// Parses a user-supplied OTP code
// - accepts exactly Digits ASCII characters in '0'..'9', and nothing else:
// no sign, no space, no hexadecimal or octal prefix, no Unicode digit, so the
// leading zeros of the code are enforced
// - Digits must be in 1..9
// - returns true and sets Value to the numerical code on success
// - returns false and sets Value to -1 on failure
function ParseOtpCode(const Code: RawUtf8; Digits: Integer; out Value: Integer): Boolean;

/// Formats a numerical OTP code with its leading zeros, e.g. 81804 -> '081804'
// - returns '' if Code is negative or Digits is not in 1..9
function FormatOtpCode(Code, Digits: Integer): RawUtf8;

/// Builds an otpauth://totp/ URI for enrollment in authenticator applications
// - Issuer and Account are percent-encoded (RFC 3986 unreserved set only, with
// a space as %20), so a user-supplied account name cannot inject parameters
// - Issuer is used both as label prefix and as the issuer= parameter, as
// recommended by the Key Uri Format; it may be ''
// - Secret is the Base32 secret; any '=' padding is removed
// - returns '' if Secret is '' or Digits/Period are out of range
function BuildOtpAuthUri(const Issuer, Account, Secret: RawUtf8;
  Digits: Integer = OTP_DEFAULT_DIGITS; Period: Integer = OTP_DEFAULT_INTERVAL): RawUtf8;


implementation


type
  /// Real-time provider using mORMot's UnixTimeUtc
  TUnixTimeProvider = class(TInterfacedObject, ITimeProvider)
  public
    function GetCurrentUnixTime: Int64;
  end;

  /// HMAC-SHA1 provider using mORMot cryptography
  TMormotHmacSha1Provider = class(TInterfacedObject, ICryptoProvider)
  public
    function ComputeHmac(const Key: RawByteString; const Data; DataLen: Integer): RawByteString;
  end;

  /// Base32 encoder/decoder using mORMot's Base32ToBin/BinToBase32
  TMormotBase32Provider = class(TInterfacedObject, IEncodingProvider)
  public
    function Base32Decode(const Encoded: RawUtf8): RawByteString;
    function Base32Encode(const Data: RawByteString): RawUtf8;
  end;

  /// Secure secret generator using mORMot's cryptographic PRNG
  TSecureSecretGenerator = class(TInterfacedObject, ISecretGenerator)
  public
    function GenerateSecret(Length: Integer): RawUtf8;
  end;

type
  /// OTP service implementation with injected dependencies
  // - Pure algorithm logic, no hardcoded dependencies
  TOtpService = class(TInterfacedObject, IOtpProvider)
  private
    fTimeProvider: ITimeProvider;
    fCryptoProvider: ICryptoProvider;
    fEncodingProvider: IEncodingProvider;
    function VerifyCode(const Secret: RawByteString; Code: Integer;
      Counter: Int64; StepsBack, StepsForward, Digits: Integer;
      out MatchedStep: Int64): Boolean;
  public
    constructor Create(
      ATimeProvider: ITimeProvider;
      ACryptoProvider: ICryptoProvider;
      AEncodingProvider: IEncodingProvider);

    function ComputeOTP(const Secret: RawByteString; Counter: Int64; Digits: Integer): Integer;
    function ComputeTOTP(const Secret: RawUtf8; Digits: Integer = OTP_DEFAULT_DIGITS;
      Interval: Integer = OTP_DEFAULT_INTERVAL): Integer;
    function VerifyTOTPStep(const Secret: RawByteString; const Code: RawUtf8;
      UnixTime: Int64; StepsBack, StepsForward: Integer; out MatchedStep: Int64;
      Digits: Integer = OTP_DEFAULT_DIGITS; Interval: Integer = OTP_DEFAULT_INTERVAL): Boolean;
    function ValidateTOTP(const Secret: RawUtf8; Token: Integer; WindowSize: Integer = 1;
      Digits: Integer = OTP_DEFAULT_DIGITS; Interval: Integer = OTP_DEFAULT_INTERVAL): Boolean;
  end;

const
  // Precomputed powers of 10 for efficient modulo
  POW10: array[0..9] of Cardinal = (
    1, 10, 100, 1000, 10000, 100000,
    1000000, 10000000, 100000000, 1000000000
  );


{ TUnixTimeProvider }

function TUnixTimeProvider.GetCurrentUnixTime: Int64;
begin
  Result := UnixTimeUtc;
end;

{ TMormotHmacSha1Provider }

function TMormotHmacSha1Provider.ComputeHmac(const Key: RawByteString;
  const Data; DataLen: Integer): RawByteString;
var
  Hash: THash512Rec;
begin
  // Compute HMAC-SHA1 using mORMot's Hmac function
  Hmac(saSha1, pointer(Key), @Data, Length(Key), DataLen, @Hash);
  // Extract first 20 bytes (SHA-1 digest size)
  SetLength(Result, 20);
  MoveFast(Hash, pointer(Result)^, 20);
  FillZero(Hash.b);
end;

{ TMormotBase32Provider }

function TMormotBase32Provider.Base32Decode(const Encoded: RawUtf8): RawByteString;
begin
  Result := Base32ToBin(Encoded);
end;

function TMormotBase32Provider.Base32Encode(const Data: RawByteString): RawUtf8;
begin
  Result := BinToBase32(Data);
end;

{ TSecureSecretGenerator }

function TSecureSecretGenerator.GenerateSecret(Length: Integer): RawUtf8;
var
  Bytes: RawByteString;
  ByteCount: Integer;
begin
  // Length is the desired number of Base32 output characters.
  // Base32ToBin() requires the input length to be a multiple of 8
  // (each group of 8 chars encodes exactly 5 bytes).
  if Length < OTP_MIN_SECRET_CHARS then
    Length := OTP_MIN_SECRET_CHARS; // 32 chars = 20 bytes = 160 bits
  // Round up to the nearest multiple of 8
  Length := (Length + 7) and (not 7);
  // Generate the corresponding random bytes from the CSPRNG, then encode
  ByteCount := (Length shr 3) * 5; // 8 chars -> 5 bytes
  SetLength(Bytes, ByteCount);
  TAesPrng.Main.FillRandom(pointer(Bytes), ByteCount);
  Result := BinToBase32(Bytes);
  FillZero(Bytes);
end;

{ TOtpService }

constructor TOtpService.Create(ATimeProvider: ITimeProvider;
  ACryptoProvider: ICryptoProvider; AEncodingProvider: IEncodingProvider);
begin
  inherited Create;
  fTimeProvider := ATimeProvider;
  fCryptoProvider := ACryptoProvider;
  fEncodingProvider := AEncodingProvider;
end;

function TOtpService.ComputeOTP(const Secret: RawByteString; Counter: Int64;
  Digits: Integer): Integer;
var
  CounterBE: Int64;
  Hash: RawByteString;
  Offset: Integer;
  BinCode: Cardinal;
begin
  // Validate inputs: an unsupported digit count is an error, not "6"
  if (Digits < 1) or (Digits > 9) then
    Exit(-1);

  // Convert counter to big-endian (network byte order)
  CounterBE := bswap64(Counter);

  // Compute HMAC of counter
  Hash := fCryptoProvider.ComputeHmac(Secret, CounterBE, SizeOf(CounterBE));

  // Validate hash length: fail closed (0 would be the valid code "000000")
  if Length(Hash) < 20 then
    Exit(-1);

  // Dynamic truncation per RFC 4226
  // RawByteString is 1-based, so indices are 1..20 for SHA-1
  // the offset is the low nibble of the last byte, i.e. always in 0..15,
  // so the 4 bytes at Offset+1..Offset+4 are always within the digest
  Offset := Ord(Hash[20]) and $0F;

  BinCode :=
    (Cardinal(Ord(Hash[Offset + 1])) and $7F) shl 24 or
    (Cardinal(Ord(Hash[Offset + 2])) and $FF) shl 16 or
    (Cardinal(Ord(Hash[Offset + 3])) and $FF) shl 8 or
    (Cardinal(Ord(Hash[Offset + 4])) and $FF);

  // Modulo to get N digits
  Result := Integer(BinCode mod POW10[Digits]);
  FillZero(Hash);
end;

function TOtpService.ComputeTOTP(const Secret: RawUtf8; Digits, Interval: Integer): Integer;
var
  SecretBin: RawByteString;
  Counter: Int64;
begin
  // Validate inputs
  if (Interval <= 0) or
     (Digits < 1) or (Digits > 9) then
    Exit(-1);

  // Decode Base32 secret
  SecretBin := fEncodingProvider.Base32Decode(Secret);
  if SecretBin = '' then
    Exit(-1);

  // Calculate time-based counter
  Counter := fTimeProvider.GetCurrentUnixTime div Interval;

  // Compute OTP using counter
  Result := ComputeOTP(SecretBin, Counter, Digits);
  FillZero(SecretBin);
end;

function TOtpService.VerifyCode(const Secret: RawByteString; Code: Integer;
  Counter: Int64; StepsBack, StepsForward, Digits: Integer;
  out MatchedStep: Int64): Boolean;
var
  Step, Expected: Integer;
  Found, Hit, Take: Integer;
  Candidate: Int64;
begin
  // Every step of the window is evaluated: no early exit, no data-dependent
  // branch on the comparison, so the timing does not reveal which step matched
  Found := 0;
  MatchedStep := 0;
  for Step := -StepsBack to StepsForward do
  begin
    Candidate := Counter + Step;
    Expected := ComputeOTP(Secret, Candidate, Digits);
    if Expected < 0 then
    begin
      // provider failure: it does not depend on the code, so exiting is safe
      MatchedStep := 0;
      Exit(False);
    end;
    Hit := Ord(Expected = Code);     // 1 if this step matches, 0 otherwise
    Take := Hit and (Found xor 1);   // keep the first matching step only
    MatchedStep := MatchedStep or (Candidate and (-Int64(Take)));
    Found := Found or Hit;
  end;
  Result := Found <> 0;
end;

function TOtpService.VerifyTOTPStep(const Secret: RawByteString; const Code: RawUtf8;
  UnixTime: Int64; StepsBack, StepsForward: Integer; out MatchedStep: Int64;
  Digits, Interval: Integer): Boolean;
var
  Value: Integer;
begin
  Result := False;
  MatchedStep := 0;

  // Validate every parameter before touching the secret
  if (Secret = '') or
     (UnixTime < 0) or
     (Interval <= 0) or
     (Digits < 1) or (Digits > 9) or
     (StepsBack < 0) or (StepsBack > OTP_MAX_WINDOW_STEPS) or
     (StepsForward < 0) or (StepsForward > OTP_MAX_WINDOW_STEPS) then
    Exit;

  // Strict parsing: exactly Digits ASCII digits
  if not ParseOtpCode(Code, Digits, Value) then
    Exit;

  Result := VerifyCode(Secret, Value, UnixTime div Interval,
    StepsBack, StepsForward, Digits, MatchedStep);
end;

function TOtpService.ValidateTOTP(const Secret: RawUtf8; Token, WindowSize,
  Digits, Interval: Integer): Boolean;
var
  SecretBin: RawByteString;
  MatchedStep: Int64;
begin
  Result := False;

  // Validate inputs: a negative window is an error, not its absolute value,
  // and the window is bounded so that the number of HMAC is bounded too
  if (WindowSize < 0) or (WindowSize > OTP_MAX_WINDOW_STEPS) or
     (Interval <= 0) or
     (Digits < 1) or (Digits > 9) or
     (Token < 0) or (Cardinal(Token) >= POW10[Digits]) then
    Exit;

  // Decode secret
  SecretBin := fEncodingProvider.Base32Decode(Secret);
  if SecretBin = '' then
    Exit;

  // Check current time step +/- window
  Result := VerifyCode(SecretBin, Token, fTimeProvider.GetCurrentUnixTime div Interval,
    WindowSize, WindowSize, Digits, MatchedStep);
  FillZero(SecretBin);
end;

{ TOtpFactory }

class function TOtpFactory.CreateDefault: IOtpProvider;
begin
  Result := TOtpService.Create(
    TUnixTimeProvider.Create,
    TMormotHmacSha1Provider.Create,
    TMormotBase32Provider.Create
  );
end;

class function TOtpFactory.CreateWithProviders(ATimeProvider: ITimeProvider;
  ACryptoProvider: ICryptoProvider; AEncodingProvider: IEncodingProvider): IOtpProvider;
begin
  Result := TOtpService.Create(ATimeProvider, ACryptoProvider, AEncodingProvider);
end;

class function TOtpFactory.CreateSecretGenerator: ISecretGenerator;
begin
  Result := TSecureSecretGenerator.Create;
end;


{ global functions }

function ParseOtpCode(const Code: RawUtf8; Digits: Integer; out Value: Integer): Boolean;
var
  i: Integer;
  c: AnsiChar;
begin
  Result := False;
  Value := -1;
  if (Digits < 1) or (Digits > 9) or
     (Length(Code) <> Digits) then
    Exit;
  Value := 0;
  for i := 1 to Digits do
  begin
    c := Code[i];
    if (c < '0') or (c > '9') then
    begin
      Value := -1;
      Exit;
    end;
    Value := Value * 10 + (Ord(c) - Ord('0'));
  end;
  Result := True;
end;

function FormatOtpCode(Code, Digits: Integer): RawUtf8;
begin
  if (Code < 0) or (Digits < 1) or (Digits > 9) or
     (Cardinal(Code) >= POW10[Digits]) then
    Exit('');
  Result := UInt32ToUtf8(Code);
  if Length(Result) < Digits then
    Result := RawUtf8(StringOfChar(AnsiChar('0'), Digits - Length(Result))) + Result;
end;

// RFC 3986 percent-encoding: everything but the unreserved set is encoded,
// a space becomes %20 (not '+'), which is what the otpauth label requires
function PercentEncode(const Text: RawUtf8): RawUtf8;
const
  HEX: array[0..15] of AnsiChar = '0123456789ABCDEF';
var
  i, n: Integer;
  c: AnsiChar;
begin
  Result := '';
  n := 0;
  for i := 1 to Length(Text) do
    if Text[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~'] then
      Inc(n)
    else
      Inc(n, 3);
  SetLength(Result, n);
  n := 1;
  for i := 1 to Length(Text) do
  begin
    c := Text[i];
    if c in ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~'] then
    begin
      Result[n] := c;
      Inc(n);
    end
    else
    begin
      Result[n] := '%';
      Result[n + 1] := HEX[Ord(c) shr 4];
      Result[n + 2] := HEX[Ord(c) and $0F];
      Inc(n, 3);
    end;
  end;
end;

function BuildOtpAuthUri(const Issuer, Account, Secret: RawUtf8;
  Digits, Period: Integer): RawUtf8;
var
  Key: RawUtf8;
begin
  Result := '';
  if (Secret = '') or
     (Digits < 1) or (Digits > 9) or
     (Period <= 0) then
    Exit;
  Key := Secret;
  while (Key <> '') and (Key[Length(Key)] = '=') do
    SetLength(Key, Length(Key) - 1);
  if Key = '' then
    Exit;
  Result := 'otpauth://totp/';
  if Issuer <> '' then
    Result := Result + PercentEncode(Issuer) + ':';
  Result := Result + PercentEncode(Account) + '?secret=' + PercentEncode(Key);
  if Issuer <> '' then
    Result := Result + '&issuer=' + PercentEncode(Issuer);
  Result := Result + '&algorithm=SHA1&digits=' + UInt32ToUtf8(Digits) +
    '&period=' + UInt32ToUtf8(Period);
end;

end.

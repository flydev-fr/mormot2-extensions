unit mormot.ext.otp;

// -----------------------------------------------------------------------------
// RFC 4226/6238-compatible HOTP/TOTP unit (HMAC-SHA1 profile)
// -----------------------------------------------------------------------------

{$I mormot.defines.inc}

interface

uses
  mormot.core.base,
  mormot.core.os,
  mormot.core.buffers,
  mormot.crypt.core,
  mormot.crypt.secure;

type
  /// Time provider abstraction for testability
  // - Allows injection of mock time providers in tests
  ITimeProvider = interface
    ['{8B3C1A2D-4E5F-6789-ABCD-EF0123456789}']
    /// Returns current Unix timestamp in seconds
    function GetCurrentUnixTime: Int64;
  end;

  /// Cryptographic operations abstraction
  // - Decouples OTP logic from specific crypto implementations
  // - Enables testing with mock crypto or alternative algorithms
  ICryptoProvider = interface
    ['{9C4D2B3E-5F60-7890-BCDE-F01234567890}']
    /// Computes HMAC hash of data with given key
    // - Returns raw hash bytes (20 bytes for SHA1, 32 for SHA256, etc.)
    function ComputeHmac(const Key: RawByteString; const Data; DataLen: Integer): RawByteString;
  end;

  /// Base32 encoding/decoding abstraction
  // - RFC 4648 Base32 encoding for OTP secrets
  IEncodingProvider = interface
    ['{AD5E3C4F-6071-8901-CDEF-012345678901}']
    /// Decodes Base32 string to binary
    function Base32Decode(const Encoded: RawUtf8): RawByteString;
    /// Encodes binary to Base32 string
    function Base32Encode(const Data: RawByteString): RawUtf8;
  end;

  /// Secret generator abstraction
  // - Generates cryptographically secure random secrets
  ISecretGenerator = interface
    ['{BE6F4D50-7182-9012-DEF0-123456789012}']
    /// Generates a Base32-encoded secret of specified length
    // - Length: number of Base32 characters (default 20 = ~100 bits)
    function GenerateSecret(Length: Integer): RawUtf8;
  end;

  /// Main OTP provider interface
  // - Core abstraction for all OTP operations
  // - Supports both HOTP (counter-based) and TOTP (time-based)
  IOtpProvider = interface
    ['{CF705E61-8293-0123-EF01-234567890123}']
    /// Computes HOTP (counter-based OTP) from binary secret
    // - Secret: raw binary key (already decoded from Base32)
    // - Counter: counter value (for HOTP) or time step (for TOTP)
    // - Digits: number of digits in result (typically 6 or 8)
    function ComputeOTP(const Secret: RawByteString; Counter: Int64; Digits: Integer): Integer;
    
    /// Computes TOTP (time-based OTP) from Base32 secret
    // - Secret: Base32-encoded key string
    // - Digits: number of digits (default 6)
    // - Interval: time step in seconds (default 30)
    function ComputeTOTP(const Secret: RawUtf8; Digits: Integer = 6; Interval: Integer = 30): Integer;
    
    /// Validates a TOTP token against a secret
    // - Secret: Base32-encoded key string
    // - Token: user-provided OTP code
    // - WindowSize: number of time steps to check before/after current (default 1)
    // - Returns True if token matches within the window
    function ValidateTOTP(const Secret: RawUtf8; Token: Integer; WindowSize: Integer = 1): Boolean;
  end;


type
  /// Factory for creating OTP provider instances
  // - Provides convenient methods for common scenarios
  // - Supports full dependency injection for testing
  TOtpFactory = class
  public
    /// Creates OTP provider with default mORMot-based implementations
    // - Uses real time, HMAC-SHA1, mORMot Base32, secure PRNG
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
    
    /// Creates standalone secret generator
    class function CreateSecretGenerator: ISecretGenerator;
  end;

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
  public
    constructor Create(
      ATimeProvider: ITimeProvider;
      ACryptoProvider: ICryptoProvider;
      AEncodingProvider: IEncodingProvider);
    
    function ComputeOTP(const Secret: RawByteString; Counter: Int64; Digits: Integer): Integer;
    function ComputeTOTP(const Secret: RawUtf8; Digits: Integer = 6; Interval: Integer = 30): Integer;
    function ValidateTOTP(const Secret: RawUtf8; Token: Integer; WindowSize: Integer = 1): Boolean;
  end;


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
  ByteCount, i: Integer;
begin
  // Length is the desired number of Base32 output characters.
  // Base32ToBin() requires the input length to be a multiple of 8
  // (each group of 8 chars encodes exactly 5 bytes).
  if Length < 8 then
    Length := 32; // Default: 32 chars = 20 bytes = 160 bits
  // Round up to the nearest multiple of 8
  Length := (Length + 7) and (not 7);
  // Generate the corresponding random bytes, then encode
  ByteCount := (Length shr 3) * 5; // 8 chars -> 5 bytes
  SetLength(Bytes, ByteCount);
  for i := 1 to ByteCount do
    Bytes[i] := AnsiChar(Random32(256));
  Result := BinToBase32(Bytes);
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
const
  // Precomputed powers of 10 for efficient modulo
  POW10: array[0..9] of Cardinal = (
    1, 10, 100, 1000, 10000, 100000,
    1000000, 10000000, 100000000, 1000000000
  );
var
  CounterBE: Int64;
  Hash: RawByteString;
  Offset: Integer;
  BinCode: Cardinal;
begin
  // Validate inputs
  if (Digits < 1) or (Digits > 9) then
    Digits := 6;
    
  // Convert counter to big-endian (network byte order)
  CounterBE := bswap64(Counter);
  
  // Compute HMAC of counter
  Hash := fCryptoProvider.ComputeHmac(Secret, CounterBE, SizeOf(CounterBE));
  
  // Validate hash length
  if Length(Hash) < 20 then
    Exit(0);
  
  // Dynamic truncation per RFC 4226
  // RawByteString is 1-based, so indices are 1..20 for SHA-1
  Offset := Ord(Hash[20]) and $0F;  // Last byte is at index 20
  
  // Ensure we don't read beyond hash bounds (need 4 bytes starting at Offset+1)
  if Offset > 15 then  // Maximum offset should be 15 (indices 16-19)
    Offset := 15;
  
  BinCode :=
    (Cardinal(Ord(Hash[Offset + 1])) and $7F) shl 24 or
    (Cardinal(Ord(Hash[Offset + 2])) and $FF) shl 16 or
    (Cardinal(Ord(Hash[Offset + 3])) and $FF) shl 8 or
    (Cardinal(Ord(Hash[Offset + 4])) and $FF);
  
  // Modulo to get N digits
  Result := Integer(BinCode mod POW10[Digits]);
end;

function TOtpService.ComputeTOTP(const Secret: RawUtf8; Digits, Interval: Integer): Integer;
var
  SecretBin: RawByteString;
  Counter: Int64;
begin
  // Decode Base32 secret
  SecretBin := fEncodingProvider.Base32Decode(Secret);
  if SecretBin = '' then
    Exit(0);
    
  // Validate interval
  if Interval <= 0 then
    Interval := 30;
    
  // Calculate time-based counter
  Counter := fTimeProvider.GetCurrentUnixTime div Interval;
  
  // Compute OTP using counter
  Result := ComputeOTP(SecretBin, Counter, Digits);
end;

function TOtpService.ValidateTOTP(const Secret: RawUtf8; Token, WindowSize: Integer): Boolean;
var
  SecretBin: RawByteString;
  Counter: Int64;
  Step: Integer;
  Expected: Integer;
const
  DEFAULT_INTERVAL = 30;
  DEFAULT_DIGITS = 6;
begin
  Result := False;
  
  // Decode secret
  SecretBin := fEncodingProvider.Base32Decode(Secret);
  if SecretBin = '' then
    Exit;
    
  // Get current time counter
  Counter := fTimeProvider.GetCurrentUnixTime div DEFAULT_INTERVAL;
  
  // Check current time step ± window
  for Step := -Abs(WindowSize) to Abs(WindowSize) do
  begin
    Expected := ComputeOTP(SecretBin, Counter + Step, DEFAULT_DIGITS);
    if Expected = Token then
      Exit(True);
  end;
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

end.


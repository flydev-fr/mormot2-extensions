object FormOTP: TFormOTP
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'One Time Password Demo'
  ClientHeight = 387
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  FormStyle = fsStayOnTop
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 13
  object GrpSecret: TGroupBox
    Left = 8
    Top = 8
    Width = 444
    Height = 113
    Caption = 'Secret Key'
    TabOrder = 0
    object LblKey: TLabel
      Left = 12
      Top = 20
      Width = 59
      Height = 13
      Caption = 'Base32 key:'
    end
    object LblUrl: TLabel
      Left = 12
      Top = 64
      Width = 191
      Height = 13
      Caption = 'OTP Auth URL (for authenticator apps):'
    end
    object EdtKey: TEdit
      Left = 12
      Top = 36
      Width = 322
      Height = 21
      TabOrder = 0
      Text = 'C6ES2M3TXQTOYMMC43HUGQ6D66BVHUCM'
      OnChange = EdtKeyChange
    end
    object BtnNewKey: TButton
      Left = 342
      Top = 34
      Width = 90
      Height = 25
      Caption = 'New Key'
      TabOrder = 1
      OnClick = BtnNewKeyClick
    end
    object EdtOtpUrl: TEdit
      Left = 12
      Top = 79
      Width = 322
      Height = 21
      ReadOnly = True
      TabOrder = 2
    end
    object BtnCopyUrl: TButton
      Left = 342
      Top = 77
      Width = 90
      Height = 25
      Caption = 'Copy URL'
      TabOrder = 3
      OnClick = BtnCopyUrlClick
    end
  end
  object GrpTOTP: TGroupBox
    Left = 8
    Top = 127
    Width = 444
    Height = 82
    Caption = 'Time-Based OTP (TOTP)'
    TabOrder = 1
    object LblTOTPCaption: TLabel
      Left = 12
      Top = 22
      Width = 67
      Height = 13
      Caption = 'Current code:'
    end
    object LblTOTPCode: TLabel
      Left = 12
      Top = 38
      Width = 152
      Height = 27
      AutoSize = False
      Caption = '------'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -24
      Font.Name = 'Courier New'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LblTimeCaption: TLabel
      Left = 178
      Top = 22
      Width = 75
      Height = 13
      Caption = 'Time remaining:'
    end
    object LblTimeRemaining: TLabel
      Left = 402
      Top = 40
      Width = 34
      Height = 13
      Alignment = taRightJustify
      AutoSize = False
      Caption = '30 s'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object PrgTime: TProgressBar
      Left = 178
      Top = 40
      Width = 218
      Height = 16
      Max = 30
      Smooth = True
      TabOrder = 0
    end
  end
  object GrpHOTP: TGroupBox
    Left = 8
    Top = 215
    Width = 444
    Height = 59
    Caption = 'Counter-Based OTP (HOTP)'
    TabOrder = 2
    object LblCounterCaption: TLabel
      Left = 12
      Top = 24
      Width = 43
      Height = 13
      Caption = 'Counter:'
    end
    object LblHOTPCaption: TLabel
      Left = 270
      Top = 24
      Width = 34
      Height = 13
      Caption = 'Result:'
    end
    object EdtCounter: TEdit
      Left = 68
      Top = 20
      Width = 64
      Height = 21
      NumbersOnly = True
      TabOrder = 0
      Text = '0'
    end
    object BtnCalcHOTP: TButton
      Left = 142
      Top = 18
      Width = 116
      Height = 25
      Caption = 'Calculate HOTP'
      TabOrder = 1
      OnClick = BtnCalcHOTPClick
    end
    object EdtHOTPResult: TEdit
      Left = 314
      Top = 20
      Width = 118
      Height = 21
      ReadOnly = True
      TabOrder = 2
    end
  end
  object GrpValidate: TGroupBox
    Left = 8
    Top = 280
    Width = 444
    Height = 96
    Caption = 'Validate Token'
    TabOrder = 3
    object LblTokenCaption: TLabel
      Left = 12
      Top = 24
      Width = 89
      Height = 13
      Caption = 'Enter TOTP token:'
    end
    object LblValidResult: TLabel
      Left = 12
      Top = 56
      Width = 420
      Height = 28
      AutoSize = False
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
      WordWrap = True
    end
    object EdtValidToken: TEdit
      Left = 118
      Top = 20
      Width = 72
      Height = 21
      MaxLength = 8
      NumbersOnly = True
      TabOrder = 0
    end
    object BtnValidate: TButton
      Left = 200
      Top = 18
      Width = 132
      Height = 25
      Caption = 'Validate TOTP Token'
      Default = True
      TabOrder = 1
      OnClick = BtnValidateClick
    end
  end
  object Timer1: TTimer
    Interval = 500
    OnTimer = Timer1Timer
    Left = 396
    Top = 124
  end
end

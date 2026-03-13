object FormMarkdownDemo: TFormMarkdownDemo
  Left = 0
  Top = 0
  Caption = 'mormot.ext.markdown - VCL Demo'
  ClientHeight = 560
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object Splitter: TSplitter
    Left = 400
    Top = 41
    Width = 5
    Height = 519
    ResizeStyle = rsUpdate
  end
  object PanelTop: TPanel
    Left = 0
    Top = 0
    Width = 900
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    ExplicitWidth = 898
    object LabelDialect: TLabel
      Left = 112
      Top = 12
      Width = 39
      Height = 15
      Caption = 'Dialect:'
    end
    object BtnConvert: TButton
      Left = 8
      Top = 8
      Width = 90
      Height = 25
      Caption = 'Convert'
      Default = True
      TabOrder = 0
      OnClick = BtnConvertClick
    end
    object ComboDialect: TComboBox
      Left = 160
      Top = 9
      Width = 140
      Height = 23
      Style = csDropDownList
      TabOrder = 1
    end
    object CheckSafe: TCheckBox
      Left = 320
      Top = 12
      Width = 80
      Height = 17
      Caption = 'Safe mode'
      TabOrder = 2
    end
  end
  object PanelLeft: TPanel
    Left = 0
    Top = 41
    Width = 400
    Height = 519
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 1
    ExplicitHeight = 511
    object MemoMarkdown: TMemo
      Left = 0
      Top = 0
      Width = 400
      Height = 519
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      ScrollBars = ssBoth
      TabOrder = 0
    end
  end
  object PanelRight: TPanel
    Left = 405
    Top = 41
    Width = 495
    Height = 519
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    ExplicitWidth = 493
    ExplicitHeight = 511
    object WebBrowser: TWebBrowser
      Left = 0
      Top = 0
      Width = 495
      Height = 519
      Align = alClient
      TabOrder = 0
      ExplicitWidth = 493
      ExplicitHeight = 511
      ControlData = {
        4C000000EE280000EA2A00000000000000000000000000000000000000000000
        000000004C000000000000000000000001000000E0D057007335CF11AE690800
        2B2E126208000000000000004C0000000114020000000000C000000000000046
        8000000000000000000000000000000000000000000000000000000000000000
        00000000000000000100000000000000000000000000000000000000}
    end
  end
end

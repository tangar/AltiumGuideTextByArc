object TextByArcForm: TTextByArcForm
  Left = 120
  Top = 90
  BorderStyle = bsDialog
  Caption = 'Text Along Arc'
  ClientHeight = 528
  ClientWidth = 520
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = TextByArcFormCreate
  OnShow = TextByArcFormShow
  OnHide = TextByArcFormHide
  PixelsPerInch = 96
  TextHeight = 13
  object gbText: TGroupBox
    Left = 8
    Top = 6
    Width = 504
    Height = 74
    Caption = ' Text '
    TabOrder = 0
    object memoText: TMemo
      Left = 8
      Top = 17
      Width = 488
      Height = 50
      ScrollBars = ssVertical
      TabOrder = 0
      WordWrap = True
      Lines.Strings = (
        'VECTOR SUPER SPIRAL')
    end
  end
  object gbArc: TGroupBox
    Left = 8
    Top = 86
    Width = 504
    Height = 96
    Caption = ' Arc '
    TabOrder = 1
    object lblCx: TLabel
      Left = 12
      Top = 24
      Width = 47
      Height = 13
      Caption = 'Center X:'
    end
    object eCx: TEdit
      Left = 66
      Top = 20
      Width = 88
      Height = 21
      TabOrder = 0
      Text = '0'
    end
    object lblCy: TLabel
      Left = 164
      Top = 24
      Width = 47
      Height = 13
      Caption = 'Center Y:'
    end
    object eCy: TEdit
      Left = 216
      Top = 20
      Width = 88
      Height = 21
      TabOrder = 1
      Text = '0'
    end
    object lblR: TLabel
      Left = 314
      Top = 24
      Width = 44
      Height = 13
      Caption = 'Radius:'
    end
    object eR: TEdit
      Left = 362
      Top = 20
      Width = 64
      Height = 21
      TabOrder = 2
      Text = '30'
    end
    object lblA1: TLabel
      Left = 12
      Top = 58
      Width = 88
      Height = 13
      Caption = 'Start angle:'
    end
    object eA1: TEdit
      Left = 112
      Top = 54
      Width = 64
      Height = 21
      TabOrder = 3
      Text = '180'
    end
    object lblA2: TLabel
      Left = 186
      Top = 58
      Width = 84
      Height = 13
      Caption = 'End angle:'
    end
    object eA2: TEdit
      Left = 282
      Top = 54
      Width = 64
      Height = 21
      TabOrder = 4
      Text = '0'
    end
    object btnArc: TButton
      Left = 370
      Top = 50
      Width = 122
      Height = 25
      Caption = 'From arc'
      TabOrder = 5
      OnClick = btnArcClick
    end
  end
  object gbStyle: TGroupBox
    Left = 8
    Top = 188
    Width = 504
    Height = 150
    Caption = ' Style '
    TabOrder = 2
    object lblH: TLabel
      Left = 12
      Top = 24
      Width = 46
      Height = 13
      Caption = 'Height:'
    end
    object eHeight: TEdit
      Left = 62
      Top = 20
      Width = 56
      Height = 21
      TabOrder = 0
      Text = '3'
    end
    object lblGap: TLabel
      Left = 132
      Top = 24
      Width = 41
      Height = 13
      Caption = 'Gap:'
    end
    object eGap: TEdit
      Left = 176
      Top = 20
      Width = 56
      Height = 21
      TabOrder = 1
      Text = '0.5'
    end
    object lblShift: TLabel
      Left = 248
      Top = 24
      Width = 41
      Height = 13
      Caption = 'Shift:'
    end
    object eShift: TEdit
      Left = 294
      Top = 20
      Width = 56
      Height = 21
      TabOrder = 2
      Text = '0'
    end
    object lblShiftHint: TLabel
      Left = 362
      Top = 24
      Width = 130
      Height = 13
      Caption = '+ out, - in'
    end
    object rbOut: TRadioButton
      Left = 12
      Top = 58
      Width = 140
      Height = 17
      Caption = 'Clockwise'
      Checked = True
      TabOrder = 3
    end
    object rbIn: TRadioButton
      Left = 160
      Top = 58
      Width = 140
      Height = 17
      Caption = 'CCW'
      TabOrder = 4
    end
    object cbFit: TCheckBox
      Left = 310
      Top = 58
      Width = 180
      Height = 17
      Caption = 'Fit to arc'
      Checked = True
      TabOrder = 5
    end
    object lblStroke: TLabel
      Left = 12
      Top = 122
      Width = 48
      Height = 13
      Caption = 'Thickness:'
    end
    object eStroke: TEdit
      Left = 62
      Top = 118
      Width = 56
      Height = 21
      TabOrder = 7
      Text = '0'
    end
    object lblStrokeHint: TLabel
      Left = 132
      Top = 122
      Width = 300
      Height = 13
      Caption = 'stroke font only, 0 = default'
    end
    object lblUnits: TLabel
      Left = 12
      Top = 92
      Width = 52
      Height = 13
      Caption = 'Units:'
    end
    object pnlUnits: TPanel
      Left = 70
      Top = 86
      Width = 190
      Height = 21
      BevelOuter = bvNone
      Caption = ''
      TabOrder = 6
      object rbMil: TRadioButton
        Left = 6
        Top = 2
        Width = 70
        Height = 17
        Caption = 'Mil'
        TabOrder = 0
        OnClick = rbUnitsClick
      end
      object rbMM: TRadioButton
        Left = 82
        Top = 2
        Width = 100
        Height = 17
        Caption = 'Millimeters'
        Checked = True
        TabOrder = 1
        OnClick = rbUnitsClick
      end
    end
    object lblUnitsHint: TLabel
      Left = 262
      Top = 92
      Width = 230
      Height = 13
      Caption = 'lengths in chosen units'
    end
  end
  object gbExport: TGroupBox
    Left = 8
    Top = 344
    Width = 504
    Height = 100
    Caption = ' Layer and font '
    TabOrder = 3
    object lblLayer: TLabel
      Left = 12
      Top = 26
      Width = 36
      Height = 13
      Caption = 'Layer:'
    end
    object cbLayer: TComboBox
      Left = 52
      Top = 22
      Width = 200
      Height = 21
      Style = csDropDownList
      TabOrder = 0
    end
    object lblFont: TLabel
      Left = 264
      Top = 26
      Width = 48
      Height = 13
      Caption = 'Font:'
    end
    object cbFont: TComboBox
      Left = 316
      Top = 22
      Width = 176
      Height = 21
      Style = csDropDown
      TabOrder = 1
      Text = 'Stroke (Altium)'
    end
    object cbMirror: TCheckBox
      Left = 12
      Top = 54
      Width = 300
      Height = 17
      Caption = 'Mirror (bottom side)'
      TabOrder = 2
    end
  end
  object lblMsg: TLabel
    Left = 8
    Top = 450
    Width = 504
    Height = 36
    AutoSize = False
    Caption = ''
    WordWrap = True
  end
  object btnHelp: TButton
    Left = 8
    Top = 492
    Width = 90
    Height = 27
    Caption = 'Help'
    TabOrder = 4
    OnClick = btnHelpClick
  end
  object btnUndo: TButton
    Left = 104
    Top = 492
    Width = 100
    Height = 27
    Caption = 'Undo'
    Enabled = False
    TabOrder = 5
    OnClick = btnUndoClick
  end
  object btnUndoAll: TButton
    Left = 206
    Top = 492
    Width = 100
    Height = 27
    Caption = 'Undo all'
    Enabled = False
    TabOrder = 6
    OnClick = btnUndoAllClick
  end
  object btnPlace: TButton
    Left = 308
    Top = 492
    Width = 100
    Height = 27
    Caption = 'Place'
    Default = True
    TabOrder = 7
    OnClick = btnPlaceClick
  end
  object btnClose: TButton
    Left = 408
    Top = 492
    Width = 104
    Height = 27
    Cancel = True
    Caption = 'Close'
    ModalResult = 2
    TabOrder = 8
    OnClick = btnCloseClick
  end
end

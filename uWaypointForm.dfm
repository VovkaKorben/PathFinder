object WaypointForm: TWaypointForm
  Left = 0
  Top = 0
  Caption = 'Waypoint Navigator'
  ClientHeight = 451
  ClientWidth = 659
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  OnCreate = FormCreate
  OnShow = FormShow
  DesignSize = (
    659
    451)
  PixelsPerInch = 96
  TextHeight = 13
  object GroupBox1: TGroupBox
    Left = 8
    Top = 8
    Width = 395
    Height = 435
    Anchors = [akLeft, akTop, akRight, akBottom]
    Caption = 'Choose destination point:'
    TabOrder = 0
    DesignSize = (
      395
      435)
    object lvWaypoints: TListView
      Left = 16
      Top = 20
      Width = 365
      Height = 401
      Anchors = [akLeft, akTop, akRight, akBottom]
      Columns = <>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsList
      OnAdvancedCustomDrawItem = lvWaypointsAdvancedCustomDrawItem
      OnDblClick = lvWaypointsDblClick
      OnSelectItem = lvWaypointsSelectItem
    end
  end
  object frameContainer: TGroupBox
    Left = 418
    Top = 8
    Width = 233
    Height = 404
    Anchors = [akTop, akRight, akBottom]
    Caption = 'Information'
    TabOrder = 1
    object panMove: TPanel
      Left = -19
      Top = 48
      Width = 241
      Height = 229
      TabOrder = 1
      DesignSize = (
        241
        229)
      object Memo1: TMemo
        Left = 8
        Top = 8
        Width = 225
        Height = 213
        Anchors = [akLeft, akTop, akRight, akBottom]
        Lines.Strings = (
          'Memo1')
        TabOrder = 0
      end
    end
    object panClanbank: TPanel
      Tag = 2
      Left = 120
      Top = 76
      Width = 110
      Height = 141
      BevelOuter = bvNone
      Caption = 'panClanbank'
      TabOrder = 2
    end
    object Panel1: TPanel
      Tag = 3
      Left = -9
      Top = 115
      Width = 110
      Height = 141
      BevelOuter = bvNone
      Caption = 'panClanbank'
      TabOrder = 3
      object Label1: TLabel
        Left = 16
        Top = 12
        Width = 48
        Height = 13
        Caption = 'test mode'
      end
    end
    object pan7Signs: TPanel
      Tag = 1
      Left = 3
      Top = 15
      Width = 185
      Height = 374
      Caption = 'pan7Signs'
      TabOrder = 0
      object rbDawn: TRadioButton
        Left = 16
        Top = 16
        Width = 57
        Height = 17
        Caption = 'Down'
        Checked = True
        TabOrder = 0
        TabStop = True
      end
      object rbDusk: TRadioButton
        Left = 71
        Top = 12
        Width = 57
        Height = 17
        Caption = 'Dusk'
        TabOrder = 1
      end
      object cbSeal1: TCheckBox
        Left = 28
        Top = 43
        Width = 97
        Height = 17
        Caption = 'Seal of Avarice'
        Checked = True
        State = cbChecked
        TabOrder = 2
      end
      object cbSeal2: TCheckBox
        Left = 28
        Top = 59
        Width = 97
        Height = 17
        Caption = 'Seal of Gnosis'
        Checked = True
        State = cbChecked
        TabOrder = 3
      end
      object cbSeal3: TCheckBox
        Left = 28
        Top = 75
        Width = 97
        Height = 17
        Caption = 'Seal of Strife'
        TabOrder = 4
      end
    end
  end
  object btCancel: TButton
    Left = 572
    Top = 418
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 2
  end
  object btOk: TButton
    Left = 491
    Top = 418
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 3
    OnClick = btOkClick
  end
  object BitBtn1: TBitBtn
    Left = 369
    Top = 4
    Width = 27
    Height = 25
    Anchors = [akTop, akRight]
    Glyph.Data = {
      36030000424D3603000000000000360000002800000010000000100000000100
      18000000000000030000120B0000120B00000000000000000000FFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000FFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000FFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFF000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000FFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000FFFFFFFFFFFFFFFFFFFFFFFF
      000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000
      00000000000000FFFFFFFFFFFFFFFFFF000000FFFFFFCFCFCFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFF000000FFFFFF000000000000606060EFEFEF000000
      000000FFFFFF000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA7A7A7FFFF
      FF000000FFFFFFFFFFFFFFFFFF000000000000000000FFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000FFFFFFFFFFFFFFFFFFFFFFFF
      000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000
      00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFF000000080808FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFA8A8A8FFFFFFFFFFFF707070000000000000FFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000
      0000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF}
    TabOrder = 4
    OnClick = BitBtn1Click
  end
end

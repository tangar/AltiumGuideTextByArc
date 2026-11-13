{==========================================================================}
{  AltiumGuideTextByArcForm.pas                                            }
{                                                                          }
{  Parameters window for "Text Along Arc" (an Altium script form).         }
{                                                                          }
{  Works together with the AltiumGuideTextByArcForm.dfm file (the file     }
{  names and the form name in the .dfm must match) and calls the           }
{  calculation from AltiumGuideTextByArcScript.pas. Both .pas files and    }
{  the .dfm must be in the same script project.                            }
{                                                                          }
{  The only Run Script entry point: TextAlongArc                           }
{                                                                          }
{  NOTE: the file is pure ASCII, so it does not depend on the ANSI or      }
{  UTF-8 encoding Altium uses to read it.                                  }
{==========================================================================}

{--------------------------------------------------------------------------}
{  Window helper functions                                                 }
{--------------------------------------------------------------------------}

{ Index in the layer list -> layer: 0 - current, 1 - Top Overlay,           }
{ 2 - Bottom Overlay, 3..34 - Mechanical 1..32.                            }
Const
    { Font list entry that means the Altium stroke font }
    FONT_STROKE = 'Stroke (Altium)';

{ Current input units: False - mils, True - millimeters.                   }
{ The MIL2MM / MM2MIL factors are declared in the engine.                  }
Var
    gUnitsMM : Boolean;
    { how many placements were made in this session and not undone yet }
    gPlaced  : Integer;

Function ComboIndexToLayer(Board : IPCB_Board; Index : Integer) : TLayer;
Begin
    If Index = 1 Then
        Result := eTopOverlay
    Else If Index = 2 Then
        Result := eBottomOverlay
    Else If Index >= 3 Then
        Result := ILayer.MechanicalLayer(Index - 2)
    Else
        Result := Board.CurrentLayer;
End;

{ Input field -> number; on error writes the reason to the window message  }
{ line.                                                                    }
{ NOTE: the procedure is not a form method, so components are accessed     }
{ through the TextByArcForm instance.                                      }
Function ReadNum(Edit : TEdit; const What : String; var V : Double) : Boolean;
Begin
    Result := False;
    If Not TryNum(Edit.Text, V) Then
    Begin
        TextByArcForm.lblMsg.Caption := 'Check the "' + What + '" field: ' + Trim(Edit.Text);
        Exit;
    End;
    Result := True;
End;

{ Number with the given number of decimal places (no trailing zeros).      }
Function NumFix(X : Double; Digits : Integer) : String;
Var
    Neg, Done : Boolean;
    V : Double;
    I, F, J, Lim : Integer;
    T, FStr : String;
Begin
    Neg := X < 0;
    V   := Abs(X);
    Lim := 1;
    For J := 1 To Digits Do Lim := Lim * 10;
    V := Trunc(V * Lim + 0.5) / Lim;
    I := Trunc(V);
    F := Round((V - I) * Lim);
    If F >= Lim Then
    Begin
        I := I + 1;
        F := 0;
    End;
    T := IntToStr(I);
    If F > 0 Then
    Begin
        FStr := IntToStr(F);
        While Length(FStr) < Digits Do FStr := '0' + FStr;
        J := Length(FStr);
        Done := False;
        While Not Done Do
        Begin
            If J <= 0 Then
                Done := True
            Else If FStr[J] = '0' Then
                J := J - 1
            Else
                Done := True;
        End;
        FStr := Copy(FStr, 1, J);
        If FStr <> '' Then T := T + '.' + FStr;
    End;
    If Neg Then
        If T <> '0' Then T := '-' + T;
    Result := T;
End;

{ Fill the fields with the geometry of the selected arc: X/Y relative to   }
{ the board origin, in the window's current units.                         }
Procedure SetArcFields(Board : IPCB_Board; Arc : IPCB_Arc);
Var
    K : Double;
    D : Integer;
    Ox, Oy : Double;
Begin
    If gUnitsMM Then
    Begin
        K := MIL2MM;
        D := 4;
    End
    Else
    Begin
        K := 1;
        D := 2;
    End;
    Ox := CoordToMils(Board.XOrigin);
    Oy := CoordToMils(Board.YOrigin);
    TextByArcForm.eCx.Text := NumFix((CoordToMils(Arc.XCenter) - Ox) * K, D);
    TextByArcForm.eCy.Text := NumFix((CoordToMils(Arc.YCenter) - Oy) * K, D);
    TextByArcForm.eR.Text  := NumFix(CoordToMils(Arc.Radius) * K, D);
    { the order of the angles sets the direction of the traversal }
    If TextByArcForm.rbIn.Checked Then
    Begin
        TextByArcForm.eA1.Text := NumStr(Arc.StartAngle);
        TextByArcForm.eA2.Text := NumStr(Arc.EndAngle);
    End
    Else
    Begin
        TextByArcForm.eA1.Text := NumStr(Arc.EndAngle);
        TextByArcForm.eA2.Text := NumStr(Arc.StartAngle);
    End;
End;

{ Folder containing the file (with a trailing backslash).                  }
Function DirOf(const S : String) : String;
Var
    I : Integer;
Begin
    Result := '';
    For I := Length(S) DownTo 1 Do
    Begin
        If S[I] = '\' Then
        Begin
            Result := Copy(S, 1, I);
            Exit;
        End;
    End;
End;

{ File with the last field values - next to the board.                     }
Function SettingsFile(Board : IPCB_Board) : String;
Begin
    Result := DirOf(Board.FileName) + 'AltiumGuideTextByArc.ini';
End;

{ Remember the current values of the window fields.                        }
Procedure SaveFormState(Board : IPCB_Board);
Var
    SL, Lns : TStringList;
    I : Integer;
Begin
    If Board = Nil Then Exit;
    If Trim(Board.FileName) = '' Then Exit;
    SL := TStringList.Create;
    Try
        If gUnitsMM Then SL.Add('units=mm') Else SL.Add('units=mil');
        SL.Add('cx='    + TextByArcForm.eCx.Text);
        SL.Add('cy='    + TextByArcForm.eCy.Text);
        SL.Add('r='     + TextByArcForm.eR.Text);
        SL.Add('a1='    + TextByArcForm.eA1.Text);
        SL.Add('a2='    + TextByArcForm.eA2.Text);
        SL.Add('h='     + TextByArcForm.eHeight.Text);
        SL.Add('gap='   + TextByArcForm.eGap.Text);
        SL.Add('shift=' + TextByArcForm.eShift.Text);
        SL.Add('stroke=' + TextByArcForm.eStroke.Text);
        If TextByArcForm.rbIn.Checked Then SL.Add('inside=1') Else SL.Add('inside=0');
        If TextByArcForm.cbFit.Checked Then SL.Add('fit=1') Else SL.Add('fit=0');
        SL.Add('layer=' + IntToStr(TextByArcForm.cbLayer.ItemIndex));
        SL.Add('font='  + TextByArcForm.cbFont.Text);
        If TextByArcForm.cbMirror.Checked Then SL.Add('mirror=1') Else SL.Add('mirror=0');
        Lns := TStringList.Create;
        Try
            Lns.Text := TextByArcForm.memoText.Text;
            SL.Add('lines=' + IntToStr(Lns.Count));
            For I := 0 To Lns.Count - 1 Do
                SL.Add('line' + IntToStr(I) + '=' + Lns[I]);
        Finally
            Lns.Free;
        End;
        Try
            SL.SaveToFile(SettingsFile(Board));
        Except
        End;
    Finally
        SL.Free;
    End;
End;

{ Restore the last field values of the window (if the file exists).        }
Procedure LoadFormState(Board : IPCB_Board);
Var
    SL, Lns : TStringList;
    I, N, Li : Integer;
    V : String;
Begin
    If Board = Nil Then Exit;
    If Trim(Board.FileName) = '' Then Exit;
    If Not FileExists(SettingsFile(Board)) Then Exit;
    SL := TStringList.Create;
    Try
        Try
            SL.LoadFromFile(SettingsFile(Board));
        Except
            SL.Clear;
        End;

        V := SL.Values['units'];
        If V = 'mm' Then
        Begin
            gUnitsMM := True;
            TextByArcForm.rbMM.Checked  := True;
            TextByArcForm.rbMil.Checked := False;
        End
        Else If V = 'mil' Then
        Begin
            gUnitsMM := False;
            TextByArcForm.rbMil.Checked := True;
            TextByArcForm.rbMM.Checked  := False;
        End;

        V := SL.Values['cx'];    If V <> '' Then TextByArcForm.eCx.Text     := V;
        V := SL.Values['cy'];    If V <> '' Then TextByArcForm.eCy.Text     := V;
        V := SL.Values['r'];     If V <> '' Then TextByArcForm.eR.Text      := V;
        V := SL.Values['a1'];    If V <> '' Then TextByArcForm.eA1.Text     := V;
        V := SL.Values['a2'];    If V <> '' Then TextByArcForm.eA2.Text     := V;
        V := SL.Values['h'];     If V <> '' Then TextByArcForm.eHeight.Text := V;
        V := SL.Values['gap'];   If V <> '' Then TextByArcForm.eGap.Text    := V;
        V := SL.Values['shift']; If V <> '' Then TextByArcForm.eShift.Text  := V;
        V := SL.Values['stroke']; If V <> '' Then TextByArcForm.eStroke.Text := V;

        TextByArcForm.rbIn.Checked  := (SL.Values['inside'] = '1');
        TextByArcForm.rbOut.Checked := Not TextByArcForm.rbIn.Checked;
        TextByArcForm.cbFit.Checked := (SL.Values['fit'] = '1');
        TextByArcForm.cbMirror.Checked := (SL.Values['mirror'] = '1');

        Li := ParseInt(SL.Values['layer'], 0);
        If Li < 0 Then Li := 0;
        If Li >= TextByArcForm.cbLayer.Items.Count Then Li := 0;
        TextByArcForm.cbLayer.ItemIndex := Li;

        V := SL.Values['font'];
        If V <> '' Then TextByArcForm.cbFont.Text := V;

        N := ParseInt(SL.Values['lines'], -1);
        If N >= 0 Then
        Begin
            Lns := TStringList.Create;
            Try
                For I := 0 To N - 1 Do
                    Lns.Add(SL.Values['line' + IntToStr(I)]);
                TextByArcForm.memoText.Text := Lns.Text;
            Finally
                Lns.Free;
            End;
        End;
    Finally
        SL.Free;
    End;
End;

{ Rescale a field value when the units change.                             }
Function ScaleStr(const S : String; K : Double; Digits : Integer) : String;
Var
    V : Double;
Begin
    If TryNum(S, V) Then
        Result := NumFix(V * K, Digits)
    Else
        Result := S;
End;

{--------------------------------------------------------------------------}
{  Window event handlers                                                   }
{--------------------------------------------------------------------------}

{ One editor undo step (the same as Ctrl+Z).                               }
Procedure UndoOneStep(Dummy : Integer);
Begin
    Try
        ResetParameters;
        RunProcess('PCB:Undo');
    Except
    End;
End;

{ How many text objects are on the board: this counter shows whether the   }
{ placement was removed, since the union goes away in a separate undo step.}
Function CountTextObjects(Board : IPCB_Board) : Integer;
Var
    Iter : IPCB_BoardIterator;
    Txt  : IPCB_Text;
    N    : Integer;
Begin
    Result := 0;
    If Board = Nil Then Exit;
    Iter := Board.BoardIterator_Create;
    If Iter = Nil Then Exit;
    Iter.AddFilter_ObjectSet(MkSet(eTextObject));
    Iter.AddFilter_LayerSet(AllLayers);
    Iter.AddFilter_Method(eProcessAll);
    N := 0;
    Txt := Iter.FirstPCBObject;
    While Txt <> Nil Do
    Begin
        N := N + 1;
        Txt := Iter.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iter);
    Result := N;
End;

{ Enable the undo buttons according to the count of placements not undone }
{ yet.                                                                    }
Procedure RefreshUndoButtons(Dummy : Integer);
Begin
    TextByArcForm.btnUndo.Enabled    := gPlaced > 0;
    TextByArcForm.btnUndoAll.Enabled := gPlaced > 1;
End;

{ "Undo" button: removes one placement COMPLETELY.                         }
{ The union is created in a separate undo step, so after the first step    }
{ we check whether the number of text objects decreased, and if not, do    }
{ one more step.                                                          }
Procedure TTextByArcForm.btnUndoClick(Sender: TObject);
Var
    Board : IPCB_Board;
    Before, After : Integer;
Begin
    lblMsg.Caption := '';
    If gPlaced <= 0 Then
    Begin
        lblMsg.Caption := 'Nothing to undo: no placements in this session.';
        Exit;
    End;
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        lblMsg.Caption := 'No active PCB board.';
        Exit;
    End;

    Before := CountTextObjects(Board);
    UndoOneStep(0);
    After := CountTextObjects(Board);
    If After = Before Then
    Begin
        { the first step removed only the union - remove the characters too }
        UndoOneStep(0);
        After := CountTextObjects(Board);
    End;

    gPlaced := gPlaced - 1;
    RefreshUndoButtons(0);
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
    If After < Before Then
        lblMsg.Caption := 'Placement undone (text objects ' + IntToStr(Before) +
                          ' -> ' + IntToStr(After) + '). Still placed: ' +
                          IntToStr(gPlaced) + '.'
    Else
        lblMsg.Caption := 'Undo failed: the number of objects on the board did not decrease.';
End;

{ "Undo all" button: removes all placements of the session (with their      }
{ unions).                                                                 }
Procedure TTextByArcForm.btnUndoAllClick(Sender: TObject);
Var
    Board : IPCB_Board;
    Before, After, Done, Guard : Integer;
    Stop : Boolean;
Begin
    lblMsg.Caption := '';
    If gPlaced <= 0 Then
    Begin
        lblMsg.Caption := 'Nothing to undo: no placements in this session.';
        Exit;
    End;
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        lblMsg.Caption := 'No active PCB board.';
        Exit;
    End;

    Done  := 0;
    Guard := 0;
    Stop  := False;
    While Not Stop Do
    Begin
        If gPlaced <= 0 Then
            Stop := True
        Else If Guard >= 200 Then
            Stop := True
        Else
        Begin
            Guard  := Guard + 1;
            Before := CountTextObjects(Board);
            UndoOneStep(0);
            After := CountTextObjects(Board);
            If After = Before Then
            Begin
                UndoOneStep(0);
                After := CountTextObjects(Board);
            End;
            If After >= Before Then
            Begin
                { nothing left to roll back: so that unrelated actions are not wiped out }
                gPlaced := 0;
                Stop := True;
            End
            Else
            Begin
                gPlaced := gPlaced - 1;
                Done := Done + 1;
            End;
        End;
    End;

    RefreshUndoButtons(0);
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
    lblMsg.Caption := 'Placements undone: ' + IntToStr(Done) + '.';
End;

{ The window is closing - remember the field values for the next run.      }
Procedure TTextByArcForm.TextByArcFormHide(Sender: TObject);
Var
    Board : IPCB_Board;
Begin
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
    SaveFormState(Board);
End;

{ Window creation: fill the layer and font lists once.                     }
Procedure TTextByArcForm.TextByArcFormCreate(Sender: TObject);
Var
    I : Integer;
Begin
    cbLayer.Items.Clear;
    cbLayer.Items.Add('Current layer');
    cbLayer.Items.Add('Top Overlay');
    cbLayer.Items.Add('Bottom Overlay');
    For I := 1 To 32 Do
        cbLayer.Items.Add('Mechanical ' + IntToStr(I));
    cbLayer.ItemIndex := 0;

    cbFont.Items.Clear;
    cbFont.Items.Add(FONT_STROKE);
    cbFont.Items.Add('Arial');
    cbFont.Items.Add('Arial Narrow');
    cbFont.Items.Add('Calibri');
    cbFont.Items.Add('Courier New');
    cbFont.Items.Add('Tahoma');
    cbFont.Items.Add('Times New Roman');
    cbFont.Items.Add('Verdana');
    cbFont.ItemIndex := 0;

    rbOut.Checked := True;
    rbIn.Checked  := False;
    cbFit.Checked := True;

    lblMsg.Caption := '';

    { default units - millimeters }
    rbMil.Checked := False;
    rbMM.Checked  := True;
    gUnitsMM      := True;

    { All captions are set here, from code: the .dfm file stays ASCII, so the }
    { window text does not depend on the encoding it was saved in.            }
    TextByArcForm.Caption := 'Text Along Arc - parameters';
    gbText.Caption := ' Text ';
    gbArc.Caption  := ' Arc: A1 = text start, A2 = end (A1 = A2 = full circle) ';
    lblCx.Caption  := 'Center X:';
    lblCy.Caption  := 'Center Y:';
    lblR.Caption   := 'Radius:';
    lblA1.Caption  := 'Start angle:';
    lblA2.Caption  := 'End angle:';
    btnArc.Caption := 'From arc';

    gbStyle.Caption   := ' Appearance ';
    lblH.Caption      := 'Height:';
    lblGap.Caption    := 'Gap:';
    lblShift.Caption  := 'Shift:';
    lblShiftHint.Caption := '+ out, - in';
    rbOut.Caption     := 'Clockwise';
    rbIn.Caption      := 'CCW';
    cbFit.Caption     := 'Fit to arc';
    cbMirror.Caption  := 'Mirror (bottom side)';
    lblStroke.Caption := 'Thickness:';
    lblStrokeHint.Caption := 'stroke font only, 0 = default';
    lblUnits.Caption  := 'Units:';
    rbMil.Caption     := 'Mil';
    rbMM.Caption      := 'Millimeters';
    lblUnitsHint.Caption := 'X/Y from board origin';

    gbExport.Caption := ' Layer and font ';
    lblLayer.Caption := 'Layer:';
    lblFont.Caption  := 'Font:';

    btnHelp.Caption    := 'Help';
    btnUndo.Caption    := 'Undo';
    btnUndoAll.Caption := 'Undo all';
    btnUndo.Enabled    := False;
    btnUndoAll.Enabled := False;
    gPlaced            := 0;
    btnPlace.Caption := 'Place';
    btnClose.Caption := 'Close';
End;

{ Showing the window: clear the message and fill in the selected arc       }
{ geometry.                                                                }
Procedure TTextByArcForm.TextByArcFormShow(Sender: TObject);
Var
    Board : IPCB_Board;
    Arc   : IPCB_Arc;
Begin
    lblMsg.Caption := '';
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    { restore the values from the previous run }
    LoadFormState(Board);

    { if an arc is selected - take the geometry from it }
    Arc := FindSelectedArc(Board);
    If Arc = Nil Then Exit;
    SetArcFields(Board, Arc);
End;

{ "From arc" button.                                                       }
Procedure TTextByArcForm.btnArcClick(Sender: TObject);
Var
    Board : IPCB_Board;
    Arc   : IPCB_Arc;
Begin
    lblMsg.Caption := '';
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        lblMsg.Caption := 'No active PCB board.';
        Exit;
    End;
    Arc := FindSelectedArc(Board);
    If Arc = Nil Then
    Begin
        lblMsg.Caption := 'No arc selected: click an arc on the board and press the button again.';
        Exit;
    End;
    SetArcFields(Board, Arc);
    lblMsg.Caption := 'Geometry taken from the selected arc.';
End;

{ Units switch: mils <-> millimeters.                                      }
Procedure TTextByArcForm.rbUnitsClick(Sender: TObject);
Var
    K : Double;
    D : Integer;
Begin
    If rbMM.Checked = gUnitsMM Then Exit;
    If rbMM.Checked Then
    Begin
        K := MIL2MM;   { mils -> millimeters }
        D := 4;
    End
    Else
    Begin
        K := MM2MIL;   { millimeters -> mils }
        D := 2;
    End;
    eCx.Text     := ScaleStr(eCx.Text, K, D);
    eCy.Text     := ScaleStr(eCy.Text, K, D);
    eR.Text      := ScaleStr(eR.Text, K, D);
    eHeight.Text := ScaleStr(eHeight.Text, K, D);
    eGap.Text    := ScaleStr(eGap.Text, K, D);
    eShift.Text  := ScaleStr(eShift.Text, K, D);
    eStroke.Text := ScaleStr(eStroke.Text, K, D);
    gUnitsMM := rbMM.Checked;
    lblMsg.Caption := '';
End;

{ "Place" button.                                                          }
Procedure TTextByArcForm.btnPlaceClick(Sender: TObject);
Var
    Board   : IPCB_Board;
    S       : String;
    Cx, Cy, R, A1, A2 : Double;
    H, G, Sh, Th : Double;
    Layer    : TLayer;
    UseTT    : Boolean;
    FontName : String;
    ModeInside, FitToArc, Mirror : Boolean;
    ErrMsg, InfoMsg : String;
    Cnt : Integer;
Begin
    lblMsg.Caption := '';
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        lblMsg.Caption := 'No active PCB board.';
        Exit;
    End;

    S := Trim(memoText.Text);
    If S = '' Then
    Begin
        lblMsg.Caption := 'Enter a text string.';
        Exit;
    End;

    If Not ReadNum(eCx,     'Center X',    Cx) Then Exit;
    If Not ReadNum(eCy,     'Center Y',    Cy) Then Exit;
    If Not ReadNum(eR,      'Radius',      R)  Then Exit;
    If Not ReadNum(eA1,     'Start angle', A1) Then Exit;
    If Not ReadNum(eA2,     'End angle',   A2) Then Exit;
    If Not ReadNum(eHeight, 'Height',      H)  Then Exit;
    If Not ReadNum(eGap,    'Gap',         G)  Then Exit;
    If Not ReadNum(eShift,  'Shift',       Sh) Then Exit;
    If Not ReadNum(eStroke, 'Thickness',   Th) Then Exit;

    { the fields are in the selected units: convert millimeters to mils }
    If gUnitsMM Then
    Begin
        Cx := Cx * MM2MIL;
        Cy := Cy * MM2MIL;
        R  := R  * MM2MIL;
        H  := H  * MM2MIL;
        G  := G  * MM2MIL;
        Sh := Sh * MM2MIL;
        Th := Th * MM2MIL;
    End;

    { X/Y are relative to the board origin - convert to absolute coordinates }
    Cx := Cx + CoordToMils(Board.XOrigin);
    Cy := Cy + CoordToMils(Board.YOrigin);

    If R <= 0 Then
    Begin
        lblMsg.Caption := 'Radius must be greater than zero.';
        Exit;
    End;
    If H <= 0 Then
    Begin
        lblMsg.Caption := 'Character height must be greater than zero.';
        Exit;
    End;

    ModeInside := rbIn.Checked;
    FitToArc   := cbFit.Checked;
    Mirror     := cbMirror.Checked;
    Layer      := ComboIndexToLayer(Board, cbLayer.ItemIndex);

    FontName := Trim(cbFont.Text);
    If (FontName = '') Or (FontName = FONT_STROKE) Then
    Begin
        UseTT    := False;
        FontName := '';
    End
    Else
    Begin
        UseTT := True;
        If UpperCase(FontName) = 'ARIAL' Then FontName := 'Arial';
    End;

    Cnt := PlaceTextAlongArc(Board, S, Cx, Cy, R, A1, A2, H, G, Sh, Th,
                             ModeInside, FitToArc, Mirror, Layer, UseTT, FontName,
                             ErrMsg, InfoMsg);

    If ErrMsg <> '' Then
    Begin
        lblMsg.Caption := ErrMsg;
        Exit;
    End;

    lblMsg.Caption := 'Done, objects: ' + IntToStr(Cnt) + '. ' + InfoMsg;
    gPlaced := gPlaced + 1;
    RefreshUndoButtons(0);
    SaveFormState(Board);
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
End;

{ "Close" button.                                                          }
Procedure TTextByArcForm.btnCloseClick(Sender: TObject);
Begin
    Close;
End;

{ "Help" button.                                                           }
Procedure TTextByArcForm.btnHelpClick(Sender: TObject);
Var
    Msg : String;
Begin
    Msg := 'Text Along Arc' + CRLF + CRLF;
    Msg := Msg + 'The text STARTS at angle A1 and runs toward A2:' + CRLF;
    Msg := Msg + '"Clockwise" walks clockwise, "CCW" walks counterclockwise.' + CRLF;
    Msg := Msg + 'A2 only sets the arc span (|A2 - A1|); with A1 = A2' + CRLF;
    Msg := Msg + 'you get a full circle.' + CRLF + CRLF;
    Msg := Msg + 'The "From arc" button fills in the center, radius and angles' + CRLF;
    Msg := Msg + 'of the arc selected on the board (the same happens when the' + CRLF;
    Msg := Msg + 'window opens).' + CRLF + CRLF;
    Msg := Msg + 'The "Mirror" checkbox enables MirrorFlag: the text is meant' + CRLF;
    Msg := Msg + 'to be read from the back side (letters are mirrored and the' + CRLF;
    Msg := Msg + 'character order is reversed, like Altium built-in mirrored' + CRLF;
    Msg := Msg + 'text), for example on Bottom Overlay.' + CRLF + CRLF;
    Msg := Msg + '"Clockwise" walks clockwise (text above the arc, the upper' + CRLF;
    Msg := Msg + 'part of the circle); "CCW" walks counterclockwise (below the' + CRLF;
    Msg := Msg + 'arc, for the lower part, so the text is not upside down).' + CRLF;
    Msg := Msg + '"Fit to arc" adjusts the gaps so that the string fills the' + CRLF;
    Msg := Msg + 'whole arc; otherwise the "Gap" field is used.' + CRLF + CRLF;
    Msg := Msg + 'Letters sit on the arc with their bottom, so periods and' + CRLF;
    Msg := Msg + 'commas land on the line, not at mid-height. Use the "Shift"' + CRLF;
    Msg := Msg + 'field to move the text inward or outward (minus = inward).' + CRLF + CRLF;
    Msg := Msg + 'Layer: "Current layer" is the active board layer.' + CRLF;
    Msg := Msg + 'Font: "Stroke (Altium)" or any TrueType font by name.' + CRLF + CRLF;
    Msg := Msg + 'X/Y are relative to the board origin (Edit > Origin > Set);' + CRLF;
    Msg := Msg + 'the units (mils / millimeters) are switched in the' + CRLF;
    Msg := Msg + '"Appearance" group; switching recalculates the field values,' + CRLF;
    Msg := Msg + 'angles are always in degrees.' + CRLF + CRLF;
    Msg := Msg + 'The placed characters are combined into a union: they can be' + CRLF;
    Msg := Msg + 'selected, moved and copied as a single object (Edit > Unions).' + CRLF + CRLF;
    Msg := Msg + 'The undo buttons work on the placements of this session:' + CRLF;
    Msg := Msg + '"Undo" removes the last placement together with its union' + CRLF;
    Msg := Msg + '(can be pressed repeatedly),' + CRLF;
    Msg := Msg + '"Undo all" removes all placements of the session.' + CRLF;
    Msg := Msg + 'These are editor undo steps: if something was done by hand' + CRLF;
    Msg := Msg + 'between placements, those actions are undone too (like Ctrl+Z).' + CRLF + CRLF;
    Msg := Msg + 'Field values are saved when the window closes to' + CRLF;
    Msg := Msg + 'AltiumGuideTextByArc.ini next to the board and restored on the' + CRLF;
    Msg := Msg + 'next run; if an arc is selected, its geometry takes precedence.' + CRLF;
    Msg := Msg + 'The whole placement is one undo step (Ctrl+Z).';
    ShowInfo(Msg);
End;

{--------------------------------------------------------------------------}
{  Starting the window                                                     }
{--------------------------------------------------------------------------}
Procedure TextAlongArc;
Var
    Board : IPCB_Board;
Begin
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        ShowError('No active PCB board. Open a .PcbDoc and run the script again.');
        Exit;
    End;

    TextByArcForm.Visible := False;
    TextByArcForm.ShowModal;

    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
End;

{==========================================================================}
{  End of file                                                             }
{==========================================================================}
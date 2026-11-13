{==========================================================================}
{  AltiumGuideTextByArcForm.pas                                            }
{                                                                          }
{  Окно параметров "Текст вдоль дуги" (скрипт-форма Altium).                }
{                                                                          }
{  Работает в паре с файлом  AltiumGuideTextByArcForm.dfm                  }
{  (имена файлов и имя формы в .dfm должны совпадать!) и вызывает расчёт    }
{  из AltiumGuideTextByArcScript.pas. Оба .pas-файла и .dfm должны лежать   }
{  в одном скрипт-проекте.                                                 }
{                                                                          }
{  Единственная точка входа для Run Script: TextAlongArc                    }
{                                                                          }
{  ВНИМАНИЕ: файл сохранён в кодировке ANSI (Windows-1251).                }
{==========================================================================}

{--------------------------------------------------------------------------}
{  Служебные функции окна                                                  }
{--------------------------------------------------------------------------}

{ Индекс в списке слоёв -> слой: 0 - текущий, 1 - Top Overlay,              }
{ 2 - Bottom Overlay, 3..34 - Mechanical 1..32.                            }
Const
    { Пункт списка шрифтов, означающий штриховой шрифт Altium }
    FONT_STROKE = 'Штриховой Altium';

{ Текущие единицы полей ввода: False - милы, True - миллиметры.            }
{ Коэффициенты перевода MIL2MM / MM2MIL объявлены в движке.               }
Var
    gUnitsMM : Boolean;
    { сколько размещений сделано в этом сеансе и ещё не отменено }
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

{ Поле ввода -> число; при ошибке пишет причину в строку сообщений окна.   }
{ ВНИМАНИЕ: процедура не является методом формы, поэтому обращения к       }
{ компонентам идут через экземпляр TextByArcForm.                          }
Function ReadNum(Edit : TEdit; const What : String; var V : Double) : Boolean;
Begin
    Result := False;
    If Not TryNum(Edit.Text, V) Then
    Begin
        TextByArcForm.lblMsg.Caption := 'Проверьте поле "' + What + '": ' + Trim(Edit.Text);
        Exit;
    End;
    Result := True;
End;

{ Число с заданным количеством знаков после точки (без хвостовых нулей).   }
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

{ Записать в поля геометрию выделенной дуги: X/Y - от нулевой точки платы, }
{ в текущих единицах окна.                                                 }
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
    { порядок углов задаёт направление обхода: "ПО Ч.С." - по часовой }
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

{ Папка, в которой лежит файл (вместе с завершающим обратным слэшем).      }
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

{ Файл с последними значениями полей - рядом с платой.                     }
Function SettingsFile(Board : IPCB_Board) : String;
Begin
    Result := DirOf(Board.FileName) + 'AltiumGuideTextByArc.ini';
End;

{ Запомнить текущие значения полей окна.                                   }
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

{ Восстановить последние значения полей окна (если файл есть).             }
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

{ Пересчёт значения поля при смене единиц.                                 }
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
{  Обработчики окна                                                        }
{--------------------------------------------------------------------------}

{ Один шаг отмены редактора (то же, что Ctrl+Z).                           }
Procedure UndoOneStep(Dummy : Integer);
Begin
    Try
        ResetParameters;
        RunProcess('PCB:Undo');
    Except
    End;
End;

{ Сколько текстовых объектов на плате: по этому счётчику видно, снялось ли  }
{ размещение, ведь union уходит отдельным шагом отмены.                    }
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

{ Доступность кнопок отмены по счётчику неотменённых размещений.           }
Procedure RefreshUndoButtons(Dummy : Integer);
Begin
    TextByArcForm.btnUndo.Enabled    := gPlaced > 0;
    TextByArcForm.btnUndoAll.Enabled := gPlaced > 1;
End;

{ Кнопка "Отменить": снимает одно размещение ЦЕЛИКОМ.                      }
{ union создаётся отдельным шагом отмены, поэтому после первого шага        }
{ проверяем, убавилось ли текстовых объектов, и если нет - делаем ещё шаг. }
Procedure TTextByArcForm.btnUndoClick(Sender: TObject);
Var
    Board : IPCB_Board;
    Before, After : Integer;
Begin
    lblMsg.Caption := '';
    If gPlaced <= 0 Then
    Begin
        lblMsg.Caption := 'Отменять нечего: размещений в этом сеансе нет.';
        Exit;
    End;
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        lblMsg.Caption := 'Нет активной платы (PCB).';
        Exit;
    End;

    Before := CountTextObjects(Board);
    UndoOneStep(0);
    After := CountTextObjects(Board);
    If After = Before Then
    Begin
        { первым шагом снялся только union - снимаем и сами символы }
        UndoOneStep(0);
        After := CountTextObjects(Board);
    End;

    gPlaced := gPlaced - 1;
    RefreshUndoButtons(0);
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
    If After < Before Then
        lblMsg.Caption := 'Размещение отменено (текстовых объектов ' + IntToStr(Before) +
                          ' -> ' + IntToStr(After) + '). Осталось неотменённых: ' +
                          IntToStr(gPlaced) + '.'
    Else
        lblMsg.Caption := 'Отменить не удалось: объектов на плате не убавилось.';
End;

{ Кнопка "Отменить всё": снимает все размещения сеанса (с их union).       }
Procedure TTextByArcForm.btnUndoAllClick(Sender: TObject);
Var
    Board : IPCB_Board;
    Before, After, Done, Guard : Integer;
    Stop : Boolean;
Begin
    lblMsg.Caption := '';
    If gPlaced <= 0 Then
    Begin
        lblMsg.Caption := 'Отменять нечего: размещений в этом сеансе нет.';
        Exit;
    End;
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        lblMsg.Caption := 'Нет активной платы (PCB).';
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
                { дальше откатывать нечего: чтобы не снести чужие действия }
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
    lblMsg.Caption := 'Отменено размещений: ' + IntToStr(Done) + '.';
End;

{ Окно закрывается - запоминаем значения полей для следующего запуска.     }
Procedure TTextByArcForm.TextByArcFormHide(Sender: TObject);
Var
    Board : IPCB_Board;
Begin
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
    SaveFormState(Board);
End;

{ Создание окна: заполняем списки слоёв и шрифтов один раз.                }
Procedure TTextByArcForm.TextByArcFormCreate(Sender: TObject);
Var
    I : Integer;
Begin
    cbLayer.Items.Clear;
    cbLayer.Items.Add('Текущий слой');
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

    { единицы по умолчанию - миллиметры }
    rbMil.Checked := False;
    rbMM.Checked  := True;
    gUnitsMM      := True;

    { Все русские подписи ставим здесь, из кода: файл .dfm остаётся в ASCII,  }
    { поэтому кириллица не зависит от того, в какой кодировке его сохранят.   }
    TextByArcForm.Caption := 'Текст вдоль дуги - параметры';
    gbText.Caption := ' Текст ';
    gbArc.Caption  := ' Дуга: A1 - начало текста, A2 - конец (A1 = A2 - полный круг) ';
    lblCx.Caption  := 'Центр X:';
    lblCy.Caption  := 'Центр Y:';
    lblR.Caption   := 'Радиус:';
    lblA1.Caption  := 'Начальный угол:';
    lblA2.Caption  := 'Конечный угол:';
    btnArc.Caption := 'Взять из дуги';

    gbStyle.Caption   := ' Оформление ';
    lblH.Caption      := 'Высота:';
    lblGap.Caption    := 'Зазор:';
    lblShift.Caption  := 'Сдвиг:';
    lblShiftHint.Caption := '+ наружу, - внутрь';
    rbOut.Caption     := 'ПО Ч.С.';
    rbIn.Caption      := 'Против Ч.С.';
    cbFit.Caption     := 'Растянуть по дуге';
    cbMirror.Caption  := 'Зеркально (для низа платы)';
    lblStroke.Caption := 'Толщина:';
    lblStrokeHint.Caption := 'штриховой шрифт; 0 - по умолчанию';
    lblUnits.Caption  := 'Единицы:';
    rbMil.Caption     := 'Мили';
    rbMM.Caption      := 'Миллиметры';
    lblUnitsHint.Caption := 'X/Y - от нулевой точки платы';

    gbExport.Caption := ' Слой и шрифт ';
    lblLayer.Caption := 'Слой:';
    lblFont.Caption  := 'Шрифт:';

    btnHelp.Caption    := 'Справка';
    btnUndo.Caption    := 'Отменить';
    btnUndoAll.Caption := 'Отменить всё';
    btnUndo.Enabled    := False;
    btnUndoAll.Enabled := False;
    gPlaced            := 0;
    btnPlace.Caption := 'Разместить';
    btnClose.Caption := 'Закрыть';
End;

{ Показ окна: чистим сообщение и подставляем геометрию выделенной дуги.    }
Procedure TTextByArcForm.TextByArcFormShow(Sender: TObject);
Var
    Board : IPCB_Board;
    Arc   : IPCB_Arc;
Begin
    lblMsg.Caption := '';
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    { восстанавливаем значения прошлого запуска }
    LoadFormState(Board);

    { если выделена дуга - геометрия берётся из неё }
    Arc := FindSelectedArc(Board);
    If Arc = Nil Then Exit;
    SetArcFields(Board, Arc);
End;

{ Кнопка "Взять из дуги".                                                  }
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
        lblMsg.Caption := 'Нет активной платы (PCB).';
        Exit;
    End;
    Arc := FindSelectedArc(Board);
    If Arc = Nil Then
    Begin
        lblMsg.Caption := 'Дуга не выделена: щёлкните по дуге на плате и нажмите кнопку снова.';
        Exit;
    End;
    SetArcFields(Board, Arc);
    lblMsg.Caption := 'Геометрия взята из выделенной дуги.';
End;

{ Переключатель единиц: милы <-> миллиметры.                              }
Procedure TTextByArcForm.rbUnitsClick(Sender: TObject);
Var
    K : Double;
    D : Integer;
Begin
    If rbMM.Checked = gUnitsMM Then Exit;
    If rbMM.Checked Then
    Begin
        K := MIL2MM;   { милы -> миллиметры }
        D := 4;
    End
    Else
    Begin
        K := MM2MIL;   { миллиметры -> милы }
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

{ Кнопка "Разместить".                                                     }
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
        lblMsg.Caption := 'Нет активной платы (PCB).';
        Exit;
    End;

    S := Trim(memoText.Text);
    If S = '' Then
    Begin
        lblMsg.Caption := 'Введите строку текста.';
        Exit;
    End;

    If Not ReadNum(eCx,     'Центр X',        Cx) Then Exit;
    If Not ReadNum(eCy,     'Центр Y',        Cy) Then Exit;
    If Not ReadNum(eR,      'Радиус',         R)  Then Exit;
    If Not ReadNum(eA1,     'Начальный угол', A1) Then Exit;
    If Not ReadNum(eA2,     'Конечный угол',  A2) Then Exit;
    If Not ReadNum(eHeight, 'Высота',         H)  Then Exit;
    If Not ReadNum(eGap,    'Зазор',          G)  Then Exit;
    If Not ReadNum(eShift,  'Сдвиг',          Sh) Then Exit;
    If Not ReadNum(eStroke, 'Толщина',        Th) Then Exit;

    { поля заданы в выбранных единицах: миллиметры переводим в милы }
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

    { X/Y заданы от нулевой точки платы - переводим в абсолютные координаты }
    Cx := Cx + CoordToMils(Board.XOrigin);
    Cy := Cy + CoordToMils(Board.YOrigin);

    If R <= 0 Then
    Begin
        lblMsg.Caption := 'Радиус должен быть больше нуля.';
        Exit;
    End;
    If H <= 0 Then
    Begin
        lblMsg.Caption := 'Высота символа должна быть больше нуля.';
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

    lblMsg.Caption := 'Готово, объектов: ' + IntToStr(Cnt) + '. ' + InfoMsg;
    gPlaced := gPlaced + 1;
    RefreshUndoButtons(0);
    SaveFormState(Board);
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
End;

{ Кнопка "Закрыть".                                                        }
Procedure TTextByArcForm.btnCloseClick(Sender: TObject);
Begin
    Close;
End;

{ Кнопка "Справка".                                                        }
Procedure TTextByArcForm.btnHelpClick(Sender: TObject);
Var
    Msg : String;
Begin
    Msg := 'Текст вдоль дуги' + CRLF + CRLF;
    Msg := Msg + 'Текст НАЧИНАЕТСЯ в угле A1 и идёт в сторону A2:' + CRLF;
    Msg := Msg + 'режим "ПО Ч.С." - по часовой стрелке, "Против Ч.С." - против.' + CRLF;
    Msg := Msg + 'A2 задаёт протяжённость дуги (|A2 - A1|); при A1 = A2' + CRLF;
    Msg := Msg + 'получается полный круг.' + CRLF + CRLF;
    Msg := Msg + 'Кнопка "Взять из дуги" подставляет центр, радиус и углы' + CRLF;
    Msg := Msg + 'выделенной на плате дуги (то же делается при открытии окна).' + CRLF + CRLF;
    Msg := Msg + 'Флажок "Зеркально" включает MirrorFlag - так текст ставят на' + CRLF;
    Msg := Msg + 'читался с обратной стороны (буквы зеркальны, порядок символов' + CRLF;
    Msg := Msg + 'тоже разворачивается - как у штатного зеркального текста),' + CRLF;
    Msg := Msg + 'например, на Bottom Overlay.' + CRLF + CRLF;
    Msg := Msg + 'Режим "ПО Ч.С." - обход по часовой стрелке (текст над дугой,' + CRLF;
    Msg := Msg + 'верхняя часть окружности); "Против Ч.С." - против часовой' + CRLF;
    Msg := Msg + '(под дугой, для нижней части, чтобы текст не был перевёрнут).' + CRLF;
    Msg := Msg + '"Растянуть по дуге" подгоняет зазоры так, чтобы' + CRLF;
    Msg := Msg + 'строка заняла дугу целиком; иначе используется поле "Зазор".' + CRLF + CRLF;
    Msg := Msg + 'Буквы стоят на дуге низом - точки и запятые попадают на линию,' + CRLF;
    Msg := Msg + 'а не на середину высоты. Сдвинуть текст внутрь или наружу' + CRLF;
    Msg := Msg + 'можно полем "Сдвиг" (минус - внутрь).' + CRLF + CRLF;
    Msg := Msg + 'Слой: "Текущий слой" - активный слой платы.' + CRLF;
    Msg := Msg + 'Шрифт: "Штриховой Altium" или любой TrueType по имени.' + CRLF + CRLF;
    Msg := Msg + 'X/Y задаются от нулевой точки платы (Edit > Origin > Set);' + CRLF;
    Msg := Msg + 'единицы (милы / миллиметры) переключаются в группе' + CRLF;
    Msg := Msg + '"Оформление"; при переключении значения полей пересчитываются,' + CRLF;
    Msg := Msg + 'углы всегда в градусах.' + CRLF + CRLF;
    Msg := Msg + 'Размещённые символы объединяются в union: их можно выделить,' + CRLF;
    Msg := Msg + 'двигать и копировать как один объект (Edit > Unions).' + CRLF + CRLF;
    Msg := Msg + 'Кнопки отмены работают по размещениям этого сеанса:' + CRLF;
    Msg := Msg + '"Отменить" - убирает последнее размещение вместе с его union' + CRLF;
    Msg := Msg + '(нажимать можно многократно),' + CRLF;
    Msg := Msg + '"Отменить всё" - снимает все размещения сеанса.' + CRLF;
    Msg := Msg + 'Это шаги отмены редактора: если между размещениями что-то' + CRLF;
    Msg := Msg + 'делали руками, отменятся и эти действия (как Ctrl+Z).' + CRLF + CRLF;
    Msg := Msg + 'Значения полей запоминаются при закрытии окна в файле' + CRLF;
    Msg := Msg + 'AltiumGuideTextByArc.ini рядом с платой и восстанавливаются при' + CRLF;
    Msg := Msg + 'следующем запуске; если выделена дуга, её геометрия важнее.' + CRLF;
    Msg := Msg + 'Всё размещение - один шаг отмены (Ctrl+Z).';
    ShowInfo(Msg);
End;

{--------------------------------------------------------------------------}
{  Запуск окна                                                             }
{--------------------------------------------------------------------------}
Procedure TextAlongArc;
Var
    Board : IPCB_Board;
Begin
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
        ShowError('Нет активной платы (PCB). Откройте .PcbDoc и запустите скрипт снова.');
        Exit;
    End;

    TextByArcForm.Visible := False;
    TextByArcForm.ShowModal;

    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
End;

{==========================================================================}
{  Конец файла                                                             }
{==========================================================================}

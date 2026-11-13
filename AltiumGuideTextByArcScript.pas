{==========================================================================}
{  AltiumGuideTextByArcScript.pas                                          }
{                                                                          }
{  Расстановка текста вдоль дуги (или полной окружности) на плате PCB.     }
{  Переработка AltiumGuideTextByCircleScript.pas (Igor Emelyanoff, 2023).  }
{                                                                          }
{  Что изменилось по сравнению с исходным скриптом:                        }
{   1. Геометрия берётся у ВЫДЕЛЕННОЙ на плате дуги (если она выделена),   }
{      либо задаётся вручную: центр X/Y, радиус, начальный/конечный угол.   }
{   2. Шаг между символами считается по РЕАЛЬНОЙ ширине каждого символа     }
{      (замер габарита на плате), а не "360 / длина строки". Поэтому нет    }
{      разрывов и нахлёстов на узких и широких буквах.                      }
{   3. Поворот идёт вокруг ЦЕНТРА габарита символа, а не вокруг точки       }
{      привязки текста, поэтому символы стоят точно на дуге.                }
{   4. Пробелы не создают объектов, но дают правильный зазор.               }
{   5. Режим "Против Ч.С." - для нижней части дуги (текст не вверх ногами).   }
{   6. Режим "растянуть по дуге": зазоры подгоняются под длину дуги.        }
{   7. Pi вместо 3.14, Double вместо Float, корректные типы, откат: всё      }
{      размещение идёт одной операцией (одна отмена по Ctrl+Z).             }
{   8. Штриховой шрифт Altium или TrueType (Arial и любой установленный).    }
{   9. Всё размещение - одна операция: Ctrl+Z убирает его целиком.         }
{                                                                          }
{  Как запустить:                                                          }
{      DXP (File) > Run Script... > единственная процедура TextAlongArc      }
{      (окно параметров - в файле AltiumGuideTextByArcForm.pas, расчёт -     }
{      здесь, в PlaceTextAlongArc). Все остальные процедуры имеют           }
{      параметры, поэтому в списке Run Script не показываются.             }
{                                                                          }
{  Соглашения:                                                             }
{      Длины задаются в миллиметрах; координаты X/Y - от НУЛЕВОЙ ТОЧКИ          }
{      платы (так же, как их показывает сам Altium: Board.XOrigin/YOrigin).  }
{      Углы в градусах, против часовой стрелки от оси +X; дуга идёт от       }
{      начального угла к конечному ПРОТИВ часовой стрелки (как              }
{      StartAngle/EndAngle у IPCB_Arc). В вопросах числа разделяются         }
{      точкой с запятой ";". Файл в кодировке ANSI (Windows-1251).           }
{==========================================================================}

Const
    { Перевод длин: 1 мил = 0.001 дюйма = 0.0254 мм }
    MIL2MM = 0.0254;
    MM2MIL = 39.3700787401575;

    { Доли высоты символа, используемые как его ширина в аварийном случае, }
    { когда замер габарита на плате не удался.                             }
    FW_SPACE  = 0.50;
    FW_NARROW = 0.34;
    FW_WIDE   = 0.90;
    FW_NORMAL = 0.68;

    CRLF = #13#10;

{==========================================================================}
{  Вспомогательные функции                                                 }
{==========================================================================}

{ Число в строку. Разделитель дробной части всегда точка, поэтому строка   }
{ не зависит от региональных настроек Windows.                             }
function NumStr(X : Double) : String;
Var
    Neg, Done : Boolean;
    V : Double;
    I, F, J : Integer;
    T, FStr : String;
Begin
    Neg := X < 0;
    V := Abs(X);
    V := Trunc(V * 1000 + 0.5) / 1000;
    I := Trunc(V);
    F := Round((V - I) * 1000);
    If F >= 1000 Then
    Begin
        I := I + 1;
        F := 0;
    End;
    T := IntToStr(I);
    If F > 0 Then
    Begin
        FStr := Copy('00' + IntToStr(F), Length('00' + IntToStr(F)) - 2, 3);
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

{ Строка в число. Понимает и точку, и запятую как разделитель дробной      }
{ части. При ошибке возвращает Def.                                        }
{ Разбор числа вручную, без StrToFloat. Причина: в DelphiScript try/except
  вокруг StrToFloat не перехватывает EConvertError, а на русской локали
  StrToFloat('1968.5') падает - разделитель дробной части там запятая.
  Здесь принимаются и точка, и запятая, и исключений не возникает.
  Возвращает False, если строка не является числом.                       }
function TryNum(const S : String; var V : Double) : Boolean;
Var
    T : String;
    I, N, Digit : Integer;
    Ch : Char;
    Neg, SeenSep, SeenDigit : Boolean;
    IntPart, FracPart, Scale : Double;
Begin
    Result    := False;
    V         := 0;
    T         := Trim(S);
    N         := Length(T);
    If N = 0 Then Exit;

    I   := 1;
    Neg := False;
    If (T[I] = '-') Or (T[I] = '+') Then
    Begin
        Neg := (T[I] = '-');
        I   := I + 1;
    End;

    IntPart   := 0;
    FracPart  := 0;
    Scale     := 1;
    SeenSep   := False;
    SeenDigit := False;

    While I <= N Do
    Begin
        Ch := T[I];
        If (Ord(Ch) >= 48) And (Ord(Ch) <= 57) Then
        Begin
            SeenDigit := True;
            Digit     := Ord(Ch) - 48;
            If SeenSep Then
            Begin
                Scale    := Scale / 10;
                FracPart := FracPart + Digit * Scale;
            End
            Else
                IntPart := IntPart * 10 + Digit;
        End
        Else If (Ch = '.') Or (Ch = ',') Then
        Begin
            If SeenSep Then Exit;
            SeenSep := True;
        End
        Else
            Exit;
        I := I + 1;
    End;

    If Not SeenDigit Then Exit;
    V := IntPart + FracPart;
    If Neg Then V := -V;
    Result := True;
End;

{ Строка в число. Понимает и точку, и запятую как разделитель дробной      }
{ части. При ошибке возвращает Def.                                        }
function ParseNum(const S : String; Def : Double) : Double;
Var
    V : Double;
Begin
    If TryNum(S, V) Then
        Result := V
    Else
        Result := Def;
End;

function ParseInt(const S : String; Def : Integer) : Integer;
Begin
    Result := Round(ParseNum(S, Def));
End;



{ Первая ВЫДЕЛЕННАЯ дуга на плате (или Nil).                               }
function FindSelectedArc(Board : IPCB_Board) : IPCB_Arc;
Var
    Iter  : IPCB_BoardIterator;
    A     : IPCB_Arc;
    Found : IPCB_Arc;
Begin
    Result := Nil;
    Found  := Nil;
    Iter := Board.BoardIterator_Create;
    If Iter = Nil Then Exit;
    Iter.AddFilter_ObjectSet(MkSet(eArcObject));
    Iter.AddFilter_LayerSet(AllLayers);
    Iter.AddFilter_Method(eProcessAll);
    A := Iter.FirstPCBObject;
    While A <> Nil Do
    Begin
        Try
            If A.Selected Then
                If Found = Nil Then Found := A;
        Except
        End;
        A := Iter.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iter);
    Result := Found;
End;


{ Аварийная оценка ширины символа, если габарит с платы не прочитался.     }
function FallbackWidth(const Ch : String; SizeCoord : Integer) : Integer;
Var
    C : String;
    F : Double;
Begin
    C := UpperCase(Ch);
    F := FW_NORMAL;
    If C = ' ' Then
        F := FW_SPACE
    Else If Length(C) = 1 Then
    Begin
        If Pos(C, 'IJL1.,:;!|/''') > 0 Then
            F := FW_NARROW
        Else If Pos(C, 'MW') > 0 Then
            F := FW_WIDE;
    End;
    Result := Round(SizeCoord * F);
End;

{ Замер символа: ширина габарита (W) в координатах платы. Временный объект   }
{ добавляется на плату, замеряется и удаляется, поэтому в результат не       }
{ попадает.                                                                }
procedure MeasureChar(Board : IPCB_Board; const Ch : String; SizeCoord : Integer;
                      WidthCoord : Integer;
                      Layer : TLayer; UseTT : Boolean; const FontName : String;
                      var W : Integer);
Var
    Txt : IPCB_Text;
    R   : TCoordRect;
    PX, PY : Integer;
Begin
    W := 0;
    Txt := PCBServer.PCBObjectFactory(eTextObject, eNoDimension, eCreate_Default);
    If Txt = Nil Then Exit;
    PX := MilsToCoord(0);
    PY := MilsToCoord(0);
    Txt.Layer      := Layer;
    Txt.Text       := Ch;
    Txt.Size       := SizeCoord;
    If (WidthCoord > 0) And (Not UseTT) Then Txt.Width := WidthCoord;
    Txt.Rotation   := 0;
    Txt.XLocation  := PX;
    Txt.YLocation  := PY;
    Txt.UseTTFonts := UseTT;
    If UseTT Then Txt.FontName := FontName;
    Board.AddPCBObject(Txt);
    Try
        R := Txt.BoundingRectangle;
        W := R.Right - R.Left;
    Except
        W := 0;
    End;
    Board.RemovePCBObject(Txt);
End;

{ Ширина пробела. Меряется как разница габаритов "A A" и "AA" - так         }
{ работает и на шрифтах, где у пробела нет собственного габарита.           }
function MeasureSpaceWidth(Board : IPCB_Board; SizeCoord : Integer;
                           WidthCoord : Integer;
                           Layer : TLayer; UseTT : Boolean;
                           const FontName : String) : Integer;
Var
    Txt    : IPCB_Text;
    R      : TCoordRect;
    W1, W2 : Integer;
Begin
    Result := Round(SizeCoord * FW_SPACE);
    Txt := PCBServer.PCBObjectFactory(eTextObject, eNoDimension, eCreate_Default);
    If Txt = Nil Then Exit;
    Txt.Layer      := Layer;
    Txt.Size       := SizeCoord;
    If (WidthCoord > 0) And (Not UseTT) Then Txt.Width := WidthCoord;
    Txt.Rotation   := 0;
    Txt.XLocation  := MilsToCoord(0);
    Txt.YLocation  := MilsToCoord(0);
    Txt.UseTTFonts := UseTT;
    If UseTT Then Txt.FontName := FontName;
    Txt.Text := 'AA';
    Board.AddPCBObject(Txt);
    Try
        Try
            R  := Txt.BoundingRectangle;
            W1 := R.Right - R.Left;
            Txt.Text := 'A A';
            R  := Txt.BoundingRectangle;
            W2 := R.Right - R.Left;
            If (W2 - W1) > 0 Then Result := W2 - W1;
        Except
        End;
    Finally
        Board.RemovePCBObject(Txt);
    End;
End;

{ Снять выделение со всех объектов платы. Нужно перед сборкой union,      }
{ чтобы в него попали только наши символы.                                 }
procedure DeselectAll(Board : IPCB_Board);
Var
    I : Integer;
Begin
    { штатная команда Edit > DeSelect > All }
    Try
        ResetParameters;
        AddStringParameter('Scope', 'All');
        RunProcess('PCB:DeSelect');
    Except
    End;
    { и на всякий случай снимаем флаг у объектов }
    For I := Board.SelectecObjectCount - 1 DownTo 0 Do
    Begin
        Try
            Board.SelectecObject[I].Selected := False;
        Except
        End;
    End;
End;

{==========================================================================}
{  Раскладка строки вдоль дуги                                             }
{                                                                          }
{  CxMil, CyMil  - центр дуги, милы (абсолютные координаты платы);          }
{  RMil          - радиус дуги, милы;                                      }
{  A1, A2        - начало и конец дуги, градусы против часовой стрелки;     }
{  SizeMil       - высота символа, милы;                                   }
{  GapMil        - зазор между символами, милы (может быть отрицательным);  }
{  ShiftMil      - радиальный сдвиг текста: + наружу, - внутрь, милы;      }
{  StrokeMil     - толщина штрихов (только штриховой шрифт), милы;          }
{                  0 - толщина по умолчанию, для TrueType игнорируется;     }
{  ModeInside    - False: обход по часовой стрелке ("ПО Ч.С."),            }
{                  True : против часовой ("Против Ч.С.");                 }
{  FitToArc      - True: зазоры подгоняются под длину дуги;                }
{  Mirror        - True: текст зеркальный (для нижней стороны платы);      }
{  FontName      - имя TrueType-шрифта (при UseTT = True).                 }
{  Каждый символ ставится так, что его точка привязки (низ буквы) лежит    }
{  на дуге - поэтому точки, запятые и прочие низкие знаки стоят по низу     }
{  строки, а не по её середине.                                           }
{  Возвращает число созданных объектов.                                    }
{  ErrMsg  - текст ошибки ('' = норма);                                    }
{  InfoMsg - сводка по фактическим размерам и предупреждения.              }
{==========================================================================}
function PlaceTextAlongArc(Board : IPCB_Board; const S : String;
                           CxMil, CyMil, RMil, A1, A2 : Double;
                           SizeMil, GapMil, ShiftMil, StrokeMil : Double;
                           ModeInside, FitToArc, Mirror : Boolean;
                           Layer : TLayer; UseTT : Boolean; const FontName : String;
                           var ErrMsg, InfoMsg : String) : Integer;
Var
    Txt  : IPCB_Text;
    CacheK, CacheW : TStringList;
    N, I, Idx, Created : Integer;
    Ch   : String;
    SizeC, GapC, ShiftC, RC, RplC : Integer;
    StrokeC : Integer;
    CtrX, CtrY : Integer;
    Wc : Integer;
    TotW, Ltot, GapEff, SArc : Double;
    SpanDeg, SpanRad, StartRad : Double;
    DirSign, ThetaRad, ThetaDeg, PhiDeg : Double;
    Cum, SAdv, Wf, Px, Py : Double;
    Grouped : Boolean;
    SelBefore, SelAfter, SelFlags : Integer;
    ObjList : TInterfaceList;
Begin
    Result  := 0;
    ErrMsg  := '';
    InfoMsg := '';

    N := Length(S);
    If N < 1 Then
    Begin
        ErrMsg := 'Пустая строка.';
        Exit;
    End;
    If SizeMil <= 0 Then
    Begin
        ErrMsg := 'Высота символа должна быть больше нуля.';
        Exit;
    End;
    If RMil <= 0 Then
    Begin
        ErrMsg := 'Радиус должен быть больше нуля.';
        Exit;
    End;

    { ---- протяжённость дуги: |A2 - A1|; при A1 = A2 - полный круг --------- }
    SpanDeg := Abs(A2 - A1);
    While SpanDeg > 360 Do SpanDeg := SpanDeg - 360;
    If SpanDeg <= 0 Then SpanDeg := 360;

    { Текст НАЧИНАЕТСЯ в угле A1 и идёт в сторону A2:
      "ПО Ч.С."     - по часовой стрелке (так текст читается сверху),
      "Против Ч.С." - против часовой. A2 задаёт только протяжённость. }
    StartRad := A1 * Pi / 180;
    SpanRad  := SpanDeg * Pi / 180;

    SizeC  := MilsToCoord(SizeMil);
    StrokeC := MilsToCoord(StrokeMil);
    If StrokeC < 0 Then StrokeC := 0;
    GapC   := MilsToCoord(GapMil);
    ShiftC := MilsToCoord(ShiftMil);
    RC     := MilsToCoord(RMil);
    RplC   := RC + ShiftC;
    CtrX    := MilsToCoord(CxMil);
    CtrY    := MilsToCoord(CyMil);

    If RplC <= 0 Then
    Begin
        ErrMsg := 'Радиус с учётом радиального сдвига получился <= 0.';
        Exit;
    End;
    If SizeC <= 0 Then
    Begin
        ErrMsg := 'Высота символа получилась <= 0.';
        Exit;
    End;

    If ModeInside Then DirSign := 1 Else DirSign := -1;

    CacheK := TStringList.Create;
    CacheW := TStringList.Create;
    CacheK.CaseSensitive := True;

    Board.LayerIsDisplayed[Layer] := True;
    Board.LayerIsUsed[Layer]      := True;

    { сюда складываем созданные символы: понадобятся для выделения и union }
    ObjList := TInterfaceList.Create;

    PCBServer.PreProcess;
    Try
        { ---- проход 1: ширины символов (кэш по символу) ---- }
        TotW := 0;
        For I := 1 To N Do
        Begin
            Ch  := Copy(S, I, 1);
            Idx := CacheK.IndexOf(Ch);
            If Idx < 0 Then
            Begin
                If Ch = ' ' Then
                    Wc := MeasureSpaceWidth(Board, SizeC, StrokeC, Layer, UseTT, FontName)
                Else
                Begin
                    MeasureChar(Board, Ch, SizeC, StrokeC, Layer, UseTT, FontName, Wc);
                    If (Wc <= 0) Or (Wc > SizeC * 5) Then Wc := FallbackWidth(Ch, SizeC);
                End;
                CacheK.Add(Ch);
                CacheW.Add(IntToStr(Wc));
                Idx := CacheK.Count - 1;
            End;
            TotW := TotW + ParseInt(CacheW[Idx], 0);
        End;

        { ---- зазор: фиксированный или подогнанный под дугу ---- }
        SArc := RplC * SpanRad;
        If FitToArc And (N > 1) Then
            GapEff := (SArc - TotW) / (N - 1)
        Else
            GapEff := GapC;
        Ltot := TotW + GapEff * (N - 1);

        { ---- проход 2: создание символов на дуге ---- }
        Cum     := 0;
        Created := 0;
        For I := 1 To N Do
        Begin
            Ch  := Copy(S, I, 1);
            Idx := CacheK.IndexOf(Ch);
            Wf  := ParseInt(CacheW[Idx], 0);

            { точка привязки символа (низ буквы) вдоль дуги. У зеркального
              текста знак уходит влево от привязки, а сам текст Altium
              зеркалит целиком - значит раскладку тоже надо развернуть,
              иначе слово читается задом наперёд. Зеркалим позицию
              относительно середины строки: привязка = Ltot - Cum. }
            If Mirror Then
                SAdv := Ltot - Cum
            Else
                SAdv := Cum;
            Cum  := Cum + Wf + GapEff;

            If Ch <> ' ' Then
            Begin
                ThetaRad := StartRad + DirSign * (SAdv / RplC);
                ThetaDeg := ThetaRad * 180 / Pi;
                If ModeInside Then
                    PhiDeg := ThetaDeg + 90
                Else
                    PhiDeg := ThetaDeg - 90;

                { точка на дуге, куда ставится точка привязки символа }
                Px := CtrX + RplC * Cos(ThetaRad);
                Py := CtrY + RplC * Sin(ThetaRad);

                Txt := PCBServer.PCBObjectFactory(eTextObject, eNoDimension, eCreate_Default);
                If Txt <> Nil Then
                Begin
                    PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
                    Txt.Layer      := Layer;
                    Txt.Text       := Ch;
                    Txt.Size       := SizeC;
                    If (StrokeC > 0) And (Not UseTT) Then Txt.Width := StrokeC;
                    Txt.Rotation   := PhiDeg;
                    Txt.XLocation  := Round(Px);
                    Txt.YLocation  := Round(Py);
                    Txt.UseTTFonts := UseTT;
                    If UseTT Then Txt.FontName := FontName;
                    Txt.MirrorFlag := Mirror;
                    Board.AddPCBObject(Txt);
                    PCBServer.SendMessageToRobots(Txt.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
                    PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Txt.I_ObjectAddress);
                    ObjList.Add(Txt);
                    Created := Created + 1;
                End;
            End;
        End;

        Result := Created;

        { ---- сводка по фактическим размерам ---- }
        InfoMsg := 'Длина текста: ' + NumStr(CoordToMils(Round(Ltot))) + ' мил; ' +
                   'длина дуги: ' + NumStr(CoordToMils(Round(SArc))) + ' мил; ' +
                   'фактический зазор: ' + NumStr(CoordToMils(Round(GapEff))) + ' мил.';
        If (StrokeC > 0) And (Not UseTT) Then
            InfoMsg := InfoMsg + CRLF + 'Толщина штрихов: ' +
                       NumStr(CoordToMils(StrokeC)) + ' мил.';
        If Mirror Then
            InfoMsg := InfoMsg + CRLF + 'Текст зеркальный (для нижней стороны платы).';
        If Ltot > SArc + 1 Then
            InfoMsg := InfoMsg + CRLF + 'Внимание: текст длиннее дуги на ' +
                       NumStr(CoordToMils(Round(Ltot - SArc))) + ' мил - он выйдет за её пределы.';
        If GapEff < -SizeC / 2 Then
            InfoMsg := InfoMsg + CRLF + 'Внимание: символы перекрываются - уменьшите высоту текста ' +
                       'или увеличьте радиус.';
    Finally
        CacheK.Free;
        CacheW.Free;
        { закрываем транзакцию в любом случае - иначе отмена в Altium ломается }
        PCBServer.PostProcess;
    End;

    Board.ViewManager_FullUpdate;

    { ---- union --------------------------------------------------------- }
    { Процесс группировки работает с выделением, которое должно быть уже
      применено редактором, поэтому вызываем его ПОСЛЕ PostProcess.        }
    If Created > 1 Then
    Begin
        { выделяем символы уже вне транзакции }
        DeselectAll(Board);
        For I := 0 To ObjList.Count - 1 Do
        Begin
            Txt := ObjList.Items[I];
            Try
                Txt.Selected := True;
            Except
            End;
        End;

        { сколько наших объектов действительно помечено }
        SelFlags := 0;
        For I := 0 To ObjList.Count - 1 Do
        Begin
            Txt := ObjList.Items[I];
            Try
                If Txt.Selected Then SelFlags := SelFlags + 1;
            Except
            End;
        End;

        { даём редактору применить выделение }
        Board.ViewManager_FullUpdate;
        Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
        Sleep(150);
        SelBefore := Board.SelectecObjectCount;

        { Create Union From Selected Objects = PCB:ManageUnions,
          параметр Action=CreateUnion (см. AdvPcb.rcs).
          Mode=Silent / Silent=True - принятая в PCB-сервере конвенция
          "не показывать диалог": иначе всплывает окно
          "N objects added to union": передаём Mode/Silent/ShowDialog. }
        Grouped := False;
        Try
            ResetParameters;
            AddStringParameter('Action', 'CreateUnion');
            AddStringParameter('Mode', 'Silent');
            AddStringParameter('Silent', 'True');
            AddStringParameter('ShowDialog', 'False');
            RunProcess('PCB:ManageUnions');
            Grouped := True;
        Except
            Grouped := False;
        End;
        Board.ViewManager_FullUpdate;
        SelAfter := Board.SelectecObjectCount;

        InfoMsg := InfoMsg + CRLF +
                   'Union: помечено ' + IntToStr(SelFlags) + ' из ' + IntToStr(Created) +
                   ', редактор видит выделенных ' + IntToStr(SelBefore) +
                   ', после команды ' + IntToStr(SelAfter) + '.';
        If Grouped Then
            InfoMsg := InfoMsg + CRLF +
                       'Команда объединения выполнена. Если Ctrl+Z не убрал текст ' +
                       'с первого раза - union отдельный шаг отмены.'
        Else
            InfoMsg := InfoMsg + CRLF +
                       'Команда PCB:ManageUnions вернула ошибку - union не создан.';
    End;

    { после размещения ничего не оставляем выделенным: выделение нужно было
      только чтобы собрать union }
    If Created > 0 Then
        DeselectAll(Board);

    ObjList.Free;
End;

{==========================================================================}
{  Конец файла                                                             }
{==========================================================================}

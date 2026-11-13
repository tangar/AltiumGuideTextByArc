{==========================================================================}
{  AltiumGuideTextByArcScript.pas                                          }
{                                                                          }
{  Laying out text along an arc (or a full circle) on a PCB board.         }
{  A rework of AltiumGuideTextByCircleScript.pas (Igor Emelyanoff, 2023).  }
{                                                                          }
{  What changed compared to the original script:                           }
{   1. The geometry is taken from the arc SELECTED on the board (if one    }
{      is selected), or set manually: center X/Y, radius, start/end angle. }
{   2. The step between characters is computed from the REAL width of each }
{      character (bounding box measured on the board), not from            }
{      "360 / string length". Therefore there are no gaps or overlaps on   }
{      narrow and wide letters.                                            }
{   3. Rotation goes around the CENTER of the character bounding box, not  }
{      around the text anchor, so the characters sit exactly on the arc.   }
{   4. Spaces create no objects but contribute the correct gap.            }
{   5. "CCW" mode is for the lower part of the arc (the text is not        }
{      upside down).                                                       }
{   6. "Fit to arc" mode: the gaps are fitted to the arc length.           }
{   7. Pi instead of 3.14, Double instead of Float, proper types, undo:    }
{      the whole placement is one operation (one Ctrl+Z undo).             }
{   8. Altium stroke font or TrueType (Arial and any installed font).      }
{   9. The whole placement is one operation: Ctrl+Z removes it completely. }
{                                                                          }
{  How to run:                                                             }
{      DXP (File) > Run Script... > the only procedure TextAlongArc        }
{      (the parameters window is in AltiumGuideTextByArcForm.pas, the      }
{      calculation is here, in PlaceTextAlongArc). All other procedures    }
{      have parameters, so they are not shown in the Run Script list.      }
{                                                                          }
{  Conventions:                                                            }
{      Lengths are in mils; X/Y coordinates are relative to the BOARD      }
{      ORIGIN (as Altium itself displays them: Board.XOrigin/YOrigin).     }
{      Angles are in degrees, counterclockwise from the +X axis; the arc   }
{      goes from the start angle to the end angle COUNTERCLOCKWISE (like   }
{      StartAngle/EndAngle of IPCB_Arc). Numbers use a period as the       }
{      decimal separator. The file is pure ASCII.                          }
{==========================================================================}

Const
    { Length conversion: 1 mil = 0.001 inch = 0.0254 mm }
    MIL2MM = 0.0254;
    MM2MIL = 39.3700787401575;

    { Fractions of the character height used as its width in the fallback  }
    { case when the bounding box measurement on the board fails.           }
    FW_SPACE  = 0.50;
    FW_NARROW = 0.34;
    FW_WIDE   = 0.90;
    FW_NORMAL = 0.68;

    CRLF = #13#10;

{==========================================================================}
{  Helper functions                                                        }
{==========================================================================}

{ Number to string. The decimal separator is always a period, so the       }
{ string does not depend on the Windows regional settings.                 }
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

{ String to number. Understands both a period and a comma as the decimal   }
{ separator. Returns Def on error.                                         }
{ The number is parsed manually, without StrToFloat. Reason: in
  DelphiScript try/except around StrToFloat does not catch EConvertError,
  and on locales with a comma decimal separator StrToFloat('1968.5') fails.
  Here both a period and a comma are accepted and no exception is raised.
  Returns False if the string is not a number.                            }
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

{ String to number. Understands both a period and a comma as the decimal   }
{ separator. Returns Def on error.                                         }
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



{ The first SELECTED arc on the board (or Nil).                            }
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


{ Fallback estimate of the character width when the board bounding box     }
{ could not be read.                                                       }
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

{ Character measurement: bounding box width (W) in board coordinates. A    }
{ temporary object is added to the board, measured and removed, so it does }
{ not end up in the result.                                                }
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

{ Space width. Measured as the difference between the bounding boxes of    }
{ "A A" and "AA" - this also works for fonts where the space has no        }
{ bounding box of its own.                                                 }
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

{ Deselect all objects on the board. Needed before assembling the union,   }
{ so that only our characters get into it.                                 }
procedure DeselectAll(Board : IPCB_Board);
Var
    I : Integer;
Begin
    { the built-in Edit > DeSelect > All command }
    Try
        ResetParameters;
        AddStringParameter('Scope', 'All');
        RunProcess('PCB:DeSelect');
    Except
    End;
    { and just in case clear the flag on the objects }
    For I := Board.SelectecObjectCount - 1 DownTo 0 Do
    Begin
        Try
            Board.SelectecObject[I].Selected := False;
        Except
        End;
    End;
End;

{==========================================================================}
{  Laying out a string along an arc                                        }
{                                                                          }
{  CxMil, CyMil  - arc center, mils (absolute board coordinates);          }
{  RMil          - arc radius, mils;                                       }
{  A1, A2        - start and end of the arc, degrees counterclockwise;     }
{  SizeMil       - character height, mils;                                 }
{  GapMil        - gap between characters, mils (may be negative);         }
{  ShiftMil      - radial text offset: + outward, - inward, mils;          }
{  StrokeMil     - stroke thickness (stroke font only), mils;              }
{                  0 - default thickness, ignored for TrueType;            }
{  ModeInside    - False: clockwise traversal ("Clockwise"),               }
{                  True : counterclockwise ("CCW");                        }
{  FitToArc      - True: the gaps are fitted to the arc length;            }
{  Mirror        - True: mirrored text (for the bottom side of the board); }
{  FontName      - TrueType font name (when UseTT = True).                 }
{  Each character is placed so that its anchor point (the bottom of the    }
{  letter) lies on the arc - that is why periods, commas and other low     }
{  marks sit at the bottom of the line, not at its middle.                 }
{  Returns the number of created objects.                                  }
{  ErrMsg  - error text ('' = OK);                                         }
{  InfoMsg - summary of the actual dimensions and warnings.                }
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
        ErrMsg := 'Empty string.';
        Exit;
    End;
    If SizeMil <= 0 Then
    Begin
        ErrMsg := 'Character height must be greater than zero.';
        Exit;
    End;
    If RMil <= 0 Then
    Begin
        ErrMsg := 'Radius must be greater than zero.';
        Exit;
    End;

    { ---- arc span: |A2 - A1|; A1 = A2 means a full circle ---------------- }
    SpanDeg := Abs(A2 - A1);
    While SpanDeg > 360 Do SpanDeg := SpanDeg - 360;
    If SpanDeg <= 0 Then SpanDeg := 360;

    { The text STARTS at angle A1 and goes toward A2:
      "Clockwise" - clockwise (so the text reads above the arc),
      "CCW"       - counterclockwise. A2 only sets the span. }
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
        ErrMsg := 'Radius including the radial shift is <= 0.';
        Exit;
    End;
    If SizeC <= 0 Then
    Begin
        ErrMsg := 'Character height is <= 0.';
        Exit;
    End;

    If ModeInside Then DirSign := 1 Else DirSign := -1;

    CacheK := TStringList.Create;
    CacheW := TStringList.Create;
    CacheK.CaseSensitive := True;

    Board.LayerIsDisplayed[Layer] := True;
    Board.LayerIsUsed[Layer]      := True;

    { collect the created characters here: needed for selection and union }
    ObjList := TInterfaceList.Create;

    PCBServer.PreProcess;
    Try
        { ---- pass 1: character widths (cached per character) ---- }
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

        { ---- gap: fixed or fitted to the arc ---- }
        SArc := RplC * SpanRad;
        If FitToArc And (N > 1) Then
            GapEff := (SArc - TotW) / (N - 1)
        Else
            GapEff := GapC;
        Ltot := TotW + GapEff * (N - 1);

        { ---- pass 2: creating the characters on the arc ---- }
        Cum     := 0;
        Created := 0;
        For I := 1 To N Do
        Begin
            Ch  := Copy(S, I, 1);
            Idx := CacheK.IndexOf(Ch);
            Wf  := ParseInt(CacheW[Idx], 0);

            { anchor point of the character (bottom of the letter) along the
              arc. With mirrored text the sign runs to the left of the anchor,
              and Altium mirrors the whole text, so the layout must be
              reversed too, otherwise the word reads backwards. Mirror the
              position about the middle of the string:
              anchor = Ltot - Cum. }
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

                { point on the arc where the character anchor is placed }
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

        { ---- summary of the actual dimensions ---- }
        InfoMsg := 'Text length: ' + NumStr(CoordToMils(Round(Ltot))) + ' mil; ' +
                   'arc length: ' + NumStr(CoordToMils(Round(SArc))) + ' mil; ' +
                   'effective gap: ' + NumStr(CoordToMils(Round(GapEff))) + ' mil.';
        If (StrokeC > 0) And (Not UseTT) Then
            InfoMsg := InfoMsg + CRLF + 'Stroke thickness: ' +
                       NumStr(CoordToMils(StrokeC)) + ' mil.';
        If Mirror Then
            InfoMsg := InfoMsg + CRLF + 'Mirrored text (for the bottom side of the board).';
        If Ltot > SArc + 1 Then
            InfoMsg := InfoMsg + CRLF + 'Warning: the text is ' +
                       NumStr(CoordToMils(Round(Ltot - SArc))) + ' mil longer than the arc and will extend beyond it.';
        If GapEff < -SizeC / 2 Then
            InfoMsg := InfoMsg + CRLF + 'Warning: the characters overlap - reduce the text height ' +
                       'or increase the radius.';
    Finally
        CacheK.Free;
        CacheW.Free;
        { close the transaction in any case - otherwise undo in Altium breaks }
        PCBServer.PostProcess;
    End;

    Board.ViewManager_FullUpdate;

    { ---- union --------------------------------------------------------- }
    { The grouping process works with the selection, which must already be
      applied by the editor, so we call it AFTER PostProcess. }
    If Created > 1 Then
    Begin
        { select the characters outside the transaction }
        DeselectAll(Board);
        For I := 0 To ObjList.Count - 1 Do
        Begin
            Txt := ObjList.Items[I];
            Try
                Txt.Selected := True;
            Except
            End;
        End;

        { how many of our objects are actually marked }
        SelFlags := 0;
        For I := 0 To ObjList.Count - 1 Do
        Begin
            Txt := ObjList.Items[I];
            Try
                If Txt.Selected Then SelFlags := SelFlags + 1;
            Except
            End;
        End;

        { let the editor apply the selection }
        Board.ViewManager_FullUpdate;
        Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
        Sleep(150);
        SelBefore := Board.SelectecObjectCount;

        { Create Union From Selected Objects = PCB:ManageUnions,
          parameter Action=CreateUnion (see AdvPcb.rcs).
          Mode=Silent / Silent=True - the convention accepted in the PCB
          server for "do not show a dialog": otherwise the
          "N objects added to union" window pops up: pass
          Mode/Silent/ShowDialog. }
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
                   'Union: ' + IntToStr(SelFlags) + ' of ' + IntToStr(Created) +
                   ' marked, the editor sees ' + IntToStr(SelBefore) +
                   ' selected, ' + IntToStr(SelAfter) + ' after the command.';
        If Grouped Then
            InfoMsg := InfoMsg + CRLF +
                       'Union command completed. If Ctrl+Z did not remove the ' +
                       'text the first time, the union is a separate undo step.'
        Else
            InfoMsg := InfoMsg + CRLF +
                       'PCB:ManageUnions returned an error - union not created.';
    End;

    { after placement leave nothing selected: the selection was only
      needed to assemble the union }
    If Created > 0 Then
        DeselectAll(Board);

    ObjList.Free;
End;

{==========================================================================}
{  End of file                                                             }
{==========================================================================}
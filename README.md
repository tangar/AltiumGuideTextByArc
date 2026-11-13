# ArcSilk — Text Along an Arc on an Altium Board

An Altium Designer script that lays out a string of text along the selected arc (or a full
circle) on a PCB silkscreen layer. Each character gets its own tangential rotation, its own gap
based on the real glyph width, and an anchor point on the arc itself, so the text follows the
circle without gaps, overlaps, or "dancing" letters.

A rework of the `AltiumGuideTextByCircleScript.pas` script (Igor Emelyanoff, 2023).

## Features

- **Geometry from the selected arc.** Select an arc on the board and its center, radius and angles
  are filled in automatically (the "From arc" button does the same). Without a selection,
  everything is set by hand.
- **Spacing by real glyph width.** The width of each character is measured on the board instead of
  being computed as "arc length / character count". Narrow (`I`, `J`, `.`, `,`) and wide (`M`, `W`)
  letters neither clump together nor drift apart.
- **Anchored to the arc, not to the text midpoint.** Rotation goes around the center of the
  character bounding box, and the anchor point (the bottom of the letter) lies on the arc, so
  periods and commas sit on the line, not at mid-height.
- **Spaces without objects.** A space creates no object on the board but still gives the correct
  gap.
- **Two traversal directions.** "Clockwise" puts the text above the arc, "CCW" below it, so the
  text is not upside down.
- **"Fit to arc" mode** adjusts the gaps so the string fills the whole arc.
- **Altium stroke font or any TrueType font** (Arial, Times New Roman, or any font installed on
  the system), plus stroke thickness for the stroke font.
- **Mirrored text** (`MirrorFlag`) for the bottom side of the board: the letters are mirrored and
  the character order is reversed, just like Altium's built-in mirrored text.
- **Undo in one operation.** The whole placement runs in a single transaction: `Ctrl+Z` removes it
  entirely. The "Undo" / "Undo all" buttons can remove placements together with their union.
- **A union of the placed characters** — the string can then be moved and copied as one object.

## Repository layout

| File | Purpose |
| --- | --- |
| `AltiumGuideTextByArc.PrjScr` | Altium Designer script project. Contains two documents: the engine and the parameters window. |
| `AltiumGuideTextByArcScript.pas` | Engine: character measurement and the `PlaceTextAlongArc` function. No UI. |
| `AltiumGuideTextByArcForm.pas` | Modal parameters window, undo buttons, saving values to `.ini`. Entry point: `TextAlongArc`. |
| `AltiumGuideTextByArcForm.dfm` | Form description: layout of the parameters window. |
| `README.md` | This file. |

The form file `AltiumGuideTextByArcForm.dfm` is stored next to the `.pas` files, and its name
must match the form class and the `.pas` unit. Without it the project will not compile: the code
uses the components `memoText`, `eCx`, `eCy`, `eR`, `eA1`, `eA2`, `eHeight`, `eGap`, `eShift`,
`eStroke`, `rbMil`, `rbMM`, `rbIn`, `rbOut`, `cbFit`, `cbMirror`, `cbLayer`, `cbFont`, `btnArc`,
`btnPlace`, `btnClose`, `btnHelp`, `btnUndo`, `btnUndoAll`, `lblMsg`, `gbText`, `gbArc`,
`gbStyle`, `gbExport` and their labels. The `.dfm` itself is ASCII, and all captions are assigned
from code in `TextByArcFormCreate`, so the window text does not depend on the encoding the form
file was saved in.

## Requirements

- Altium Designer with DelphiScript support (PCB editor).
- A `.PcbDoc` board document open when the script is run.
- All script-project files in one folder; the form's `.pas` and `.dfm` next to each other.

## Quick start

1. Open the `.PcbDoc` and select an arc to place the text along (optional but convenient: the
   geometry is filled in automatically).
2. `DXP (File) » Run Script...` → select the script project → the
   `AltiumGuideTextByArcForm.pas` script → the `TextAlongArc` procedure. This is the only
   parameterless procedure, so it is the only one shown in the `Run Script` list.
3. In the window that opens, check the text, the arc geometry, the character height and the layer.
4. Click **Place**. The result is one operation and is undone with `Ctrl+Z`.
5. Don't like it? Use **Undo** (last placement) or **Undo all** (all placements of this session)
   without closing the window.

If an arc is selected when the window opens, its geometry overrides the values saved from the
previous run. If no arc is selected, the values from the `.ini` file are restored.

## Window parameters

### Arc

| Field | Meaning |
| --- | --- |
| Center X, Center Y | Arc center. Coordinates are **relative to the board origin** (`Board.XOrigin/YOrigin`), as Altium itself displays them. |
| Radius | Arc radius. |
| Start angle (A1) | The angle at which the text **starts**. Degrees, counterclockwise from the +X axis. |
| End angle (A2) | Only sets the arc span (the absolute difference between A2 and A1). With `A1 = A2` you get a full circle. |
| "From arc" | Fill in the center, radius and angles of the selected arc. |

The traversal direction is set not by the sign of the angles but by the radio buttons: "Clockwise"
or "CCW". The order of the values in the A1/A2 fields is adjusted automatically so the text starts
at the right place.

### Appearance

| Field | Meaning |
| --- | --- |
| Height | Character height. |
| Gap | Distance between characters; may be negative (tight packing). |
| Shift | Radial offset of the text: `+` outward from the arc, `-` inward. |
| Thickness | Stroke thickness. Stroke font only; `0` means the Altium default. |
| "Fit to arc" | Fit the gaps to the arc length instead of using the fixed "Gap". |
| "Mirror (bottom side)" | Enable `MirrorFlag` — the text reads from the back side of the board. |
| Units | Mils or millimeters. Switching recalculates the field values. |

Angles are always in degrees, regardless of the selected units.

### Layer and font

| Field | Meaning |
| --- | --- |
| Layer | "Current layer" (the board's active layer), Top Overlay, Bottom Overlay, or Mechanical 1…32. |
| Font | "Stroke (Altium)" or a TrueType font by name (Arial, Arial Narrow, Calibri, Courier New, Tahoma, Times New Roman, Verdana). |
| "Help" | Brief tips on angles, mirroring, shift and undo. |
| "Undo", "Undo all" | Roll back placements of the current session (see below). |

## How it works

1. **Measurement.** For each unique character, a text object is temporarily added to the board, its
   bounding box (`BoundingRectangle`) is read, and the object is removed — it does not end up in
   the result. The space width is measured as the difference between the bounding boxes of
   `A A` and `AA`, so it also works for fonts where the space has no bounding box of its own.
   Widths are cached per character.
2. **Gap.** With "Fit to arc" enabled: `(arc length - sum of widths) / (N - 1)`; otherwise the
   "Gap" field is used.
3. **Layout.** For each character the arc length is computed, then the angle
   `θ = A1 ± (s / (R + shift))`, the anchor point on the circle and the tangential rotation
   (`θ ± 90°`). For mirrored text the position is mirrored about the middle of the string,
   otherwise the word would read backwards.
4. **Transaction.** The whole placement is wrapped in `PCBServer.PreProcess` / `PostProcess` — one
   editor undo step.
5. **Union.** Already outside the transaction, the characters are selected and combined with the
   `PCB:ManageUnions` command (action `CreateUnion`, in silent mode), after which the selection is
   cleared. That is why the union is a separate undo step: you may need to press `Ctrl+Z` twice.
6. **Summary.** The message line of the window shows the actual text length, the arc length and the
   effective gap, plus warnings if the string is longer than the arc or the characters overlap.

## Undo and union

- "Undo" performs a `PCB:Undo` step and checks whether the number of text objects on the board
  decreased; if the first step removed only the union, it performs a second step. This removes
  exactly one placement.
- "Undo all" repeats this in a loop until the board stops shrinking, and stops so as not to wipe
  out unrelated actions.
- Step counters live in session memory: after the script restarts, the undo buttons are inactive
  again, and undo is left to the regular `Ctrl+Z`.

## Settings

The values of all fields are saved when the window closes to `AltiumGuideTextByArc.ini` next to the
board (in the folder from `Board.FileName`) and restored on the next run. The file is created on
the user's machine and is not committed to the repository.

## Limitations and known specifics

- **Sources are ASCII.** The `.pas` files contain no non-ASCII characters, so they no longer depend
  on the ANSI/UTF-8 encoding Altium uses to read them; nothing gets garbled.
- **One board instance.** The script only works with the active PCB document (`PCBServer`); it will
  not start in another editor (Schematic, etc.) and reports that.
- **Precision.** Character positions are rounded to board coordinates (`MilsToCoord`), so on very
  small radii the error is noticeable — increase the radius or the height.
- **Overlap.** A negative gap is allowed, but when `gap < -(height / 2)` the script warns about
  overlapping characters.
- **Union is a separate undo step**, see above.

## Running without the window

The engine does not depend on the form: call `PlaceTextAlongArc` from your own script. The
parameters are in mils, the coordinates are absolute, the angles are in degrees:

```pascal
Cnt := PlaceTextAlongArc(Board, 'ARC SILK',          { text }
                         CxMil, CyMil, RMil,         { center and radius }
                         0, 360,                     { A1, A2 - full circle }
                         60, 5, 0, 0,                { height, gap, shift, thickness }
                         False, True, False,         { clockwise, fit, mirror }
                         eTopOverlay,                { layer }
                         False, '',                  { stroke font }
                         ErrMsg, InfoMsg);
```

`ErrMsg` is the error text (`''` means OK), `InfoMsg` is a summary of the actual dimensions and
warnings, and the result is the number of created objects.

## For developers

- The only `Run Script` entry point is `TextAlongArc` (Form.pas). All other procedures take
  parameters and are not shown in the list.
- The math and board handling live in `...Script.pas`; the UI and settings persistence live in
  `...Form.pas`. Geometry is passed between them in mils, in coordinates relative to the board
  origin.
- Numbers are parsed and formatted manually (`TryNum`, `NumStr`, `NumFix`): `StrToFloat` cannot be
  used — on locales where the decimal separator is a comma, `StrToFloat('1968.5')` fails, and
  `try/except` in DelphiScript around it does not catch `EConvertError`. Both a period and a comma
  are accepted; the output always uses a period.
- The fallback character-width factors (used when the board bounding box cannot be read) are the
  constants `FW_SPACE`, `FW_NARROW`, `FW_WIDE`, `FW_NORMAL` at the top of `...Script.pas`.
- The layer list, the font list and all window captions are set in `TextByArcFormCreate`.
- Before committing: keep the `.pas` files ASCII, check that `A1 = A2` produces a full circle, and
  that a single placement is removed with one `Ctrl+Z`.

## License

No license file has been added to the repository; the rights to the predecessor script belong to
its author (Igor Emelyanoff).

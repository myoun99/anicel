import '../../models/frame.dart' show celNumberOrMark, inbetweenMark;
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_se_row_visual.dart';

/// THE marker a timeline cell shows for its exposure state: the timesheet
/// `X`, a drawing's name or the in-between mark, the mark on its own, or
/// nothing.
///
/// One table for every row — the dialog miniature included, which draws
/// through the row painter since 2026-09-24. Until 2026-09-03 the miniature
/// (then a widget cell of its own) kept its own copy, and that copy still
/// stopped the X at the playback range — the rule the user retired on
/// 2026-08-02 (an empty run starts where it starts). Two spellings of one
/// law drift; this is the one.
String timelineCellMarker({
  required Layer layer,
  required TimelineCellExposureState exposureState,
  required bool emptyRunStart,
  String? frameName,
}) {
  // THE marker table, all kinds (it was split across this painter and
  // TimelineFrameCell while the sparse rows were still widgets).
  return switch (exposureState) {
    // The timesheet "X": the FIRST cell of each empty run (paper-sheet
    // style). Camera rows mirror keyframes, instruction rows carry
    // instruction events and SE columns stay blank between entries on
    // paper — no X on any of those.
    //
    // It used to stop at the cut's end, which made the X the one GLYPH
    // that knew the cut's length — so a length that moved could not be
    // drawn without re-baking the glyphs. The rule is the same everywhere
    // now (user's rule 2026-08-02): an empty run starts where it starts.
    TimelineCellExposureState.uncovered =>
      !layer.kind.holdsDrawings ||
              layerKindUsesSeSheetCells(layer.kind) ||
              !emptyRunStart
          ? ''
          : 'X',
    // SE entries and instruction events draw their writing through the
    // row-level span overlays; the cells stay glyph-free paper. Camera
    // key summaries are span overlays too since B4 — the shared lane key
    // markers ([timelineUnionKeyMarkerSpans]) — so the text channel says
    // nothing there, and in particular never the paper-cell mark that used
    // to surface mid-drag when the preview outran the committed name.
    //
    // 🚨A DIRECTION row too, cels and all (유저 2026-09-12: 「이름을
    // 안보이게」): its block is its span (R27), and the span overlay is its
    // writing — not the name, and not the ○ an unnamed cel would print.
    TimelineCellExposureState.drawingStart =>
      layerKindUsesSeSheetCells(layer.kind) ||
              layer.kind.carriesInstructions ||
              layer.kind == LayerKind.camera
          ? ''
          : celNumberOrMark(frameName),
    TimelineCellExposureState.held => '',
    TimelineCellExposureState.markHeld ||
    TimelineCellExposureState.markUncovered => inbetweenMark,
  };
}

import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../timeline/property_lane_model.dart' show PropertyLaneRow;
import '../timeline/timeline_se_row_visual.dart' show layerKindUsesSeSheetCells;
import 'flip_hud_model.dart';

/// ONE ROW of the flip window for a layer row — what the timeline's window
/// and the storyboard's both draw a layer row with ([flipHudLaneRow] draws
/// its lanes).
///
/// ★One builder for both panels' rows, because the window has to say where
/// you are in the words of the panel you are working in (유저 2026-09-24:
/// 「마지막으로 만진 패널」): an S row drawn by the timeline is its cut's
/// projection and by the storyboard the track's own row, and the row is
/// handed in as whichever the panel shows — this builder never knows which.
///
/// [withRuns] false skips the runs a frame-axis window never draws (it shows
/// ONE row's blocks), keeping the row's place in the list.
/// [celNameAt] prints a block's cel name; a transition span prints its
/// writing, else the name of the term [spanDefById] finds for it, else the
/// raw id when that term was deleted (the row's own fallback).
FlipHudRow flipHudLayerRow(
  Layer layer, {
  required bool withRuns,
  required String? Function(Layer layer, int frame) celNameAt,
  required CameraInstructionDef? Function(String instructionId)? spanDefById,
}) {
  final runs = <FlipHudRun>[];
  if (withRuns) {
    if (layer.kind.bandIsInstructionsOnly) {
      // The TRANSITION row's blocks are its SPANS, and they live in its
      // instruction map rather than on its timeline — the same blocks the
      // flip counts there. ↩️This read the timeline alone and drew the row
      // empty under a flip that walked its spans.
      for (final entry in layer.instructions.entries) {
        runs.add(
          FlipHudRun(
            startIndex: entry.key,
            length: entry.value.length,
            // The name the rows print for the span — its writing, else its
            // term's name, else the raw id — so a transition named by the
            // cuts it joins (F-229) reads the same here.
            label: entry.value.displayLabel(
              spanDefById?.call(entry.value.instructionId),
            ),
          ),
        );
      }
    } else {
      for (final entry in layer.timeline.entries) {
        final exposure = entry.value;
        // Ghosts are derived edges, not authored blocks — the run-label
        // painter leaves them out for the same reason.
        if (!exposure.isDrawing || exposure.ghost) {
          continue;
        }
        runs.add(
          FlipHudRun(
            startIndex: entry.key,
            length: exposure.length ?? 1,
            label: celNameAt(layer, entry.key) ?? '',
          ),
        );
      }
    }
    runs.sort((a, b) => a.startIndex.compareTo(b.startIndex));
  }
  return FlipHudRow(
    name: layer.name,
    kind: layer.kind,
    runs: runs,
    // The cells painter's own rule for the X: only rows that hold
    // drawings print one, and SE columns stay blank between entries.
    holdsDrawings:
        layer.kind.holdsDrawings && !layerKindUsesSeSheetCells(layer.kind),
  );
}

/// A PROPERTY LANE's row in the flip window: its keys, under its own name.
/// [kind] is its owner's — a layer's, or the storyboard's for a V track's
/// lanes, whose owner is no layer at all.
FlipHudRow flipHudLaneRow(
  PropertyLaneRow lane, {
  required LayerKind kind,
  required bool withRuns,
}) {
  final keys = withRuns
      ? (lane.keyedFrames.toList()..sort())
      : const <int>[];
  return FlipHudRow(
    name: lane.label,
    kind: kind,
    isLane: true,
    // A key row has no cels, so it prints no timesheet X — the same
    // reason the cells painter withholds one there.
    holdsDrawings: false,
    runs: [
      for (final frame in keys)
        FlipHudRun(
          startIndex: frame,
          length: 1,
          isKey: true,
          holdKey: lane.holdOutFrames.contains(frame),
        ),
    ],
  );
}

/// A track's V ROW in the flip window: its CUTS on the track's axis — the
/// blocks the V row's flip steps through — each by its name.
///
/// ↩️Its PANELS, each named for its cut, while the V row's flip counted
/// them (2026-09-24); the V row counts cuts again and the panels are the
/// conte row's blocks (I-73, 유저 2026-10-08: 「v행에서는 콘티블록에
/// 서있다거나 하는걸 안하도록 … 컷 선택만 되도록」).
///
/// A track is not a layer; the rail shows its name alone, and the space
/// between cuts is not a missing drawing, so it carries no timesheet X.
FlipHudRow flipHudTrackRow({
  required String name,
  required List<StoryboardTimelineLayoutEntry> cuts,
}) => FlipHudRow(
  name: name,
  kind: LayerKind.storyboard,
  showsKindIcon: false,
  holdsDrawings: false,
  runs: [
    for (final cut in cuts)
      FlipHudRun(
        startIndex: cut.startFrame,
        length: cut.duration,
        label: cut.cut.name,
      ),
  ],
);

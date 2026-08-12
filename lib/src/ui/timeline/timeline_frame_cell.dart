import 'package:flutter/material.dart';
import '../widgets/instant_tap_region.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../input/app_input_settings.dart' show AppInput;
import '../theme/app_theme.dart';
import 'layer_label_controls.dart' show layerMarkColor;
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_style.dart';
import 'timeline_exposure_block_visual.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_se_row_visual.dart';

/// One frame cell. Deliberately CURSOR-INDEPENDENT: the selected-cell ring,
/// the selected-exposure outline and the playhead all live on the grid's
/// TimelineCursorLayer, so a playhead move never rebuilds cells (the
/// playback-performance architecture).
class TimelineFrameCell extends StatelessWidget {
  const TimelineFrameCell({
    super.key,
    required this.layer,
    required this.frameIndex,
    required this.active,
    required this.outsidePlaybackRange,
    required this.exposureState,
    required this.exposureBlockSegment,
    this.ghost = false,
    this.emptyRunStart = false,
    this.frameName,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onActivateCell,
    this.suppressPointerDownSelect,
    this.axis = Axis.horizontal,
    this.width,
    this.height,
    this.cellKeyPrefix = 'timeline-cell',
  });

  final Layer layer;
  final int frameIndex;
  final bool active;
  final bool outsidePlaybackRange;
  final TimelineCellExposureState exposureState;
  final TimelineExposureBlockVisualSegment exposureBlockSegment;

  /// A derived REPEAT instance (UI-R8): the cell dims like the
  /// out-of-range blend — timeline display only, playback and the canvas
  /// render ghosts at full quality.
  final bool ghost;

  /// Whether this cell opens an empty run — the timesheet X marks only the
  /// FIRST cell of each empty stretch, like paper sheets.
  final bool emptyRunStart;
  final String? frameName;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// Double-tap hook opening the cell's editor (SE label dialog; the
  /// instruction picker joins later). Null keeps plain taps snappy — the
  /// double-tap recognizer would delay single-tap selection otherwise.
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// A press INSIDE the frame-range selection initiates a MOVE — it must
  /// not re-seek the playhead first (UI-R22 #2, the painter rows'
  /// UI-R10 #12 rule unified onto the sparse cells). True suppresses the
  /// pointer-down select for this cell.
  final bool Function(int frameIndex)? suppressPointerDownSelect;

  /// The frame axis direction: horizontal in the layer timeline, vertical
  /// in the X-sheet. Controls which edges of an exposure block round.
  final Axis axis;

  /// Cell dimensions; default to the horizontal timeline metrics.
  final double? width;
  final double? height;

  /// Key namespace ('timeline-cell' / 'xsheet-cell') so both grids share
  /// this widget while keeping their stable test keys.
  final String cellKeyPrefix;

  static const TimelineGridMetrics _metrics = TimelineGridMetrics.defaults;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // SE and instruction rows paint the same white paper blocks as drawing
    // rows (the row overlays add writing/marks on top). Camera rows are the
    // exception — their "coverage" is the lane-key union summary, drawn as
    // accent ◆/■ markers on empty-cell styling instead of paper.
    final cameraSummaryCell = layer.kind == LayerKind.camera;
    final effectiveExposureState = cameraSummaryCell && exposureState.isCovered
        ? TimelineCellExposureState.uncovered
        : exposureState;
    final styleColors = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: effectiveExposureState,
      selected: false,
      // ⑲: the row's blocks are its layer's colour label.
      paper: layerMarkColor(layer.mark),
    );
    // Ghost repeat instances dim like out-of-range cells (UI-R8).
    final dimmed = outsidePlaybackRange || ghost;
    // No band tint anymore (UI-R10 #26): the 6f/24f line system carries
    // the rhythm on the painted drawing rows.
    final backgroundColor = dimmed
        ? Color.alphaBlend(
            AppColors.washUp.withValues(alpha: 0.54),
            styleColors.background,
          )
        : styleColors.background;
    // Blocks keep their chrome; PLAIN cells draw NO border of their own
    // (UI-R18 #2/#8) — the grid-wide overlay owns every per-cell line,
    // so sparse widget rows read exactly like the painterized rows.
    final plainGridCell = cameraSummaryCell || !exposureBlockSegment.isBlock;
    final borderColor = plainGridCell
        ? Colors.transparent
        : dimmed
        ? Color.alphaBlend(
            colorScheme.outlineVariant.withValues(alpha: 0.55),
            styleColors.border,
          )
        : styleColors.border;
    final isEmptyX = exposureState == TimelineCellExposureState.uncovered;

    final onActivateCell = this.onActivateCell;
    void select() {
      onSelectLayer(layer.id);
      onSelectFrame(frameIndex);
    }

    final cell = InkWell(
      key: ValueKey<String>('$cellKeyPrefix-${layer.id}-$frameIndex'),
      // Deliberate NO-OP: pointer selection rides the raw pointer-down
      // below. Selecting here replayed LATE — with onDoubleTap registered
      // the arena resolves ~300ms after a quick tap, so tapping cell B
      // right after cell A fired A's deferred tap AFTER B's selection (the
      // selection visibly jumped B → A → B). The recognizer itself must
      // STAY registered though: dropping it changes how much drag slop the
      // scroll viewport consumes over cells (grid scroll tests pin that).
      // Assistive-tech activation goes through the Semantics onTap.
      onTap: () {},
      onDoubleTap: onActivateCell == null
          ? null
          : () {
              select();
              onActivateCell(layer.id, frameIndex);
            },
      child: Container(
        width: width ?? _metrics.frameCellWidth,
        height: height ?? _metrics.layerRowHeight,
        alignment: Alignment.center,
        decoration: _timelineCellDecoration(
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          borderWidth: 1.0,
          exposureBlockSegment: cameraSummaryCell
              ? TimelineExposureBlockVisualSegment.none
              : exposureBlockSegment,
          axis: axis,
        ),
        child: Center(
          child: Semantics(
            onTap: select,
            child: Text(
              // Zoomed-out cells are too narrow for glyphs; the block
              // colors alone carry the overview (Premiere-style).
              (width ?? _metrics.frameCellWidth) < 14
                  ? ''
                  : _markerForCell(
                      layer: layer,
                      exposureState: exposureState,
                      emptyRunStart: emptyRunStart,
                      frameName: frameName,
                      outsidePlaybackRange: outsidePlaybackRange,
                    ),
              semanticsLabel: _semanticsLabelForCell(
                layer: layer,
                exposureState: exposureState,
                frameName: frameName,
              ),
              style: TextStyle(
                // Camera key-summary markers read like the lane key
                // diamonds (UI-R24 #9): the frame-block WHITE body —
                // selection speaks through the accent outline layers, not
                // the glyph. Dimmed outside the playback range.
                color: cameraSummaryCell && exposureState.isCovered
                    ? timelineDrawingStartColor.withValues(
                        alpha: dimmed ? 0.55 : 1,
                      )
                    : timelineCellUsesDrawingInk(effectiveExposureState)
                    ? (dimmed
                          ? timelineDrawingInkColor.withValues(alpha: 0.55)
                          : timelineDrawingInkColor)
                    : isEmptyX
                    // The "X" only marks emptiness; keep it quiet.
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                    : dimmed
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
                    : colorScheme.onSurface,
                fontWeight:
                    !isEmptyX && exposureState != TimelineCellExposureState.held
                    ? FontWeight.bold
                    : null,
              ),
            ),
          ),
        ),
      ),
    );

    // Selection must not wait out the double-tap window: with onDoubleTap
    // registered, InkWell's onTap only fires once the gesture arena
    // resolves (~300ms after a quick tap). [InstantTapRegion] takes the
    // press off the arena — pen/mouse on the DOWN, a finger on the release
    // if it did not travel (PEN-12 #6: scroll owns finger drags, but a
    // clean finger tap still selects) — under the timeline's own device
    // gate (UI-R23 feedback #2).
    //
    // R10 lifted that policy out of here: it is the app's answer for every
    // control that carries a double tap, and it was written twice inside
    // the timeline alone before it had a name.
    return InstantTapRegion(
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      onTap: (_) {
        // A press INSIDE the frame-range selection initiates a MOVE — it
        // must not re-seek the playhead first (UI-R10 #12).
        if (!(suppressPointerDownSelect?.call(frameIndex) ?? false)) {
          select();
        }
      },
      child: cell,
    );
  }
}

BoxDecoration _timelineCellDecoration({
  required Color backgroundColor,
  required Color borderColor,
  required double borderWidth,
  required TimelineExposureBlockVisualSegment exposureBlockSegment,
  required Axis axis,
}) {
  return BoxDecoration(
    color: backgroundColor,
    border: Border.all(color: borderColor, width: borderWidth),
    borderRadius: _timelineCellBorderRadius(exposureBlockSegment, axis),
  );
}

BorderRadius? _timelineCellBorderRadius(
  TimelineExposureBlockVisualSegment exposureBlockSegment,
  Axis axis,
) {
  if (!exposureBlockSegment.isBlock) {
    return null;
  }

  const blockRadius = Radius.circular(6);
  final startRadius = exposureBlockSegment.continuesFromPrevious
      ? Radius.zero
      : blockRadius;
  final endRadius = exposureBlockSegment.continuesToNext
      ? Radius.zero
      : blockRadius;
  return switch (axis) {
    Axis.horizontal => BorderRadius.horizontal(
      left: startRadius,
      right: endRadius,
    ),
    Axis.vertical => BorderRadius.vertical(top: startRadius, bottom: endRadius),
  };
}

String _markerForCell({
  required Layer layer,
  required TimelineCellExposureState exposureState,
  required bool emptyRunStart,
  String? frameName,
  required bool outsidePlaybackRange,
}) {
  return switch (exposureState) {
    // The timesheet "X": the FIRST cell of each empty run inside the
    // playback range (paper-sheet style). Camera rows mirror keyframes,
    // instruction rows carry instruction events and SE columns stay blank
    // between entries on paper — no X on any of those.
    TimelineCellExposureState.uncovered =>
      !layerKindHoldsDrawings(layer.kind) ||
              layerKindUsesSeSheetCells(layer.kind) ||
              outsidePlaybackRange ||
              !emptyRunStart
          ? ''
          : 'X',
    // SE entries and instruction events draw their writing through the
    // row-level span overlays; the cells stay glyph-free paper.
    TimelineCellExposureState.drawingStart =>
      layerKindUsesSeSheetCells(layer.kind) ||
              layerKindCarriesInstructions(layer.kind)
          ? ''
          : frameName == null || frameName.isEmpty
          ? '○'
          : frameName,
    TimelineCellExposureState.held => '',
    TimelineCellExposureState.markHeld ||
    TimelineCellExposureState.markUncovered => '●',
  };
}

String? _semanticsLabelForCell({
  required Layer layer,
  required TimelineCellExposureState exposureState,
  String? frameName,
}) {
  // Instruction spans carry their own semantics on the row overlay.
  if (layerKindCarriesInstructions(layer.kind)) {
    return null;
  }
  return switch (exposureState) {
    TimelineCellExposureState.uncovered => null,
    TimelineCellExposureState.drawingStart =>
      layer.kind == LayerKind.camera
          ? 'camera keyframe'
          : frameName == null || frameName.isEmpty
          ? 'drawing start'
          : 'drawing start $frameName',
    TimelineCellExposureState.held => 'held exposure',
    TimelineCellExposureState.markHeld ||
    TimelineCellExposureState.markUncovered => 'inbetween mark',
  };
}

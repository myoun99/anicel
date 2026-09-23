import 'package:flutter/material.dart';
import '../widgets/instant_tap_region.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/app_input_settings.dart' show AppInput;
import '../theme/app_theme.dart';
import 'layer_label_controls.dart' show layerMarkColor;
import 'axis_turn.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_marker.dart';
import 'timeline_cell_style.dart';
import 'timeline_exposure_block_visual.dart';
import 'timeline_grid_metrics.dart';

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
    this.frameName,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onSettledPress,
    this.onActivateCell,
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

  final String? frameName;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// 🚨T10's second half: the press turned out to be a TAP, so whatever was
  /// selected goes (유저: 「클릭하고 떼면 뭐든 비우게」). Null on surfaces
  /// that own no selection.
  final VoidCallback? onSettledPress;

  /// Double-tap hook opening the cell's editor (SE label dialog; the
  /// instruction picker joins later). Null keeps plain taps snappy — the
  /// double-tap recognizer would delay single-tap selection otherwise.
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// ⛔`suppressPointerDownSelect` is GONE (㉟-a). It existed so a press
  /// inside the frame-range selection could start a move without the
  /// playhead jumping first (UI-R10 #12 / UI-R22 #2) — a job ㉟ took over
  /// wholesale by picking on the RELEASE, where a drag never arrives. What
  /// was left of it was suppressing the still tap inside a selection, and
  /// that tap is supposed to clear (유저 08-12).

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
    final cellSize = Size(
      width ?? _metrics.frameCellWidth,
      height ?? _metrics.layerRowHeight,
    );

    final onActivateCell = this.onActivateCell;
    // 🚨T10 — the order is load-bearing; see the twin in
    // `timeline_row_cells_painter`. The frame moves first so that standing
    // decides about THIS cell rather than about wherever the playhead
    // happened to be.
    void select() {
      onSelectFrame(frameIndex);
      onSelectLayer(layer.id);
    }

    final cell = InkWell(
      key: ValueKey<String>('$cellKeyPrefix-${layer.id}-$frameIndex'),
      // Deliberate NO-OP: the pick rides the raw pointer stream below (㉟:
      // on the RELEASE). Selecting here replayed LATE — with onDoubleTap registered
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
        width: cellSize.width,
        height: cellSize.height,
        alignment: Alignment.center,
        decoration: _timelineCellDecoration(
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          borderWidth: 1.0,
          borderRadius: timelineCellBorderRadius(
            cameraSummaryCell
                ? TimelineExposureBlockVisualSegment.none
                : exposureBlockSegment,
            axis,
            cellExtent: extentAlong(axis, cellSize),
            crossExtent: extentAcross(axis, cellSize),
          ),
        ),
        child: Center(
          child: Semantics(
            onTap: select,
            child: Text(
              // Zoomed-out cells are too narrow for glyphs; the block
              // colors alone carry the overview (Premiere-style).
              (width ?? _metrics.frameCellWidth) < 14
                  ? ''
                  : timelineCellMarker(
                      layer: layer,
                      exposureState: exposureState,
                      // The miniature never shows an uncovered cell, so
                      // no empty run can start here.
                      emptyRunStart: false,
                      frameName: frameName,
                    ),
              semanticsLabel: timelineCellSemanticsLabel(
                layerKind: layer.kind,
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

    // The pick must not wait out the double-tap window: with onDoubleTap
    // registered, InkWell's onTap only fires once the gesture arena
    // resolves (~300ms after a quick tap). [InstantTapRegion] takes the pick
    // off the arena and — ㉟ — lands it on the RELEASE for every device: a
    // press that travels is a drag and picks nothing, a press that does not
    // is a tap and picks here. [AppInput.timelineCellPressSeeks] carries the
    // why (it used to be pen/mouse on the DOWN, touch on the release).
    //
    // R10 lifted that policy out of here: it is the app's answer for every
    // control that carries a double tap, and it was written twice inside
    // the timeline alone before it had a name.
    return InstantTapRegion(
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      // T10: the PICK. Whether it also clears is the session's call —
      // `standOnRow` holds the selection when the press landed inside it,
      // because that press is most likely the start of a move.
      //
      // ⛔The UI-R10 #12 guard that used to stand at this call site is not
      // coming back. The question belongs where the selection lives, or the
      // next surface to grow a press forgets to ask it — which is how this
      // cell and the painted strip drifted apart before.
      onTap: (_) => select(),
      // And when the press turned out to be a tap, the selection goes —
      // 유저: 「클릭하고 떼면 뭐든 비우게」.
      onSettledTap: onSettledPress == null ? null : (_) => onSettledPress!(),
      child: cell,
    );
  }
}

BoxDecoration _timelineCellDecoration({
  required Color backgroundColor,
  required Color borderColor,
  required double borderWidth,
  required BorderRadius? borderRadius,
}) {
  return BoxDecoration(
    color: backgroundColor,
    border: Border.all(color: borderColor, width: borderWidth),
    borderRadius: borderRadius,
  );
}

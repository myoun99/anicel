import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import 'timeline_cell_editor_policy.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_style.dart' show timelineDrawingInkColor;
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_range_gesture.dart';
import 'se_audio_lane.dart' show TimelineAudioLaneCallbacks;
import 'timeline_row_cells_painter.dart';
import 'timeline_row_edit_chrome.dart';
import 'timeline_row_run_labels_painter.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_instruction_row_visual.dart';
import 'timeline_se_row_visual.dart';

/// One layer's row of frame cells. CURSOR-INDEPENDENT by design: nothing
/// here reads the playhead — the selected-cell ring, the selected-exposure
/// outline and the playhead tint live on the grid's TimelineCursorLayer,
/// so a frame tick never rebuilds this row (playback-performance
/// architecture).
class TimelineFrameCellsRow extends StatelessWidget {
  const TimelineFrameCellsRow({
    super.key,
    this.axis = Axis.horizontal,
    this.keyPrefix = 'timeline',
    required this.layer,
    required this.active,
    required this.playbackFrameCount,
    required this.geometry,
    required this.crossAxisExtent,
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    this.celHasContentForLayer,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onActivateCell,
    this.instructionDefById,
    this.audioPeaksFor,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.seClipMarkerTooltip,
    this.showSeconds = false,
    this.audioLane,
    this.commaDrag,
    this.rangeGesture,
    this.runEdit,
    this.baseLayer,
    this.seSpillsIn = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  });

  final Layer layer;
  final bool active;
  final int playbackFrameCount;

  /// The LIVE frame-axis geometry — the part a ZOOM STEP moves (R28 #4).
  ///
  /// It arrives as a listenable, not as scalars, so the row's memo can key
  /// on its IDENTITY and a zoom step reaches the painted rows as a repaint
  /// plus one box relayout instead of rebuilding every visible row's whole
  /// subtree. The SPARSE kinds (SE / instruction / camera, whose cells and
  /// overlays are still a widget apiece) read `geometry.value` at build time
  /// and stay in the memo key by value — they rebuild on zoom exactly as
  /// before.
  final TimelineFrameGeometryHandle geometry;

  /// Row height (horizontal) / column width (X-sheet). NOT a zoom field.
  final double crossAxisExtent;

  /// The frame axis this row lays its cells along: horizontal in the layer
  /// timeline, vertical in the X-sheet. Every axis-aware child overlay and
  /// the cell strip dispatch on it, so both orientations share this widget.
  final Axis axis;

  /// The semantic-key namespace ('timeline' | 'xsheet'): the widget's keys
  /// read `<keyPrefix>-frame-<row|column>-...` so each surface keeps the
  /// keys its widget tests pin.
  final String keyPrefix;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set, the row builds
  /// ONCE for the FULL frame bounds — the painter windows itself off the
  /// quantized [windowBucket] (repaint once per span crossing, pure
  /// translation between), the sparse widget-cell kinds re-window their
  /// cells under the same bucket, and the overlays (grips, handles, SE
  /// writing) position content-absolutely. Null keeps the classic
  /// pre-windowed contract.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact source (see
  /// [TimelineRowCellsPainter.celHasContentForLayer]); null = no tint.
  final bool Function(Layer layer, int frameIndex)? celHasContentForLayer;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// Double-tap cell editor hook; only kinds that open an editor get it
  /// (policy: [layerKindOpensCellEditorOnDoubleTap]).
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// Resolves instruction ids to their vocabulary defs for CAM row chips;
  /// null hides instruction overlays.
  final CameraInstructionDef? Function(String instructionId)?
  instructionDefById;

  /// Waveform peaks resolver for SE rows' audio clips; null hides them.
  final AudioPeaks? Function(String filePath)? audioPeaksFor;
  final ProjectFrameRate projectFrameRate;

  /// Clipped-take marker tooltip (REC1-D); null = markers off (the
  /// clipping-notice toggle, threaded as the string itself).
  final String? seClipMarkerTooltip;

  /// The shared frames/seconds display toggle — the block duration labels
  /// (R26 #7) follow it.
  final bool showSeconds;

  /// What the audio lane may ask the session to do; this row uses the
  /// clip-remove menu and the media drop target. Null = display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// Comma-drag hooks; null hides the block edge grips.
  final TimelineCommaDragCallbacks? commaDrag;

  /// The range select/move gesture bundle (UI-R8 — the block-body move
  /// handle's successor); null keeps the row display-only.
  final TimelineRangeGestureCallbacks? rangeGesture;

  /// The run-edge [+]/[↻] handle hooks (UI-R8); null hides the handles.
  final TimelineRunEditCallbacks? runEdit;

  /// The row's COMMITTED repository layer while [layer] carries a drag
  /// preview (kept for callers even though the range gesture layer mounts
  /// row-wide and never unmounts mid-preview); null falls back to [layer].
  final Layer? baseLayer;

  /// Track-SE rows whose display clone starts with a block spilling in
  /// from an earlier cut (UI-R7 #6): the cut start draws the `~`
  /// continuation and the block's start grip stands down (its real start
  /// lives in that earlier cut).
  final bool seSpillsIn;

  @override
  Widget build(BuildContext context) {
    final commaDrag = this.commaDrag;
    final rangeGesture = this.rangeGesture;
    final axisWord = axis == Axis.vertical ? 'column' : 'row';
    // The SPARSE kinds' build-time snapshot. The painted paths never read
    // this — they take the listenable and follow it live.
    final frames = geometry.value;
    // Grips ride every drawing-holding kind; the run clusters skip the SE
    // sheet rows (their spans are sound clips, not glued cel runs).
    final wantsGrips = commaDrag != null && layerKindHoldsDrawings(layer.kind);
    final wantsRunEdges =
        runEdit != null &&
        layerKindHoldsDrawings(layer.kind) &&
        !layerKindUsesSeSheetCells(layer.kind);
    final chromeResolver = wantsGrips || wantsRunEdges
        ? TimelineRowChromeResolver(
            layer: layer,
            baseLayer: baseLayer,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            includeGrips: wantsGrips,
            includeRunEdges: wantsRunEdges,
            // The spill-in block's `~` replaces its start grip (UI-R7 #6).
            suppressStartGripAtZero:
                seSpillsIn && layerKindUsesSeSheetCells(layer.kind),
          )
        : null;

    final stack = Stack(
      key: ValueKey<String>('$keyPrefix-frame-$axisWord-area-${layer.id}'),
      children: [
        // EVERY row paints its cells as ONE CustomPaint (UI-R9 #12b, and
        // R28 #4 for the sparse kinds): the SE / instruction / camera rows
        // used to render a widget per cell, which is what made a zoom step
        // rebuild 140-180 widgets on four rows alone. The span overlays
        // above still position themselves as widgets — the cells beneath
        // them are canvas work now.
        timelineRowCellsPaintArea(
          context: context,
          keyPrefix: keyPrefix,
          layer: layer,
          active: active,
          playbackFrameCount: playbackFrameCount,
          geometry: geometry,
          crossAxisExtent: crossAxisExtent,
          axis: axis,
          windowBucket: windowBucket,
          viewportMainExtent: viewportMainExtent,
          // Instruction rows have no timeline entries — their events adapt
          // onto the shared exposure states so the cells paint the same
          // paper blocks. A TOP-LEVEL tear-off, not a closure: the painter
          // value-compares this field, and a fresh closure per build would
          // re-record the row on every pass.
          exposureStateForLayer: layer.kind == LayerKind.instruction
              ? instructionCellExposureState
              : exposureStateForLayer,
          frameNameForLayer: frameNameForLayer,
          celHasContentForLayer: celHasContentForLayer,
          onSelectLayer: onSelectLayer,
          onSelectFrame: onSelectFrame,
          onActivateCell: layerKindOpensCellEditorOnDoubleTap(layer.kind)
              ? onActivateCell
              : null,
          suppressPointerDownSelect: rangeGesture == null
              ? null
              : (frameIndex) {
                  final selection = rangeGesture.selection.value;
                  return selection != null &&
                      selection.coversLayer(layer.id) &&
                      selection.contains(frameIndex);
                },
        ),
        // NO extra section-divider overlay (R3 feedback #6): section
        // boundaries share the same single hairline as every row boundary;
        // the rail's gutter bracket carries the section identity.
        // NO empty-stretch furniture here (R5-②): uncovered timeline cells
        // are already dark — the gray wash is print-sheet-only.
        // SE audio clips paint over the paper cells, under the writing —
        // clipped to the row's drawing blocks (no block, no waveform).
        if (layerKindUsesSeSheetCells(layer.kind) && audioPeaksFor != null)
          ...timelineRowAudioOverlays(
            layer: layer,
            frameStartIndex: frames.frameStartIndex,
            leadingFrameSpacerWidth: frames.leadingFrameSpacerWidth,
            frameCellExtent: frames.frameCellExtent,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            frameRate: projectFrameRate,
            audioPeaksFor: audioPeaksFor!,
            onRemoveClip: audioLane?.onRemoveClip == null
                ? null
                : (clipIndex) => audioLane!.onRemoveClip!(layer.id, clipIndex),
            color: timelineDrawingInkColor.withValues(alpha: 0.22),
            keyPrefix: keyPrefix,
          ),
        // SE rows: the sheet's writing on the paper blocks — name box at
        // the block start plus the dialogue fitted across the span.
        if (layerKindUsesSeSheetCells(layer.kind))
          ...timelineRowSeLabelOverlays(
            layer: layer,
            frameStartIndex: frames.frameStartIndex,
            frameEndIndexExclusive: frames.frameEndIndexExclusive,
            leadingFrameSpacerWidth: frames.leadingFrameSpacerWidth,
            frameCellExtent: frames.frameCellExtent,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            keyPrefix: keyPrefix,
          ),
        // Clipped-take markers (REC1-D): mounted only when the clipping
        // notice is on — the tooltip string doubles as the switch.
        if (layerKindUsesSeSheetCells(layer.kind) &&
            seClipMarkerTooltip != null)
          ...timelineRowClipMarkerOverlays(
            layer: layer,
            frameStartIndex: frames.frameStartIndex,
            frameEndIndexExclusive: frames.frameEndIndexExclusive,
            leadingFrameSpacerWidth: frames.leadingFrameSpacerWidth,
            frameCellExtent: frames.frameCellExtent,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            tooltip: seClipMarkerTooltip!,
            color: Theme.of(context).colorScheme.error,
            keyPrefix: keyPrefix,
          ),
        // Cut-boundary `~` marks (UI-R7 #6): a sound running past the cut
        // end / spilling in from the previous cut announces its other half.
        if (layerKindUsesSeSheetCells(layer.kind))
          ...timelineRowSeContinuationMarks(
            layer: layer,
            cutFrameCount: playbackFrameCount,
            spillsInAtStart: seSpillsIn,
            frameStartIndex: frames.frameStartIndex,
            frameEndIndexExclusive: frames.frameEndIndexExclusive,
            leadingFrameSpacerWidth: frames.leadingFrameSpacerWidth,
            frameCellExtent: frames.frameCellExtent,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            keyPrefix: keyPrefix,
          ),
        // Media-browser drops land on SE blocks (sound → block frame).
        if (layerKindUsesSeSheetCells(layer.kind) &&
            audioLane?.onDropMediaAsset != null)
          ...timelineRowSeAssetDropTargets(
            layer: layer,
            frameStartIndex: frames.frameStartIndex,
            frameEndIndexExclusive: frames.frameEndIndexExclusive,
            leadingFrameSpacerWidth: frames.leadingFrameSpacerWidth,
            frameCellExtent: frames.frameCellExtent,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            onAssetDropped: (blockStartFrame, path) =>
                audioLane!.onDropMediaAsset!(layer.id, blockStartFrame, path),
            keyPrefix: keyPrefix,
          ),
        // Instruction rows: the sheet's CAM column — bar arrows or the O.L
        // bowtie on the paper block, A → B endpoint values and the name
        // snapped to the anchor cell.
        if (layer.kind == LayerKind.instruction && instructionDefById != null)
          ...timelineRowInstructionOverlays(
            layer: layer,
            frameStartIndex: frames.frameStartIndex,
            frameEndIndexExclusive: frames.frameEndIndexExclusive,
            leadingFrameSpacerWidth: frames.leadingFrameSpacerWidth,
            frameCellExtent: frames.frameCellExtent,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            defById: instructionDefById!,
            keyPrefix: keyPrefix,
          ),
        // R26 #7: each block's own length at its end cell, bottom-right
        // (the storyboard cut block's TIME label, on frame blocks). ONE
        // painter for the whole row (R28 #4) — a `Positioned` per block
        // made a zoom step re-lay-out rows x blocks boxes.
        if (layerKindHoldsDrawings(layer.kind) &&
            !layerKindUsesSeSheetCells(layer.kind))
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: ValueKey<String>('$keyPrefix-run-durations-${layer.id}'),
                painter: TimelineRowRunLabelsPainter(
                  layer: layer,
                  geometry: geometry,
                  crossAxisExtent: crossAxisExtent,
                  showSeconds: showSeconds,
                  countingBase: projectFrameRate.countingBase,
                  axis: axis,
                ),
              ),
            ),
          ),
        // The range gesture layer replaces the block-body move handle
        // (UI-R8, TVP style): a pan on the cells SELECTS a frame range —
        // a pan starting inside the current selection MOVES it. Mounted
        // UNDER the grips so the edges keep comma-drag priority. EVERY
        // layer row mounts it (UI-R20 #2: cells are cells — SE, camera
        // and instruction rows select too; what a selection can DO stays
        // kind-gated at the session seams).
        if (rangeGesture != null)
          TimelineFrameRangeGestureLayer(
            // The SLOT key (R12-③ rule, UI-R22 #1): mid-drag previews
            // add/remove sibling overlays in this Stack — without a key
            // the positional rematch REMOUNTS this layer and its dispose
            // commits the move under the pointer.
            key: ValueKey<String>('$keyPrefix-range-gesture-slot-${layer.id}'),
            layer: layer,
            geometry: geometry,
            crossAxisExtent: crossAxisExtent,
            callbacks: rangeGesture,
            axis: axis,
          ),
        // The block edit chrome — comma grips plus the TVP run-edge
        // clusters ([+] add-frames over the N/H/R property tag, hugging
        // each glued run's edges). ONE painter and ONE gesture layer for
        // the whole row (R28 #4 tier 2): these were a Positioned box per
        // grip and a two-Text Column per run edge, so a zoom step re-laid
        // out rows x (blocks + runs) of them.
        //
        // Identity vs display (R12-③, UI-R11 #1/#2): the run clusters
        // position on the DISPLAY layer (they ride previews) but call back
        // with the COMMITTED run's identity, and the layer itself no longer
        // remounts mid-gesture at all — its state lives at row level.
        if (chromeResolver != null)
          Positioned.fill(
            // The SLOT key (R12-③ rule, UI-R22 #1): mid-drag previews
            // add/remove sibling overlays in this Stack.
            key: ValueKey<String>('$keyPrefix-edit-chrome-slot-${layer.id}'),
            child: TimelineRowEditChromeLayer(
              paintKey: ValueKey<String>(
                '$keyPrefix-edit-chrome-${layer.id}',
              ),
              layerId: layer.id,
              resolver: chromeResolver,
              geometry: geometry,
              axis: axis,
              commaDrag: commaDrag,
              runEdit: runEdit,
            ),
          ),
        if (commaDrag != null && layer.kind == LayerKind.instruction)
          ...timelineRowInstructionEdgeGrips(
            layer: layer,
            frameStartIndex: frames.frameStartIndex,
            frameEndIndexExclusive: frames.frameEndIndexExclusive,
            leadingFrameSpacerWidth: frames.leadingFrameSpacerWidth,
            frameCellExtent: frames.frameCellExtent,
            crossAxisExtent: crossAxisExtent,
            commaDrag: commaDrag,
            axis: axis,
          ),
      ],
    );
    // The X-sheet column is cross-axis sized to the layer's row height (its
    // width); the horizontal row takes its height from the parent list.
    return axis == Axis.vertical
        ? SizedBox(width: crossAxisExtent, child: stack)
        : stack;
  }

}

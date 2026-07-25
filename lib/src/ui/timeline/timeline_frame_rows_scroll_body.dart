import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/audio_clip.dart' show AudioFadeCurve, AudioVolumeKey;
import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../text/app_strings.dart';
import 'property_lane_model.dart';
import 'se_audio_lane.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_drag_preview.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_folder_aggregate_row.dart';
import 'timeline_frame_cells_row.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_row_cells_painter.dart'
    show timelineRowReadsGeometryAtBuild;
import 'timeline_lane_rows.dart';

import '../../models/project_frame_rate.dart';

/// See [TimelineFrameRowsScrollBody.memoAux].
class TimelineRowMemoAux {
  const TimelineRowMemoAux({this.cameraTrack, this.instructionDefs});

  /// The active cut's camera track object (immutable — a key edit is a
  /// new instance).
  final Object? cameraTrack;

  /// The camera-instruction registry object.
  final Object? instructionDefs;
}

class TimelineFrameRowsScrollBody extends StatefulWidget {
  const TimelineFrameRowsScrollBody({
    super.key,
    required this.rows,
    required this.activeLayerId,
    required this.playbackFrameCount,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.leadingFrameSpacerWidth,
    required this.trailingFrameSpacerWidth,
    required this.totalFrameContentWidth,
    this.leadingLayerSpacerHeight = 0,
    this.trailingLayerSpacerHeight = 0,
    required this.metrics,
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    this.celHasContentForLayer,
    this.celContentTokenForLayer,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onActivateCell,
    this.instructionDefById,
    this.audioPeaksFor,
    this.seClipMarkerTooltip,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.audioLane,
    this.onSetAudioClipFadeCurve,
    this.onSetAudioClipEnvelope,
    this.resolveStrings,
    this.showSeconds = false,
    this.commaDrag,
    this.rangeGesture,
    this.laneRange,
    this.runEdit,
    this.laneEdit,
    this.dragPreview,
    this.seSpillInLayerIds = const {},
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.memoAux = const TimelineRowMemoAux(),
  });

  /// Identity tokens for the sparse rows' EXTERNAL inputs (UI-R20 #4):
  /// the camera row reads the cut's camera track and instruction rows
  /// read the instruction registry — both outside the Layer value, so
  /// their identities join the memo key here. Hosts pass the live
  /// objects; a key change is exactly an edit.
  final TimelineRowMemoAux memoAux;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set the drawing rows
  /// build once for the full bounds (their painters window themselves off
  /// the quantized bucket — repaint per span crossing, pure translation
  /// between) and the sparse rows re-window under the same bucket — a
  /// scroll rebuilds nothing here.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// Display rows: layer rows interleaved with expanded property lanes.
  /// May be a layer-axis WINDOW of the full row list — the spacer heights
  /// preserve the scroll geometry of the rows sliced away.
  final List<TimelineDisplayRow> rows;
  final LayerId? activeLayerId;
  final int playbackFrameCount;
  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;
  final double totalFrameContentWidth;

  /// Layer-axis spacers standing in for the rows above/below the built
  /// window (the vertical counterpart of the frame-axis spacers).
  final double leadingLayerSpacerHeight;
  final double trailingLayerSpacerHeight;

  final TimelineGridMetrics metrics;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact source (null = no tint).
  final bool Function(Layer layer, int frameIndex)? celHasContentForLayer;

  /// R26 #44: the per-layer empty-cel token joining the row memo key —
  /// cel pixels live outside the immutable Layer, so without this an
  /// emptiness flip (first stroke, undo to blank) would leave the row's
  /// cached widget showing the stale tint.
  final String? Function(Layer layer)? celContentTokenForLayer;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;
  final CameraInstructionDef? Function(String instructionId)?
  instructionDefById;
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// Clipped-take marker tooltip (REC1-D); null = markers off. A display
  /// fact, so it joins the row memo token below.
  final String? seClipMarkerTooltip;
  final ProjectFrameRate projectFrameRate;

  /// What the audio lane may ask the session to do; null = display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// Commits the audio-lane fade-curve toggle (AUDIO-PRO R1).
  final void Function(LayerId layerId, int clipIndex, AudioFadeCurve curve)?
  onSetAudioClipFadeCurve;

  /// Commits the audio-lane volume-envelope dialog (AUDIO-PRO R1).
  final void Function(
    LayerId layerId,
    int clipIndex,
    List<AudioVolumeKey> keys,
  )?
  onSetAudioClipEnvelope;

  /// The PROGRAM-language table for the lane menu/dialogs; null keeps
  /// English (the incremental-coverage rule).
  final AppStrings Function()? resolveStrings;

  /// The shared frames/seconds display toggle (block duration labels,
  /// R26 #7).
  final bool showSeconds;

  final TimelineCommaDragCallbacks? commaDrag;

  /// The range select/move gesture bundle (UI-R8 — the block-body move
  /// handle's successor); null keeps rows display-only.
  final TimelineRangeGestureCallbacks? rangeGesture;

  /// The LANE selection domain's gesture bundle (UI-R23 #3 part 2); null
  /// keeps the lane bands display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  /// The run-edge [+]/[↻] handle hooks (UI-R8); null hides the handles.
  final TimelineRunEditCallbacks? runEdit;
  final PropertyLaneEditCallbacks? laneEdit;

  /// The session's edit-drag preview channel: a drag step rebuilds ONLY the
  /// dragged layer's row (through its gate), never this body.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// Track-SE rows whose display clone starts with a spill-in block
  /// (UI-R7 #6: `~` at the cut start, start grip stands down).
  final Set<LayerId> seSpillInLayerIds;

  @override
  State<TimelineFrameRowsScrollBody> createState() =>
      _TimelineFrameRowsScrollBodyState();
}

/// The data snapshot a memoized row was built from. The CONTENT-deciding
/// callbacks (exposure state, frame names) join the key by equality —
/// session method tearoffs compare equal across host rebuilds, so the
/// memo still hits in production while injected test closures invalidate
/// it. Behavior-only callbacks (select/activate hooks) are deliberately
/// NOT part of the key: every timeline host callback closes over the
/// stable session only, so a cached row's captured hooks stay
/// behaviorally identical even when their object identities churn.
typedef _RowMemoInputs = ({
  Layer layer,
  bool active,
  int playbackFrameCount,
  // The frame-axis GEOMETRY, present only for rows that still read it at
  // build time (R28 #4). The painted drawing rows take the live handle and
  // follow it through repaint/relayout, so a zoom step must NOT invalidate
  // them — null here. The sparse widget-cell kinds keep the value and
  // rebuild on zoom exactly as before.
  TimelineFrameGeometry? geometry,
  double crossAxisExtent,
  ProjectFrameRate projectFrameRate,
  TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
  // R26 #44: the layer's empty-cel token — cel pixels live outside the
  // Layer value, so emptiness flips must invalidate the memo here.
  String? celContentToken,
  bool hasCommaDrag,
  bool hasRangeGesture,
  bool hasActivateCell,
  ValueListenable<TimelineDragPreview?>? dragPreview,
  // The sparse rows' EXTERNAL inputs (UI-R20 #4): identity tokens for
  // the camera track / instruction registry, and the SE spill-in flag.
  Object? auxiliaryIdentity,
  bool seSpillsIn,
  // REC1-D: the clip-marker switch is a display fact — toggling it must
  // invalidate SE rows (the memo-token discipline).
  String? seClipMarkerTooltip,
});

class _RowMemoEntry {
  const _RowMemoEntry({required this.inputs, required this.widget});

  final _RowMemoInputs inputs;
  final Widget widget;
}

class _TimelineFrameRowsScrollBodyState
    extends State<TimelineFrameRowsScrollBody> {
  /// Identity-gated row memo (the timesheet-document memo, per row): on a
  /// commit-time rebuild the untouched layers come back as the SAME Layer
  /// instances from the repository, so their rows reuse the cached widget
  /// INSTANCE and Flutter skips their whole subtree rebuild. Only kinds
  /// whose row visuals derive purely from the Layer value are memoized —
  /// camera rows read the active cut's camera track, SE rows resolve
  /// waveform peaks that load asynchronously, and lane rows are few.
  final Map<Object, _RowMemoEntry> _rowMemo = {};

  /// The LIVE frame-axis geometry every painted row follows (R28 #4).
  ///
  /// It lives here, in State, so its IDENTITY survives the rebuilds this
  /// body does on every zoom step — that identity is what lets the memo hand
  /// a painted row's cached widget back while the geometry underneath it has
  /// moved. Republished from `build`, which is safe because every listener is
  /// a render object (the row painters' `repaint`, the axis box's relayout):
  /// both marks are honoured later in the same frame. Never attach a
  /// `ValueListenableBuilder` or a `setState` listener to it.
  late final ValueNotifier<TimelineFrameGeometry> _geometry = ValueNotifier(
    _geometryFromWidget(),
  );

  TimelineFrameGeometry _geometryFromWidget() => TimelineFrameGeometry(
    frameCellExtent: widget.metrics.frameCellWidth,
    frameStartIndex: widget.frameStartIndex,
    frameEndIndexExclusive: widget.frameEndIndexExclusive,
    leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
    trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
  );

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  /// Folder rows key off their own id like every other row — the header's
  /// representative member (which DID collide with that member's own row)
  /// is gone; the prefix just keeps the band's key readable.
  String _rowKeySuffix(TimelineDisplayRow row) =>
      row.isFolder ? 'folder-${row.layer.id}' : row.lane?.laneId ?? 'cells';

  bool _rowIsMemoizable(TimelineDisplayRow row) {
    // Every non-lane row memoizes now (UI-R20 #4): the churny inputs the
    // sparse kinds depended on joined the memo token — the camera track
    // and the instruction registry ride [TimelineRowMemoAux] identities,
    // SE spill-in rides a per-layer flag, and the SE/camera display
    // clones themselves are identity-cached upstream. The audio WAVEFORM
    // stays safe because it lives on the (unmemoized) lane rows.
    // Folder rows stay unmemoized too: their aggregate runs churn
    // identity per build and the painter is a handful of rects.
    return !row.isLane && !row.isFolder;
  }

  bool _inputsMatch(_RowMemoInputs a, _RowMemoInputs b) {
    return identical(a.layer, b.layer) &&
        a.active == b.active &&
        a.playbackFrameCount == b.playbackFrameCount &&
        a.geometry == b.geometry &&
        a.crossAxisExtent == b.crossAxisExtent &&
        a.projectFrameRate == b.projectFrameRate &&
        a.exposureStateForLayer == b.exposureStateForLayer &&
        a.frameNameForLayer == b.frameNameForLayer &&
        a.celContentToken == b.celContentToken &&
        a.hasCommaDrag == b.hasCommaDrag &&
        a.hasRangeGesture == b.hasRangeGesture &&
        a.hasActivateCell == b.hasActivateCell &&
        identical(a.dragPreview, b.dragPreview) &&
        identical(a.auxiliaryIdentity, b.auxiliaryIdentity) &&
        a.seSpillsIn == b.seSpillsIn &&
        a.seClipMarkerTooltip == b.seClipMarkerTooltip;
  }

  /// The row kind's external-input identity for the memo token.
  Object? _auxiliaryIdentityFor(Layer layer) {
    return switch (layer.kind) {
      LayerKind.camera => widget.memoAux.cameraTrack,
      LayerKind.instruction => widget.memoAux.instructionDefs,
      _ => null,
    };
  }

  Widget _buildCellsRow(Layer layer, {required Layer baseLayer}) {
    return TimelineFrameCellsRow(
      layer: layer,
      baseLayer: baseLayer,
      active: layer.id == widget.activeLayerId,
      playbackFrameCount: widget.playbackFrameCount,
      geometry: _geometry,
      crossAxisExtent: widget.metrics.layerRowHeight,
      exposureStateForLayer: widget.exposureStateForLayer,
      frameNameForLayer: widget.frameNameForLayer,
      celHasContentForLayer: widget.celHasContentForLayer,
      onSelectLayer: widget.onSelectLayer,
      onSelectFrame: widget.onSelectFrame,
      onActivateCell: widget.onActivateCell,
      instructionDefById: widget.instructionDefById,
      audioPeaksFor: widget.audioPeaksFor,
      seClipMarkerTooltip: widget.seClipMarkerTooltip,
      projectFrameRate: widget.projectFrameRate,
      showSeconds: widget.showSeconds,
      audioLane: widget.audioLane,
      commaDrag: widget.commaDrag,
      rangeGesture: widget.rangeGesture,
      runEdit: widget.runEdit,
      seSpillsIn: widget.seSpillInLayerIds.contains(layer.id),
      windowBucket: widget.windowBucket,
      viewportMainExtent: widget.viewportMainExtent,
    );
  }

  Widget _buildLaneRow(TimelineDisplayRow row, Layer layer) {
    return laneIsSeAudio(row.lane!)
        ? SeAudioLaneFrameRow(
            layer: layer,
            frameStartIndex: widget.frameStartIndex,
            frameEndIndexExclusive: widget.frameEndIndexExclusive,
            leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
            trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
            metrics: widget.metrics,
            frameRate: widget.projectFrameRate,
            audioPeaksFor: widget.audioPeaksFor,
            onSetClipOffset: widget.audioLane?.onSetClipOffset == null
                ? null
                : (clipIndex, offsetFrames) =>
                      widget.audioLane!.onSetClipOffset!(
                        layer.id,
                        clipIndex,
                        offsetFrames,
                      ),
            offsetDrag: widget.audioLane?.offsetDrag,
            onSetClipFades: widget.audioLane?.onSetClipFades == null
                ? null
                : (clipIndex, fadeIn, fadeOut) =>
                      widget.audioLane!.onSetClipFades!(
                        layer.id,
                        clipIndex,
                        fadeIn,
                        fadeOut,
                      ),
            onSetClipGain: widget.audioLane?.onSetClipGain == null
                ? null
                : (clipIndex, gain) => widget.audioLane!.onSetClipGain!(
                    layer.id,
                    clipIndex,
                    gain,
                  ),
            onSetClipFadeCurve: widget.onSetAudioClipFadeCurve == null
                ? null
                : (clipIndex, curve) => widget.onSetAudioClipFadeCurve!(
                    layer.id,
                    clipIndex,
                    curve,
                  ),
            onSetClipEnvelope: widget.onSetAudioClipEnvelope == null
                ? null
                : (clipIndex, keys) =>
                      widget.onSetAudioClipEnvelope!(layer.id, clipIndex, keys),
            resolveStrings: widget.resolveStrings,
          )
        : TimelineLaneFrameRow(
            layer: layer,
            lane: row.lane!,
            frameStartIndex: widget.frameStartIndex,
            frameEndIndexExclusive: widget.frameEndIndexExclusive,
            leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
            trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
            metrics: widget.metrics,
            laneEdit: widget.laneEdit,
            // The LANE selection domain (UI-R23 #3 part 2) — layer
            // transform lanes only; the camera's atomic keyframes stand
            // down in v1.
            laneRange: layer.kind == LayerKind.camera ? null : widget.laneRange,
          );
  }

  Widget _buildRow(TimelineDisplayRow row) {
    final rowKey = ValueKey<String>(
      'timeline-row-${row.layer.id}-${_rowKeySuffix(row)}',
    );

    // RepaintBoundary per row: one row's repaint (ink, hover, drags) never
    // re-rasterizes its neighbours, and the cursor layer above repaints
    // without touching the row layers at all. The gate inside makes an
    // edge-drag step rebuild exactly this row when it is the drag target.
    Widget buildGated() => RepaintBoundary(
      key: rowKey,
      child: TimelineDragPreviewRowGate(
        dragPreview: widget.dragPreview,
        layer: row.layer,
        rowBuilder: (context, layer) => row.isFolder
            ? TimelineFolderAggregateRow(
                aggregateRuns: row.aggregateRuns,
                frameStartIndex: widget.frameStartIndex,
                frameEndIndexExclusive: widget.frameEndIndexExclusive,
                leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
                trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
                metrics: widget.metrics,
                // R28 #11: the empty-cel grey reaches the folder band.
                members: row.members,
                memberHasContentAt: widget.celHasContentForLayer,
              )
            : row.isLane
            ? _buildLaneRow(row, layer)
            : _buildCellsRow(layer, baseLayer: row.layer),
      ),
    );

    if (!_rowIsMemoizable(row)) {
      return buildGated();
    }

    final inputs = (
      layer: row.layer,
      active: row.layer.id == widget.activeLayerId,
      playbackFrameCount: widget.playbackFrameCount,
      // THE line: a row whose every geometry consumer is live keeps its memo
      // entry across a zoom step; a row with build-time span overlays (SE,
      // instruction) must miss.
      geometry: timelineRowReadsGeometryAtBuild(row.layer.kind)
          ? _geometry.value
          : null,
      crossAxisExtent: widget.metrics.layerRowHeight,
      projectFrameRate: widget.projectFrameRate,
      exposureStateForLayer: widget.exposureStateForLayer,
      frameNameForLayer: widget.frameNameForLayer,
      celContentToken: widget.celContentTokenForLayer?.call(row.layer),
      hasCommaDrag: widget.commaDrag != null,
      hasRangeGesture: widget.rangeGesture != null,
      hasActivateCell: widget.onActivateCell != null,
      dragPreview: widget.dragPreview,
      auxiliaryIdentity: _auxiliaryIdentityFor(row.layer),
      seSpillsIn: widget.seSpillInLayerIds.contains(row.layer.id),
      seClipMarkerTooltip: widget.seClipMarkerTooltip,
    );
    final cached = _rowMemo[rowKey.value];
    if (cached != null && _inputsMatch(cached.inputs, inputs)) {
      return cached.widget;
    }
    final built = buildGated();
    _rowMemo[rowKey.value] = _RowMemoEntry(inputs: inputs, widget: built);
    return built;
  }

  @override
  Widget build(BuildContext context) {
    // Republish BEFORE the rows read it: the painted rows' render objects
    // take the mark now and settle it during this frame's layout/paint.
    _geometry.value = _geometryFromWidget();
    final children = <Widget>[
      if (widget.leadingLayerSpacerHeight > 0)
        SizedBox(
          key: const ValueKey<String>('timeline-leading-layer-spacer'),
          height: widget.leadingLayerSpacerHeight,
        ),
      for (final row in widget.rows) _buildRow(row),
      if (widget.trailingLayerSpacerHeight > 0)
        SizedBox(
          key: const ValueKey<String>('timeline-trailing-layer-spacer'),
          height: widget.trailingLayerSpacerHeight,
        ),
      if (widget.rows.isEmpty)
        SizedBox(
          width: widget.totalFrameContentWidth,
          height: widget.metrics.layerRowHeight,
        ),
    ];

    // Bound the memo to the rows built this pass (scrolled-out rows just
    // rebuild when they come back).
    final liveKeys = <Object>{
      for (final row in widget.rows)
        'timeline-row-${row.layer.id}-${_rowKeySuffix(row)}',
    };
    _rowMemo.removeWhere((key, _) => !liveKeys.contains(key));

    return KeyedSubtree(
      key: const ValueKey<String>('timeline-frame-rows-scroll-body'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

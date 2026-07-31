import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/audio_clip.dart' show AudioFadeCurve, AudioVolumeKey;
import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/timeline_row_address.dart';
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
import 'timeline_cel_content_source.dart';
import 'timeline_folder_aggregate_row.dart';
import 'timeline_frame_cells_row.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_window.dart' show timelineFrameWindowSpanFor;
import 'timeline_grid_metrics.dart';
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
    this.celContent,
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

  /// R26 #44: the unworked-block tint's fact AND its event (null = no
  /// tint). The event replaced a per-layer "empty cels" token that joined
  /// the memo key: the token forced a row REBUILD and only when something
  /// else already announced, while the revision repaints the row painter
  /// the moment a cel gains pixels — and costs no per-row string build.
  final TimelineCelContentSource? celContent;
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

  /// The same geometry seen through the frame-axis WINDOW (zoom round) —
  /// handed to the rows whose every consumer reads it live, so their boxes
  /// stop being `frames * cellWidth` and a zoom step re-lays-out one box per
  /// row instead of everything in it.
  ///
  /// The SPARSE kinds keep [_geometry]: their span overlays are widgets
  /// positioned from build-time scalars, so a window that slides under them
  /// without a rebuild would leave them behind.
  ///
  /// It follows the window bucket DIRECTLY (not through build) because a
  /// scroll must not rebuild this body — the same render-object-only
  /// listener contract as [_geometry].
  late final ValueNotifier<TimelineFrameGeometry> _windowedGeometry =
      ValueNotifier(_windowedGeometryFromWidget());

  TimelineFrameGeometry _geometryFromWidget() => TimelineFrameGeometry(
    frameCellExtent: widget.metrics.frameCellWidth,
    frameStartIndex: widget.frameStartIndex,
    frameEndIndexExclusive: widget.frameEndIndexExclusive,
    leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
    trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
  );

  /// The window for the CURRENT bucket: origin quantized to the shared
  /// bucket span (so it moves once per crossing, exactly when the painters
  /// re-window), extent a constant pixel span around the viewport.
  ///
  /// Without a bucket or a measured viewport there is no window at all and
  /// every row keeps the content-sized box.
  TimelineFrameGeometry _windowedGeometryFromWidget() {
    final base = _geometryFromWidget();
    final bucket = widget.windowBucket;
    final viewport = widget.viewportMainExtent;
    final cellExtent = base.frameCellExtent;
    if (bucket == null || viewport <= 0 || cellExtent <= 0) {
      return base;
    }
    final spanPx = timelineFrameWindowSpanFor(cellExtent) * cellExtent;
    return base.windowed(
      originPx: math.max(
        0.0,
        bucket.value * spanPx - timelineFrameWindowMarginPx,
      ),
      extentPx: viewport + 2 * timelineFrameWindowMarginPx,
    );
  }

  void _handleWindowBucket() {
    _windowedGeometry.value = _windowedGeometryFromWidget();
  }

  @override
  void initState() {
    super.initState();
    widget.windowBucket?.addListener(_handleWindowBucket);
  }

  @override
  void didUpdateWidget(covariant TimelineFrameRowsScrollBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.windowBucket, widget.windowBucket)) {
      oldWidget.windowBucket?.removeListener(_handleWindowBucket);
      widget.windowBucket?.addListener(_handleWindowBucket);
    }
  }

  @override
  void dispose() {
    widget.windowBucket?.removeListener(_handleWindowBucket);
    _geometry.dispose();
    _windowedGeometry.dispose();
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

  /// The handle every row follows.
  ///
  /// The sparse kinds used to be excluded: their span overlays were placed
  /// from build-time scalars, so a window sliding under them without a
  /// rebuild would have stranded them. [TimelineFrameSpanLayout] places those
  /// overlays during layout now, so every kind rides the window.
  ValueNotifier<TimelineFrameGeometry> _geometryFor(LayerKind kind) =>
      _windowedGeometry;

  /// The folder header's frame band, plus the range gesture (R9 #1).
  ///
  /// The band itself stays pure display — the runs it draws are the
  /// members' union, so it has no comma grips, no run edges and no block
  /// of its own to move. What it gains is SELECTION: "프레임셀이면 싹 다
  /// 작동해야함" (user, 2026-07-31), and a row that shows frames but
  /// refuses to be dragged across is the exception that made the timeline
  /// feel inconsistent.
  ///
  /// The selection lands on the FOLDER ROW, not its members — the user was
  /// explicit that a folder must not behave like the transform header's
  /// select-everything ("자꾸 트랜스폼헤더마냥 전체선택시키려들지마").
  Widget _buildFolderRow(TimelineDisplayRow row) {
    final band = TimelineFolderAggregateRow(
      aggregateRuns: row.aggregateRuns,
      frameStartIndex: widget.frameStartIndex,
      frameEndIndexExclusive: widget.frameEndIndexExclusive,
      leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
      trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
      metrics: widget.metrics,
      // R28 #11: the empty-cel grey reaches the folder band.
      members: row.members,
      memberHasContentAt: widget.celContent?.hasContent,
    );
    final rangeGesture = widget.rangeGesture;
    if (rangeGesture == null) {
      return band;
    }
    // The gesture layer positions itself, so it is a DIRECT Stack child.
    return Stack(
      children: [
        band,
        TimelineFrameRangeGestureLayer(
          key: ValueKey<String>(
            'timeline-range-gesture-slot-folder-${row.layer.id}',
          ),
          row: LayerRowAddress(row.layer.id),
          geometry: _geometryFor(row.layer.kind),
          crossAxisExtent: widget.metrics.layerRowHeight,
          callbacks: rangeGesture,
        ),
      ],
    );
  }

  Widget _buildCellsRow(Layer layer, {required Layer baseLayer}) {
    return TimelineFrameCellsRow(
      layer: layer,
      baseLayer: baseLayer,
      active: layer.id == widget.activeLayerId,
      playbackFrameCount: widget.playbackFrameCount,
      geometry: _geometryFor(layer.kind),
      crossAxisExtent: widget.metrics.layerRowHeight,
      exposureStateForLayer: widget.exposureStateForLayer,
      frameNameForLayer: widget.frameNameForLayer,
      celContent: widget.celContent,
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
            ? _buildFolderRow(row)
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
      // THE line: every row's geometry consumers are live now — painters
      // through `repaint`, span overlays through the span layout — so a zoom
      // step keeps every memo entry. It stays in the record (as a constant
      // null) to say that deliberately.
      geometry: null,
      crossAxisExtent: widget.metrics.layerRowHeight,
      projectFrameRate: widget.projectFrameRate,
      exposureStateForLayer: widget.exposureStateForLayer,
      frameNameForLayer: widget.frameNameForLayer,
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
    _windowedGeometry.value = _windowedGeometryFromWidget();
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

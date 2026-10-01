import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../widgets/tick_layer.dart';
import 'lane_row_slice.dart';
import 'memo_token.dart';
import 'property_lane_model.dart';
import 'se_audio_lane.dart' show SeAudioLaneFrameRow, laneIsSeAudio;
import 'timeline_cell_exposure_state.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_cells_row.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_lane_rows.dart' show TimelineLaneFrameRow;
import 'timeline_se_row_visual.dart' show layerKindUsesSeSheetCells;

/// What a grid's CELLS row is built from beyond its drawing — the key both
/// the timeline's rows and the x-sheet's columns keep a row by (F-244).
///
/// 🚨ONE reading for both grids. The x-sheet built the same row, turned on
/// its side, from its own spelling of these inputs and kept none of them:
/// every column again at every commit and every bucket crossing — and it
/// never took the camera track, so ㉘ (a camera key that did not show until
/// another row was picked) stayed fixed on the timeline alone.
///
/// The CONTENT-deciding callbacks (exposure state, frame names) join the
/// key by equality — session method tearoffs compare equal across host
/// rebuilds, so the memo still hits in production while injected test
/// closures invalidate it. Behavior-only callbacks (select/activate hooks)
/// are deliberately NOT part of the key: every timeline host callback
/// closes over the stable session only, so a cached row's captured hooks
/// stay behaviorally identical even when their object identities churn.
typedef TimelineCellsRowFacts = ({
  // The Layer INSTANCE: on a commit-time rebuild the untouched layers come
  // back as the same instances from the repository, and `Layer.==` is a
  // deep walk over frames that this gate must never pay.
  ByIdentity<Layer> layer,
  int playbackFrameCount,
  // The frame-axis GEOMETRY, present only for rows that still read it at
  // build time (R28 #4). The painted drawing rows take the live handle and
  // follow it through repaint/relayout, so a zoom step must NOT invalidate
  // them — null here. The sparse widget-cell kinds keep the value and
  // rebuild on zoom exactly as before.
  TimelineFrameGeometry? geometry,
  double crossAxisExtent,
  ProjectFrameRate projectFrameRate,
  // #29: the substrate generation — linked cuts can share Layer
  // instances, so layer identity alone cannot say "same world".
  String substrateGeneration,
  // THE RESIZE LAW (device report 2026-08-17): the painted rows' request
  // set — the frame window their painters draw and request substrate
  // tiles for — is computed FROM this scalar, frozen into the painter at
  // build time. A viewport that widens must therefore rebuild the row,
  // or the newly exposed cells stay outside every request set forever:
  // opening a project in a small window and enlarging it left the new
  // width's blocks unrendered until a cut round-trip rebuilt the rows.
  // Zoom steps do not move it (it is a pixel quantity), so the zoom
  // memo-keep this record exists for is untouched.
  double viewportMainExtent,
  TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
  bool hasCommaDrag,
  bool hasRangeGesture,
  bool hasActivateCell,
  ByIdentity<ValueListenable<TimelineDragPreview?>?> dragPreview,
  // The sparse rows' EXTERNAL inputs (UI-R20 #4): identity tokens for
  // the camera track / instruction registry, and the SE spill-in lead
  // (F-113: the waveform's start moves with it, so it keys the memo too).
  ByIdentity<Object?> auxiliaryIdentity,
  int? spillInLeadFrames,
  // REC1-D: the clip-marker switch is a display fact — toggling it must
  // invalidate SE rows (the memo-token discipline).
  String? seClipMarkerTooltip,
  // The waveform an SE row paints arrives on its OWN — a conform lands
  // after the take or the import is placed, and the store's notification
  // rebuilds the host with the same Layer. So the peaks join the key, one
  // per sound the row draws, by identity (null while extracting). 🪦The
  // row was built while the take's conform still ran, and every rebuild
  // after handed that blank row back until an edit replaced the layer —
  // 「이름/대사 지정하니까 보이네」 (유저 09-25, card `F-178` ⑥).
  ByList<AudioPeaks?> seAudioPeaks,
  // A1 (2026-08-17): the frames/seconds display mode is a display fact
  // too — the run-duration labels ride the rows as a foreground painter,
  // so a memo hit on toggle returned the identical widget and the block
  // text stayed in the old mode until an unrelated token field moved
  // (layer activation was the user's observed workaround). Same
  // discipline as seClipMarkerTooltip and THE RESIZE LAW above. The tile
  // bake stays out of this on purpose: duration text is never baked into
  // tiles (the labels painter exists as a foreground layer precisely so
  // this toggle is a plain repaint, never a re-raster).
  bool showSeconds,
});

/// A grid as its cells rows see it: what it reads them from, and how it
/// lays them — the timeline's rows as they are, the x-sheet's columns
/// turned on their side ([axis] vertical, [keyPrefix] `xsheet`).
typedef TimelineCellsRowGrid = ({
  TimelineGridHooks hooks,
  TimelineGridMetrics metrics,
  // The handle every row follows — the grid's WINDOWED geometry, one
  // notifier for the grid's life (R28 #4), so a zoom step reaches a kept
  // row as a repaint and a relayout, never a rebuild. The sparse kinds used
  // to be excluded: their span overlays were placed from build-time
  // scalars, so a window sliding under them without a rebuild would have
  // stranded them. [TimelineFrameSpanLayout] places those overlays during
  // layout now, so every kind rides the window.
  ValueNotifier<TimelineFrameGeometry> geometry,
  ValueListenable<int>? windowBucket,
  double viewportMainExtent,
  // The range select/move gesture bundle (UI-R8 — the block-body move
  // handle's successor); null keeps rows display-only.
  TimelineRangeGestureCallbacks? rangeGesture,
  Axis axis,
  String keyPrefix,
});

/// The facts of [row]'s cells row as [grid] tells them.
TimelineCellsRowFacts timelineCellsRowFacts(
  TimelineDisplayRow row,
  TimelineCellsRowGrid grid,
) {
  final hooks = grid.hooks;
  return (
    layer: ByIdentity(row.layer),
    playbackFrameCount: hooks.playbackFrameCount,
    // THE line: every row's geometry consumers are live now — painters
    // through `repaint`, span overlays through the span layout — so a zoom
    // step keeps every memo entry. It stays in the record (as a constant
    // null) to say that deliberately.
    geometry: null,
    crossAxisExtent: grid.metrics.layerRowHeight,
    projectFrameRate: hooks.projectFrameRate,
    substrateGeneration: hooks.substrateGeneration,
    viewportMainExtent: grid.viewportMainExtent,
    exposureStateForLayer: hooks.exposureStateForLayer,
    frameNameForLayer: hooks.frameNameForLayer,
    hasCommaDrag: hooks.commaDrag != null,
    hasRangeGesture: grid.rangeGesture != null,
    hasActivateCell: hooks.onActivateCell != null,
    dragPreview: ByIdentity(hooks.dragPreview),
    auxiliaryIdentity: ByIdentity(
      timelineRowCoverageIdentity(row.layer, hooks.memoAux),
    ),
    spillInLeadFrames: hooks.spillInLeadFrames[row.layer.id],
    seClipMarkerTooltip: hooks.seClipMarkerTooltip,
    seAudioPeaks: ByList(_seAudioPeaksOf(row.layer, hooks)),
    showSeconds: hooks.showSeconds,
  );
}

/// The row kind's external-input identity — for the memo token and for the
/// painter's own "has this row changed" ([TimelineFrameCellsRow.coverageIdentity]).
///
/// The def table is external input for EVERY instruction-carrying row: a
/// renamed or recoloured term has to reach the transition row's marks too,
/// and a row whose external input is missing from this token memoises stale.
Object? timelineRowCoverageIdentity(Layer layer, TimelineRowMemoAux aux) {
  if (layer.kind == LayerKind.camera) {
    return aux.cameraTrack;
  }
  if (layer.kind.carriesInstructions) {
    return aux.instructionDefs;
  }
  return null;
}

/// What an SE row's waveform strips paint, one per sound it draws
/// ([seAudioSpans]) — nothing for every other row.
List<AudioPeaks?> _seAudioPeaksOf(Layer layer, TimelineGridHooks hooks) {
  final peaksFor = hooks.audioPeaksFor;
  if (peaksFor == null || !layerKindUsesSeSheetCells(layer.kind)) {
    return const [];
  }
  return [
    for (final span in seAudioSpans(layer)) peaksFor(span.clip.filePath),
  ];
}

/// [row]'s cells row as [grid] builds it, [layer] being the one its drag
/// gate hands over — the preview's while a drag is staged on it.
Widget timelineCellsRowFrom(
  TimelineDisplayRow row,
  Layer layer,
  TimelineCellsRowGrid grid,
) {
  final hooks = grid.hooks;
  return TimelineFrameCellsRow(
    axis: grid.axis,
    keyPrefix: grid.keyPrefix,
    layer: layer,
    baseLayer: row.layer,
    // The cells a hovering file would author. Read off the channel the
    // GATE above already subscribes to — it rebuilt this builder to hand
    // over [layer], and the span belongs to the same step — so the drag
    // preview keeps exactly one subscriber per row. The sheet shows what
    // the timeline shows: a file held over a column draws the cells it
    // would author there. ⛔Not the sheet's own rule — the same span off
    // the same channel, resolved by the same function.
    silhouette: timelineDragSilhouetteFor(hooks.dragPreview?.value, layer.id),
    playbackFrameCount: hooks.playbackFrameCount,
    geometry: grid.geometry,
    crossAxisExtent: grid.metrics.layerRowHeight,
    exposureStateForLayer: hooks.exposureStateForLayer,
    frameNameForLayer: hooks.frameNameForLayer,
    celContent: hooks.celContent,
    // ㉘: the same value the row MEMO keys on. It had to reach the
    // painter too — the memo only decides whether to rebuild the row,
    // and a rebuilt row whose painter says "nothing changed" repaints
    // nothing and re-uses the tile it baked before the key existed.
    coverageIdentity: timelineRowCoverageIdentity(row.layer, hooks.memoAux),
    onSelectLayer: hooks.onSelectLayer,
    onSelectFrame: hooks.onSelectFrame,
    onSettledPress: hooks.onSettledPress,
    onActivateCell: hooks.onActivateCell,
    instructionDefById: hooks.instructionDefById,
    instructionCrossingTooltip: hooks.instructionCrossingTooltip,
    audioPeaksFor: hooks.audioPeaksFor,
    seClipMarkerTooltip: hooks.seClipMarkerTooltip,
    projectFrameRate: hooks.projectFrameRate,
    showSeconds: hooks.showSeconds,
    audioLane: hooks.audioLane,
    onDropMediaAssetOnLayer: hooks.onDropMediaAssetOnLayer,
    acceptsMediaAssetOnLayer: hooks.acceptsMediaAssetOnLayer,
    onHoverMediaAssetOnLayer: hooks.onHoverMediaAssetOnLayer,
    onLeaveMediaAssetOnLayer: hooks.onLeaveMediaAssetOnLayer,
    commaDrag: hooks.commaDrag,
    rangeGesture: grid.rangeGesture,
    runEdit: hooks.runEdit,
    spillInLeadFrames: hooks.spillInLeadFrames[layer.id],
    windowBucket: grid.windowBucket,
    viewportMainExtent: grid.viewportMainExtent,
    substrateGeneration: hooks.substrateGeneration,
    // Resolved from the GATE's layer, per rebuild — a drag step
    // re-derives the union like the lanes re-derive (B4).
    unionLane: hooks.unionLaneForLayer?.call(layer),
  );
}

/// [row] on a layer of its own, behind its drag gate — every row of both
/// grids, cells and lanes.
///
/// A layer per row: one row's repaint (ink, hover, drags) never
/// re-rasterizes its neighbours, and the cursor layer above repaints
/// without touching the row layers at all. The gate inside makes an
/// edge-drag step rebuild exactly this row when it is the drag target —
/// and 🚨F-244: that rebuild is laid out in the row's OWN scope. A plain
/// boundary here held the paint in but not the layout: the step rebuilt in
/// the grid's layout scope, laid it out again and repainted the rows'
/// viewport around the one row that moved (a drag step is a tick:
/// [TickLayer]).
Widget timelineGatedRow(
  TimelineDisplayRow row,
  ValueListenable<TimelineDragPreview?>? dragPreview,
  Widget Function(BuildContext context, Layer layer) rowBuilder,
) => TickLayer(
  child: TimelineDragPreviewRowGate(
    dragPreview: dragPreview,
    layer: row.layer,
    slice: row.isLane ? (layer) => laneRowSlice(layer, row.lane!.laneId) : null,
    rowBuilder: rowBuilder,
  ),
);

/// The frames a grid lays its lane rows over — its window and the room it
/// leaves at either end — and the lanes' selection domain: what a lane row
/// takes of its grid beyond the cells' record.
typedef TimelineLaneRowSpan = ({
  int startIndex,
  int endIndexExclusive,
  double leadingSpacer,
  double trailingSpacer,
  // The LANE selection domain (UI-R23 #3 part 2) — EVERY row's lanes now,
  // camera included. It stood down there until 2026-08-08 on the reading
  // that the camera's keyframes are atomic; they are not (a camera row's
  // lanes edit `cut.camera.track`, a per-property TransformTrack like any
  // other). What was actually missing was the move path's camera arm, which
  // is why wiring this earlier would have written keys into the camera
  // layer's own unused track. The x-sheet's goes through the B4-④
  // escalation wrap, like the horizontal grid's.
  TimelineLaneRangeCallbacks? laneRange,
});

/// [row]'s lane at [layer] — the gate's, so a drag step shows its preview —
/// as [grid] lays its rows over [span]: the SE audio lane or a property
/// lane, the timeline's rows as they are and the x-sheet's columns turned
/// on their side.
///
/// 🚨ONE builder for both grids (`lane-rows-built-twice`, 2026-10-01). Each
/// wrote both rows out from the same hooks, and they differed only in the
/// axis, the key prefix and where the span came from — which [grid] and
/// [span] carry.
Widget timelineLaneRowFrom(
  TimelineDisplayRow row,
  Layer layer,
  TimelineCellsRowGrid grid,
  TimelineLaneRowSpan span,
) {
  final hooks = grid.hooks;
  final audioLane = hooks.audioLane;
  final onSetClipOffset = audioLane?.onSetClipOffset;
  final onSetClipFades = audioLane?.onSetClipFades;
  return laneIsSeAudio(row.lane!)
      ? SeAudioLaneFrameRow(
          axis: grid.axis,
          keyPrefix: grid.keyPrefix,
          layer: layer,
          frameStartIndex: span.startIndex,
          frameEndIndexExclusive: span.endIndexExclusive,
          leadingFrameSpacerWidth: span.leadingSpacer,
          trailingFrameSpacerWidth: span.trailingSpacer,
          metrics: grid.metrics,
          frameRate: hooks.projectFrameRate,
          audioPeaksFor: hooks.audioPeaksFor,
          spillInLeadFrames: hooks.spillInLeadFrames[layer.id],
          onSetClipOffset: onSetClipOffset == null
              ? null
              : (clipIndex, offsetFrames) =>
                    onSetClipOffset(layer.id, clipIndex, offsetFrames),
          offsetDrag: audioLane?.offsetDrag,
          onSetClipFades: onSetClipFades == null
              ? null
              : (clipIndex, fadeIn, fadeOut) =>
                    onSetClipFades(layer.id, clipIndex, fadeIn, fadeOut),
        )
      : TimelineLaneFrameRow(
          axis: grid.axis,
          keyPrefix: grid.keyPrefix,
          layer: layer,
          // R10: the previewed lane while a key drag is in flight. A grid
          // with no lanes hands back the committed row (`laneAsPreviewed`).
          lane: previewedLaneRow(
            row: row,
            previewLayer: layer,
            lanesForLayer: (layer) =>
                hooks.lanesForLayer?.call(layer) ?? const [],
          ),
          frameStartIndex: span.startIndex,
          frameEndIndexExclusive: span.endIndexExclusive,
          leadingFrameSpacerWidth: span.leadingSpacer,
          trailingFrameSpacerWidth: span.trailingSpacer,
          metrics: grid.metrics,
          laneRange: span.laneRange,
        );
}

/// What a grid keeps of a cells row: the row as built, and what it was
/// built from.
typedef KeptTimelineCellsRow = Kept<TimelineCellsRowFacts>;

/// [row]'s cells row as [kept] holds it (F-244): the one it holds while its
/// facts are what they were — on a commit, only the rows the edit touched
/// come back new — else a new one, kept.
///
/// ONE memo for the timeline's rows and the x-sheet's columns. Every
/// non-lane row keeps (UI-R20 #4): the churny inputs the sparse kinds
/// depended on joined the facts — the camera track and the instruction
/// registry ride [TimelineRowMemoAux] identities, SE spill-in rides a
/// per-layer flag, the SE row's waveform peaks ride the key by identity,
/// and the SE/camera display clones themselves are identity-cached
/// upstream. 🪦「The audio WAVEFORM stays safe because it lives on the
/// (unmemoized) lane rows」 stood here — the SE row paints one under its
/// blocks too, and it stayed blank (09-25). R10 brought FOLDER rows in:
/// their band used to churn a fresh runs list per build, which is exactly
/// why they were excluded — now the band is an identity-cached display
/// clone, so the key answers for them like any other row. Lane rows, which
/// are few and follow the cursor themselves, are not kept.
Widget keptTimelineCellsRow(
  Map<LayerId, KeptTimelineCellsRow> kept,
  TimelineDisplayRow row,
  TimelineCellsRowGrid grid,
) => keptWhileSame(
  kept,
  row.layer.id,
  timelineCellsRowFacts(row, grid),
  // R10: a FOLDER row is a cells row. Its band arrives as the display
  // clone's own timeline, so it takes the shared painter, the shared press
  // policy — the playhead can be put on it at last — and the tile bake,
  // while staying non-editable for free: every edit affordance below gates
  // on `LayerKind.holdsDrawings`, which a folder fails.
  () => timelineGatedRow(
    row,
    grid.hooks.dragPreview,
    (context, layer) => timelineCellsRowFrom(row, layer, grid),
  ),
);

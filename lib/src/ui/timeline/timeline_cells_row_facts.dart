import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/attached_layer_resolve.dart';
import '../../models/camera_instruction.dart' show CameraInstructionDef;
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/sound_cannot_play.dart';
import '../widgets/tick_layer.dart';
import 'berth_row.dart';
import 'lane_row_slice.dart';
import 'memo_token.dart';
import 'property_lane_model.dart';
import 'row_berths.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_cells_row.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_window.dart' show TimelineNextPage;
import 'timeline_frame_range_gesture.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_lane_rows.dart' show TimelineLaneFrameRow;
import 'timeline_section_runs.dart' show timelineDisplayRowExtent;
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
  // 🚨I-57 (10-13): the row's SHAPE — what of its layer decides which
  // pieces it mounts — and not the layer. What the pieces draw comes past
  // the memo ([BerthRow.shows]), so a cut switch hands back every row of
  // the same shape and repaints it. The layer INSTANCE keyed this record,
  // and the world and the cut's length with it ([BerthWorld]): every
  // crossing a scrub or a play made built every row again.
  LayerKind kind,
  bool syncedAttached,
  // The frame-axis GEOMETRY, present only for rows that still read it at
  // build time (R28 #4). The painted drawing rows take the live handle and
  // follow it through repaint/relayout, so a zoom step must NOT invalidate
  // them — null here. The sparse widget-cell kinds keep the value and
  // rebuild on zoom exactly as before.
  TimelineFrameGeometry? geometry,
  double crossAxisExtent,
  ProjectFrameRate projectFrameRate,
  // ↩️THE RESIZE LAW's view extent stood here (device report 2026-08-17):
  // the painters' request set was cut from a build-time scalar, so a
  // widened view had to build the row again. It rides the live geometry
  // now ([TimelineFrameGeometry.viewExtentPx]) — a kept row repaints on it.
  TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
  bool hasCommaDrag,
  bool hasRangeGesture,
  bool hasActivateCell,
  // The resolvers a kept row's pictures ask again when the world says
  // their answer moved — the peaks, the camera track, the term registry
  // ([BerthWorld]). By equality, as the content callbacks above: the
  // host's are methods that read the session as it stands, so the memo
  // hits, and a resolver answering from a snapshot is a new one and builds
  // the row again. 🚨I-57 (10-13): a world change used to build the row
  // again, the resolver with it — now it rebuilds the pictures alone, and
  // they ask the resolver the row was built with.
  AudioPeaks? Function(String filePath)? audioPeaksFor,
  SoundCannotPlay? Function(String filePath)? soundCannotPlay,
  CameraInstructionDef? Function(String instructionId)? instructionDefById,
  PropertyLaneRow? Function(Layer layer)? unionLaneFor,
  ByIdentity<ValueListenable<TimelineDragPreview?>?> dragPreview,
  // REC1-D: the clip-marker switch is a display fact — toggling it must
  // invalidate SE rows (the memo-token discipline).
  String? seClipMarkerTooltip,
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
  // The frame axis' scrollable — what a header graph's guest tags read
  // where they paint, to stand in the view while its picture scrolls under
  // them (I-89 ③). Null where the host has none: the view stands at the
  // frames' start.
  ScrollController? frameAxisController,
  // Where a playing run's next turn stands the frame axis — what the rows
  // bake that page's tiles for while it plays this one
  // ([TimelineFrameAxisFollower.nextPage]). Null where no run turns it.
  TimelineNextPage? Function()? nextPage,
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
    kind: row.layer.kind,
    syncedAttached: isSyncedAttachedLayer(row.layer),
    // THE line: every row's geometry consumers are live now — painters
    // through `repaint`, span overlays through the span layout — so a zoom
    // step keeps every memo entry. It stays in the record (as a constant
    // null) to say that deliberately.
    geometry: null,
    crossAxisExtent: grid.metrics.layerRowHeight,
    projectFrameRate: hooks.projectFrameRate,
    exposureStateForLayer: hooks.exposureStateForLayer,
    frameNameForLayer: hooks.frameNameForLayer,
    hasCommaDrag: hooks.commaDrag != null,
    hasRangeGesture: grid.rangeGesture != null,
    hasActivateCell: hooks.onActivateCell != null,
    audioPeaksFor: hooks.audioPeaksFor,
    soundCannotPlay: hooks.soundCannotPlay,
    instructionDefById: hooks.instructionDefById,
    unionLaneFor: hooks.unionLaneForLayer,
    dragPreview: ByIdentity(hooks.dragPreview),
    seClipMarkerTooltip: hooks.seClipMarkerTooltip,
    showSeconds: hooks.showSeconds,
  );
}

/// The world [row]'s cells row draws as [grid] tells it — what reaches a
/// kept row past its memo ([BerthRow.world]) with the layer it stands for.
BerthWorld timelineCellsRowWorld(
  TimelineDisplayRow row,
  TimelineCellsRowGrid grid,
) {
  final hooks = grid.hooks;
  return (
    // #29: the substrate generation — linked cuts can share Layer
    // instances, so layer identity alone cannot say "same world".
    substrateGeneration: hooks.substrateGeneration,
    drawnFrameCount: hooks.runFrames,
    // F-113: the waveform's start moves with it.
    spillInLeadFrames: hooks.spillInLeadFrames[row.layer.id],
    cutId: hooks.cutId,
    // The sparse rows' EXTERNAL inputs (UI-R20 #4): the camera track / the
    // instruction registry.
    coverageIdentity: ByIdentity(
      timelineRowCoverageIdentity(row.layer, hooks.memoAux),
    ),
    // The waveform an SE row paints arrives on its OWN — a conform lands
    // after the take or the import is placed, and the store's notification
    // rebuilds the host with the same Layer. So the peaks join the world,
    // one per sound the row draws, by identity (null while extracting).
    // 🪦The row was built while the take's conform still ran, and every
    // rebuild after handed that blank row back until an edit replaced the
    // layer — 「이름/대사 지정하니까 보이네」 (유저 09-25, card `F-178` ⑥).
    seAudioPeaks: ByList(_seAudioPeaksOf(row.layer, hooks)),
    // And why each cannot be played, as it moves: a conform landing or
    // failing rebuilds the host as a waveform landing does.
    seSoundsCannotPlay: ByList(_seSoundsCannotPlayOf(row.layer, hooks)),
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

/// What an SE row's waveform strips paint, one per sound it draws.
List<AudioPeaks?> _seAudioPeaksOf(Layer layer, TimelineGridHooks hooks) =>
    _perSound(layer, hooks.audioPeaksFor);

/// Why each sound an SE row draws cannot be played.
List<SoundCannotPlay?> _seSoundsCannotPlayOf(
  Layer layer,
  TimelineGridHooks hooks,
) => _perSound(layer, hooks.soundCannotPlay);

/// What [ask] answers of each sound an SE row draws ([seAudioSpans]) —
/// nothing for every other row, nor where nothing asks.
List<T?> _perSound<T>(Layer layer, T? Function(String filePath)? ask) {
  if (ask == null || !layerKindUsesSeSheetCells(layer.kind)) {
    return const [];
  }
  return [for (final span in seAudioSpans(layer)) ask(span.clip.filePath)];
}

/// [row]'s cells row as [grid] builds it — for the layer it stands for
/// when it is built; what it shows after that comes past its memo, from the
/// gate above it ([keptTimelineCellsRow]).
Widget timelineCellsRowFrom(TimelineDisplayRow row, TimelineCellsRowGrid grid) {
  final hooks = grid.hooks;
  final world = timelineCellsRowWorld(row, grid);
  return TimelineFrameCellsRow(
    axis: grid.axis,
    keyPrefix: grid.keyPrefix,
    layer: row.layer,
    drawnFrameCount: world.drawnFrameCount,
    geometry: grid.geometry,
    crossAxisExtent: grid.metrics.layerRowHeight,
    exposureStateForLayer: hooks.exposureStateForLayer,
    frameNameForLayer: hooks.frameNameForLayer,
    celContent: hooks.celContent,
    // ㉘: the same value the row's WORLD carries. It had to reach the
    // painter too — the world only decides whether to rebuild the
    // pictures, and a rebuilt picture whose painter says "nothing changed"
    // repaints nothing and re-uses the tile it baked before the key
    // existed.
    coverageIdentity: world.coverageIdentity.value,
    onSelectLayer: hooks.onSelectLayer,
    onSelectFrame: hooks.onSelectFrame,
    onSettledPress: hooks.onSettledPress,
    onActivateCell: hooks.onActivateCell,
    instructionDefById: hooks.instructionDefById,
    instructionCrossingTooltip: hooks.instructionCrossingTooltip,
    audioPeaksFor: hooks.audioPeaksFor,
    soundCannotPlay: hooks.soundCannotPlay,
    seClipMarkerTooltip: hooks.seClipMarkerTooltip,
    projectFrameRate: hooks.projectFrameRate,
    showSeconds: hooks.showSeconds,
    onDropMediaAssetOnSeBlock: hooks.onDropMediaAssetOnSeBlock,
    onDropMediaAssetOnLayer: hooks.onDropMediaAssetOnLayer,
    acceptsMediaAssetOnLayer: hooks.acceptsMediaAssetOnLayer,
    onHoverMediaAssetOnLayer: hooks.onHoverMediaAssetOnLayer,
    onLeaveMediaAssetOnLayer: hooks.onLeaveMediaAssetOnLayer,
    commaDrag: hooks.commaDrag,
    rangeGesture: grid.rangeGesture,
    runEdit: hooks.runEdit,
    spillInLeadFrames: world.spillInLeadFrames,
    cutId: world.cutId,
    windowBucket: grid.windowBucket,
    nextPage: grid.nextPage,
    stepsUntilShown: hooks.stepsUntilShown,
    substrateGeneration: world.substrateGeneration,
    unionLaneFor: hooks.unionLaneForLayer,
  );
}

/// [row] on a layer of its own, behind its drag gate — every lane row of
/// both grids. A cells row is kept by its shape and stands under its gate
/// instead ([keptTimelineCellsRow]).
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
/// as [grid] lays its rows over [span]: the timeline's rows as they are and
/// the x-sheet's columns turned on their side. ↩️A lane was the SE audio
/// lane's waveform band or a property lane's, until the band went (I-140).
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
  // A lane the enlarged graph folds is laid as a row of its strip (I-89
  // ③D) — the metrics are what carry a lane row's extent across — so its
  // keys stay in the strip, as small as a cell that tight makes any mark
  // (D39-2): the mock's 5판 keeps a thinned lane's keys.
  final metrics = row.folded
      ? grid.metrics.copyWith(
          layerRowHeight: timelineDisplayRowExtent(row, grid.metrics),
        )
      : grid.metrics;
  return TimelineLaneFrameRow(
    axis: grid.axis,
    keyPrefix: grid.keyPrefix,
    layer: layer,
    // R10: the previewed lane while a key drag is in flight. A grid
    // with no lanes hands back the committed row (`laneAsPreviewed`).
    lane: previewedLaneRow(
      row: row,
      previewLayer: layer,
      lanesForLayer: hooks.lanesOf,
    ),
    frameStartIndex: span.startIndex,
    frameEndIndexExclusive: span.endIndexExclusive,
    leadingFrameSpacerWidth: span.leadingSpacer,
    trailingFrameSpacerWidth: span.trailingSpacer,
    metrics: metrics,
    laneRange: span.laneRange,
  );
}

/// What a grid keeps of its cells rows, berth by berth.
typedef KeptTimelineCellsRows = KeptByBerth<TimelineCellsRowFacts>;

/// [row]'s cells row as [kept] holds it in its berth of [berths] (F-244):
/// the one it holds while its facts are what they were, else a new one,
/// kept — and the layer it stands for and the world it draws handed down
/// past it by its drag gate ([TimelineDragPreviewRowGate.shows]).
///
/// 🚨I-57 (10-13): the facts are the row's SHAPE, so a cut switch hands
/// every row of the same shape back whole — its pieces that draw the
/// layer are built again, alone, and the rest repaints. They named the
/// row's layer, and the cut's world with it, so every crossing a scrub or
/// a play made built every row again. On a commit, only the rows the edit
/// touched draw anew.
///
/// The BERTH stands OUTSIDE the keep, given this pass's layer and world:
/// inside it, a kept row would have kept its last layer too. The row's
/// tick layer stands INSIDE ([TickLayer]): a new one per pass would lay out
/// every row again. And the gate stands on that tick layer, reading the
/// pass from the berth above it — 🚨F-446 (10-24): a drag step is a tick
/// (F-244), and the gate's rebuild is laid out there, alone.
/// ↩️It stood with the berth, in the grid's layout scope (I-57): a cut-end
/// trim on the user's cut derived again every row its length draws a
/// ghost on, and each step laid out and repainted the rows' viewport.
///
/// The sheet shows what the timeline shows: a file held over a column
/// draws the cells it would author there. ⛔Not the sheet's own rule — the
/// same span off the same channel, resolved by the same gate.
///
/// ONE memo for the timeline's rows and the x-sheet's columns. Every
/// non-lane row keeps (UI-R20 #4): the churny inputs the sparse kinds
/// depended on reach the row through its world — the camera track and the
/// instruction registry ride [TimelineRowMemoAux] identities, SE spill-in
/// rides a per-layer flag, the SE row's waveform peaks ride by identity,
/// and the SE/camera display clones themselves are identity-cached
/// upstream. 🪦「The audio WAVEFORM stays safe because it lives on the
/// (unmemoized) lane rows」 stood here — the SE row paints one under its
/// blocks too, and it stayed blank (09-25). R10 brought FOLDER rows in:
/// their band used to churn a fresh runs list per build, which is exactly
/// why they were excluded — now the band is an identity-cached display
/// clone, so it reaches a kept row like any other row's layer. Lane rows,
/// which are few and follow the cursor themselves, are not kept.
Widget keptTimelineCellsRow(
  KeptTimelineCellsRows kept,
  RowBerthMap berths,
  TimelineDisplayRow row,
  TimelineCellsRowGrid grid,
) => BerthRow(
  layer: row.layer,
  world: timelineCellsRowWorld(row, grid),
  child: kept.keep(
    berths,
    row,
    timelineCellsRowFacts(row, grid),
    // R10: a FOLDER row is a cells row. Its band arrives as the display
    // clone's own timeline, so it takes the shared painter, the shared
    // press policy — the playhead can be put on it at last — and the tile
    // bake, while staying non-editable for free: every edit affordance
    // gates on `LayerKind.holdsDrawings`, which a folder fails.
    () => TickLayer(
      child: TimelineDragPreviewRowGate.shows(
        dragPreview: grid.hooks.dragPreview,
        layer: row.layer,
        child: timelineCellsRowFrom(row, grid),
      ),
    ),
  ),
);

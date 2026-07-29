import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Listenable, ValueListenable;
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerHoverEvent, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;

import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_mark.dart';
import '../models/project.dart';
import '../models/project_frame_rate.dart';
import '../models/se_audio_spans.dart';
import '../models/timeline_coverage.dart' show TimelineBlockEdge, drawingBlocks;
import '../models/track.dart';
import '../models/track_id.dart';
import '../models/transform_track.dart';
import '../services/audio/audio_peaks_extractor.dart';
import '../services/cut_frame_composite_plan.dart' show layerIdentityPose;
import 'audio/waveform_painter.dart';
import 'storyboard_cut_fade_policy.dart';
import 'storyboard_cut_blocks_painter.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnailResolver;
import 'storyboard_layer_policy.dart';
import 'storyboard_timeline_layout.dart';
import 'theme/app_theme.dart';
import 'timeline/layer_label_controls.dart';
import 'widgets/field_slider.dart';
import 'timeline/property_lane_model.dart'
    show PropertyLaneEditCallbacks, PropertyLaneRow, TimelineDisplayRow;
import 'timeline/timeline_row_span_resolver.dart'
    show resolveBlockMoveTargetLayer;
import 'timeline/se_audio_lane.dart' show SeAudioLaneFrameRow;
import 'timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow, TimelineLaneFrameRow;
import 'timeline/timeline_ruler_cursor_overlay.dart';
import 'timeline/transform_lane_policy.dart'
    show transformGroupHeader, transformGroupHeaderLane, transformPropertyLanes;
import 'timeline/timeline_drag_preview.dart';
import 'timeline/timeline_cell_style.dart'
    show
        timelineBaseGridAlpha,
        timelineDrawingInkColor,
        timelineRangeSelectionBandDecoration,
        timelineSelectedFrameBorderColor;
import 'timeline/timeline_exposure_comma_drag_handle.dart'
    show TimelineBlockEdgeGrip, timelineBlockEdgeGripPlacement;
import 'timeline/timeline_row_edit_chrome.dart'
    show
        TimelineRowChromeResolver,
        TimelineRowEditChromeLayer,
        TimelineRowGripCallbacks;
import 'timeline/timeline_frame_geometry.dart'
    show TimelineFrameGeometry, TimelineFrameGeometryHandle;
import 'timeline/timeline_frame_range_gesture.dart'
    show TimelineFrameRangeGestureLayer, TimelineRangeGestureCallbacks;
import '../models/storyboard_coverage.dart'
    show
        StoryboardCoverageCell,
        storyboardCoverageCells,
        storyboardDivisionKeys;
import '../models/timeline_frame_range.dart' show TimelineFrameRangeSelection;
import '../models/timeline_row_address.dart'
    show LayerRowAddress, TimelineRowAddress, TrackRowAddress;
import '../models/track_frame_range.dart';
import 'timeline/timeline_frame_span_layout.dart'
    show TimelineFixedFrameSpanLayer, TimelineFrameSpan;
import 'timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'timeline/timeline_frame_coordinate_policy.dart'
    show frameIndexFromLocalX;
import 'timeline/timeline_frame_range_policy.dart'
    show endlessTrailingFrames, endlessViewportFillFrames;
import '../models/layer_kind.dart';
import 'timeline/timeline_frame_ruler.dart';
import 'timeline/timeline_edge_auto_pan.dart';
import 'timeline/timeline_frame_window.dart';
import 'timeline/timeline_grid_metrics.dart';
import 'timeline/timeline_horizontal_scrollbar_rail.dart';
import 'timeline/timeline_layer_controls_header.dart';
import 'timeline/timeline_vertical_scrollbar_rail.dart';
import 'timeline/timeline_playhead.dart' show timelinePlayheadColor;
import 'timeline/timeline_row_filter.dart';
import 'timeline/timeline_scale.dart';
import 'timeline/timeline_se_row_visual.dart'
    show SePaperSpan, SeSpanVisual, timelineRowClipMarkerOverlays;
import 'timeline/timeline_zoom_anchor_policy.dart';

/// The drag hooks the STRIP's edges need, mirroring the timeline's
/// comma-drag callbacks: live preview per step, ONE undo on release.
///
/// There is one shape of edge on this row, and where it sits decides what
/// it re-times (design, user's rule 2026-07-25; edge unification
/// 2026-07-28): the first panel's leading edge is the cut's START, and
/// EVERY trailing edge — inner and last alike — is that panel's comma,
/// with the cut's length riding the row end. Hence two begins and one set
/// of continuations — the grip that started decides which session verb
/// the rest of the drag belongs to, and the mount that knows the geometry
/// is the one that says so.
class StoryboardStripEdgeCallbacks {
  const StoryboardStripEdgeCallbacks({
    required this.onCutEdgeBegin,
    required this.onCommaBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  /// Trims the cut itself. Returns whether the drag may start (deleted
  /// cuts refuse).
  final bool Function(CutId cutId, TimelineBlockEdge edge) onCutEdgeBegin;

  /// Resizes the comma of the panel whose block is keyed at
  /// [blockStartIndex] (CUT-LOCAL) on [cutId]'s storyboard row — an inner
  /// trailing edge; the later panels ripple and the cut's length follows.
  /// Returns whether the drag may start.
  final bool Function(CutId cutId, int blockStartIndex) onCommaBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// Whole-block MOVE hooks (R10-④): dragging a cut block horizontally
/// SLIDES the cut along the frame axis (session
/// begin/update/end/cancelCutMoveDrag — live preview, ONE undo per drag).
/// Reordering moved to a long-press lift.
class StoryboardCutMoveCallbacks {
  const StoryboardCutMoveCallbacks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final bool Function(CutId cutId) onBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// Movie-end drag hooks (UI-R20 #3): the storyboard's end line edits the
/// MOVIE's final length — the project's trailing gap past the last cut —
/// never the cuts themselves (session begin/update/end/cancelMovieEndDrag;
/// live preview through the drag channel, ONE undo on release).
class StoryboardMovieEndCallbacks {
  const StoryboardMovieEndCallbacks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final bool Function() onBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// Cut RANGE-selection hooks (UI-R18 #1): a drag on the cut row paints a
/// contiguous run selection (anchor = where the drag started, head = the
/// pointer's frame now); a drag that starts INSIDE the selection routes to
/// [StoryboardCutMoveCallbacks] instead and slides the whole run; a plain
/// tap clears. The timeline's frame-range selection model applied to cuts.
class StoryboardCutSelectCallbacks {
  const StoryboardCutSelectCallbacks({
    required this.selectedRange,
    required this.onDrag,
    required this.onClear,
  });

  /// The live selection (null = none) — a frame RANGE on the track's
  /// global axis, which blocks tint from directly (they are selected when
  /// the range covers them), color-only per the selection language.
  final ValueListenable<TrackFrameRangeSelection?> selectedRange;

  /// A select-drag step stated on the track's GLOBAL FRAME axis. Ordinals
  /// used to be the panel-facing form, which is what kept the cut row on a
  /// gesture of its own; frames are the axis the shared range gesture
  /// already speaks, and the session snaps them to whole cuts with the
  /// same rule the timeline snaps cells with.
  /// [headRowDelta] is the Excel-style cross-row reach (feedback #14): how
  /// many rows DOWN the rail the pointer has travelled from the one the
  /// drag started on. The session walks its own row order with it, so this
  /// stays a plain integer rather than a row the panel had to name.
  final void Function({
    required TrackId trackId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    int headRowDelta,
  })
  onDrag;
  final VoidCallback onClear;
}

/// Range selection on a track-SE row — the cut row's hooks, one row up and
/// one axis over: the same shared gesture, the same track-global selection,
/// only the snap material differs (sounds instead of cuts).
class StoryboardSeSelectCallbacks {
  const StoryboardSeSelectCallbacks({
    required this.selectedRange,
    required this.onDrag,
    required this.onClear,
    this.move,
  });

  /// The live selection (null = none), shared with the cut row: the S rows
  /// and the V row are rows of ONE track-axis selection, so starting one
  /// here is what takes it off the cut row.
  final ValueListenable<TrackFrameRangeSelection?> selectedRange;

  /// A select-drag step on the track's GLOBAL frame axis. [headRowDelta]
  /// reaches across the rail's rows exactly as the cut row's does.
  final void Function({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    int headRowDelta,
  })
  onDrag;
  final VoidCallback onClear;

  /// Sliding the selected sounds — a drag that STARTS inside the
  /// selection, the timeline's grammar. Null keeps the row select-only.
  final StoryboardRangeMoveCallbacks? move;
}

/// Range selection on the cut block's STRIP — the cut's own panels.
///
/// The strip is a CUT-OWNED row, so unlike every other row of this panel it
/// speaks the cut's local axis: its selection is the ordinary cut-local one
/// the timeline uses, on that cut's storyboard layer. The mount converts,
/// which is why these callbacks take a cut-local index and a layer.
class StoryboardStripSelectCallbacks {
  const StoryboardStripSelectCallbacks({
    required this.selection,
    required this.onDrag,
    required this.onClear,
    this.move,
  });

  /// The live cut-local selection (the session's own), so the strip can
  /// answer whether a frame is inside it.
  final ValueListenable<TimelineFrameRangeSelection?> selection;

  /// A select-drag step in the anchor cut's LOCAL frames.
  final void Function({
    required LayerId layerId,
    required int anchorIndex,
    required int headIndex,
  })
  onDrag;
  final VoidCallback onClear;

  /// Sliding the selected PANELS — a drag that starts inside the
  /// selection. On a row that tiles its cut there is no free space to
  /// re-time into, so every move this allows is a reorder and the panels
  /// can never leave the cut between them. Null keeps the strip
  /// select-only.
  final StoryboardRangeMoveCallbacks? move;
}

/// A row's half of the shared range gesture's MOVE mode: the selected
/// blocks slide, previewing live and committing once on release.
///
/// One shape for every row of this panel — the S rows slide sounds along
/// the track's global axis, the strip slides a cut's panels along the cut's
/// own — because the gesture and the session's move machine are the same
/// for both. What differs is which begin the mount hands over, and that is
/// the mount's to know.
class StoryboardRangeMoveCallbacks {
  const StoryboardRangeMoveCallbacks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final bool Function(LayerId layerId) onBegin;

  /// [targetLayerId] is the sibling row the pointer has reached — null
  /// means it never left the row it started on, which is every step of a
  /// strip drag (a cut has exactly one storyboard row to be on).
  final void Function(int frameDelta, LayerId? targetLayerId) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// A press on a row's CELLS: the row that was pressed and the track-global
/// frame under the pointer. The timeline's cell contract (`onSelectLayer` +
/// `onSelectFrame` on the raw pointer down) stated once for a rail whose
/// rows are not all layers — the landing verbs differ per row kind, the
/// press does not.
typedef StoryboardRowFramePress =
    void Function(TimelineRowAddress row, int globalFrame);

class StoryboardPanel extends StatefulWidget {
  const StoryboardPanel({
    super.key,
    required this.project,
    required this.activeCutId,
    this.onRowFramePress,
    this.activeLayerId,
    this.selectedRow,
    this.onSelectLayer,
    this.onSelectTrack,
    this.stripEdges,
    this.cutMove,
    this.cutSelect,
    this.stripSelect,
    this.movieEnd,
    this.trackLaneHeight = defaultTrackLaneHeight,
    this.pixelsPerFrame = 8,
    this.showSeconds = false,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.playheadFrame,
    this.frameCachedSignal,
    this.onSeekGlobalFrame,
    this.onScrubGlobalFrame,
    this.onScrubEnd,
    this.isFrameCached,
    this.thumbnailFor,
    this.audioPeaksFor,
    this.seClipMarkerTooltip,
    this.seLanePreview,
    this.expandedSeAudioRows = const {},
    this.onToggleSeRowLane,
    this.expandedTransformTracks = const {},
    this.onToggleTrackLane,
    this.expandedTransformGroups = const {},
    this.onToggleTransformGroup,
    this.cutLaneEditFor,
    this.layerLaneEdit,
    this.activeCutFrameIndex = 0,
    this.onSelectFrameIndex,
    this.poseDisplaySize,
    this.onSetCutFade,
    this.onToggleLayerVisibility,
    this.onToggleLayerMuted,
    this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.onLayerMarkSelected,
    this.layerFxEnabledOf,
    this.onToggleLayerFx,
    this.cutFxEnabledOf,
    this.onToggleCutFx,
    this.cutPictureVisibleOf,
    this.onToggleCutPictureVisibility,
    this.seCommaDrag,
    this.seSelect,
    this.onSetAudioClipOffset,
    this.dragPreview,
    this.legend,
    this.visibilitySoloEnabled = false,
    this.opacityDragPreview,
    this.legendOpacityValue = 1.0,
  });

  /// Blocks are strictly frame-linear (Premiere-style): a large minimum
  /// width would make neighbours overlap when zoomed out. The tiny floor
  /// only keeps zero-length cuts visible.
  static const double _minBlockWidth = 8;

  // Wide enough for the timeline-style rows (icon + names) the rail mirrors.
  // 140 → 240 when the S rows gained the timeline-parity layer controls
  // (R4-⑨ '완벽통일'); the control set needs the width, like the timeline
  // rail's own widening for the fx switch.
  // 240 → the timeline rail's width (UI-R5 storyboard unification): the
  // rail rows share the timeline's slot grid and the legend header sits
  // on top, so the columns line up across both panels.
  static const double _trackLabelWidth = 372;
  static const double _rulerHeight = 24;

  /// The V rows' height, and the range the adjustment moves it through.
  ///
  /// ONE height for every V track, not one per track (user's rule): the
  /// rows are the same kind of thing, and a rail whose rows disagree about
  /// height stops reading as a rail. The S rows keep their own sizing —
  /// they twirl audio lanes open, so height means something else there.
  ///
  /// The floor sits below [StoryboardCutBlocksPainter.bandsMinBlockHeight]
  /// on purpose: shrinking past it FOLDS the bands, which is the compact
  /// look, not a broken one.
  static const double defaultTrackLaneHeight = 64;
  static const double minTrackLaneHeight = 28;
  static const double maxTrackLaneHeight = 160;
  static const double trackLaneHeightStep = 12;

  /// The vertical scrollbar's lane width — the TIMELINE's
  /// [TimelineGridMetrics.verticalScrollbarWidth] by value (UI-R10 #15/#21
  /// unification: same rail, same lane, same column geometry).
  static const double _scrollbarLaneWidth = 14;

  /// The bottom horizontal scrollbar row's height — the timeline grids'
  /// value (UI-R10 #21 3-row unification).
  static const double _bottomScrollbarRailHeight = 16;

  static const double _timelineTrailingPadding = 12;

  final Project project;

  /// The session's scoped edit-drag channel (R10-③). The panel substitutes
  /// cut-trim previews into [project] INTERNALLY, so a drag step rebuilds
  /// only the cut-layout-dependent pieces (blocks, lanes, ruler width) —
  /// the SE rows (waveforms) and the label rails hold their built
  /// subtrees. Null renders [project] as-is.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// Null = no cut selected (gap state, UI-R9 #3): no highlight,
  /// cut-scoped rail controls stand down.
  final CutId? activeCutId;

  /// The cells' press — see [StoryboardRowFramePress]. It replaced a
  /// cut-selected callback on the V row and a per-BLOCK tap zone on the S
  /// rows, neither of which could answer for an empty cell.
  final StoryboardRowFramePress? onRowFramePress;

  /// The session's active layer — the drawing target, and what the S rows'
  /// cut-scoped controls act on. It no longer decides the HIGHLIGHT: see
  /// [selectedRow].
  final LayerId? activeLayerId;

  /// THE selected row, track rows and layer rows in one address space
  /// (`EditorSessionManager.selectedRow`). Exactly one row highlights, the
  /// way the timeline has exactly one selected layer row — the V row used
  /// to light from "the active cut lives on this track" and the S rows from
  /// [activeLayerId], which are unrelated states, so both could read as
  /// selected at once. Null = no row highlighted.
  final TimelineRowAddress? selectedRow;

  /// Tapping an S-row label selects its TRACK layer (the same session
  /// selection a timeline row tap makes). Null keeps labels display-only.
  final ValueChanged<LayerId>? onSelectLayer;

  /// Tapping a V-row label selects its TRACK (UI-R18 #6): the session
  /// promotes that track's cut under the shared global playhead to the
  /// active cut. Null keeps V labels display-only.
  final ValueChanged<TrackId>? onSelectTrack;

  /// Edge-grip hooks for the strip's panel edges: the first panel's front
  /// edge re-times the cut's lead, and every trailing edge is its panel's
  /// comma with the cut's length riding the row end (edge unification).
  /// Null hides the grips.
  final StoryboardStripEdgeCallbacks? stripEdges;

  /// Every V row's height — the rail's label row and the strip row read
  /// the same number, because they are two columns of one row.
  final double trackLaneHeight;

  /// Whole-block move hooks (R10-④): a horizontal drag on a block's body
  /// slides the cut (gap authoring + edge-style pushes). Null disables
  /// the slide (blocks then only tap-select / long-press reorder).
  final StoryboardCutMoveCallbacks? cutMove;

  /// Cut range-selection hooks (UI-R18 #1). With these set, a body drag
  /// on an unselected cut SELECTS a run and only drags starting inside
  /// the selection slide (through [cutMove]); null keeps every body drag
  /// a direct slide.
  final StoryboardCutSelectCallbacks? cutSelect;

  /// Range selection on the STRIP — the cut's own panels, on the cut's own
  /// axis. Null keeps the strip display-only.
  final StoryboardStripSelectCallbacks? stripSelect;

  /// Movie-end drag hooks (UI-R20 #3); null hides the end grip (the line
  /// still shows).
  final StoryboardMovieEndCallbacks? movieEnd;

  /// Frame-axis zoom, owned by the host (the panel header's shared zoom
  /// slider drives it).
  final double pixelsPerFrame;

  /// Conte-sheet time display for the cut totals: frames (`48f`) or
  /// seconds+frames (`2+00`), toggled by the panel header's shared button.
  final bool showSeconds;
  final ProjectFrameRate projectFrameRate;

  /// Track-global frame the playhead line sits on (playback position while
  /// playing, the active cut's playhead otherwise) — a LISTENABLE, the
  /// cursor-layer pattern (W4): only the playhead overlay and the ruler
  /// subscribe, so scrub moves and playback ticks never rebuild the
  /// panel's strips/blocks/rails. Null (or a null value) hides the line.
  final ValueListenable<int?>? playheadFrame;

  /// Repaints the ruler's cached-range (green) bar as the prerender cache
  /// fills; null leaves the bar static per build.
  final Listenable? frameCachedSignal;

  /// Tapping or scrubbing the ruler reports the track-global frame under
  /// the pointer. Null makes the ruler display-only.
  final ValueChanged<int>? onSeekGlobalFrame;

  /// Ruler-drag scrub path: per-move frames go here (cursor-only, no
  /// commit) and the drag's release fires [onScrubEnd] to commit once.
  /// Null falls back to [onSeekGlobalFrame] per move.
  final ValueChanged<int>? onScrubGlobalFrame;
  final VoidCallback? onScrubEnd;

  /// Cached-range resolver in track-global frames for the ruler's green
  /// strip (same look as the timeline header's).
  final bool Function(int globalFrame)? isFrameCached;

  /// Build-time resolver for the cut blocks' first-frame thumbnails (the
  /// store behind it kicks async renders and re-notifies). The image stays
  /// OWNED BY THE RESOLVER — blocks paint it without disposing. Null hides
  /// the thumbnail strip.
  final StoryboardThumbnailResolver? thumbnailFor;

  /// Waveform peaks per audio file for the SE rows (null hides waveforms).
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// The recorded-take clipping warning tooltip (REC1-D): non-null mounts
  /// the red block-corner marker on clipped SE spans, matching the
  /// timeline and X-sheet. Null hides it (clipping notice setting off).
  final String? seClipMarkerTooltip;

  /// The armed SE lane's in-flight take PREVIEW while recording rolls
  /// (REC1-C): stands in for the matching track lane in the DISPLAY rows
  /// only — rail controls, commits and undo keep the repository lane.
  final Layer? seLanePreview;

  /// Twirled-down S rows ([seRowKey]): an enlarged read-only waveform lane
  /// under the row, the timeline Audio lane's storyboard sibling.
  final Set<String> expandedSeAudioRows;
  final void Function(Track track, int slot)? onToggleSeRowLane;

  /// Twirled-down V tracks (track id value): the cut-level Transform group
  /// under the track row (V-track full transform, R6 — the AE lanes plus
  /// the cut-fade Opacity strip).
  final Set<String> expandedTransformTracks;
  final void Function(Track track)? onToggleTrackLane;

  /// Twirled-open Transform GROUP HEADERS (AE group collapse, default
  /// collapsed): track id values for the V tracks, [seRowKey]s for the S
  /// rows. One set — the key shapes never collide.
  final Set<String> expandedTransformGroups;
  final void Function(String groupKey)? onToggleTransformGroup;

  /// Per-cut lane edit hooks for the V track's Transform lanes: the host
  /// builds callbacks that edit THAT cut's cut-level transform track (one
  /// undo per edit). The carrier Layer the substrate hands back is
  /// synthetic — the closures capture their cut. Null = display-only.
  final PropertyLaneEditCallbacks? Function(Cut cut)? cutLaneEditFor;

  /// Lane edit hooks for the S rows' Transform lanes — the timeline's
  /// layer-transform lane editing on the ACTIVE cut's slot layers. Null =
  /// display-only.
  final PropertyLaneEditCallbacks? layerLaneEdit;

  /// The ACTIVE cut's playhead (cut-local): the lane labels' value column
  /// and keyframe navigator read here.
  final int activeCutFrameIndex;

  /// Key-navigator jumps (◀ ▶) select this cut-local frame on the session.
  final ValueChanged<int>? onSelectFrameIndex;

  /// The display space the CUT pose resolves over for the value column
  /// (the camera's output frame — the same space playback and the MP4
  /// bake use). Null hides the V lanes' values.
  final CanvasSize? poseDisplaySize;

  /// Commits a cut-fade handle drag (one undo); null makes the Opacity
  /// lane display-only. The fade is transparency (R3b) — no per-cut
  /// target color rides along any more.
  final void Function(CutId cutId, int fadeInFrames, int fadeOutFrames)?
  onSetCutFade;

  // --- Timeline-parity layer controls ('완벽통일', R4-⑨) -------------------
  // The S rows carry the SAME layer controls as the timeline rows, acting
  // on the ACTIVE cut's slot layer (the storyboard rail is track-global;
  // the active cut supplies the concrete layer). All LayerId-generic —
  // wired to the same session methods the timeline host uses.
  final ValueChanged<LayerId>? onToggleLayerVisibility;
  final ValueChanged<LayerId>? onToggleLayerMuted;
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  final void Function(LayerId layerId, LayerMark mark)? onLayerMarkSelected;

  final bool Function(LayerId layerId)? layerFxEnabledOf;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// The timeline's rail legend over this panel's rail (UI-R5): same
  /// bulk flyouts + master opacity bar, acting on the ACTIVE cut's layers
  /// through the same session hooks. Null renders a display-only legend.
  final LayerLegendCallbacks? legend;

  /// Whether the visibility solo mode is engaged (legend eye state color).
  final bool visibilitySoloEnabled;

  /// The session's live opacity-drag preview (UI-R6 #2): S-row sliders
  /// follow a master-bar sweep live instead of waiting for the release
  /// commit.
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  /// The legend master bar's RESTING value: the last value committed
  /// through the bar (UI-R6 #2) — not an average of the rows.
  final double legendOpacityValue;

  /// V-row display toggles (R9, session view state, ACTIVE-cut scoped like
  /// the S-row layer controls): the fx switch bypasses the cut-level
  /// Transform group (pose + fade) in the playback display, the eye hides
  /// the cut's picture there. Null hides the buttons.
  final bool Function(CutId cutId)? cutFxEnabledOf;
  final ValueChanged<CutId>? onToggleCutFx;
  final bool Function(CutId cutId)? cutPictureVisibleOf;
  final ValueChanged<CutId>? onToggleCutPictureVisibility;

  /// Range selection on the S rows — the cut row's hooks one row up, in
  /// the same track-axis selection. Null keeps the S rows unselectable.
  final StoryboardSeSelectCallbacks? seSelect;

  /// The timeline's comma-drag hooks for the ACTIVE cut's SE blocks (the
  /// session's exposure edge drags are active-cut scoped — other cuts'
  /// blocks select on tap first). Null hides the grips.
  final TimelineCommaDragCallbacks? seCommaDrag;

  /// The Audio lane's slide edit for the ACTIVE cut's clips (same reused
  /// timeline lane substrate). Null keeps the lane display-only.
  final void Function(LayerId layerId, int clipIndex, int offsetFrames)?
  onSetAudioClipOffset;

  /// The per-S-row view-state key: `<trackId>-<slot>`.
  static String seRowKey(Track track, int slot) => '${track.id.value}-$slot';

  @override
  State<StoryboardPanel> createState() => _StoryboardPanelState();
}

class _StoryboardPanelState extends State<StoryboardPanel> {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.projectFrameRate.countingBase;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  int _endlessTrailingFrames = 0;

  /// The live horizontal offset as a VALUE channel (UI-R15, the
  /// timeline's B1 pattern): scroll pixels update this notifier — the
  /// pinned ruler's translate follows it with zero panel rebuilds. Only
  /// an endless-extent change (growth/shrink) still goes through
  /// setState.
  final ValueNotifier<double> _horizontalScrollOffset = ValueNotifier<double>(
    0,
  );

  /// The QUANTIZED window bucket (UI-R16, shared policy): the ruler
  /// painters' repaint trigger — fires once per span crossing, so the
  /// frames between crossings are pure translation.
  final ValueNotifier<int> _horizontalWindowBucket = ValueNotifier<int>(0);

  /// The cut under the pointer. With the blocks painted there is no widget
  /// per cut to hold a hover state, so this one notifier serves every V
  /// row and a hover costs a repaint instead of a rebuild.
  final ValueNotifier<CutId?> _hoveredCutId = ValueNotifier<CutId?>(null);

  /// The V rows' frame-axis geometry, as the LIVE handle the shared range
  /// gesture reads at press time (the timeline's rows hold the same kind of
  /// handle). Republished from `build`, which is safe here because nothing
  /// listens to it — the gesture layer only ever reads `.value`.
  final TimelineFrameGeometryHandle _frameGeometry =
      TimelineFrameGeometryHandle(
        const TimelineFrameGeometry(
          frameCellExtent: 8,
          frameStartIndex: 0,
          frameEndIndexExclusive: 0,
        ),
      );

  @override
  void initState() {
    super.initState();
    _horizontalController.addListener(_handleHorizontalScroll);
  }

  @override
  void didUpdateWidget(covariant StoryboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Zoom-around-playhead: the playhead stays put on screen through zoom
    // when visible; otherwise (or with no playhead) the leading-edge frame
    // anchors. Shared policy with the timeline grids.
    if (oldWidget.pixelsPerFrame != widget.pixelsPerFrame &&
        _horizontalController.hasClients) {
      _horizontalController.jumpTo(
        zoomAnchoredScrollOffset(
          oldOffset: _horizontalController.position.pixels,
          oldPixelsPerFrame: oldWidget.pixelsPerFrame,
          newPixelsPerFrame: widget.pixelsPerFrame,
          viewportExtent: _horizontalController.position.viewportDimension,
          anchorFrame: widget.playheadFrame?.value,
        ),
      );
    }
  }

  void _handleHorizontalScroll() {
    if (!_horizontalController.hasClients) {
      return;
    }
    _watchHorizontalScrollActivity();
    final offset = _horizontalController.offset;
    final position = _horizontalController.position;
    final next = endlessTrailingFrames(
      baseFrameCount: _totalFrames(
        widget.project,
        buildStoryboardTimelineLayout(widget.project),
      ),
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _scale.pixelsPerFrame,
      // Past-content cells vanish once scrolled out of view (UI-R12 #16,
      // the timeline's shrink rule): discrete moves may shrink right
      // away, gesture pixels wait for the settle listener.
      allowShrink: !position.isScrollingNotifier.value,
    );
    // Repaint-only scroll (UI-R15→R16): the offset rides the value
    // channel (translate), the quantized bucket triggers the painters;
    // widgets rebuild ONLY when the endless extent itself changes.
    _horizontalScrollOffset.value = offset;
    _horizontalWindowBucket.value = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: _scale.pixelsPerFrame,
    );
    if (next != _endlessTrailingFrames) {
      setState(() => _endlessTrailingFrames = next);
    }
  }

  ScrollPosition? _watchedHorizontalPosition;

  void _watchHorizontalScrollActivity() {
    final position = _horizontalController.position;
    if (identical(position, _watchedHorizontalPosition)) {
      return;
    }
    _watchedHorizontalPosition?.isScrollingNotifier.removeListener(
      _handleHorizontalScrollActivity,
    );
    _watchedHorizontalPosition = position;
    position.isScrollingNotifier.addListener(_handleHorizontalScrollActivity);
  }

  /// Scroll settled: apply the lazy endless SHRINK (UI-R12 #16 — the
  /// timeline's rule, unified): the extent contracts back toward the
  /// cuts' end so the scrollbar thumb recovers, never mid-gesture.
  void _handleHorizontalScrollActivity() {
    final position = _watchedHorizontalPosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    final next = endlessTrailingFrames(
      baseFrameCount: _totalFrames(
        widget.project,
        buildStoryboardTimelineLayout(widget.project),
      ),
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _scale.pixelsPerFrame,
      allowShrink: true,
    );
    if (next != _endlessTrailingFrames && mounted) {
      setState(() => _endlessTrailingFrames = next);
    }
  }

  /// Ruler edge auto-pan (UI-R12 #16, the timeline's rule unified): a
  /// scrub past the viewport edge pans the strip — rightward it
  /// deliberately OVERSHOOTS the built extent, and the growth listener
  /// materializes the frames the overshot view needs. The scrollbar and
  /// scroll physics stay clamped at the built cells.
  void _autoPanRulerEdge(double delta) {
    if (!_horizontalController.hasClients) {
      return;
    }
    final position = _horizontalController.position;
    final target = math.max(0.0, position.pixels + delta);
    if (target != position.pixels) {
      _horizontalController.jumpTo(target);
    }
  }

  TimelineScale get _scale => TimelineScale(
    pixelsPerFrame: widget.pixelsPerFrame,
    minBlockWidth: StoryboardPanel._minBlockWidth,
  );

  @override
  void dispose() {
    _horizontalController.removeListener(_handleHorizontalScroll);
    _watchedHorizontalPosition?.isScrollingNotifier.removeListener(
      _handleHorizontalScrollActivity,
    );
    _verticalController.dispose();
    _horizontalController.dispose();
    _horizontalScrollOffset.dispose();
    _horizontalWindowBucket.dispose();
    _hoveredCutId.dispose();
    _frameGeometry.dispose();
    super.dispose();
  }

  /// The widest content edge across every track (blocks can outgrow their
  /// duration via the minimum block width) plus trailing padding — the
  /// ruler and playhead overlay both span it.
  double _timelineContentWidth(
    List<StoryboardTimelineLayoutEntry> entries,
    TimelineScale scale,
  ) {
    var width = 0.0;
    for (final entry in entries) {
      final right =
          scale.leftForFrame(entry.startFrame) +
          scale.widthForDuration(entry.duration);
      if (right > width) {
        width = right;
      }
    }
    return width + StoryboardPanel._timelineTrailingPadding;
  }

  /// The MOVIE length in frames (UI-R20 #3): the cuts' content end plus
  /// the project's trailing gap — the end line sits here, and dragging
  /// it edits the trailing gap (never the cuts).
  int _totalFrames(
    Project project,
    List<StoryboardTimelineLayoutEntry> entries,
  ) {
    var total = 0;
    for (final entry in entries) {
      if (entry.endFrame > total) {
        total = entry.endFrame;
      }
    }
    return total + project.trailingFrames;
  }

  /// The ACTIVE cut when it lives on [track]; null otherwise (the rail's
  /// lane controls then stand down, like the S-row layer controls).
  Cut? _activeCutOf(Track track) {
    for (final cut in track.cuts) {
      if (cut.id == widget.activeCutId) {
        return cut;
      }
    }
    return null;
  }

  /// The cut sitting under the current global playhead on track
  /// [trackIndex] (UI-R13 #2: the V-row fx/eye act on THIS, each track
  /// independently). Null when the playhead is unwired or the index is a
  /// gap on this track — the buttons then no-op, never gray out.
  Cut? _cutAtPlayheadOn(int trackIndex) {
    final globalFrame = widget.playheadFrame?.value;
    if (globalFrame == null) {
      return null;
    }
    for (final entry in buildStoryboardTimelineLayout(widget.project)) {
      if (entry.trackIndex == trackIndex &&
          globalFrame >= entry.startFrame &&
          globalFrame < entry.endFrame) {
        return entry.cut;
      }
    }
    return null;
  }

  /// The shared lane substrate speaks Layer; the V track's cut-level lanes
  /// ride a synthetic carrier — its id only feeds the widget keys, the
  /// edit closures capture their cut ([StoryboardPanel.cutLaneEditFor]).
  Layer _vLaneCarrier(String seed) =>
      Layer(id: LayerId('v-$seed'), name: 'V', frames: const []);

  /// The cut's WINDOW of its owning TRACK's transform lanes (R4a): the
  /// per-cut strips and labels still speak cut-local frames; this is the
  /// projection they read — the SE display clone's idiom for the V
  /// effects.
  TransformTrack _cutWindowTransformOf(Cut cut) {
    for (final track in widget.project.tracks) {
      var start = 0;
      for (final candidate in track.cuts) {
        start += candidate.leadingGapFrames;
        if (candidate.id == cut.id) {
          return trackTransformCutWindow(
            track.transformTrack,
            startFrame: start,
            duration: cut.duration,
          );
        }
        start += candidate.duration;
      }
    }
    return TransformTrack.empty();
  }

  /// The Transform-group member lanes of one V track, header first: the
  /// AE lane list valued against the ACTIVE cut's window (label-only rows
  /// while the active cut lives elsewhere). The Opacity lane stays LAST —
  /// its strip is the cut-fade envelope row, and the labels must line up.
  List<PropertyLaneRow> _cutTransformLanes(Track track, Cut? activeCut) {
    final expanded = widget.expandedTransformGroups.contains(track.id.value);
    final displaySize = widget.poseDisplaySize;
    final window = activeCut == null
        ? TransformTrack.empty()
        : _cutWindowTransformOf(activeCut);
    final lanes = activeCut == null
        ? transformPropertyLanes(
            TransformTrack.empty(),
            includeAnchorAndOpacity: true,
          )
        : transformPropertyLanes(
            window,
            includeAnchorAndOpacity: true,
            poseAt: displaySize == null
                ? null
                : (frame) => trackPoseAt(window, frame, displaySize),
            anchorAt: displaySize == null
                ? null
                : (frame) =>
                      trackAnchorPointAt(window, frame) ??
                      CanvasPoint(
                        x: displaySize.width / 2,
                        y: displaySize.height / 2,
                      ),
            opacityAt: (frame) => trackFadeOpacityAt(window, frame),
          );
    return [
      transformGroupHeader(expanded: expanded),
      if (expanded) ...lanes.where((lane) => !lane.isGroupHeader),
    ];
  }

  /// One S row's Transform-group lanes, header first, valued against the
  /// ACTIVE cut's slot layer (the same raw-track resolution the timeline's
  /// value column uses — fx bypass never touches authoring values).
  List<PropertyLaneRow> _seTransformLanes(
    Track track,
    int slot,
    Cut? activeCut,
    Layer? layer,
  ) {
    final expanded = widget.expandedTransformGroups.contains(
      StoryboardPanel.seRowKey(track, slot),
    );
    final lanes = layer == null || activeCut == null
        ? transformPropertyLanes(
            TransformTrack.empty(),
            includeAnchorAndOpacity: true,
          )
        : transformPropertyLanes(
            layer.transformTrack,
            includeAnchorAndOpacity: true,
            poseAt: (frame) => layer.transformTrack.resolveAt(
              frameIndex: frame,
              orElse: () => layerIdentityPose(activeCut.canvasSize),
            ),
            anchorAt: (frame) =>
                resolveAnchorTrackAt(layer.transformTrack.anchorPoint, frame) ??
                CanvasPoint(
                  x: activeCut.canvasSize.width / 2,
                  y: activeCut.canvasSize.height / 2,
                ),
            opacityAt: (frame) =>
                resolveOpacityTrackAt(layer.transformTrack.opacity, frame),
          );
    return [
      transformGroupHeader(expanded: expanded),
      if (expanded) ...lanes.where((lane) => !lane.isGroupHeader),
    ];
  }

  /// Transform-lane rail label rows on the shared substrate ([lanes] from
  /// [_cutTransformLanes]/[_seTransformLanes]): the group header row plus
  /// the twirled-open member lanes, storyboard-prefixed. [active] gates
  /// the navigator's frame jumps and value edits to the active cut.
  List<Widget> _transformLaneLabels({
    required Layer carrier,
    required String groupKey,
    required List<PropertyLaneRow> lanes,
    required PropertyLaneEditCallbacks? laneEdit,
    required bool active,
  }) {
    final metrics = TimelineGridMetrics(
      frameCellWidth: widget.pixelsPerFrame,
      layerRowHeight: _transformLaneHeight - 2,
    );
    final onToggleGroup = widget.onToggleTransformGroup;
    return [
      for (final lane in lanes)
        TimelineLaneControlsRow(
          layer: carrier,
          lane: lane,
          metrics: metrics,
          width: StoryboardPanel._trackLabelWidth,
          height: _transformLaneHeight,
          currentFrameIndex: widget.activeCutFrameIndex,
          onSelectFrame: active ? widget.onSelectFrameIndex : null,
          laneEdit: lane.isGroupHeader || !active ? null : laneEdit,
          onToggleLaneGroup: onToggleGroup == null
              ? null
              : (_, _) => onToggleGroup(groupKey),
          keyPrefix: 'storyboard',
          leadingInset: layerSectionLabelSlotWidth,
        ),
    ];
  }

  /// The layers the legend header's bulk ops act on: the ACTIVE cut's
  /// layers plus its track's SE rows (the same set the timeline legend
  /// sweeps through the session).
  List<Layer> _legendLayers() {
    for (final track in widget.project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == widget.activeCutId) {
          return [...cut.layers, ...track.seLayers];
        }
      }
    }
    return const [];
  }

  Set<LayerMark> _legendMarksInUse() => {
    for (final layer in _legendLayers())
      if (layer.mark != LayerMark.none) layer.mark,
  };

  Set<LayerKind> _legendKindsInUse() => {
    for (final layer in _legendLayers()) layer.kind,
  };

  bool _legendAllSeMuted() {
    var sawSe = false;
    for (final layer in _legendLayers()) {
      if (layer.kind != LayerKind.se) {
        continue;
      }
      sawSe = true;
      if (!layer.muted) {
        return false;
      }
    }
    return sawSe;
  }

  Set<LayerId> _legendDisplayedLayerIds() => {
    for (final layer in _legendLayers())
      if (layerKindHasPictureOpacity(layer.kind)) layer.id,
  };

  Widget _seLabelRow(Track track, int slot) {
    final trackLayer = _trackSeAt(track, slot);
    return _StoryboardSeLabel(
      track: track,
      slot: slot,
      active:
          trackLayer != null &&
          widget.selectedRow == LayerRowAddress(trackLayer.id),
      onSelectLayer: widget.onSelectLayer,
      laneExpanded: widget.expandedSeAudioRows.contains(
        StoryboardPanel.seRowKey(track, slot),
      ),
      onToggleLane: widget.onToggleSeRowLane == null
          ? null
          : () => widget.onToggleSeRowLane!(track, slot),
      activeLayer: _activeSlotLayerOf(track, widget.activeCutId, slot),
      onToggleLayerVisibility: widget.onToggleLayerVisibility,
      onToggleLayerMuted: widget.onToggleLayerMuted,
      onLayerOpacityChanged: widget.onLayerOpacityChanged,
      onLayerOpacityChangeEnd: widget.onLayerOpacityChangeEnd,
      onLayerMarkSelected: widget.onLayerMarkSelected,
      layerFxEnabledOf: widget.layerFxEnabledOf,
      onToggleLayerFx: widget.onToggleLayerFx,
      opacityDragPreview: widget.opacityDragPreview,
    );
  }

  /// One track group's rail rows in TIMELINE order (R6 B3, R7-④): the S
  /// rows (each with its twirled-down Audio lane and Transform group)
  /// ABOVE the V track row and ITS Transform group, slots counting UP from
  /// the bottom like the timeline's layer stack (S1 sits right above V,
  /// S2 above it); the section ZONE spans the whole group (UI-R7 #2).
  List<Widget> _railRowsForTrack(Track track, int index) {
    final activeCut = _activeCutOf(track);
    final topSlot = _seSlotCount(track) - 1;
    final seRows = <Widget>[
      for (var slot = topSlot; slot >= 0; slot--) ...[
        _seLabelRow(track, slot),
        if (widget.expandedSeAudioRows.contains(
          StoryboardPanel.seRowKey(track, slot),
        )) ...[
          // Audio leads the S twirl-down (the row's main tool, timeline
          // parity); the Transform group sits below, collapsed default.
          _StoryboardLaneLabel(
            laneKey:
                'storyboard-lane-label-'
                '${track.id.value}'
                '-s${slot + 1}-audio',
            label: 'Audio',
            icon: Icons.graphic_eq,
            height: _audioLaneHeight,
          ),
          ..._transformLaneLabels(
            carrier:
                _trackSeAt(track, slot) ??
                _vLaneCarrier('se-${StoryboardPanel.seRowKey(track, slot)}'),
            groupKey: StoryboardPanel.seRowKey(track, slot),
            lanes: _seTransformLanes(
              track,
              slot,
              activeCut,
              _trackSeAt(track, slot),
            ),
            laneEdit: widget.layerLaneEdit,
            active: activeCut != null && _trackSeAt(track, slot) != null,
          ),
        ],
      ],
    ];
    final vRows = <Widget>[
      _StoryboardTrackLabel(
        track: track,
        trackLabel: 'V${index + 1}',
        laneHeight: widget.trackLaneHeight,
        laneExpanded: widget.expandedTransformTracks.contains(track.id.value),
        onToggleLane: widget.onToggleTrackLane == null
            ? null
            : () => widget.onToggleTrackLane!(track),
        // V-track selection (UI-R18 #6): tapping selects the track (its
        // playhead-index cut becomes active). The highlight says THIS ROW
        // IS SELECTED — not "the active cut lives here", which is what the
        // cut block's own active border already says, and which could light
        // at the same time as an S row.
        active: widget.selectedRow == TrackRowAddress(track.id),
        onSelectTrack: widget.onSelectTrack == null
            ? null
            : () => widget.onSelectTrack!(track.id),
        activeCut: activeCut,
        // UI-R13 #2: the fx/eye act on THIS track's cut at the current
        // global index (each track independently) — no stand-down, no
        // parked look. A gap simply means no cut exists there: the
        // buttons stay normal and a press is a no-op.
        subjectCut: _cutAtPlayheadOn(index) ?? activeCut,
        cutFxEnabledOf: widget.cutFxEnabledOf,
        onToggleCutFx: widget.onToggleCutFx,
        cutPictureVisibleOf: widget.cutPictureVisibleOf,
        onToggleCutPictureVisibility: widget.onToggleCutPictureVisibility,
      ),
      if (widget.expandedTransformTracks.contains(track.id.value))
        ..._transformLaneLabels(
          carrier: _vLaneCarrier(track.id.value),
          groupKey: track.id.value,
          lanes: _cutTransformLanes(track, activeCut),
          laneEdit: activeCut == null
              ? null
              : widget.cutLaneEditFor?.call(activeCut),
          active: activeCut != null,
        ),
    ];
    return [
      _sectionZoneGroup(
        keyValue: 'storyboard-section-zone-${track.id.value}-se',
        label: 'SE',
        rows: seRows,
      ),
      _sectionZoneGroup(
        keyValue: 'storyboard-section-zone-${track.id.value}-v',
        label: 'V',
        rows: vRows,
      ),
    ];
  }

  /// One section's rail rows with the ZONE spanning the whole group over
  /// the rows' reserved band slots (UI-R7 #2): S1·S2 read as one SE
  /// sub-zone, exactly like the timeline's run zones.
  Widget _sectionZoneGroup({
    required String keyValue,
    required String label,
    required List<Widget> rows,
  }) {
    return Stack(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: KeyedSubtree(
            key: ValueKey<String>(keyValue),
            child: SectionBandZone(label: label),
          ),
        ),
      ],
    );
  }

  /// Per-row hairline under every STRIP row (UI-R5 storyboard unification:
  /// the timeline grid's row lines reach the frame area here too). Drawn
  /// as a foreground so row heights stay untouched (rail lockstep).
  Widget _stripRowLine(Widget row) {
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: row,
    );
  }

  /// One track's whole strip section: its rows in a column, with the
  /// track-axis range selection drawn OVER them as the timeline's one
  /// selection band (R27 #14 — cells, lanes and now this rail draw exactly
  /// the same band, so a storyboard span cannot read as a different kind
  /// of selection).
  Widget _trackGroupSection(
    Track track,
    int index,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
    List<Widget> seRows,
  ) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _stripRowsForTrack(
            track,
            index,
            entries,
            width,
            scale,
            seRows,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(child: _trackRangeBand(track, scale)),
        ),
      ],
    );
  }

  /// The band itself: [selection.spanRows] top to bottom — intervening
  /// twirled-open lanes ride under it, exactly as the timeline's band
  /// covers lanes between two covered layer rows.
  Widget _trackRangeBand(Track track, TimelineScale scale) {
    final selectedRange =
        widget.cutSelect?.selectedRange ?? widget.seSelect?.selectedRange;
    if (selectedRange == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TrackFrameRangeSelection?>(
      valueListenable: selectedRange,
      builder: (context, selection, _) {
        if (selection == null ||
            selection.trackId != track.id ||
            scale.pixelsPerFrame <= 0) {
          return const SizedBox.shrink();
        }
        final spanned = selection.spanRows.toSet();
        double y = 0;
        double? top;
        double? bottom;
        for (final (address, height) in _trackGroupRowGeometry(track)) {
          if (address != null && spanned.contains(address)) {
            top ??= y;
            bottom = y + height;
          }
          y += height;
        }
        if (top == null || bottom == null) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned(
              left: scale.leftForFrame(selection.startFrame),
              top: top,
              width: selection.lengthFrames * scale.pixelsPerFrame,
              height: bottom - top,
              child: Semantics(
                key: const ValueKey<String>(
                  'storyboard-frame-range-selection',
                ),
                label: 'selected frame range',
                container: true,
                child: DecoratedBox(
                  decoration: timelineRangeSelectionBandDecoration,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The group's rows in VISUAL order with their heights — mirrored from
  /// [_seStripRowsForTrack] and [_stripRowsForTrack] row for row. A new
  /// row kind must land in both, or the band drifts off its rows.
  List<(TimelineRowAddress?, double)> _trackGroupRowGeometry(Track track) {
    final slots = <(TimelineRowAddress?, double)>[];
    for (var slot = _seSlotCount(track) - 1; slot >= 0; slot--) {
      final layer = _trackSeAt(track, slot);
      slots.add((
        layer == null ? null : LayerRowAddress(layer.id),
        _seRowHeight,
      ));
      if (widget.expandedSeAudioRows.contains(
        StoryboardPanel.seRowKey(track, slot),
      )) {
        slots.add((null, _audioLaneHeight));
        // The SE transform strips: the group header, plus the property
        // lanes when twirled open ([_seTransformLaneStrips]'s shape).
        slots.add((null, _transformLaneHeight));
        if (widget.expandedTransformGroups.contains(
          StoryboardPanel.seRowKey(track, slot),
        )) {
          for (var lane = 0; lane < 5; lane++) {
            slots.add((null, _transformLaneHeight));
          }
        }
      }
    }
    slots.add((TrackRowAddress(track.id), widget.trackLaneHeight));
    return slots;
  }

  /// One track group's strip rows, mirroring [_railRowsForTrack] row for
  /// row (heights must stay in lockstep — the two columns share no
  /// scaffolding).
  List<Widget> _stripRowsForTrack(
    Track track,
    int index,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
    List<Widget> seRows,
  ) {
    return [
      // Prebuilt from the RAW project outside the drag-preview builder
      // (R10-③): identical instances per step = subtree rebuilds skipped.
      ...seRows,
      _stripRowLine(
        _StoryboardTrackRow(
          track: track,
          layoutEntries: entries,
          activeCutId: widget.activeCutId,
          onRowFramePress: widget.onRowFramePress,
          laneHeight: widget.trackLaneHeight,
          width: width,
          stripEdges: widget.stripEdges,
          cutMove: widget.cutMove,
          cutSelect: widget.cutSelect,
          stripSelect: widget.stripSelect,
          thumbnailFor: widget.thumbnailFor,
          timelineScale: scale,
          frameGeometry: _frameGeometry,
          hoveredCutId: _hoveredCutId,
          windowBucket: _horizontalWindowBucket,
          viewportWidth: _stripViewportWidth,
          showSeconds: widget.showSeconds,
          projectFrameRate: widget.projectFrameRate,
        ),
      ),
      if (widget.expandedTransformTracks.contains(track.id.value))
        for (final strip in _cutTransformLaneStrips(
          track,
          index,
          entries,
          width,
          scale,
        ))
          _stripRowLine(strip),
    ];
  }

  /// The DISPLAY form of a track SE lane: the in-flight take preview
  /// stands in for the armed lane, by identity (REC1-C).
  Layer? _seDisplayAt(Track track, int slot) {
    final base = _trackSeAt(track, slot);
    final preview = widget.seLanePreview;
    return preview != null && base != null && preview.id == base.id
        ? preview
        : base;
  }

  /// One track's SE strip rows (+ twirled-down audio/transform lanes) —
  /// track-global content, built from the base layout.
  List<Widget> _seStripRowsForTrack(
    Track track,
    int index,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
  ) {
    // The rail draws S rows TOP-DOWN from the highest slot, so the move's
    // row delta walks them in that order (slot 0 sits just above the V
    // row). Track-owned rows, so the global layers — never the display
    // clones a move would refuse to commit to.
    final seRowsInDisplayOrder = <TimelineDisplayRow>[
      for (var slot = _seSlotCount(track) - 1; slot >= 0; slot -= 1)
        if (_trackSeAt(track, slot) case final layer?)
          TimelineDisplayRow.layer(layer, layerIndex: slot),
    ];
    Widget seRow(int slot, Layer? layer) => _StoryboardSeRow(
      seRowsInDisplayOrder: seRowsInDisplayOrder,
      trackIndex: index,
      slot: slot,
      layer: layer,
      layoutEntries: entries,
      width: width,
      timelineScale: scale,
      projectFrameRate: widget.projectFrameRate,
      audioPeaksFor: widget.audioPeaksFor,
      onRowFramePress: widget.onRowFramePress,
      seCommaDrag: widget.seCommaDrag,
      seSelect: widget.seSelect,
      frameGeometry: _frameGeometry,
    );
    return [
      for (var slot = _seSlotCount(track) - 1; slot >= 0; slot--) ...[
        _stripRowLine(
          // The gate keeps comma drags LIVE here (UI-R7 #7): these rows
          // are built once per panel build (identical instances across
          // cut-trim preview steps, R10-③), so without it an SE edge drag
          // only showed on release. It resolves the GLOBAL preview form —
          // this strip renders the track axis, not the active-cut clone.
          switch (_seDisplayAt(track, slot)) {
            null => seRow(slot, null),
            final globalLayer => TimelineDragPreviewRowGate(
              dragPreview: widget.dragPreview,
              layer: globalLayer,
              useGlobalForm: true,
              rowBuilder: (context, layer) => seRow(slot, layer),
            ),
          },
        ),
        if (widget.expandedSeAudioRows.contains(
          StoryboardPanel.seRowKey(track, slot),
        )) ...[
          _stripRowLine(
            _StoryboardAudioLaneRow(
              trackIndex: index,
              slot: slot,
              layer: _seDisplayAt(track, slot),
              layoutEntries: entries,
              width: width,
              timelineScale: scale,
              projectFrameRate: widget.projectFrameRate,
              audioPeaksFor: widget.audioPeaksFor,
              seClipMarkerTooltip: widget.seClipMarkerTooltip,
              activeCutId: widget.activeCutId,
              onSetAudioClipOffset: widget.onSetAudioClipOffset,
            ),
          ),
          for (final strip in _seTransformLaneStrips(
            track,
            index,
            slot,
            entries,
            width,
            scale,
          ))
            _stripRowLine(strip),
        ],
      ],
    ];
  }

  /// Resolves [laneId] against a transform [track] for one strip span.
  PropertyLaneRow _laneOfTrack(TransformTrack track, String laneId) {
    if (laneId == transformGroupHeaderLane.laneId) {
      return transformGroupHeaderLane;
    }
    return transformPropertyLanes(
      track,
      includeAnchorAndOpacity: true,
    ).firstWhere((lane) => lane.laneId == laneId);
  }

  /// The V track's Transform strip rows: the group header band plus,
  /// twirled open, the AE lanes' key-marker strips — and the cut-fade
  /// envelope row AS the Opacity strip (fade handles unchanged, canonical
  /// key policy intact).
  List<Widget> _cutTransformLaneStrips(
    Track track,
    int trackIndex,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
  ) {
    final expanded = widget.expandedTransformGroups.contains(track.id.value);
    Widget strip(String laneId) => _StoryboardLaneStripRow(
      rowKey: 'storyboard-cut-lane-row-$trackIndex-$laneId',
      layoutEntries: entries,
      width: width,
      timelineScale: scale,
      activeCutId: widget.activeCutId,
      laneOf: (cut) => (
        _vLaneCarrier(cut.id.value),
        // The cut's WINDOW of the track lanes (R4a): the strip renders
        // cut-local frames, so it reads the projection.
        _laneOfTrack(_cutWindowTransformOf(cut), laneId),
      ),
      laneEditFor: widget.cutLaneEditFor,
    );
    return [
      strip(transformGroupHeaderLane.laneId),
      if (expanded) ...[
        strip('anchor-point'),
        strip('position'),
        strip('scale'),
        strip('rotation'),
        _StoryboardOpacityLaneRow(
          trackIndex: trackIndex,
          layoutEntries: entries,
          width: width,
          timelineScale: scale,
          windowOf: _cutWindowTransformOf,
          onSetCutFade: widget.onSetCutFade,
        ),
      ],
    ];
  }

  /// One S row's Transform strip rows: per-cut key-marker strips on the
  /// slot layers' OWN tracks (cuts without the slot skip), editing gated
  /// to the active cut.
  List<Widget> _seTransformLaneStrips(
    Track track,
    int trackIndex,
    int slot,
    List<StoryboardTimelineLayoutEntry> entries,
    double width,
    TimelineScale scale,
  ) {
    final rowKey = StoryboardPanel.seRowKey(track, slot);
    final expanded = widget.expandedTransformGroups.contains(rowKey);
    final layerLaneEdit = widget.layerLaneEdit;
    Widget strip(String laneId) => _StoryboardLaneStripRow(
      rowKey: 'storyboard-se-lane-row-$trackIndex-${slot + 1}-$laneId',
      layoutEntries: entries,
      width: width,
      timelineScale: scale,
      activeCutId: widget.activeCutId,
      laneOf: (cut) {
        final layer = _trackSeAt(track, slot);
        if (layer == null) {
          return null;
        }
        return (layer, _laneOfTrack(layer.transformTrack, laneId));
      },
      laneEditFor: layerLaneEdit == null ? null : (_) => layerLaneEdit,
    );
    return [
      strip(transformGroupHeaderLane.laneId),
      if (expanded) ...[
        strip('anchor-point'),
        strip('position'),
        strip('scale'),
        strip('rotation'),
        strip('opacity'),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Viewport paper fill (UI-R12 #16): the strips run to the
        // viewport's right edge — recorded FIRST so the SE strip rows and
        // the body agree on the rendered extent within one build.
        _stripViewportWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth -
                      StoryboardPanel._trackLabelWidth -
                      StoryboardPanel._scrollbarLaneWidth)
                  .clamp(0.0, double.infinity)
                  .toDouble()
            : 0.0;
        _viewportFillFrameCells = endlessViewportFillFrames(
          viewportExtent: _stripViewportWidth,
          frameCellExtent: _scale.pixelsPerFrame,
        );
        // The V rows' geometry for this pass. `frameStartIndex` is 0 and
        // there is no leading spacer: the storyboard's x IS the track-global
        // frame axis, which is exactly why the timeline's gesture layer can
        // read it without knowing whose row it is on.
        _frameGeometry.value = TimelineFrameGeometry(
          frameCellExtent: _scale.pixelsPerFrame,
          frameStartIndex: 0,
          frameEndIndexExclusive:
              _totalFrames(
                widget.project,
                buildStoryboardTimelineLayout(widget.project),
              ) +
              _endlessTrailingFrames +
              _viewportFillFrameCells,
        );
        // SE rows are built OUTSIDE the drag-preview builder from the RAW
        // project (R10-③): their content is track-global, so a cut trim
        // never changes them — handing the per-step rebuild IDENTICAL row
        // instances lets Flutter skip their whole subtrees (waveform
        // painters included). The trade: an in-flight trim doesn't slide
        // their cut-boundary marks until release. SE comma drags edit the
        // ACTIVE layer through the timeline gates, unaffected here.
        final seStripRowsByTrack = _seStripRowsByTrack();
        final dragPreview = widget.dragPreview;
        if (dragPreview == null) {
          return _buildBody(context, widget.project, seStripRowsByTrack);
        }
        return ValueListenableBuilder<TimelineDragPreview?>(
          valueListenable: dragPreview,
          builder: (context, preview, _) => _buildBody(
            context,
            projectWithTimelineDragPreview(widget.project, preview),
            seStripRowsByTrack,
          ),
        );
      },
    );
  }

  /// The base-layout SE strip rows (+ their twirled-down lanes) per track
  /// index — computed once per PANEL build and reused across drag-preview
  /// steps.
  List<List<Widget>> _seStripRowsByTrack() {
    final layoutEntries = buildStoryboardTimelineLayout(widget.project);
    final scale = _scale;
    final contentWidth = _contentWidthFor(widget.project, layoutEntries, scale);
    return [
      for (var index = 0; index < widget.project.tracks.length; index++)
        _seStripRowsForTrack(
          widget.project.tracks[index],
          index,
          layoutEntries
              .where((entry) => entry.trackIndex == index)
              .toList(growable: false),
          contentWidth,
          scale,
        ),
    ];
  }

  /// Frame cells the strips viewport needs to be fully papered (UI-R12
  /// #16) — recorded by [_buildBody]'s LayoutBuilder. Zero until layout.
  int _viewportFillFrameCells = 0;

  /// The strip column's viewport width — the shared window policy's other
  /// input (UI-R16). Recorded in build beside [_viewportFillFrameCells],
  /// which already derived from it.
  double _stripViewportWidth = 0;

  /// Render extent (UI-R12 #16 contract, unified with the timeline
  /// grids): the cells scrolled/panned into existence PLUS the viewport
  /// fill — the old always-120 resting runway is gone, so past-content
  /// cells vanish once out of view and the scrollbar stops at the built
  /// cells. Only the ruler edge-drag overshoots and grows the extent.
  int _renderedFramesFor(int totalFrames) =>
      math.max(totalFrames + _endlessTrailingFrames, _viewportFillFrameCells);

  /// The scroll content's full width for [layoutEntries] (cuts + the
  /// endless runway). The rendered-cell term is EXACT (UI-R12 #16): any
  /// padding past the built cells would be a phantom scroll zone the
  /// growth listener keeps chasing (the block term keeps its grip
  /// overhang; cells simply materialize under it once).
  double _contentWidthFor(
    Project project,
    List<StoryboardTimelineLayoutEntry> layoutEntries,
    TimelineScale scale,
  ) {
    final renderedFrames = _renderedFramesFor(
      _totalFrames(project, layoutEntries),
    );
    return math.max(
      _timelineContentWidth(layoutEntries, scale),
      scale.leftForFrame(renderedFrames),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Project project,
    List<List<Widget>> seStripRowsByTrack,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final layoutEntries = buildStoryboardTimelineLayout(project);
    final scale = _scale;
    final totalFrames = _totalFrames(project, layoutEntries);
    // Endless frame axis (UI-R12 #16): cells cover the view — the cuts,
    // whatever the viewport needs to read papered, and whatever the ruler
    // edge-drag has materialized. No resting runway beyond that.
    final renderedFrames = _renderedFramesFor(totalFrames);
    final contentWidth = _contentWidthFor(project, layoutEntries, scale);
    // The playhead + green bar repaint through their own listenables (the
    // cursor-layer pattern) — the ruler's overlay PAINTER and the playhead
    // overlay subscribe below, nothing else in this build does.
    final playheadListenable = widget.playheadFrame;

    // The panel-private frame (border + all-6 padding) is GONE (UI-R10
    // #15): the timeline hosts its grid edge-to-edge under the command
    // bar, and that inset was exactly the odd top-left padding that made
    // the two rails read differently. The body is the timeline's 3-ROW
    // structure (UI-R10 #21): [legend | lane | ruler] on top,
    // [labels | scrollbar | strips] in the middle,
    // [blank | blank | horizontal scrollbar] pinned on the bottom.
    return ColoredBox(
      key: const ValueKey<String>('storyboard-panel'),
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // PINNED RULER: the frame ruler sits ABOVE the vertical scroll
          // area (the timeline's sticky-header pattern) so it stays put
          // while tracks and SE rows scroll under it; it follows the
          // horizontal scroll by translation.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The timeline's legend header over the rail (UI-R5
              // storyboard unification): same slots, same flyouts.
              SizedBox(
                width: StoryboardPanel._trackLabelWidth,
                child: TimelineLayerControlsHeader(
                  // The storyboard rail keeps its own width (R27 #6: the
                  // timeline's grew for the blend column; this rail has
                  // no blend cell, so it must not).
                  metrics: const TimelineGridMetrics(
                    layerControlsWidth: StoryboardPanel._trackLabelWidth,
                  ),
                  legend: widget.legend,
                  rowFilter: TimelineRowFilter.none,
                  showRowSolos: false,
                  marksInUse: _legendMarksInUse(),
                  kindsInUse: _legendKindsInUse(),
                  visibilitySoloEnabled: widget.visibilitySoloEnabled,
                  allSeMuted: _legendAllSeMuted(),
                  displayedLayerIds: widget.legend == null
                      ? null
                      : _legendDisplayedLayerIds,
                  displayedOpacity: widget.legendOpacityValue,
                ),
              ),
              // Blank corner over the scrollbar lane (the timeline's
              // header-row slot).
              const TimelineVerticalScrollbarSlot(
                width: StoryboardPanel._scrollbarLaneWidth,
                height: StoryboardPanel._rulerHeight,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportWidth = constraints.hasBoundedWidth
                        ? constraints.maxWidth
                        : contentWidth;
                    return SizedBox(
                      height: StoryboardPanel._rulerHeight,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: contentWidth,
                          maxWidth: contentWidth,
                          minHeight: StoryboardPanel._rulerHeight,
                          maxHeight: StoryboardPanel._rulerHeight,
                          // UI-R15: scroll moves ONLY this translate — the
                          // ruler strip itself builds once (full bounds)
                          // and its painters window off the live offset.
                          child: ValueListenableBuilder<double>(
                            valueListenable: _horizontalScrollOffset,
                            child: _StoryboardRuler(
                              width: contentWidth,
                              renderedFrames: renderedFrames,
                              contentFrames: totalFrames,
                              playhead: playheadListenable,
                              frameCachedSignal: widget.frameCachedSignal,
                              viewportOffset: _horizontalScrollOffset,
                              windowBucket: _horizontalWindowBucket,
                              viewportWidth: viewportWidth,
                              timelineScale: scale,
                              onSeekGlobalFrame: widget.onSeekGlobalFrame,
                              onScrubGlobalFrame: widget.onScrubGlobalFrame,
                              onScrubEnd: widget.onScrubEnd,
                              isFrameCached: widget.isFrameCached,
                              onEdgeAutoPan: _autoPanRulerEdge,
                              framesPerSecond: _countingFps,
                              showSeconds: widget.showSeconds,
                            ),
                            builder: (context, offset, child) =>
                                Transform.translate(
                                  offset: Offset(-offset, 0),
                                  child: child,
                                ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, middleConstraints) {
                final middleViewportHeight = middleConstraints.hasBoundedHeight
                    ? middleConstraints.maxHeight
                    : 0.0;
                return Stack(
                  children: [
                    ScrollConfiguration(
                      // The pinned rail IS this area's scrollbar — the desktop
                      // auto-overlay would double it (UI-R10 #22 unification).
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        key: const ValueKey<String>(
                          'storyboard-vertical-viewport',
                        ),
                        controller: _verticalController,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sections live INSIDE the rows now (UI-R5): the
                            // first S row and the V row carry inline tags — no
                            // bracket gutter beside the rail.
                            SizedBox(
                              key: const ValueKey<String>(
                                'storyboard-track-label-rail',
                              ),
                              width: StoryboardPanel._trackLabelWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Track groups in TIMELINE order (R6 B3): the
                                  // S rows sit ABOVE their V track, slots
                                  // bottom-up like the timeline (top-down
                                  // S2, S1, V — R7-④).
                                  for (
                                    var index = 0;
                                    index < project.tracks.length;
                                    index++
                                  )
                                    ..._railRowsForTrack(
                                      project.tracks[index],
                                      index,
                                    ),
                                ],
                              ),
                            ),
                            // The scrollbar lane: the scroll content reserves
                            // the column, the pinned rail overlays it.
                            const SizedBox(
                              width: StoryboardPanel._scrollbarLaneWidth,
                            ),
                            Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(
                                  context,
                                ).copyWith(scrollbars: false),
                                child: SingleChildScrollView(
                                  key: const ValueKey<String>(
                                    'storyboard-timeline-horizontal-viewport',
                                  ),
                                  controller: _horizontalController,
                                  scrollDirection: Axis.horizontal,
                                  child: Stack(
                                    children: [
                                      // Frame grid lines under the blocks:
                                      // the runway reads as endless frame
                                      // cells, like the timeline's grid
                                      // (painted — costs nothing per frame).
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: RepaintBoundary(
                                            child: CustomPaint(
                                              key: const ValueKey<String>(
                                                'storyboard-frame-lines',
                                              ),
                                              painter: _StoryboardFrameLinesPainter(
                                                pixelsPerFrame:
                                                    scale.pixelsPerFrame,
                                                // The shared faint
                                                // grid ink (UI-R14
                                                // #4) — one value
                                                // across all three
                                                // panels.
                                                color: colorScheme
                                                    .outlineVariant
                                                    .withValues(
                                                      alpha:
                                                          timelineBaseGridAlpha,
                                                    ),
                                                framesPerSecond: _countingFps,
                                                colorScheme: colorScheme,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // RepaintBoundary (R12-⑥): the playhead
                                      // overlay above moves every playback tick;
                                      // without the boundary each move re-
                                      // rasterizes every strip, thumbnail and
                                      // waveform in this column.
                                      RepaintBoundary(
                                        child: Column(
                                          key: const ValueKey<String>(
                                            'storyboard-timeline-scroll-content',
                                          ),
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Width driver: the scroll content spans
                                            // the full frame runway even when every
                                            // row is narrower (the pinned ruler used
                                            // to do this from inside the content).
                                            SizedBox(width: contentWidth),
                                            // Track groups in TIMELINE order (R6
                                            // B3), mirroring the rail exactly —
                                            // row for row, height for height.
                                            for (
                                              var index = 0;
                                              index < project.tracks.length;
                                              index++
                                            )
                                              _trackGroupSection(
                                                project.tracks[index],
                                                index,
                                                layoutEntries
                                                    .where(
                                                      (entry) =>
                                                          entry.trackIndex ==
                                                          index,
                                                    )
                                                    .toList(growable: false),
                                                contentWidth,
                                                scale,
                                                index <
                                                        seStripRowsByTrack
                                                            .length
                                                    ? seStripRowsByTrack[index]
                                                    : const [],
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (playheadListenable != null)
                                        // Frame-wide accent tint only — no solid
                                        // edge line over the blocks (user
                                        // direction); the ruler carries its own
                                        // current-frame highlight. Subscribes to
                                        // the cursor itself: a tick moves THIS
                                        // overlay, the blocks never rebuild.
                                        ValueListenableBuilder<int?>(
                                          valueListenable: playheadListenable,
                                          builder:
                                              (
                                                context,
                                                playheadFrame,
                                                _,
                                              ) => playheadFrame == null
                                              ? const SizedBox.shrink()
                                              : Positioned(
                                                  key: const ValueKey<String>(
                                                    'storyboard-playhead',
                                                  ),
                                                  left: scale.leftForFrame(
                                                    playheadFrame,
                                                  ),
                                                  top: 0,
                                                  bottom: 0,
                                                  width: scale.pixelsPerFrame,
                                                  child: IgnorePointer(
                                                    child: ColoredBox(
                                                      color:
                                                          timelinePlayheadColor
                                                              .withValues(
                                                                alpha: 0.18,
                                                              ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      // The MOVIE-END line through the
                                      // STRIPS (UI-R20 #3): the ruler's
                                      // red line extended vertically, and
                                      // draggable — it edits the movie's
                                      // FINAL LENGTH (the project's
                                      // trailing gap), never the cuts;
                                      // the panel's internal preview
                                      // substitution makes it follow
                                      // live.
                                      if (totalFrames > 0)
                                        Positioned(
                                          key: const ValueKey<String>(
                                            'storyboard-cut-end-line',
                                          ),
                                          left: scale.leftForFrame(totalFrames),
                                          top: 0,
                                          bottom: 0,
                                          width: 2,
                                          child: const IgnorePointer(
                                            child: ColoredBox(
                                              color: AppColors.danger,
                                            ),
                                          ),
                                        ),
                                      if (totalFrames > 0 &&
                                          widget.movieEnd != null)
                                        _StoryboardEndLineHandle(
                                          // Grabbed from the EMPTY side of
                                          // the line, never straddling it:
                                          // everything left of the movie's
                                          // end belongs to the content, and
                                          // the last cut's trailing edge
                                          // grip is right there. Centring
                                          // the handle put a full-height
                                          // opaque box over that grip and
                                          // made it unreachable.
                                          left: scale.leftForFrame(totalFrames),
                                          pixelsPerFrame: scale.pixelsPerFrame,
                                          movieEnd: widget.movieEnd!,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: StoryboardPanel._trackLabelWidth,
                      top: 0,
                      bottom: 0,
                      width: StoryboardPanel._scrollbarLaneWidth,
                      child: TimelineVerticalScrollbarRail(
                        key: const ValueKey<String>(
                          'storyboard-vertical-scrollbar',
                        ),
                        controller: _verticalController,
                        viewportHeight: middleViewportHeight,
                        contentHeight: middleViewportHeight,
                        width: StoryboardPanel._scrollbarLaneWidth,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // BOTTOM row of the 3-row structure (UI-R10 #21): blank
          // corners under the rail and the scrollbar lane, then the
          // PINNED horizontal scrollbar (it used to live inside the
          // vertical scroll content and scrolled away with it).
          Row(
            children: [
              const SizedBox(
                key: ValueKey<String>(
                  'storyboard-bottom-scrollbar-left-spacer',
                ),
                width: StoryboardPanel._trackLabelWidth,
                height: StoryboardPanel._bottomScrollbarRailHeight,
              ),
              const SizedBox(
                width: StoryboardPanel._scrollbarLaneWidth,
                height: StoryboardPanel._bottomScrollbarRailHeight,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportWidth = constraints.hasBoundedWidth
                        ? constraints.maxWidth
                        : 0.0;
                    return TimelineHorizontalScrollbarRail(
                      key: const ValueKey<String>(
                        'storyboard-horizontal-scrollbar',
                      ),
                      controller: _horizontalController,
                      viewportWidth: viewportWidth,
                      contentWidth: contentWidth,
                      height: StoryboardPanel._bottomScrollbarRailHeight,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The compact cut-management toolbar at the top of the storyboard: the
/// storyboard owns the cut lifecycle, so new/rename/note/canvas/duplicate/
/// move/delete live here (icon-only with tooltips, acting on the active
/// cut). Zoom lives in the panel header's shared slider.
/// The Premiere-style frame ruler across the top of the track area: frame
/// ticks and 1-based labels on the shared [TimelineScale], scrolling with
/// the blocks. Tapping or dragging seeks via [onSeekGlobalFrame].
/// The storyboard's frame ruler IS the timeline's ([TimelineFrameRuler] with
/// the cell extent carrying the storyboard zoom): identical header cells,
/// adaptive labels, runway dimming and the cut-end boundary line. The row is
/// windowed to the scrolled viewport because the storyboard's scroll content
/// is not otherwise virtualized.
class _StoryboardRuler extends StatefulWidget {
  const _StoryboardRuler({
    required this.width,
    required this.renderedFrames,
    required this.contentFrames,
    required this.playhead,
    required this.frameCachedSignal,
    required this.viewportOffset,
    required this.windowBucket,
    required this.viewportWidth,
    required this.timelineScale,
    required this.onSeekGlobalFrame,
    required this.onScrubGlobalFrame,
    required this.onScrubEnd,
    required this.isFrameCached,
    this.onEdgeAutoPan,
    this.framesPerSecond = 24,
    this.showSeconds = false,
  });

  final double width;

  /// Rendered range — includes the endless-axis runway past the cuts;
  /// seeks may land anywhere in it (over-end selection like the timeline).
  final int renderedFrames;

  /// The cuts' actual end (runway dimming + the cut-end boundary line).
  final int contentFrames;

  /// The playhead + cache-warm signals, consumed by the cursor overlay
  /// PAINTER only (R12-B): a playback tick or a warming frame repaints
  /// one thin layer — the header cells never rebuild. At storyboard zoom
  /// there are far more of them than in the timeline, which is exactly
  /// why the old rebuild-per-tick ruler showed up as fixed frame drops.
  final ValueListenable<int?>? playhead;
  final Listenable? frameCachedSignal;

  /// The live horizontal offset (UI-R15): the strip builds ONCE with the
  /// full frame bounds; the edge-pan test reads the live offset, while
  /// the shared ruler painter and the cursor overlay window themselves
  /// off the QUANTIZED [windowBucket] (UI-R16) — a scroll repaints once
  /// per span crossing, never rebuilds.
  final ValueListenable<double> viewportOffset;
  final ValueListenable<int> windowBucket;
  final double viewportWidth;
  final TimelineScale timelineScale;
  final ValueChanged<int>? onSeekGlobalFrame;

  /// Drag-scrub path (cursor-only per move + one commit on release); null
  /// falls back to per-move seeks.
  final ValueChanged<int>? onScrubGlobalFrame;
  final VoidCallback? onScrubEnd;

  final bool Function(int globalFrame)? isFrameCached;

  /// Edge auto-pan sink (UI-R12 #16, unified with the timeline ruler): a
  /// scrub within 24px of the viewport edge reports a pan delta; the
  /// panel jumps the horizontal axis (overshooting rightward so growth
  /// materializes frames past the built extent).
  final ValueChanged<double>? onEdgeAutoPan;

  /// The two-line ruler's parameters (UI-R10 #27, unified: the seconds
  /// display cycles 1..fps here exactly like the timeline — UI-R11 #10).
  final int framesPerSecond;
  final bool showSeconds;

  @override
  State<_StoryboardRuler> createState() => _StoryboardRulerState();
}

class _StoryboardRulerState extends State<_StoryboardRuler> {
  /// Per-gesture dedupe (the timeline's `_lastRulerScrubbedFrameIndex`):
  /// same-frame moves report once.
  int? _lastScrubbedFrame;

  void _resetScrubTracking() => _lastScrubbedFrame = null;

  /// The scrub's VIEWPORT-local x for a pointer at [globalPosition], or
  /// null before this row has a box (the timeline's
  /// `_rulerViewportLocalXFromGlobal`).
  ///
  /// Resolved LIVE, through the render object, every event — which is the
  /// whole of feedback #13. A gesture's `localPosition` is transformed by
  /// what was captured when the pointer went DOWN, and this strip is
  /// translated by the scroll: the moment an edge auto-pan moves it, that
  /// captured transform is stale and every later move reports a frame
  /// that has drifted by however far the axis has panned. Leaving the
  /// viewport and coming back is exactly how a drag accumulates that pan.
  double? _viewportLocalX(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    // This row IS the content strip, so its own local x is content-local;
    // the viewport-local one the edge test and the shared frame policy
    // both speak is that minus the live offset.
    return box.globalToLocal(globalPosition).dx - widget.viewportOffset.value;
  }

  void _scrubAtGlobal(Offset globalPosition) {
    if (widget.contentFrames <= 0 || widget.renderedFrames <= 0) {
      return;
    }
    final localX = _viewportLocalX(globalPosition);
    if (localX == null) {
      return;
    }
    _autoPanAt(localX);
    // THE shared frame policy, the one the timeline ruler and the X-sheet
    // already call — viewport-local x plus the live offset (feedback #13:
    // "로직도 똑같이 통일하라는거니까").
    final frame = frameIndexFromLocalX(
      localX: localX,
      horizontalScrollOffset: widget.viewportOffset.value,
      frameCellWidth: widget.timelineScale.pixelsPerFrame,
      visibleFrameCount: widget.renderedFrames,
    );
    if (frame == null || frame == _lastScrubbedFrame) {
      return;
    }
    _lastScrubbedFrame = frame;
    (widget.onScrubGlobalFrame ?? widget.onSeekGlobalFrame)?.call(frame);
  }

  /// [viewportX] is VIEWPORT-relative — what the edge test needs.
  void _autoPanAt(double viewportX) {
    final onEdgeAutoPan = widget.onEdgeAutoPan;
    if (onEdgeAutoPan == null || widget.viewportWidth <= 0) {
      return;
    }
    final delta = edgeAutoPanDelta(viewportX, widget.viewportWidth);
    if (delta != 0) {
      onEdgeAutoPan(delta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cellWidth = widget.timelineScale.pixelsPerFrame;
    final metrics = TimelineGridMetrics(
      frameCellWidth: cellWidth,
      layerRowHeight: StoryboardPanel._rulerHeight,
      layerControlsWidth: 0,
      verticalScrollbarWidth: 0,
    );

    // The TIMELINE ruler's scrub scheme verbatim (UI-R18 #13): the RAW
    // pointer layer scrubs on the press itself (the cursor comes to the
    // finger immediately — taps included) and commits on the raw
    // up/cancel, wherever the pointer ends up; the gesture layer below
    // only claims the horizontal drag from the pan arena and feeds the
    // moves. The old drag-only GestureDetector waited for arena
    // recognition, so presses did nothing and taps never committed.
    return Listener(
      key: const ValueKey<String>('storyboard-ruler'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _resetScrubTracking();
        _scrubAtGlobal(event.position);
      },
      onPointerUp: (_) => widget.onScrubEnd?.call(),
      onPointerCancel: (_) => widget.onScrubEnd?.call(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        // GLOBAL positions, resolved live against this row's box — a
        // gesture's own localPosition rides a transform captured at
        // pointer-down, which the edge auto-pan invalidates mid-drag
        // (feedback #13).
        onHorizontalDragStart: (details) =>
            _scrubAtGlobal(details.globalPosition),
        onHorizontalDragUpdate: (details) =>
            _scrubAtGlobal(details.globalPosition),
        onHorizontalDragEnd: (_) => _resetScrubTracking(),
        onHorizontalDragCancel: _resetScrubTracking,
        child: SizedBox(
          width: widget.width,
          height: StoryboardPanel._rulerHeight,
          child: Stack(
            children: [
              // STATIC header cells: cursor- and cache-independent — ticks
              // and warming frames never rebuild them. Full bounds (UI-R15):
              // the shared painter self-windows off the live offset.
              TimelineFrameRuler(
                key: const ValueKey<String>('storyboard-frame-ruler'),
                frameStartIndex: 0,
                frameEndIndexExclusive: widget.renderedFrames,
                currentFrameIndex: -1,
                playbackFrameCount: widget.contentFrames,
                leadingFrameSpacerWidth: 0,
                trailingFrameSpacerWidth: 0,
                metrics: metrics,
                onSelectFrame: (_) {},
                framesPerSecond: widget.framesPerSecond,
                showSeconds: widget.showSeconds,
                windowBucket: widget.windowBucket,
                viewportMainExtent: widget.viewportWidth,
              ),
              // The moving parts REPAINT only: current-frame tint + green
              // cached bar, one thin isolated layer. Shared with the
              // timeline ruler, which needs the very same split.
              Positioned.fill(
                child: TimelineRulerCursorOverlay(
                  keyValue: 'storyboard-ruler-cursor-overlay',
                  playhead: widget.playhead,
                  repaintSignal: widget.frameCachedSignal,
                  windowBucket: widget.windowBucket,
                  viewportMainExtent: widget.viewportWidth,
                  renderedFrames: widget.renderedFrames,
                  contentFrames: widget.contentFrames,
                  cellWidth: cellWidth,
                  isFrameCached: widget.isFrameCached,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SE rows under a track: one per SE slot, S1·S2… like the sheet columns.
// 22 → 30 with the timeline-parity S-row controls (mute/eye/opacity).
const double _seRowHeight = 30;

/// Twirl-down lane heights: the enlarged waveform strip, the cut-fade
/// (Opacity) envelope lane and the Transform lanes (labels and strips
/// share these — the rail and strips columns must stay height-synced).
const double _audioLaneHeight = 36;
const double _opacityLaneHeight = 26;
const double _transformLaneHeight = 26;

/// The track's SE row count: SE rows are TRACK-owned (list order is THE
/// ordering every panel renders — timeline parity by identity).
int _seSlotCount(Track track) => track.seLayers.length;

/// The [slot]th TRACK-owned SE layer (global-frame timeline); null when
/// the track has fewer rows.
Layer? _trackSeAt(Track track, int slot) =>
    slot >= 0 && slot < track.seLayers.length ? track.seLayers[slot] : null;

/// The [slot]th SE layer for the rail's timeline-parity controls; null
/// only while the active cut lives on ANOTHER track. A GAP (no active
/// cut) keeps the controls up (UI-R10 #12): the SE rows are TRACK-owned —
/// standing in a gap merely means no cut is selected.
Layer? _activeSlotLayerOf(Track track, CutId? activeCutId, int slot) {
  if (activeCutId != null && !track.cuts.any((cut) => cut.id == activeCutId)) {
    return null;
  }
  return _trackSeAt(track, slot);
}

/// SE slot rows in the rail: the same bordered-row language as the track
/// row above them, compact like the timeline's SE rows — with the timeline
/// rows' controls and a lane chevron (twirl-down waveform strip).
class _StoryboardSeLabel extends StatelessWidget {
  const _StoryboardSeLabel({
    required this.track,
    required this.slot,
    this.laneExpanded = false,
    this.onToggleLane,
    this.activeLayer,
    this.active = false,
    this.onSelectLayer,
    this.onToggleLayerVisibility,
    this.onToggleLayerMuted,
    this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.onLayerMarkSelected,
    this.layerFxEnabledOf,
    this.onToggleLayerFx,
    this.opacityDragPreview,
  });

  final Track track;
  final int slot;

  final bool laneExpanded;
  final VoidCallback? onToggleLane;

  /// The ACTIVE cut's layer behind this slot (null while the active cut
  /// lives on another track or has no such slot) — the timeline-parity
  /// controls act on it.
  final Layer? activeLayer;

  /// Whether this row is THE selected row — the same highlight the
  /// timeline row shows (W3 identity keeps them in sync automatically).
  final bool active;

  /// Tapping the row selects its track layer, like tapping a timeline
  /// row label. Null keeps the row display-only.
  final ValueChanged<LayerId>? onSelectLayer;
  final ValueChanged<LayerId>? onToggleLayerVisibility;
  final ValueChanged<LayerId>? onToggleLayerMuted;
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  final void Function(LayerId layerId, LayerMark mark)? onLayerMarkSelected;

  final bool Function(LayerId layerId)? layerFxEnabledOf;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// The session's live opacity-drag preview (UI-R6 #2): while the master
  /// bar drags THIS row's layer, the slider follows live instead of
  /// waiting for the release commit.
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final layer = activeLayer;
    final trackLayer = _trackSeAt(track, slot);
    final onSelect = onSelectLayer;
    // Rows stack FLUSH like the timeline rail — no inter-row padding
    // (R7-⑤); the 1px borders carry the separation.
    return InkWell(
      key: ValueKey<String>(
        'storyboard-se-label-${track.id.value}-${slot + 1}',
      ),
      onTap: trackLayer == null || onSelect == null
          ? null
          : () => onSelect(trackLayer.id),
      child: Container(
        width: StoryboardPanel._trackLabelWidth,
        height: _seRowHeight,
        // Right-only pad: the section band hugs the left edge (UI-R6 #5);
        // slot columns still line up with the legend header.
        padding: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          // The timeline row's active treatment verbatim (S-row selection,
          // W4): secondaryContainer fill; the accent border is GONE
          // (UI-R18 #5 — selection speaks through the background alone).
          color: active
              ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
              : colorScheme.surface,
          border: Border(
            left: BorderSide(color: colorScheme.outlineVariant),
            right: BorderSide(color: colorScheme.outlineVariant),
            bottom: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Semantics(
          // The rail's ONE selection marker — the V rows carry the same
          // key, so "exactly one row is selected" is one assertion.
          key: active
              ? const ValueKey<String>('storyboard-selected-row')
              : null,
          label: active ? 'selected layer' : 'layer',
          container: true,
          explicitChildNodes: true,
          // The timeline rail's slot grid VERBATIM (UI-R5 unification):
          // [section tag][chevron][sheet][mark][name][waveform-in-fill-
          // slot][fx][eye][mute][opacity] — the legend header lines up
          // over these exact columns.
          child: Row(
            children: [
              // Reserved section slot — the SE zone overlays the group
              // (UI-R7 #2).
              const LayerSectionBandCell(),
              const SizedBox(width: 8),
              // The timeline rows' lane chevron, storyboard-prefixed.
              if (onToggleLane != null)
                InkWell(
                  key: ValueKey<String>(
                    'storyboard-se-lane-toggle-${track.id.value}-${slot + 1}',
                  ),
                  onTap: onToggleLane,
                  child: SizedBox(
                    width: layerLaneToggleSlotWidth,
                    height: _seRowHeight,
                    child: Icon(
                      laneExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                const SizedBox(width: layerLaneToggleSlotWidth),
              // NO sheet toggle here (UI-R9 #5): the timesheet flag is a
              // CUT-scoped setting ("drop this layer from THIS cut's
              // sheet") and the storyboard rail is track-global — the
              // slot stays reserved (empty) so the grid keeps lining up
              // and a future control can move in.
              const SizedBox(width: layerTimesheetSlotWidth),
              const SizedBox(width: layerControlChipGap),
              if (layer != null && onLayerMarkSelected != null)
                LayerMarkChip(
                  keyPrefix: 'storyboard',
                  layerId: layer.id,
                  mark: layer.mark,
                  onMarkSelected: onLayerMarkSelected!,
                )
              else
                const SizedBox(width: layerMarkSlotWidth),
              const SizedBox(width: layerControlChipGap),
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.music_note_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        // The TRACK layer's stored name — the same label
                        // the timeline row shows (W3 ordering unification).
                        trackLayer?.name ?? 'S${slot + 1}',
                        overflow: TextOverflow.ellipsis,
                        // Selection reads by COLOR only (user rule).
                        style: TextStyle(
                          fontSize: 11,
                          color: active
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // NO waveform-hide eye (UI-R7 #8): the timeline rows carry
              // none either — the twirled-down Audio lane is the "big
              // waveform" view. The fill-reference slot stays reserved so
              // the trailing columns align.
              const SizedBox(width: layerFillReferenceSlotWidth),
              if (layer != null &&
                  onToggleLayerFx != null &&
                  layerKindShowsFxToggle(layer.kind))
                FxToggleButton(
                  keyValue: 'storyboard-layer-fx-${layer.id}',
                  fxEnabled: layerFxEnabledOf?.call(layer.id) ?? true,
                  onToggle: () => onToggleLayerFx!(layer.id),
                )
              else
                const SizedBox(width: layerFxSlotWidth),
              if (layer != null && onToggleLayerVisibility != null)
                LayerVisibilityToggleButton(
                  keyValue: 'storyboard-layer-visibility-${layer.id}',
                  isVisible: layer.isVisible,
                  onToggle: () => onToggleLayerVisibility!(layer.id),
                )
              else
                const SizedBox(width: layerVisibilitySlotWidth),
              if (layer != null && onToggleLayerMuted != null)
                SizedBox(
                  width: layerMuteSlotWidth,
                  height: 26,
                  child: LayerMuteToggleButton(
                    keyValue: 'storyboard-layer-mute-${layer.id}',
                    muted: layer.muted,
                    onToggle: () => onToggleLayerMuted!(layer.id),
                  ),
                )
              else
                const SizedBox(width: layerMuteSlotWidth),
              if (layer != null && onLayerOpacityChanged != null)
                SizedBox(
                  width: layerOpacitySlotWidth,
                  child: _opacityField(layer),
                )
              else
                const SizedBox(width: layerOpacitySlotWidth),
            ],
          ),
        ),
      ),
    );
  }

  /// The row's opacity slider, live-following the session's drag preview
  /// when it targets this layer (the master bar sweep, UI-R6 #2).
  Widget _opacityField(Layer layer) {
    Widget slider(double value) => FieldSlider(
      key: ValueKey<String>('storyboard-layer-opacity-${layer.id}'),
      min: 0,
      max: 1,
      value: value,
      valueText: '${(value * 100).round()}%',
      valueTextBuilder: (next) => '${(next * 100).round()}%',
      displayFactor: 100,
      height: 18,
      onChanged: (opacity) => onLayerOpacityChanged!(layer.id, opacity),
      onChangeEnd: onLayerOpacityChangeEnd == null
          ? null
          : (opacity) => onLayerOpacityChangeEnd!(layer.id, opacity),
    );

    final preview = opacityDragPreview;
    final resting = layer.opacity.clamp(0.0, 1.0).toDouble();
    if (preview == null) {
      return slider(resting);
    }
    return ValueListenableBuilder<({Set<LayerId> layerIds, double opacity})?>(
      valueListenable: preview,
      builder: (context, dragging, _) => slider(
        dragging != null && dragging.layerIds.contains(layer.id)
            ? dragging.opacity
            : resting,
      ),
    );
  }
}

/// A twirled-down lane's rail label row (Audio / Opacity), indented under
/// its owner row like the timeline's lane labels.
class _StoryboardLaneLabel extends StatelessWidget {
  const _StoryboardLaneLabel({
    required this.laneKey,
    required this.label,
    required this.icon,
    required this.height,
  });

  final String laneKey;
  final String label;
  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>(laneKey),
      width: StoryboardPanel._trackLabelWidth,
      height: height,
      padding: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        // Side/bottom borders only (UI-R10 #20), like the timeline rail.
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant),
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // The rows' section band continues through lane rows (UI-R6 #5).
          const LayerSectionBandCell(),
          const SizedBox(width: 18),
          Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One TRACK-owned SE row: the track's [slot]th SE layer rendered straight
/// on the global frame axis — blocks keep their true lengths (a sound may
/// cross cut boundaries; each crossed boundary draws a `~` continuation
/// mark) and the timeline's data is exactly this layer, by identity.
class _StoryboardSeRow extends StatelessWidget {
  const _StoryboardSeRow({
    required this.trackIndex,
    required this.slot,
    required this.layer,
    required this.layoutEntries,
    required this.width,
    required this.timelineScale,
    required this.projectFrameRate,
    this.audioPeaksFor,
    this.onRowFramePress,
    this.seCommaDrag,
    this.seSelect,
    this.frameGeometry,
    this.seRowsInDisplayOrder = const [],
  });

  final int trackIndex;
  final int slot;

  /// This track's S rows top-to-bottom — what a MOVE's row delta walks.
  /// Only S rows are in it, which is what keeps a drag from crossing into
  /// a row whose blocks are not sounds.
  final List<TimelineDisplayRow> seRowsInDisplayOrder;

  /// The track's GLOBAL SE layer behind this row (null = fewer rows).
  final Layer? layer;
  final List<StoryboardTimelineLayoutEntry> layoutEntries;
  final double width;
  final TimelineScale timelineScale;
  final ProjectFrameRate projectFrameRate;
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// Timeline parity: the row's cells press (row + frame, empty cells
  /// included) and EVERY block carries the comma edge grips (UI-R7 #5 —
  /// global starts, any cut).
  final StoryboardRowFramePress? onRowFramePress;
  final TimelineCommaDragCallbacks? seCommaDrag;

  /// Range selection on this row — the SAME shared gesture and the same
  /// track-axis selection the cut row uses, one row up. Null keeps the row
  /// display-only.
  final StoryboardSeSelectCallbacks? seSelect;

  /// The panel's live frame-axis geometry, which the shared gesture reads
  /// to turn a pointer position into a track-global frame.
  final TimelineFrameGeometryHandle? frameGeometry;

  /// Whether the live selection covers this row at [globalFrame].
  bool _isSelectedAt(int globalFrame) {
    final layer = this.layer;
    final selection = seSelect?.selectedRange.value;
    return layer != null &&
        selection != null &&
        selection.coversRow(LayerRowAddress(layer.id)) &&
        selection.contains(globalFrame);
  }

  @override
  Widget build(BuildContext context) {
    final spans = <Widget>[];
    final layer = this.layer;
    if (layer != null) {
      final blocks = drawingBlocks(layer.timeline);
      // Paper blocks first — the storyboard SE row has no cells
      // underneath, so each block paints its own paper span (SePaperSpan)
      // at its TRUE global extent; waveforms go above the paper, the
      // writing on top.
      for (final block in blocks) {
        spans.add(
          Positioned(
            left: timelineScale.leftForFrame(block.startIndex),
            top: 0,
            bottom: 0,
            width:
                (block.endIndexExclusive - block.startIndex) *
                timelineScale.pixelsPerFrame,
            child: IgnorePointer(
              key: ValueKey<String>(
                'storyboard-se-paper-${layer.id}-${block.startIndex}',
              ),
              child: SePaperSpan(
                axis: Axis.horizontal,
                frameCellExtent: timelineScale.pixelsPerFrame,
              ),
            ),
          ),
        );
      }
      // Waveforms above the paper (painted UNDER the SE writing): sounds
      // are FRAME-LINKED — each carrying block windows its waveform,
      // clamped to the block and the file length (cut ends no longer
      // clip — the block may cross them).
      final audioPeaksFor = this.audioPeaksFor;
      if (audioPeaksFor != null) {
        for (final span in seAudioSpans(layer)) {
          final peaks = audioPeaksFor(span.clip.filePath);
          if (peaks == null) {
            continue;
          }
          // The offset trim shrinks the audible tail (same as the
          // timeline rows and playback).
          final endExclusive = math.min(
            span.startFrame +
                peaks.durationFrames(projectFrameRate) -
                span.clip.offsetFrames,
            span.endFrameExclusive,
          );
          if (endExclusive <= span.startFrame) {
            continue;
          }
          spans.add(
            Positioned(
              left: timelineScale.leftForFrame(span.startFrame),
              top: 0,
              bottom: 0,
              width:
                  (endExclusive - span.startFrame) *
                  timelineScale.pixelsPerFrame,
              child: IgnorePointer(
                key: ValueKey<String>(
                  'storyboard-audio-clip-${layer.id}'
                  '-${span.clipIndex}-b${span.startFrame}',
                ),
                child: CustomPaint(
                  painter: WaveformPainter(
                    peaks: peaks,
                    frameRate: projectFrameRate,
                    pixelsPerFrame: timelineScale.pixelsPerFrame,
                    // Ink on the paper spans, like the timeline SE rows.
                    color: timelineDrawingInkColor.withValues(alpha: 0.22),
                    leadingFrames: span.clip.offsetFrames,
                  ),
                ),
              ),
            ),
          );
        }
      }
      // The sheet's writing on the paper blocks.
      for (final block in blocks) {
        String? dialogue;
        String? seName;
        for (final frame in layer.frames) {
          if (frame.id == block.frameId) {
            dialogue = frame.name;
            seName = frame.seName;
            break;
          }
        }
        spans.add(
          Positioned(
            left: timelineScale.leftForFrame(block.startIndex),
            top: 0,
            bottom: 0,
            width:
                (block.endIndexExclusive - block.startIndex) *
                timelineScale.pixelsPerFrame,
            child: IgnorePointer(
              key: ValueKey<String>(
                'storyboard-se-span-${layer.id}-${block.startIndex}',
              ),
              child: SeSpanVisual(
                axis: Axis.horizontal,
                dialogue: dialogue ?? '',
                seName: seName,
              ),
            ),
          ),
        );
      }
      // NO `~` continuation marks here (UI-R7 #6): the storyboard shows
      // the WHOLE flow — blocks simply run across cut boundaries; the
      // cut-scoped timeline view carries the continuation marks instead.
      // Timeline parity: ONE row-wide press selects the row and seeks to
      // the frame under the pointer. It used to be a tap zone per BLOCK,
      // which meant an empty cell answered nothing and a block always
      // landed the playhead on its START — neither is what a timeline cell
      // does. Translucent and mounted BEFORE the grips, so the edges keep
      // comma-drag priority…
      // The selection wash — colour only, over the row's content the way
      // the timeline's selected cells tint their paper (0.12, their very
      // value: the shared range band rides ABOVE this at 0.18, and the two
      // must sum to the timeline's look, not double it).
      final seSelect = this.seSelect;
      if (seSelect != null) {
        spans.add(
          Positioned.fill(
            key: ValueKey<String>('storyboard-se-selection-${layer.id}'),
            child: IgnorePointer(
              child: ValueListenableBuilder<TrackFrameRangeSelection?>(
                valueListenable: seSelect.selectedRange,
                builder: (context, selection, _) {
                  if (selection == null ||
                      !selection.coversRow(LayerRowAddress(layer.id)) ||
                      timelineScale.pixelsPerFrame <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Stack(
                    children: [
                      Positioned(
                        left: timelineScale.leftForFrame(selection.startFrame),
                        top: 0,
                        bottom: 0,
                        width:
                            selection.lengthFrames *
                            timelineScale.pixelsPerFrame,
                        child: ColoredBox(
                          color: timelineSelectedFrameBorderColor.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      }
      if (onRowFramePress != null) {
        spans.add(
          Positioned.fill(
            key: ValueKey<String>('storyboard-se-press-${layer.id}'),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if (event.buttons != 0 &&
                    (event.buttons & kPrimaryButton) == 0) {
                  return;
                }
                if (timelineScale.pixelsPerFrame <= 0) {
                  return;
                }
                onRowFramePress!(
                  LayerRowAddress(layer.id),
                  (event.localPosition.dx / timelineScale.pixelsPerFrame)
                      .floor(),
                );
              },
            ),
          ),
        );
      }
      // THE range gesture — the timeline's, the same one the cut row
      // mounts, addressed to this LAYER row. It states track-global frames
      // because that is the axis this row draws in: the cut-local display
      // clone the timeline shows is windowed to the active cut, so a sound
      // two cuts away has no local index to be selected by. Mounted UNDER
      // the grips so the edges keep comma-drag priority.
      final geometry = frameGeometry;
      if (seSelect != null && geometry != null) {
        spans.add(
          TimelineFrameRangeGestureLayer(
            // The SLOT key (R12-③): the layer already positions itself, so
            // it goes into the Stack bare — a Positioned around it would be
            // a second ParentDataWidget on the same render object.
            key: ValueKey<String>(
              'storyboard-se-range-gesture-slot-${layer.id}',
            ),
            row: LayerRowAddress(layer.id),
            geometry: geometry,
            crossAxisExtent: _seRowHeight,
            callbacks: TimelineRangeGestureCallbacks(
              isInSelection: (_, frame) => _isSelectedAt(frame),
              onSelectUpdate: (_, anchorIndex, headIndex, headRowDelta) =>
                  seSelect.onDrag(
                    layerId: layer.id,
                    anchorGlobalFrame: anchorIndex,
                    headGlobalFrame: headIndex,
                    headRowDelta: headRowDelta,
                  ),
              onTapClear: (_) => seSelect.onClear(),
              // A drag that STARTS inside the selection slides the sounds,
              // and may cross onto a sibling S row — the timeline's own
              // row-change grammar, resolved by the timeline's own
              // resolver over THIS rail's row order.
              //
              // The list it walks holds only this track's S rows, so the
              // clamp is the kind guard: a drag cannot wander onto the cut
              // row (or any other section) because no such row is in it.
              onMoveBegin: (_, _) => seSelect.move?.onBegin(layer.id) ?? false,
              onMoveUpdate: (frameDelta, rowDelta) => seSelect.move?.onUpdate(
                frameDelta,
                resolveBlockMoveTargetLayer(
                  rows: seRowsInDisplayOrder,
                  sourceLayerId: layer.id,
                  rowDelta: rowDelta,
                ),
              ),
              onMoveEnd: () => seSelect.move?.onEnd(),
              onMoveCancel: () => seSelect.move?.onCancel(),
            ),
          ),
        );
      }
      // …and EVERY block carries the timeline's own comma edge grips
      // (UI-R7 #5: the active-cut gate is gone — the strip is the whole
      // flow, so any cut's sound edits in place). Block starts pass
      // GLOBAL frames; the host's callbacks flag them as such
      // (blockStartIsGlobal) so the session skips the active-cut window.
      final seCommaDrag = this.seCommaDrag;
      if (seCommaDrag != null) {
        final grips = <Widget>[];
        var ordinal = 0;
        for (final block in blocks) {
          final blockOrdinal = ordinal;
          ordinal += 1;
          for (final edge in TimelineBlockEdge.values) {
            grips.add(
              TimelineFrameSpan(
                placement: timelineBlockEdgeGripPlacement(
                  edge: edge,
                  startIndex: block.startIndex,
                  endIndexExclusive: block.endIndexExclusive,
                ),
                child: TimelineBlockEdgeGrip(
                  key: ValueKey<String>(
                    'storyboard-se-grip-${layer.id}-$blockOrdinal'
                    '-${edge.name}',
                  ),
                  layerId: layer.id,
                  blockStartIndex: block.startIndex,
                  blockOrdinal: blockOrdinal,
                  edge: edge,
                  resolveFrameCellExtent: () => timelineScale.pixelsPerFrame,
                  callbacks: seCommaDrag,
                ),
              ),
            );
          }
        }
        if (grips.isNotEmpty) {
          spans.add(
            Positioned.fill(
              child: TimelineFixedFrameSpanLayer(
                geometry: TimelineFrameGeometry(
                  frameCellExtent: timelineScale.pixelsPerFrame,
                  frameStartIndex: 0,
                  frameEndIndexExclusive: timelineScale.pixelsPerFrame <= 0
                      ? 0
                      : (width / timelineScale.pixelsPerFrame).ceil(),
                ),
                crossAxisExtent: _seRowHeight,
                axis: Axis.horizontal,
                children: grips,
              ),
            ),
          );
        }
      }
    }

    return SizedBox(
      key: ValueKey<String>('storyboard-se-row-$trackIndex-${slot + 1}'),
      width: width,
      height: _seRowHeight,
      child: Stack(children: spans),
    );
  }
}

/// The twirled-down S row's enlarged waveform strip: the timeline Audio
/// lane ITSELF, mounted ONCE across the whole track (the layer is
/// track-owned — its spans sit on the global axis and slide-edit
/// everywhere; the session's clip edits resolve by layer id).
class _StoryboardAudioLaneRow extends StatelessWidget {
  const _StoryboardAudioLaneRow({
    required this.trackIndex,
    required this.slot,
    required this.layer,
    required this.layoutEntries,
    required this.width,
    required this.timelineScale,
    required this.projectFrameRate,
    this.audioPeaksFor,
    this.seClipMarkerTooltip,
    this.activeCutId,
    this.onSetAudioClipOffset,
  });

  final int trackIndex;
  final int slot;

  /// The track's GLOBAL SE layer behind this lane.
  final Layer? layer;
  final List<StoryboardTimelineLayoutEntry> layoutEntries;
  final double width;
  final TimelineScale timelineScale;
  final ProjectFrameRate projectFrameRate;
  final AudioPeaks? Function(String filePath)? audioPeaksFor;
  final String? seClipMarkerTooltip;
  final CutId? activeCutId;
  final void Function(LayerId layerId, int clipIndex, int offsetFrames)?
  onSetAudioClipOffset;

  @override
  Widget build(BuildContext context) {
    final spans = <Widget>[];
    final onSetAudioClipOffset = this.onSetAudioClipOffset;
    final layer = this.layer;
    // The reused lane renders with timeline metrics: the frame-axis zoom is
    // the storyboard's pixels-per-frame, the cross extent this lane's
    // height.
    final laneMetrics = TimelineGridMetrics(
      frameCellWidth: timelineScale.pixelsPerFrame,
      layerRowHeight: _audioLaneHeight - 2,
    );
    if (layer != null && layoutEntries.isNotEmpty) {
      final totalFrames = layoutEntries.last.endFrame;
      spans.add(
        Positioned(
          left: timelineScale.leftForFrame(0),
          top: 1,
          width: totalFrames * timelineScale.pixelsPerFrame,
          height: _audioLaneHeight - 2,
          child: KeyedSubtree(
            key: ValueKey<String>('storyboard-audio-lane-span-${layer.id}'),
            child: SeAudioLaneFrameRow(
              layer: layer,
              frameStartIndex: 0,
              frameEndIndexExclusive: totalFrames,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: laneMetrics,
              frameRate: projectFrameRate,
              audioPeaksFor: audioPeaksFor,
              keyPrefix: 'storyboard-${layer.id}',
              onSetClipOffset: onSetAudioClipOffset == null
                  ? null
                  : (clipIndex, offsetFrames) =>
                        onSetAudioClipOffset(layer.id, clipIndex, offsetFrames),
            ),
          ),
        ),
      );
      // Recorded-take clipping warning (REC1-D): the same red block-corner
      // marker the timeline and X-sheet mount, over the lane's own frame
      // extent. The tooltip string doubles as the switch.
      final clipTooltip = seClipMarkerTooltip;
      if (clipTooltip != null) {
        spans.add(
          Positioned(
            left: timelineScale.leftForFrame(0),
            top: 1,
            width: totalFrames * timelineScale.pixelsPerFrame,
            height: _audioLaneHeight - 2,
            child: TimelineFixedFrameSpanLayer(
              geometry: TimelineFrameGeometry(
                frameCellExtent: timelineScale.pixelsPerFrame,
                frameStartIndex: 0,
                frameEndIndexExclusive: totalFrames,
              ),
              crossAxisExtent: _audioLaneHeight - 2,
              axis: Axis.horizontal,
              children: timelineRowClipMarkerOverlays(
                layer: layer,
                frameStartIndex: 0,
                frameEndIndexExclusive: totalFrames,
                crossAxisExtent: _audioLaneHeight - 2,
                axis: Axis.horizontal,
                tooltip: clipTooltip,
                color: Theme.of(context).colorScheme.error,
                keyPrefix: 'storyboard-${layer.id}',
              ),
            ),
          ),
        );
      }
    }
    return SizedBox(
      key: ValueKey<String>(
        'storyboard-audio-lane-row-$trackIndex-${slot + 1}',
      ),
      width: width,
      height: _audioLaneHeight,
      child: Stack(children: spans),
    );
  }
}

/// One Transform lane's frame band: the reused timeline lane substrate
/// rendered PER CUT (the audio lane's remount pattern — each span runs
/// cut-local frames at the cut's global left). Key markers ride each
/// cut's own transform track; editing is gated to the ACTIVE cut, like
/// the audio lane's slide edit.
class _StoryboardLaneStripRow extends StatelessWidget {
  const _StoryboardLaneStripRow({
    required this.rowKey,
    required this.layoutEntries,
    required this.width,
    required this.timelineScale,
    required this.laneOf,
    this.activeCutId,
    this.laneEditFor,
  });

  final String rowKey;
  final List<StoryboardTimelineLayoutEntry> layoutEntries;
  final double width;
  final TimelineScale timelineScale;

  /// Resolves one cut's (carrier layer, lane) pair; null skips the cut
  /// (an S slot the cut doesn't carry).
  final (Layer, PropertyLaneRow)? Function(Cut cut) laneOf;
  final CutId? activeCutId;
  final PropertyLaneEditCallbacks? Function(Cut cut)? laneEditFor;

  @override
  Widget build(BuildContext context) {
    final metrics = TimelineGridMetrics(
      frameCellWidth: timelineScale.pixelsPerFrame,
      layerRowHeight: _transformLaneHeight - 2,
    );
    final spans = <Widget>[];
    for (final entry in layoutEntries) {
      final resolved = laneOf(entry.cut);
      if (resolved == null) {
        continue;
      }
      final (carrier, lane) = resolved;
      spans.add(
        Positioned(
          left: timelineScale.leftForFrame(entry.startFrame),
          top: 1,
          width: entry.duration * timelineScale.pixelsPerFrame,
          height: _transformLaneHeight - 2,
          child: KeyedSubtree(
            key: ValueKey<String>('$rowKey-span-${entry.cut.id.value}'),
            child: TimelineLaneFrameRow(
              layer: carrier,
              lane: lane,
              frameStartIndex: 0,
              frameEndIndexExclusive: entry.duration,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: metrics,
              laneEdit: entry.cut.id == activeCutId
                  ? laneEditFor?.call(entry.cut)
                  : null,
              keyPrefix: 'storyboard',
            ),
          ),
        ),
      );
    }
    return SizedBox(
      key: ValueKey<String>(rowKey),
      width: width,
      height: _transformLaneHeight,
      child: Stack(children: spans),
    );
  }
}

/// The twirled-down V track's Opacity lane: one fade-envelope span per cut
/// with draggable fade in/out handles at the span edges — the cut fade
/// ("opacity joins the transform system"). Commits ONE undo per handle
/// drag via [StoryboardPanel.onSetCutFade].
class _StoryboardOpacityLaneRow extends StatelessWidget {
  const _StoryboardOpacityLaneRow({
    required this.trackIndex,
    required this.layoutEntries,
    required this.width,
    required this.timelineScale,
    required this.windowOf,
    this.onSetCutFade,
  });

  final int trackIndex;
  final List<StoryboardTimelineLayoutEntry> layoutEntries;
  final double width;
  final TimelineScale timelineScale;

  /// The cut's window of the owning track's lanes (R4a) — the envelope's
  /// reading.
  final TransformTrack Function(Cut cut) windowOf;

  final void Function(CutId cutId, int fadeInFrames, int fadeOutFrames)?
  onSetCutFade;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey<String>('storyboard-opacity-lane-row-$trackIndex'),
      width: width,
      height: _opacityLaneHeight,
      child: Stack(
        children: [
          for (final entry in layoutEntries)
            Positioned(
              left: timelineScale.leftForFrame(entry.startFrame),
              top: 1,
              bottom: 1,
              width: entry.duration * timelineScale.pixelsPerFrame,
              child: _CutFadeSpan(
                key: ValueKey<String>(
                  'storyboard-cut-fade-span-${entry.cut.id.value}',
                ),
                cut: entry.cut,
                transformWindow: windowOf(entry.cut),
                frameCellExtent: timelineScale.pixelsPerFrame,
                onSetFade: onSetCutFade == null
                    ? null
                    : (fadeIn, fadeOut) =>
                          onSetCutFade!(entry.cut.id, fadeIn, fadeOut),
              ),
            ),
        ],
      ),
    );
  }
}

/// One cut's fade-envelope span. The opacity envelope paints from the
/// cut's WINDOW of the track lane (R4a — any key shape), while dragging
/// an EDGE ZONE previews and commits the canonical fade shape for that
/// end.
class _CutFadeSpan extends StatefulWidget {
  const _CutFadeSpan({
    super.key,
    required this.cut,
    required this.transformWindow,
    required this.frameCellExtent,
    this.onSetFade,
  });

  final Cut cut;

  /// The cut's window of the owning track's lanes, LOCAL frames — what
  /// the envelope samples and the handles parse.
  final TransformTrack transformWindow;

  final double frameCellExtent;
  final void Function(int fadeInFrames, int fadeOutFrames)? onSetFade;

  @override
  State<_CutFadeSpan> createState() => _CutFadeSpanState();
}

class _CutFadeSpanState extends State<_CutFadeSpan> {
  static const double _handleExtent = 14;

  double _dragDelta = 0;
  bool _dragging = false;
  bool _draggingOut = false;

  int get _deltaFrames => (_dragDelta / widget.frameCellExtent).round();

  int get _maxFade => math.max(0, widget.cut.duration - 1);

  ({int fadeInFrames, int fadeOutFrames}) get _baseLengths =>
      trackFadeLengthsInWindow(
        widget.transformWindow,
        startFrame: 0,
        duration: widget.cut.duration,
      );

  int get _previewFadeIn {
    final base = _baseLengths.fadeInFrames;
    if (!_dragging || _draggingOut) {
      return base;
    }
    return (base + _deltaFrames).clamp(0, _maxFade);
  }

  int get _previewFadeOut {
    final base = _baseLengths.fadeOutFrames;
    if (!_dragging || !_draggingOut) {
      return base;
    }
    return (base - _deltaFrames).clamp(0, _maxFade);
  }

  void _endDrag() {
    final fadeIn = _previewFadeIn;
    final fadeOut = _previewFadeOut;
    final base = _baseLengths;
    setState(() {
      _dragging = false;
      _dragDelta = 0;
    });
    if (fadeIn != base.fadeInFrames || fadeOut != base.fadeOutFrames) {
      widget.onSetFade?.call(fadeIn, fadeOut);
    }
  }

  /// Per-frame opacity samples: the window's lane at rest, the canonical
  /// preview shape while a handle drags.
  List<double> _envelopeSamples() {
    final duration = math.max(1, widget.cut.duration);
    if (!_dragging) {
      return [
        for (var frame = 0; frame < duration; frame += 1)
          trackFadeOpacityAt(widget.transformWindow, frame),
      ];
    }
    final fadeIn = _previewFadeIn;
    final fadeOut = _previewFadeOut;
    final last = duration - 1;
    return [
      for (var frame = 0; frame < duration; frame += 1)
        math.min(
          fadeIn > 0 && frame < fadeIn ? frame / fadeIn : 1.0,
          fadeOut > 0 && frame > last - fadeOut
              ? (last - frame) / fadeOut
              : 1.0,
        ),
    ];
  }

  Widget _handleZone({required bool trailing}) {
    return Positioned(
      left: trailing ? null : 0,
      right: trailing ? 0 : null,
      top: 0,
      bottom: 0,
      width: _handleExtent,
      child: Tooltip(
        message: trailing ? 'Fade Out' : 'Fade In',
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: ValueKey<String>(
              'storyboard-cut-fade-${trailing ? 'out' : 'in'}-handle-'
              '${widget.cut.id.value}',
            ),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) => setState(() {
              _dragging = true;
              _draggingOut = trailing;
              _dragDelta = 0;
            }),
            onHorizontalDragUpdate: (details) =>
                setState(() => _dragDelta += details.delta.dx),
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: () => setState(() {
              _dragging = false;
              _dragDelta = 0;
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final editable = widget.onSetFade != null && widget.cut.duration > 1;
    final fadeIn = _previewFadeIn;
    final fadeOut = _previewFadeOut;
    // One envelope color: the fade is transparency now (R3b) — there is
    // no per-cut target to tint toward, and a white-out is a white cut on
    // a lower track.
    final envelopeColor = AppColors.accent;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.all(Radius.circular(3)),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: CustomPaint(
              painter: _CutFadeEnvelopePainter(
                samples: _envelopeSamples(),
                pixelsPerFrame: widget.frameCellExtent,
                lineColor: envelopeColor,
                fillColor: envelopeColor.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
        if (editable) _handleZone(trailing: false),
        if (editable) _handleZone(trailing: true),
        if (_dragging)
          Positioned(
            left: 4,
            top: 1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  child: Text(
                    _draggingOut ? 'out ${fadeOut}f' : 'in ${fadeIn}f',
                    style: const TextStyle(fontSize: 9, color: Colors.black),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints a cut's opacity envelope: a line through per-frame samples with
/// the area underneath filled — 1.0 rides the top edge, 0.0 the bottom.
class _CutFadeEnvelopePainter extends CustomPainter {
  const _CutFadeEnvelopePainter({
    required this.samples,
    required this.pixelsPerFrame,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> samples;
  final double pixelsPerFrame;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.isEmpty) {
      return;
    }
    const inset = 2.0;
    final usable = size.height - inset * 2;
    double yFor(double value) => inset + (1 - value.clamp(0.0, 1.0)) * usable;

    final line = Path()..moveTo(0, yFor(samples.first));
    for (var frame = 0; frame < samples.length; frame += 1) {
      // Each frame holds its value across its own cell.
      final left = frame * pixelsPerFrame;
      final right = math.min(size.width, left + pixelsPerFrame);
      final y = yFor(samples[frame]);
      line.lineTo(left, y);
      line.lineTo(right, y);
      if (right >= size.width) {
        break;
      }
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _CutFadeEnvelopePainter oldDelegate) {
    if (oldDelegate.pixelsPerFrame != pixelsPerFrame ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.samples.length != samples.length) {
      return true;
    }
    for (var index = 0; index < samples.length; index += 1) {
      if (oldDelegate.samples[index] != samples[index]) {
        return true;
      }
    }
    return false;
  }
}

/// Rail rows share the timeline label rail's row language — bordered
/// surface rows, a kind icon leading the name — so the storyboard's left
/// edge reads near-identically to the timeline's layers/sections rail
/// (user direction). The track row opens its section like the timeline's
/// heavier section divider.
class _StoryboardTrackLabel extends StatelessWidget {
  const _StoryboardTrackLabel({
    required this.track,
    required this.trackLabel,
    required this.laneHeight,
    this.laneExpanded = false,
    this.onToggleLane,
    this.active = false,
    this.onSelectTrack,
    this.activeCut,
    this.subjectCut,
    this.cutFxEnabledOf,
    this.onToggleCutFx,
    this.cutPictureVisibleOf,
    this.onToggleCutPictureVisibility,
  });

  final Track track;
  final String trackLabel;

  /// Kept in lockstep with the strip row's: the rail and the strips are two
  /// columns of the same row and share no scaffolding to enforce it.
  final double laneHeight;

  /// Whether there is room for the track NAME under the V label. The bold
  /// label and the 11pt name stack to about 36px, so the floor height (28)
  /// fits exactly one of them.
  bool get _showsSecondLine => laneHeight >= _twoLineLaneHeight;

  /// The height two stacked label lines need. Below it the rail prints the
  /// V label alone.
  static const double _twoLineLaneHeight = 40;

  final bool laneExpanded;
  final VoidCallback? onToggleLane;

  /// This row is THE selected row — the S-row active treatment (background
  /// only, UI-R18 #5/#6).
  final bool active;

  /// Tapping the row selects the TRACK (UI-R18 #6): the session promotes
  /// its playhead-index cut to active. Null keeps the row display-only.
  final VoidCallback? onSelectTrack;

  /// The ACTIVE cut when it lives on this track (null otherwise) — the
  /// transform-lane gating still keys off it.
  final Cut? activeCut;

  /// The fx/eye buttons' target (UI-R13 #2): THIS track's cut at the
  /// current global index. The buttons render NORMAL always — no parked
  /// look, no stand-down; null (a gap on this track) just makes a press
  /// a no-op, because no cut exists at the index.
  final Cut? subjectCut;
  final bool Function(CutId cutId)? cutFxEnabledOf;
  final ValueChanged<CutId>? onToggleCutFx;
  final bool Function(CutId cutId)? cutPictureVisibleOf;
  final ValueChanged<CutId>? onToggleCutPictureVisibility;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // V-track selection (UI-R18 #6): the S-row tap/highlight language on
    // the V row — tap selects the TRACK, the active treatment speaks
    // through the background alone.
    return InkWell(
      key: ValueKey<String>('storyboard-track-select-${track.id.value}'),
      onTap: onSelectTrack,
      child: Container(
        key: ValueKey<String>('storyboard-track-label-row-${track.id.value}'),
        width: StoryboardPanel._trackLabelWidth,
        height: laneHeight,
        padding: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
              : colorScheme.surface,
          // Side/bottom borders only (UI-R10 #20): stacked rail rows keep
          // single-pixel seams, like the timeline rail.
          border: Border(
            left: BorderSide(color: colorScheme.outlineVariant),
            right: BorderSide(color: colorScheme.outlineVariant),
            bottom: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Semantics(
          // The rail's ONE selection marker, shared with the S rows: a V
          // row is a row like any other, so both kinds answer here.
          key: active
              ? const ValueKey<String>('storyboard-selected-row')
              : null,
          label: active ? 'selected track' : 'track',
          container: true,
          explicitChildNodes: true,
          child: Row(
            children: [
              // Reserved section slot — the V zone overlays the group
              // (UI-R7 #2).
              const LayerSectionBandCell(),
              const SizedBox(width: 8),
              // The timeline rows' lane chevron: twirls down the track's
              // cut-level Transform group (the V-track lanes + fade strip).
              if (onToggleLane != null)
                InkWell(
                  key: ValueKey<String>(
                    'storyboard-track-lane-toggle-${track.id.value}',
                  ),
                  onTap: onToggleLane,
                  child: SizedBox(
                    width: 16,
                    height: 24,
                    child: Icon(
                      laneExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                const SizedBox(width: 16),
              const Icon(Icons.movie_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trackLabel,
                      key: ValueKey<String>(
                        'storyboard-track-label-${track.id.value}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    // The NAME stands down on a short row (feedback #8): two
                    // stacked lines need more than the floor height gives,
                    // and the row used to overflow its bottom by 9px there.
                    // The same grammar as the cut block's bands folding —
                    // a height threshold drops the detail, never the label
                    // that says which row this is.
                    if (track.name.isNotEmpty && _showsSecondLine)
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              // V-row display toggles (UI-R13 #2): ALWAYS-normal buttons in
              // the shared fx/eye slots (UI-R5) acting on THIS track's cut at
              // the current global index — no stand-down, no parked graying.
              // Where no cut exists (a gap on this track) a press is a no-op;
              // the button is track furniture, only its subject is absent.
              const SizedBox(width: layerFillReferenceSlotWidth),
              if (onToggleCutFx != null)
                FxToggleButton(
                  keyValue:
                      'storyboard-cut-fx-'
                      '${subjectCut?.id.value ?? 'none-${track.id.value}'}',
                  subject: 'cut',
                  size: 26,
                  fxEnabled: subjectCut == null
                      ? true
                      : (cutFxEnabledOf?.call(subjectCut!.id) ?? true),
                  onToggle: () {
                    final subject = subjectCut;
                    if (subject != null) {
                      onToggleCutFx!(subject.id);
                    }
                  },
                )
              else
                const SizedBox(width: layerFxSlotWidth),
              if (onToggleCutPictureVisibility != null)
                SizedBox(
                  width: layerVisibilitySlotWidth,
                  height: 26,
                  // The SAME eye the layer and folder rows mount — this was
                  // a sixth inline copy (R28 follow-up).
                  child: LayerVisibilityToggleButton(
                    keyValue:
                        'storyboard-cut-visibility-'
                        '${subjectCut?.id.value ?? 'none-${track.id.value}'}',
                    subject: 'cut picture',
                    isVisible:
                        subjectCut == null ||
                        (cutPictureVisibleOf?.call(subjectCut!.id) ?? true),
                    onToggle: () {
                      final subject = subjectCut;
                      if (subject != null) {
                        onToggleCutPictureVisibility!(subject.id);
                      }
                    },
                  ),
                )
              else
                const SizedBox(width: layerVisibilitySlotWidth),
              const SizedBox(width: layerMuteSlotWidth),
              const SizedBox(width: layerOpacitySlotWidth),
            ],
          ),
        ),
      ),
    );
  }
}

/// The end line's drag grip (UI-R18 #15 → UI-R20 #3): a 12px strip over
/// the strips' movie-end line; dragging it edits the movie's FINAL
/// LENGTH (the project's trailing gap) through the session channel —
/// live preview, ONE undo on release. It never touches the cuts.
class _StoryboardEndLineHandle extends StatefulWidget {
  const _StoryboardEndLineHandle({
    required this.left,
    required this.pixelsPerFrame,
    required this.movieEnd,
  });

  final double left;
  final double pixelsPerFrame;
  final StoryboardMovieEndCallbacks movieEnd;

  @override
  State<_StoryboardEndLineHandle> createState() =>
      _StoryboardEndLineHandleState();
}

class _StoryboardEndLineHandleState extends State<_StoryboardEndLineHandle> {
  double _dx = 0;
  bool _dragging = false;

  void _start() {
    if (!widget.movieEnd.onBegin()) {
      return;
    }
    _dragging = true;
    _dx = 0;
  }

  void _update(double delta) {
    if (!_dragging) {
      return;
    }
    _dx += delta;
    widget.movieEnd.onUpdate((_dx / widget.pixelsPerFrame).round());
  }

  void _end() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.movieEnd.onEnd();
  }

  void _cancel() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.movieEnd.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: const ValueKey<String>('storyboard-cut-end-handle'),
      left: widget.left,
      top: 0,
      bottom: 0,
      width: 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => _start(),
          onHorizontalDragUpdate: (details) => _update(details.delta.dx),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _cancel,
        ),
      ),
    );
  }
}

/// One panel of the strip as the edit chrome sees it: a global frame span,
/// and what its two edges mean.
typedef _StoryboardStripGrip = ({
  CutId cutId,
  int startFrame,
  int endFrameExclusive,

  /// Whether this is its cut's FIRST panel — the only one whose leading
  /// edge carries a grip, and that grip is the cut's start trim.
  bool isFirst,

  /// The CUT-LOCAL timeline key of the block this panel's trailing edge
  /// comma-resizes, or null when that edge is the cut's own length
  /// instead (the last panel — it goes through the cut-edge begin, which
  /// also serves cuts with no storyboard row at all).
  int? commaBlockKey,
});

class _StoryboardTrackRow extends StatelessWidget {
  const _StoryboardTrackRow({
    required this.track,
    required this.layoutEntries,
    required this.activeCutId,
    required this.onRowFramePress,
    required this.laneHeight,
    required this.width,
    required this.stripEdges,
    required this.cutMove,
    required this.cutSelect,
    required this.stripSelect,
    required this.thumbnailFor,
    required this.timelineScale,
    required this.frameGeometry,
    required this.hoveredCutId,
    required this.windowBucket,
    required this.viewportWidth,
    required this.showSeconds,
    required this.projectFrameRate,
  });

  final Track track;
  final List<StoryboardTimelineLayoutEntry> layoutEntries;

  /// The scroll content's full width — the SE rows' own. The row used to
  /// size itself to its cuts, which left NO widget (no press, no range
  /// gesture) past the last cut or on an empty track, while every empty
  /// cell there is still a cell ("빈 칸도 칸").
  final double width;

  /// Null = no cut selected (gap state, UI-R9 #3): no highlight,
  /// cut-scoped rail controls stand down.
  final CutId? activeCutId;
  final StoryboardRowFramePress? onRowFramePress;

  /// This row's height — the rail's matching label row reads the same one.
  final double laneHeight;
  final StoryboardStripEdgeCallbacks? stripEdges;
  final StoryboardCutMoveCallbacks? cutMove;
  final StoryboardCutSelectCallbacks? cutSelect;

  /// Range selection on the STRIP — the cut's own panels, on the cut's own
  /// axis. Null keeps the strip display-only.
  final StoryboardStripSelectCallbacks? stripSelect;
  final StoryboardThumbnailResolver? thumbnailFor;
  final TimelineScale timelineScale;

  /// The panel's live frame-axis geometry — what the SHARED range gesture
  /// reads to turn a pointer position into a track-global frame.
  final TimelineFrameGeometryHandle frameGeometry;

  /// The cut under the pointer, panel-wide: with the blocks painted there
  /// is no widget per cut to hold a hover state, so one notifier does for
  /// the whole row and a hover is a repaint rather than a rebuild.
  final ValueNotifier<CutId?> hoveredCutId;

  /// The shared window inputs (UI-R16): the blocks painter draws — and asks
  /// for thumbnails — only inside the visible span.
  final ValueListenable<int> windowBucket;
  final double viewportWidth;

  final bool showSeconds;
  final ProjectFrameRate projectFrameRate;

  /// The cut covering track-global [frame], or null in a gap / past the
  /// end. The row's blocks are the snap material, so a press that lands
  /// between cuts addresses no cut at all — the same answer
  /// [TrackFrameAxis.cutBlockAt] gives the shared snap rule.
  StoryboardTimelineLayoutEntry? _cutAtFrame(int frame) {
    for (final entry in layoutEntries) {
      if (frame < entry.startFrame) {
        return null;
      }
      if (frame < entry.endFrame) {
        return entry;
      }
    }
    return null;
  }

  /// Each cut's panels, under the coverage rule — the strip's content AND
  /// the row's grip material, resolved once for both. A cut with no
  /// storyboard row still answers with ONE cell over the whole cut, so
  /// neither consumer has an empty case to handle.
  Map<CutId, List<StoryboardCoverageCell>> _cellsByCut() => {
    for (final entry in layoutEntries)
      entry.cutId: storyboardCoverageCells(
        timeline: storyboardLayerForCut(entry.cut)?.timeline,
        cutDuration: entry.duration,
      ),
  };

  /// One entry per PANEL of the row, in track order — what the edit chrome
  /// hangs its grips on.
  ///
  /// The cut has no edge grips of its own any more (design, user's rule
  /// 2026-07-25): a cut edge is always ON the strip, so the first panel's
  /// leading edge IS the cut's start and the last panel's trailing edge IS
  /// its length. Each panel therefore carries exactly one edge — its END —
  /// and only the first carries a start as well, which is what leaves ONE
  /// grip per boundary instead of two facing each other across it.
  ///
  /// A cut with no storyboard row has a single panel spanning it, so it
  /// grows exactly the two grips it had before: the new rule's degenerate
  /// case IS the old behaviour, with no branch saying so.
  ///
  /// An inner trailing edge needs its panel's own TIMELINE key (the block
  /// its comma resizes), which the coverage cell cannot answer — the first
  /// cell's startIndex is clamped to 0 whatever its key says — so the keys
  /// are read off the row alongside the cells.
  List<_StoryboardStripGrip> _stripGrips(
    Map<CutId, List<StoryboardCoverageCell>> cellsByCut,
  ) => [
    for (final entry in layoutEntries)
      if (cellsByCut[entry.cutId] case final cells?)
        ...() {
          final keys = storyboardDivisionKeys(
            timeline: storyboardLayerForCut(entry.cut)?.timeline,
            cutDuration: entry.duration,
          );
          return [
            for (var index = 0; index < cells.length; index += 1)
              (
                cutId: entry.cutId,
                startFrame: entry.startFrame + cells[index].startIndex,
                endFrameExclusive:
                    entry.startFrame + cells[index].endIndexExclusive,
                isFirst: index == 0,
                commaBlockKey: index == cells.length - 1 || index >= keys.length
                    ? null
                    : keys[index],
              ),
          ];
        }(),
  ];

  /// The STRIP's half of the shared range gesture.
  ///
  /// The strip is a CUT-OWNED row, so its selection is the cut-local one —
  /// which is also why the drag never leaves the cut it started in: a
  /// cut-local index cannot name a frame in another cut. That is the
  /// "clip to the anchor cut" rule, arriving as arithmetic rather than as
  /// a guard.
  ///
  /// The row address is ignored, as it is on the cut row: the pressed FRAME
  /// says which cut, and therefore which storyboard layer, the drag is on.
  /// The strip under [frame]: the covering cut and its storyboard row —
  /// null in gaps and on cuts without one. The strip GESTURE and its
  /// hit-test gate read this one answer, so what the callbacks would
  /// refuse is exactly what the gate lets fall through.
  ({StoryboardTimelineLayoutEntry entry, Layer layer})? _stripAt(int frame) {
    final entry = _cutAtFrame(frame);
    if (entry == null) {
      return null;
    }
    final layer = storyboardLayerForCut(entry.cut);
    return layer == null ? null : (entry: entry, layer: layer);
  }

  TimelineRangeGestureCallbacks? _stripGesture() {
    final stripSelect = this.stripSelect;
    if (stripSelect == null) {
      return null;
    }
    return TimelineRangeGestureCallbacks(
      isInSelection: (_, frame) {
        final strip = _stripAt(frame);
        final selection = stripSelect.selection.value;
        return strip != null &&
            selection != null &&
            selection.coversLayer(strip.layer.id) &&
            selection.contains(frame - strip.entry.startFrame);
      },
      onSelectUpdate: (_, anchorIndex, headIndex, _) {
        final strip = _stripAt(anchorIndex);
        if (strip == null) {
          return;
        }
        final start = strip.entry.startFrame;
        final lastLocal = strip.entry.duration - 1;
        int localOf(int globalFrame) =>
            (globalFrame - start).clamp(0, lastLocal < 0 ? 0 : lastLocal);
        stripSelect.onDrag(
          layerId: strip.layer.id,
          anchorIndex: localOf(anchorIndex),
          headIndex: localOf(headIndex),
        );
      },
      onTapClear: (_) => stripSelect.onClear(),
      // Sliding the panels: the same move the timeline's rows do, on the
      // cut's own axis. The pressed frame says which cut — and therefore
      // which storyboard row — the drag belongs to, exactly as the select
      // half reads it.
      onMoveBegin: (_, frame) {
        final strip = _stripAt(frame);
        return strip != null &&
            (stripSelect.move?.onBegin(strip.layer.id) ?? false);
      },
      // No target row is ever reported: a cut has exactly one storyboard
      // row, so there is nowhere sideways to land.
      onMoveUpdate: (frameDelta, _) =>
          stripSelect.move?.onUpdate(frameDelta, null),
      onMoveEnd: () => stripSelect.move?.onEnd(),
      onMoveCancel: () => stripSelect.move?.onCancel(),
    );
  }

  /// Whether [frame] sits in the live selection — a plain range test now
  /// that the selection IS a range on this row's own axis.
  bool _isSelectedAt(int frame) {
    final selection = cutSelect?.selectedRange.value;
    return selection != null &&
        selection.coversRow(TrackRowAddress(track.id)) &&
        selection.contains(frame);
  }

  /// The cut row's half of the shared range gesture: SELECT paints a cut
  /// run through the session's frame-stated entry point, MOVE slides the
  /// grabbed cut (or the whole selected run) along the frame axis.
  ///
  /// The row delta is ignored: this panel shows one cut row per track and
  /// there is no "drop a cut on another track" verb — a cross-track move
  /// would need one, not a different gesture.
  TimelineRangeGestureCallbacks? _rangeGesture() {
    final cutSelect = this.cutSelect;
    final cutMove = this.cutMove;
    if (cutSelect == null && cutMove == null) {
      return null;
    }
    return TimelineRangeGestureCallbacks(
      // With no selection hookup there is no select domain at all, so
      // every press is a move press — what the block body did before the
      // row had a range gesture. [onMoveBegin] still refuses gaps.
      isInSelection: (_, frame) => cutSelect == null || _isSelectedAt(frame),
      onSelectUpdate: (_, anchorIndex, headIndex, headRowDelta) =>
          cutSelect?.onDrag(
            trackId: track.id,
            anchorGlobalFrame: anchorIndex,
            headGlobalFrame: headIndex,
            headRowDelta: headRowDelta,
          ),
      onTapClear: (_) => cutSelect?.onClear(),
      onMoveBegin: (_, frame) {
        final entry = _cutAtFrame(frame);
        return entry != null && (cutMove?.onBegin(entry.cutId) ?? false);
      },
      onMoveUpdate: (frameDelta, _) => cutMove?.onUpdate(frameDelta),
      onMoveEnd: () => cutMove?.onEnd(),
      onMoveCancel: () => cutMove?.onCancel(),
    );
  }

  /// The timeline cells' contract verbatim: the raw pointer DOWN selects
  /// this row and seeks to the frame under it — never a tap recognizer (the
  /// arena must not delay a select), which is also the only shape that
  /// leaves the row-wide tap free to clear the selection.
  ///
  /// EVERY frame answers, gaps included: an empty cell is still a cell, so
  /// there is no gap rule here — the seek parks, exactly as the ruler's
  /// does. A press inside the live selection stays silent: it is starting a
  /// move, not picking a frame.
  void _handlePressDown(PointerDownEvent event) {
    if (event.buttons != 0 && (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    final frame = _frameAtX(event.localPosition.dx);
    if (_isSelectedAt(frame)) {
      return;
    }
    onRowFramePress?.call(TrackRowAddress(track.id), frame);
  }

  int _frameAtX(double x) => timelineScale.pixelsPerFrame <= 0
      ? 0
      : (x / timelineScale.pixelsPerFrame).floor();

  void _handleHover(PointerHoverEvent event) {
    hoveredCutId.value = _cutAtFrame(_frameAtX(event.localPosition.dx))?.cutId;
  }

  @override
  Widget build(BuildContext context) {
    final timelineWidth = _timelineWidthFor(layoutEntries, timelineScale);
    final rangeGesture = _rangeGesture();
    final cellsByCut = _cellsByCut();
    final grips = _stripGrips(cellsByCut);
    // Where the panels are drawn is where their gestures and their EDGES
    // live — the picture and the pointer read one definition of the band.
    final stripBand = StoryboardCutBlocksPainter.stripBandOf(
      laneHeight,
    );

    return KeyedSubtree(
      key: ValueKey<String>('storyboard-track-row-${track.id.value}'),
      child: SizedBox(
        key: ValueKey<String>(
          'storyboard-track-timeline-area-${track.id.value}',
        ),
        width: math.max(timelineWidth, width),
        height: laneHeight,
        child: Stack(
          children: [
            // THE blocks — one painter for the whole row (R28 #4's rule
            // brought to the cut axis). A cut costs a draw call, not three
            // widgets, and off-window cuts cost nothing at all.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: ValueKey<String>(
                    'storyboard-cut-blocks-${track.id.value}',
                  ),
                  painter: StoryboardCutBlocksPainter(
                    entries: layoutEntries,
                    // Resolved HERE, not in the painter: a cut holding two
                    // storyboard layers is a StateError, and a painter that
                    // throws takes the frame down with it.
                    storyboardLayerNames: {
                      for (final entry in layoutEntries)
                        if (storyboardLayerForCut(entry.cut) case final layer?)
                          entry.cutId: layer.name,
                    },
                    // The STRIP's content: the cut's panels, under the
                    // coverage rule — the same reading the grips hang on.
                    storyboardCellsByCut: cellsByCut,
                    geometry: frameGeometry,
                    crossAxisExtent: laneHeight,
                    minBlockWidth: timelineScale.minBlockWidth,
                    activeCutId: activeCutId,
                    selectedRange: cutSelect?.selectedRange,
                    rowAddress: TrackRowAddress(track.id),
                    hoveredCutId: hoveredCutId,
                    colorScheme: Theme.of(context).colorScheme,
                    brightness: Theme.of(context).brightness,
                    baseTextStyle:
                        Theme.of(context).textTheme.labelSmall ??
                        DefaultTextStyle.of(context).style,
                    showSeconds: showSeconds,
                    countingBase: projectFrameRate.countingBase,
                    thumbnailFor: thumbnailFor,
                    showThumbnails: thumbnailFor != null,
                    windowBucket: windowBucket,
                    viewportMainExtent: viewportWidth,
                  ),
                ),
              ),
            ),
            // The press layer sits ABOVE the blocks and passes pointers
            // through (translucent): the blocks own no tap of their own
            // any more, so nothing competes with the row-wide gesture.
            // It carries the HOVER too, which the block widgets used to
            // track one InkWell apiece.
            Positioned.fill(
              key: ValueKey<String>('storyboard-cut-press-${track.id.value}'),
              child: MouseRegion(
                onHover: _handleHover,
                onExit: (_) => hoveredCutId.value = null,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handlePressDown,
                ),
              ),
            ),
            // THE range gesture — the timeline's, not a copy of it: a pan
            // paints a cut run, a pan starting inside the selection slides
            // it. Mounted UNDER the grips so the edges keep trim priority.
            if (rangeGesture != null)
              TimelineFrameRangeGestureLayer(
                key: ValueKey<String>(
                  'storyboard-cut-range-gesture-slot-${track.id.value}',
                ),
                row: TrackRowAddress(track.id),
                geometry: frameGeometry,
                crossAxisExtent: laneHeight,
                callbacks: rangeGesture,
              ),
            // THE STRIP's own gesture, over the band that draws the panels.
            // It sits ABOVE the cut gesture and covers only the strip, so
            // the split between "the bands are the cut, the strip is its
            // panels" is hit-testing and not a branch: a press on a band
            // simply misses this and lands on the cut gesture below.
            if (_stripGesture() case final stripGesture?)
              Positioned(
                key: ValueKey<String>(
                  'storyboard-strip-gesture-slot-${track.id.value}',
                ),
                left: 0,
                right: 0,
                top: stripBand.top,
                height: stripBand.height,
                // Hit-testing gates the strip gesture to frames that HAVE a
                // strip: its pan claims the arena at DOWN (eager), so a
                // press it cannot answer — a gap, a cut without a
                // storyboard row — must never reach it, or the cut-axis
                // gesture below is starved and the drag dies silently (the
                // real-device "no selection where there is no cut block").
                child: _FrameHitGate(
                  claimsDx: (dx) => _stripAt(_frameAtX(dx)) != null,
                  // The gesture layer fills its Stack, so it needs one of
                  // its own here — a second Positioned around it would be
                  // two ParentDataWidgets on one render object.
                  child: Stack(
                    children: [
                      TimelineFrameRangeGestureLayer(
                        row: TrackRowAddress(track.id),
                        geometry: frameGeometry,
                        crossAxisExtent: stripBand.height,
                        callbacks: stripGesture,
                      ),
                    ],
                  ),
                ),
              ),
            // THE EDGES, on the strip with the panels they divide. They ride
            // ABOVE the strip and cut gestures so an edge keeps its priority
            // over both; the middles keep the rest.
            //
            // One shape of grip, and where it sits decides what it does: the
            // first panel's leading edge re-times the cut's lead, and every
            // trailing edge is its panel's comma with the cut's length
            // riding the row end (edge unification — the division verb is
            // gone). The cut block itself has no edges any more.
            //
            // THE timeline's chrome layer, not a cut-shaped copy of it: one
            // painter and one gesture layer for the whole row, where this
            // used to be two widgets a cut.
            if (stripEdges != null)
              Positioned(
                key: ValueKey<String>(
                  'storyboard-edit-chrome-slot-${track.id.value}',
                ),
                left: 0,
                right: 0,
                top: stripBand.top,
                height: stripBand.height,
                child: TimelineRowEditChromeLayer(
                  paintKey: ValueKey<String>(
                    'storyboard-edit-chrome-${track.id.value}',
                  ),
                  // These grips sit on the CUT BLOCK, not on paper
                  // (feedback #11): its background follows the theme, so
                  // the bars take the light ink where it goes dark.
                  gripSurface: Theme.of(context).brightness,
                  // No layer: these blocks are panels of many cuts, and the
                  // row has no run edges for a LayerId to name.
                  layerId: null,
                  resolver: TimelineRowChromeResolver(
                    gripBlocks: [
                      for (var index = 0; index < grips.length; index += 1)
                        (
                          ordinal: index,
                          startIndex: grips[index].startFrame,
                          endIndexExclusive: grips[index].endFrameExclusive,
                          // Only the first panel of a cut carries a start
                          // grip: inside a cut the panels touch, so one grip
                          // per boundary is the whole of it.
                          startGrip: grips[index].isFirst,
                          endGrip: true,
                        ),
                    ],
                    gripIdScope: track.id.value,
                    layer: null,
                    baseLayer: null,
                    crossAxisExtent: stripBand.height,
                    axis: Axis.horizontal,
                    includeRunEdges: false,
                  ),
                  geometry: frameGeometry,
                  axis: Axis.horizontal,
                  // The row closes the identity in, by ordinal — the grip
                  // hooks themselves know nothing about cuts or panels.
                  grips: TimelineRowGripCallbacks(
                    onBegin: (_, ordinal, edge) {
                      if (ordinal < 0 || ordinal >= grips.length) {
                        return false;
                      }
                      final grip = grips[ordinal];
                      if (edge == TimelineBlockEdge.start) {
                        return stripEdges!.onCutEdgeBegin(
                          grip.cutId,
                          TimelineBlockEdge.start,
                        );
                      }
                      final commaKey = grip.commaBlockKey;
                      return commaKey == null
                          ? stripEdges!.onCutEdgeBegin(
                              grip.cutId,
                              TimelineBlockEdge.end,
                            )
                          : stripEdges!.onCommaBegin(grip.cutId, commaKey);
                    },
                    onUpdate: stripEdges!.onUpdate,
                    onEnd: stripEdges!.onEnd,
                    onCancel: stripEdges!.onCancel,
                  ),
                  runEdit: null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _timelineWidthFor(
    List<StoryboardTimelineLayoutEntry> entries,
    TimelineScale scale,
  ) {
    const trailingPadding = 12.0;

    if (entries.isEmpty) {
      return 0;
    }

    return entries
            .map(
              (entry) =>
                  scale.leftForFrame(entry.startFrame) +
                  scale.widthForDuration(entry.duration),
            )
            .reduce(
              (width, nextWidth) => width > nextWidth ? width : nextWidth,
            ) +
        trailingPadding;
  }
}

/// Admits pointers only where [claimsDx] says yes — the STRIP gesture's
/// hit-test gate. An eager pan claims the arena the moment it is hit, so a
/// gesture layer that would answer a position with nothing must not be hit
/// there at all; refusing in the callbacks is too late.
class _FrameHitGate extends SingleChildRenderObjectWidget {
  const _FrameHitGate({required this.claimsDx, super.child});

  /// Whether a pointer at this row-local x belongs to the gated child.
  final bool Function(double dx) claimsDx;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFrameHitGate(claimsDx);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFrameHitGate renderObject,
  ) {
    renderObject.claimsDx = claimsDx;
  }
}

class _RenderFrameHitGate extends RenderProxyBox {
  _RenderFrameHitGate(this.claimsDx);

  bool Function(double dx) claimsDx;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      claimsDx(position.dx) && super.hitTest(result, position: position);
}

/// Vertical frame-boundary lines behind the cut blocks (the timeline grid's
/// cell borders, storyboard-flavored): every frame when cells are wide,
/// thinning to the shared label cadence when zoomed out.
class _StoryboardFrameLinesPainter extends CustomPainter {
  const _StoryboardFrameLinesPainter({
    required this.pixelsPerFrame,
    required this.color,
    required this.framesPerSecond,
    required this.colorScheme,
  });

  final double pixelsPerFrame;
  final Color color;
  final int framesPerSecond;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelsPerFrame <= 0) {
      return;
    }
    final lineEveryFrames = pixelsPerFrame >= 16
        ? 1
        : TimelineGridMetrics(
            frameCellWidth: pixelsPerFrame,
          ).frameLabelEveryFrames;
    final step = pixelsPerFrame * lineEveryFrames;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // The 6f/24f beat lines over the base grid (UI-R13 #7 — every frame
    // grid carries the sheet rhythm, the storyboard included).
    final sixPaint = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1;
    final secondPaint = Paint()
      ..color = colorScheme.onSurfaceVariant
      ..strokeWidth = 1.5;
    for (var frame = 6; frame * pixelsPerFrame <= size.width; frame += 6) {
      final x = frame * pixelsPerFrame;
      final beatPaint = framesPerSecond > 0 && frame % framesPerSecond == 0
          ? secondPaint
          : sixPaint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), beatPaint);
    }
  }

  @override
  bool shouldRepaint(_StoryboardFrameLinesPainter oldDelegate) {
    return oldDelegate.pixelsPerFrame != pixelsPerFrame ||
        oldDelegate.color != color ||
        oldDelegate.framesPerSecond != framesPerSecond ||
        oldDelegate.colorScheme != colorScheme;
  }
}

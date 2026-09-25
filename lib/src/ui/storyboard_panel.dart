import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Listenable, ValueListenable;
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerHoverEvent, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;

import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_effect.dart' show EffectId, effectParameterValueAt;
import '../models/layer_id.dart';
import '../models/layer_mark.dart';
import '../models/project.dart';
import '../models/project_frame_rate.dart';
import '../models/se_audio_spans.dart';
import '../models/timeline_coverage.dart'
    show
        TimelineBlockEdge,
        TimelineDrawingBlock,
        coveringDrawingBlockAt,
        drawingBlocks;
import '../models/track.dart';
import '../models/track_id.dart';
import '../models/track_transform_lane_carrier.dart';
import 'canvas/flip_hud_controller.dart' show FlipHudAxis;
import 'canvas/flip_hud_model.dart';
import 'canvas/flip_hud_rows.dart';
import 'storyboard/storyboard_rows_channel.dart';
import '../services/audio/audio_peaks_extractor.dart';
import 'audio/waveform_painter.dart';
import 'storyboard_cut_blocks_painter.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnailResolver;
import 'storyboard_layer_policy.dart';
import '../models/storyboard_timeline_layout.dart';
import 'theme/app_theme.dart';
import 'timeline/timeline_frame_axis_follower.dart';
import 'timeline/layer_label_controls.dart';
import 'timeline/layer_opacity_field.dart';
import 'timeline/timeline_cut_end_handle.dart'
    show timelineCutEndPreviewFrameCount;
import 'timeline/layer_rail_columns.dart';
import 'timeline/rail_column_swipe.dart';
import 'timeline/layer_rail_window.dart';
import 'widgets/dock_edge_splitter.dart';
import 'widgets/field_slider.dart';
import 'timeline/property_lane_model.dart'
    show
        PropertyLaneEditCallbacks,
        PropertyLaneRow,
        TimelineDisplayRow,
        laneGroupKey;
import 'timeline/property_lanes_for_row.dart' show propertyLanesForRow;
import 'timeline/timeline_row_span_resolver.dart'
    show
        laneSpanOverDrawnRows,
        resolveBlockMoveTargetLayer,
        resolveInGroupHeadLane,
        resolveLaneSpanEscalationOverAddresses;
import 'timeline/se_audio_lane.dart'
    show SeAudioLaneFrameRow, TimelineAudioLaneCallbacks, laneIsSeAudio;
import 'timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow, TimelineLaneFrameRow;
import 'timeline/effect_lane_policy.dart'
    show effectPropertyLanes, parseEffectLaneId;
import 'timeline/layer_drop_policy.dart' show rowStepsBetween, slotForSteps;
import 'timeline/layer_row_drag.dart'
    show
        EffectRowSubject,
        LayerRowDragTarget,
        LayerRowSubject,
        TimelineRowDragHooks,
        TrackRowSubject,
        effectRowDragChip,
        layerRowDragChips;
import 'timeline/timeline_current_row.dart';
import 'timeline/timeline_ruler_cursor_overlay.dart';
import 'timeline/transform_lane_policy.dart'
    show laneSelectionCoversBandRow, transformGroupHeader;
import '../models/app_input_settings.dart' show AppInput;
import 'widgets/instant_tap_region.dart' show InstantTapRegion;
import 'timeline/timeline_beat_lines.dart'
    show
        TimelineGridLaw,
        TimelineGridRows,
        TimelineGridSheet,
        timelineLaneGround,
        timelineRowPaperExtent;
import 'timeline/timeline_cell_double_tap.dart'
    show timelineCellDoubleTapActivation, timelineCellDoubleTapRecord;
import 'timeline/timeline_drag_preview.dart';
import 'timeline/timeline_cell_style.dart'
    show
        storyboardCutBlockBackgroundColor,
        timelineBlockCornerRadiusAt,
        timelineDrawingInkColor,
        timelineRangeSelectionBandDecorationAt,
        timelineSelectedFrameBorderColor,
        timelineStandingCellDecoration;
import 'timeline/timeline_exposure_comma_drag_handle.dart'
    show TimelineBlockEdgeGrip, timelineBlockEdgeGripPlacement;
import 'timeline/timeline_row_edit_chrome.dart'
    show
        TimelineGripPaper,
        TimelineRowChromeResolver,
        TimelineRowEditChromeLayer,
        TimelineRowGripCallbacks;
import 'timeline/timeline_frame_geometry.dart'
    show TimelineFrameGeometry, TimelineFrameGeometryHandle;
import 'timeline/timeline_frame_range_gesture.dart'
    show
        TimelineFrameRangeGestureLayer,
        TimelineLaneRangeCallbacks,
        TimelineLaneRangeHooks,
        TimelineRangeGestureCallbacks;
import '../models/storyboard_coverage.dart'
    show
        StoryboardCoverageCell,
        storyboardDivisionKeys;
import '../models/timeline_frame_range.dart'
    show TimelineFrameRangeSelection, TimelineLaneSelection;
import '../models/timeline_row_address.dart'
    show LaneRowAddress, LayerRowAddress, TimelineRowAddress, TrackRowAddress;
import '../models/track_frame_range.dart';
import 'media/media_asset_drop_target.dart';
import '../models/timeline_empty_gaps.dart' show emptyGapsBetween;
import 'timeline/timeline_frame_span_layout.dart'
    show
        TimelineFixedFrameSpanLayer,
        TimelineFrameSpan,
        TimelineFrameSpanPlacement;
import 'timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'timeline/timeline_frame_coordinate_policy.dart'
    show FrameScrubDedupe, frameIndexFromLocalX;
import 'timeline/timeline_frame_range_policy.dart'
    show TimelineFrameRange, endlessViewportFillFrames;
import '../models/layer_kind.dart';
import '../models/camera_instruction.dart' show CameraInstructionDef;
import 'timeline/instruction_span_editing.dart' show instructionSpanCovering;
import 'timeline/timeline_instruction_row_visual.dart'
    show timelineRowInstructionEdgeGrips, timelineRowInstructionOverlays;
import 'timeline/timeline_frame_ruler.dart';
import 'timeline/timeline_edge_auto_pan.dart';
import 'timeline/timeline_grid_metrics.dart';
import 'timeline/timeline_row_cross_offset.dart';
import 'timeline/timeline_horizontal_scrollbar_rail.dart';
import 'timeline/timeline_layer_controls_header.dart';
import 'timeline/timeline_vertical_scrollbar_rail.dart';
import 'timeline/timeline_playhead.dart' show timelinePlayheadColor;
import 'timeline/timeline_row_filter.dart';
import 'timeline/timeline_scale.dart';
import 'timeline/timeline_section_policy.dart'
    show TimelineSection, timelineSectionLabel;
import 'timeline/timeline_se_row_visual.dart'
    show SePaperSpan, SeSpanVisual, timelineRowClipMarkerOverlays;
import 'timeline/timeline_selected_exposure_outline.dart'
    show TimelineSelectionRing;
import 'timeline/timeline_zoom_anchor_policy.dart';
import 'layout/device_grid_scroll_controller.dart';
import 'text/app_strings.dart' show AppText;
import 'listenable_rebind.dart';

part 'storyboard/storyboard_standing.dart';
part 'storyboard/storyboard_rows_and_labels.dart';
part 'storyboard/storyboard_scroll.dart';
part 'storyboard/storyboard_rail_rows.dart';
part 'storyboard/storyboard_sheet.dart';

/// One row of the storyboard rail, as the shared swipe sees it.
///
/// Three kinds share the rail and they do not share a subject — see
/// `_StoryboardRailRows._trackGroupRowGeometry`, the only place that builds
/// one, and `railRowsIn`, which walks them.
typedef StoryboardRailRow = ({Track track, Layer? layer, int? seSlot});

/// One row of a track group's rail, as the strip column lays it out.
///
/// [row] is the address a select-drag may land its head on (S rows and the
/// V row). [laneRow] is the address you can STAND on when the row is a
/// property lane — of the V track's carrier or of an SE layer — which is a
/// wider set than [bandRow], the lanes that carry a range band. The
/// fade-envelope row is the case that separates the two: it is the opacity
/// lane's row and takes the standing ring, but it draws fade handles
/// instead of key markers and no selection reaches it.
///
/// [lane] is whether the row is a LANE band at all — the Audio lane as much
/// as a property lane — which is what the grid sheet paints the lane ground
/// under (I-44). Neither address says it: the Audio lane keeps none, and an
/// S slot with no layer keeps none either.
///
/// [railRow] is the row as the rail's column swipe sees it — the transition,
/// S and V rows, which carry the columns. A lane carries none, so it has
/// none, and the walk steps over it.
typedef _StoryboardRailSlot = ({
  TimelineRowAddress? row,
  LaneRowAddress? laneRow,
  bool bandRow,
  bool lane,
  StoryboardRailRow? railRow,
  double height,
});

/// The drag hooks the STRIP's edges need, mirroring the timeline's
/// comma-drag callbacks: live preview per step, ONE undo on release.
///
/// There is one shape of edge on this row, and where it sits decides what
/// it re-times (design, user's rule 2026-07-25; edge unification
/// 2026-07-28, every-panel leading edges 2026-08-02):
///
/// - EVERY leading edge — first and inner alike — is the cut's START, with
///   the panel it belongs to the one that gives up the commas. It is one
///   verb at every ordinal, which is why the ordinal travels with it
///   instead of forking the callback;
/// - EVERY trailing edge — inner and last alike — is that panel's comma,
///   with the cut's length riding the row end.
///
/// Hence two begins and one set of continuations — the grip that started
/// decides which session verb the rest of the drag belongs to, and the
/// mount that knows the geometry is the one that says so.
class StoryboardStripEdgeCallbacks {
  const StoryboardStripEdgeCallbacks({
    required this.onCutEdgeBegin,
    required this.onCommaBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  /// Trims the cut itself. [panelIndex] is the CUT-LOCAL ordinal of the
  /// panel the grip sits on — the panel a LEAD drag takes the frames from.
  /// Returns whether the drag may start (deleted cuts refuse).
  final bool Function(CutId cutId, TimelineBlockEdge edge, int panelIndex)
  onCutEdgeBegin;

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
  /// [headRow] is the Excel-style cross-row reach (feedback #14): the
  /// rail row the pointer is over now, which the PANEL resolves from the
  /// heights it paints (R9 #25 — it used to be a row count computed from
  /// one row height, which mis-counted every row of a different size).
  final void Function({
    required TrackId trackId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? headRow,
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

  /// A select-drag step on the track's GLOBAL frame axis. [headRow]
  /// reaches across the rail's rows exactly as the cut row's does.
  /// [anchorRow]/[spanRows] are the escalated LANE-anchor form (C②): the
  /// panel hands the sliced span of the rows it drew.
  final void Function({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? headRow,
    TimelineRowAddress? anchorRow,
    List<TimelineRowAddress> spanRows,
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

/// A media-browser row let go on a storyboard row, at a track frame — the
/// row and the frame as the press names them ([StoryboardRowFramePress]).
typedef StoryboardMediaDrop =
    void Function(TimelineRowAddress row, int globalFrame, String path);

/// Whether the file standing on a storyboard row at a track frame can land
/// there — the session's answer, which the drag's chip wears (「불가능 = 칩의
/// 금지 표시」).
typedef StoryboardMediaDropAccepts =
    bool Function(TimelineRowAddress row, int globalFrame, String path);

class StoryboardPanel extends StatefulWidget {
  const StoryboardPanel({
    super.key,
    required this.project,
    required this.activeCutId,
    this.onRowFramePress,
    this.onDropMediaAsset,
    this.acceptsMediaAsset,
    this.onDropMediaAssetOnRail,
    this.acceptsMediaAssetOnRail,
    this.activeLayerId,
    this.selectedRow,
    this.onSelectLayer,
    this.onSelectTrack,
    this.stripEdges,
    this.cutMove,
    this.cutSelect,
    this.stripSelect,
    this.onCreateStoryboardLayer,
    this.movieEnd,
    this.trackLaneHeight = defaultTrackLaneHeight,
    this.onResizeTrackLanes,
    this.pixelsPerFrame = 8,
    this.showSeconds = false,
    this.onShowSecondsChanged,
    this.railExtent,
    this.frameAxisOffset,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.playheadFrame,
    this.revealSelectionTick,
    this.playbackFrame,
    this.frameReadySignal,
    this.onSeekGlobalFrame,
    this.onScrubGlobalFrame,
    this.onScrubEnd,
    this.isFrameReady,
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
    this.trackLaneEditFor,
    this.laneRange,
    this.currentRowHooks,
    this.rowDragHooks,
    this.onSeRowSelectionSpan,
    this.layerLaneEdit,
    this.poseDisplaySize,
    this.onSetCutFade,
    this.onToggleLayerVisibility,
    this.onOpenLayerMixer,
    this.isLayerSoloed,
    this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.onLayerMarkSelected,
    this.onToggleLayerTimesheet,
    this.layerOnTimesheetOf,
    this.layerEyeOnOf,
    this.seRowLaneOpenOf,
    this.trackLaneOpenOf,
    this.layerFxStateOf,
    this.onToggleLayerFx,
    this.cutPictureVisibleOf,
    this.onToggleCutPictureVisibility,
    this.trackFxStateOf,
    this.onToggleTrackFx,
    this.trackOpacityOf,
    this.onTrackOpacityChanged,
    this.onTrackOpacityChangeEnd,
    this.onToggleTrackEffectEnabled,
    this.onResetTrackEffectGroup,
    this.onToggleLaneGroupEnabled,
    this.onResetLaneGroup,
    this.seCommaDrag,
    this.seSelect,
    this.audioLane,
    this.transitionDefById,
    this.rowsChannel,
    this.transitionCrossingTooltip,
    this.transitionCommaDrag,
    this.onEditTransitionSpan,
    this.onEditSeEntry,
    this.dragPreview,
    this.legend,
    this.rowFilter = TimelineRowFilter.none,
    this.visibilitySoloEnabled = false,
    this.opacityDragPreview,
    this.legendOpacityValue = 1.0,
  });

  /// Blocks are strictly frame-linear (Premiere-style): a large minimum
  /// width would make neighbours overlap when zoomed out. The tiny floor
  /// only keeps zero-length cuts visible.
  ///
  /// Public since D15: the folded storyboard draws the same blocks and
  /// must not carry a floor of its own — a second `8` over there is a
  /// second answer the day this one moves.
  static const double cutBlockMinWidth = 8;
  static const double _minBlockWidth = cutBlockMinWidth;

  // Wide enough for the timeline-style rows (icon + names) the rail mirrors.
  // 140 → 240 when the S rows gained the timeline-parity layer controls
  // (R4-⑨ '완벽통일'); the control set needs the width, like the timeline
  // rail's own widening for the fx switch.
  // 240 → the timeline rail's width (UI-R5 storyboard unification): the
  // rail rows share the timeline's slot grid and the legend header sits
  // on top, so the columns line up across both panels.
  //
  // 372 → 434 (user, 2026-08-04: "영역의 최대 길이를 둘 다 통일하라는거야").
  // This rail HAD been following the timeline's — the storyboard tests that
  // widen their surfaces still say "the rail widened to the timeline's 372"
  // — and then it missed the one hop that mattered, R27 #6's 372 → 434. It
  // was the odd one out by accident, not by decision.
  //
  // ⛔ NOT `timelineLayerControlsWidth`, deliberately. The user asked for
  // the same NUMBER and explicitly NOT for one source: "다만 코드상 독립.
  // 하나 바꾼다고 다른게 바뀌지않도록." The two rails carry different
  // columns — this one has no blend cell — so the day either needs a new
  // one, the other must be free to stay put. The repetition is the point;
  // do not "clean it up" into a shared constant.
  //
  // 434 → 443 (text-scale-rail-opac, 유저 2026-09-25): the opacity column
  // this rail shares widened to hold the legend's OPAC at 1×, and the
  // answer the user picked named both rails.
  static const double _trackLabelWidth = 443;

  /// [_trackLabelWidth] where [context] lays its text out: this rail pays for
  /// ITS word-holding column's growth — the opacity bar's; it has no blend
  /// column — as the timeline's pays for its two (text-scale-rail-columns,
  /// 유저 2026-09-25: 「칸도 글자 따라 넓어진다」). 0 at 1×.
  static double railWidthIn(BuildContext context) =>
      _trackLabelWidth +
      (layerRailColumnWidthsIn(context).opacity - layerOpacitySlotWidth);

  /// The frame ruler's height — and, since the seconds corner is the strip
  /// beside it, that button's too.
  ///
  /// ㉓ (user, 2026-08-12): 「스토리보드의 「초 표시」 버튼 위치/패딩이
  /// 타임라인과 미묘하게 다르다. 이런 기본규격은 제발 통일하자.
  /// **하드코딩한거냐?**」 — it was: a literal 24 here against the
  /// timeline's ruler, which has always taken its header row's own height.
  /// Four pixels shorter put the icon's centre two above the timeline's,
  /// which is exactly the kind of difference you feel and cannot name.
  ///
  /// ⚠️Unlike [_trackLabelWidth] — the same NUMBER on purpose and
  /// deliberately NOT one source — this one IS the band, so it is written
  /// as the band. The rail widths may diverge (different columns); a strip
  /// and the strip beside it in the same row may not.
  static double _rulerHeightIn(BuildContext context) =>
      _headerBandHeightIn(context);

  /// The V rows' height, and the range the adjustment moves it through.
  ///
  /// ONE height for every V track, not one per track (user's rule): the
  /// rows are the same kind of thing, and a rail whose rows disagree about
  /// height stops reading as a rail. The S rows keep their own sizing —
  /// they twirl audio lanes open, so height means something else there.
  ///
  /// ⚠️The floor was set below the height where the bands FOLDED, on
  /// purpose — the compact look. The bands no longer fold (유저 2026-09-25:
  /// 「띠는 v행 세로 줄어도 고정으로 그 자리에 두자」), so at this floor the
  /// strip between them keeps 2px of picture while every word of the bands
  /// stays whole — the compact look is now a row of writing.
  static const double defaultTrackLaneHeight = 64;
  // Min/max are the height's LEGAL RANGE — the bar's steppers died with B7
  // (2026-08-17), and the V-track splitter (2026-09-26) clamps to the same
  // pair ([onResizeTrackLanes]).
  static const double minTrackLaneHeight = 28;
  static const double maxTrackLaneHeight = 160;

  /// [height] held to the legal range — what the splitter's drag and a
  /// saved layout alike may set.
  static double clampTrackLaneHeight(double height) =>
      height.clamp(minTrackLaneHeight, maxTrackLaneHeight).toDouble();

  /// The vertical scrollbar's lane width — the TIMELINE's
  /// [TimelineGridMetrics.verticalScrollbarWidth] by value (UI-R10 #15/#21
  /// unification: same rail, same lane, same column geometry).
  static const double _scrollbarLaneWidth = timelineVerticalScrollbarWidth;

  /// The bottom horizontal scrollbar row's height — the timeline grids'
  /// value (UI-R10 #21 3-row unification).
  static const double _bottomScrollbarRailHeight =
      timelineBottomScrollbarRailHeight;

  /// The header band above the track rows — a `Row` of the seconds corner,
  /// the ruler and [TimelineLayerControlsHeader].
  ///
  /// The LEGEND is what sets it: it is a `Container(height:
  /// metrics.layerRowHeight)` and nothing in the row may exceed it. Since ㉓
  /// the other two take the same number rather than sitting short inside it,
  /// so the band is now one height rather than the tallest of three.
  ///
  /// Where it is shown, that row grows with its words under the OS text
  /// size exactly as the timeline's legend does ([timelineLayerRowHeightIn],
  /// text-scale-rail-rows — 「범례 줄도 같이」).
  static double _headerBandHeightIn(BuildContext context) =>
      timelineLayerRowHeightIn(context);

  /// The shortest this panel is laid out at, ITS OWN chrome only — the host
  /// adds its command bar ([StoryboardTabHost.minPanelHeight]).
  ///
  /// The user's rule (2026-08-02): the body stops at TWO ROWS, where a row
  /// is a track lane at its FLOOR ([minTrackLaneHeight]) — the same 28px
  /// the timeline's layer row is, so both panels stop on the same budget.
  ///
  /// WHAT LANDS in that budget is the project's business, not the floor's:
  /// the default lane is 64 and SE rows are 30, so at the floor the user
  /// gets a scrollable sliver rather than two whole lanes. The number's job
  /// is that the body stays scrollABLE — 56 clears the 32px thumb minimum
  /// with room to travel — and that the chrome above and below it survives.
  /// The bottom scrollbar row is what the user watched disappear.
  static const double minPanelHeight =
      timelineLayerRowHeight +
      2 * minTrackLaneHeight +
      _bottomScrollbarRailHeight;

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

  /// A media-browser row let go on a row's frames — a track's (the V row) or
  /// an SE row's empty cell. The row stands on that frame through
  /// [onRowFramePress] first — a drop LANDS, and landing is standing (T4) —
  /// then hands the drop here. Null leaves the rows refusing the drag, as
  /// the timeline's rows do.
  final StoryboardMediaDrop? onDropMediaAsset;

  /// See [StoryboardMediaDropAccepts]. Null is yes.
  final StoryboardMediaDropAccepts? acceptsMediaAsset;

  /// A media-browser row let go on the RAIL, which names no row and no
  /// frame. Null leaves the rail refusing the drag.
  final void Function(String path)? onDropMediaAssetOnRail;

  /// Whether that file can land on the rail — the chip's answer; null is
  /// yes.
  final bool Function(String path)? acceptsMediaAssetOnRail;

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
  /// edge is the CUT's lead edge, and every trailing edge is its panel's
  /// comma with the cut's length riding the row end (edge unification).
  /// Null hides the grips.
  final StoryboardStripEdgeCallbacks? stripEdges;

  /// Every V row's height — the rail's label row and the strip row read
  /// the same number, because they are two columns of one row.
  final double trackLaneHeight;

  /// The V rows' splitter (유저 2026-09-25: 「슬슬 V트랙 위아래 스플리터
  /// 조절기능 넣자. 썸네일 크게보고싶을때용」): the drag's travel down the
  /// bottom edge of a V row's label, answered with how much of it the height
  /// took ([DockEdgeSplitter.onDragDelta]'s contract — the owner clamps, and
  /// the hand pays back what ran past the edge). The owner holds the ONE
  /// height every V row shares. Null: no splitter.
  final double Function(double delta)? onResizeTrackLanes;

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

  /// D30: pressed on a no-layer cut's CREATE affordance in the strip
  /// slot. The host's gate/dispatch pair is the session's
  /// canAddLayerOfKind/addLayerOfKind (T25). Null = display-only.
  final ValueChanged<CutId>? onCreateStoryboardLayer;

  /// Movie-end drag hooks (UI-R20 #3); null hides the end grip (the line
  /// still shows).
  final StoryboardMovieEndCallbacks? movieEnd;

  /// Frame-axis zoom, owned by the host (the panel header's shared zoom
  /// slider drives it).
  final double pixelsPerFrame;

  /// Conte-sheet time display for the cut totals: frames (`48f`) or
  /// seconds+frames (`2+00`), toggled from the grid's top-left corner.
  final bool showSeconds;

  /// The toggle itself, in the corner over the layer-axis scrollbar (it
  /// used to be a command-bar button shared with the timeline). Null
  /// leaves the corner blank.
  final ValueChanged<bool>? onShowSecondsChanged;

  /// This rail's window size, set by the splitter beside it and persisted
  /// by the workspace. Null = a session-local one of our own.
  final LayerRailExtent? railExtent;

  /// Where the FRAME axis stands, in pixels — kept by the host beside
  /// [railExtent] because it has to outlive this panel (F-143: a fold
  /// remounts it, and the offset that lived here went with it). Null = a
  /// session-local one of our own, as with the rail.
  final ValueNotifier<double>? frameAxisOffset;

  final ProjectFrameRate projectFrameRate;

  /// Track-global frame the playhead line sits on (playback position while
  /// playing, the active cut's playhead otherwise) — a LISTENABLE, the
  /// cursor-layer pattern (W4): only the playhead overlay, the ruler and the
  /// track rows' lane labels (V and S — their keys are the track's)
  /// subscribe, so scrub moves and playback ticks never rebuild the panel's
  /// strips/blocks/rails. Null (or a null value) hides the line.
  final ValueListenable<int?>? playheadFrame;


  /// F-110: WHETHER PLAYBACK IS RUNNING — the playback position, or null
  /// while nothing plays. The gate on the strip turning its page; the frame
  /// it pages to is [playheadFrame]'s, which is already global here.
  final ValueListenable<int?>? playbackFrame;
  /// R5: the session's "bring the selection back into view" tick.
  final ValueListenable<int>? revealSelectionTick;

  /// Repaints the ruler's cached-range (green) bar as the prerender cache
  /// fills; null leaves the bar static per build.
  final Listenable? frameReadySignal;

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
  final bool Function(int globalFrame)? isFrameReady;

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

  /// Twirled-down S rows ([seRowKey]): the row's lanes — the list the
  /// timeline's SE row twirls down ([propertyLanesForRow]). ↩️An enlarged
  /// read-only waveform lane at first, the timeline Audio lane's storyboard
  /// sibling, which is where the name comes from; the lanes are the
  /// timeline's own since F-101.
  final Set<String> expandedSeAudioRows;
  final void Function(Track track, int slot)? onToggleSeRowLane;

  /// Twirled-down V tracks (track id value): the cut-level Transform group
  /// under the track row (V-track full transform, R6 — the AE lanes plus
  /// the cut-fade Opacity strip).
  final Set<String> expandedTransformTracks;
  final void Function(Track track)? onToggleTrackLane;

  /// Twirled-open GROUP HEADERS (AE group collapse, default collapsed): track
  /// id values for the V tracks, [laneGroupKey]s for the S rows — the
  /// timeline's own keys, since an S row's groups are the row's groups
  /// (F-101; ↩️they were [seRowKey]s while the S rows had the Transform group
  /// alone). One set — the key shapes never collide.
  final Set<String> expandedTransformGroups;
  final void Function(String groupKey)? onToggleTransformGroup;

  /// Lane edit hooks for the V track's OWN Transform lanes (R4b): the
  /// host builds callbacks that edit [Track.transformTrack] at GLOBAL
  /// frames (one undo per edit) — no cut needed. The carrier Layer the
  /// substrate hands back is synthetic ([trackTransformLaneCarrierId]);
  /// the closures capture their track. Null = display-only.
  final PropertyLaneEditCallbacks? Function(Track track)? trackLaneEditFor;

  /// The lane range feature's HOST hooks (the timeline's machinery; the
  /// session routes the carrier id onto the track). The panel resolves
  /// geometry and mounts the gesture-level bundle itself (C②'s two-level
  /// shape). Null = no lane selection here.
  final TimelineLaneRangeHooks? laneRange;

  /// Which row the frame-axis verbs act on, and the label press that moves
  /// it (R10 #19's rail half) — the same bundle the timeline's rail takes,
  /// because a property row here is a property row there.
  final TimelineCurrentRowHooks? currentRowHooks;

  /// The row-order drag, for the S rows. The V rows are TRACKS and their
  /// order is the film's compositing order — a different decision, and not
  /// this round's (user, 2026-08-07).
  final TimelineRowDragHooks? rowDragHooks;

  /// A5-3② — the SPAN half of ⑨'s select-then-move, for the S rows.
  ///
  /// [rowDragHooks]'s three selection hooks only ARM a selection (they say
  /// whether this press starts one and where it anchors); growing it as the
  /// pointer crosses rows is this. Null leaves a press selecting the single
  /// row it landed on, which is still the right FIRST phase — but the rail
  /// then cannot select a range, so it is wired wherever the hooks are.
  final void Function(List<TimelineDisplayRow> rows, int rowDelta)?
  onSeRowSelectionSpan;

  /// Lane edit hooks for the S rows' Transform lanes — the lane verbs on
  /// the TRACK's S rows, handed [playheadFrame]'s global frames. Null =
  /// display-only.
  final PropertyLaneEditCallbacks? layerLaneEdit;

  // ⛔`activeCutFrameCursor` and `onSelectFrameIndex` are GONE (F-102,
  // 2026-09-15): the S rows' lane labels were their one reader, and they
  // read and seek [playheadFrame] now — an S row's keys are the track's.
  // The channel rule the cursor carried (「lane labels show the value AT the
  // cursor: subscribe here so a tick rebuilds only these small cells」,
  // #844) is [playheadFrame]'s too.

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

  /// The SE row's speaker, which opens the row's mixer anchored under
  /// itself (R10 R3) — the same door the two timeline rails mount, so the
  /// storyboard rail stops being the one that can only mute.
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  /// Whether that row is soloed (the speaker's accent tint).
  final bool Function(LayerId layerId)? isLayerSoloed;

  final void Function(LayerId layerId, double opacity)? onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  final void Function(LayerId layerId, LayerMarkEdit edit)? onLayerMarkSelected;

  /// B5③ (2026-08-17, ordered twice before): the timeline rows' timesheet
  /// toggle on this rail's rows too — the SAME session verb the timeline
  /// wires, flipping [Layer.onTimesheet].
  final ValueChanged<LayerId>? onToggleLayerTimesheet;

  /// A LIVE read of the sheet flag — see [EditorSessionManager.isLayerOnTimesheet].
  /// The bulk-drag needs it: a captured [Layer] still reads the value the
  /// last frame had, and the sweep would spread the opposite of what the
  /// press just set.
  final bool Function(LayerId layerId)? layerOnTimesheetOf;

  /// A LIVE read of a layer’s own eye — see [layerOnTimesheetOf].
  final bool Function(LayerId layerId)? layerEyeOnOf;

  /// LIVE reads of the two twirl sets, for the same reason as
  /// [layerOnTimesheetOf]: the host mutates them and the new value reaches
  /// this widget only on the next build, which is a frame too late for a
  /// bulk-drag that started on one of those buttons.
  final bool Function(Track track, int slot)? seRowLaneOpenOf;
  final bool Function(Track track)? trackLaneOpenOf;

  final LayerFxState Function(LayerId layerId)? layerFxStateOf;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// The timeline's rail legend over this panel's rail (UI-R5): same
  /// bulk flyouts + master opacity bar, acting on the ACTIVE cut's layers
  /// through the same session hooks. Null renders a display-only legend.
  final LayerLegendCallbacks? legend;

  /// The legend's row filter (R5 #9 — "있는거면 다 달아서 통일").
  ///
  /// Judged FACET BY FACET, not row kind by row kind: a chip hides only
  /// rows that carry the field it reads. An S row is a layer and answers
  /// every chip; a V row carries `fxEnabled` and nothing else, so the fx
  /// chip filters it exactly like a layer while the mark chip leaves it
  /// alone — because a track has no mark, not because it is a track.
  ///
  /// The alternative was to fail the fields a track lacks, and that is not
  /// a filter: any mark would empty the storyboard whatever the mark was.
  final TimelineRowFilter rowFilter;

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

  /// The V row's eye (R9, session view state, scoped to the track's cut at
  /// the playhead): it hides that cut's picture in the playback display.
  /// Null hides the button. The fx switch beside it is the TRACK's — see
  /// [trackFxStateOf].
  final bool Function(CutId cutId)? cutPictureVisibleOf;
  final ValueChanged<CutId>? onToggleCutPictureVisibility;

  /// R9 #21: the V row's TRACK columns — the fx master over the track's
  /// per-cut switches, and the track's static opacity (live-following the
  /// session's drag). Null keeps the columns reserved and empty.
  final LayerFxState Function(Track track)? trackFxStateOf;
  final ValueChanged<Track>? onToggleTrackFx;
  final double Function(Track track)? trackOpacityOf;
  final void Function(Track track, double opacity)? onTrackOpacityChanged;
  final void Function(Track track, double opacity)? onTrackOpacityChangeEnd;

  /// One V-track EFFECT's own bypass, from its lane group header (the twin
  /// of a layer effect's switch). Null leaves the glyph inert.
  final void Function(Track track, EffectId effectId)?
  onToggleTrackEffectEnabled;

  /// One V-track group header's RESET (R5, AE's group Reset) — the lane id
  /// names the group, exactly as the layer surfaces' does.
  final void Function(Track track, String headerLaneId)?
  onResetTrackEffectGroup;

  /// Range selection on the S rows — the cut row's hooks one row up, in
  /// the same track-axis selection. Null keeps the S rows unselectable.
  final StoryboardSeSelectCallbacks? seSelect;

  /// The timeline's comma-drag hooks for the ACTIVE cut's SE blocks (the
  /// session's exposure edge drags are active-cut scoped — other cuts'
  /// blocks select on tap first). Null hides the grips.
  final TimelineCommaDragCallbacks? seCommaDrag;

  /// The S rows' sound edits — the Audio lane's offset slide and fade drags —
  /// the same object the timeline's SE rows take (F-101; ↩️it was the offset
  /// slide alone). Null keeps the lane display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// An S row's group header switch and reset — the timeline's own verbs
  /// (F-101). Null leaves the switch inert and hides the reset.
  final void Function(Layer layer, PropertyLaneRow lane)?
  onToggleLaneGroupEnabled;
  final void Function(Layer layer, PropertyLaneRow lane)? onResetLaneGroup;

  // The TRANSITION row (O.L / F.I / F.O). This panel is the ONE surface that
  // authors it: the row is track-owned and its spans address the global frame
  // axis, so the cut timeline shows the same spans READ-ONLY (user's law —
  // the global track is where transitions are made). Null hooks keep the row
  // display-only here too, which is what a host with no session does.

  /// The vocabulary lookup the marks draw from (id → def), so the row paints
  /// the same wedge/bowtie the cut's direction row does. Null leaves the
  /// spans unmarked.
  final CameraInstructionDef? Function(String instructionId)? transitionDefById;

  /// Where this panel hands its stacked rows to the shell — the ↑/↓ walk and
  /// the flip window read them while the storyboard is the panel being
  /// worked in ([_StoryboardSheet]). Null for a mount nothing walks.
  final StoryboardRowsChannel? rowsChannel;

  /// D26: crossing-fade warning resolver for the AUTHORING row — global
  /// start keys (this axis is where spans really live).
  final String? Function(int spanStartKey)? transitionCrossingTooltip;

  /// The row's edge grips — the timeline's own comma-drag hooks, pointed at
  /// the session's transition writer. Block starts are GLOBAL frames.
  final TimelineCommaDragCallbacks? transitionCommaDrag;

  /// Opens the term dialog (O.L / F.I / F.O …) for the span covering this
  /// GLOBAL frame — also where the span is created and deleted.
  ///
  /// ⛔There is no `onCreateTransition` beside it any more. Creation used to
  /// be a `＋` on the rail with its own enablement resolver; it is the same
  /// verb as editing now (an empty frame creates), so the panel takes ONE
  /// callback and the row grew no second door.
  final void Function(int globalFrame)? onEditTransitionSpan;

  /// B6 (2026-08-17): opens the SE instance dialog for the sound block
  /// covering this GLOBAL frame on [LayerId] — the timeline SE cells'
  /// entrance, reached by the frame blocks' same-cell double tap.
  final void Function(LayerId layerId, int globalFrame)? onEditSeEntry;

  /// The per-S-row view-state key: `<trackId>-<slot>`.
  static String seRowKey(Track track, int slot) => '${track.id.value}-$slot';

  @override
  State<StoryboardPanel> createState() => _StoryboardPanelState();
}

/// What one build of the storyboard body computes once and every stage of
/// the body reads: the layout and its scale, the frame counts, the content
/// width, the rail's window, the playhead listenable, the theme and the
/// strip rows the host handed in.
///
/// A value object rather than nine parameters — the same shape as the
/// workspace's `_WorkspaceFrame` (Round 6, 2026-09-03: `_buildBody` was 574
/// lines and became four named stages plus this).
class _StoryboardBodyFrame {
  const _StoryboardBodyFrame({
    required this.project,
    required this.layoutEntries,
    required this.scale,
    required this.totalFrames,
    required this.renderedFrames,
    required this.contentWidth,
    required this.playheadListenable,
    required this.availableRailWidth,
    required this.railWindowExtent,
    required this.colorScheme,
    required this.trackGlobalStripRowsByTrack,
  });

  final Project project;
  final List<StoryboardTimelineLayoutEntry> layoutEntries;
  final TimelineScale scale;
  final int totalFrames;
  final int renderedFrames;
  final double contentWidth;
  final ValueListenable<int?>? playheadListenable;
  final double? availableRailWidth;
  final double railWindowExtent;
  final ColorScheme colorScheme;
  final List<List<Widget>> trackGlobalStripRowsByTrack;
}
class _StoryboardPanelState extends State<StoryboardPanel> {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.projectFrameRate.countingBase;

  final ScrollController _verticalController = ScrollController();

  /// 🚨Born where the axis stands, not at zero (F-143) — a fold remounts
  /// this panel, and a newborn 0 was read back after layout and recorded as
  /// a scroll over the position the host had kept. The timeline grids'
  /// controllers are born the same way.
  late final ScrollController _horizontalController = ScrollController(
    initialScrollOffset: _horizontalScrollOffset.value,
  );

  /// The fallback rail extent for hosts that keep none of their own.
  LayerRailExtent? _ownedRailExtent;

  // ── the rail rows and lanes: their own object ───────────────────────
  //
  // A collaborator (storyboard/storyboard_rail_rows.dart, a part of this library). The
  // State keeps the entry points its build tree calls.
  late final _StoryboardRailRows _railRows = _StoryboardRailRows(this);

  /// The rail's NATURAL width — what its rows cost laid out in full. The
  /// window never changes it, so every row in this file keeps stating
  /// [StoryboardPanel.railWidthIn] and none of them has to learn about the
  /// splitter.
  double get _naturalRailWidth => StoryboardPanel.railWidthIn(context);

  /// The S, transition and lane rows' heights where the panel is shown —
  /// asked here, once, and handed to every row, so a label and its strip
  /// cannot answer from two contexts ([_storyboardRowHeightsIn]).
  _StoryboardRowHeights get _rowHeights => _storyboardRowHeightsIn(context);

  // ── the horizontal scroll: its own object, in its own file ──────────
  //
  // A collaborator (storyboard/storyboard_scroll.dart, a part of this library). The
  // State keeps the entry points its build tree calls.
  late final _StoryboardScroll _scroll = _StoryboardScroll(this);

  /// The door a collaborator rebuilds through - setState is protected,
  /// and a collaborator is not a subclass.
  void _rebuild(VoidCallback fn) => setState(fn);

  /// The live horizontal offset as a VALUE channel (UI-R15, the
  /// timeline's B1 pattern): scroll pixels update this notifier — the
  /// pinned ruler's translate follows it with zero panel rebuilds. Only
  /// an endless-extent change (growth/shrink) still goes through
  /// setState.
  ///
  /// The host's when it keeps one ([StoryboardPanel.frameAxisOffset]) —
  /// read ONCE, as in the timeline grids.
  late final ValueNotifier<double> _horizontalScrollOffset =
      widget.frameAxisOffset ?? _ownedHorizontalScrollOffset;

  /// The fallback frame-axis offset for hosts that keep none of their own.
  final ValueNotifier<double> _ownedHorizontalScrollOffset =
      ValueNotifier<double>(0);

  /// The QUANTIZED window bucket (UI-R16, shared policy): the ruler
  /// painters' repaint trigger — fires once per span crossing, so the
  /// frames between crossings are pure translation.
  final ValueNotifier<int> _horizontalWindowBucket = ValueNotifier<int>(0);

  /// The frame axis following its controller — the timeline grids'
  /// follower, the same object: the endless trailing room, the activity
  /// watch for its lazy shrink, and the two notifiers above.
  late final TimelineFrameAxisFollower _frameAxis = TimelineFrameAxisFollower(
    controller: _horizontalController,
    frameAxisOffset: _horizontalScrollOffset,
    frameWindowBucket: _horizontalWindowBucket,
    cellExtent: () => _scale.pixelsPerFrame,
    baseFrameCount: () => _restingFramesOf(
      _totalFrames(
        widget.project,
        buildStoryboardTimelineLayout(widget.project),
      ),
    ),
    rebuild: _rebuild,
    isMounted: () => mounted,
  );

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
    _horizontalController.addListener(_frameAxis.handleScroll);
    widget.revealSelectionTick?.addListener(_handleRevealSelection);
    widget.playheadFrame?.addListener(_handlePlaybackPage);
    _bindSheet(widget.rowsChannel);
  }

  /// THE STORYBOARD AS A SHEET, handed to the shell's walkers.
  late final _StoryboardSheet _sheet = _StoryboardSheet(this);

  void _bindSheet(StoryboardRowsChannel? channel) => channel?.bind(
    this,
    rows: _sheet.rows,
    snapshotOf: _sheet.flipHudSnapshot,
  );

  /// R5: the same "bring the selection back into view" tick the timeline
  /// answers, in THIS surface's terms — the strips run on the GLOBAL frame
  /// axis, so the playhead frame is what the reveal aims at.
  ///
  /// After the frame, because the row list this pass built is what any
  /// row-side reveal would count in.
  void _handleRevealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_horizontalController.hasClients) {
        return;
      }
      final frame = widget.playheadFrame?.value;
      final cell = widget.pixelsPerFrame;
      if (frame == null || cell <= 0) {
        return;
      }
      jumpToReveal(
        _horizontalController,
        (
          start: frame * cell,
          extent: cell,
          margin: cell,
        ),
      );
    });
  }

  /// F-110: the strip turns a PAGE when playback carries the playhead out of
  /// the window — 유저 2026-09-12: 「재생시에도 플레이헤드 밖 나갈때
  /// 스크롤하도록 … 넘어가면 룰러가 왼쪽에 오도록 스크롤바 한번만 이동」.
  ///
  /// ⛔THE WALK ABOVE IS A DIFFERENT LAW, not a setting of this one. A
  /// selection walk moves the least it can and keeps a neighbour in sight;
  /// a page stands the playhead at the window's start and does nothing at
  /// all until it leaves. [pageToPlayhead] is the other surfaces' too.
  ///
  /// ⛔And no post-frame hop: the page must land on the frame the tick
  /// carried, and this listener already runs with [playheadFrame] set — the
  /// row list a reveal waits for is not read here.
  void _handlePlaybackPage() {
    final frame = widget.playheadFrame?.value;
    if (widget.playbackFrame?.value == null || frame == null) {
      return;
    }
    pageToPlayhead((
      controller: _horizontalController,
      extent: widget.pixelsPerFrame,
      at: frame,
    ));
  }

  @override
  void didUpdateWidget(covariant StoryboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    rebindListener(
      oldWidget.revealSelectionTick,
      widget.revealSelectionTick,
      _handleRevealSelection,
    );
    rebindListener(
      oldWidget.playheadFrame,
      widget.playheadFrame,
      _handlePlaybackPage,
    );
    if (!identical(oldWidget.rowsChannel, widget.rowsChannel)) {
      oldWidget.rowsChannel?.unbind(this);
      _bindSheet(widget.rowsChannel);
    }
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

  TimelineScale get _scale => TimelineScale(
    pixelsPerFrame: widget.pixelsPerFrame,
    minBlockWidth: StoryboardPanel._minBlockWidth,
  );

  @override
  void dispose() {
    widget.rowsChannel?.unbind(this);
    widget.revealSelectionTick?.removeListener(_handleRevealSelection);
    widget.playheadFrame?.removeListener(_handlePlaybackPage);
    _horizontalController.removeListener(_frameAxis.handleScroll);
    _frameAxis.dispose();
    _verticalController.dispose();
    _horizontalController.dispose();
    // ⛔Only our own — the host's outlives this panel by design.
    _ownedHorizontalScrollOffset.dispose();
    _horizontalWindowBucket.dispose();
    _hoveredCutId.dispose();
    _frameGeometry.dispose();
    _ownedRailExtent?.dispose();
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
  ) => movieEndFramesOver(entries, trailingFrames: project.trailingFrames);

  /// Where the movie ends under [preview]: the end of the project the
  /// BLOCKS are drawn from mid-drag — whichever drag moves it, a cut's or
  /// the end line's own. The strip's line, its grip and the ruler's line
  /// all read this one (F-119).
  int _movieEndUnder(TimelineDragPreview preview) =>
      movieEndFrames(projectWithTimelineDragPreview(widget.project, preview));

  // ── where the storyboard stands: its own object ─────────────────────
  //
  // A collaborator (storyboard/storyboard_standing.dart, a part of this library). The
  // State keeps the entry points its build tree calls.
  late final _StoryboardStanding _standing = _StoryboardStanding(this);

  // `_cutWindowTransformOf` retired with the V row's transform: there is no
  // track lane for a cut window to project.

  /// The group key one V-track EFFECT's lanes twirl under. The V row keeps
  /// its own flat key space (its Transform group is keyed by the bare track
  /// id), so an effect hangs its id off that.
  static String trackEffectGroupKey(Track track, EffectId effectId) =>
      '${track.id.value}-fx-${effectId.value}';

  // ── the rows and their labels: their own object ─────────────────────
  //
  // A collaborator (storyboard/storyboard_rows_and_labels.dart, a part of this library). The
  // State keeps the entry points its build tree calls.
  late final _StoryboardRowsAndLabels _rows = _StoryboardRowsAndLabels(this);

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
      if (layer.kind.hasPictureOpacity) layer.id,
  };

  /// The DISPLAY form of a track SE lane: the in-flight take preview
  /// stands in for the armed lane, by identity (REC1-C).
  Layer? _seDisplayAt(Track track, int slot) {
    final base = _trackSeAt(track, slot);
    final preview = widget.seLanePreview;
    return preview != null && base != null && preview.id == base.id
        ? preview
        : base;
  }

  @override
  Widget build(BuildContext context) {
    // The splitter's value is read at the TOP here and nowhere deeper:
    // the strip viewport's width is the first thing this build derives
    // from it, and the rail rows keep stating their natural width.
    //
    // 🚨D43-2 재개: the grid's ground, stated once above both the overlay
    // and every row that covers it. The storyboard sits on `surface`, not
    // the timeline's container colour — which is exactly why this is
    // inherited rather than guessed at the point of use.
    return TimelineGridLaw(
      ground: Theme.of(context).colorScheme.surface,
      framesPerSecond: _countingFps,
      child: ValueListenableBuilder<double?>(
        valueListenable: _railRows._railExtent,
        builder: (context, _, child) => LayoutBuilder(
          builder: (context, constraints) {
            // Viewport paper fill (UI-R12 #16): the strips run to the
            // viewport's right edge — recorded FIRST so the SE strip rows and
            // the body agree on the rendered extent within one build.
            // What the panel can spare for the rail ([layerRailAvailableExtent]).
            // Recorded so `_buildBody` and every part of the rail read the
            // ONE value.
            _availableRailWidth = layerRailAvailableExtent(
              constraints,
              railAxis: Axis.horizontal,
              scrollbarLaneExtent: StoryboardPanel._scrollbarLaneWidth,
            );
            _stripViewportWidth = constraints.hasBoundedWidth
                ? (constraints.maxWidth -
                          StoryboardPanel._scrollbarLaneWidth -
                          _railRows._railExtent.windowExtent(
                            _naturalRailWidth,
                            availableExtent: _availableRailWidth,
                          ) -
                          LayerRailSplitter.thickness)
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
                  _frameAxis.trailingFrames +
                  _viewportFillFrameCells,
            );
            // SE rows are built OUTSIDE the drag-preview builder from the RAW
            // project (R10-③): their content is track-global, so a cut trim
            // never changes them — handing the per-step rebuild IDENTICAL row
            // instances lets Flutter skip their whole subtrees (waveform
            // painters included). The trade: an in-flight trim doesn't slide
            // their cut-boundary marks until release. SE comma drags edit the
            // ACTIVE layer through the timeline gates, unaffected here.
            final trackGlobalStripRowsByTrack = _railRows._trackGlobalStripRowsByTrack();
            // The body builds from the COMMITTED project, once. The drag
            // preview is read further down, at [_trackGroupSection] — see the
            // measurement in its doc for why the difference is not small.
            return _buildBody(
              context,
              widget.project,
              trackGlobalStripRowsByTrack,
            );
          },
        ),
      ),
    );
  }

  /// Frame cells the strips viewport needs to be fully papered (UI-R12
  /// #16) — recorded by [_buildBody]'s LayoutBuilder. Zero until layout.
  int _viewportFillFrameCells = 0;

  /// The strip column's viewport width — the shared window policy's other
  /// input (UI-R16). Recorded in build beside [_viewportFillFrameCells],
  /// which already derived from it.
  double _stripViewportWidth = 0;

  /// The rail's layout ceiling for this pass (see
  /// [LayerRailExtent.windowExtent]); null in an unbounded host.
  double? _availableRailWidth;

  /// Render extent (UI-R12 #16 contract, unified with the timeline
  /// grids): the cells scrolled/panned into existence PLUS the viewport
  /// fill — the old always-120 resting runway is gone, so past-content
  /// cells vanish once out of view and the scrollbar stops at the built
  /// cells. Only the ruler edge-drag overshoots and grows the extent.
  int _renderedFramesFor(int totalFrames) => math.max(
    _restingFramesOf(totalFrames) + _frameAxis.trailingFrames,
    _viewportFillFrameCells,
  );

  /// The frames the strips' axis RESTS at before its endless room: the
  /// movie's end line and the post-cut allowance past it — asked of the one
  /// policy the timeline grids ask, so the scrollbar's far end shows the
  /// line on every surface that draws one (F-174).
  int _restingFramesOf(int totalFrames) =>
      TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: totalFrames,
        minimumVisibleFrameCells: 0,
      ).visibleFrameCount;

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
    List<List<Widget>> trackGlobalStripRowsByTrack,
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
    final availableRailWidth = _availableRailWidth;
    final railWindowExtent = _railRows._railExtent.windowExtent(
      _naturalRailWidth,
      availableExtent: availableRailWidth,
    );
    final frame = _StoryboardBodyFrame(
      project: project,
      layoutEntries: layoutEntries,
      scale: scale,
      totalFrames: totalFrames,
      renderedFrames: renderedFrames,
      contentWidth: contentWidth,
      playheadListenable: playheadListenable,
      availableRailWidth: availableRailWidth,
      railWindowExtent: railWindowExtent,
      colorScheme: colorScheme,
      trackGlobalStripRowsByTrack: trackGlobalStripRowsByTrack,
    );
    return ColoredBox(
      key: const ValueKey<String>('storyboard-panel'),
      color: colorScheme.surface,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PINNED RULER: the frame ruler sits ABOVE the vertical scroll
              // area (the timeline's sticky-header pattern) so it stays put
              // while tracks and SE rows scroll under it; it follows the
              // horizontal scroll by translation.
              _pinnedRulerRow(frame),
              _scrollArea(frame),
              // BOTTOM row of the 3-row structure (UI-R10 #21): blank
              // corners under the rail and the scrollbar lane, then the
              // PINNED horizontal scrollbar (it used to live inside the
              // vertical scroll content and scrolled away with it).
              _bottomScrollbarRow(frame),
            ],
          ),
          // The grip floats over the 5px slot the three rows reserve, so
          // one grab spans the legend, the rows and the scrollbar line.
          _railGrip(frame),
        ],
      ),
    );
  }

  Positioned _railGrip(_StoryboardBodyFrame frame) {
    return Positioned(
      left: StoryboardPanel._scrollbarLaneWidth + frame.railWindowExtent,
      top: 0,
      bottom: 0,
      width: LayerRailSplitter.thickness,
      child: LayerRailSplitter(
        key: const ValueKey<String>('storyboard-rail-splitter'),
        axis: Axis.horizontal,
        extent: _railRows._railExtent,
        naturalExtent: _naturalRailWidth,
        availableExtent: frame.availableRailWidth,
      ),
    );
  }

  Row _bottomScrollbarRow(_StoryboardBodyFrame frame) {
    return Row(
      children: [
        const SizedBox(
          key: ValueKey<String>(
            'storyboard-bottom-scrollbar-left-spacer',
          ),
          width: StoryboardPanel._scrollbarLaneWidth,
          height: StoryboardPanel._bottomScrollbarRailHeight,
        ),
        // The rail's own bar — the panel's second of three.
        LayerRailScrollbar(
          axis: Axis.horizontal,
          rail: _railRows._railExtent,
          naturalExtent: _naturalRailWidth,
          availableExtent: frame.availableRailWidth,
          laneExtent: StoryboardPanel._bottomScrollbarRailHeight,
          keyPrefix: 'storyboard',
        ),
        const SizedBox(
          width: LayerRailSplitter.thickness,
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
                contentWidth: frame.contentWidth,
                height: StoryboardPanel._bottomScrollbarRailHeight,
              );
            },
          ),
        ),
      ],
    );
  }

  Expanded _scrollArea(_StoryboardBodyFrame frame) {
    final playheadListenable = frame.playheadListenable;
    return Expanded(
      child: LayoutBuilder(
        builder: (context, middleConstraints) {
          final middleViewportHeight =
              middleConstraints.hasBoundedHeight
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
                  child: DeviceGridScrollBody(
                    controller: _verticalController,
                    axisDirection: AxisDirection.down,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reserves the left EDGE column the layer-axis
                        // scrollbar floats over.
                        const SizedBox(
                          width: StoryboardPanel._scrollbarLaneWidth,
                        ),
                        // Sections live INSIDE the rows now (UI-R5): the
                        // first S row and the V row carry inline tags — no
                        // bracket gutter beside the rail.
                        LayerRailWindow(
                          axis: Axis.horizontal,
                          rail: _railRows._railExtent,
                          naturalExtent: _naturalRailWidth,
                          availableExtent: frame.availableRailWidth,
                          child: SizedBox(
                            key: const ValueKey<String>(
                              'storyboard-track-label-rail',
                            ),
                            width: _naturalRailWidth,
                            // 🚨The rail's Krita-style column
                            // swipe, the SAME one the timeline
                            // rail wears (유저 2026-08-29: 「타임
                            // 라인이랑 왜 통일안한거지?」). It was
                            // the timeline's private state until
                            // the reason for that was measured and
                            // found invented — see
                            // [RailSwipeColumnPointer].
                            child: Stack(
                              children: [
                                RailColumnSwipe<StoryboardRailRow>(
                                  axis: Axis.vertical,
                                  columns: _railRows._railSwipeColumns(),
                                  rowsIn: _railRows.railRowsIn,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Track groups in TIMELINE order (R6 B3): the
                                      // S rows sit ABOVE their V track, slots
                                      // bottom-up like the timeline (top-down
                                      // S2, S1, V — R7-④).
                                      for (
                                        var index = 0;
                                        index < frame.project.tracks.length;
                                        index++
                                      )
                                        ..._railRows.railRowsForTrack(
                                          frame.project.tracks[index],
                                          index,
                                        ),
                                    ],
                                  ),
                                ),
                                // A pool file let go on the rail: the layer
                                // area's law — a sound by the SE rows' rule, a
                                // picture nowhere (no row of the cut's stack is
                                // on this rail). Last, a permanent slot that
                                // takes no pointer until a drag is in flight.
                                if (widget.onDropMediaAssetOnRail
                                    case final onDrop?)
                                  Positioned.fill(
                                    child: MediaAssetDropTarget(
                                      key: const ValueKey<String>(
                                        'storyboard-rail-placement-entrance',
                                      ),
                                      accepts: (data, _) =>
                                          widget.acceptsMediaAssetOnRail?.call(
                                            data.path,
                                          ) ??
                                          true,
                                      onDrop: (data, _) => onDrop(data.path),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Reserves the gap the rail splitter floats over.
                        const SizedBox(
                          width: LayerRailSplitter.thickness,
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
                              child: DeviceGridScrollBody(
                                controller: _horizontalController,
                                axisDirection: AxisDirection.right,
                                child: Stack(
                                  children: [
                                    // THE grid sheet under the rows (D8/D38
                                    // — the storyboard's own copy of the
                                    // lines had drifted: pre-split beat
                                    // color, base+beat double ink at 6f, a
                                    // line at x=0, no snap; deleted, never
                                    // reconciled). I-44: the lanes' ground
                                    // and every row seam are the sheet's
                                    // too, off the rail's own row table.
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: RepaintBoundary(
                                          child: Builder(
                                            builder: (context) {
                                              final ground =
                                                  TimelineGridLaw.maybeOf(
                                                    context,
                                                  )?.ground;
                                              return TimelineGridSheet(
                                                key: const ValueKey<String>(
                                                  'storyboard-grid-sheet',
                                                ),
                                                frameCellExtent: frame
                                                    .scale
                                                    .pixelsPerFrame,
                                                rows: ground == null
                                                    ? TimelineGridRows.none
                                                    : _railRows.gridRows(
                                                        frame.project.tracks,
                                                        ground,
                                                      ),
                                              );
                                            },
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
                                          SizedBox(
                                            width: frame.contentWidth,
                                          ),
                                          // Track groups in TIMELINE order (R6
                                          // B3), mirroring the rail exactly —
                                          // row for row, height for height.
                                          for (
                                            var index = 0;
                                            index <
                                                frame.project.tracks.length;
                                            index++
                                          )
                                            _railRows.trackGroupSection(
                                              frame.project.tracks[index],
                                              index,
                                              frame.layoutEntries
                                                  .where(
                                                    (entry) =>
                                                        entry
                                                            .trackIndex ==
                                                        index,
                                                  )
                                                  .toList(
                                                    growable: false,
                                                  ),
                                              frame.contentWidth,
                                              frame.scale,
                                              index <
                                                      frame.trackGlobalStripRowsByTrack
                                                          .length
                                                  ? frame.trackGlobalStripRowsByTrack[index]
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
                                        valueListenable:
                                            playheadListenable,
                                        builder:
                                            (
                                              context,
                                              playheadFrame,
                                              _,
                                            ) => playheadFrame == null
                                            ? const SizedBox.shrink()
                                            : Positioned(
                                                key:
                                                    const ValueKey<
                                                      String
                                                    >(
                                                      'storyboard-playhead',
                                                    ),
                                                left: frame.scale
                                                    .leftForFrame(
                                                      playheadFrame,
                                                    ),
                                                top: 0,
                                                bottom: 0,
                                                width: frame.scale
                                                    .pixelsPerFrame,
                                                child: IgnorePointer(
                                                  child: ColoredBox(
                                                    color: timelinePlayheadColor
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
                                    // 🚨F-18: the line and its grip
                                    // follow the DRAG, not the
                                    // committed project. The body
                                    // around them still builds
                                    // committed-once on purpose —
                                    // only these two read the
                                    // preview, so nothing else
                                    // rebuilds per step.
                                    if (frame.totalFrames > 0)
                                      ValueListenableBuilder<
                                        TimelineDragPreview?
                                      >(
                                        valueListenable:
                                            widget.dragPreview ??
                                            _noDragPreview,
                                        builder: (context, preview, _) {
                                          final live =
                                              timelineCutEndPreviewFrameCount(
                                                preview: preview,
                                                cutId: null,
                                                playbackFrameCount:
                                                    frame.totalFrames,
                                                movieEndUnder: _movieEndUnder,
                                              );
                                          return Positioned(
                                            key: const ValueKey<String>(
                                              'storyboard-cut-end-line',
                                            ),
                                            left: frame.scale.leftForFrame(
                                              live,
                                            ),
                                            top: 0,
                                            bottom: 0,
                                            width: 2,
                                            child:
                                                const IgnorePointer(
                                                  child: ColoredBox(
                                                    color: AppColors
                                                        .danger,
                                                  ),
                                                ),
                                          );
                                        },
                                      ),
                                    if (frame.totalFrames > 0 &&
                                        widget.movieEnd != null)
                                      _StoryboardEndLineHandle(
                                        dragPreview:
                                            widget.dragPreview,
                                        committedTotalFrames:
                                            frame.totalFrames,
                                        movieEndUnder: _movieEndUnder,
                                        scale: frame.scale,
                                        // Grabbed from the EMPTY side of
                                        // the line, never straddling it:
                                        // everything left of the movie's
                                        // end belongs to the content, and
                                        // the last cut's trailing edge
                                        // grip is right there. Centring
                                        // the handle put a full-height
                                        // opaque box over that grip and
                                        // made it unreachable.
                                        pixelsPerFrame:
                                            frame.scale.pixelsPerFrame,
                                        movieEnd: widget.movieEnd!,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // The layer-axis bar moved off the rail's right edge
              // and onto the panel's left one — the gap it used to
              // fill is the splitter's now.
              Positioned(
                left: 0,
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
    );
  }

  Row _pinnedRulerRow(_StoryboardBodyFrame frame) {
    final bandHeight = StoryboardPanel._rulerHeightIn(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The corner above the layer-axis scrollbar: the seconds
        // toggle, moved off the command bar (rail-window round).
        TimelineSecondsToggleCorner(
          key: const ValueKey<String>(
            'storyboard-time-display-toggle-button',
          ),
          width: StoryboardPanel._scrollbarLaneWidth,
          height: bandHeight,
          showSeconds: widget.showSeconds,
          onChanged: widget.onShowSecondsChanged,
        ),
        // The timeline's legend header over the rail (UI-R5
        // storyboard unification): same slots, same flyouts —
        // and now inside the rail's own window, so the legend is
        // cut exactly where the rows below it are.
        LayerRailWindow(
          axis: Axis.horizontal,
          rail: _railRows._railExtent,
          naturalExtent: _naturalRailWidth,
          availableExtent: frame.availableRailWidth,
          child: SizedBox(
            width: _naturalRailWidth,
            child: TimelineLayerControlsHeader(
              // The storyboard rail states its OWN width, which
              // today is the same number as the timeline's and is
              // deliberately not the same constant (see
              // [StoryboardPanel.railWidthIn]). Widening it
              // adds no column here — `hasBlendColumn` is a host
              // answer, not something derived from the width — so
              // the extra width lands in the NAME, which is where
              // a track wants it.
              //
              // The legend's columns are this rail's rows' columns, and
              // its extent the rail's, as the rows lay them out
              // (text-scale-rail-columns). Its row is the band's — the
              // band grew with its words and the legend inside it must
              // too, or its OPAC is cut at the foot
              // (text-scale-storyboard-rows).
              metrics: TimelineGridMetrics.defaults.copyWith(
                layerControlsWidth: _naturalRailWidth,
                layerRowHeight: StoryboardPanel._headerBandHeightIn(context),
                railColumns: layerRailColumnWidthsIn(context),
              ),
              legend: widget.legend,
              rowFilter: widget.rowFilter,
              showRowSolos: true,
              marksInUse: _legendMarksInUse(),
              kindsInUse: _legendKindsInUse(),
              visibilitySoloEnabled: widget.visibilitySoloEnabled,
              allSeMuted: _legendAllSeMuted(),
              displayedLayerIds: widget.legend == null
                  ? null
                  : _legendDisplayedLayerIds,
              displayedOpacity: widget.legendOpacityValue,
              // ㉒: the lane column's header verb, same as the
              // timeline's.
              anyLanesExpanded: _railRows._anyLanesExpanded,
              onExpandAllLanes: _railRows.hasLaneTwirls
                  ? _railRows.expandAllLanes
                  : null,
              onCollapseAllLanes: _railRows.hasLaneTwirls
                  ? _railRows.collapseAllLanes
                  : null,
            ),
          ),
        ),
        const SizedBox(width: LayerRailSplitter.thickness),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : frame.contentWidth;
              _frameAxis.rereadAfterLayout();
              return SizedBox(
                height: bandHeight,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: frame.contentWidth,
                    maxWidth: frame.contentWidth,
                    minHeight: bandHeight,
                    maxHeight: bandHeight,
                    // UI-R15: scroll moves ONLY this translate — the
                    // ruler strip itself builds once (full bounds)
                    // and its painters window off the live offset.
                    //
                    // 🚨★★★F-32, the THIRD grid with this exact
                    // shape: the cells below sit inside
                    // `DeviceGridScrollBody` (which cancels the
                    // scroll offset's sub-device-pixel fraction)
                    // and this ruler translated raw, so it kept
                    // the fraction they had cancelled.
                    //
                    // 🧪Measured at ratio 1.5, offset 1.5: ruler
                    // 453.5 vs cells 453.667 — the same numbers
                    // the horizontal timeline gave.
                    //
                    // ↩️F-95: the translate read a NOTIFIER that a
                    // resize past the end never reached; the
                    // follower reads the position when it paints.
                    child: ScrollFollower(
                      controller: _horizontalController,
                      axisDirection: AxisDirection.right,
                      child: _StoryboardRuler(
                        width: frame.contentWidth,
                        renderedFrames: frame.renderedFrames,
                        contentFrames: frame.totalFrames,
                        movieEndUnder: _movieEndUnder,
                        dragPreview: widget.dragPreview,
                        playhead: frame.playheadListenable,
                        frameReadySignal: widget.frameReadySignal,
                        viewportOffset: _horizontalScrollOffset,
                        windowBucket: _horizontalWindowBucket,
                        viewportWidth: viewportWidth,
                        timelineScale: frame.scale,
                        onSeekGlobalFrame: widget.onSeekGlobalFrame,
                        onScrubGlobalFrame: widget.onScrubGlobalFrame,
                        onScrubEnd: widget.onScrubEnd,
                        isFrameReady: widget.isFrameReady,
                        onEdgeAutoPan: _scroll.autoPanRulerEdge,
                        framesPerSecond: _countingFps,
                        showSeconds: widget.showSeconds,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
    required this.movieEndUnder,
    this.dragPreview,
    required this.playhead,
    required this.frameReadySignal,
    required this.viewportOffset,
    required this.windowBucket,
    required this.viewportWidth,
    required this.timelineScale,
    required this.onSeekGlobalFrame,
    required this.onScrubGlobalFrame,
    required this.onScrubEnd,
    required this.isFrameReady,
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

  /// Where the movie ends under a drag — the panel's one reading, which the
  /// strip's line and grip read too (F-18, F-119).
  final int Function(TimelineDragPreview preview) movieEndUnder;

  /// The panel's drag channel; null keeps the ruler's end line committed.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// The playhead + cache-warm signals, consumed by the cursor overlay
  /// PAINTER only (R12-B): a playback tick or a warming frame repaints
  /// one thin layer — the header cells never rebuild. At storyboard zoom
  /// there are far more of them than in the timeline, which is exactly
  /// why the old rebuild-per-tick ruler showed up as fixed frame drops.
  final ValueListenable<int?>? playhead;
  final Listenable? frameReadySignal;

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

  final bool Function(int globalFrame)? isFrameReady;

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
  final FrameScrubDedupe _scrubbedFrame = FrameScrubDedupe();

  void _resetScrubTracking() => _scrubbedFrame.reset();

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
    final frame = _scrubbedFrame.next(
      frameIndexFromLocalX(
        localX: localX,
        horizontalScrollOffset: widget.viewportOffset.value,
        frameCellWidth: widget.timelineScale.pixelsPerFrame,
        visibleFrameCount: widget.renderedFrames,
      ),
    );
    if (frame == null) {
      return;
    }
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
      layerRowHeight: StoryboardPanel._rulerHeightIn(context),
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
          height: StoryboardPanel._rulerHeightIn(context),
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
                playhead: widget.playhead,
                playbackFrameCount: widget.contentFrames,
                // F-18: the ruler's end line follows the drag with the
                // strip's line and grip — the same reader (F-119: every drag
                // that moves the movie's end, not the end line's alone).
                dragPreview: widget.dragPreview,
                movieEndUnder: widget.movieEndUnder,
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
              // ready bar, one thin isolated layer. Shared with the
              // timeline ruler, which needs the very same split.
              Positioned.fill(
                child: TimelineRulerCursorOverlay(
                  keyValue: 'storyboard-ruler-cursor-overlay',
                  playhead: widget.playhead,
                  repaintSignal: widget.frameReadySignal,
                  windowBucket: widget.windowBucket,
                  viewportMainExtent: widget.viewportWidth,
                  renderedFrames: widget.renderedFrames,
                  cellWidth: cellWidth,
                  isFrameReady: widget.isFrameReady,
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

/// The transition row's height. Same regulation as an S row — the transition
/// row is the timesheet's CAMERA column on this axis, and the two must line
/// up with the rail's own row pitch.
const double _transitionRowHeight = 30;

/// A twirled-down lane's height — every lane, the Audio lane included: the
/// timeline draws all its rows at one height, and the labels and the strips
/// share it (the rail and strips columns must stay height-synced).
/// ↩️The Audio lane stood taller as an enlarged waveform strip until F-101
/// made it the timeline's own lane; the cut-fade envelope's own height went
/// with that row before.
const double _laneHeight = 26;

/// The three rows above as they stand where the panel is shown — each the
/// height it was drawn at plus as much as a row's name grew under the OS
/// text size ([timelineLayerRowGrowthIn]), 0 at 1×.
///
/// 🚨text-scale-storyboard-rows (유저 2026-09-24, 「행도 글자 크기를 따라
/// 자란다」). The rows round grew the timeline's rows and this panel's legend
/// band, and not these three: at 2× an S row's name wanted 40 in its 29.
/// ⛔Everything that lays a row out reads THIS, never the constants — the
/// rail's labels, the strips beside them, and the one table the bands, the
/// sheet and the select-drag read. Two of them on different numbers is a
/// label and its strip parting ways.
typedef _StoryboardRowHeights = ({double se, double transition, double lane});

_StoryboardRowHeights _storyboardRowHeightsIn(BuildContext context) {
  final growth = timelineLayerRowGrowthIn(context);
  return (
    se: _seRowHeight + growth,
    transition: _transitionRowHeight + growth,
    lane: _laneHeight + growth,
  );
}

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
  // The controls belong to the ROW, and the row belongs to the track. A
  // gap kept them up already (UI-R10 #12, "the SE rows are TRACK-owned");
  // the active cut living on ANOTHER track is the same statement, so it
  // gets the same answer (user, 2026-08-09).
  return _trackSeAt(track, slot);
}

/// SE slot rows in the rail: the same bordered-row language as the track
/// row above them, compact like the timeline's SE rows — with the timeline
/// rows' controls and a lane chevron (twirl-down waveform strip).
/// The chrome every storyboard rail label sits in: the select target, the
/// fixed-width cell with its border and active tint, and the row's
/// semantics node.
///
/// 🚨ONE shell for the SE label, the transition label and the track label
/// row — three hand-copied heads (the audit's clone scan, 2026-09-03).
/// [chromeless] is the track row's own switch: a lane strip under it
/// draws no border and no tint.
class _StoryboardLabelShell extends StatelessWidget {
  const _StoryboardLabelShell({
    required this.selectKey,
    this.rowKey,
    required this.onTap,
    required this.height,
    required this.active,
    this.chromeless = false,
    required this.semanticsLabel,
    required this.child,
  });

  final Key selectKey;
  final Key? rowKey;
  final VoidCallback? onTap;
  final double height;
  final bool active;
  final bool chromeless;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      // The row BODY, not a control: 'storyboard-se-label-',
      // 'storyboard-transition-label-' and 'storyboard-track-select-' are
      // decided in every_button_claims_its_press_test (a drag from here is
      // the row's reorder, not a scroll).
      key: selectKey,
      onTap: onTap,
      child: Container(
        key: rowKey,
        width: StoryboardPanel.railWidthIn(context),
        height: height,
        padding: const EdgeInsets.only(right: 8),
        decoration: chromeless
            ? null
            : BoxDecoration(
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
          key: active
              ? const ValueKey<String>('storyboard-selected-row')
              : null,
          label: semanticsLabel,
          container: true,
          explicitChildNodes: true,
          child: child,
        ),
      ),
    );
  }
}

/// A storyboard label row's NAME: the one row-name style every surface
/// wears ([layerRowNameStyle], F-26 #1226 — 「스토리보드패널도 겸사겸사 싹 다
/// 폰트 통일」), the colour this row's own. Selection reads by COLOR only
/// (user rule). The SE and transition rows each hand-typed a `fontSize:
/// 11` here until the round-8 audit (2026-09-06).
Widget _storyboardRowName(
  BuildContext context,
  String name, {
  required bool active,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Text(
    name,
    overflow: TextOverflow.ellipsis,
    style: layerRowNameStyle(context).copyWith(
      color: active ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
    ),
  );
}

class _StoryboardSeLabel extends StatelessWidget {
  const _StoryboardSeLabel({
    required this.track,
    required this.slot,
    required this.height,
    this.laneExpanded = false,
    this.onToggleLane,
    this.activeLayer,
    this.active = false,
    this.onSelectLayer,
    this.onToggleLayerVisibility,
    this.onOpenLayerMixer,
    this.isLayerSoloed,
    this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.onLayerMarkSelected,
    this.onToggleLayerTimesheet,
    this.layerFxStateOf,
    this.onToggleLayerFx,
    this.opacityDragPreview,
  });

  final Track track;
  final int slot;

  /// The row's height where the panel is shown ([_StoryboardRowHeights.se]).
  final double height;

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

  /// The SE row's speaker, which opens the row's mixer anchored under
  /// itself (R10 R3) — the same door the two timeline rails mount, so the
  /// storyboard rail stops being the one that can only mute.
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  /// Whether that row is soloed (the speaker's accent tint).
  final bool Function(LayerId layerId)? isLayerSoloed;

  final void Function(LayerId layerId, double opacity)? onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  final void Function(LayerId layerId, LayerMarkEdit edit)? onLayerMarkSelected;

  /// B5③: the timeline rows' sheet toggle, on this rail too.
  final ValueChanged<LayerId>? onToggleLayerTimesheet;

  final LayerFxState Function(LayerId layerId)? layerFxStateOf;
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
    return _StoryboardLabelShell(
      selectKey: ValueKey<String>(
        'storyboard-se-label-${track.id.value}-${slot + 1}',
      ),
      onTap: trackLayer == null || onSelect == null
          ? null
          : () => onSelect(trackLayer.id),
      height: height,
      active: active,
      semanticsLabel: active
          ? AppText.strings.semSelectedLayer
          : AppText.strings.semLayer,
      child: Row(
            children: [
              // The rail's shared column skeleton (R9 #22) — this row used
              // to hand-list its slots and put the kind icon INSIDE the
              // name area, so its name started 6px early.
              ...layerRailLeadingCells(
                // The timeline rows' lane chevron, storyboard-prefixed.
                laneToggle: onToggleLane == null
                    ? null
                    : RailSwipeColumnPointer(
                        onPressed: onToggleLane,
                        child: InkWell(
                          key: ValueKey<String>(
                            'storyboard-se-lane-toggle-'
                            '${track.id.value}-${slot + 1}',
                          ),
                          // ⛔A NO-OP: the press already fired it (onPressDown
                          // above). Both would fire twice.
                          onTap: () {},
                          child: SizedBox(
                            height: height,
                            child: Icon(
                              laneExpanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                // B5③ (2026-08-17, superseding UI-R9 #5's empty slot —
                // ordered twice): the timeline rows' sheet toggle, same
                // widget, same kind gate, same session verb. The flag is a
                // LAYER field ([Layer.onTimesheet]) and this row's layer is
                // track-owned, so the toggle needs no cut to act.
                timesheet: layer == null || onToggleLayerTimesheet == null
                    ? null
                    : layerRailTimesheetCell(
                        keyPrefix: 'storyboard',
                        layer: layer,
                        onToggle: onToggleLayerTimesheet!,
                      ),
                mark: layer != null && onLayerMarkSelected != null
                    ? LayerMarkChip.forLayer(
                        layer,
                        keyPrefix: 'storyboard',
                        onMarkSelected: onLayerMarkSelected!,
                      )
                    : null,
                typeButton: LayerTypeButton(
                  keyPrefix: 'storyboard',
                  idValue: '${track.id.value}-s${slot + 1}',
                  kind: LayerKind.se,
                  height: height,
                  onTap: trackLayer == null || onSelect == null
                      ? null
                      : () => onSelect(trackLayer.id),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _storyboardRowName(
                    context,
                    // The TRACK layer's stored name — the same label the
                    // timeline row shows (W3 ordering unification).
                    trackLayer?.name ?? 'S${slot + 1}',
                    active: active,
                  ),
                ),
              ),
              ...layerRailTrailingCells(
                columns: layerRailColumnWidthsIn(context),
                // NO waveform-hide eye (UI-R7 #8): the timeline rows carry
                // none either — the twirled-down Audio lane is the "big
                // waveform" view. The fill-reference slot stays reserved so
                // the trailing columns align.
                fx:
                    layer != null &&
                        onToggleLayerFx != null &&
                        layerKindShowsFxToggle(layer.kind)
                    ? RailSwipeColumnPointer(
                        child: FxToggleButton(
                          keyValue: 'storyboard-layer-fx-${layer.id}',
                          state:
                              layerFxStateOf?.call(layer.id) ?? LayerFxState.on,
                          onToggle: () => onToggleLayerFx!(layer.id),
                        ),
                      )
                    : null,
                visibility: layer != null && onToggleLayerVisibility != null
                    ? RailSwipeColumnPointer(
                        child: LayerVisibilityToggleButton(
                          keyValue: 'storyboard-layer-visibility-${layer.id}',
                          isVisible: layer.isVisible,
                          onToggle: () => onToggleLayerVisibility!(layer.id),
                        ),
                      )
                    : null,
                mute: layer != null && onOpenLayerMixer != null
                    ? SizedBox(
                        height: 26,
                        child: LayerMuteToggleButton(
                          keyValue: 'storyboard-layer-mute-${layer.id}',
                          muted: layer.muted,
                          soloed: isLayerSoloed?.call(layer.id) ?? false,
                          onOpenMixer: (anchorContext) =>
                              onOpenLayerMixer!(anchorContext, layer.id),
                        ),
                      )
                    : null,
                opacity: layer != null && onLayerOpacityChanged != null
                    ? _opacityField(layer)
                    : null,
              ),
            ],
          ),
    );
  }

  /// The row's opacity slider, live-following the session's drag preview
  /// when it targets this layer (the master bar sweep, UI-R6 #2).
  Widget _opacityField(Layer layer) => layerOpacityField(
    layer: layer,
    keyPrefix: 'storyboard',
    dragPreview: opacityDragPreview,
    onChanged: onLayerOpacityChanged!,
    onChangeEnd: onLayerOpacityChangeEnd,
  );
}

/// The TRANSITION row's rail label — the track's O.L / F.I / F.O row.
///
/// The rail's shared column skeleton, like every other row — and the
/// timeline row's three controls with it (B5③ 2026-08-17, ordered twice):
/// the sheet toggle (the kind is eligible — it prints), the mark chip (⑲:
/// the strip's blocks are painted in the mark colour, so the chip IS this
/// row's color label), and the eye, whose subject is the layer's COMPOSITE
/// CONTRIBUTION — a hidden transition row stops feeding its fades to
/// playback ([EditorSessionManager.transitionSpansOfTrack]). fx/opacity
/// stay absent by KIND, the same [layerKindShowsFxToggle]/
/// [layerKindShowsOpacityControl] answers the timeline row reads.
///
/// ⛔It carries **no verb of its own** either. It used to hold a `＋` reading
/// "make one at the playhead", and that button is what the user was pointing
/// at (2026-08-11): 「프레임생성하는거 행에 버튼만들어서 넣은거같은데, 그게아니라
/// 인스턴스편집버튼으로 작동하도록. 삭제나 그런거 다 똑같이」. Create, edit and
/// delete are one verb now — [editTransitionSpanInstance], reached from the
/// frame pill's Edit Instance and from the row's double-tap — so a second
/// entrance on the rail is the predecessor, not a convenience.
class _StoryboardTransitionLabel extends StatelessWidget {
  const _StoryboardTransitionLabel({
    required this.track,
    required this.layer,
    required this.active,
    required this.height,
    this.onSelectLayer,
    this.onToggleLayerVisibility,
    this.onLayerMarkSelected,
    this.onToggleLayerTimesheet,
  });

  final Track track;
  final Layer layer;

  /// Whether this row is THE selected row (same highlight as every other).
  final bool active;

  /// The row's height where the panel is shown
  /// ([_StoryboardRowHeights.transition]).
  final double height;
  final ValueChanged<LayerId>? onSelectLayer;

  /// B5③: the timeline row's three controls, same verbs (see class doc).
  final ValueChanged<LayerId>? onToggleLayerVisibility;
  final void Function(LayerId layerId, LayerMarkEdit edit)? onLayerMarkSelected;
  final ValueChanged<LayerId>? onToggleLayerTimesheet;

  @override
  Widget build(BuildContext context) {
    final onSelect = onSelectLayer;
    return _StoryboardLabelShell(
      selectKey: ValueKey<String>(
        'storyboard-transition-label-${track.id.value}',
      ),
      onTap: onSelect == null ? null : () => onSelect(layer.id),
      height: height,
      active: active,
      semanticsLabel: active
          ? AppText.strings.semSelectedLayer
          : AppText.strings.semLayer,
      child: Row(
            children: [
              ...layerRailLeadingCells(
                // B5③: the timeline row's sheet toggle and mark chip in
                // their shared slots — same widgets, same gates.
                timesheet: onToggleLayerTimesheet == null
                    ? null
                    : layerRailTimesheetCell(
                        keyPrefix: 'storyboard',
                        layer: layer,
                        onToggle: onToggleLayerTimesheet!,
                      ),
                mark: onLayerMarkSelected != null
                    ? LayerMarkChip.forLayer(
                        layer,
                        keyPrefix: 'storyboard',
                        onMarkSelected: onLayerMarkSelected!,
                      )
                    : null,
                typeButton: LayerTypeButton(
                  keyPrefix: 'storyboard',
                  idValue: '${track.id.value}-transition',
                  kind: LayerKind.transition,
                  height: height,
                  onTap: onSelect == null ? null : () => onSelect(layer.id),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _storyboardRowName(
                    context,
                    layer.name,
                    active: active,
                  ),
                ),
              ),
              ...layerRailTrailingCells(
                columns: layerRailColumnWidthsIn(context),
                // The eye: include/exclude this row's composite
                // contribution (B5③ — 「비지블 = 해당 합성 반영/미반영」).
                // fx and opacity stay kind-gated off, exactly like the
                // timeline row's slots for this kind.
                visibility: onToggleLayerVisibility != null
                    ? RailSwipeColumnPointer(
                        child: LayerVisibilityToggleButton(
                          keyValue: 'storyboard-layer-visibility-${layer.id}',
                          isVisible: layer.isVisible,
                          onToggle: () => onToggleLayerVisibility!(layer.id),
                        ),
                      )
                    : null,
              ),
            ],
          ),
    );
  }
}

/// The TRACK-owned TRANSITION row on the global frame axis: the O.L / F.I /
/// F.O spans exactly as stored, marks and grips included.
///
/// This is the surface that AUTHORS them. The cut timeline shows the same
/// spans projected onto each participating cut and read-only, which is why
/// the two surfaces state a span's position differently on purpose — here it
/// straddles the cut boundary it fires across; there each cut sees the whole
/// mark on its own side.
///
/// Everything drawn here is the direction row's own machinery: the paper
/// span, [timelineRowInstructionOverlays] for the marks and
/// [TimelineBlockEdgeGrip] for the edges. Nothing about a mark is re-drawn
/// for this row.
/// Whether the live [selection] covers [row] at [frame] — the storyboard's
/// one range test, for the SE row, the transition row and the cut row
/// (the audit's clone scan, 2026-09-03).
bool _storyboardRangeCovers(
  TrackFrameRangeSelection? selection,
  TimelineRowAddress row,
  int frame,
) =>
    selection != null && selection.coversRow(row) && selection.contains(frame);

/// A storyboard row's press layer: a tap seeks the pressed frame through
/// [onRowFramePress], a double-tap hands the frame to [onEdit].
///
/// 🚨ONE layer for the SE row and the transition row (the audit's clone
/// scan, 2026-09-03). 🚨★★★I-9: same as the transition strip one class
/// up — the coverage question belongs to the host's fork, not to a copy
/// here.
Positioned _storyboardRowPressLayer({
  required Key key,
  required Layer layer,
  required int? Function(Offset local) frameAt,
  required StoryboardRowFramePress? onRowFramePress,
  required void Function(int frame)? onEdit,
}) {
  return Positioned.fill(
    key: key,
    child: InstantTapRegion(
      behavior: HitTestBehavior.translucent,
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      onPressDown: timelineCellDoubleTapRecord(
        layerId: layer.id,
        frameAt: frameAt,
      ),
      onTap: (localPosition) {
        final frame = frameAt(localPosition);
        if (frame == null) {
          return;
        }
        onRowFramePress?.call(LayerRowAddress(layer.id), frame);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: onEdit == null
            ? null
            : timelineCellDoubleTapActivation(
                layerId: layer.id,
                frameAt: frameAt,
                onActivate: onEdit,
              ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

/// A storyboard row's drop place: the frame under the pointer by the row's
/// own press conversion ([frameAtX], in the row's box), the row stood on
/// through [onRowFramePress] first — a drop LANDS, and landing is standing
/// (T4) — then the drop handed to [drop]. ONE place for the V row and the SE
/// rows, as [_storyboardRowPressLayer] is one press.
///
/// A permanent slot, as the canvas's is: it draws nothing and absorbs no
/// hit test until a matching drag is in flight.
MediaAssetDropTarget _storyboardRowDropTarget({
  required Key key,
  required BuildContext rowContext,
  required TimelineRowAddress row,
  required int? Function(double rowX) frameAtX,
  required StoryboardRowFramePress? onRowFramePress,
  required StoryboardMediaDrop drop,
  required StoryboardMediaDropAccepts? accepts,
}) {
  int? frameAt(Offset globalPosition) {
    final box = rowContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    return frameAtX(box.globalToLocal(globalPosition).dx);
  }

  return MediaAssetDropTarget(
    key: key,
    accepts: (data, globalPosition) {
      final frame = frameAt(globalPosition);
      return frame != null && (accepts?.call(row, frame, data.path) ?? true);
    },
    onDrop: (data, globalPosition) {
      final frame = frameAt(globalPosition);
      if (frame == null) {
        return;
      }
      onRowFramePress?.call(row, frame);
      drop(row, frame, data.path);
    },
  );
}

/// A storyboard row's range-select layer, wired to [select]; [rows] are
/// the rows a block move from this row may land on.
TimelineFrameRangeGestureLayer _storyboardRowRangeGestureLayer({
  required Key key,
  required Layer layer,
  required TimelineFrameGeometryHandle geometry,
  required double crossAxisExtent,
  required StoryboardSeSelectCallbacks select,
  required TimelineRowAddress? Function(TimelineRowAddress, double)? railRowAt,
  required List<TimelineDisplayRow> rows,
}) {
  final row = LayerRowAddress(layer.id);
  return TimelineFrameRangeGestureLayer(
    key: key,
    row: row,
    geometry: geometry,
    crossAxisExtent: crossAxisExtent,
    callbacks: TimelineRangeGestureCallbacks(
      isInSelection: (_, frame) =>
          _storyboardRangeCovers(select.selectedRange.value, row, frame),
      onSelectUpdate: (_, anchorIndex, headIndex, headCrossOffset) =>
          select.onDrag(
            layerId: layer.id,
            anchorGlobalFrame: anchorIndex,
            headGlobalFrame: headIndex,
            headRow: railRowAt?.call(row, headCrossOffset),
          ),
      onTapClear: (_) => select.onClear(),
      onMoveBegin: (_, _) => select.move?.onBegin(layer.id) ?? false,
      onMoveUpdate: (frameDelta, rowDelta) => select.move?.onUpdate(
        frameDelta,
        resolveBlockMoveTargetLayer(
          rows: rows,
          sourceLayerId: layer.id,
          rowDelta: rowDelta,
        ),
      ),
      onMoveEnd: () => select.move?.onEnd(),
      onMoveCancel: () => select.move?.onCancel(),
    ),
  );
}

class _StoryboardTransitionRow extends StatelessWidget {
  const _StoryboardTransitionRow({
    required this.track,
    required this.layer,
    required this.width,
    required this.height,
    required this.timelineScale,
    this.defById,
    this.crossingTooltip,
    this.commaDrag,
    this.onRowFramePress,
    this.onEditSpan,
    this.select,
    this.railRowAt,
  });

  final Track track;

  /// The row as it should RENDER — the committed layer, or the session's
  /// in-flight edge-drag form while a grip is held.
  final Layer layer;
  final double width;

  /// Its label's height ([_StoryboardRowHeights.transition]) — one row.
  final double height;
  final TimelineScale timelineScale;
  final CameraInstructionDef? Function(String instructionId)? defById;

  /// D26: the crossing-fade warning, by GLOBAL start key on this axis.
  final String? Function(int spanStartKey)? crossingTooltip;
  final TimelineCommaDragCallbacks? commaDrag;
  final StoryboardRowFramePress? onRowFramePress;
  final void Function(int globalFrame)? onEditSpan;

  /// Range selection AND move, the SE row's own bundle: the transition row
  /// is a track-owned rail row like an S row, so it selects — and slides
  /// its selection (C1 2026-08-17) — through the same verbs.
  final StoryboardSeSelectCallbacks? select;

  /// The rail's row lookup, so a select-drag can reach across rows exactly as
  /// the S rows' does.
  final TimelineRowAddress? Function(TimelineRowAddress, double)? railRowAt;

  /// The visible frame window this strip covers — the whole content width,
  /// like the SE grips' own geometry.
  int get _frameEndExclusive => timelineScale.pixelsPerFrame <= 0
      ? 0
      : (width / timelineScale.pixelsPerFrame).ceil();

  TimelineFrameGeometry get _geometry => TimelineFrameGeometry(
    frameCellExtent: timelineScale.pixelsPerFrame,
    frameStartIndex: 0,
    frameEndIndexExclusive: _frameEndExclusive,
  );

  @override
  Widget build(BuildContext context) {
    final spans = <Widget>[];
    // The paper under each span, at its TRUE global extent: this row has no
    // cells of its own, so it paints its paper the way the storyboard's SE
    // rows do rather than through the cell exposure states. [SePaperSpan] is
    // the shared paper block (a rounded block, no line across it — I-44) —
    // named for its first user, not SE-specific.
    for (final entry in layer.instructions.entries) {
      spans.add(
        Positioned(
          left: timelineScale.leftForFrame(entry.key),
          top: 0,
          bottom: 0,
          width: entry.value.length * timelineScale.pixelsPerFrame,
          child: IgnorePointer(
            key: ValueKey<String>(
              'storyboard-transition-paper-${layer.id}-${entry.key}',
            ),
            child: SePaperSpan(
              axis: Axis.horizontal,
              frameCellExtent: timelineScale.pixelsPerFrame,
              startFrame: entry.key,
              // ⑲: the block is its layer's colour label.
              paper: layerMarkColor(layer.mark),
            ),
          ),
        ),
      );
    }
    // The marks, from the direction row's own overlay builder.
    final defById = this.defById;
    if (defById != null && _frameEndExclusive > 0) {
      spans.add(
        Positioned.fill(
          child: IgnorePointer(
            child: TimelineFixedFrameSpanLayer(
              geometry: _geometry,
              crossAxisExtent: height,
              axis: Axis.horizontal,
              children: timelineRowInstructionOverlays(
                layer: layer,
                frameStartIndex: 0,
                frameEndIndexExclusive: _frameEndExclusive,
                axis: Axis.horizontal,
                defById: defById,
                keyPrefix: 'storyboard',
                // D26: the refusal marker on the AUTHORING axis too — the
                // one predicate, answered by global key here.
                crossingWarningTooltip: crossingTooltip,
                crossingWarningColor: Theme.of(context).colorScheme.error,
                crossAxisExtent: height,
              ),
            ),
          ),
        ),
      );
    }
    // Row-wide press: stand here, like every other row on this rail — a bare
    // Listener, the SE row's own, so the park lands whatever gesture follows.
    // DOUBLE-tap opens the span's term dialog, which is the cut timeline's
    // gesture for "edit this instance" and the only place a term is renamed
    // or a span deleted. Creation stays the rail's + button, so no boundary
    // gains an O.L by being brushed past. Mounted BEFORE the grips so the
    // edges keep drag priority.
    //
    // 🚨B5① (2026-08-17): the double tap rides the FRAME BLOCKS' shared
    // gate now — both taps must land on the SAME cell, or two seeks along
    // one span (click 1, click 3) opened the editor through the
    // recognizer's 100px slop. The record half arms on the press below,
    // exactly as `timelineRowCellsPaintArea` does; a covered-cell check is
    // this row's own subject guard, applied AFTER the shared law.
    final onRowFramePress = this.onRowFramePress;
    final onEditSpan = this.onEditSpan;
    if (onRowFramePress != null || onEditSpan != null) {
      int? frameAt(Offset local) => timelineScale.pixelsPerFrame <= 0
          ? null
          : (local.dx / timelineScale.pixelsPerFrame).floor();
      spans.add(
        _storyboardRowPressLayer(
          key: ValueKey<String>('storyboard-transition-press-${layer.id}'),
          layer: layer,
          frameAt: frameAt,
          onRowFramePress: onRowFramePress,
          onEdit: onEditSpan,
        ),
      );
    }
    // THE range gesture — the SE row's, verbatim, addressed to this row. It was
    // the one row of this rail a range drag could not touch (user 2026-08-11),
    // and the reason was simply that nothing mounted it here.
    //
    // Mounted UNDER the grips so the edges keep their drag priority, exactly
    // as the SE row's is.
    //
    // 🚨B5② (2026-08-17): "mounted UNDER" is STACK ORDER, and this block used
    // to sit AFTER the grips in [spans] — on top of them — so its eager pan
    // took every edge drag and the commas never moved. The SE row one class
    // down had the order right all along; this row now matches it, and the
    // grips go in LAST below.
    //
    // 🚨C1 (2026-08-17): the MOVE half too — the SE row's, verbatim. It used
    // to refuse (`onMoveBegin: false`) on the cut's read-only law, but that
    // law was about the CUT timeline's projection; THIS rail is the global
    // axis the spans really live on, where the edge grips already edit.
    // (That law went on 2026-09-25 — the cut's marks edit too.) The row list handed to the
    // move resolver holds only this row, which is the whole kind guard: a
    // transition span has no sibling row to land on, so the drag slides
    // frames and never changes rows (the SE rows' own clamp construction).
    final select = this.select;
    if (select != null && _frameEndExclusive > 0) {
      spans.add(
        _storyboardRowRangeGestureLayer(
          key: ValueKey<String>(
            'storyboard-transition-range-gesture-slot-${layer.id}',
          ),
          layer: layer,
          geometry: TimelineFrameGeometryHandle(_geometry),
          crossAxisExtent: height,
          select: select,
          railRowAt: railRowAt,
          rows: [TimelineDisplayRow.layer(layer, layerIndex: 0)],
        ),
      );
    }
    // …and the edge grips LAST, so they sit above the range gesture and the
    // press — the frame blocks' arbitration (edges keep comma-drag
    // priority), the same order the SE row and the cut row already mount.
    final commaDrag = this.commaDrag;
    if (commaDrag != null && _frameEndExclusive > 0) {
      final grips = timelineRowInstructionEdgeGrips(
        layer: layer,
        frameStartIndex: 0,
        frameEndIndexExclusive: _frameEndExclusive,
        resolveFrameCellExtent: () => timelineScale.pixelsPerFrame,
        commaDrag: commaDrag,
        axis: Axis.horizontal,
        crossAxisExtent: height,
      );
      if (grips.isNotEmpty) {
        spans.add(
          Positioned.fill(
            child: TimelineFixedFrameSpanLayer(
              geometry: _geometry,
              crossAxisExtent: height,
              axis: Axis.horizontal,
              children: grips,
            ),
          ),
        );
      }
    }
    return SizedBox(
      key: ValueKey<String>('storyboard-transition-row-${track.id.value}'),
      width: width,
      height: height,
      child: Stack(children: spans),
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
    required this.height,
    required this.timelineScale,
    required this.projectFrameRate,
    this.audioPeaksFor,
    this.seClipMarkerTooltip,
    this.onRowFramePress,
    this.onDropMediaAsset,
    this.acceptsMediaAsset,
    this.onEditSeEntry,
    this.seCommaDrag,
    this.seSelect,
    this.frameGeometry,
    this.railRowAt,
    this.seRowsInDisplayOrder = const [],
  });

  /// R9 #25: the rail row a cross-axis pointer offset lands on, resolved
  /// by the PANEL against the heights it paints. Null keeps the anchor.
  final TimelineRowAddress? Function(
    TimelineRowAddress anchorRow,
    double crossOffset,
  )?
  railRowAt;

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

  /// Its label's height ([_StoryboardRowHeights.se]) — one row.
  final double height;
  final TimelineScale timelineScale;
  final ProjectFrameRate projectFrameRate;
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// The recorded-take clipping warning (REC1-D): non-null mounts the red
  /// block-corner marker on clipped spans, where the timeline's SE row
  /// mounts it. Null hides it (clipping notice setting off).
  final String? seClipMarkerTooltip;

  /// Timeline parity: the row's cells press (row + frame, empty cells
  /// included) and EVERY block carries the comma edge grips (UI-R7 #5 —
  /// global starts, any cut).
  final StoryboardRowFramePress? onRowFramePress;

  /// A media-browser row let go on one of this row's EMPTY cells — see
  /// [StoryboardPanel.onDropMediaAsset]. Null mounts no drop place.
  final StoryboardMediaDrop? onDropMediaAsset;
  final StoryboardMediaDropAccepts? acceptsMediaAsset;

  /// B6 (2026-08-17): double-tapping the SAME cell of a sound block opens
  /// its instance editor — the timeline SE row's entrance, gated by the
  /// frame blocks' shared [TimelineCellDoubleTapGate]. Global frames,
  /// because that is this row's axis. Null keeps the row press-only.
  final void Function(LayerId layerId, int globalFrame)? onEditSeEntry;

  final TimelineCommaDragCallbacks? seCommaDrag;

  /// Range selection on this row — the SAME shared gesture and the same
  /// track-axis selection the cut row uses, one row up. Null keeps the row
  /// display-only.
  final StoryboardSeSelectCallbacks? seSelect;

  /// The panel's live frame-axis geometry, which the shared gesture reads
  /// to turn a pointer position into a track-global frame.
  final TimelineFrameGeometryHandle? frameGeometry;

  /// Whether the live selection covers this row at [globalFrame].

  @override
  Widget build(BuildContext context) {
    final spans = <Widget>[];
    final layer = this.layer;
    if (layer != null) {
      final blocks = drawingBlocks(layer.timeline);
      spans.addAll(_contentSpans(layer, blocks));
      spans.addAll(_interactionLayers(context, layer, blocks));
      final clipTooltip = seClipMarkerTooltip;
      if (clipTooltip != null) {
        spans.add(_clipMarkerLayer(context, layer, clipTooltip));
      }
    }

    return SizedBox(
      key: ValueKey<String>('storyboard-se-row-$trackIndex-${slot + 1}'),
      width: width,
      height: height,
      child: Stack(children: spans),
    );
  }

  /// Clipped takes' red corners (REC1-D) on the ROW, where the timeline's SE
  /// row mounts them. ↩️They rode the twirled-down Audio lane here, so a
  /// clipped take showed only while its row was open (F-101).
  Positioned _clipMarkerLayer(
    BuildContext context,
    Layer layer,
    String tooltip,
  ) {
    final frames = timelineScale.pixelsPerFrame <= 0
        ? 0
        : (width / timelineScale.pixelsPerFrame).ceil();
    return Positioned.fill(
      child: TimelineFixedFrameSpanLayer(
        geometry: TimelineFrameGeometry(
          frameCellExtent: timelineScale.pixelsPerFrame,
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: height,
        axis: Axis.horizontal,
        children: timelineRowClipMarkerOverlays(
          layer: layer,
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
          crossAxisExtent: height,
          axis: Axis.horizontal,
          tooltip: tooltip,
          color: Theme.of(context).colorScheme.error,
          keyPrefix: 'storyboard-${layer.id}',
        ),
      ),
    );
  }

  /// What the row shows: each block's paper, the waveform where a clip's
  /// peaks are known, and the dialogue / SE name over each block.
  List<Widget> _contentSpans(
    Layer layer,
    List<TimelineDrawingBlock> blocks,
  ) {
    final spans = <Widget>[];
    // Paper blocks first — the storyboard SE row has no cells
    // underneath, so each block paints its own paper span (SePaperSpan)
    // at its TRUE global extent; waveforms go above the paper, the
    // writing on top.
    for (final block in blocks) {
      spans.add(
        _paperSpan(block, layer),
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
          _waveformSpan(span, endExclusive, layer, peaks),
        );
      }
    }
    // The sheet's writing on the paper blocks.
    for (final block in blocks) {
      final frame = layer.frameById(block.frameId);
      final dialogue = frame?.name;
      final seName = frame?.seName;
      spans.add(
        _dialogueSpan(block, layer, dialogue, seName),
      );
    }
    return spans;
  }

  /// What the row answers to: the selection wash, the press layer, the
  /// range gesture, and the comma grips on each block's edges.
  List<Widget> _interactionLayers(
    BuildContext context,
    Layer layer,
    List<TimelineDrawingBlock> blocks,
  ) {
    final spans = <Widget>[];
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
        _selectionWash(layer, seSelect),
      );
    }
    if (onRowFramePress != null || onEditSeEntry != null) {
      final onEditSeEntry = this.onEditSeEntry;
      spans.add(
        _pressLayer(layer, (local) => _frameAtX(local.dx), onEditSeEntry),
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
        _rangeGestureLayer(layer, geometry, seSelect),
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
            _edgeGrip(edge, block, layer, blockOrdinal, seCommaDrag),
          );
        }
      }
      if (grips.isNotEmpty) {
        spans.add(
          _gripLayer(grips),
        );
      }
    }
    // A sound let go on an EMPTY cell: a new block from that cell. Last,
    // like every drop place — it takes no pointer until a drag is in flight.
    final drop = onDropMediaAsset;
    if (drop != null) {
      final cells = _cellDropLayer(context, layer, blocks, drop);
      if (cells != null) {
        spans.add(cells);
      }
    }
    return spans;
  }

  /// The press's conversion: this row's frame 0 sits at its left edge.
  int? _frameAtX(double x) => timelineScale.pixelsPerFrame <= 0
      ? null
      : (x / timelineScale.pixelsPerFrame).floor();

  /// The row's cells, as its grips and its drop places are laid out on.
  TimelineFrameGeometry get _rowFrames => TimelineFrameGeometry(
    frameCellExtent: timelineScale.pixelsPerFrame,
    frameStartIndex: 0,
    frameEndIndexExclusive: timelineScale.pixelsPerFrame <= 0
        ? 0
        : (width / timelineScale.pixelsPerFrame).ceil(),
  );

  Positioned _gripLayer(List<Widget> grips) {
    return Positioned.fill(
      child: TimelineFixedFrameSpanLayer(
        geometry: _rowFrames,
        crossAxisExtent: height,
        axis: Axis.horizontal,
        children: grips,
      ),
    );
  }

  /// One drop place per EMPTY gap of this row — the timeline's SE row law
  /// (「SE 행의 빈 칸 → 새 블록」) on the track axis this row draws. Over the
  /// gaps only, as the timeline's are, so a block is never the place to
  /// start another; the gaps are [emptyGapsBetween]'s, the one free-span
  /// answer.
  Positioned? _cellDropLayer(
    BuildContext context,
    Layer layer,
    List<TimelineDrawingBlock> blocks,
    StoryboardMediaDrop drop,
  ) {
    final frames = _rowFrames;
    final end = frames.frameEndIndexExclusive;
    // The walk asks cell by cell, and a track runs to thousands of frames.
    // Past the row's last block nothing covers a cell, so the walk stops
    // there and the rest is one gap — the answer inside it is still
    // [emptyGapsBetween]'s.
    final walked = blocks.isEmpty
        ? 0
        : math.min(blocks.last.endIndexExclusive, end);
    final gaps = [
      ...emptyGapsBetween(layer, 0, walked),
      if (walked < end) (startIndex: walked, length: end - walked),
    ];
    if (gaps.isEmpty) {
      return null;
    }
    return Positioned.fill(
      child: TimelineFixedFrameSpanLayer(
        geometry: frames,
        crossAxisExtent: height,
        axis: Axis.horizontal,
        children: [
          for (final gap in gaps)
            TimelineFrameSpan(
              placement: TimelineFrameSpanPlacement(
                startIndex: gap.startIndex,
                endIndexExclusive: gap.startIndex + gap.length,
              ),
              child: _storyboardRowDropTarget(
                key: ValueKey<String>(
                  'storyboard-se-cell-drop-${layer.id}-${gap.startIndex}',
                ),
                rowContext: context,
                row: LayerRowAddress(layer.id),
                frameAtX: _frameAtX,
                onRowFramePress: onRowFramePress,
                drop: drop,
                accepts: acceptsMediaAsset,
              ),
            ),
        ],
      ),
    );
  }

  TimelineFrameSpan _edgeGrip(TimelineBlockEdge edge, TimelineDrawingBlock block, Layer layer, int blockOrdinal, TimelineCommaDragCallbacks seCommaDrag) {
    return TimelineFrameSpan(
      placement: timelineBlockEdgeGripPlacement(
        edge: edge,
        startIndex: block.startIndex,
        endIndexExclusive: block.endIndexExclusive,
        // I-44: on the SE paper, which stops a seam short of the row.
        crossAxisExtent: timelineRowPaperExtent(height),
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
    );
  }

  TimelineFrameRangeGestureLayer _rangeGestureLayer(
    Layer layer,
    TimelineFrameGeometryHandle geometry,
    StoryboardSeSelectCallbacks seSelect,
  ) => _storyboardRowRangeGestureLayer(
    key: ValueKey<String>('storyboard-se-range-gesture-slot-${layer.id}'),
    layer: layer,
    geometry: geometry,
    crossAxisExtent: height,
    select: seSelect,
    railRowAt: railRowAt,
    rows: seRowsInDisplayOrder,
  );

  Positioned _pressLayer(
    Layer layer,
    int? Function(Offset local) frameAt,
    void Function(LayerId layerId, int globalFrame)? onEditSeEntry,
  ) => _storyboardRowPressLayer(
    key: ValueKey<String>('storyboard-se-press-${layer.id}'),
    layer: layer,
    frameAt: frameAt,
    onRowFramePress: onRowFramePress,
    onEdit: onEditSeEntry == null
        ? null
        : (frame) => onEditSeEntry(layer.id, frame),
  );

  Positioned _selectionWash(Layer layer, StoryboardSeSelectCallbacks seSelect) {
    return Positioned.fill(
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
    );
  }

  /// A full-height strip over the frames `[startFrame, endExclusive)`.
  ///
  /// ⛔THREE SPANS ON THIS ROW placed themselves: the dialogue, the paper
  /// and the waveform. Each worked the left edge and the width out of the
  /// same scale, and each wrapped its child in the same ignored pointer —
  /// three chances for one of them to place a strip a frame off the others
  /// on the row it shares.
  Positioned _frameSpan({
    required int startFrame,
    required int endExclusive,
    required Key key,
    required Widget child,
  }) => Positioned(
    left: timelineScale.leftForFrame(startFrame),
    top: 0,
    bottom: 0,
    width: (endExclusive - startFrame) * timelineScale.pixelsPerFrame,
    child: IgnorePointer(key: key, child: child),
  );

  Positioned _dialogueSpan(
    TimelineDrawingBlock block,
    Layer layer,
    String? dialogue,
    String? seName,
  ) => _frameSpan(
    startFrame: block.startIndex,
    endExclusive: block.endIndexExclusive,
    key: ValueKey<String>(
      'storyboard-se-span-${layer.id}-${block.startIndex}',
    ),
    child: SeSpanVisual(
      axis: Axis.horizontal,
      dialogue: dialogue ?? '',
      seName: seName,
    ),
  );

  Positioned _waveformSpan(
    SeAudioSpan span,
    int endExclusive,
    Layer layer,
    AudioPeaks peaks,
  ) => _frameSpan(
    startFrame: span.startFrame,
    endExclusive: endExclusive,
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
  );

  Positioned _paperSpan(TimelineDrawingBlock block, Layer layer) => _frameSpan(
    startFrame: block.startIndex,
    endExclusive: block.endIndexExclusive,
    key: ValueKey<String>(
      'storyboard-se-paper-${layer.id}-${block.startIndex}',
    ),
    child: SePaperSpan(
      axis: Axis.horizontal,
      frameCellExtent: timelineScale.pixelsPerFrame,
      startFrame: block.startIndex,
      // ⑲: the block is its layer's colour label.
      paper: layerMarkColor(layer.mark),
    ),
  );
}

/// One lane's frame band on the shared substrate — the timeline grid's own
/// row for whatever the lane is: the Audio lane's waveform band
/// ([SeAudioLaneFrameRow]) or a property lane's key markers
/// ([TimelineLaneFrameRow]), told apart by [laneIsSeAudio] exactly as the
/// timeline tells them apart (F-101).
///
/// ↩️It said 「rendered PER CUT (the audio lane's remount pattern)」, which
/// R4b had already retired: the band runs the track's global axis in one row.
class _StoryboardLaneStripRow extends StatelessWidget {
  const _StoryboardLaneStripRow({
    required this.rowKey,
    required this.carrier,
    required this.lane,
    required this.width,
    required this.height,
    required this.timelineScale,
    required this.projectFrameRate,
    this.laneEdit,
    this.laneRange,
    this.audioLane,
    this.audioPeaksFor,
  });

  final String rowKey;

  /// The row's identity on the shared lane substrate: the GLOBAL SE layer
  /// itself, or the V track's synthetic carrier
  /// ([trackTransformLaneCarrierId]).
  final Layer carrier;

  /// The lane resolved against the TRACK-AXIS transform (global keyed
  /// frames) — one continuous row, exactly like an SE row (R4b): keys
  /// exist with no cut under them and edits land at global frames, so the
  /// old per-cut spans' local-frame emissions (an offset accident against
  /// track-owned data) are structurally gone.
  final PropertyLaneRow lane;

  final double width;

  /// Its label's height ([_StoryboardRowHeights.lane]) — one row.
  final double height;
  final TimelineScale timelineScale;
  final ProjectFrameRate projectFrameRate;
  final PropertyLaneEditCallbacks? laneEdit;

  /// Wires the band's range-select/move gesture (the timeline's lane
  /// machinery, carrier-routed in the session); null keeps the band
  /// display-only (SE lanes, v1).
  final TimelineLaneRangeCallbacks? laneRange;

  /// The Audio band's sound edits and the peaks it draws — what the
  /// timeline's SE rows take. A property lane reads neither.
  final TimelineAudioLaneCallbacks? audioLane;
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  @override
  Widget build(BuildContext context) {
    final metrics = TimelineGridMetrics(
      frameCellWidth: timelineScale.pixelsPerFrame,
      layerRowHeight: height - 2,
    );
    final frames = timelineScale.pixelsPerFrame <= 0
        ? 0
        : (width / timelineScale.pixelsPerFrame).floor();
    final onSetClipOffset = audioLane?.onSetClipOffset;
    final onSetClipFades = audioLane?.onSetClipFades;
    return SizedBox(
      key: ValueKey<String>(rowKey),
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: laneIsSeAudio(lane)
            ? SeAudioLaneFrameRow(
                layer: carrier,
                frameStartIndex: 0,
                frameEndIndexExclusive: frames,
                leadingFrameSpacerWidth: 0,
                trailingFrameSpacerWidth: 0,
                metrics: metrics,
                frameRate: projectFrameRate,
                audioPeaksFor: audioPeaksFor,
                // The span keys ride the row's id, as they did on the Audio
                // lane this band replaced.
                keyPrefix: 'storyboard-${carrier.id}',
                onSetClipOffset: onSetClipOffset == null
                    ? null
                    : (clipIndex, offsetFrames) =>
                          onSetClipOffset(carrier.id, clipIndex, offsetFrames),
                offsetDrag: audioLane?.offsetDrag,
                onSetClipFades: onSetClipFades == null
                    ? null
                    : (clipIndex, fadeIn, fadeOut) => onSetClipFades(
                        carrier.id,
                        clipIndex,
                        fadeIn,
                        fadeOut,
                      ),
              )
            : TimelineLaneFrameRow(
                layer: carrier,
                lane: lane,
                frameStartIndex: 0,
                frameEndIndexExclusive: frames,
                leadingFrameSpacerWidth: 0,
                trailingFrameSpacerWidth: 0,
                metrics: metrics,
                laneRange: laneRange,
                keyPrefix: 'storyboard',
              ),
      ),
    );
  }
}

/// Rail rows share the timeline label rail's row language — bordered
/// surface rows, a kind icon leading the name — so the storyboard's left
/// edge reads near-identically to the timeline's layers/sections rail
/// (user direction). The track row opens its section like the timeline's
/// heavier section divider.
/// The V row's RAIL half — the track's label and its columns.
///
/// Public because the folded storyboard mounts this very widget (D15): the
/// timeline's folded row already mounts its real `TimelineLayerControlsRow`
/// rather than re-listing its slots, and 「트랙이 보여야 하는데 프레임이
/// 보인다」 was the storyboard having no such row to mount at all.
class StoryboardTrackLabelRow extends StatelessWidget {
  const StoryboardTrackLabelRow({
    super.key,
    required this.track,
    required this.trackLabel,
    required this.laneHeight,
    this.laneExpanded = false,
    this.onToggleLane,
    this.active = false,
    this.onSelectTrack,
    this.activeCut,
    this.subjectCut,
    this.cutPictureVisibleOf,
    this.onToggleCutPictureVisibility,
    this.trackFxState = LayerFxState.on,
    this.onToggleTrackFx,
    this.trackOpacity = 1.0,
    this.onTrackOpacityChanged,
    this.onTrackOpacityChangeEnd,
    this.chromeless = false,
  });

  /// The rail's own width — what a host windows this row against.
  static double railWidthIn(BuildContext context) =>
      StoryboardPanel.railWidthIn(context);

  /// GROUND OFF: no fill, no active wash, no seams (the folded row's whole
  /// design is the negative space — see [CollapsedRowOverlay]). It is the
  /// same flag, spelled the same way, that the timeline's rail row takes:
  /// 「chromeless는 셀이 아니라 행의 성질」, so a row that paints ground has
  /// to read it wherever it paints.
  final bool chromeless;

  final Track track;
  final String trackLabel;

  /// Kept in lockstep with the strip row's: the rail and the strips are two
  /// columns of the same row and share no scaffolding to enforce it.
  final double laneHeight;

  // ⛔The two-line gate went with the track NAME it guarded (⑭). A rail that
  // prints one label needs no threshold for a second — and leaving the gate
  // behind is how dead conditions accumulate into "this looked deliberate".

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
  final bool Function(CutId cutId)? cutPictureVisibleOf;
  final ValueChanged<CutId>? onToggleCutPictureVisibility;

  /// R9 #21: the V row's own columns, describing the TRACK rather than
  /// whichever cut happens to sit under the playhead — the fx switch as a
  /// MASTER over the track's per-cut switches, and the static opacity that
  /// the animated fade lane multiplies. Null keeps the row display-only.
  final LayerFxState trackFxState;
  final VoidCallback? onToggleTrackFx;
  final double trackOpacity;
  final ValueChanged<double>? onTrackOpacityChanged;
  final ValueChanged<double>? onTrackOpacityChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // V-track selection (UI-R18 #6): the S-row tap/highlight language on
    // the V row — tap selects the TRACK, the active treatment speaks
    // through the background alone.
    return _StoryboardLabelShell(
      selectKey: ValueKey<String>('storyboard-track-select-${track.id.value}'),
      rowKey: ValueKey<String>('storyboard-track-label-row-${track.id.value}'),
      onTap: onSelectTrack,
      height: laneHeight,
      active: active,
      chromeless: chromeless,
      semanticsLabel: active
          ? AppText.strings.semSelectedTrack
          : AppText.strings.semTrack,
      child: Row(
            children: [
              // R9 #22 — THE 44px. This row hand-listed its leading slots
              // and skipped the sheet and mark columns entirely, drawing an
              // 18px icon where the canonical type button is 22; its name
              // and every column measured from it sat 44px left of every
              // other rail row's. It now builds from the shared skeleton
              // like everyone else.
              ...layerRailLeadingCells(
                // The timeline rows' lane chevron: twirls down the track's
                // cut-level Transform group (the V-track lanes + fade
                // strip).
                laneToggle: onToggleLane == null
                    ? null
                    : RailSwipeColumnPointer(
                        onPressed: onToggleLane,
                        child: InkWell(
                          key: ValueKey<String>(
                            'storyboard-track-lane-toggle-${track.id.value}',
                          ),
                          // ⛔A NO-OP: the press already fired it (onPressDown
                          // above). Both would fire twice.
                          onTap: () {},
                          child: SizedBox(
                            height: 24,
                            child: Icon(
                              laneExpanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                // A track is not a layer, so the type slot takes the film
                // strip by override rather than a kind.
                typeButton: LayerTypeButton(
                  keyPrefix: 'storyboard',
                  idValue: 'v-${track.id.value}',
                  icon: _vRowGlyph,
                  semanticLabel: AppText.strings.sbVideoTrack,
                  onTap: onSelectTrack,
                ),
              ),
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
                      // F-26: 「지금 우선 V1라는 글자만 볼드체인거 굉장히
                      // 통일감면에서 이상함」 — a row's name is a row's name
                      // on every surface, so the bold is gone and this
                      // points at the one style with the rest.
                      style: layerRowNameStyle(context),
                    ),
                    // ⛔NO SECOND LINE (⑭ 유저 2026-08-12: 「v행에 있는
                    // Track 1 이거 삭제. 그냥 V1이라고만 존재하도록. **다시는
                    // 안 쓸 텍스트임.**」)
                    //
                    // `Track.name` was a leftover from the multi-track era.
                    // The app is single-track by the user's own decision (the
                    // V-track add/remove UI was deliberately never built —
                    // 전제 8), so every row printed the same manufactured
                    // "Track 1" underneath its real label. A row's identity IS
                    // `V1`; the line beneath it said nothing a second row
                    // could have contradicted.
                    //
                    // The height-threshold fold that used to guard it went too
                    // (there is no detail left to drop on a short row).
                  ],
                ),
              ),
              // V-row display toggles (UI-R13 #2): ALWAYS-normal buttons in
              // the shared fx/eye slots (UI-R5) acting on THIS track's cut at
              // the current global index — no stand-down, no parked graying.
              // Where no cut exists (a gap on this track) a press is a no-op;
              // the button is track furniture, only its subject is absent.
              ...layerRailTrailingCells(
                columns: layerRailColumnWidthsIn(context),
                // R9 #21: the switch in this row's fx column is the
                // TRACK's — a row's columns describe the row's own
                // subject, and this row is the track's.
                //
                // R10 R3: it is now the ONLY fx axis on the film. The
                // per-cut bypass that used to hang off this button's
                // context menu is gone — a switch nobody could reach on
                // touch, over a state that never left the session.
                fx: onToggleTrackFx == null
                    ? null
                    : RailSwipeColumnPointer(
                        child: FxToggleButton(
                          keyValue: 'storyboard-track-fx-${track.id.value}',
                          subject: RailSubject.track,
                          state: trackFxState,
                          onToggle: onToggleTrackFx!,
                        ),
                      ),
                visibility: onToggleCutPictureVisibility == null
                    ? null
                    : RailSwipeColumnPointer(
                        child: SizedBox(
                          height: 26,
                          // The SAME eye the layer and folder rows mount —
                          // this was a sixth inline copy (R28 follow-up).
                          child: LayerVisibilityToggleButton(
                            keyValue:
                                'storyboard-cut-visibility-'
                                '${subjectCut?.id.value ?? 'none-${track.id.value}'}',
                            subject: RailSubject.track,
                            isVisible:
                                subjectCut == null ||
                                (cutPictureVisibleOf?.call(subjectCut!.id) ??
                                    true),
                            onToggle: () {
                              final subject = subjectCut;
                              if (subject != null) {
                                onToggleCutPictureVisibility!(subject.id);
                              }
                            },
                          ),
                        ),
                      ),
                // R9 #21: the track's STATIC opacity — this slot was empty
                // while every other rail row had a bar. The animated fade
                // lane multiplies it, exactly as a layer's animated
                // opacity multiplies its static one.
                opacity: onTrackOpacityChanged == null
                    ? null
                    : FieldSlider.opacity(
                        key: ValueKey<String>(
                          'storyboard-track-opacity-${track.id.value}',
                        ),
                        value: trackOpacity.clamp(0.0, 1.0).toDouble(),
                        height: 18 + FieldSlider.growthIn(context),
                        onChanged: onTrackOpacityChanged,
                        onChangeEnd: onTrackOpacityChangeEnd,
                      ),
              ),
            ],
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
    required this.dragPreview,
    required this.committedTotalFrames,
    required this.movieEndUnder,
    required this.scale,
    required this.pixelsPerFrame,
    required this.movieEnd,
  });

  /// F-18: the grip rides the LIVE end, like the line it grips and like the
  /// timeline's own cut-end handle. It used to be placed from the committed
  /// project, so the finger left it behind on the first frame of a drag.
  final ValueListenable<TimelineDragPreview?>? dragPreview;
  final int committedTotalFrames;
  final int Function(TimelineDragPreview preview) movieEndUnder;
  final TimelineScale scale;
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
    return ValueListenableBuilder<TimelineDragPreview?>(
      valueListenable: widget.dragPreview ?? _noDragPreview,
      builder: (context, preview, child) => Positioned(
        key: const ValueKey<String>('storyboard-cut-end-handle'),
        left: widget.scale.leftForFrame(
          timelineCutEndPreviewFrameCount(
            preview: preview,
            cutId: null,
            playbackFrameCount: widget.committedTotalFrames,
            movieEndUnder: widget.movieEndUnder,
          ),
        ),
        top: 0,
        bottom: 0,
        width: 12,
        child: child!,
      ),
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

  /// This panel's CUT-LOCAL ordinal. Every panel hangs a leading grip
  /// (user's rule 2026-08-02) and the grip is the same verb whatever the
  /// ordinal — the cut's lead edge, with this panel the one that gives up
  /// the commas. The ordinal is what tells the session WHICH panel that is.
  int panelIndex,

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
    required this.onDropMediaAsset,
    required this.acceptsMediaAsset,
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
    this.railRowAt,
    this.onCreateStoryboardLayer,
  });

  /// R9 #25: the rail row a cross-axis pointer offset lands on, resolved
  /// by the PANEL against the heights it paints. Null keeps the anchor.
  final TimelineRowAddress? Function(
    TimelineRowAddress anchorRow,
    double crossOffset,
  )?
  railRowAt;

  /// D30: pressed on a no-layer cut's CREATE affordance (the reserved
  /// strip slot's content). The gate and the dispatch both live with the
  /// host's session pair (canAddLayerOfKind/addLayerOfKind — T25); null
  /// keeps the affordance display-only.
  final ValueChanged<CutId>? onCreateStoryboardLayer;

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
  final StoryboardMediaDrop? onDropMediaAsset;
  final StoryboardMediaDropAccepts? acceptsMediaAsset;

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
  Map<CutId, List<StoryboardCoverageCell>> _cellsByCut() =>
      storyboardCellsByCut(layoutEntries);

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
                panelIndex: index,
                commaBlockKey: index == cells.length - 1 || index >= keys.length
                    ? null
                    : keys[index],
              ),
          ];
        }(),
  ];

  /// The plates the row's grips stand on: a cut's first panel starts its
  /// plate and its last panel ends it — the plate's round corners — and
  /// every boundary between panels is the plate's straight edge.
  TimelineGripPaper _gripPaper(List<_StoryboardStripGrip> grips) => (
    cornerStarts: {
      for (final grip in grips)
        if (grip.panelIndex == 0) grip.startFrame,
    },
    cornerEnds: {
      for (var index = 0; index < grips.length; index += 1)
        if (index == grips.length - 1 ||
            grips[index + 1].cutId != grips[index].cutId)
          grips[index].endFrameExclusive,
    },
    cornerRadius: StoryboardCutBlocksPainter.plateCornerRadius,
  );

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
      // The panel press already seeks into its cut, so the tap only drops
      // the selection (R10: standing is handled by the press here).
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
      onMoveEnd: stripSelect.move?.onEnd ?? _noMove,
      onMoveCancel: stripSelect.move?.onCancel ?? _noMove,
    );
  }

  /// Whether [frame] sits in the live selection — a plain range test now
  /// that the selection IS a range on this row's own axis.
  bool _isSelectedAt(int frame) => _storyboardRangeCovers(
    cutSelect?.selectedRange.value,
    TrackRowAddress(track.id),
    frame,
  );

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
      onSelectUpdate: (_, anchorIndex, headIndex, headCrossOffset) =>
          cutSelect?.onDrag(
            trackId: track.id,
            anchorGlobalFrame: anchorIndex,
            headGlobalFrame: headIndex,
            headRow: railRowAt?.call(
              TrackRowAddress(track.id),
              headCrossOffset,
            ),
          ),
      // A cut press already takes the cut and seeks into it, so the tap
      // only drops the selection (R10: standing is the press's job here).
      onTapClear: (_) => cutSelect?.onClear(),
      onMoveBegin: (_, frame) {
        final entry = _cutAtFrame(frame);
        return entry != null && (cutMove?.onBegin(entry.cutId) ?? false);
      },
      onMoveUpdate: (frameDelta, _) => cutMove?.onUpdate(frameDelta),
      onMoveEnd: cutMove?.onEnd ?? _noMove,
      onMoveCancel: cutMove?.onCancel ?? _noMove,
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
  /// Both halves of the pointer DOWN — the seek AND the D30 create — run
  /// under this ONE gate pair: secondary buttons are not presses here,
  /// and a press inside the live selection is starting a move, so it
  /// neither seeks nor creates.
  bool _pressDownGated(PointerDownEvent event) {
    if (event.buttons != 0 && (event.buttons & kPrimaryButton) == 0) {
      return true;
    }
    return _isSelectedAt(_frameAtX(event.localPosition.dx));
  }

  void _handlePressDown(PointerDownEvent event) {
    onRowFramePress?.call(
      TrackRowAddress(track.id),
      _frameAtX(event.localPosition.dx),
    );
  }

  /// D30: a press inside the ACTIVE no-layer cut's create affordance —
  /// eligibility and rect are [StoryboardCutBlocksPainter
  /// .createAffordanceRectOf]'s, the SAME call the paint made. The
  /// visual is the PRE-press snapshot, so a press on a non-active cut's
  /// block centre stays a SELECT (its slot drew no affordance), and only
  /// the next press — on the drawn '+' — creates.
  void _maybeCreateStoryboardLayer(
    StoryboardCutBlocksPainter painter,
    PointerDownEvent event,
  ) {
    final onCreate = onCreateStoryboardLayer;
    if (onCreate == null) {
      return;
    }
    final block = painter.blockAt(event.localPosition);
    if (block == null) {
      return;
    }
    final affordance = StoryboardCutBlocksPainter.createAffordanceRectOf(block);
    if (affordance == null || !affordance.contains(event.localPosition)) {
      return;
    }
    onCreate(block.cutId);
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
    final drop = onDropMediaAsset;
    final cellsByCut = _cellsByCut();
    final grips = _stripGrips(cellsByCut);
    // Where the panels are drawn is where their gestures and their EDGES
    // live — the picture and the pointer read one definition of the band.
    final stripBand = StoryboardCutBlocksPainter.stripBandOf(laneHeight);

    // Held in a local so the press layer hit-tests the SAME visuals the
    // paint lays down (the D30 create affordance reads block.strip).
    //
    // Through the shared builder (D15): the folded storyboard draws its
    // row with this same call, so the picture there cannot be a second
    // opinion about thumbnails, names or where the writing sits.
    final blocksPainter = storyboardCutBlocksPainterFor(
      entries: layoutEntries,
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
      windowBucket: windowBucket,
      viewportMainExtent: viewportWidth,
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
                  painter: blocksPainter,
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
                  onPointerDown: (event) {
                    _onCutPressDown(event, blocksPainter);
                  },
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
            // D30: the STRIP's own selection band — the timeline's ONE
            // band decoration, drawn from the cut-local selection's own
            // numbers. One listener per TRACK row, never per cut
            // (old-tablet law), pointer-transparent like every band.
            if (stripSelect case final stripSelect?)
              Positioned(
                left: 0,
                right: 0,
                top: stripBand.top,
                height: stripBand.height,
                child: IgnorePointer(
                  child: ValueListenableBuilder<TimelineFrameRangeSelection?>(
                    valueListenable: stripSelect.selection,
                    builder: (context, selection, _) {
                      return _stripRangeOutline(
                        selection,
                        crossExtent: stripBand.height,
                      );
                    },
                  ),
                ),
              ),
            // THE EDGES, at the panels' boundaries. They ride ABOVE the strip
            // and cut gestures so an edge keeps its priority over both; the
            // middles keep the rest.
            //
            // One shape of grip, and where it sits decides what it does: the
            // first panel's leading edge is the CUT's lead edge, and every
            // trailing edge is its panel's comma with the cut's length
            // riding the row end (edge unification — the division verb is
            // gone). The cut block has no grips of its own besides these.
            //
            // 🗣️ON THE WHOLE PLATE, in its corners (유저 2026-09-25: 「제대로
            // 컷블록의 위치에 존재하지않아. 내부에 존재하는느낌」 · 「공통
            // 적용해서」): the I-43 triangle takes the block's corners, and the
            // cut's block is the plate — its end edge the plate's top-right,
            // its start edge the bottom-left, the two corners the cut's title
            // and length leave free. ↩️They lay on the picture strip since
            // #757 (07-25, 「a cut edge is always ON the strip」), which put
            // every triangle in the strip's corners, inside the plate.
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
                top: 0,
                height: laneHeight,
                child: TimelineRowEditChromeLayer(
                  paintKey: ValueKey<String>(
                    'storyboard-edit-chrome-${track.id.value}',
                  ),
                  // The ground is what the grips' corners actually SIT ON:
                  // the plate's bands — so the ground law gives the light
                  // mark on the dark plate whether or not thumbnails show
                  // (유저 2026-09-25: 「배경이 어두워서 엣지가 잘 안보여 …
                  // 기본을 하얀색으로한다던가」). ↩️B1 (08-17) gave them the
                  // picture's white while they stood on the strip: a
                  // panel's picture is left-aligned, so the end triangle
                  // mostly stood on the plate past it, dark on dark. The
                  // bands stay whatever the row's height (유저 2026-09-25:
                  // 「띠는 v행 세로 줄어도 고정으로 그 자리에 두자」), so
                  // no row leaves the corners on the pictures.
                  gripGround: storyboardCutBlockBackgroundColor(
                    Theme.of(context).colorScheme,
                    active: false,
                    hovered: false,
                    rangeSelected: false,
                  ),
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
                          // EVERY panel hangs a leading grip (user's rule
                          // 2026-08-02). R4 had left it on the first panel
                          // alone, because P5 #8's interior front grips
                          // DELEGATED to the previous panel's back grip —
                          // two handles doing one thing. They are not that
                          // any more: a front grip takes the frames off the
                          // cut's HEAD and a back grip off its TAIL, so the
                          // two edges of one boundary name two edits.
                          startGrip: true,
                          endGrip: true,
                        ),
                    ],
                    gripIdScope: track.id.value,
                    layer: null,
                    baseLayer: null,
                    crossAxisExtent: laneHeight,
                    axis: Axis.horizontal,
                    includeRunEdges: false,
                    gripPaper: _gripPaper(grips),
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
                      // R10 R4: no impersonation. A grip reports the edge
                      // it IS, and the rule that decides what moves lives
                      // one layer down, in the session — which is where
                      // the "a front edge inside a cut is really the
                      // previous back edge" trick belonged all along.
                      final grip = grips[ordinal];
                      if (edge == TimelineBlockEdge.start) {
                        return stripEdges!.onCutEdgeBegin(
                          grip.cutId,
                          TimelineBlockEdge.start,
                          grip.panelIndex,
                        );
                      }
                      final commaKey = grip.commaBlockKey;
                      return commaKey == null
                          ? stripEdges!.onCutEdgeBegin(
                              grip.cutId,
                              TimelineBlockEdge.end,
                              grip.panelIndex,
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
            // A pool file let go on the row's frames. The row stands on that
            // frame through its own press first — landing is standing (T4) —
            // then hands the drop up, where the session names the NEW cut
            // there. A permanent slot, as the canvas's is: it draws nothing
            // and absorbs no hit test until a matching drag is in flight.
            // Last in the stack, so a grip under the file hides no frame.
            if (drop != null)
              Positioned.fill(
                child: _storyboardRowDropTarget(
                  key: ValueKey<String>(
                    'storyboard-track-asset-drop-${track.id.value}',
                  ),
                  rowContext: context,
                  row: TrackRowAddress(track.id),
                  frameAtX: _frameAtX,
                  onRowFramePress: onRowFramePress,
                  drop: drop,
                  accepts: acceptsMediaAsset,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The strip's range-selection band: the selected panels of the cut
  /// whose storyboard layer the selection names, or nothing when no
  /// entry carries that layer.
  Widget _stripRangeOutline(
    TimelineFrameRangeSelection? selection, {
    required double crossExtent,
  }) {
    if (selection == null ||
        timelineScale.pixelsPerFrame <= 0) {
      return const SizedBox.shrink();
    }
    StoryboardTimelineLayoutEntry? anchor;
    for (final entry in layoutEntries) {
      if (storyboardLayerForCut(entry.cut)?.id ==
          selection.layerId) {
        anchor = entry;
        break;
      }
    }
    if (anchor == null) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        Positioned(
          left: timelineScale.leftForFrame(
            anchor.startFrame + selection.startIndex,
          ),
          top: 0,
          bottom: 0,
          width:
              timelineScale.pixelsPerFrame *
              (selection.endIndexExclusive -
                  selection.startIndex),
          child: Semantics(
            key: const ValueKey<String>(
              'storyboard-strip-range-selection',
            ),
            label: AppText.strings.tlSelectedPanelRange,
            container: true,
            child: DecoratedBox(
              decoration: timelineRangeSelectionBandDecorationAt(
                cellExtent: timelineScale.pixelsPerFrame,
                crossExtent: crossExtent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A press on the cut blocks: gated first, then the press itself, then
  /// the storyboard-layer create judged on the painter this build drew.
  void _onCutPressDown(
    PointerDownEvent event,
    StoryboardCutBlocksPainter blocksPainter,
  ) {
    if (_pressDownGated(event)) {
      return;
    }
    _handlePressDown(event);
    // The create judges the PRE-press snapshot (the
    // painter this build drew), so running after the
    // press's activation cannot widen it (D30).
    _maybeCreateStoryboardLayer(blocksPainter, event);
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

// _StoryboardFrameLinesPainter is GONE (D8/D38 2026-08-18): it was a
// drifted copy of TimelineBeatLinesPainter — pre-beatLine-split second
// color, base+beat double ink at 6f multiples, a line at x=0, no snap —
// and the storyboard now mounts the shared grid sheet above (I-44).

/// A never-changing drag channel, for the two end-line widgets when the host
/// hands none. Cheaper than branching the builder, and it can never notify.
final ValueNotifier<TimelineDragPreview?> _noDragPreview =
    ValueNotifier<TimelineDragPreview?>(null);

/// A row with no move hooks ends and cancels a move by doing nothing.
void _noMove() {}

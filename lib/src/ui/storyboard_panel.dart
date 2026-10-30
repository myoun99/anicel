import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show Listenable, ValueListenable, listEquals;
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerHoverEvent, kPrimaryButton;
import 'package:flutter/material.dart';

import '../models/attached_layer_resolve.dart'
    show
        attachArrowPlacement,
        attachRowWearsBaseComposite,
        isSyncedAttachedLayer;
import '../models/attached_placement.dart' show AttachedPlacement;
import '../models/canvas_size.dart';
import '../models/conte_group.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame_id.dart';
import '../models/fx_plugin_description.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart'
    show EffectId, LayerEffect, effectParameterValueAtTime;
import '../models/layer_folder.dart'
    show LayerFolderIndex, attachFolderLevelsAbove, attachGroupBaseOf;
import '../models/layer_id.dart';
import '../models/layer_mark.dart';
import '../models/project.dart';
import '../models/project_frame_rate.dart';
import '../models/range_snap.dart' show StandingUnit, standingUnitAt;
import '../models/se_audio_spans.dart';
import '../models/timeline_coverage.dart'
    show
        TimelineBlockEdge,
        TimelineDrawingBlock,
        coveringDrawingBlockAt,
        drawingBlocks;
import '../models/camera_row_reach.dart';
import '../models/track.dart';
import '../models/track_camera_head.dart' show cameraHeadFamilyOf;
import '../models/track_camera_row.dart';
import '../models/track_id.dart';
import '../models/track_conte_row.dart';
import '../models/track_projection_row.dart'
    show
        projectionRowIdOf,
        projectionRowInHandOn,
        projectionRowUnder,
        trackIdOfProjectionRow;
import '../models/track_transform_lane_carrier.dart';
import '../models/transform_track.dart' show TransformTrack;
import '../models/track_transitions.dart' show transitionRowSpans;
import 'dashed_path.dart' show DashPattern, dashesAlong;
import 'canvas/canvas_press.dart' show canvasPressButtons, canvasPressPans;
import 'canvas/flip_hud_controller.dart' show FlipHudAxis;
import 'canvas/flip_hud_model.dart';
import 'canvas/flip_hud_rows.dart';
import 'canvas/view_hand.dart';
import 'storyboard/storyboard_rows_channel.dart';
import '../services/audio/audio_peaks_extractor.dart';
import 'audio/sound_cannot_play.dart' show SoundCannotPlay, soundCannotPlayIn;
import 'storyboard_cut_blocks_painter.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnails;
import 'storyboard_layer_policy.dart';
import '../models/storyboard_timeline_layout.dart';
import 'theme/app_theme.dart';
import 'timeline/timeline_frame_axis_follower.dart';
import 'timeline/layer_label_controls.dart';
import 'timeline/timeline_cut_end_handle.dart'
    show EndLineGrip, timelineCutEndPreviewFrameCount;
import 'timeline/layer_rail_columns.dart';
import 'timeline/berth_row.dart' show BerthRow;
import 'timeline/rail_eyes.dart'
    show RailEye, RailEyeShown, RailEyes, railEyesOf;
import 'timeline/rail_column_swipe.dart';
import 'timeline/layer_rail_window.dart';
import 'timeline/frame_ruler_view.dart';
import 'timeline/timeline_grid_frame.dart';
import 'timeline/lane_graph.dart'
    show LaneGraphVerbs, LaneGraphsView, TimelineGraphSeat;
import 'timeline/lane_graph_seats.dart'
    show
        LaneGraphLine,
        laneBandStandsOn,
        laneGraphHeadedBy,
        laneGraphLineAmong,
        seatLaneGraphs;
import 'timeline/timeline_lane_graph.dart'
    show LaneGraphGrid, laneGraphFrameSide, laneGraphLines, timelineRowBuiltNow;
import 'timeline/timeline_section_runs.dart'
    show timelineDisplayRowExtent, timelineRowEdgesOf;
import 'timeline/timeline_swipe_columns.dart'
    show RailSwipeHooks, timelineSwipeColumns;
import 'widgets/dock_edge_splitter.dart';
import 'widgets/drag_chip.dart' show DragChipItem;
import 'widgets/tick_layer.dart';
import 'timeline/property_lane_model.dart'
    show
        LaneStretchWord,
        PropertyLaneEditCallbacks,
        PropertyLaneRow,
        TimelineDisplayRow,
        laneAsPreviewed,
        laneGroupKey,
        layerRowHiddenBy,
        parseLaneGroupKey,
        previewedLaneRow;
import 'timeline/property_lanes_for_row.dart' show propertyLanesForRow;
import 'timeline/timeline_row_edges.dart';
import 'timeline/timeline_visible_range.dart';
import 'timeline/held_row_pin.dart';
import 'timeline/window_move_keep.dart';
import 'timeline/timeline_row_selection_bands.dart';
import 'timeline/timeline_row_span_resolver.dart'
    show
        laneBoxLanesOf,
        laneSpanOverDrawnRows,
        resolveBlockMoveTargetLayer,
        resolveInGroupHeadLane,
        resolveLaneSpanEscalationOverAddresses,
        resolveSelectionSpanOverAddresses;
import 'timeline/timeline_lane_rows.dart'
    show
        TimelineLaneControlsRow,
        TimelineLaneFrameRow,
        TimelineLaneKeysLine,
        laneRowFrame,
        timelineHollowKeyFrames,
        timelineKeysLineSpan,
        timelineLaneKeySpan,
        timelineStretchWordSpan;
import 'timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectPropertyLanes, parseEffectLaneId;
import 'timeline/layer_drop_policy.dart'
    show
        linesBeyondRow,
        ownsTheLane,
        rowStepsBetween,
        rowUnitAround,
        slotForSteps;
import 'timeline/layer_row_drag.dart'
    show
        ConteSeatRowSubject,
        EffectRowSubject,
        LaneRowSubject,
        LayerRowDragSubject,
        LayerRowDragTarget,
        LayerRowSubject,
        TimelineRowDragHooks,
        TrackRowSubject,
        TrackSeRowSubject,
        effectRowDragChip,
        layerRowDragChips,
        timelineRowAddressOfDragSubject;
import 'timeline/timeline_block_look.dart'
    show TimelineBlockRow, timelineRowLookOf;
import 'timeline/timeline_cel_content_source.dart';
import 'timeline/timeline_current_row.dart';
import 'timeline/timeline_ruler_cursor_overlay.dart';
import 'input/arena_tap_hold.dart';
import 'input/control_press_claim.dart' show PressFire, PressFireScope;
import 'input/hit_gate.dart';
import 'input/panel_pan.dart';
import 'input/two_axis_drag.dart';
import 'panels/panel_collapsed_scope.dart';
import 'timeline/transform_lane_policy.dart'
    show
        cameraPropertyLanes,
        cameraUnionHeader,
        laneSelectionCoversBandRow,
        transformGroupHeader,
        transformGroupHeaderLane;
import '../models/app_input_settings.dart' show AppInput;
import 'widgets/instant_tap_region.dart' show InstantTapRegion;
import 'widgets/row_plate.dart';
import 'timeline/timeline_beat_lines.dart'
    show
        TimelineGridDash,
        TimelineGridLaw,
        TimelineGridRow,
        TimelineGridRows,
        TimelineGridSheet,
        timelineBlockPaperShape,
        timelineGridLineSnap,
        timelineLaneGround,
        timelineRowPaperExtent;
import 'timeline/timeline_double_tap.dart'
    show
        TimelineDoubleTapCells,
        TimelineLabelDoubleClick,
        timelineCellDoubleTapActivation,
        timelineCellDoubleTapRecord,
        timelineDoubleTapAim;
import 'timeline/lane_row_slice.dart';
import 'timeline/timeline_drag_preview.dart';
import 'timeline/timeline_cell_style.dart'
    show
        storyboardCutBlockBackgroundColor,
        timelineRangeSelectionBandDecorationAt,
        timelineSelectedFrameBorderColor,
        timelineStandingWashDecorationAt;
import 'timeline/timeline_exposure_comma_drag_handle.dart'
    show TimelineBlockEdgeGrip, timelineBlockEdgeGripPlacement;
import 'timeline/timeline_row_edit_chrome.dart'
    show
        TimelineRowChromeResolver,
        TimelineRowEditChromeLayer,
        TimelineRowGripCallbacks,
        timelineLayerGripBlocks;
import 'timeline/timeline_frame_geometry.dart'
    show TimelineFrameGeometry, TimelineFrameGeometryHandle;
import 'timeline/timeline_frame_range_gesture.dart'
    show
        TimelineFrameRangeGestureLayer,
        TimelineLaneRangeCallbacks,
        TimelineLaneRangeHooks,
        TimelineRangeGestureCallbacks;
import '../models/storyboard_coverage.dart'
    show storyboardCoverageCells, storyboardDivisionKeys;
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
        TimelineFrameSpanLayout,
        TimelineFrameSpanPlacement;
import 'timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'timeline/timeline_frame_coordinate_policy.dart'
    show FrameScrubDedupe, frameIndexFromLocalX, timelineFrameEdge;
import 'timeline/timeline_frame_range_policy.dart'
    show TimelineFrameRange, endlessViewportFillFrames;
import '../models/layer_kind.dart';
import '../models/camera_instruction.dart' show CameraInstructionDef;
import 'timeline/timeline_instruction_row_visual.dart'
    show timelineRowInstructionEdgeGrips, timelineRowInstructionOverlays;
import 'timeline/timeline_frame_ruler.dart';
import 'timeline/timeline_row_run_labels_painter.dart'
    show TimelineRowRunLabelsPainter;
import 'timeline/timeline_row_cells_painter.dart' show TimelineRowCellsPainter;
import 'timeline/timeline_grid_tile_store.dart' show TimelineGridTileStore;
import 'timeline/timeline_tile_raster_source.dart'
    show filmSubstrateGeneration;
import 'effective_device_pixel_ratio.dart' show EffectiveDevicePixelRatio;
import 'timeline/timeline_cell_exposure_state.dart'
    show timelineOwnCelNameAt, timelineOwnCelsStateAt;
import 'timeline/timeline_frame_window.dart'
    show timelineFrameWindowReachFor, visibleFrameWindowFor;
import 'timeline/memo_token.dart'
    show ByIdentity, ByList, BySet, Kept, KeptPiece, keptWhileSame;
import 'repaint_props.dart';
import 'timeline/timeline_edge_auto_pan.dart';
import 'timeline/timeline_grid_metrics.dart';
import 'timeline/timeline_row_cross_offset.dart';
import 'timeline/timeline_horizontal_scrollbar_rail.dart';
import 'timeline/timeline_layer_controls_header.dart';
import 'timeline/timeline_legend_menus.dart';
import 'timeline/timeline_layer_controls_row.dart'
    show
        ControlsRowFace,
        TimelineGroupFold,
        TimelineLayerControlsRow,
        timelineGroupFoldFor;
import 'timeline/timeline_vertical_scrollbar_rail.dart';
import 'timeline/timeline_playhead.dart' show timelinePlayheadColumn;
import 'timeline/timeline_row_filter.dart';
import 'timeline/timeline_scale.dart';
import 'timeline/timeline_section_policy.dart'
    show TimelineSection, timelineSectionForLayerKind, timelineSectionLabel;
import 'timeline/timeline_se_row_visual.dart'
    show
        SePaperSpan,
        seNameBoxExtent,
        timelineRowAudioOverlays,
        timelineRowSeLabelOverlays,
        timelineRowSoundWarningOverlays;
import 'timeline/timeline_zoom_anchor_policy.dart';
import 'layout/device_grid_scroll_controller.dart';
import 'text/app_strings.dart' show AppText;
import 'listenable_rebind.dart';
import 'session/rail_legends.dart';
import 'session/row_spans.dart' show trackRowMaterialBlocks;
import 'sliced_value_listenable_builder.dart'
    show SlicedListenable, SlicedListenableBuilder;

part 'storyboard/storyboard_projection_keys.dart';
part 'storyboard/storyboard_camera_row.dart';
part 'storyboard/storyboard_conte_row.dart';
part 'storyboard/storyboard_cut_starts.dart';
part 'storyboard/storyboard_standing.dart';
part 'storyboard/storyboard_rows_and_labels.dart';
part 'storyboard/storyboard_scroll.dart';
part 'storyboard/storyboard_rows_window.dart';
part 'storyboard/storyboard_rail_rows.dart';
part 'storyboard/storyboard_rail_sweep.dart';
part 'storyboard/storyboard_sheet.dart';
part 'storyboard/storyboard_folded_row.dart';

/// One row of a track group's rail, as the strip column lays it out.
///
/// [row] is the address a select-drag may land its head on (S rows and the
/// V row). [laneRow] is the address you can STAND on when the row is a
/// property lane — of the V track's carrier or of an SE layer — which is a
/// wider set than [bandRow], the lanes that carry a range band. The
/// fade-envelope row is the case that separates the two: it is the opacity
/// lane's row and takes the standing cell, but it draws fade handles
/// instead of key markers and no selection reaches it.
///
/// [lane] is whether the row is a LANE band at all — an open graph's room
/// as much as a property lane — which is what the grid sheet paints the
/// lane ground under (I-44). Neither address says it: the room keeps none,
/// and an S slot with no layer keeps none either.
///
/// [seSlot] is the slot of an S row, which its run is found by; null for
/// every other row.
///
/// [standRow] is the address you can STAND on when the row is neither of
/// those — a CONTE row of the track ([trackConteRowId], I-73): its cells
/// are its cuts' own, selected inside a cut on the cut's own axis, so no
/// track-axis select-drag lands its head on it and it keeps no [row]
/// (유저 2026-10-08: the sweep across cuts is for later).
///
/// [display] is the row as the timeline's rail holds one: a lane — its
/// carrier and the lane — which is what a header graph seats
/// ([seatLaneGraphs], I-89 ①), and a row that wears a layer — the S and
/// transition rows theirs, the V row its lane carrier, a projection head
/// the layer it has in hand by the row's own id — which is what the
/// column sweep reads and presses ([_StoryboardRailSweep], I-89 ①ⓒ); null
/// for a row with no button to sweep — a headless one, an empty S slot.
/// [graph] is the open header graph the slot stands in: a lane it draws, or
/// the ROOM it stands past them, a slot of its own after the last of them
/// that nobody stands on.
typedef _StoryboardRailSlot = ({
  TimelineRowAddress? row,
  LaneRowAddress? laneRow,
  LayerRowAddress? standRow,
  bool bandRow,
  bool lane,
  int? seSlot,
  double height,
  TimelineDisplayRow? display,
  TimelineGraphSeat? graph,
});

/// R9 #25: the rows a select-drag pressed on [anchorRow] has swept to a
/// pointer [crossOffset] from its top ([_StoryboardRailRows._railSweepOn]) —
/// every row from the pressed one to the one under the pointer, in the
/// order the rail draws them — resolved by the PANEL against the heights it
/// paints. Null keeps the anchor.
typedef _RailSweepAt =
    List<TimelineRowAddress>? Function(
      TimelineRowAddress anchorRow,
      double crossOffset,
    );

/// The address a rail slot is stood on by — a row's own, a lane's, or the
/// conte row's — or null for a row nobody stands on (an open graph's room,
/// an S slot with no layer).
TimelineRowAddress? _standingAddressOf(_StoryboardRailSlot slot) =>
    slot.row ?? slot.laneRow ?? slot.standRow;

/// The drag hooks the cuts' and their panels' edges need, mirroring the
/// timeline's comma-drag callbacks: live preview per step, ONE undo on
/// release. The V row hangs a cut's own two edges with them, and the conte
/// row under it every panel's (I-73; ↩️one row hung both while the panels
/// were drawn inside the cut block).
///
/// There is one shape of edge, and where it sits decides what it re-times
/// (design, user's rule 2026-07-25; edge unification 2026-07-28,
/// every-panel leading edges 2026-08-02):
///
/// - EVERY leading edge — first and inner alike — is the cut's START, with
///   the panel it belongs to the one that gives up the commas. It is one
///   verb at every ordinal, which is why the ordinal travels with it
///   instead of forking the callback;
/// - EVERY trailing edge — inner and last alike — is that panel's comma,
///   with the cut's length riding the row end.
///
/// A row riding the conte hangs its own blocks' two edges on the row under
/// it, and they are that block's alone ([onRowEdgeBegin], I-73).
///
/// Hence three begins and one set of continuations — the grip that started
/// decides which session verb the rest of the drag belongs to, and the
/// mount that knows the geometry is the one that says so.
class StoryboardStripEdgeCallbacks {
  const StoryboardStripEdgeCallbacks({
    required this.onCutEdgeBegin,
    required this.onCommaBegin,
    required this.onRowEdgeBegin,
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

  /// Re-times the block keyed [blockStartIndex] — in its row's own frames
  /// — of [layerId], a row of [cutId] riding the cut's conte: either edge,
  /// as that row's grips on the timeline do. Returns whether the drag may
  /// start (a row that owns no timing refuses).
  final bool Function(
    CutId cutId,
    LayerId layerId,
    int blockStartIndex,
    TimelineBlockEdge edge,
  )
  onRowEdgeBegin;

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
  /// [spanRows] are the Excel-style cross-row reach (feedback #14): the
  /// rows the drag swept, lanes and all, in the order the panel draws them
  /// ([StoryboardSeSelectCallbacks.onDrag]'s), which the PANEL resolves
  /// from the heights it paints (R9 #25 — it used to be a row count
  /// computed from one row height, which mis-counted every row of a
  /// different size).
  final void Function({
    required TrackId trackId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    List<TimelineRowAddress> spanRows,
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

  /// A select-drag step on the track's GLOBAL frame axis. [spanRows]
  /// reach across the rail's rows exactly as the cut row's do: the rows the
  /// drag swept from [anchorRow] — the panel hands the sliced span of the
  /// rows it drew, lanes and all, whichever row it was pressed on (C② ·
  /// H20).
  final void Function({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? anchorRow,
    List<TimelineRowAddress> spanRows,
  })
  onDrag;
  final VoidCallback onClear;

  /// Sliding the selected sounds — a drag that STARTS inside the
  /// selection, the timeline's grammar. Null keeps the row select-only.
  final StoryboardRangeMoveCallbacks? move;
}

/// Range selection on the CONTE ROW — the cut's own panels (↩️the cut
/// block's strip, until I-73 gave them a row).
///
/// Its blocks are a CUT's own, so unlike every other row of this panel it
/// speaks the cut's axis: its selection is the ordinary cut-local one the
/// timeline uses, on that cut's storyboard layer. The mount converts, which
/// is why these callbacks take the layer and a frame of its own.
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

/// The unworked-block tint's source for the conte rows, which cross every
/// cut (F-357): whether one cut's cel holds a picture, whether it could not
/// be read (its block red — frame-picture-indicator-Q1 b), and the signal
/// that an answer may have moved — the timeline's own
/// ([TimelineCelContentSource]), asked of the cut a frame stands in.
typedef ConteCelContent = ({
  bool Function(Cut cut, LayerId row, FrameId cel) holdsAPicture,
  bool Function(Cut cut, LayerId row, FrameId cel) cannotBeRead,
  ValueListenable<int> revision,
});

/// What the rail lays its rows from ([_StoryboardRailRows]) — which rows it
/// shows, which lanes they twirl down, where those sit and how tall each
/// is: this panel's own fields ([StoryboardPanel.railInputs]), or the
/// session's as they are now ([StoryboardPanel.railNow]).
///
/// 🚨ONE record, so the folded row is laid by the table the open rail lays
/// from inputs this panel has not been given yet: the workspace builds the
/// fold before it rebuilds this panel. ↩️A graph opened over the lane the
/// fold stood on left the fold the V row, at the V row's height (card
/// a-folded-conte-row-keeps-its-height-through-a-graph).
typedef StoryboardRailInputs = ({
  Project project,
  CutId? activeCutId,
  TimelineRowAddress? selectedRow,
  ValueListenable<List<TimelineRowAddress>>? rowSelection,
  Set<LayerId> expandedLaneLayerIds,
  Set<String> expandedLaneGroupKeys,
  LaneGraphsView laneGraphs,
  Set<TimelineSection> hiddenSections,
  TimelineRowFilter rowFilter,
  Set<LayerId> collapsedAttachBaseIds,
  LayerFxState Function(LayerId layerId)? layerFxStateOf,
  LayerFxState Function(Track track)? trackFxStateOf,
  CanvasSize? poseDisplaySize,
  double trackLaneHeight,
});

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
    this.onSettledPress,
    this.labelDoubleClick,
    this.onSelectTrack,
    this.stripEdges,
    this.cutMove,
    this.cutSelect,
    this.stripSelect,
    this.onCreateStoryboardLayer,
    this.linkedCutIds = const {},
    this.onOpenCutLinks,
    this.movieEnd,
    this.trackLaneHeight = defaultTrackLaneHeight,
    this.onResizeTrackLanes,
    this.pixelsPerFrame = 8,
    this.onPixelsPerFrameChanged,
    this.rulerView = FrameRulerView.frames,
    this.rulerPages,
    this.onRulerViewChanged,
    this.railExtent,
    this.frameAxisOffset,
    this.layerAxisOffset,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.playheadFrame,
    this.cutUnderPlayhead,
    this.revealSelectionTick,
    this.playbackFrame,
    this.frameReadySignal,
    this.onSeekGlobalFrame,
    this.onScrubGlobalFrame,
    this.onScrubEnd,
    this.readyRunsIn,
    this.thumbnails,
    this.audioPeaksFor,
    this.soundCannotPlay,
    this.seClipMarkerTooltip,
    this.seLanePreview,
    this.trackLaneEditFor,
    this.laneRange,
    this.currentRowHooks,
    this.rowDragHooks,
    this.onRowSelectionSpan,
    this.rowSelection,
    this.layerLaneEdit,
    this.cutLaneEdit,
    this.poseDisplaySize,
    this.hasFxPlugin,
    this.onSetCutFade,
    this.onToggleLayerVisibility,
    this.onOpenLayerMixer,
    this.onOpenCameraPath,
    this.isLayerSoloed,
    this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.onLayerMarkSelected,
    this.onToggleLayerTimesheet,
    this.layerOnTimesheetOf,
    this.onToggleLayerOnionSkin,
    this.layerOnionSkinEnabledOf,
    this.layerEyeOnOf,
    this.layerLanesOpenOf,
    this.layerFxStateOf,
    this.onToggleLayerFx,
    this.onLayerBlendModeSelected,
    this.collapsedAttachBaseIds = const {},
    this.onToggleAttachGroup,
    this.groupFoldOpenOf,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.expandedLaneGroupKeys = const {},
    this.onToggleLaneGroupKey,
    this.laneGroupOpenOf,
    this.laneGraphs = LaneGraphsView.none,
    this.laneGraphVerbs,
    this.laneGraphsNow,
    this.railNow,
    this.trackFxStateOf,
    this.onToggleTrackFx,
    this.onToggleTrackEffectEnabled,
    this.onResetTrackEffectGroup,
    this.onToggleLaneGroupEnabled,
    this.laneGroupOnOf,
    this.onResetLaneGroup,
    this.seCommaDrag,
    this.seSelect,
    this.transitionDefById,
    this.transitionRowShown,
    this.rowsChannel,
    this.transitionCrossingTooltip,
    this.transitionCommaDrag,
    this.onEditTransitionSpan,
    this.onEditSeEntry,
    this.onEditCutBlock,
    this.onEditConteBlock,
    this.conteCelContent,
    this.stepsUntilShown,
    this.onCameraCutPress,
    this.onEditCameraCell,
    this.cutFrameCursor,
    this.onSeekCutFrame,
    this.dragPreview,
    this.legend,
    this.legendHand,
    this.rowFilter = TimelineRowFilter.none,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.visibilitySoloEnabled = false,
    this.opacityDragPreview,
    this.legendOpacityValue = 1.0,
    this.legendOnionSkinOn = false,
  });

  /// Blocks are strictly frame-linear (Premiere-style): a large minimum
  /// width would make neighbours overlap when zoomed out. The tiny floor
  /// only keeps zero-length cuts visible.
  ///
  /// ↩️At I-22's ten-minute floor "tiny" was 64 frames, and every shorter
  /// cut lay over the next. The floor stops where the next cut starts now
  /// (유저 2026-09-26, zoom-floor-fixed-marks-Q1 — the painter's `_widthFor`),
  /// so a zero-length cut with a cut right behind it is not drawn at all.
  ///
  /// ↩️And it is one pixel, not eight (유저 2026-09-27: 「타임라인줌 최대한
  /// 줄이면 컷블록이 엔드라인 넘거나 해서 원래 있어야할 크기보다 블럭이
  /// 커지는데 최대한 원래 공간만 차지하도록」). Eight pixels was 64 frames at
  /// the floor, so a short cut before a gap and the film's last cut grew past
  /// their frames — the last one over the end line. A block is its frames
  /// now; only a cut too short to cover a pixel is drawn as one, so it does
  /// not vanish, and still never past the next cut.
  ///
  /// Public since D15: the folded storyboard draws the same blocks and
  /// must not carry a floor of its own — a second floor over there is a
  /// second answer the day this one moves.
  static const double cutBlockMinWidth = 1;
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
  // 하나 바꾼다고 다른게 바뀌지않도록." The two rails carried different
  // columns — this one had no blend cell and no onion, both of which came
  // later (I-73, I-89-Q22) — so the day either needs a new one, the other
  // must be free to stay put. The
  // repetition is the point; do not "clean it up" into a shared constant.
  //
  // 434 → 443 (text-scale-rail-opac, 유저 2026-09-25): the opacity column
  // this rail shares widened to hold the legend's OPAC at 1×, and the
  // answer the user picked named both rails.
  //
  // 2026-10-08 (I-73): the day came for the BLEND cell — the conte row's
  // head is the timeline's own (유저: 「콘티행도 동일하게 하고싶으니까 어태치
  // 접기펼치기버튼등 동일하게 할수있는거 다 넣는거 잊지말고」; the drawn
  // proposal: 「라벨 · fx · 눈 · 불투명도 · 블렌드 · 레인 펼침이 타임라인과
  // 같이 됩니다」), so this rail carries the column and every row of it
  // keeps the slot ([optionalRailColumns]). The NUMBER stays: it is the width
  // the timeline's rail has held that cell in since R27 #6, and the room
  // comes back out of the name, where it had gone.
  //
  // 443 → 519 (tool-settings-panel-tidy, 유저 2026-10-10): a lane's value
  // boxes took their ± and pencil, and the timeline's rail pays the 76
  // (「레일도 그만큼 넓어집니다」 — 「문제없는데」). This rail's camera and
  // conte rows twirl down the same lanes, so the same number.
  //
  // 519 → 461 (F-409, 유저 2026-10-19): the timeline's names went to two
  // thirds, and 「이런 개선들은 말 안해도 콘티패널이랑 법 통일」 — the same
  // number again.
  //
  // 2026-10-20 (I-89-Q22): the day came for the ONION cell — 「어니언도
  // 콘티행 기본적으로 버튼 글로벌이니까 넣음」. The number stays again, and
  // the room comes out of the name, which is now the timeline's to the
  // pixel: the two rails carry the same columns.
  static const double _trackLabelWidth = 461;

  /// Which optional columns this rail's rows keep — the host's answer every
  /// row and the legend above them read ([layerRailTrailingCells]): an
  /// ONION slot (I-89-Q22 — a conte row's, one for the track's cuts) and a
  /// BLEND slot after the opacity's, which a row with nothing to show in
  /// them reserves, empty, as it does every column it has nothing in.
  static const LayerRailOptionalColumns optionalRailColumns = (
    onion: true,
    blend: true,
  );

  /// The kinds this rail's rows can be — its legend's kind solos
  /// ([TimelineLegendMenus.kinds]): a conte row, and a cut's row turned
  /// back into a drawing row (I-73) or filed in a 공정 folder of the conte;
  /// an S row; the transition row and the camera row.
  ///
  /// 🗣️F-408 (유저 2026-10-19): 「콘티패널엔 이미지레이어 없으니
  /// 대응안되는거 리스트 정리」 — no IMAGE, INSTRUCTION or ADJUSTMENT row
  /// stands on this rail: those are a cut's own rows, which the timeline
  /// shows. ↩️It listed the active cut's kinds, so those came up here and
  /// a solo of one emptied the rail.
  static const Set<LayerKind> railKinds = {
    LayerKind.storyboard,
    LayerKind.animation,
    LayerKind.folder,
    LayerKind.se,
    LayerKind.transition,
    LayerKind.camera,
  };

  /// [_trackLabelWidth] where [context] lays its text out: this rail pays for
  /// its word-holding columns' growth — the opacity bar's, the blend
  /// chip's and a lane's value boxes' — as the timeline's pays for the
  /// same three (text-scale-rail-columns, 유저 2026-09-25: 「칸도 글자 따라
  /// 넓어진다」). 0 at 1×. ↩️The opacity's alone, while this rail had no
  /// blend column; the lanes' unpaid, out of their names.
  static double railWidthIn(BuildContext context) {
    final columns = layerRailColumnWidthsIn(context);
    return _trackLabelWidth +
        (columns.opacity - layerOpacitySlotWidth) +
        (columns.blend - layerBlendSlotWidth) +
        (columns.laneValue - layerLaneValueSlotWidth);
  }

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
  /// they twirl their lanes open, so height means something else there.
  ///
  /// 🗣️I-73 (유저 2026-10-08: 「띠 둘만 이사로 가자」, and the drawn
  /// proposal it answered: 「글자 띠 둘이 내려가 콘티 행이 됩니다. 한 번만
  /// 나옵니다. 높이 70 + 30」): the cut block keeps its own TWO bands
  /// ([StoryboardCutBlocksPainter.bandHeight] each, 26px) and the picture
  /// the 44px it had; the conte blocks' two went down to the conte row, a
  /// row of its own under this one. The floor is the bands alone: they never
  /// fold (유저 2026-09-25: 「띠는 v행 세로 줄어도 고정으로 그 자리에 두자」),
  /// so at 26 the picture is gone and every word stays whole.
  /// ↩️96 · 52 while the block wore four bands — 유저 2026-09-26: 「기본높이는
  /// 96으로 가자. 최솟값 ok. 최대값은 최대한 키울수있으면 좋아」: 96 left the
  /// picture those same 44px, a little more than the 38 the old 64 row left
  /// it between two bands.
  ///
  /// The CEILING is the tallest row whose picture stays sharp
  /// ([maxTrackLaneHeightFor]) — 🗣️유저 2026-09-27
  /// (storyboard-v-row-ceiling-Q1): 「그림이 선명한 한 최대로(카메라 프레임
  /// 높이 + 띠)」. ↩️504, while the tallest picture a strip could ask was
  /// the conte's fixed 640px one. ↩️64 · 28 · 160 with two bands.
  static const double defaultTrackLaneHeight = 70;
  // The height's LEGAL RANGE — the bar's steppers died with B7 (2026-08-17),
  // and the V-track splitter (2026-09-26) clamps to it
  // ([onResizeTrackLanes]).
  static const double minTrackLaneHeight =
      StoryboardCutBlocksPainter.bandHeight * 2;

  /// The tallest a V row may grow for a film shot through [cameraFrame] on
  /// a screen of [devicePixelRatio]: the strip asks its picture at the
  /// height it shows it, up to the camera frame (`pictureRenderWidthFor`),
  /// so past the frame's own height in the screen's pixels the picture
  /// would stretch (⛔해상도로 속도를 사지 않는다) — that height, and the
  /// bands over it.
  static double maxTrackLaneHeightFor(
    CanvasSize cameraFrame,
    double devicePixelRatio,
  ) => minTrackLaneHeight + cameraFrame.height / devicePixelRatio;

  /// [height] held to the legal range under [ceiling] — the height the rows
  /// are drawn at, whatever the splitter or a saved layout set.
  static double clampTrackLaneHeight(
    double height, {
    required double ceiling,
  }) => height
      .clamp(minTrackLaneHeight, math.max(minTrackLaneHeight, ceiling))
      .toDouble();

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
  /// is the timeline's layer row — so both panels stop on the same budget.
  /// ⚠️It named [minTrackLaneHeight] while that floor WAS the same 28px; the
  /// V rows' floor is their bands (52 with four, 2026-09-26; 26 with the
  /// cut's two, I-73) and the budget stays the timeline's.
  ///
  /// WHAT LANDS in that budget is the project's business, not the floor's:
  /// the default lane is 70 and SE rows are 30, so at the floor the user
  /// gets a scrollable sliver rather than two whole lanes. The number's job
  /// is that the body stays scrollABLE — 56 clears the 32px thumb minimum
  /// with room to travel — and that the chrome above and below it survives.
  /// The bottom scrollbar row is what the user watched disappear.
  static const double minPanelHeight =
      timelineLayerRowHeight +
      2 * timelineLayerRowHeight +
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

  /// A press on a rail row that turned out to be a TAP — the timeline
  /// rail's T10 second half, the same verb ([TimelineLayerControlsRow
  /// .onSettledPress]): whatever was selected goes (유저: 「클릭하고 떼면 뭐든
  /// 비우게」). Null clears nothing on the release.
  final VoidCallback? onSettledPress;

  /// A double click on a layer's label — the timeline rail's, the same
  /// widget (I-48). Null mounts none.
  final TimelineLabelDoubleClick? labelDoubleClick;

  /// Tapping a V-row label selects its TRACK (UI-R18 #6): the session
  /// promotes that track's cut under the shared global playhead to the
  /// active cut. Null keeps V labels display-only.
  final ValueChanged<TrackId>? onSelectTrack;

  /// Edge-grip hooks for the V row's cut edges and the conte row's panel
  /// edges: a cut's — and its first panel's — front edge is the CUT's lead
  /// edge, and every trailing edge is its panel's comma with the cut's
  /// length riding the row end (edge unification). Null hides the grips.
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

  /// Range selection on the CONTE ROW — the cut's own panels, on the cut's
  /// own axis. Null keeps the row display-only.
  final StoryboardStripSelectCallbacks? stripSelect;

  /// D30: pressed on a no-layer cut's CREATE affordance — its stretch of
  /// the conte row. The host's gate/dispatch pair is the session's
  /// canAddLayerOfKind/addLayerOfKind (T25). Null = display-only.
  final ValueChanged<CutId>? onCreateStoryboardLayer;

  /// The LINKED cuts (I-25): their names wear the link icon.
  final Set<CutId> linkedCutIds;

  /// Pressed on a linked cut's link icon: the link window (I-25). Null
  /// keeps the icon display-only.
  final void Function(BuildContext context, CutId cutId)? onOpenCutLinks;

  /// Movie-end drag hooks (UI-R20 #3); null hides the end grip (the line
  /// still shows).
  final StoryboardMovieEndCallbacks? movieEnd;

  /// Frame-axis zoom, owned by the host (the panel header's shared zoom
  /// slider drives it).
  final double pixelsPerFrame;

  /// The host's zoom writer — the readout's and the zoom keys' — which a
  /// pinch on the sheet writes through too (F-506). Null names no zoom, and
  /// fingers only move the sheet.
  final ValueChanged<double>? onPixelsPerFrameChanged;

  /// How the rulers count (I-81), picked from the grid's top-left corner —
  /// and the cut totals with them: frames (`48`) or seconds+frames (`2+0`)
  /// ([showSeconds]).
  final FrameRulerView rulerView;

  /// The conte book's pages — where the page view's ruler starts again
  /// (I-81-Q3 「콘티용지패널의 페이지 기준」); null off it.
  final TimelineRulerPages? rulerPages;

  /// Whether a length reads as seconds+frames ([FrameRulerView.seconds]).
  bool get showSeconds => rulerView.seconds;

  /// The pick itself, in the corner over the layer-axis scrollbar (it
  /// used to be a command-bar button shared with the timeline). Null
  /// leaves the corner blank.
  final ValueChanged<FrameRulerView>? onRulerViewChanged;

  /// This rail's window size, set by the splitter beside it and persisted
  /// by the workspace. Null = a session-local one of our own.
  final LayerRailExtent? railExtent;

  /// Where the FRAME axis stands, in pixels — kept by the host beside
  /// [railExtent] because it has to outlive this panel (F-143: a fold
  /// remounted it until 09-28, and the offset that lived here went with it)
  /// and because the folded row turns it. Null = a session-local one of our
  /// own, as with the rail.
  final ValueNotifier<double>? frameAxisOffset;

  /// Where the LAYER axis stands, in pixels down the rows — the project's,
  /// saved with it (F-267), as the timeline's rows are: born there, and
  /// followed ([followKeptAxis]). Null = nobody keeps it; the rows start at
  /// the top.
  final ValueNotifier<double>? layerAxisOffset;

  final ProjectFrameRate projectFrameRate;

  /// Track-global frame the playhead line sits on (playback position while
  /// playing, the active cut's playhead otherwise) — a LISTENABLE, the
  /// cursor-layer pattern (W4): only the playhead overlay, the ruler and the
  /// track rows' lane labels (V and S — their keys are the track's)
  /// subscribe, so scrub moves and playback ticks never rebuild the panel's
  /// strips/blocks/rails. Null (or a null value) hides the line.
  final ValueListenable<int?>? playheadFrame;

  /// The cut under the playhead — the session's one answer for the cut being
  /// looked at, moving on crossings only. Its plate wears the standing wash
  /// (F-248); null where none is wired.
  final ValueListenable<CutId?>? cutUnderPlayhead;


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
  final ReadyRunsIn? readyRunsIn;

  /// The cut blocks' panel pictures ([StoryboardThumbnails]: asked while
  /// the blocks paint, and a landed one repaints them). The image stays
  /// OWNED BY THE RESOLVER — blocks paint it without disposing. Null hides
  /// the thumbnail strip.
  final StoryboardThumbnails? thumbnails;

  /// Why an SE row's sound cannot be played — its block red, with a
  /// warning line saying why (`PlaybackRig.soundCannotPlay`).
  final SoundCannotPlay? Function(String filePath)? soundCannotPlay;

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

  // ↩️The S rows' and the V rows' twirls, and the groups under them, came
  // in sets of this rail's own — S rows by `<trackId>-<slot>`, V rows by
  // track id, a V effect's group by `<trackId>-fx-<effectId>` — that the
  // host kept outside the document, and an S row twirled apart from the very
  // row the timeline twirls. They are the rows' since F-360's second half:
  // an S row's are its SE row's, read in [expandedLaneLayerIds] and
  // [expandedLaneGroupKeys] as the timeline reads that row's, and a V row's
  // its track's, read off the track (`Track.lanesExpanded`,
  // `Track.expandedLaneGroups`) — both turned by [onToggleLayerLanes] and
  // [onToggleLaneGroupKey], the V row by its lane carrier.

  /// Lane edit hooks for the V track's OWN lanes — its fx chain (R4b): the
  /// layer rows' own verbs, handed the row's lane carrier
  /// ([trackTransformLaneCarrierId]), which they send home to the track —
  /// at GLOBAL frames (one undo per edit), no cut needed. Null =
  /// display-only.
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

  /// A5-3② — the SPAN half of ⑨'s select-then-move.
  ///
  /// [rowDragHooks]'s three selection hooks only ARM a selection (they say
  /// whether this press starts one and where it anchors); growing it as the
  /// pointer crosses rows is this. Null leaves a press selecting the single
  /// row it landed on, which is still the right FIRST phase — but the rail
  /// then cannot select a range, so it is wired wherever the hooks are.
  ///
  /// [rows] are the rows this rail DRAWS, every track's, by the address each
  /// is stood on ([_StoryboardSheet.rows]) — 🗣️F-322 (유저 2026-10-09):
  /// 「레이어의 선택범위 작동안하고 … 타임라인이랑 완벽통일」. ↩️It was the S
  /// rows' alone, so a span from an S row stopped at the V row and no other
  /// row of this rail started one.
  final void Function(List<TimelineRowAddress> rows, int rowDelta)?
  onRowSelectionSpan;

  /// The rows the row selection holds — drawn over the rail as the
  /// timeline's rail draws them, one band over each run
  /// ([TimelineRowSelectionBands]). A listenable rather than a value: the
  /// selection grows per pointer move inside a gesture, and only the band
  /// has to hear it.
  final ValueListenable<List<TimelineRowAddress>>? rowSelection;

  /// Lane edit hooks for the S rows' Transform lanes — the lane verbs on
  /// the TRACK's S rows, handed [playheadFrame]'s global frames. Null =
  /// display-only.
  final PropertyLaneEditCallbacks? layerLaneEdit;

  /// …and for a projection row's lanes (I-73 ④ⓔ): the lane verbs on the
  /// layer of the cut the session stands in, handed [cutFrameCursor]'s
  /// frames of its own — the timeline's lane edits, on the timeline's axis.
  /// Null = display-only.
  final PropertyLaneEditCallbacks? cutLaneEdit;

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

  /// Whether this device has the plugin an effect is of — the effect
  /// headers of one it has not grey, as the timeline's do (I-132-Q28).
  /// Null greys none.
  final bool Function(FxPluginDescription plugin)? hasFxPlugin;

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

  /// The camera row's path button — the timeline's camera row's, which this
  /// rail's camera row is (I-89 ④).
  final Future<void> Function(BuildContext anchorContext)? onOpenCameraPath;

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

  /// The timeline rows' onion on this rail's rows — the SAME session verb
  /// the timeline wires. Only a conte row's kind ghosts, and its onion is
  /// its head's, one for the track's cuts (🗣️I-89-Q22, 유저 2026-10-16:
  /// 「어니언도 콘티행 기본적으로 버튼 글로벌이니까 넣음」).
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;

  /// A LIVE read of a row's onion — see [layerOnTimesheetOf].
  final bool Function(LayerId layerId)? layerOnionSkinEnabledOf;

  /// A LIVE read of a layer’s own eye — see [layerOnTimesheetOf].
  final bool Function(LayerId layerId)? layerEyeOnOf;

  /// A LIVE read of a row's twirl — an S row's by its layer, a V row's by
  /// its lane carrier — for the same reason as [layerOnTimesheetOf]: a
  /// press writes it, and the new value reaches this widget only on the
  /// next build, which is a frame too late for a bulk-drag that started on
  /// one of those buttons.
  final bool Function(LayerId layerId)? layerLanesOpenOf;

  final LayerFxState Function(LayerId layerId)? layerFxStateOf;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// A conte row's BLEND, picked on its head — the timeline rail's own
  /// verb (I-73). The conte rows' heads are the timeline's rows, and they
  /// are mounted while the host wires them whole: this, the eye, the
  /// opacity and the label ([_StoryboardRowsAndLabels.conteLabelRow]).
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;

  /// The bases whose attach group is folded, and the fold's verb — the
  /// timeline rail's own pair. A conte row's twirl folds the attach rows
  /// riding it, in every cut at once: the head is one.
  final Set<LayerId> collapsedAttachBaseIds;
  final ValueChanged<LayerId>? onToggleAttachGroup;

  /// A LIVE read of a row's group fold — see [layerOnTimesheetOf].
  final bool Function(LayerId layerId)? groupFoldOpenOf;

  /// The rows whose property lanes are twirled down, and the twirl's verb —
  /// the timeline rail's own pair (I-73 ④ⓔ). A projection row's head is
  /// the timeline's row, and its twirl is that row's: the camera row's,
  /// twirled on its head, is every camera of the track's, as the head is
  /// one.
  final Set<LayerId> expandedLaneLayerIds;
  final ValueChanged<LayerId>? onToggleLayerLanes;

  /// The lane GROUPS twirled open inside those rows, and their twirl — the
  /// timeline rail's own pair, by [laneGroupKey]: a conte row's Transform
  /// and effect groups twirl with the timeline's (I-73 ④ⓔ), in every cut
  /// of the track at once.
  final Set<String> expandedLaneGroupKeys;
  final ValueChanged<String>? onToggleLaneGroupKey;

  /// A LIVE read of a lane group's twirl, by its header lane — see
  /// [layerOnTimesheetOf].
  final bool Function(LayerId layerId, String headerLaneId)? laneGroupOpenOf;

  /// The header graphs open over those groups, and their verbs — the
  /// timeline rail's own (I-89 ①): a lane this rail draws is seated in its
  /// group's graph as the timeline's rows are ([seatLaneGraphs]). Null
  /// [laneGraphVerbs] mounts no graph button.
  final LaneGraphsView laneGraphs;
  final LaneGraphVerbs? laneGraphVerbs;

  /// A LIVE read of [laneGraphs] — for the column sweep, as
  /// [layerOnTimesheetOf] is: a press on a graph or pin button opens it,
  /// and the new set reaches this widget only on the next build.
  final LaneGraphsView Function()? laneGraphsNow;

  /// A LIVE read of what the rail lays its rows from ([railInputs]) — for
  /// the folded row ([StoryboardRowsChannel.foldedRowFor]), which the
  /// workspace builds before this widget is handed the new ones. Null
  /// reads [railInputs].
  final StoryboardRailInputs Function()? railNow;

  /// What the rail lays its rows from, as this widget was handed it.
  StoryboardRailInputs get railInputs => (
    project: project,
    activeCutId: activeCutId,
    selectedRow: selectedRow,
    rowSelection: rowSelection,
    expandedLaneLayerIds: expandedLaneLayerIds,
    expandedLaneGroupKeys: expandedLaneGroupKeys,
    laneGraphs: laneGraphs,
    hiddenSections: hiddenSections,
    rowFilter: rowFilter,
    collapsedAttachBaseIds: collapsedAttachBaseIds,
    layerFxStateOf: layerFxStateOf,
    trackFxStateOf: trackFxStateOf,
    poseDisplaySize: poseDisplaySize,
    trackLaneHeight: trackLaneHeight,
  );

  /// The timeline's rail legend over this panel's rail (UI-R5): same
  /// bulk flyouts + master opacity bar, acting on the ACTIVE cut's layers
  /// through the same session hooks. Null renders a display-only legend.
  final LayerLegendCallbacks? legend;

  /// Where this panel holds up the menus its legend header opens, written
  /// each time it is built — what a key presses one of (I-40).
  final ViewHand<RailLegendHold>? legendHand;

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

  /// The SE and camera sections left off the rail — the set the timeline's
  /// grids read, toggled from the same legend menu ([onToggleSection]).
  ///
  /// 🗣️F-199 (유저 2026-09-27): 「콘티패널도 타임라인이랑 동일하게 se나
  /// 카메라섹션 접을수있게 로직통일」. The S rows are the SE section and the
  /// transition row the camera section's ([timelineSectionForLayerKind]); the
  /// V row belongs to none and always shows. ↩️The legend here carried the
  /// menu all along, greyed: it was never handed the toggle.
  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

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

  /// Whether every row the legend's onion sweep acts on ghosts — its icon
  /// in the accent, as the timeline's legend reads it (F-443).
  final bool legendOnionSkinOn;

  /// R9 #21: the V row's TRACK column — the fx master over the track's fx
  /// work. Null keeps the column reserved and empty. (↩️The row's eye and
  /// its static opacity were handed in beside it until I-73 — see
  /// [StoryboardTrackLabelRow.trackFxState].)
  final LayerFxState Function(Track track)? trackFxStateOf;
  final ValueChanged<Track>? onToggleTrackFx;

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

  /// An S row's group header switch and reset — the timeline's own verbs
  /// (F-101). Null leaves the switch inert and hides the reset.
  final void Function(Layer layer, PropertyLaneRow lane)?
  onToggleLaneGroupEnabled;
  final void Function(Layer layer, PropertyLaneRow lane)? onResetLaneGroup;

  /// A LIVE read of a lane group's switch, by its header lane — for the
  /// column sweep, as [layerOnTimesheetOf] is.
  final bool? Function(LayerId layerId, String headerLaneId)? laneGroupOnOf;

  // The TRANSITION row (O.L / F.I / F.O). This panel is the ONE surface that
  // authors it: the row is track-owned and its spans address the global frame
  // axis, so the cut timeline shows the same spans READ-ONLY (user's law —
  // the global track is where transitions are made). Null hooks keep the row
  // display-only here too, which is what a host with no session does.

  /// The vocabulary lookup the marks draw from (id → def), so the row paints
  /// the same wedge/bowtie the cut's direction row does. Null leaves the
  /// spans unmarked.
  final CameraInstructionDef? Function(String instructionId)? transitionDefById;

  /// [track]'s transition row — or a drag's form of it — the way it is
  /// SHOWN: every span named by the cuts it joins (F-229). Null shows the
  /// row as stored, which is what a host with no session does.
  final Layer Function(Track track, Layer row)? transitionRowShown;

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

  /// 🗣️F-255 (유저 2026-10-01): 「이름변경 입구 확대. 지금 프레임블록이랑
  /// 레이어라벨 더블클릭하면 이름편집인데 콘티블록이나 컷블록에도
  /// 통일적용」 — a CUT block double-clicked on its own paper, at this
  /// GLOBAL frame of [TrackId]'s row: the frame blocks' same-cell double
  /// tap, on the cut row.
  final void Function(TrackId trackId, int globalFrame)? onEditCutBlock;

  /// …and a CONTE block double-clicked, on the conte row: the cell it is,
  /// of its cut's storyboard row [LayerId], at this GLOBAL frame.
  final void Function(TrackId trackId, LayerId layerId, int globalFrame)?
  onEditConteBlock;

  /// Whether a conte block's cel holds a picture, cut by cut — the
  /// timeline's unworked-block tint on the conte rows (F-357). Null = no
  /// tint.
  final ConteCelContent? conteCelContent;

  /// How many steps on the playing run shows [cutId]'s frame [frameIndex]
  /// — what the conte rows' substrate tiles are let go by
  /// (`PlaybackRig.stepsUntilShown`). Null where no run reaches the host.
  final int? Function(CutId cutId, int frameIndex)? stepsUntilShown;

  /// A press on the CAMERA row's cells that lands in a cut (I-73 ④): the
  /// cut whose own frames hold the pointer — over an O.L, the one on the
  /// line it is on — and the frame of its own there. A press where no cut's
  /// own frames are goes to [onRowFramePress], as every row's does.
  final StoryboardCameraCutPress? onCameraCutPress;

  /// …and a double click on its cell: the timeline camera row's own — the
  /// key there opens, an empty cell is keyed — on the cell the first click
  /// stood the session on.
  final VoidCallback? onEditCameraCell;

  /// The frame of its own the cut the session stands in is on — what a
  /// projection row's lane labels read their values at, as the timeline's
  /// lane labels do (I-73 ④ⓔ). Null reads frame 0.
  final ValueListenable<int>? cutFrameCursor;

  /// A seek to a frame of [CutId]'s own — the key navigator (◆) of a
  /// projection row's lane label, which walks the keys of the cut the
  /// session stands in.
  final void Function(CutId cutId, int ownFrame)? onSeekCutFrame;

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
  final List<List<List<Widget>>> trackGlobalStripRowsByTrack;
}
class _StoryboardPanelState extends State<StoryboardPanel> {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.projectFrameRate.countingBase;

  /// The host's record of the layer axis ([StoryboardPanel.layerAxisOffset])
  /// — read ONCE, as the frame axis's is.
  late final ValueNotifier<double>? _keptLayerAxis = widget.layerAxisOffset;

  /// The rows, born where the project left them (F-267). The rows and the
  /// frames are the storyboard: one sheet, dragged both ways at once
  /// (F-351).
  late final TwoAxisScrollController _verticalController =
      TwoAxisScrollController(bornAt: _keptLayerAxis);

  /// Lets go of [_keptLayerAxis] ([followKeptAxis]).
  late final VoidCallback _letGoOfKeptRows;

  /// Born where the axis stands ([TwoAxisScrollController.bornAt]), as the
  /// timeline grids' controllers are.
  late final TwoAxisScrollController _horizontalController =
      TwoAxisScrollController(bornAt: _horizontalScrollOffset);

  /// The fallback rail extent for hosts that keep none of their own.
  LayerRailExtent? _ownedRailExtent;

  // ── the rail rows and lanes: their own object ───────────────────────
  //
  // A collaborator (storyboard/storyboard_rail_rows.dart, a part of this library). The
  // State keeps the entry points its build tree calls.
  late final _StoryboardRailRows _railRows = _StoryboardRailRows(this);

  // ── the rail's column sweep: its own object, in its own file ────────
  //
  // A collaborator (storyboard/storyboard_rail_sweep.dart, a part of this
  // library): the timeline's one list over these rows.
  late final _StoryboardRailSweep _sweep = _StoryboardRailSweep(this);

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

  // ── the rows' window: its own object ────────────────────────────────
  //
  // A collaborator (storyboard/storyboard_rows_window.dart, a part of this
  // library): the rows built where the view stands.
  late final _StoryboardRowsWindow _rowsWindow = _StoryboardRowsWindow(this);

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
    viewportFillFrames: () => _viewportFillFrameCells,
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

  /// This panel's legend, held up for as long as it is mounted: a panel
  /// built anew comes up before this one goes, so this one puts down only
  /// its own ([ViewHand] — card `rail-legend-menus-lost-to-an-old-goodbye`).
  final RailLegendHold _legend = RailLegendHold();
  late final ViewHand<RailLegendHold>? _legendKeeper = widget.legendHand;

  @override
  void initState() {
    super.initState();
    _legendKeeper?.up(_legend);
    _horizontalController.addListener(_frameAxis.handleScroll);
    _verticalController.addListener(_rowsWindow.handleScroll);
    _letGoOfKeptRows = followKeptAxis(
      _verticalController,
      _keptLayerAxis,
      isMounted: () => mounted,
    );
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
    foldedRowFor: _folded.rowFor,
  );

  /// The row the storyboard stands on, as the folded overlay shows it.
  late final _StoryboardFolded _folded = _StoryboardFolded(this);

  /// R5: the same "bring the selection back into view" tick the timeline
  /// answers, by the timeline's own function — the strips run on the GLOBAL
  /// frame axis, so the playhead frame is what the frames aim at, and the
  /// row you stand on is what the rows do (F-361,
  /// [_StoryboardStanding.standingRowItem]). One S row of margin, as the
  /// timeline keeps one layer row.
  ///
  /// After the frame, because the row list this pass built is what the
  /// row-side reveal counts in.
  void _handleRevealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      revealSelectionOnBothAxes(
        frames: (
          controller: _horizontalController,
          extent: widget.pixelsPerFrame,
          at: widget.playheadFrame?.value ?? -1,
        ),
        rows: (
          controller: _verticalController,
          item: _standing.standingRowItem(_rowHeights.se),
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
    // anchors. ⛔The timeline grids' own call, not a third spelling of it:
    // this jump was the policy written out again, and the one that did not
    // hear the fold rule the grids' call keeps.
    applyZoomAnchoredScroll(
      _horizontalController,
      oldPixelsPerFrame: oldWidget.pixelsPerFrame,
      newPixelsPerFrame: widget.pixelsPerFrame,
      anchorFrame: widget.playheadFrame?.value,
    );
  }

  TimelineScale get _scale => TimelineScale(
    pixelsPerFrame: widget.pixelsPerFrame,
    minBlockWidth: StoryboardPanel._minBlockWidth,
  );

  @override
  void dispose() {
    _legendKeeper?.down(_legend);
    widget.rowsChannel?.unbind(this);
    widget.revealSelectionTick?.removeListener(_handleRevealSelection);
    widget.playheadFrame?.removeListener(_handlePlaybackPage);
    _horizontalController.removeListener(_frameAxis.handleScroll);
    _verticalController.removeListener(_rowsWindow.handleScroll);
    _rowsWindow.dispose();
    _frameAxis.dispose();
    _letGoOfKeptRows();
    _standing.dispose();
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
      final right = scale.blockEndFor(entry.startFrame, entry.duration);
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

  /// [header], its menus handed to whoever presses its rows by key (I-40):
  /// the very menus it opens, counted on this panel's rows.
  TimelineLayerControlsHeader _publishedLegend(
    TimelineLayerControlsHeader header,
  ) {
    _legend.menus = header.legend == null ? null : header.menus;
    return header;
  }

  Set<LayerMark> _legendMarksInUse() => {
    for (final layer in _legendLayers())
      if (layer.mark != LayerMark.none) layer.mark,
  };

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
    // ★FOLDED, NO BODY (유저 2026-10-14: 「열려있을때만 지어지는게
    // 맞는구조」 · 「이건 모든 패널 공통적인 사항이야」). The State stays for
    // the rows it hands the folded row and the walk ([_bindSheet]), read off
    // the project as it stands. Opened, the body is built where the kept
    // axes stand ([TwoAxisScrollController.bornAt]).
    if (PanelCollapsedScope.of(context)) {
      return const SizedBox.shrink();
    }
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
      // R26 #34: the canvas's pan moves the conte panel too, through the
      // timeline grids' one driver.
      child: PanelPanDriver(
        controllers: [_verticalController, _horizontalController],
        // The panel fills what it is given — its column is as tall as it
        // may be and stretched — and says so, for the body below to be
        // laid out alone.
        child: SizedBox.expand(
          child: ValueListenableBuilder<double?>(
            valueListenable: _railRows._railExtent,
            // Every notify runs this again: laid out, painted and described
            // alone, or each one rebuilt the nodes of the rows in it (I-57).
            builder: (context, _, _) => LaidOutAlone(builder: _sizedBody),
          ),
        ),
      ),
    );
  }

  /// The body for the size the panel is given.
  Widget _sizedBody(BuildContext context, BoxConstraints constraints) {
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
    // The rows' view, as [_scrollArea] is laid — the body less the pinned
    // ruler band over it and the scrollbar row under it: an enlarged header
    // graph stands as far as it lets one (I-89 ③D), so it is recorded
    // before anything lays a row, and the rows are laid afresh.
    _middleViewportHeight = constraints.hasBoundedHeight
        ? (constraints.maxHeight -
                  StoryboardPanel._rulerHeightIn(context) -
                  StoryboardPanel._bottomScrollbarRailHeight)
              .clamp(0.0, double.infinity)
              .toDouble()
        : 0.0;
    _railRows.forgetLaneSeating();
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
      viewExtentPx: _stripViewportWidth,
    );
    // SE rows are built OUTSIDE the drag-preview builder from the RAW
    // project (R10-③): their content is track-global, so a cut trim
    // never changes them — handing the per-step rebuild IDENTICAL row
    // instances lets Flutter skip their whole subtrees (waveform
    // painters included). The trade: an in-flight trim doesn't slide
    // their cut-boundary marks until release. SE comma drags edit the
    // ACTIVE layer through the timeline gates, unaffected here.
    final trackGlobalStripRowsByTrack =
        _railRows._trackGlobalStripRowsByTrack();
    // The body builds from the COMMITTED project, once. The drag
    // preview is read further down, at [_trackGroupSection] — see the
    // measurement in its doc for why the difference is not small.
    return _buildBody(context, widget.project, trackGlobalStripRowsByTrack);
  }

  /// Frame cells the strips viewport needs to be fully papered (UI-R12
  /// #16) — recorded by [_sizedBody]. Zero until layout.
  int _viewportFillFrameCells = 0;

  /// The strip column's viewport width — the shared window policy's other
  /// input (UI-R16). Recorded in build beside [_viewportFillFrameCells],
  /// which already derived from it.
  double _stripViewportWidth = 0;

  /// The rows' viewport height — what an enlarged header graph stands to.
  /// Recorded in build beside [_stripViewportWidth]; zero until layout.
  double _middleViewportHeight = 0;

  /// The rail's layout ceiling for this pass (see
  /// [LayerRailExtent.windowExtent]); null in an unbounded host.
  double? _availableRailWidth;

  /// Render extent (UI-R12 #16 contract) — the follower's
  /// ([TimelineFrameAxisFollower.renderedFrameCount]). ↩️The old always-120
  /// resting runway is gone, so past-content cells vanish once out of view
  /// and the scrollbar stops at the built cells.
  int get _renderedFrames => _frameAxis.renderedFrameCount;

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
    List<StoryboardTimelineLayoutEntry> layoutEntries,
    TimelineScale scale,
  ) {
    return math.max(
      _timelineContentWidth(layoutEntries, scale),
      scale.leftForFrame(_renderedFrames),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Project project,
    List<List<List<Widget>>> trackGlobalStripRowsByTrack,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final layoutEntries = buildStoryboardTimelineLayout(project);
    final scale = _scale;
    final totalFrames = _totalFrames(project, layoutEntries);
    // Endless frame axis (UI-R12 #16): cells cover the view — the cuts,
    // whatever the viewport needs to read papered, and whatever the ruler
    // edge-drag has materialized. No resting runway beyond that.
    final renderedFrames = _renderedFrames;
    final contentWidth = _contentWidthFor(layoutEntries, scale);
    // The playhead + green bar repaint through their own listenables (the
    // cursor-layer pattern) — the ruler's overlay PAINTER and the playhead
    // overlay subscribe below, nothing else in this build does.
    final playheadListenable = widget.playheadFrame;

    // The panel-private frame (border + all-6 padding) is GONE (UI-R10
    // #15): the timeline hosts its grid edge-to-edge under the command
    // bar, and that inset was exactly the odd top-left padding that made
    // the two rails read differently. The body is the timeline's THREE ROWS
    // (UI-R10 #21), laid by the same widgets (`timeline_grid_frame.dart`,
    // F-459): legend, corner and ruler on top; the rail, the layer-axis
    // bar and the strips in the middle; the two horizontal bars pinned
    // on the bottom.
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
              // BOTTOM row (UI-R10 #21): the rail's bar and the PINNED
              // horizontal scrollbar (it used to live inside the vertical
              // scroll content and scrolled away with it).
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

  Positioned _railGrip(_StoryboardBodyFrame frame) => timelineGridGrip(
    railWindowExtent: frame.railWindowExtent,
    splitter: LayerRailSplitter(
      key: const ValueKey<String>('storyboard-rail-splitter'),
      axis: Axis.horizontal,
      extent: _railRows._railExtent,
      naturalExtent: _naturalRailWidth,
      availableExtent: frame.availableRailWidth,
    ),
  );

  Widget _bottomScrollbarRow(_StoryboardBodyFrame frame) {
    return TimelineGridBottomRow(
      keyPrefix: 'storyboard',
      barWidth: StoryboardPanel._scrollbarLaneWidth,
      height: StoryboardPanel._bottomScrollbarRailHeight,
      // The rail's own bar — the panel's second of three.
      railBar: LayerRailScrollbar(
        axis: Axis.horizontal,
        rail: _railRows._railExtent,
        naturalExtent: _naturalRailWidth,
        availableExtent: frame.availableRailWidth,
        laneExtent: StoryboardPanel._bottomScrollbarRailHeight,
        keyPrefix: 'storyboard',
      ),
      // Laid out alone: every notify runs it again (I-57).
      frameBar: SizedBox(
        height: StoryboardPanel._bottomScrollbarRailHeight,
        child: LaidOutAlone(
          builder: (context, constraints) => TimelineHorizontalScrollbarRail(
            key: const ValueKey<String>('storyboard-horizontal-scrollbar'),
            controller: _horizontalController,
            viewportWidth: constraints.maxWidth,
            contentWidth: frame.contentWidth,
            height: StoryboardPanel._bottomScrollbarRailHeight,
          ),
        ),
      ),
    );
  }

  /// The grid sheet off the rail's own row table, on the ground the law
  /// hands down — rebuilt only where a drag moves a cut's start (the
  /// projection rows' dashes, [_StoryboardRailRows.gridRows]).
  Widget _gridSheet(BuildContext context, _StoryboardBodyFrame frame) {
    final ground = TimelineGridLaw.maybeOf(context)?.ground;
    final preview = widget.dragPreview ?? _noDragPreview;
    return SlicedListenableBuilder<TimelineGridRows>(
      listenable: preview,
      slice: () => ground == null
          ? TimelineGridRows.none
          : _railRows.gridRows(
              frame.project.tracks,
              ground,
              preview: preview.value,
            ),
      builder: (context, rows) => TimelineGridSheet(
        key: const ValueKey<String>('storyboard-grid-sheet'),
        frameCellExtent: frame.scale.pixelsPerFrame,
        rows: rows,
      ),
    );
  }

  Expanded _scrollArea(_StoryboardBodyFrame frame) {
    final playheadListenable = frame.playheadListenable;
    return Expanded(
      // Laid out alone: every notify runs it again (I-57).
      child: LaidOutAlone(
        builder: (context, middleConstraints) {
          final middleViewportHeight =
              middleConstraints.hasBoundedHeight
              ? middleConstraints.maxHeight
              : 0.0;
          return TimelineGridBodyRow(
            barWidth: StoryboardPanel._scrollbarLaneWidth,
            railWindowExtent: frame.railWindowExtent,
            bar: TimelineVerticalScrollbarRail(
              key: const ValueKey<String>('storyboard-vertical-scrollbar'),
              controller: _verticalController,
              viewportHeight: middleViewportHeight,
              contentHeight: middleViewportHeight,
            ),
            body: ScrollConfiguration(
              // The pinned rail IS this area's scrollbar — the desktop
              // auto-overlay would double it (UI-R10 #22 unification).
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: TwoAxisDrag(
                axes: [_verticalController, _horizontalController],
                zoom: sheetZoom(
                  widget.pixelsPerFrame,
                  widget.projectFrameRate,
                  widget.onPixelsPerFrameChanged,
                ),
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
                                RailColumnSwipe<TimelineDisplayRow>(
                                  axis: Axis.vertical,
                                  columns: _sweep.columns(),
                                  rowsIn: _sweep.rowsIn,
                                  // Laid by the rows' window, as the strips.
                                  child: _rowsWindow.laidColumn(
                                    _rowsWindow.railKeep,
                                    (rowsOf) => [
                                      // Track groups in TIMELINE order (R6
                                      // B3): the S rows sit ABOVE their V
                                      // track, slots bottom-up like the
                                      // timeline (top-down S2, S1, V — R7-④).
                                      for (
                                        var index = 0;
                                        index < frame.project.tracks.length;
                                        index++
                                      )
                                        ..._railRows.railRowsForTrack(
                                          frame.project.tracks[index],
                                          index,
                                          rowsOf(index),
                                        ),
                                    ],
                                    // One pass of the rail's keep: a row it
                                    // stops drawing is let go of.
                                    newPass: _rows.railPass,
                                  ),
                                ),
                                // The row selection, over the LAYER area
                                // as the timeline's rail lays it (A2) —
                                // its own listener, since a span grows
                                // per pointer move inside a gesture.
                                if (widget.rowSelection case final selection?)
                                  Positioned(
                                    left: layerSectionLabelSlotWidth,
                                    top: 0,
                                    right: 0,
                                    bottom: 0,
                                    child:
                                        ValueListenableBuilder<
                                          List<TimelineRowAddress>
                                        >(
                                          valueListenable: selection,
                                          builder: (context, selected, _) =>
                                              _railRows.rowSelectionBands(
                                                selected,
                                              ),
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
                        const TimelineGridRailGap(
                          barWidth: StoryboardPanel._scrollbarLaneWidth,
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
                                    // 🚨F-446 (10-24): on a tick layer — a
                                    // cut move's step moves the dashes of
                                    // the cuts' starts, and rebuilt in the
                                    // scroll area's layout scope it laid
                                    // the area out and repainted it whole.
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: TickLayer(
                                          child: Builder(
                                            builder: (context) =>
                                                _gridSheet(context, frame),
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
                                      Positioned.fill(
                                        child: StoryboardPlayheadTint(
                                          playhead: playheadListenable,
                                          pixelsPerFrame:
                                              frame.scale.pixelsPerFrame,
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
                                      _movieEndMarks(frame),
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
            ),
          );
        },
      ),
    );
  }

  /// The movie-end line through the strips and its grip, following the
  /// drag (F-18) — on a tick layer filling the strips ([TickOverlay]), as
  /// the timeline's cut end rides its grid, ruler and sheet (F-244).
  /// 🚨F-446 (10-24): bare in the strips' stack, each step's line moved
  /// that stack's child and laid the scroll content and both viewports out
  /// again, repainting the storyboard's body around them.
  Widget _movieEndMarks(_StoryboardBodyFrame frame) => TickOverlay(
    children: [
      ValueListenableBuilder<TimelineDragPreview?>(
        valueListenable: widget.dragPreview ?? _noDragPreview,
        builder: (context, preview, _) {
          final live = timelineCutEndPreviewFrameCount(
            preview: preview,
            cutId: null,
            playbackFrameCount: frame.totalFrames,
            movieEndUnder: _movieEndUnder,
          );
          return Positioned(
            key: const ValueKey<String>('storyboard-cut-end-line'),
            left: frame.scale.leftForFrame(live),
            top: 0,
            bottom: 0,
            width: 2,
            child: IgnorePointer(
              child: ColoredBox(color: AppColors.danger),
            ),
          );
        },
      ),
      if (widget.movieEnd != null)
        _StoryboardEndLineHandle(
          dragPreview: widget.dragPreview,
          committedTotalFrames: frame.totalFrames,
          movieEndUnder: _movieEndUnder,
          scale: frame.scale,
          // Grabbed from the EMPTY side of the line, never straddling it:
          // everything left of the movie's end belongs to the content, and
          // the last cut's trailing edge grip is right there. Centring the
          // handle put a full-height opaque box over that grip and made it
          // unreachable.
          pixelsPerFrame: frame.scale.pixelsPerFrame,
          movieEnd: widget.movieEnd!,
        ),
    ],
  );

  Widget _pinnedRulerRow(_StoryboardBodyFrame frame) {
    final bandHeight = StoryboardPanel._rulerHeightIn(context);
    return TimelineGridHeaderRow(
      cornerKey: const ValueKey<String>(
        'storyboard-time-display-toggle-button',
      ),
      barWidth: StoryboardPanel._scrollbarLaneWidth,
      height: bandHeight,
      rulerView: widget.rulerView,
      onRulerViewChanged: widget.onRulerViewChanged,
      // The timeline's legend header over the rail (UI-R5
      // storyboard unification): same slots, same flyouts —
      // and now inside the rail's own window, so the legend is
      // cut exactly where the rows below it are.
      legend: LayerRailWindow(
        axis: Axis.horizontal,
        rail: _railRows._railExtent,
        naturalExtent: _naturalRailWidth,
        availableExtent: frame.availableRailWidth,
        child: SizedBox(
          width: _naturalRailWidth,
          child: _publishedLegend(TimelineLayerControlsHeader(
            // The storyboard rail states its OWN width, which
            // today is the same number as the timeline's and is
            // deliberately not the same constant (see
            // [StoryboardPanel.railWidthIn]). Widening it
            // adds no column here — `optionalRailColumns` is a host
            // answer, not something derived from the width — so
            // the extra width lands in the NAME, which is where
            // a track wants it.
            //
            // And the host's answer is said here outright, not left to
            // whether a legend was handed in: the rows below keep the
            // blend slot either way ([StoryboardPanel.optionalRailColumns]),
            // and a heading that came and went with the legend would stand
            // a column off them.
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
            optionalColumns: StoryboardPanel.optionalRailColumns,
            rowFilter: widget.rowFilter,
            hiddenSections: widget.hiddenSections,
            onToggleSection: widget.onToggleSection,
            marksInUse: _legendMarksInUse,
            kinds: StoryboardPanel.railKinds,
            visibilitySoloEnabled: widget.visibilitySoloEnabled,
            displayedLayerIds: widget.legend == null
                ? null
                : _legendDisplayedLayerIds,
            displayedOpacity: widget.legendOpacityValue,
            displayedOnionSkinOn: widget.legendOnionSkinOn,
            // ㉒: the lane column's header verb, same as the
            // timeline's.
            anyLanesExpanded: _railRows._anyLanesExpanded,
            onExpandAllLanes: _railRows.hasLaneTwirls
                ? _railRows.expandAllLanes
                : null,
            onCollapseAllLanes: _railRows.hasLaneTwirls
                ? _railRows.collapseAllLanes
                : null,
          )),
        ),
      ),
      // Laid out alone: every notify runs it again (I-57).
      ruler: SizedBox(
        height: bandHeight,
        child: LaidOutAlone(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;
            _frameAxis.rereadAfterLayout();
            return ClipRect(
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
                    readyRunsIn: widget.readyRunsIn,
                    onEdgeAutoPan: _scroll.autoPanRulerEdge,
                    framesPerSecond: _countingFps,
                    rulerView: widget.rulerView,
                    rulerPages: widget.rulerPages,
                  ),
                ),
              ),
            );
          },
        ),
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
    required this.readyRunsIn,
    this.onEdgeAutoPan,
    this.framesPerSecond = 24,
    this.rulerView = FrameRulerView.frames,
    this.rulerPages,
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

  final ReadyRunsIn? readyRunsIn;

  /// Edge auto-pan sink (UI-R12 #16, unified with the timeline ruler): a
  /// scrub within 24px of the viewport edge reports a pan delta; the
  /// panel jumps the horizontal axis (overshooting rightward so growth
  /// materializes frames past the built extent).
  final ValueChanged<double>? onEdgeAutoPan;

  /// The two-line ruler's parameters (UI-R10 #27, unified: the seconds
  /// display cycles 1..fps here exactly like the timeline — UI-R11 #10).
  final int framesPerSecond;
  final FrameRulerView rulerView;
  final TimelineRulerPages? rulerPages;

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
        // R26 #34: a press that pans is the pan's, not a scrub.
        if (canvasPressPans(canvasPressButtons(event))) {
          return;
        }
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
                rulerView: widget.rulerView,
                pages: widget.rulerPages,
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
                  readyRunsIn: widget.readyRunsIn,
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

/// The conte row's height — the track's conte layers as one row of frame
/// blocks under the V row (I-73). Same regulation as an S row: it is the
/// timeline's own row, drawn by the timeline's own painter.
const double _conteRowHeight = 30;

/// The camera row's height — the track's cuts' camera layers as one row at
/// the top of its CAM section (I-73 ④). The S row's regulation for now:
/// 유저 2026-10-08, of the two lines an O.L splits it into, 「일단 행높이는
/// 진행해보고 결정하자」.
const double _cameraRowHeight = 30;

/// A twirled-down lane's height — every lane: the timeline draws all its
/// rows at one height, and the labels and the strips share it (the rail and
/// strips columns must stay height-synced).
/// ↩️The Audio lane stood taller as an enlarged waveform strip until F-101
/// made it the timeline's own lane (it went with I-140); the cut-fade
/// envelope's own height went with that row before.
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
typedef _StoryboardRowHeights = ({
  double se,
  double transition,
  double conte,
  double camera,
  double lane,
});

_StoryboardRowHeights _storyboardRowHeightsIn(BuildContext context) {
  final growth = timelineLayerRowGrowthIn(context);
  return (
    se: _seRowHeight + growth,
    transition: _transitionRowHeight + growth,
    conte: _conteRowHeight + growth,
    camera: _cameraRowHeight + growth,
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

/// The chrome a storyboard rail label that wears no layer sits in — the V
/// row's, and a projection row's while it has no head
/// ([_StoryboardHeadlessLabel]): the select target, the fixed-width cell
/// with its border and active tint, and the row's semantics node. A row
/// that wears a layer wears the timeline's own row ([_StoryboardRailHead]).
///
/// 🚨ONE shell for the rows it holds — three hand-copied heads once (the
/// audit's clone scan, 2026-09-03). [chromeless] is the track row's own
/// switch: a lane strip under it draws no border and no tint.
class _StoryboardLabelShell extends StatelessWidget {
  const _StoryboardLabelShell({
    required this.selectKey,
    this.rowKey,
    required this.onTap,
    this.onSettledPress,
    required this.height,
    required this.active,
    this.chromeless = false,
    required this.semanticsLabel,
    required this.child,
  });

  final Key selectKey;
  final Key? rowKey;
  final VoidCallback? onTap;

  /// Its press turned out to be a tap ([StoryboardPanel.onSettledPress]).
  final VoidCallback? onSettledPress;
  final double height;
  final bool active;
  final bool chromeless;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final select = onTap;
    final settled = onSettledPress;
    // The PICK rides the raw pointer, as the strips' and the timeline rows'
    // do (T10). ↩️It was the InkWell's tap: on the release, and 300ms late
    // once a double-tap recognizer joined its arena ([InstantTapRegion]
    // names that delay).
    final strip = InstantTapRegion(
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      onTap: (_) => select?.call(),
      // And when the press turned out to be a tap, the selection goes, as
      // on the timeline's rows.
      onSettledTap: settled == null ? null : (_) => settled(),
      child: _surface(context),
    );
    // 🚨THE WHOLE ROW IS 「레이어 쪽」, as the timeline's row states it
    // ([TimelineLayerControlsRow.build], 유저 확정 2026-08-30: 「레이어 쪽
    // 버튼은 탭다운, 헤더쪽은 손떼면」). ↩️Only this rail's swipe columns were
    // on the press, so its type button acted on the release while the twirl
    // and the fx switch beside it acted on the press (I-89 ①).
    return PressFireScope(fireOn: PressFire.down, child: strip);
  }

  Widget _surface(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ArenaTapHold(
      // The row BODY, not a control: a drag that starts here is the V row's
      // move (#1349 the V row's reorder), not a scroll — so no press claim
      // goes on it, which would undo that round.
      key: selectKey,
      // ⛔The timeline row's own: the pick is the region's above, and this
      // holds a tap in the arena so scroll slop over a row behaves the way
      // it always has. A display-only row holds none, inert as it was.
      holds: onTap != null,
      // The timeline row's plate too. The lit row is a NAME, as the
      // timeline's is (I-57): a key there while the row was lit, gone when
      // it was not, remade the row's content whenever the selection moved.
      child: RowPlate(
        key: rowKey,
        name: active ? 'storyboard-selected-row' : null,
        width: StoryboardPanel.railWidthIn(context),
        height: height,
        padding: const EdgeInsets.only(right: layerRailEndPadding),
        decoration: chromeless
            ? null
            : BoxDecoration(
                color: active
                    ? railSelectedRowColor(colorScheme)
                    : colorScheme.surface,
                border: Border(
                  left: BorderSide(color: colorScheme.outlineVariant),
                  right: BorderSide(color: colorScheme.outlineVariant),
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
        label: semanticsLabel,
        child: child,
      ),
    );
  }
}

/// The playhead's column on the playhead's frame — no solid edge line over
/// the blocks (user direction) — the timeline's own ([timelinePlayheadColumn],
/// F-212). It subscribes to the cursor itself, on a layer of its own
/// ([TickLayer]): a tick moves THIS overlay, the blocks never rebuild.
///
/// ONE tint for the panel's strips and for the row the storyboard folds
/// into (유저 2026-09-27, folded-row-playhead-during-playback-Q1: 「접힌
/// 오버레이도 재생헤드나 인덱스나 … 다 구조적으로 동기화」) — the folded
/// row had no playhead at all.
class StoryboardPlayheadTint extends StatelessWidget {
  const StoryboardPlayheadTint({
    super.key,
    required this.playhead,
    required this.pixelsPerFrame,
    this.firstFrame = 0,
  });

  /// The track frame the playhead stands on ([PlayheadCursors.trackFrame]).
  final ValueListenable<int?> playhead;

  final double pixelsPerFrame;

  /// The frame at this layer's left edge: 0 on the panel's strips, the
  /// window's first frame on the folded row, which lays out one screenful
  /// from there (F-143).
  final int firstFrame;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TickLayer(
      child: ValueListenableBuilder<int?>(
        valueListenable: playhead,
        builder: (context, frame, _) => Stack(
          children: [
            if (frame != null)
              timelinePlayheadColumn(
                axis: Axis.horizontal,
                frame: frame,
                cellExtent: pixelsPerFrame,
                origin: -timelineFrameEdge(firstFrame, pixelsPerFrame),
                columnKey: const ValueKey<String>('storyboard-playhead'),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A PROJECTION row's label while it has no head to wear (I-73) — a conte
/// seat no cut holds a row at, the camera row in a gap — or while the host
/// has not wired the heads' verbs: the row's name and its kind's glyph, on
/// the rail's shared column skeleton with every control slot reserved and
/// empty, stood on by the row's own address. With a head it is the
/// timeline's own row, one for every cut ([_StoryboardRailHead] — I-73 ③,
/// 유저 2026-10-08: 「콘티행도 동일하게 하고싶으니까 어태치
/// 접기펼치기버튼등 동일하게 할수있는거 다 넣는거 잊지말고」 · 「콘티레이어
/// 권고한대로 머리만 한벌 ok」).
///
/// ↩️It was the transition row's label first, and the S rows had one of
/// their own beside it; both wear the timeline's row now (I-89 ①).
class _StoryboardHeadlessLabel extends KeptPiece {
  const _StoryboardHeadlessLabel({
    required this.trackId,
    required this.rowId,
    required this.kind,
    required this.keyName,
    required this.name,
    required this.active,
    required this.height,
    this.chromeless = false,
    this.onSelectLayer,
    this.onSettledPress,
  });

  /// The track whose row this is — its keys' word.
  final TrackId trackId;

  /// The address the row is picked by: the conte row's
  /// ([trackConteRowId]), the camera row's ([trackCameraRowId]) — a row no
  /// one cut's layer names.
  final LayerId rowId;

  /// The row's kind — its type glyph.
  final LayerKind kind;

  /// The row's word in its keys: `storyboard-<keyName>-label-<track>`.
  final String keyName;

  /// The name the row prints.
  final String name;

  /// Whether this row is THE selected row (same highlight as every other).
  final bool active;

  /// The row's height where the panel is shown ([_StoryboardRowHeights]).
  final double height;
  final ValueChanged<LayerId>? onSelectLayer;

  /// Its press turned out to be a tap ([StoryboardPanel.onSettledPress]).
  final VoidCallback? onSettledPress;

  /// Drawn without its ground — the folded overlay's ([_StoryboardFolded]).
  final bool chromeless;

  /// What the row shows: its name and its glyph.
  ///
  /// 🚨I-57 (10-14): built again with the panel on every notify and every
  /// cut crossed, as every rail label was.
  @override
  Object? get facts => (
    trackId,
    rowId,
    kind,
    keyName,
    name,
    active,
    height,
    onSelectLayer != null,
    onSettledPress != null,
    chromeless,
  );

  @override
  Widget buildKept(BuildContext context) {
    final onSelect = onSelectLayer;
    return _StoryboardLabelShell(
      selectKey: ValueKey<String>(
        'storyboard-$keyName-label-${trackId.value}',
      ),
      chromeless: chromeless,
      onTap: onSelect == null ? null : () => onSelect(rowId),
      onSettledPress: onSettledPress,
      height: height,
      active: active,
      semanticsLabel: active
          ? AppText.strings.semSelectedLayer
          : AppText.strings.semLayer,
      child: Row(
        children: [
          ...layerRailLeadingCells(
            typeButton: LayerTypeButton(
              keyPrefix: 'storyboard',
              idValue: '${trackId.value}-$keyName',
              kind: kind,
              height: height,
              onTap: onSelect == null ? null : () => onSelect(rowId),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              // The one row-name style every surface wears
              // ([layerRowNameStyle], F-26 #1226 — 「스토리보드패널도
              // 겸사겸사 싹 다 폰트 통일」): no layer, so no eye to dim it.
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: layerRowNameStyle(context),
              ),
            ),
          ),
          ...layerRailTrailingCells(
            columns: layerRailColumnWidthsIn(context),
            optionalColumns: StoryboardPanel.optionalRailColumns,
          ),
        ],
      ),
    );
  }
}

/// A rail row that wears a layer — a PROJECTION row's head, a conte row's
/// or the camera row's (I-73), and the track's own S rows and transition
/// row: THE TIMELINE'S OWN ROW ([TimelineLayerControlsRow]) wearing the
/// layer the row has in hand, at this rail's width and the row's height.
///
/// 🗣️유저 2026-10-13 (I-89 ①): 「다시 말하지만 이런건 다 콘티패널에도
/// 동일하게 있어야해. 같은 법으로」. ↩️The S and transition rows were labels
/// of this rail's own, built from the same cells, and they lagged the row
/// they copied as the x-sheet's private header once had (T10): their colour
/// label, type button and speaker acted on the release, and a tap inside
/// the selection left it standing.
///
/// 🚨I-57 (10-14): built again with the panel on every notify and every cut
/// crossed — 🔬464 of a crossing's 1,088 rebuilds on the AMMI OP, five
/// heads. Kept by its FACE ([ControlsRowFace]), as the timeline's rail
/// keeps its rows (I-57 ㉣): a crossing that hands the row a layer of the
/// same face hands it back whole, and what in it asks WHICH layer it wears
/// asks [BerthRow] above it — the eye through [RailEyes] beside that
/// ([_StoryboardRowsAndLabels._wearing]).
///
/// Every press acts on the ROW [rowId] — what the selection holds and a
/// stand names — so a press made there is a press inside the selection
/// when the row is in it (row-buttons-act-on-the-selection); the session
/// lands it on the row in hand (`RowSelection.layerActedOn`). ↩️They
/// pressed the layer the label wears — one cut's, which no selection on
/// this rail holds — so a press on a selected conte row changed that row
/// alone (the 10-10 audit). The verbs here are the host's, each handed
/// [rowId] at the press.
class _StoryboardRailHead extends KeptPiece {
  const _StoryboardRailHead({
    super.key,
    required this.rowId,
    required this.layer,
    required this.metrics,
    required this.active,
    required this.fxState,
    this.chromeless = false,
    this.depth = 0,
    this.hasLanes = false,
    this.lanesExpanded = false,
    this.onToggleLanes,
    this.onSelectLayer,
    this.onSettledPress,
    this.labelDoubleClick,
    this.onToggleLayerVisibility,
    this.onLayerOpacityChanged,
    this.onLayerMarkSelected,
    this.onToggleLayerTimesheet,
    this.onToggleLayerOnionSkin,
    this.onionSkinEnabled = false,
    this.onOpenLayerMixer,
    this.soloed = false,
    this.onLayerBlendModeSelected,
    this.onLayerOpacityChangeEnd,
    this.onToggleLayerFx,
    this.opacityDragPreview,
    this.onOpenCameraPath,
    this.attachArrowPlacement,
    this.wearsBaseComposite = false,
    this.hasGroupFold = false,
    this.groupFoldExpanded = true,
    this.onToggleGroupFold,
    this.laneGraphVerbs,
    this.headsGraph = false,
    this.graphOpen = false,
  });

  /// The row the head stands for — a conte row's seat
  /// ([trackConteRowId]), the camera row ([trackCameraRowId]), or the
  /// track's own row, an S row's or the transition row's: its layer's id.
  final LayerId rowId;

  /// The layer the row has in hand — a cut's, which the row wears, or the
  /// track's own.
  final Layer layer;
  final TimelineGridMetrics metrics;

  /// Whether the row is the one stood on.
  final bool active;
  final LayerFxState fxState;
  final bool chromeless;

  /// How far the row hangs in — the timeline row's indent
  /// ([TimelineLayerControlsRow.depth]): a conte row filed in a 공정
  /// folder, one level per folder (I-99).
  final int depth;
  final bool hasLanes;
  final bool lanesExpanded;

  /// The twirl, turned through the row it names at the press
  /// ([_StoryboardRowsAndLabels._twirlTurning]).
  final ValueChanged<LayerId>? onToggleLanes;
  final ValueChanged<LayerId>? onSelectLayer;

  /// Its press turned out to be a tap ([StoryboardPanel.onSettledPress]).
  final VoidCallback? onSettledPress;

  /// Its double click (I-48's rename), pressed on the ROW [rowId] — what
  /// the selection holds and the press stands on — not the layer it wears,
  /// which is one cut's: the rename finds the name there
  /// (`LayerVerbs.renameableOf`), wherever the head stands (F-322:
  /// 「더블클릭으로 레이어 이름바꾸는거 … 통일」). ↩️It pressed the head's
  /// layer, and a head standing in a cut other than the active one renamed
  /// nothing.
  final TimelineLabelDoubleClick? labelDoubleClick;
  final ValueChanged<LayerId>? onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChanged;
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;
  final void Function(LayerId layerId, LayerMarkEdit edit)? onLayerMarkSelected;

  /// The sheet toggle, where the row is handed one
  /// ([_StoryboardRailSweep.handsSheetToggle]): a conte row's writes its
  /// head's flag, one for every cut ([ConteHead.onTimesheet]).
  /// ↩️The track's own rows' alone until I-89-Q22 made the flag the
  /// head's.
  final ValueChanged<LayerId>? onToggleLayerTimesheet;

  /// The onion toggle and whether the row ghosts — a conte row's for every
  /// cut, as its onion is one (`OnionSkin.isLayerOnionSkinEnabled`, I-89-Q22).
  /// Its column stands on every row of this rail
  /// ([StoryboardPanel.optionalRailColumns]); a row whose kind cannot ghost
  /// keeps its slot empty.
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;
  final bool onionSkinEnabled;

  /// An S row's speaker, opening its mixer under itself, and whether the
  /// row is soloed (the speaker's accent).
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;
  final bool soloed;
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;
  final ValueChanged<LayerId>? onToggleLayerFx;
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;
  final Future<void> Function(BuildContext anchorContext)? onOpenCameraPath;
  final AttachedPlacement? attachArrowPlacement;
  final bool wearsBaseComposite;
  final bool hasGroupFold;
  final bool groupFoldExpanded;
  final ValueChanged<LayerId>? onToggleGroupFold;

  /// The header graphs' verbs (I-89 ①) — the timeline's, as this rail
  /// hands them — and whether the row heads a graph and it stands open: the
  /// camera row, the row being its own Transform group (㉙), as on the
  /// timeline. Its button turns the graph of the layer the head wears.
  final LaneGraphVerbs? laneGraphVerbs;
  final bool headsGraph;
  final bool graphOpen;

  /// What the head shows: its layer's FACE — never which layer, which a
  /// crossing changes — and what the session answers for the row. The eye
  /// is not here: it rides past the keep ([RailEyes]).
  @override
  Object? get facts => (
    rowId,
    ControlsRowFace(layer),
    metrics,
    active,
    fxState,
    chromeless,
    depth,
    hasLanes,
    lanesExpanded,
    onToggleLanes != null,
    onSelectLayer != null,
    onSettledPress != null,
    labelDoubleClick != null,
    onToggleLayerVisibility != null,
    onLayerOpacityChanged != null,
    onLayerOpacityChangeEnd != null,
    onLayerMarkSelected != null,
    onToggleLayerTimesheet != null,
    onToggleLayerOnionSkin != null,
    onionSkinEnabled,
    onOpenLayerMixer != null,
    soloed,
    onLayerBlendModeSelected != null,
    onToggleLayerFx != null,
    ByIdentity(opacityDragPreview),
    onOpenCameraPath != null,
    attachArrowPlacement,
    wearsBaseComposite,
    hasGroupFold,
    groupFoldExpanded,
    onToggleGroupFold != null,
    laneGraphVerbs != null,
    headsGraph,
    graphOpen,
  );

  @override
  Widget buildKept(BuildContext context) {
    final doubleClick = labelDoubleClick;
    final endOpacity = onLayerOpacityChangeEnd;
    final pickBlend = onLayerBlendModeSelected;
    final toggleFx = onToggleLayerFx;
    final toggleGroupFold = onToggleGroupFold;
    final toggleSheet = onToggleLayerTimesheet;
    final openMixer = onOpenLayerMixer;
    return TimelineLayerControlsRow(
      chromeless: chromeless,
      depth: depth,
      keyPrefix: 'storyboard',
      layer: layer,
      active: active,
      hasLanes: hasLanes,
      lanesExpanded: lanesExpanded,
      onToggleLanes: onToggleLanes,
      metrics: metrics,
      onSelectLayer: (_) => onSelectLayer?.call(rowId),
      onSettledPress: onSettledPress,
      labelDoubleClick: doubleClick == null ? null : (_) => doubleClick(rowId),
      onToggleLayerVisibility: (_) => onToggleLayerVisibility?.call(rowId),
      onLayerOpacityChanged: (_, opacity) =>
          onLayerOpacityChanged?.call(rowId, opacity),
      onLayerOpacityChangeEnd: endOpacity == null
          ? null
          : (_, opacity) => endOpacity(rowId, opacity),
      opacityDragPreview: opacityDragPreview,
      onLayerMarkSelected: (_, edit) =>
          onLayerMarkSelected?.call(rowId, edit),
      onToggleLayerTimesheet: toggleSheet == null
          ? null
          : (_) => toggleSheet(rowId),
      // Handed whatever the host wired: the column is this rail's, so a
      // head stands it as every other row does.
      onToggleLayerOnionSkin: (_) => onToggleLayerOnionSkin?.call(rowId),
      onionSkinEnabled: onionSkinEnabled,
      onOpenLayerMixer: openMixer == null
          ? null
          : (anchorContext, _) => openMixer(anchorContext, rowId),
      isLayerSoloed: soloed,
      onLayerBlendModeSelected: pickBlend == null
          ? null
          : (_, mode) => pickBlend(rowId, mode),
      fxState: fxState,
      onToggleLayerFx: toggleFx == null ? null : (_) => toggleFx(rowId),
      onOpenCameraPath: onOpenCameraPath,
      attachArrowPlacement: attachArrowPlacement,
      wearsBaseComposite: wearsBaseComposite,
      hasGroupFold: hasGroupFold,
      groupFoldExpanded: groupFoldExpanded,
      onToggleGroupFold: toggleGroupFold == null
          ? null
          : (_) => toggleGroupFold(rowId),
      laneGraphVerbs: laneGraphVerbs,
      headsGraph: headsGraph,
      graphOpen: graphOpen,
    );
  }
}

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
///
/// [row] is the address the press stands on — a layer's own, or a track's
/// projection row, which no layer's id names (I-73). [onPressAt] takes the
/// press instead of [onRowFramePress] on a row whose press reads more than
/// its frame: the camera row's two lines over an O.L say which cut by the
/// line the pointer is on.
Positioned _storyboardRowPressLayer({
  required Key key,
  required TimelineRowAddress row,
  required double cellExtent,
  required int? Function(Offset local) frameAt,
  required StoryboardRowFramePress? onRowFramePress,
  required void Function(int frame)? onEdit,
  void Function(Offset local, int frame)? onPressAt,
}) {
  final cells = (
    frameAt: frameAt,
    axis: Axis.horizontal,
    cellExtent: () => cellExtent,
  );
  return Positioned.fill(
    key: key,
    child: InstantTapRegion(
      behavior: HitTestBehavior.translucent,
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      onPressDown: timelineCellDoubleTapRecord(row: row, cells: cells),
      onTap: (localPosition) {
        final frame = frameAt(localPosition);
        if (frame == null) {
          return;
        }
        if (onPressAt != null) {
          onPressAt(localPosition, frame);
          return;
        }
        onRowFramePress?.call(row, frame);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: onEdit == null
            ? null
            : timelineCellDoubleTapActivation(
                row: row,
                cells: cells,
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
  required _RailSweepAt? railSweepAt,
  required List<TimelineDisplayRow> rows,
}) => TimelineFrameRangeGestureLayer(
  key: key,
  row: LayerRowAddress(layer.id),
  geometry: geometry,
  crossAxisExtent: crossAxisExtent,
  callbacks: _storyboardBandCallbacks(
    row: LayerRowAddress(layer.id),
    select: select,
    railSweepAt: railSweepAt,
    rows: rows,
  ),
);

/// The track band's gesture bundle on [row] — an S row, or a lane of its
/// layer ([TimelineRowAddress.owningLayerId]): a sweep from it selects
/// through [select] over what the rail swept ([railSweepAt]), and a press
/// inside the band moves the band, its row steps counted from this row
/// over [rows].
///
/// 🚨H20 — ONE bundle for a row's cells and, as their band
/// ([TimelineLaneRangeCallbacks.band]), each lane under them: a band carries
/// what each of its rows holds wherever it is grabbed, as the timeline's
/// grids hand their lanes the cells' bundle. ↩️A lane's press began a lane
/// selection of its own, and the band it lay in went.
TimelineRangeGestureCallbacks _storyboardBandCallbacks({
  required TimelineRowAddress row,
  required StoryboardSeSelectCallbacks select,
  required _RailSweepAt? railSweepAt,
  required List<TimelineDisplayRow> rows,
}) {
  final layerId = row.owningLayerId!;
  return TimelineRangeGestureCallbacks(
    isInSelection: (_, frame) =>
        _storyboardRangeCovers(select.selectedRange.value, row, frame),
    onSelectUpdate: (_, anchorIndex, headIndex, headCrossOffset) =>
        select.onDrag(
          layerId: layerId,
          anchorGlobalFrame: anchorIndex,
          headGlobalFrame: headIndex,
          anchorRow: row,
          spanRows: railSweepAt?.call(row, headCrossOffset) ?? const [],
        ),
    onTapClear: (_) => select.onClear(),
    onMoveBegin: (_, _) => select.move?.onBegin(layerId) ?? false,
    onMoveUpdate: (frameDelta, rowDelta) => select.move?.onUpdate(
      frameDelta,
      resolveBlockMoveTargetLayer(rows: rows, source: row, rowDelta: rowDelta),
    ),
    onMoveEnd: () => select.move?.onEnd(),
    onMoveCancel: () => select.move?.onCancel(),
  );
}

/// 🗣️F-228 (유저 2026-09-29): 「블록이라면 전부 코마텍스트가 존재해야함.
/// 통일해서 적용」 — the S rows and the transition row drew their blocks and
/// printed no length. They print it with the timeline row's own painter,
/// which already knows what a block is on either kind of row, fed the
/// panel's LIVE axis and window: the inputs the V row's blocks painter
/// reads, so a zoom step or a span crossing repaints the numbers alone.
///
/// Mounted over the paper and under the writing and the marks — where the
/// timeline row prints them (its cells' foreground, under its overlays).
mixin _StoryboardRowRunLabels {
  TimelineFrameGeometryHandle get frameGeometry;
  ValueListenable<int> get windowBucket;
  bool get showSeconds;
  ProjectFrameRate get projectFrameRate;
  double get height;

  /// [layer]'s lengths, each on its block as the row draws the block
  /// (I-129): whether the row is [shown] — its own eye where nothing says —
  /// and what its cels hold ([celContent]), onto the host's ground. What
  /// the S and transition rows hold has no picture to lack, so none of
  /// their blocks is empty.
  Widget _runLabels(
    BuildContext context,
    Layer layer, {
    bool? shown,
    TimelineCelContentSource? celContent,
  }) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: ValueKey<String>('storyboard-run-labels-${layer.id}'),
          foregroundPainter: TimelineRowRunLabelsPainter(
            layer: layer,
            geometry: frameGeometry,
            crossAxisExtent: height,
            showSeconds: showSeconds,
            countingBase: projectFrameRate.countingBase,
            baseTextStyle: DefaultTextStyle.of(context).style,
            windowBucket: windowBucket,
            shown: shown ?? RailEyes.of(context, layer).shown,
            celContent: celContent,
            paperGround: TimelineGridLaw.maybeOf(context)?.ground,
          ),
        ),
      ),
    ),
  );
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
class _StoryboardTransitionRow extends KeptPiece
    with _StoryboardRowRunLabels {
  const _StoryboardTransitionRow({
    required this.trackId,
    required this.layer,
    required this.width,
    required this.height,
    required this.timelineScale,
    required this.frameGeometry,
    required this.windowBucket,
    required this.showSeconds,
    required this.projectFrameRate,
    this.defById,
    this.crossingTooltip,
    this.commaDrag,
    this.onRowFramePress,
    this.onEditSpan,
    this.select,
    this.railSweepAt,
  });

  /// The track whose row this is — its keys' word.
  final TrackId trackId;

  /// The row as it should RENDER — the committed layer, or the session's
  /// in-flight edge-drag form while a grip is held.
  final Layer layer;
  final double width;

  /// Its label's height ([_StoryboardRowHeights.transition]) — one row.
  @override
  final double height;
  final TimelineScale timelineScale;

  /// The panel's live axis and window, which the spans' lengths are printed
  /// on ([_StoryboardRowRunLabels]).
  @override
  final TimelineFrameGeometryHandle frameGeometry;
  @override
  final ValueListenable<int> windowBucket;
  @override
  final bool showSeconds;
  @override
  final ProjectFrameRate projectFrameRate;
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

  /// The rail's sweep, so a select-drag can reach across rows exactly as
  /// the S rows' does.
  final _RailSweepAt? railSweepAt;

  /// The visible frame window this strip covers — the whole content width,
  /// like the SE grips' own geometry.
  int get _frameEndExclusive => timelineScale.framesCovering(width);

  TimelineFrameGeometry get _geometry => TimelineFrameGeometry(
    frameCellExtent: timelineScale.pixelsPerFrame,
    frameStartIndex: 0,
    frameEndIndexExclusive: _frameEndExclusive,
  );

  /// What the row shows — its spans' terms and crossing warnings by what
  /// [defById] and [crossingTooltip] answer for every span the row holds,
  /// a superset of the ones its window draws.
  ///
  /// 🚨I-57 (10-14): the S rows' story — built again with the panel on
  /// every notify and every cut crossed.
  @override
  Object? get facts => (
    trackId,
    ByIdentity(layer),
    width,
    height,
    timelineScale.pixelsPerFrame,
    timelineScale.minBlockWidth,
    ByIdentity(frameGeometry),
    ByIdentity(windowBucket),
    showSeconds,
    projectFrameRate,
    ByList([
      for (final MapEntry(key: start, value: span)
          in layer.instructions.entries)
        (span.defIn(defById), crossingTooltip?.call(start)),
    ]),
    commaDrag != null,
    onRowFramePress != null,
    onEditSpan != null,
    select != null,
    railSweepAt != null,
  );

  @override
  Widget buildKept(BuildContext context) {
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
          width: timelineScale.spanWidth(
            entry.key,
            entry.key + entry.value.length,
          ),
          child: IgnorePointer(
            key: ValueKey<String>(
              'storyboard-transition-paper-${layer.id}-${entry.key}',
            ),
            child: SePaperSpan(
              axis: Axis.horizontal,
              frameCellExtent: timelineScale.pixelsPerFrame,
              startFrame: entry.key,
              // ⑲: the block is its layer's colour label — in its look
              // (I-129).
              paper: timelineRowLookOf(context, layer).paper!,
            ),
          ),
        ),
      );
    }
    spans.add(_runLabels(context, layer));
    // The marks, from the direction row's own overlay builder. Each mark
    // takes no pointer of its own; a warning's hover reaches its block
    // (F-495). ↩️The whole layer took none, and the warning's tooltip,
    // added inside it later (D26), could never be hovered here.
    final defById = this.defById;
    if (defById != null && _frameEndExclusive > 0) {
      spans.add(
        Positioned.fill(
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
          : timelineScale.frameAt(local.dx);
      spans.add(
        _storyboardRowPressLayer(
          key: ValueKey<String>('storyboard-transition-press-${layer.id}'),
          row: LayerRowAddress(layer.id),
          cellExtent: timelineScale.pixelsPerFrame,
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
          railSweepAt: railSweepAt,
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
        geometry: TimelineFrameGeometryHandle(_geometry),
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
      key: ValueKey<String>('storyboard-transition-row-${trackId.value}'),
      width: width,
      height: height,
      child: Stack(children: spans),
    );
  }
}

/// One TRACK-owned SE row: the track's [slot]th SE layer rendered straight
/// on the global frame axis — blocks keep their true lengths (a sound may
/// cross cut boundaries) and the timeline's data is exactly this layer, by
/// identity. It shows the whole flow, so it wears no `~`: 🗣️F-358 (유저
/// 2026-10-14) 「이런건 물론 로컬패널(타임라인패널)에서만」.
class _StoryboardSeRow extends KeptPiece with _StoryboardRowRunLabels {
  const _StoryboardSeRow({
    required this.trackIndex,
    required this.slot,
    required this.layer,
    required this.width,
    required this.height,
    required this.timelineScale,
    required this.projectFrameRate,
    required this.frameGeometry,
    required this.windowBucket,
    required this.viewportWidth,
    required this.showSeconds,
    this.audioPeaksFor,
    this.soundCannotPlay,
    this.seClipMarkerTooltip,
    this.onRowFramePress,
    this.onDropMediaAsset,
    this.acceptsMediaAsset,
    this.onEditSeEntry,
    this.seCommaDrag,
    this.seSelect,
    this.railSweepAt,
    this.moveRows = const [],
  });

  /// The rail's sweep from a pressed row ([_RailSweepAt]).
  final _RailSweepAt? railSweepAt;

  final int trackIndex;
  final int slot;

  /// This track's S rows top-to-bottom, each with the lanes drawn under it
  /// ([_StoryboardRailRows._seMoveRows]) — what a MOVE's row delta walks.
  /// Only S rows and their lanes are in it, which is what keeps a drag from
  /// crossing into a row whose blocks are not sounds.
  final List<TimelineDisplayRow> moveRows;

  /// The track's GLOBAL SE layer behind this row (null = fewer rows).
  final Layer? layer;
  final double width;

  /// Its label's height ([_StoryboardRowHeights.se]) — one row.
  @override
  final double height;
  final TimelineScale timelineScale;
  @override
  final ProjectFrameRate projectFrameRate;
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// Why a sound of the row cannot be played
  /// ([StoryboardPanel.soundCannotPlay]).
  final SoundCannotPlay? Function(String filePath)? soundCannotPlay;

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
  /// frame blocks' shared [TimelineDoubleTapGate]. Global frames,
  /// because that is this row's axis. Null keeps the row press-only.
  final void Function(LayerId layerId, int globalFrame)? onEditSeEntry;

  final TimelineCommaDragCallbacks? seCommaDrag;

  /// Range selection on this row — the SAME shared gesture and the same
  /// track-axis selection the cut row uses, one row up. Null keeps the row
  /// display-only.
  final StoryboardSeSelectCallbacks? seSelect;

  /// The panel's live frame-axis geometry, which the shared gesture reads
  /// to turn a pointer position into a track-global frame, and the blocks'
  /// lengths are printed on ([_StoryboardRowRunLabels]).
  @override
  final TimelineFrameGeometryHandle frameGeometry;

  /// The panel's window, as the V row's blocks painter takes it.
  @override
  final ValueListenable<int> windowBucket;

  /// How far the panel's view reaches — what the window the row's pieces
  /// are built for reaches past its bucket ([_window]).
  final double viewportWidth;
  @override
  final bool showSeconds;

  /// What the row shows: its sounds' waveforms by what [audioPeaksFor]
  /// answers for them — each peaks by identity, none while extracting — and
  /// of the rows a move walks only their layers, which is all the walk
  /// reads ([resolveBlockMoveTargetLayer]).
  ///
  /// 🚨I-57 (10-14): built again with the panel — on every notify, every
  /// cut crossed — the row painted every waveform of the track again:
  /// 🔬three fifths of a crossing's paint on the AMMI OP, for sounds that
  /// had not moved.
  @override
  Object? get facts => (
    trackIndex,
    slot,
    ByIdentity(layer),
    width,
    height,
    timelineScale.pixelsPerFrame,
    timelineScale.minBlockWidth,
    projectFrameRate,
    ByIdentity(frameGeometry),
    ByIdentity(windowBucket),
    // By the window it reaches, not the breadth: a view a pixel wider keeps
    // its window, and the pieces built for it stand
    // (storyboard-strips-build-on-every-view-pixel).
    timelineFrameWindowReachFor(
      viewportExtent: viewportWidth,
      cellExtent: timelineScale.pixelsPerFrame,
    ),
    showSeconds,
    ByList([
      if (layer case final layer?)
        for (final span in seAudioSpans(layer))
          audioPeaksFor?.call(span.clip.filePath),
    ]),
    // And why each cannot be played: its block's paper and warning line.
    ByList([
      if (layer case final layer?)
        for (final span in seAudioSpans(layer))
          soundCannotPlay?.call(span.clip.filePath),
    ]),
    seClipMarkerTooltip,
    onRowFramePress != null,
    onDropMediaAsset != null,
    acceptsMediaAsset != null,
    onEditSeEntry != null,
    seCommaDrag != null,
    seSelect != null,
    railSweepAt != null,
    ByList([for (final row in moveRows) row.address]),
  );

  /// 🚨THE BLOCKS' PIECES ARE BUILT FOR THE PANEL'S WINDOW
  /// (frame-panels-build-in-one-frame, 2026-10-24): the row spans the whole
  /// film, and it built a paper, a waveform, the words, two grips and the
  /// drop places of EVERY sound of the track — 🔬on the AMMI OP the S rows
  /// were a fifth of reopening the storyboard. Its pieces are now the
  /// window's, re-made when the window crosses a bucket — as the projection
  /// keys' are, and as the painters beside them draw.
  @override
  Widget buildKept(BuildContext context) {
    final layer = this.layer;
    return SizedBox(
      key: ValueKey<String>('storyboard-se-row-$trackIndex-${slot + 1}'),
      width: width,
      height: height,
      child: layer == null
          ? const Stack()
          : _windowed(layer, drawingBlocks(layer.timeline)),
    );
  }

  Widget _windowed(Layer layer, List<TimelineDrawingBlock> blocks) =>
      ValueListenableBuilder<int>(
        valueListenable: windowBucket,
        builder: (context, _, _) {
          final window = _window();
          return Stack(
            children: [
              ..._contentSpans(context, layer, blocks, window),
              ..._interactionLayers(context, layer, blocks, window),
              _warningLayer(context, layer, window),
            ],
          );
        },
      );

  /// The frames the panel's window can reach while its offset stays in the
  /// bucket ([visibleFrameWindowFor]).
  ({int startIndex, int endIndexExclusive}) _window() => visibleFrameWindowFor(
    bucket: windowBucket,
    viewportMainExtent: viewportWidth,
    cellExtent: timelineScale.pixelsPerFrame,
    frameStartIndex: 0,
    frameEndIndexExclusive: _rowFrames.frameEndIndexExclusive,
  );

  /// The blocks' warning lines — a take that clipped (REC1-D), a sound that
  /// cannot be played — on the ROW, where the timeline's SE row mounts
  /// them. ↩️The clipped takes rode the twirled-down Audio lane here, so
  /// one showed only while its row was open (F-101).
  Positioned _warningLayer(
    BuildContext context,
    Layer layer,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    return Positioned.fill(
      child: TimelineFixedFrameSpanLayer(
        geometry: _rowFrames,
        crossAxisExtent: height,
        axis: Axis.horizontal,
        children: timelineRowSoundWarningOverlays(
          layer: layer,
          frameStartIndex: window.startIndex,
          frameEndIndexExclusive: window.endIndexExclusive,
          crossAxisExtent: height,
          axis: Axis.horizontal,
          warnings: (
            clipped: seClipMarkerTooltip,
            cannotPlay: soundCannotPlay,
          ),
          color: Theme.of(context).colorScheme.error,
          keyPrefix: 'storyboard-${layer.id}',
        ),
      ),
    );
  }

  /// What the row shows: each block's paper, the waveform where a clip's
  /// peaks are known, each block's length, and the dialogue / SE name over
  /// each block — those of [window].
  ///
  /// The waveforms and the writing are the timeline SE row's own overlays
  /// ([timelineRowAudioOverlays], [timelineRowSeLabelOverlays]) on the span
  /// layer the row's grips and warnings ride. ↩️The row placed them itself
  /// (one `Positioned` a span off the scale) and wrote its words with a
  /// loop of its own beside the timeline's.
  List<Widget> _contentSpans(
    BuildContext context,
    Layer layer,
    List<TimelineDrawingBlock> blocks,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    final sounds = seAudioSpans(layer);
    final audioPeaksFor = this.audioPeaksFor;
    return [
      // Paper blocks first — the storyboard SE row has no cells
      // underneath, so each block paints its own paper span (SePaperSpan)
      // at its TRUE global extent; waveforms go above the paper (cut ends
      // no longer clip: the block may cross them), the writing on top.
      _contentLayer([
        for (final block in blocks)
          if (_inWindow(block, window))
            _paperSpan(context, block, layer, sounds),
        if (audioPeaksFor != null)
          ...timelineRowAudioOverlays(
            context,
            layer: layer,
            frameStartIndex: window.startIndex,
            frameEndIndexExclusive: window.endIndexExclusive,
            axis: Axis.horizontal,
            frameRate: projectFrameRate,
            audioPeaksFor: audioPeaksFor,
            keyPrefix: 'storyboard',
          ),
      ]),
      _runLabels(context, layer),
      // The sheet's writing on the paper blocks — each name standing in the
      // frames free before its block ([seFramesFreeBefore]), so the window
      // reaches a chip's length further: a block just past it can stand
      // its name inside.
      _contentLayer(
        timelineRowSeLabelOverlays(
          layer: layer,
          frameStartIndex: window.startIndex,
          frameEndIndexExclusive:
              window.endIndexExclusive + _framesUnder(seNameBoxExtent),
          axis: Axis.horizontal,
          keyPrefix: 'storyboard',
        ),
      ),
    ];
  }

  /// A layer of what the row shows, which no pointer lands on.
  ///
  /// ⛔THREE SPANS ON THIS ROW placed themselves: the dialogue, the paper
  /// and the waveform. Each worked the left edge and the width out of the
  /// same scale, and each wrapped its child in the same ignored pointer —
  /// three chances for one of them to place a strip a frame off the others
  /// on the row it shares. ↩️A helper of the row's then placed all three;
  /// now the span layer does, the one its grips and warnings land by.
  Positioned _contentLayer(List<Widget> spans) => Positioned.fill(
    child: IgnorePointer(
      child: TimelineFixedFrameSpanLayer(
        geometry: _rowFrames,
        crossAxisExtent: height,
        axis: Axis.horizontal,
        children: spans,
      ),
    ),
  );

  /// How many of the row's frames [extent] pixels run over, whole.
  int _framesUnder(double extent) => timelineScale.pixelsPerFrame <= 0
      ? 0
      : (extent / timelineScale.pixelsPerFrame).ceil();

  static bool _inWindow(
    TimelineDrawingBlock block,
    ({int startIndex, int endIndexExclusive}) window,
  ) => frameRangesOverlap(
    block.startIndex,
    block.endIndexExclusive,
    window.startIndex,
    window.endIndexExclusive,
  );

  /// What the row answers to: the selection wash, the press layer, the
  /// range gesture, and the comma grips on the edges of [window]'s blocks.
  List<Widget> _interactionLayers(
    BuildContext context,
    Layer layer,
    List<TimelineDrawingBlock> blocks,
    ({int startIndex, int endIndexExclusive}) window,
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
    if (seSelect != null) {
      spans.add(
        _rangeGestureLayer(layer, frameGeometry, seSelect),
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
      // One handle for the row's grips: the round end of each mark reads
      // the cell off it ([BlockEdgeGrip.geometry]).
      final gripGeometry = TimelineFrameGeometryHandle(_rowFrames);
      // Each grip names its block by its place on the WHOLE row, as the
      // session counts it.
      for (final (blockOrdinal, block) in blocks.indexed) {
        if (!_inWindow(block, window)) {
          continue;
        }
        for (final edge in TimelineBlockEdge.values) {
          grips.add(
            _edgeGrip(
              edge,
              block,
              layer,
              blockOrdinal,
              seCommaDrag,
              gripGeometry,
            ),
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
      final cells = _cellDropLayer(context, layer, blocks, window, drop);
      if (cells != null) {
        spans.add(cells);
      }
    }
    return spans;
  }

  /// The press's conversion: this row's frame 0 sits at its left edge.
  int? _frameAtX(double x) => timelineScale.pixelsPerFrame <= 0
      ? null
      : timelineScale.frameAt(x);

  /// The row's cells, as its grips and its drop places are laid out on.
  TimelineFrameGeometry get _rowFrames => TimelineFrameGeometry(
    frameCellExtent: timelineScale.pixelsPerFrame,
    frameStartIndex: 0,
    frameEndIndexExclusive: timelineScale.framesCovering(width),
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
  /// answer. Those of [window], as the row's other pieces.
  Positioned? _cellDropLayer(
    BuildContext context,
    Layer layer,
    List<TimelineDrawingBlock> blocks,
    ({int startIndex, int endIndexExclusive}) window,
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
      for (final gap in [
        ...emptyGapsBetween(layer, 0, walked),
        if (walked < end) (startIndex: walked, length: end - walked),
      ])
        if (frameRangesOverlap(
          gap.startIndex,
          gap.startIndex + gap.length,
          window.startIndex,
          window.endIndexExclusive,
        ))
          gap,
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

  TimelineFrameSpan _edgeGrip(
    TimelineBlockEdge edge,
    TimelineDrawingBlock block,
    Layer layer,
    int blockOrdinal,
    TimelineCommaDragCallbacks seCommaDrag,
    TimelineFrameGeometryHandle gripGeometry,
  ) {
    return TimelineFrameSpan(
      placement: timelineBlockEdgeGripPlacement(
        edge: edge,
        block: (
          startIndex: block.startIndex,
          endIndexExclusive: block.endIndexExclusive,
        ),
        // I-44: on the SE paper, which stops a seam short of the row.
        crossAxisExtent: timelineRowPaperExtent(height),
      ),
      child: TimelineBlockEdgeGrip(
        key: ValueKey<String>(
          'storyboard-se-grip-${layer.id}-$blockOrdinal'
          '-${edge.name}',
        ),
        layer: layer,
        blockStartIndex: block.startIndex,
        blockOrdinal: blockOrdinal,
        edge: edge,
        geometry: gripGeometry,
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
    railSweepAt: railSweepAt,
    rows: moveRows,
  );

  Positioned _pressLayer(
    Layer layer,
    int? Function(Offset local) frameAt,
    void Function(LayerId layerId, int globalFrame)? onEditSeEntry,
  ) => _storyboardRowPressLayer(
    key: ValueKey<String>('storyboard-se-press-${layer.id}'),
    row: LayerRowAddress(layer.id),
    cellExtent: timelineScale.pixelsPerFrame,
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
                  width: timelineScale.spanWidth(
                    selection.startFrame,
                    selection.startFrame + selection.lengthFrames,
                  ),
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

  /// [block]'s paper: its layer's colour label (⑲) — red where a sound it
  /// carries cannot be played, as the timeline's block is
  /// (`LayerStack.soundCannotPlayAt`) and a cel that cannot be read — in
  /// the block's look ([timelineRowLookOf], I-129).
  TimelineFrameSpan _paperSpan(
    BuildContext context,
    TimelineDrawingBlock block,
    Layer layer,
    List<SeAudioSpan> sounds,
  ) {
    final cannotPlay = soundCannotPlay;
    final silent =
        cannotPlay != null &&
        soundCannotPlayIn(sounds, block.startIndex, cannotPlay) != null;
    return TimelineFrameSpan(
      placement: TimelineFrameSpanPlacement(
        startIndex: block.startIndex,
        endIndexExclusive: block.endIndexExclusive,
      ),
      child: KeyedSubtree(
        key: ValueKey<String>(
          'storyboard-se-paper-${layer.id}-${block.startIndex}',
        ),
        child: SePaperSpan(
          axis: Axis.horizontal,
          frameCellExtent: timelineScale.pixelsPerFrame,
          startFrame: block.startIndex,
          paper: timelineRowLookOf(context, layer, unreadable: silent).paper!,
        ),
      ),
    );
  }
}

/// One lane's frame band on the shared substrate — the timeline grid's own
/// lane row ([TimelineLaneFrameRow]), its key markers drawn as the timeline
/// draws them (F-101). ↩️It was the Audio lane's waveform band or a property
/// lane's, told apart as the timeline told them apart, until the band went
/// (I-140).
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
    this.laneEdit,
    this.laneRange,
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
  final PropertyLaneEditCallbacks? laneEdit;

  /// Wires the band's range-select/move gesture (the timeline's lane
  /// machinery, carrier-routed in the session) — an S row's lanes too
  /// (R5 ③b); null keeps the band display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  @override
  Widget build(BuildContext context) {
    // Its band is its whole row, as a camera or a conte row's lane's is and
    // the timeline's lanes are, so a key's mark fills its cell here too
    // (🗣️F-367: 「칸 그냥 차지는 마름모」). ↩️It stood a line in from either
    // edge — the per-cut spans' blocks (R6-B1), which the continuous rows
    // (#783) left behind.
    final metrics = TimelineGridMetrics(
      frameCellWidth: timelineScale.pixelsPerFrame,
      layerRowHeight: height,
    );
    final frames = timelineScale.pixelsPerFrame <= 0
        ? 0
        : timelineScale.frameAt(width);
    return SizedBox(
      key: ValueKey<String>(rowKey),
      width: width,
      height: height,
      child: TimelineLaneFrameRow(
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
    );
  }
}

/// The name of a track's V row — its label, the chip it shows picked up
/// (I-39), the sheet's group — by its place among the tracks: the first is
/// Cut, and a film has one track (전제 8); one past it is numbered.
/// 🗣️F-491 (유저 2026-10-27): 「콘티패널의 비디오행, 이름 Cut으로 변경」.
/// ↩️Video from F-322 (유저 2026-10-09: 「V행 이제 이름 V1행이아니라
/// Video나 Cut으로 하고싶음. Video로하자」), and V1, V2, … before that.
String storyboardVideoRowName(int index) =>
    index == 0 ? 'Cut' : 'Cut ${index + 1}';

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
class StoryboardTrackLabelRow extends KeptPiece {
  const StoryboardTrackLabelRow({
    super.key,
    required this.trackId,
    required this.trackLabel,
    required this.laneHeight,
    this.laneExpanded = false,
    this.onToggleLane,
    this.active = false,
    this.onSelectTrack,
    this.onSettledPress,
    this.trackFxState = LayerFxState.on,
    this.onToggleTrackFx,
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

  /// The track whose row this is — its keys' word.
  final TrackId trackId;
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

  /// Its press turned out to be a tap ([StoryboardPanel.onSettledPress]).
  final VoidCallback? onSettledPress;

  /// R9 #21: the V row's own column, describing the TRACK rather than
  /// whichever cut happens to sit under the playhead — the fx switch, a
  /// MASTER over the track's fx work. Null keeps the row display-only.
  ///
  /// 🗣️I-73 (유저 2026-10-08): 「V행의 불투명도랑 비지블 필요없어보여서
  /// 삭제하고싶은데 어때」 · 「5. 값도지움」 — ↩️the head carried an EYE too,
  /// which hid the picture of the cut under the playhead in the playback
  /// display (R9, UI-R13 #2), and the track's static OPACITY bar (R9 #21).
  /// Both are gone, the opacity's stored value with its bar; their two
  /// columns stand reserved and empty, as every rail row's do where it has
  /// nothing to show. (The eye was the one cell of this row the playhead
  /// moved — followed on a tick layer of its own since I-22 ③ — so the
  /// row shows nothing of the playhead now.)
  final LayerFxState trackFxState;
  final VoidCallback? onToggleTrackFx;

  /// What the row shows: its name and its switches — nothing of the
  /// track's cuts.
  ///
  /// 🚨I-57 (10-14): built again with the panel on every notify and every
  /// cut crossed, as every rail label was.
  @override
  Object? get facts => (
    trackId,
    trackLabel,
    laneHeight,
    laneExpanded,
    onToggleLane != null,
    active,
    onSelectTrack != null,
    onSettledPress != null,
    trackFxState,
    onToggleTrackFx != null,
    chromeless,
  );

  @override
  Widget buildKept(BuildContext context) {
    // V-track selection (UI-R18 #6): the S-row tap/highlight language on
    // the V row — tap selects the TRACK, the active treatment speaks
    // through the background alone.
    return _StoryboardLabelShell(
      selectKey: ValueKey<String>('storyboard-track-select-${trackId.value}'),
      rowKey: ValueKey<String>('storyboard-track-label-row-${trackId.value}'),
      onTap: onSelectTrack,
      onSettledPress: onSettledPress,
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
                // own lanes, its effect chain — none on a track with none
                // ([onToggleLane] null).
                laneToggle: onToggleLane == null
                    ? null
                    : RailSwipeColumnPointer(
                        column: RailSwipeColumn.laneToggle,
                        child: LayerFoldTwirl(
                          name:
                              'storyboard-track-lane-toggle-${trackId.value}',
                          expanded: laneExpanded,
                          tooltip: layerLaneTwirlTooltip(
                            expanded: laneExpanded,
                          ),
                          onToggle: onToggleLane,
                        ),
                      ),
                // A track is not a layer, so the type slot takes the film
                // strip by override rather than a kind.
                typeButton: LayerTypeButton(
                  keyPrefix: 'storyboard',
                  idValue: 'v-${trackId.value}',
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
                        'storyboard-track-label-${trackId.value}',
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
              // The shared trailing slots (UI-R5): the fx switch in its
              // column, and the eye's, the opacity's and the blend's reserved
              // and empty.
              ...layerRailTrailingCells(
                columns: layerRailColumnWidthsIn(context),
                optionalColumns: StoryboardPanel.optionalRailColumns,
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
                        column: RailSwipeColumn.fx,
                        child: FxToggleButton(
                          name: 'storyboard-track-fx-${trackId.value}',
                          subject: RailSubject.track,
                          state: trackFxState,
                          onToggle: onToggleTrackFx!,
                        ),
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
class _StoryboardEndLineHandle extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TimelineDragPreview?>(
      valueListenable: dragPreview ?? _noDragPreview,
      builder: (context, preview, child) => Positioned(
        key: const ValueKey<String>('storyboard-cut-end-handle'),
        left: scale.leftForFrame(
          timelineCutEndPreviewFrameCount(
            preview: preview,
            cutId: null,
            playbackFrameCount: committedTotalFrames,
            movieEndUnder: movieEndUnder,
          ),
        ),
        top: 0,
        bottom: 0,
        width: 12,
        child: child!,
      ),
      // F-445: the timeline's end line's grip ([EndLineGrip]).
      child: EndLineGrip(
        axis: Axis.horizontal,
        cellExtent: pixelsPerFrame,
        onBegin: movieEnd.onBegin,
        onUpdate: movieEnd.onUpdate,
        onEnd: movieEnd.onEnd,
        onCancel: movieEnd.onCancel,
      ),
    );
  }
}

class _StoryboardTrackRow extends KeptPiece {
  const _StoryboardTrackRow({
    required this.trackId,
    required this.layoutEntries,
    required this.onRowFramePress,
    required this.onDropMediaAsset,
    required this.acceptsMediaAsset,
    required this.laneHeight,
    required this.width,
    required this.stripEdges,
    required this.cutMove,
    required this.cutSelect,
    required this.thumbnails,
    required this.timelineScale,
    required this.frameGeometry,
    required this.hoveredCutId,
    this.standingCutId,
    required this.windowBucket,
    required this.showSeconds,
    required this.projectFrameRate,
    this.railSweepAt,
    this.linkedCutIds = const {},
    this.onOpenCutLinks,
    this.onEditCutBlock,
  });

  /// F-255: a double click on a cut block
  /// ([StoryboardPanel.onEditCutBlock]). Null keeps the block without one.
  final void Function(TrackId trackId, int globalFrame)? onEditCutBlock;

  /// The rail's sweep from a pressed row ([_RailSweepAt]).
  final _RailSweepAt? railSweepAt;

  /// The LINKED cuts on this track (I-25): their names wear the link icon.
  final Set<CutId> linkedCutIds;

  /// Pressed on a linked cut's link icon: the link window (I-25). Null
  /// keeps the icon display-only.
  final void Function(BuildContext context, CutId cutId)? onOpenCutLinks;

  final TrackId trackId;
  final List<StoryboardTimelineLayoutEntry> layoutEntries;

  /// The scroll content's full width — the SE rows' own. The row used to
  /// size itself to its cuts, which left NO widget (no press, no range
  /// gesture) past the last cut or on an empty track, while every empty
  /// cell there is still a cell ("빈 칸도 칸").
  final double width;

  final StoryboardRowFramePress? onRowFramePress;
  final StoryboardMediaDrop? onDropMediaAsset;
  final StoryboardMediaDropAccepts? acceptsMediaAsset;

  /// This row's height — the rail's matching label row reads the same one.
  final double laneHeight;
  final StoryboardStripEdgeCallbacks? stripEdges;
  final StoryboardCutMoveCallbacks? cutMove;
  final StoryboardCutSelectCallbacks? cutSelect;
  final StoryboardThumbnails? thumbnails;
  final TimelineScale timelineScale;

  /// The panel's live frame-axis geometry — what the SHARED range gesture
  /// reads to turn a pointer position into a track-global frame.
  final TimelineFrameGeometryHandle frameGeometry;

  /// The cut under the pointer, panel-wide: with the blocks painted there
  /// is no widget per cut to hold a hover state, so one notifier does for
  /// the whole row and a hover is a repaint rather than a rebuild.
  final ValueNotifier<CutId?> hoveredCutId;

  /// The cut under the playhead, whose plate wears the standing wash
  /// ([StoryboardCutBlocksPainter.standingCutId]).
  final ValueListenable<CutId?>? standingCutId;

  /// The shared window (UI-R16): the blocks painter draws — and asks for
  /// thumbnails — only inside the visible span, as far as the live
  /// geometry's view reaches.
  final ValueListenable<int> windowBucket;

  final bool showSeconds;
  final ProjectFrameRate projectFrameRate;

  /// The cut covering track-global [frame], or null in a gap / past the
  /// end ([_cutEntryAt]). The row's blocks are the snap material, so a press
  /// that lands between cuts addresses no cut at all.
  StoryboardTimelineLayoutEntry? _cutAtFrame(int frame) =>
      _cutEntryAt(layoutEntries, frame);

  /// THE ROW'S EDGES — each cut's two ends, in its plate's corners.
  ///
  /// 🗣️I-73 (유저 2026-10-08): 「띠 둘만 이사로 가자. 여기서 그럼 v행에
  /// 콘티블록 위치의 칸마다 있던 엣지는 어떻게하지? 그냥 없는게
  /// 심플한거같긴한데」 — and the drawn proposal that answer took: 「엣지는
  /// 컷의 양 끝뿐입니다」 · 「썸네일 사이는 구분선만. 잡을 것이 없습니다.
  /// 칸의 엣지는 바로 아래 콘티 행에만 있습니다」. A cut block's edges are
  /// the CUT's: its start and its length — the two verbs the conte row's
  /// first and last grips begin, from a second door.
  /// ↩️The cut had NO edge grips of its own (design, user's rule
  /// 2026-07-25): a cut edge was always on the strip, the first panel's
  /// leading edge being the cut's start and the last panel's trailing edge
  /// its length — and from 2026-09-26 (「콘티블록이 있으면 애초에 거기에
  /// 처음이랑 끝에 엣지가 존재하잖아 … 컷블록의 엣지만 삭제」 · 「콘티레이어
  /// 없으면 컷블록 기존처럼 배치하고, 있으면 콘티블록에 배치된걸로
  /// 대체되는」) only a cut with no storyboard layer kept edges in the
  /// plate's corners. Every cut's are there now — where every edge stood
  /// from 2026-09-25 (「제대로 컷블록의 위치에 존재하지않아」), and on the
  /// picture strip before that (#757, 07-25).
  ///
  /// 🗣️IN THE BANDS ALONE (I-52, 유저 2026-09-28: 「썸네일이 존재하는 블록은
  /// 엣지를 썸네일 안가리도록 … 띠에만」 · 「세로로는 해당 상단띠 전체에
  /// 걸치도록」): a triangle takes one band whole — the back edge's the
  /// cut's name, the front edge's its length — and never a picture.
  ///
  /// THE timeline's chrome layer, not a cut-shaped copy of it: one painter
  /// and one gesture layer for the row, where this used to be two widgets a
  /// cut.
  Widget _edgeChrome(
    BuildContext context,
    StoryboardCutBlocksPainter blocksPainter,
  ) => Positioned.fill(
    key: ValueKey<String>(
      'storyboard-plate-edit-chrome-slot-${trackId.value}',
    ),
    child: TimelineRowEditChromeLayer(
      paintName: 'storyboard-plate-edit-chrome-${trackId.value}',
      // What the triangles stand on: the plate, and over it the block's
      // label bands and pictures, each in its own ink (유저 2026-09-26:
      // 「2여도 흰종이부분에 엣지는 1처럼 제대로 보이게 가능하지?」). ↩️One
      // ground for the whole row — the plate's, whose bands were the plate's
      // colour then (유저 2026-09-25: 「배경이 어두워서 엣지가 잘 안보여」).
      gripGround: storyboardCutBlockBackgroundColor(
        Theme.of(context).colorScheme,
        hovered: false,
      ),
      gripGrounds: () => StoryboardPlateGrounds(blocksPainter),
      // The blocks' own window: the row spans the whole film, and the grips
      // are drawn where the view can reach, as the blocks under them are.
      windowBucket: windowBucket,
      // No layer: these blocks are cuts, and the row has no run edges for a
      // LayerId to name.
      layerId: null,
      resolver: TimelineRowChromeResolver(
        gripBlocks: [
          for (var index = 0; index < layoutEntries.length; index += 1)
            (
              ordinal: index,
              startIndex: layoutEntries[index].startFrame,
              endIndexExclusive: layoutEntries[index].endFrame,
              startGrip: true,
              endGrip: true,
            ),
        ],
        gripIdScope: trackId.value,
        layer: null,
        baseLayer: null,
        crossAxisExtent: laneHeight,
        axis: Axis.horizontal,
        includeRunEdges: false,
        // Every cut starts a plate and ends it, and the grips stand in the
        // plate's bands — in its round corners, which the block law rounds
        // for the plate and the grip alike.
        gripBand: StoryboardCutBlocksPainter.bandHeight,
      ),
      geometry: frameGeometry,
      axis: Axis.horizontal,
      // The row closes the identity in, by ordinal — the grip hooks
      // themselves know nothing about cuts.
      grips: TimelineRowGripCallbacks(
        // R10 R4: no impersonation. A grip reports the edge it IS, and the
        // rule that decides what moves lives one layer down, in the session.
        // The cut's own lead edge is its first panel's (ordinal 0).
        onBegin: (_, ordinal, edge) =>
            ordinal >= 0 &&
            ordinal < layoutEntries.length &&
            stripEdges!.onCutEdgeBegin(layoutEntries[ordinal].cutId, edge, 0),
        onUpdate: stripEdges!.onUpdate,
        onEnd: stripEdges!.onEnd,
        onCancel: stripEdges!.onCancel,
      ),
      runEdit: null,
    ),
  );

  /// Whether [frame] sits in the live selection — a plain range test now
  /// that the selection IS a range on this row's own axis.
  bool _isSelectedAt(int frame) => _storyboardRangeCovers(
    cutSelect?.selectedRange.value,
    TrackRowAddress(trackId),
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
            trackId: trackId,
            anchorGlobalFrame: anchorIndex,
            headGlobalFrame: headIndex,
            spanRows:
                railSweepAt?.call(TrackRowAddress(trackId), headCrossOffset) ??
                const [],
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
  /// The pointer DOWN runs under this ONE gate pair: secondary buttons are
  /// not presses here, and a press inside the live selection is starting a
  /// move, so it does not seek. ↩️The D30 create ran under it too, while a
  /// cut with no storyboard layer wore its button here (I-73: the conte
  /// row's).
  bool _pressDownGated(PointerDownEvent event) {
    if (event.buttons != 0 && (event.buttons & kPrimaryButton) == 0) {
      return true;
    }
    return _isSelectedAt(_frameAtX(event.localPosition.dx));
  }

  void _handlePressDown(PointerDownEvent event) {
    onRowFramePress?.call(
      TrackRowAddress(trackId),
      _frameAtX(event.localPosition.dx),
    );
  }

  int _frameAtX(double x) =>
      timelineScale.pixelsPerFrame <= 0 ? 0 : timelineScale.frameAt(x);

  void _handleHover(PointerHoverEvent event) {
    hoveredCutId.value = _cutAtFrame(_frameAtX(event.localPosition.dx))?.cutId;
  }

  /// What the row shows — its cuts by how they lie
  /// ([StoryboardTimelineLayoutEntry.==]), the cut you stand on by the one
  /// listenable its track holds ([_StoryboardStanding.standingCutOn]), the
  /// linked cuts by who they are, and the pictures by the store they come
  /// from.
  ///
  /// 🚨I-57 (10-14): built again with the panel on every notify and every
  /// cut crossed, the row painted every cut block of the track again, its
  /// pictures and its words, and said them again to a screen reader.
  @override
  Object? get facts => (
    trackId,
    ByList(layoutEntries),
    laneHeight,
    width,
    timelineScale.pixelsPerFrame,
    timelineScale.minBlockWidth,
    ByIdentity(frameGeometry),
    ByIdentity(hoveredCutId),
    ByIdentity(standingCutId),
    ByIdentity(windowBucket),
    showSeconds,
    projectFrameRate,
    thumbnails,
    BySet(linkedCutIds),
    onRowFramePress != null,
    onDropMediaAsset != null,
    acceptsMediaAsset != null,
    stripEdges != null,
    cutMove != null,
    cutSelect != null,
    railSweepAt != null,
    onOpenCutLinks != null,
    onEditCutBlock != null,
  );

  @override
  Widget buildKept(BuildContext context) {
    final timelineWidth = _storyboardCutsExtent(layoutEntries, timelineScale);
    final rangeGesture = _rangeGesture();
    final drop = onDropMediaAsset;

    // Held in a local so the press layer hit-tests the SAME visuals the
    // paint lays down (the link icon reads the block's band).
    //
    // Through the shared builder (D15): the folded storyboard draws its
    // row with this same call, so the picture there cannot be a second
    // opinion about thumbnails, names or where the writing sits.
    final blocksPainter = storyboardCutBlocksPainterFor(
      entries: layoutEntries,
      geometry: frameGeometry,
      crossAxisExtent: laneHeight,
      minBlockWidth: timelineScale.minBlockWidth,
      selectedRange: cutSelect?.selectedRange,
      rowAddress: TrackRowAddress(trackId),
      hoveredCutId: hoveredCutId,
      standingCutId: standingCutId,
      colorScheme: Theme.of(context).colorScheme,
      baseTextStyle: DefaultTextStyle.of(context).style,
      showSeconds: showSeconds,
      countingBase: projectFrameRate.countingBase,
      thumbnails: thumbnails,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      windowBucket: windowBucket,
      linkedCutIds: linkedCutIds,
    );

    return KeyedSubtree(
      key: ValueKey<String>('storyboard-track-row-${trackId.value}'),
      child: SizedBox(
        key: ValueKey<String>(
          'storyboard-track-timeline-area-${trackId.value}',
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
                    'storyboard-cut-blocks-${trackId.value}',
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
              key: ValueKey<String>('storyboard-cut-press-${trackId.value}'),
              child: MouseRegion(
                onHover: _handleHover,
                onExit: (_) => hoveredCutId.value = null,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    _onCutPressDown(context, event, blocksPainter);
                  },
                  // …and its ACTIVATION half, on the same gate, INSIDE the
                  // press: a pointer down reaches the deepest handler
                  // first, so the first press is read here before the
                  // second one's record above replaces it — the order the
                  // cells' two halves keep.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTapDown: (details) {
                      final cell = _doubleClickCellAt(details.localPosition);
                      if (cell != null) {
                        timelineCellDoubleTapActivation(
                          row: cell.row,
                          cells: cell.cells,
                          onActivate: (_) => cell.open(),
                        )(details);
                      }
                    },
                    onDoubleTap: () {},
                  ),
                ),
              ),
            ),
            // THE range gesture — the timeline's, not a copy of it: a pan
            // paints a cut run, a pan starting inside the selection slides
            // it. Mounted UNDER the grips so the edges keep trim priority.
            if (rangeGesture != null)
              TimelineFrameRangeGestureLayer(
                key: ValueKey<String>(
                  'storyboard-cut-range-gesture-slot-${trackId.value}',
                ),
                row: TrackRowAddress(trackId),
                geometry: frameGeometry,
                crossAxisExtent: laneHeight,
                callbacks: rangeGesture,
              ),
            // THE EDGES, at the cuts' two ends ([_edgeChrome]). They ride
            // ABOVE the cut gesture so an edge keeps its priority over it;
            // the middles keep the rest.
            if (stripEdges != null) _edgeChrome(context, blocksPainter),
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
                    'storyboard-track-asset-drop-${trackId.value}',
                  ),
                  rowContext: context,
                  row: TrackRowAddress(trackId),
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

  /// The CELL of this row a double click at a position aims at, as the frame
  /// blocks' gate takes it ([timelineCellDoubleTapRecord]), and what a
  /// double click on it opens — null where no block stands.
  ///
  /// 🗣️F-255 (유저 2026-10-01): 「이름변경 입구 확대. 지금 프레임블록이랑
  /// 레이어라벨 더블클릭하면 이름편집인데 콘티블록이나 컷블록에도
  /// 통일적용」 — anywhere on a cut block, the CUT: a cell of the track's row.
  /// ↩️The row held TWO papers while the conte blocks were drawn inside the
  /// cut block, and a position over them named the conte block; that double
  /// click is the conte row's now (I-73).
  ({TimelineRowAddress row, TimelineDoubleTapCells cells, VoidCallback open})?
  _doubleClickCellAt(Offset localPosition) {
    TimelineDoubleTapCells cellAt(int? frame) => (
      frameAt: (_) => frame,
      axis: Axis.horizontal,
      cellExtent: () => timelineScale.pixelsPerFrame,
    );
    // Aimed FIRST, the way the gate aims a cell narrower than a pixel
    // ([timelineDoubleTapAim]): the frame is read off the aimed spot, so a
    // pixel that straddles two cuts names one block.
    final frame = _frameAtX(
      timelineDoubleTapAim(localPosition, cellAt(null)).dx,
    );
    final onEditCutBlock = this.onEditCutBlock;
    // A frame no cut covers is no cell: a gap holds no block.
    if (onEditCutBlock == null || _cutAtFrame(frame) == null) {
      return null;
    }
    return (
      row: TrackRowAddress(trackId),
      cells: cellAt(frame),
      open: () => onEditCutBlock(trackId, frame),
    );
  }

  /// A press on the cut blocks: gated first, then the press itself, then
  /// the link icon judged on the painter this build drew.
  void _onCutPressDown(
    BuildContext context,
    PointerDownEvent event,
    StoryboardCutBlocksPainter blocksPainter,
  ) {
    // The frame block's activation law, RECORD half: which cell this press
    // hit, whatever the device and whatever the press goes on to do — the
    // recogniser reports only the second tap.
    if (_doubleClickCellAt(event.localPosition) case final cell?) {
      timelineCellDoubleTapRecord(
        row: cell.row,
        cells: cell.cells,
      )(event.localPosition);
    }
    if (_pressDownGated(event)) {
      return;
    }
    _handlePressDown(event);
    _maybeOpenCutLinks(context, blocksPainter, event);
  }

  /// I-25: a press inside a linked cut's link icon opens the link window —
  /// the rect is [StoryboardCutBlocksPainter.linkAffordanceRectOf]'s, the
  /// SAME call the paint made (the D30 create affordance's shape).
  void _maybeOpenCutLinks(
    BuildContext context,
    StoryboardCutBlocksPainter painter,
    PointerDownEvent event,
  ) {
    final onOpen = onOpenCutLinks;
    final block = onOpen == null ? null : painter.blockAt(event.localPosition);
    final icon = block == null ? null : painter.linkAffordanceRectOf(block);
    if (icon == null || !icon.contains(event.localPosition)) {
      return;
    }
    onOpen!(context, block!.cutId);
  }
}

/// The cut of [entries] — a track's, in order — covering track-global
/// [frame], or null in a gap / past the end: the same answer
/// [TrackFrameAxis.cutBlockAt] gives the shared snap rule. The V row's cuts
/// and the conte row's panels are both found by it.
StoryboardTimelineLayoutEntry? _cutEntryAt(
  List<StoryboardTimelineLayoutEntry> entries,
  int frame,
) {
  for (final entry in entries) {
    if (frame < entry.startFrame) {
      return null;
    }
    if (frame < entry.endFrame) {
      return entry;
    }
  }
  return null;
}

/// How far along the frame axis a track's cuts reach as [entries] lay them,
/// with room past the last — what the V row and the conte row under it are
/// at least as wide as, so a cut a drag has pushed past the content's width
/// is still under a pointer.
double _storyboardCutsExtent(
  List<StoryboardTimelineLayoutEntry> entries,
  TimelineScale scale,
) {
  const trailingPadding = 12.0;

  if (entries.isEmpty) {
    return 0;
  }

  return entries
          .map((entry) => scale.blockEndFor(entry.startFrame, entry.duration))
          .reduce((width, nextWidth) => width > nextWidth ? width : nextWidth) +
      trailingPadding;
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

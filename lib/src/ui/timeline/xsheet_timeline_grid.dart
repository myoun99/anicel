import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite;
import '../../models/app_language.dart' show AppLanguage;
import '../../models/attached_placement.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'layer_rail_window.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import 'timeline_cell_style.dart';
import 'timeline_frame_ruler_painter.dart'
    show TimelineRulerHeaderModel, timelineRulerSecondsLabel;
import 'timeline_body_norishiro_boundary.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import '../../models/project_frame_rate.dart';
import '../../models/timeline_row_address.dart';
import 'timeline_row_cross_offset.dart';
import 'timeline_selected_exposure_outline.dart' show TimelineSelectionRing;
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'layer_drop_policy.dart'
    show effectHeaderRowsOf, effectStepsBetween, slotForSteps;
import 'layer_row_drag.dart';
import 'timeline_current_row.dart';
import 'timeline_edge_auto_pan.dart';
import 'timeline_row_span_resolver.dart'
    show resolveBlockMoveTargetLayer, resolveLaneSpanEscalation;
import 'timeline_frame_range_gesture.dart';
import 'timeline_ruler_cursor_overlay.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_frame_cells_row.dart' show TimelineFrameCellsRow;
import 'timeline_frame_geometry.dart'
    show TimelineFrameGeometry, timelineFrameWindowMarginPx;
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_frame_cursor_layer.dart';
import 'timeline_beat_lines.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_body_cut_end_boundary.dart';
import 'timeline_cell_editor_policy.dart';
import 'property_lane_model.dart';
import 'timeline_row_filter.dart';
import 'timeline_grid_metrics.dart';
import 'se_audio_lane.dart';
import 'timeline_lane_rows.dart';
import 'timeline_horizontal_offset_policy.dart';
import 'timeline_layer_controls_header.dart';
import '../text/vertical_writing_text.dart';
import 'pen_friendly_scroll_controller.dart';
import 'stylus_glide_stop.dart';
import 'timeline_horizontal_scrollbar_rail.dart';
import 'timeline_ruler_cut_end_boundary.dart';
import 'timeline_ruler_norishiro_boundary.dart';
import 'timeline_section_policy.dart';
import 'timeline_section_runs.dart';
import 'timeline_vertical_scrollbar_rail.dart';
import 'timeline_virtualization_plan.dart';
import 'timeline_visible_range.dart';
import 'timeline_zoom_anchor_policy.dart';

/// The vertical X-sheet: the SAME grid logic as the horizontal
/// [LayerTimelineGrid], transposed.
///
/// The transposition is a metrics trick: the frame axis runs vertically, so
/// [_metrics.frameCellWidth] is the frame ROW height and
/// [_metrics.layerRowHeight] is the layer COLUMN width. Every policy the
/// horizontal grid uses — frame range, offset resolution, virtualization
/// plan, coordinate conversion, cell style/block visuals, selected exposure
/// range, playhead visibility, cut-end boundary — is reused unchanged with
/// the axes swapped; only the thin widget composition differs.
class XSheetTimelineGrid extends StatefulWidget {
  const XSheetTimelineGrid({
    super.key,
    required this.layers,
    required this.activeLayerId,
    required this.frameCursor,
    this.frameReadySignal,
    this.revealSelectionTick,
    required this.frameCount,
    this.drawnFrameCount,
    this.noriShiroLabel = '',
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    this.celContent,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onSettledPress,
    this.onScrubFrame,
    this.onScrubEnd,
    this.onActivateCell,
    this.instructionDefById,
    this.audioPeaksFor,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.showSeconds = false,
    this.onShowSecondsChanged,
    this.railExtent,
    this.audioLane,
    this.onDropMediaAssetOnLayer,
    this.isLayerSoloed,
    this.onOpenLayerMixer,
    this.attachArrowPlacementOf,
    required this.onAddLayer,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.opacityDragPreview,
    required this.onToggleLayerTimesheet,
    required this.onLayerMarkSelected,
    this.layerFxStateOf,
    this.onToggleLayerFx,
    this.onToggleLayerFillReference,
    this.onToggleLayerOnionSkin,
    this.layerOnionSkinEnabledOf,
    this.onLayerBlendModeSelected,
    this.blendLanguage = AppLanguage.en,
    this.commaDrag,
    this.rangeHooks,
    this.laneRange,
    this.currentRowHooks,
    this.rowDragHooks,
    this.selectedRows = const {},
    this.onRowSelectionSpan,
    this.runEdit,
    this.isFrameReady,
    this.metrics = defaultMetrics,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.lanesForLayer,
    this.unionLaneForLayer,
    this.laneEdit,
    this.onToggleLaneGroup,
    this.onToggleLaneGroupEnabled,
    this.onResetLaneGroup,
    this.hiddenSections = const {},
    this.rowFilter = TimelineRowFilter.none,
    this.collapsedAttachBaseIds = const {},
    this.onToggleLayerCollapsed,
    this.onToggleAttachGroup,
    this.seSpillInLayerIds = const {},
    this.seClipMarkerTooltip,
    this.dragPreview,
    this.cutEndDrag,
    this.substrateGeneration = '',
  });

  /// #29: the (project, cut) world this grid's resolvers answer from —
  /// see [TimelineRowCellsPainter.substrateGeneration].
  final String substrateGeneration;

  final List<Layer> layers;
  final LayerId? activeLayerId;

  /// Track-SE layers whose sound spills in from the previous cut (UI-R7 #6):
  /// their first block shows the `~` continuation mark instead of a start
  /// grip. Mirrors the horizontal timeline's plumbing.
  final Set<LayerId> seSpillInLayerIds;

  /// The recorded-take clipping warning tooltip (REC1-D): non-null mounts
  /// the red block-corner marker on SE cells, matching the horizontal
  /// timeline. Null hides it (the "clipping notice" setting is off).
  final String? seClipMarkerTooltip;

  /// The session's edit-drag preview channel: a comma-drag step rebuilds
  /// only the dragged layer's column (its gate) and the cursor overlay —
  /// never this grid.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// End-line drag hooks (UI-R18 #14): the red cut-end boundary grows a
  /// grip that end-trims the ACTIVE cut; the line follows the live trim
  /// preview. Null = display-only.
  final TimelineCutEndDragCallbacks? cutEndDrag;

  /// The frame cursor (editing playhead / playback position). Only the
  /// cursor layer, the frame-number rail and the lane headers subscribe —
  /// ticks never rebuild the grid (playback-performance architecture,
  /// mirroring the horizontal timeline).
  final ValueListenable<int> frameCursor;

  /// Repaints the frame rail's cached-range green strip as frames warm.
  final Listenable? frameReadySignal;

  /// R5: the session's "bring the selection back into view" tick.
  final ValueListenable<int>? revealSelectionTick;

  /// Playback frame count of the active cut (the visible range extends to
  /// the shared minimum, exactly like the horizontal timeline).
  final int frameCount;

  /// How many frames the cut is DRAWN for (尺 + のりしろ) and the word the
  /// frame rail spells across the difference. Null/empty keeps it off.
  final int? drawnFrameCount;
  final String noriShiroLabel;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact and its event (null = no tint).
  final TimelineCelContentSource? celContent;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// 🚨T10's second half: a press that turned out to be a TAP clears
  /// whatever was selected (유저: 「클릭하고 떼면 뭐든 비우게」). The sheet
  /// is the same surface stood up, so it takes the same law.
  final VoidCallback? onSettledPress;

  /// Frame-rail scrub path: per-move frames go to [onScrubFrame]
  /// (cursor-only, no commit) and the pointer's release fires [onScrubEnd]
  /// to commit once. Null falls back to [onSelectFrame] per move.
  final ValueChanged<int>? onScrubFrame;
  final VoidCallback? onScrubEnd;

  /// Double-tap cell editor hook (SE label dialog; see
  /// [layerKindOpensCellEditorOnDoubleTap]).
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// Resolves instruction ids to defs for CAM column chips.
  final CameraInstructionDef? Function(String instructionId)?
  instructionDefById;

  /// Waveform peaks for SE columns' audio clips + the removal hook.
  final AudioPeaks? Function(String filePath)? audioPeaksFor;
  final ProjectFrameRate projectFrameRate;

  /// The frame rail's number mode (UI-R10 #27): seconds display repeats
  /// 1..fps per second instead of absolute frame numbers.
  final bool showSeconds;

  /// The toggle itself, in the corner where the two axes meet (it used to
  /// be a command-bar button). Null leaves the corner blank.
  final ValueChanged<bool>? onShowSecondsChanged;

  /// The header block's window size, set by this sheet's splitter and
  /// persisted by the workspace. Null = a session-local one of our own.
  final LayerRailExtent? railExtent;

  /// What the audio lane may ask the session to do; null = display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// A media-browser row dropped on a drawing column; null refuses the drag.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onDropMediaAssetOnLayer;

  /// The SE column's mixer (R10 R3): its solo tint, and the speaker press
  /// that opens the window carrying mute/solo/fader/pan. Null hides the
  /// speaker.
  final bool Function(LayerId layerId)? isLayerSoloed;
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  /// Which way a column's attach ARROW points in its sheet slot (R10 R3),
  /// or null off an attach group. A RESOLVER for the same reason the rail
  /// takes one: the answer is stack order against the base, and a grid is
  /// handed a DISPLAY order.
  final AttachedPlacement? Function(LayerId layerId)? attachArrowPlacementOf;

  final VoidCallback onAddLayer;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  /// The session's live opacity-drag preview (UI-R6 #2).
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  final ValueChanged<LayerId> onToggleLayerTimesheet;
  final void Function(LayerId layerId, LayerMark mark) onLayerMarkSelected;

  /// The AE-style layer fx MASTER (R8: persisted, tri-state); null hides it.
  final LayerFxState Function(LayerId layerId)? layerFxStateOf;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// Drawing rows' fill-reference toggle (R20-C2); null hides it.
  final ValueChanged<LayerId>? onToggleLayerFillReference;

  /// The ONION and BLEND columns (UI-R17 #5, R27 #6). The sheet went
  /// without them until the user's R10 R6 call — "타임라인에 있는거 싹다
  /// 넣어" — and the panel had been holding both callbacks all along,
  /// passing them to the horizontal grid only.
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;
  final bool Function(LayerId layerId)? layerOnionSkinEnabledOf;
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;

  /// PROGRAM language for the blend column's mode names.
  final AppLanguage blendLanguage;

  /// Comma-drag hooks for the block edge grips (shared policy with the
  /// horizontal timeline); null hides the grips.
  final TimelineCommaDragCallbacks? commaDrag;

  /// The frame-range select/move hooks (UI-R8, the block-body move's
  /// successor): the grid resolves the pointer's COLUMN onto display
  /// entries and forwards frame delta + target layer to the session.
  final TimelineFrameRangeHooks? rangeHooks;

  /// The LANE selection domain's gesture bundle (UI-R23 #3 part 2); null
  /// keeps the lane bands display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  /// Which row the frame-axis verbs act on, and the label press that moves
  /// it (R10 #19's rail half); null leaves lane headers inert and unwashed.
  final TimelineCurrentRowHooks? currentRowHooks;

  /// The row-order drag. The sheet's columns ARE the rail's rows stood up,
  /// so the same handle rule applies along its own axis: grabbing a column
  /// header moves that layer, an fx header re-orders that chain.
  final TimelineRowDragHooks? rowDragHooks;

  /// ⑨: the row SELECT drag's span, in this sheet's own display columns —
  /// the rail's rule along the other axis, so the two surfaces select the
  /// same way without either learning the other's order.
  final void Function(List<TimelineDisplayRow> rows, int rowDelta)?
  onRowSelectionSpan;

  /// ⑨: the columns currently selected, as layer ids.
  final Set<TimelineRowAddress> selectedRows;

  /// The run-edge [+]/[↻] handle hooks (UI-R8); null hides the handles.
  final TimelineRunEditCallbacks? runEdit;

  /// Cached-range resolver for the frame rail's green strip (the transposed
  /// counterpart of the horizontal ruler's strip).
  final bool Function(int frameIndex)? isFrameReady;

  /// Grid geometry (transposed); frameCellWidth carries the frame-axis zoom
  /// as the frame ROW height here.
  final TimelineGridMetrics metrics;

  /// AE-style property lanes, transposed: an expanded layer's lanes appear
  /// as COLUMNS beside it (the layer axis runs horizontally here). Same
  /// generic provider + edit hooks as the horizontal timeline.
  final Set<LayerId> expandedLaneLayerIds;
  final ValueChanged<LayerId>? onToggleLayerLanes;
  final List<PropertyLaneRow> Function(Layer layer)? lanesForLayer;

  /// The union-summary provider (the CAMERA column's key markers, B4) —
  /// see [TimelineFrameRowsScrollBody.unionLaneForLayer].
  final PropertyLaneRow? Function(Layer layer)? unionLaneForLayer;

  final PropertyLaneEditCallbacks? laneEdit;

  /// Group headers: tapping twirls the group's member lanes (AE collapse).
  final void Function(Layer layer, PropertyLaneRow lane)? onToggleLaneGroup;

  /// The group header's own ON/OFF switch (R6), forwarded to the lane rows.
  final void Function(Layer layer, PropertyLaneRow lane)?
  onToggleLaneGroupEnabled;

  /// The group header's RESET (R5), forwarded to the lane rows.
  final void Function(Layer layer, PropertyLaneRow lane)? onResetLaneGroup;

  /// Sections hidden from the grid entirely (toolbar visibility toggles;
  /// the section axis runs horizontally here, so hiding drops columns).
  final Set<TimelineSection> hiddenSections;

  /// The rail's row FILTER (R2): drops the columns of layers failing its
  /// predicate; the active layer is exempt. Shared with the horizontal
  /// timeline (Axis rule).
  final TimelineRowFilter rowFilter;

  /// Bases whose attach group is twirled shut (UI-R20 #9): their attach
  /// columns drop — the shared view state; the fold toggle lives on the
  /// horizontal rail.
  final Set<LayerId> collapsedAttachBaseIds;

  /// The GROUP-FOLD twirl's two commits — a folder folding its members, an
  /// attach base folding its rows. R5 #2: the sheet already HID what those
  /// sets say (it reads [collapsedAttachBaseIds] and `subtreeCollapsed`
  /// like the rail does), but it carried no control to say it with, so a
  /// folder could only be folded from the other panel. One skeleton, one
  /// row vocabulary — a column that shows a fold has to offer it.
  final ValueChanged<LayerId>? onToggleLayerCollapsed;
  final ValueChanged<LayerId>? onToggleAttachGroup;

  /// TRANSPOSED metrics: frameCellWidth = frame row height, layerRowHeight
  /// = layer column width, layerControlsWidth = frame-number rail width.
  /// No section gutter here — the X-sheet's section axis is horizontal and
  /// section controls live on the column headers.
  ///
  /// R10 R6: every number here is now the timeline's, turned on its side.
  /// They used to be 36/164/72 — hand-tuned, and free to drift the moment
  /// anyone touched the timeline. A column is exactly as wide as a row is
  /// tall now, which is what makes the two grids read as one grid.
  static const TimelineGridMetrics defaultMetrics = TimelineGridMetrics(
    // A frame ROW is as tall as a frame CELL is wide.
    frameCellWidth: timelineFrameCellWidth,
    // A layer COLUMN is as wide as a layer ROW is tall — 164 → 28. This is
    // the change that makes everything in the header stand up: nothing
    // reads horizontally in 28px.
    layerRowHeight: timelineLayerRowHeight,
    // The frame-number RAIL is as wide as the ruler is tall — 72 → 28. If
    // the seconds label gets tight it is fixed in the SHARED ruler, so both
    // panels get better at once (no per-panel exception).
    layerControlsWidth: timelineFrameRulerExtent,
    sectionLabelGutterWidth: 0,
  );

  /// The section band above the layer headers: the paper sheet's
  /// ACTION/SE/CAM group headings, each wrapping its columns. It is the
  /// rail's reserved section SLOT stood up, so it is that slot's extent.
  static const double _sectionBandHeight = layerSectionLabelSlotWidth;

  /// ★ The header block is the timeline's rail, turned on its side — EVERY
  /// control single file, plus a name as generous as the rail's own name
  /// column. That equality is the point: making the rail compact makes the
  /// sheet's header shallow, with nothing to remember.
  ///
  /// R10 R6 shed columns a short panel could not afford; the user's call
  /// was the opposite — "타임라인에 있는거 싹다 넣어. 뭐 빼지말고" — and
  /// R6a answered it by scaling the whole column down. Both are gone. The
  /// block is ALWAYS this tall, and a panel that cannot spend it sees a
  /// narrower WINDOW onto it (the rail-window round): the tail is cut, the
  /// splitter says where, and nothing inside rearranges.
  ///
  /// [hasOnionColumn]/[hasBlendColumn] are the HOST's answer about which
  /// optional columns exist at all — the legend beside the headers must
  /// size from the same answer or its icons stop naming the columns under
  /// them.
  static double naturalHeaderBlockExtent({
    required bool hasOnionColumn,
    required bool hasBlendColumn,
  }) =>
      _sectionBandHeight +
      (layerRailLeadingWidth - layerSectionLabelSlotWidth) +
      _naturalNameExtent +
      layerRailTrailingWidth(
        hasOnionColumn: hasOnionColumn,
        hasBlendColumn: hasBlendColumn,
      ) +
      _headerBorderExtent;

  /// The NAME's share of the rail — what the horizontal row's `Expanded`
  /// resolves to once every slot has been served.
  static const double _naturalNameExtent =
      timelineLayerControlsWidth -
      layerRailLeadingWidth -
      layerFillReferenceSlotWidth -
      layerFxSlotWidth -
      layerOnionSlotWidth -
      layerVisibilitySlotWidth -
      layerMuteSlotWidth -
      layerOpacitySlotWidth -
      layerBlendSlotWidth;

  /// The column header's own hairlines, top and bottom.
  static const double _headerBorderExtent = 2;

  @override
  State<XSheetTimelineGrid> createState() => _XSheetTimelineGridState();
}

class _XSheetTimelineGridState extends State<XSheetTimelineGrid> {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.projectFrameRate.countingBase;

  /// Resolves range-move column deltas against the entries built this pass.
  final TimelineRangeMoveRowResolver _rangeMoveResolver =
      TimelineRangeMoveRowResolver();

  /// The LIVE frame-axis geometry the painted columns follow (R28 #4 — the
  /// timeline's rule, transposed). Its identity outlives zoom steps, so the
  /// row memo hands cached columns back while the geometry underneath moves;
  /// listeners are render objects only (see the timeline body's note).
  final ValueNotifier<TimelineFrameGeometry> _frameGeometry = ValueNotifier(
    const TimelineFrameGeometry(
      frameCellExtent: 1,
      frameStartIndex: 0,
      frameEndIndexExclusive: 0,
    ),
  );

  /// The WINDOWED twin (zoom round, the timeline body's split transposed):
  /// the columns whose every consumer reads geometry live are laid out at a
  /// constant pixel window instead of `frames * cellHeight`, so a zoom step
  /// re-lays-out one box per column rather than everything inside it. The
  /// sparse kinds keep [_frameGeometry] — their span overlays are widgets
  /// positioned from build-time scalars, and a window sliding under them
  /// without a rebuild would strand them.
  final ValueNotifier<TimelineFrameGeometry> _windowedFrameGeometry =
      ValueNotifier(
        const TimelineFrameGeometry(
          frameCellExtent: 1,
          frameStartIndex: 0,
          frameEndIndexExclusive: 0,
        ),
      );

  /// The frame-axis viewport recorded by the last build — the window's
  /// extent, needed again when the bucket moves outside a build.
  double _frameViewportExtent = 0;

  /// The fallback rail extent for hosts that keep none of their own.
  LayerRailExtent? _ownedRailExtent;

  LayerRailExtent get _railExtent =>
      widget.railExtent ?? (_ownedRailExtent ??= LayerRailExtent());

  /// The header block's NATURAL extent for this sheet — what the stood-up
  /// rail costs laid out in full. The window never changes it.
  double get _naturalHeaderBlockExtent =>
      XSheetTimelineGrid.naturalHeaderBlockExtent(
        hasOnionColumn: widget.onToggleLayerOnionSkin != null,
        hasBlendColumn: widget.onLayerBlendModeSelected != null,
      );

  /// Just the column headers — the band strip has its own row above.
  double get _naturalHeaderExtent =>
      _naturalHeaderBlockExtent - XSheetTimelineGrid._sectionBandHeight;

  TimelineFrameGeometry _baseFrameGeometry() => TimelineFrameGeometry(
    frameCellExtent: _metrics.frameCellWidth,
    frameStartIndex: 0,
    frameEndIndexExclusive: _renderedFrameCount,
  );

  TimelineFrameGeometry _windowedFrameGeometryValue() {
    final base = _baseFrameGeometry();
    final cellExtent = base.frameCellExtent;
    if (_frameViewportExtent <= 0 || cellExtent <= 0) {
      return base;
    }
    final spanPx = timelineFrameWindowSpanFor(cellExtent) * cellExtent;
    return base.windowed(
      originPx: math.max(
        0.0,
        _frameWindowBucket.value * spanPx - timelineFrameWindowMarginPx,
      ),
      extentPx: _frameViewportExtent + 2 * timelineFrameWindowMarginPx,
    );
  }

  void _handleFrameWindowBucket() {
    _windowedFrameGeometry.value = _windowedFrameGeometryValue();
  }

  /// The handle every column follows (see [_windowedFrameGeometry]).
  ///
  /// EVERY kind takes the windowed one now: the sparse columns' span
  /// overlays are placed by [TimelineFrameSpanLayout] at layout time, so a
  /// window sliding under them carries them along.
  ValueNotifier<TimelineFrameGeometry> _publishFrameGeometry(LayerKind kind) {
    _frameGeometry.value = _baseFrameGeometry();
    _windowedFrameGeometry.value = _windowedFrameGeometryValue();
    return _windowedFrameGeometry;
  }

  /// The per-build gesture bundle (rebuilt in [build], consumed by the
  /// column builder).
  TimelineRangeGestureCallbacks? _rangeGesture;

  /// The per-build LANE gesture bundle (B4-④): the host's callbacks with
  /// the escalation seam wrapped in — a lane-anchored drag that leaves its
  /// own group joins the cells law, exactly as on the horizontal grid.
  TimelineLaneRangeCallbacks? _laneRange;

  late final ScrollController _frameScrollController;
  late final ScrollController _layerScrollController;

  /// Frame-axis offset + window bucket notifiers (UI-R9 #12a, the
  /// horizontal grid's structure transposed): scroll pixels move the rail
  /// translate only; cell crossings re-window the columns; the grid never
  /// rebuilds per pixel.
  final ValueNotifier<double> _frameAxisOffset = ValueNotifier<double>(0);
  final ValueNotifier<int> _frameWindowBucket = ValueNotifier<int>(0);
  ScrollPosition? _watchedFramePosition;

  double _lastEffectiveFrameScrollOffset = 0;
  double? _scheduledFrameOffsetCorrection;
  int _endlessTrailingFrames = 0;
  final GlobalKey _railScrubViewportKey = GlobalKey();
  int? _lastRailScrubbedFrameIndex;

  TimelineGridMetrics get _metrics => widget.metrics;

  @override
  void initState() {
    super.initState();
    // PEN-10: pen-friendly positions — while a stylus is nearby, a
    // coasting fling stops hiding the cells from hit-testing.
    _frameScrollController = PenFriendlyScrollController();
    _layerScrollController = PenFriendlyScrollController();
    _frameScrollController.addListener(_handleFrameScroll);
    _frameWindowBucket.addListener(_handleFrameWindowBucket);
    widget.revealSelectionTick?.addListener(_handleRevealSelection);
  }

  /// R5: the same reveal the rail does, asked of THIS surface's axes — the
  /// frame runs down here and the columns run across, so one tick lands on
  /// two different controllers without either side knowing the other's.
  void _handleRevealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _revealSelection();
      }
    });
  }

  void _revealSelection() {
    final cell = _metrics.frameCellWidth;
    if (_frameScrollController.hasClients && cell > 0) {
      final position = _frameScrollController.position;
      final target = revealScrollOffset(
        offset: position.pixels,
        viewport: position.viewportDimension,
        start: widget.frameCursor.value * cell,
        extent: cell,
        margin: cell,
      ).clamp(position.minScrollExtent, position.maxScrollExtent);
      if (target != position.pixels) {
        _frameScrollController.jumpTo(target);
      }
    }
    final columnWidth = _metrics.layerRowHeight;
    final activeId = widget.activeLayerId;
    if (!_layerScrollController.hasClients ||
        activeId == null ||
        columnWidth <= 0) {
      return;
    }
    final at = _dragRows.indexWhere(
      (row) => !row.isLane && row.layer.id == activeId,
    );
    if (at < 0) {
      return;
    }
    final position = _layerScrollController.position;
    final target = revealScrollOffset(
      offset: position.pixels,
      viewport: position.viewportDimension,
      start: at * columnWidth,
      extent: columnWidth,
      margin: columnWidth,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      _layerScrollController.jumpTo(target);
    }
  }

  @override
  void didUpdateWidget(covariant XSheetTimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealSelectionTick != widget.revealSelectionTick) {
      oldWidget.revealSelectionTick?.removeListener(_handleRevealSelection);
      widget.revealSelectionTick?.addListener(_handleRevealSelection);
    }
    // Zoom-around-playhead (transposed): the playhead ROW stays put on
    // screen through zoom when visible; otherwise the top-edge frame
    // anchors. Same policy as the horizontal timeline (Axis rule).
    final oldCell = oldWidget.metrics.frameCellWidth;
    final newCell = widget.metrics.frameCellWidth;
    if (oldCell != newCell && _frameScrollController.hasClients) {
      _frameScrollController.jumpTo(
        zoomAnchoredScrollOffset(
          oldOffset: _frameScrollController.offset,
          oldPixelsPerFrame: oldCell,
          newPixelsPerFrame: newCell,
          viewportExtent: _frameScrollController.position.viewportDimension,
          anchorFrame: widget.frameCursor.value,
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.revealSelectionTick?.removeListener(_handleRevealSelection);
    _watchedFramePosition?.isScrollingNotifier.removeListener(
      _handleFrameScrollActivity,
    );
    _frameScrollController
      ..removeListener(_handleFrameScroll)
      ..dispose();
    _layerScrollController.dispose();
    _frameWindowBucket.removeListener(_handleFrameWindowBucket);
    _frameGeometry.dispose();
    _windowedFrameGeometry.dispose();
    _frameAxisOffset.dispose();
    _frameWindowBucket.dispose();
    _ownedRailExtent?.dispose();
    super.dispose();
  }

  /// Frame-axis scroll (UI-R9 #12a): NO setState per pixel — only an
  /// endless-extent growth (a real relayout, rare) rebuilds the grid.
  void _handleFrameScroll() {
    if (!_frameScrollController.hasClients) {
      return;
    }
    _watchFrameScrollActivity();
    final offset = _frameScrollController.offset;
    if (offset == _frameAxisOffset.value) {
      return;
    }
    _frameAxisOffset.value = offset;
    // Quantized span buckets (UI-R16): repaint once per span crossing.
    final bucket = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: _metrics.frameCellWidth,
    );
    if (bucket != _frameWindowBucket.value) {
      _frameWindowBucket.value = bucket;
    }
    final position = _frameScrollController.position;
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _visibleFrameCount,
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _metrics.frameCellWidth,
      // Discrete moves (wheel ticks, programmatic jumps) may shrink right
      // away; gesture pixels never rescale mid-drag (the settle listener
      // applies the release).
      allowShrink: !position.isScrollingNotifier.value,
    );
    if (nextTrailingFrames != _endlessTrailingFrames) {
      setState(() => _endlessTrailingFrames = nextTrailingFrames);
    }
  }

  void _watchFrameScrollActivity() {
    final position = _frameScrollController.position;
    if (identical(position, _watchedFramePosition)) {
      return;
    }
    _watchedFramePosition?.isScrollingNotifier.removeListener(
      _handleFrameScrollActivity,
    );
    _watchedFramePosition = position;
    position.isScrollingNotifier.addListener(_handleFrameScrollActivity);
  }

  /// Scroll settled: the lazy endless SHRINK (UI-R9 #11).
  void _handleFrameScrollActivity() {
    final position = _watchedFramePosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _visibleFrameCount,
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _metrics.frameCellWidth,
      allowShrink: true,
    );
    if (nextTrailingFrames != _endlessTrailingFrames && mounted) {
      setState(() => _endlessTrailingFrames = nextTrailingFrames);
    }
  }

  TimelineFrameRange get _frameRangePolicy =>
      TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: widget.frameCount,
        minimumVisibleFrameCells: _metrics.minimumVisibleFrameCells,
      );

  int get _visibleFrameCount => _frameRangePolicy.visibleFrameCount;

  /// Frame cells the current viewport needs to be fully papered (UI-R12
  /// #16) — recorded by build's outer LayoutBuilder. Zero until layout.
  int _viewportFillFrameCells = 0;

  /// Render extent (UI-R12 #16 contract): the cells scrolled into
  /// existence PLUS the viewport fill — no runway beyond. Scroll physics
  /// and the rail clamp here; the frame-rail edge-drag overshoots and the
  /// growth listener materializes what the overshot view needs.
  int get _renderedFrameCount => math.max(
    _visibleFrameCount + _endlessTrailingFrames,
    _viewportFillFrameCells,
  );

  double get _totalFrameContentHeight =>
      _renderedFrameCount * _metrics.frameCellWidth;

  double _effectiveFrameScrollOffset({
    required double requestedOffset,
    required double viewportExtent,
  }) {
    // Same offset policy as the horizontal grid, transposed to y.
    return resolveTimelineHorizontalOffset(
      requestedOffset: requestedOffset,
      totalContentWidth: _totalFrameContentHeight,
      viewportWidth: viewportExtent,
    ).effectiveOffset;
  }

  void _synchronizeFrameScrollController(double effectiveOffset) {
    if (!_frameScrollController.hasClients ||
        _frameScrollController.offset == effectiveOffset ||
        _scheduledFrameOffsetCorrection == effectiveOffset) {
      return;
    }

    _scheduledFrameOffsetCorrection = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_frameScrollController.hasClients) {
        _scheduledFrameOffsetCorrection = null;
        return;
      }

      final maxScrollExtent = _frameScrollController.position.maxScrollExtent;
      final targetOffset = effectiveOffset
          .clamp(0.0, maxScrollExtent)
          .toDouble();

      _scheduledFrameOffsetCorrection = null;
      if (_frameScrollController.offset != targetOffset) {
        _frameScrollController.jumpTo(targetOffset);
      }
    });
  }

  int? _frameIndexForRailLocalY(double localY) {
    // Shared frame/x conversion policy; the rail's local y is the "x".
    return frameIndexFromLocalX(
      localX: localY,
      horizontalScrollOffset: _lastEffectiveFrameScrollOffset,
      frameCellWidth: _metrics.frameCellWidth,
      visibleFrameCount: _renderedFrameCount,
    );
  }

  void _selectClampedFrameFromRail(int frameIndex) {
    // The endless runway IS the selectable tail now (UI-R10 #23 retired
    // the fixed safety frames): clamp against the BUILT extent.
    final clampedFrameIndex = clampFrameIndex(
      frameIndex: frameIndex,
      visibleFrameCount: _renderedFrameCount,
    );
    if (clampedFrameIndex == null ||
        clampedFrameIndex == _lastRailScrubbedFrameIndex) {
      return;
    }

    _lastRailScrubbedFrameIndex = clampedFrameIndex;
    (widget.onScrubFrame ?? widget.onSelectFrame)(clampedFrameIndex);
  }

  /// The scrub gesture's release (raw pointer up/cancel — fires for taps
  /// AND drags). Tracking is NOT reset here so trailing tap handlers stay
  /// deduplicated.
  void _endRailScrub() {
    widget.onScrubEnd?.call();
  }

  /// [autoPan] false is a PRESS: landing near an end of the rail is not a
  /// push toward it. R10 R6 found this the expensive way — the rail runs
  /// this from `onPointerDown` as well as from drag updates, so a plain tap
  /// inside the edge band scrolled the sheet under the finger before the
  /// frame was even resolved. The band is a fraction of the viewport, so
  /// the shorter the rail the larger the share of it that was untappable.
  void _selectFrameFromRailGlobalPosition(
    Offset globalPosition, {
    bool autoPan = true,
  }) {
    final renderObject = _railScrubViewportKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final localY = renderObject.globalToLocal(globalPosition).dy;
    if (autoPan) {
      _autoPanRailEdge(renderObject, localY);
    }
    final frameIndex = _frameIndexForRailLocalY(localY);
    if (frameIndex == null) {
      return;
    }

    _selectClampedFrameFromRail(frameIndex);
  }

  /// Edge auto-pan (UI-R10 #24): a rail scrub past the viewport edge
  /// scrolls the frame axis under it — with the endless growth feeding
  /// rows ahead, the rail drag alone reaches ANY frame (the scrollbar
  /// clamps at the built extent by design).
  void _autoPanRailEdge(RenderBox viewport, double localY) {
    if (!_frameScrollController.hasClients || !viewport.hasSize) {
      return;
    }
    final delta = edgeAutoPanDelta(localY, viewport.size.height);
    if (delta == 0) {
      return;
    }
    final position = _frameScrollController.position;
    // Downward the pan OVERSHOOTS the built extent (UI-R12 #16): the rail
    // drag is THE way past the last built cell — growth materializes the
    // frames the overshot view needs; scroll/scrollbar stay clamped.
    final target = math.max(0.0, position.pixels + delta);
    if (target != position.pixels) {
      _frameScrollController.jumpTo(target);
    }
  }

  void _resetRailScrubTracking() {
    _lastRailScrubbedFrameIndex = null;
  }

  List<PropertyLaneRow> _lanesFor(Layer layer) =>
      widget.lanesForLayer?.call(layer) ?? const [];

  /// Whether [layer] carries attach rows — the base column's fold twirl
  /// shows only then, exactly as the rail's does.
  bool _hasAttachGroup(Layer layer) =>
      widget.layers.any((other) => other.attachedToLayerId == layer.id);

  /// One column wrapped in its repaint boundary + drag-preview gate: an
  /// edge-drag step re-runs the builder with the preview layer substituted
  /// for the drag target's column only.
  /// One lane's HEADER cell — the transposed rail row.
  ///
  /// Lane headers show the value AT the cursor, so they subscribe to the
  /// cursor here and a tick rebuilds only these cells. R10 adds the drag
  /// gate for the same reason the horizontal rail has it: the blue value
  /// column must follow a key move per step, not sit on the committed
  /// track until the pointer lifts.
  /// The display entries of the pass in flight, for the drag's row → slot
  /// conversion (see [effectHeaderRowsOf]).
  List<TimelineDisplayRow> _dragRows = const [];

  /// One column header, made draggable along the sheet's own axis. A layer
  /// header moves the layer; an fx group header re-orders that layer's
  /// chain; every other lane header passes through untouched (members do
  /// not move — the user's rule).
  ///
  /// The sheet lists the stack RAW where the rail reverses it, and the
  /// chain the other way round from the rail — neither is stated here.
  /// Both are inferred by the policy from the lists themselves.
  Widget _draggableHeader(TimelineDisplayRow entry, Widget child) {
    final hooks = widget.rowDragHooks;
    if (hooks == null) {
      return child;
    }
    final lane = entry.lane;
    if (lane == null) {
      return LayerRowDragTarget(
        subject: LayerRowSubject(entry.layer.id),
        slotBefore: entry.layerIndex,
        rowExtent: _metrics.layerRowHeight,
        axis: Axis.vertical,
        hooks: hooks,
        isLastRow: entry.layerIndex == widget.layers.length - 1,
        // R5 #15: the sheet's columns take the ON-COLUMN drop the way the
        // rail's rows do — the band is measured along whichever axis this
        // surface runs, so the transposition costs nothing.
        onCrossed: (steps, onRow) {
          final slot = slotForSteps(
            entry.layerIndex,
            steps,
            widget.layers.length,
          );
          final target = onRow == null ? null : entry.layerIndex + onRow;
          if (target != null && target >= 0 && target < widget.layers.length) {
            hooks.onRowTarget(widget.layers, slot, widget.layers[target].id);
            return;
          }
          hooks.onUpdate(widget.layers, slot);
        },
        // ⑨: the SELECT half, counted in the sheet's own display columns.
        onSelectCrossed: hooks.onSelectBegin == null
            ? null
            : (rowDelta) =>
                  widget.onRowSelectionSpan?.call(_dragRows, rowDelta),
        child: child,
      );
    }
    if (!lane.isGroupHeader) {
      return child;
    }
    final parsed = parseEffectLaneId(lane.laneId);
    if (parsed == null || parsed.parameterId != null) {
      return child;
    }
    final headers = effectHeaderRowsOf(_dragRows, entry.layer.id);
    final slot = headers.indexWhere((h) => h.effectId == parsed.effectId);
    if (slot < 0) {
      return child;
    }
    final myRowIndex = headers[slot].rowIndex;
    return LayerRowDragTarget(
      subject: EffectRowSubject(entry.layer.id, parsed.effectId),
      slotBefore: slot,
      rowExtent: _metrics.layerRowHeight,
      axis: Axis.vertical,
      hooks: hooks,
      isLastRow: slot == headers.length - 1,
      onCrossed: (steps, _) => hooks.onEffectUpdate(
        entry.layer.id,
        [for (final header in headers) header.effectId],
        slotForSteps(
          slot,
          effectStepsBetween(headers, myRowIndex, steps),
          headers.length,
        ),
      ),
      child: child,
    );
  }

  Widget _laneHeader(TimelineDisplayRow entry) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.frameCursor,
      builder: (context, cursorFrame, _) => TimelineDragPreviewRowGate(
        dragPreview: widget.dragPreview,
        layer: entry.layer,
        rowBuilder: (context, layer) => TimelineLaneControlsRow(
          axis: Axis.vertical,
          keyPrefix: 'xsheet',
          layer: layer,
          lane: previewedLaneRow(
            row: entry,
            previewLayer: layer,
            lanesForLayer: _lanesFor,
          ),
          metrics: _metrics,
          width: _metrics.layerRowHeight,
          // Laid out at the natural extent like every other header; the
          // rail window above is what cuts it.
          height: _naturalHeaderExtent,
          currentFrameIndex: cursorFrame,
          onSelectFrame: widget.onSelectFrame,
          laneEdit: widget.laneEdit,
          onToggleLaneGroup: widget.onToggleLaneGroup,
          onToggleLaneGroupEnabled: widget.onToggleLaneGroupEnabled,
          onResetLaneGroup: widget.onResetLaneGroup,
          currentRowHooks: widget.currentRowHooks,
          // The SAME flags the layer's own column header passes, so a
          // group header's fx lands in the sheet's fx row (R5 #7).
          hasOnionColumn: widget.onToggleLayerOnionSkin != null,
          hasBlendColumn: widget.onLayerBlendModeSelected != null,
        ),
      ),
    );
  }

  Widget _gatedColumn(
    TimelineDisplayRow entry,
    TimelineVisibleRange frameRange,
    TimelineVirtualizationPlan plan,
    double viewportExtent,
  ) {
    return RepaintBoundary(
      key: ValueKey<String>(
        'xsheet-column-${entry.layer.id}-${entry.lane?.laneId ?? 'cells'}',
      ),
      child: TimelineDragPreviewRowGate(
        dragPreview: widget.dragPreview,
        layer: entry.layer,
        rowBuilder: (context, layer) =>
            _columnFor(entry, layer, frameRange, plan, viewportExtent),
      ),
    );
  }

  Widget _columnFor(
    TimelineDisplayRow entry,
    Layer layer,
    TimelineVisibleRange frameRange,
    TimelineVirtualizationPlan plan,
    double viewportExtent,
  ) {
    // Recorded for the window, which is recomputed on bucket crossings —
    // outside any build.
    _frameViewportExtent = viewportExtent;
    if (entry.isLane) {
      return laneIsSeAudio(entry.lane!)
          ? SeAudioLaneFrameRow(
              axis: Axis.vertical,
              keyPrefix: 'xsheet',
              layer: layer,
              frameStartIndex: frameRange.startIndex,
              frameEndIndexExclusive: frameRange.endIndexExclusive,
              leadingFrameSpacerWidth: plan.leadingFrameSpacerWidth,
              trailingFrameSpacerWidth: plan.trailingFrameSpacerWidth,
              metrics: _metrics,
              frameRate: widget.projectFrameRate,
              audioPeaksFor: widget.audioPeaksFor,
              onSetClipOffset: widget.audioLane?.onSetClipOffset == null
                  ? null
                  : (clipIndex, offsetFrames) =>
                        widget.audioLane!.onSetClipOffset!(
                          entry.layer.id,
                          clipIndex,
                          offsetFrames,
                        ),
              offsetDrag: widget.audioLane?.offsetDrag,
              onSetClipFades: widget.audioLane?.onSetClipFades == null
                  ? null
                  : (clipIndex, fadeIn, fadeOut) =>
                        widget.audioLane!.onSetClipFades!(
                          entry.layer.id,
                          clipIndex,
                          fadeIn,
                          fadeOut,
                        ),
            )
          : TimelineLaneFrameRow(
              axis: Axis.vertical,
              keyPrefix: 'xsheet',
              layer: layer,
              // R10: the previewed lane while a key drag is in flight —
              // the same re-derivation the horizontal body does.
              lane: previewedLaneRow(
                row: entry,
                previewLayer: layer,
                lanesForLayer: _lanesFor,
              ),
              frameStartIndex: frameRange.startIndex,
              frameEndIndexExclusive: frameRange.endIndexExclusive,
              leadingFrameSpacerWidth: plan.leadingFrameSpacerWidth,
              trailingFrameSpacerWidth: plan.trailingFrameSpacerWidth,
              metrics: _metrics,
              // The LANE selection domain (UI-R23 #3 part 2) — EVERY row's
              // lanes now, camera included (2026-08-08; see the rail's
              // twin for why it stood down and why the reason was wrong).
              // Through the B4-④ escalation wrap, like the horizontal grid.
              laneRange: _laneRange,
            );
    }
    // PRO-TIMELINE scrolling (UI-R15→R16, transposed): the cells column
    // gets FULL bounds — its painter windows itself off the quantized
    // bucket (repaint per span crossing), so the bucket pass diffs
    // identical params and records nothing; the sparse widget-cell kinds
    // re-window internally under the same bucket.
    return TimelineFrameCellsRow(
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      onActivateCell: widget.onActivateCell,
      instructionDefById: widget.instructionDefById,
      audioPeaksFor: widget.audioPeaksFor,
      projectFrameRate: widget.projectFrameRate,
      showSeconds: widget.showSeconds,
      audioLane: widget.audioLane,
      onDropMediaAssetOnLayer: widget.onDropMediaAssetOnLayer,
      seClipMarkerTooltip: widget.seClipMarkerTooltip,
      seSpillsIn: widget.seSpillInLayerIds.contains(layer.id),
      layer: layer,
      baseLayer: entry.layer,
      active: entry.layer.id == widget.activeLayerId,
      playbackFrameCount: widget.frameCount,
      geometry: _publishFrameGeometry(layer.kind),
      crossAxisExtent: _metrics.layerRowHeight,
      windowBucket: _frameWindowBucket,
      viewportMainExtent: viewportExtent,
      exposureStateForLayer: widget.exposureStateForLayer,
      frameNameForLayer: widget.frameNameForLayer,
      celContent: widget.celContent,
      onSelectLayer: widget.onSelectLayer,
      onSelectFrame: widget.onSelectFrame,
      onSettledPress: widget.onSettledPress,
      commaDrag: widget.commaDrag,
      rangeGesture: _rangeGesture,
      runEdit: widget.runEdit,
      substrateGeneration: widget.substrateGeneration,
      // The CAMERA column's union key markers (B4) — the shared lane key
      // marker code, resolved per rebuild like the lanes are.
      unionLane: widget.unionLaneForLayer?.call(layer),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const layerAxisScrollbarExtent = timelineBottomScrollbarRailHeight;

    // PEN-9: a stylus approach stops a coasting fling — mid-glide the
    // viewports ignore-pointer their children, so without the stop a pen
    // landing right after a touch fling scrolls instead of selecting.
    return StylusGlideStop(
      controllers: [_frameScrollController, _layerScrollController],
      // PEN-12 #7: no overscroll stretch/glow — the painterized rails
      // mirror the offset and cannot stretch with the cells (see the
      // horizontal grid).
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: ValueListenableBuilder<double?>(
          valueListenable: _railExtent,
          builder: (context, _, _) => LayoutBuilder(
            builder: (context, constraints) {
              // The header block is ALWAYS its natural extent; the splitter
              // says how much of it the panel shows. R10 R6 packed the name
              // and R6a scaled the whole column — both are retired, and with
              // them the arithmetic that had to guarantee the sheet a
              // minimum reserve the header could not eat.
              final naturalHeaderBlockExtent = _naturalHeaderBlockExtent;
              // What the sheet can spare for the header block: everything
              // but its own chrome and the frame area's two-row reserve.
              // Computed ONCE and handed to every part of the rail —
              // window, scrollbar and splitter — so they cannot disagree.
              final availableHeaderExtent = constraints.hasBoundedHeight
                  ? (constraints.maxHeight -
                            layerAxisScrollbarExtent -
                            LayerRailSplitter.thickness -
                            layerRailFrameReserveExtent)
                        .clamp(0.0, double.infinity)
                        .toDouble()
                  : null;
              final headerBlockHeight = _railExtent.windowExtent(
                naturalHeaderBlockExtent,
                availableExtent: availableHeaderExtent,
              );
              // The grip's own slot gives ground last: in a panel so short
              // that even a zero-height window plus 5px would overflow
              // (the header sweep goes down to 20px), the slot is what
              // shrinks rather than a yellow stripe appearing.
              final splitterSlotExtent = constraints.hasBoundedHeight
                  ? math.min(
                      LayerRailSplitter.thickness,
                      math.max(
                        0.0,
                        constraints.maxHeight -
                            layerAxisScrollbarExtent -
                            headerBlockHeight,
                      ),
                    )
                  : LayerRailSplitter.thickness;
              final bodyViewportHeight = constraints.hasBoundedHeight
                  ? (constraints.maxHeight -
                            layerAxisScrollbarExtent -
                            headerBlockHeight -
                            splitterSlotExtent)
                        .clamp(0.0, double.infinity)
                        .toDouble()
                  : 0.0;
              // Viewport paper fill (UI-R12 #16): the frame column runs to the
              // body's bottom edge — recorded before every consumer of
              // [_renderedFrameCount] below.
              _viewportFillFrameCells = endlessViewportFillFrames(
                viewportExtent: bodyViewportHeight,
                frameCellExtent: _metrics.frameCellWidth,
              );
              _lastEffectiveFrameScrollOffset = _frameAxisOffset.value;
              _synchronizeFrameScrollController(
                _effectiveFrameScrollOffset(
                  requestedOffset: _frameAxisOffset.value,
                  viewportExtent: bodyViewportHeight,
                ),
              );

              // Hidden sections contribute no columns; the section band above
              // the headers carries each section's bracket (shared row/run
              // policy with the horizontal grid).
              final entries = buildTimelineDisplayRows(
                layers: widget.layers,
                expandedLayerIds: widget.expandedLaneLayerIds,
                lanesForLayer: _lanesFor,
                hiddenSections: widget.hiddenSections,
                rowFilter: widget.rowFilter,
                collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
                activeLayerId: widget.activeLayerId,
                fxEnabledOf: (layerId) =>
                    (widget.layerFxStateOf?.call(layerId) ?? LayerFxState.on) !=
                    LayerFxState.off,
                // R9 #23: the sheet's lanes open LEFTWARD — one axis rule
                // with the horizontal grid's downward one, so "further from
                // the layer means applied later" reads the same in both.
                lanesPrecedeLayer: true,
              );
              // The row drag counts COLUMNS and lands on slots; only this
              // list knows how many columns sit between two fx headers.
              _dragRows = entries;
              final rangeHooks = widget.rangeHooks;
              _rangeMoveResolver
                ..rows = entries
                ..session = rangeHooks?.move;
              _rangeGesture = rangeHooks == null
                  ? null
                  : TimelineRangeGestureCallbacks(
                      // Every row this grid mounts is a LAYER row (the
                      // address resolves back at this one seam).
                      isInSelection: (row, frameIndex) {
                        final selection = rangeHooks.selection.value;
                        return row is LayerRowAddress &&
                            selection != null &&
                            selection.coversLayer(row.layerId) &&
                            selection.contains(frameIndex);
                      },
                      // Cross-row select (UI-R17 #8), transposed like the moves.
                      onSelectUpdate:
                          (row, anchorIndex, headIndex, headCrossOffset) {
                            if (row is! LayerRowAddress) {
                              return;
                            }
                            // R9 #25: raw pixels in, resolved here — this
                            // axis's columns are one width.
                            final headRowDelta = uniformRowDeltaForCrossOffset(
                              crossOffset: headCrossOffset,
                              rowExtent: _metrics.layerRowHeight,
                            );
                            rangeHooks.onSelectUpdate(
                              row.layerId,
                              anchorIndex,
                              headIndex,
                              headLayerId: headRowDelta == 0
                                  ? null
                                  : resolveBlockMoveTargetLayer(
                                      rows: entries,
                                      sourceLayerId: row.layerId,
                                      rowDelta: headRowDelta,
                                    ),
                            );
                          },
                      onTapClear: (_) => rangeHooks.onClear(),
                      onMoveBegin: (row, _) =>
                          row is LayerRowAddress &&
                          _rangeMoveResolver.begin(row.layerId),
                      onMoveUpdate: _rangeMoveResolver.update,
                      onMoveEnd: _rangeMoveResolver.end,
                      onMoveCancel: _rangeMoveResolver.cancel,
                    );
              // 🚨B4-④, transposed: the lane-anchored drag joins the cells
              // law the moment it leaves its own lane group — the same
              // wrap the horizontal grid applies (one law, both axes).
              final hostLaneRange = widget.laneRange;
              _laneRange = hostLaneRange == null
                  ? null
                  : TimelineLaneRangeCallbacks(
                      selection: hostLaneRange.selection,
                      onSelectUpdate:
                          (
                            layerId,
                            laneId,
                            anchorIndex,
                            headIndex,
                            headRowDelta,
                          ) {
                            final escalation = rangeHooks == null
                                ? null
                                : resolveLaneSpanEscalation(
                                    rows: entries,
                                    layerId: layerId,
                                    laneId: laneId,
                                    rowDelta: headRowDelta,
                                  );
                            if (escalation == null) {
                              hostLaneRange.onSelectUpdate(
                                layerId,
                                laneId,
                                anchorIndex,
                                headIndex,
                                headRowDelta,
                              );
                              return;
                            }
                            rangeHooks!.onSelectUpdate(
                              layerId,
                              anchorIndex,
                              headIndex,
                              headLayerId: escalation.headLayerId,
                              headLaneId: escalation.headLaneId,
                              spanRows: escalation.spanRows,
                            );
                          },
                      onTapAt: hostLaneRange.onTapAt,
                      onMoveBegin: hostLaneRange.onMoveBegin,
                      onMoveUpdate: hostLaneRange.onMoveUpdate,
                      onMoveEnd: hostLaneRange.onMoveEnd,
                      onMoveCancel: hostLaneRange.onMoveCancel,
                    );
              final sectionRuns = timelineSectionRuns(entries);

              // The shared virtualization plan with the frame axis fed through the
              // "horizontal" inputs (the axes are swapped in this grid). Computed
              // INSIDE the window-bucket subscribers (UI-R9 #12a): scroll pixels
              // re-window nothing.
              TimelineVirtualizationPlan framePlan() =>
                  calculateTimelineVirtualizationPlan(
                    horizontalScrollOffset: _effectiveFrameScrollOffset(
                      requestedOffset: _frameAxisOffset.value,
                      viewportExtent: bodyViewportHeight,
                    ),
                    verticalScrollOffset: 0,
                    viewportWidth: bodyViewportHeight,
                    viewportHeight: 0,
                    frameCellWidth: _metrics.frameCellWidth,
                    layerRowHeight: _metrics.layerRowHeight,
                    frameCount: _renderedFrameCount,
                    layerCount: entries.length,
                  );
              final totalFrameContentHeight = _totalFrameContentHeight;
              // Every column is ONE width (`timelineDisplayRowExtent` returns
              // `layerRowHeight` unconditionally). The old note here claimed
              // collapsed sections folded to a slim strip; they never did, and
              // believing it would send someone to the height-table row
              // resolver when `uniformRowDeltaForCrossOffset` — which requires
              // this uniformity — is the right one.
              final columnsContentWidth = timelineDisplayRowsExtent(
                entries,
                _metrics,
              );
              final cutEndBoundaryOffset = timelineCutEndBoundaryX(
                playbackFrameCount: widget.frameCount,
                metrics: _metrics,
              );
              // The DRAWN end, following a live trim so the blue line, the wash
              // edge and the ruler's letters never split from the red line
              // mid-drag (one function, four surfaces).
              double drawnEndOffset(TimelineDragPreview? preview) =>
                  timelineDrawnEndPreviewFrameCount(
                    preview: preview,
                    cutId: widget.cutEndDrag?.cutId,
                    playbackFrameCount: widget.frameCount,
                    drawnFrameCount: widget.drawnFrameCount,
                  ) *
                  _metrics.frameCellWidth;

              return Stack(
                children: [
                  Column(
                    children: [
                      // The LAYER axis runs across the sheet, so its scrollbar is
                      // the strip along the top — and the corner beside it holds
                      // the seconds toggle, off the command bar.
                      SizedBox(
                        height: layerAxisScrollbarExtent,
                        child: Row(
                          children: [
                            SizedBox(width: _metrics.layerControlsWidth),
                            TimelineSecondsToggleCorner(
                              key: const ValueKey<String>(
                                'xsheet-time-display-toggle-button',
                              ),
                              width: _metrics.verticalScrollbarWidth,
                              height: layerAxisScrollbarExtent,
                              showSeconds: widget.showSeconds,
                              onChanged: widget.onShowSecondsChanged,
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    TimelineHorizontalScrollbarRail(
                                      key: const ValueKey<String>(
                                        'xsheet-horizontal-scrollbar',
                                      ),
                                      controller: _layerScrollController,
                                      viewportWidth: constraints.hasBoundedWidth
                                          ? constraints.maxWidth
                                          : 0.0,
                                      contentWidth: math.max(
                                        columnsContentWidth,
                                        _metrics.layerRowHeight,
                                      ),
                                      height: layerAxisScrollbarExtent,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: _metrics.layerControlsWidth,
                              child: Column(
                                children: [
                                  // R10 R6: the corner is the LEGEND COLUMN now.
                                  // It used to read 'Frame' and label nothing —
                                  // the sheet was the one grid whose columns had
                                  // no headings at all. Same legend widget as the
                                  // timeline's, stood up, so each icon lands on
                                  // the header slot it names — and inside the same
                                  // window, so the two are cut at one line.
                                  LayerRailWindow(
                                    axis: Axis.vertical,
                                    rail: _railExtent,
                                    naturalExtent: naturalHeaderBlockExtent,
                                    availableExtent: availableHeaderExtent,
                                    child: TimelineLayerControlsHeader(
                                      axis: Axis.vertical,
                                      metrics: _metrics,
                                      railExtent: naturalHeaderBlockExtent,
                                      // The legend has no flyouts here to infer
                                      // the optional columns from, so it is told
                                      // what the ROWS carry — or its icons stop
                                      // naming the columns under them.
                                      hasOnionColumn:
                                          widget.onToggleLayerOnionSkin != null,
                                      hasBlendColumn:
                                          widget.onLayerBlendModeSelected !=
                                          null,
                                      hiddenSections: widget.hiddenSections,
                                    ),
                                  ),
                                  SizedBox(height: splitterSlotExtent),
                                  Expanded(
                                    child: Listener(
                                      key: const ValueKey<String>(
                                        'xsheet-frame-rail-scrub-area',
                                      ),
                                      behavior: HitTestBehavior.translucent,
                                      onPointerDown: (event) {
                                        _resetRailScrubTracking();
                                        _selectFrameFromRailGlobalPosition(
                                          event.position,
                                          autoPan: false,
                                        );
                                      },
                                      onPointerUp: (_) => _endRailScrub(),
                                      onPointerCancel: (_) => _endRailScrub(),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onVerticalDragStart: (details) {
                                          _selectFrameFromRailGlobalPosition(
                                            details.globalPosition,
                                            autoPan: false,
                                          );
                                        },
                                        onVerticalDragUpdate: (details) {
                                          _selectFrameFromRailGlobalPosition(
                                            details.globalPosition,
                                          );
                                        },
                                        onVerticalDragEnd: (_) =>
                                            _resetRailScrubTracking(),
                                        onVerticalDragCancel:
                                            _resetRailScrubTracking,
                                        child: ClipRect(
                                          key: _railScrubViewportKey,
                                          child: OverflowBox(
                                            alignment: Alignment.topLeft,
                                            minHeight: totalFrameContentHeight,
                                            maxHeight: totalFrameContentHeight,
                                            minWidth:
                                                _metrics.layerControlsWidth,
                                            maxWidth:
                                                _metrics.layerControlsWidth,
                                            // Pixels move the TRANSLATE only; the
                                            // rail painter windows itself off the
                                            // offset (UI-R15 — no bucket rebuild).
                                            child: ValueListenableBuilder<double>(
                                              valueListenable: _frameAxisOffset,
                                              child: Builder(
                                                builder: (context) {
                                                  return SizedBox(
                                                    width: _metrics
                                                        .layerControlsWidth,
                                                    height:
                                                        totalFrameContentHeight,
                                                    child: Stack(
                                                      children: [
                                                        // SPLIT (shared with the
                                                        // horizontal rulers): the
                                                        // numbers are static, so a
                                                        // seek no longer re-records
                                                        // a glyph per frame; the
                                                        // tint and the cached bar
                                                        // ride the overlay below.
                                                        // UI-R15: full bounds — the
                                                        // rail painter windows
                                                        // itself off the offset.
                                                        RepaintBoundary(
                                                          child: _XSheetFrameNumberRail(
                                                            frameStartIndex: 0,
                                                            frameEndIndexExclusive:
                                                                _renderedFrameCount,
                                                            // The tint lives in the
                                                            // overlay now.
                                                            currentFrameIndex:
                                                                -1,
                                                            playbackFrameCount:
                                                                widget
                                                                    .frameCount,
                                                            leadingFrameSpacerHeight:
                                                                0,
                                                            trailingFrameSpacerHeight:
                                                                0,
                                                            metrics: _metrics,
                                                            onSelectFrame:
                                                                _selectClampedFrameFromRail,
                                                            framesPerSecond:
                                                                _countingFps,
                                                            showSeconds: widget
                                                                .showSeconds,
                                                            windowBucket:
                                                                _frameWindowBucket,
                                                            viewportMainExtent:
                                                                bodyViewportHeight,
                                                          ),
                                                        ),
                                                        Positioned.fill(
                                                          child: TimelineRulerCursorOverlay(
                                                            keyValue:
                                                                'xsheet-rail-cursor-overlay',
                                                            axis: Axis.vertical,
                                                            playhead: widget
                                                                .frameCursor,
                                                            repaintSignal: widget
                                                                .frameReadySignal,
                                                            windowBucket:
                                                                _frameWindowBucket,
                                                            viewportMainExtent:
                                                                bodyViewportHeight,
                                                            renderedFrames:
                                                                _renderedFrameCount,
                                                            cellWidth: _metrics
                                                                .frameCellWidth,
                                                            isFrameReady: widget
                                                                .isFrameReady,
                                                          ),
                                                        ),
                                                        // UI-R18 #14: the rail's
                                                        // line follows the live
                                                        // trim preview so it never
                                                        // splits from the body's.
                                                        if (widget.cutEndDrag !=
                                                                null &&
                                                            widget.dragPreview !=
                                                                null)
                                                          ValueListenableBuilder<
                                                            TimelineDragPreview?
                                                          >(
                                                            valueListenable:
                                                                widget
                                                                    .dragPreview!,
                                                            builder: (context, preview, _) => TimelineRulerCutEndBoundary(
                                                              axis:
                                                                  Axis.vertical,
                                                              left:
                                                                  timelineCutEndPreviewFrameCount(
                                                                    preview:
                                                                        preview,
                                                                    cutId: widget
                                                                        .cutEndDrag!
                                                                        .cutId,
                                                                    playbackFrameCount:
                                                                        widget
                                                                            .frameCount,
                                                                  ) *
                                                                  _metrics
                                                                      .frameCellWidth,
                                                            ),
                                                          )
                                                        else
                                                          TimelineRulerCutEndBoundary(
                                                            axis: Axis.vertical,
                                                            left:
                                                                cutEndBoundaryOffset,
                                                          ),
                                                        // The のりしろ boundary,
                                                        // transposed: a length
                                                        // below the cut's end.
                                                        TimelineRulerNoriShiroBoundary(
                                                          axis: Axis.vertical,
                                                          cutEnd:
                                                              cutEndBoundaryOffset,
                                                          drawnEnd:
                                                              drawnEndOffset(
                                                                null,
                                                              ),
                                                          label: widget
                                                              .noriShiroLabel,
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                              // R9 #3 (transposed): the RAW scroll
                                              // position, overscroll included —
                                              // the clamp is for correcting the
                                              // CONTROLLER, not for paint.
                                              builder: (context, offset, child) {
                                                _lastEffectiveFrameScrollOffset =
                                                    offset;
                                                return Transform.translate(
                                                  offset: Offset(0, -offset),
                                                  child: child,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // ONE 16px column, split by the splitter: the RAIL's
                            // own bar above it, the FRAME axis's below. The
                            // column was already here at 14px carrying only the
                            // frame bar — widening it and halving it is the whole
                            // change (the user saw this before I did).
                            SizedBox(
                              width: _metrics.verticalScrollbarWidth,
                              child: Column(
                                children: [
                                  LayerRailScrollbar(
                                    axis: Axis.vertical,
                                    rail: _railExtent,
                                    naturalExtent: naturalHeaderBlockExtent,
                                    availableExtent: availableHeaderExtent,
                                    laneExtent: _metrics.verticalScrollbarWidth,
                                    keyPrefix: 'xsheet',
                                  ),
                                  SizedBox(height: splitterSlotExtent),
                                  Expanded(
                                    child: TimelineVerticalScrollbarRail(
                                      key: const ValueKey<String>(
                                        'xsheet-vertical-scrollbar',
                                      ),
                                      controller: _frameScrollController,
                                      viewportHeight: bodyViewportHeight,
                                      contentHeight: totalFrameContentHeight,
                                      width: _metrics.verticalScrollbarWidth,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: widget.layers.isEmpty
                                  ? Align(
                                      alignment: Alignment.topLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          'No layers',
                                          style: TextStyle(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ScrollConfiguration(
                                      // The custom rails ARE the scrollbars — the
                                      // desktop auto-overlay doubled the vertical one
                                      // (UI-R10 #22).
                                      behavior: ScrollConfiguration.of(
                                        context,
                                      ).copyWith(scrollbars: false),
                                      child: SingleChildScrollView(
                                        key: const ValueKey<String>(
                                          'xsheet-layer-horizontal-viewport',
                                        ),
                                        controller: _layerScrollController,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: columnsContentWidth,
                                          child: Column(
                                            children: [
                                              LayerRailWindow(
                                                axis: Axis.vertical,
                                                rail: _railExtent,
                                                naturalExtent:
                                                    naturalHeaderBlockExtent,
                                                availableExtent:
                                                    availableHeaderExtent,
                                                child: Column(
                                                  children: [
                                                    // The paper sheet's group headings: one
                                                    // bracket cell per section run, wrapping
                                                    // its columns.
                                                    Row(
                                                      children: [
                                                        for (final run
                                                            in sectionRuns)
                                                          _XSheetSectionBandCell(
                                                            run: run,
                                                            height: XSheetTimelineGrid
                                                                ._sectionBandHeight,
                                                            extent:
                                                                timelineSectionRunExtent(
                                                                  run,
                                                                  entries,
                                                                  _metrics,
                                                                ),
                                                          ),
                                                      ],
                                                    ),
                                                    Row(
                                                      children: [
                                                        for (
                                                          var index = 0;
                                                          index <
                                                              entries.length;
                                                          index += 1
                                                        )
                                                          _draggableHeader(
                                                            entries[index],
                                                            entries[index]
                                                                    .isLane
                                                                ? _laneHeader(
                                                                    entries[index],
                                                                  )
                                                                : _LayerHeader(
                                                                    depth: entries[index]
                                                                        .depth,
                                                                    headerExtent:
                                                                        _naturalHeaderExtent,
                                                                    onToggleLayerOnionSkin:
                                                                        widget
                                                                            .onToggleLayerOnionSkin,
                                                                    onionSkinEnabled:
                                                                        widget.layerOnionSkinEnabledOf?.call(
                                                                          entries[index]
                                                                              .layer
                                                                              .id,
                                                                        ) ??
                                                                        false,
                                                                    onLayerBlendModeSelected:
                                                                        widget
                                                                            .onLayerBlendModeSelected,
                                                                    blendLanguage:
                                                                        widget
                                                                            .blendLanguage,
                                                                    wearsBaseComposite: attachRowWearsBaseComposite(
                                                                      entries[index]
                                                                          .layer,
                                                                      widget
                                                                          .layers,
                                                                    ),
                                                                    layer: entries[index]
                                                                        .layer,
                                                                    active:
                                                                        entries[index]
                                                                            .layer
                                                                            .id ==
                                                                        widget
                                                                            .activeLayerId,
                                                                    // ⑨ · T1
                                                                    selected: widget
                                                                        .selectedRows
                                                                        .contains(
                                                                          LayerRowAddress(
                                                                            entries[index].layer.id,
                                                                          ),
                                                                        ),
                                                                    metrics:
                                                                        _metrics,
                                                                    onSelectLayer:
                                                                        widget
                                                                            .onSelectLayer,
                                                                    onToggleLayerVisibility:
                                                                        widget
                                                                            .onToggleLayerVisibility,
                                                                    onLayerOpacityChanged:
                                                                        widget
                                                                            .onLayerOpacityChanged,
                                                                    onLayerOpacityChangeEnd:
                                                                        widget
                                                                            .onLayerOpacityChangeEnd,
                                                                    opacityDragPreview:
                                                                        widget
                                                                            .opacityDragPreview,
                                                                    onToggleLayerTimesheet:
                                                                        widget
                                                                            .onToggleLayerTimesheet,
                                                                    fxState:
                                                                        widget.layerFxStateOf?.call(
                                                                          entries[index]
                                                                              .layer
                                                                              .id,
                                                                        ) ??
                                                                        LayerFxState
                                                                            .on,
                                                                    onToggleLayerFx:
                                                                        widget
                                                                            .onToggleLayerFx,
                                                                    onLayerMarkSelected:
                                                                        widget
                                                                            .onLayerMarkSelected,
                                                                    onToggleLayerFillReference:
                                                                        widget
                                                                            .onToggleLayerFillReference,
                                                                    onOpenLayerMixer:
                                                                        widget
                                                                            .onOpenLayerMixer,
                                                                    attachArrowPlacement: widget
                                                                        .attachArrowPlacementOf
                                                                        ?.call(
                                                                          entries[index]
                                                                              .layer
                                                                              .id,
                                                                        ),
                                                                    isLayerSoloed:
                                                                        widget.isLayerSoloed?.call(
                                                                          entries[index]
                                                                              .layer
                                                                              .id,
                                                                        ) ??
                                                                        false,
                                                                    hasLanes: _lanesFor(
                                                                      entries[index]
                                                                          .layer,
                                                                    ).isNotEmpty,
                                                                    lanesExpanded: widget
                                                                        .expandedLaneLayerIds
                                                                        .contains(
                                                                          entries[index]
                                                                              .layer
                                                                              .id,
                                                                        ),
                                                                    onToggleLanes:
                                                                        widget
                                                                            .onToggleLayerLanes,
                                                                    // One fold
                                                                    // twirl, the
                                                                    // rail's rule
                                                                    // verbatim.
                                                                    hasGroupFold:
                                                                        entries[index]
                                                                            .isFolder ||
                                                                        _hasAttachGroup(
                                                                          entries[index]
                                                                              .layer,
                                                                        ),
                                                                    groupFoldExpanded:
                                                                        entries[index]
                                                                            .isFolder
                                                                        ? !entries[index]
                                                                              .layer
                                                                              .collapsed
                                                                        : !widget
                                                                              .collapsedAttachBaseIds
                                                                              .contains(
                                                                                entries[index].layer.id,
                                                                              ),
                                                                    onToggleGroupFold:
                                                                        entries[index]
                                                                            .isFolder
                                                                        ? widget
                                                                              .onToggleLayerCollapsed
                                                                        : widget
                                                                              .onToggleAttachGroup,
                                                                  ),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Reserves the gap the splitter
                                              // floats over.
                                              SizedBox(
                                                height: splitterSlotExtent,
                                              ),
                                              Expanded(
                                                child: ScrollConfiguration(
                                                  // The rail between the frame numbers
                                                  // and the cells is THE scrollbar; the
                                                  // desktop auto-overlay was the
                                                  // duplicate (UI-R10 #22).
                                                  behavior:
                                                      ScrollConfiguration.of(
                                                        context,
                                                      ).copyWith(
                                                        scrollbars: false,
                                                      ),
                                                  child: SingleChildScrollView(
                                                    key: const ValueKey<String>(
                                                      'xsheet-frame-vertical-viewport',
                                                    ),
                                                    controller:
                                                        _frameScrollController,
                                                    child: SizedBox(
                                                      height:
                                                          totalFrameContentHeight,
                                                      // Pixels scroll the real viewport;
                                                      // only cell crossings re-window the
                                                      // columns (UI-R9 #12a).
                                                      child: ValueListenableBuilder<int>(
                                                        valueListenable:
                                                            _frameWindowBucket,
                                                        builder: (context, _, _) {
                                                          final plan =
                                                              framePlan();
                                                          final frameRange =
                                                              plan.frameRange;
                                                          return Stack(
                                                            children: [
                                                              Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  // RepaintBoundary per
                                                                  // column (mirrors the
                                                                  // horizontal rows): the
                                                                  // cursor layer repaints
                                                                  // alone on ticks. The
                                                                  // gate inside makes an
                                                                  // edge-drag step rebuild
                                                                  // exactly the dragged
                                                                  // layer's column.
                                                                  for (
                                                                    var index =
                                                                        0;
                                                                    index <
                                                                        entries
                                                                            .length;
                                                                    index += 1
                                                                  )
                                                                    _gatedColumn(
                                                                      entries[index],
                                                                      frameRange,
                                                                      plan,
                                                                      bodyViewportHeight,
                                                                    ),
                                                                ],
                                                              ),
                                                              // UI-R13 #7: the 6f/24f
                                                              // beat lines span EVERY
                                                              // column — one grid-wide
                                                              // overlay (transposed).
                                                              Positioned.fill(
                                                                child: IgnorePointer(
                                                                  child: RepaintBoundary(
                                                                    child: CustomPaint(
                                                                      key:
                                                                          const ValueKey<
                                                                            String
                                                                          >(
                                                                            'xsheet-beat-lines',
                                                                          ),
                                                                      painter: TimelineBeatLinesPainter(
                                                                        axis: Axis
                                                                            .vertical,
                                                                        frameCellExtent:
                                                                            _metrics.frameCellWidth,
                                                                        crossCellExtent:
                                                                            _metrics.layerRowHeight,
                                                                        framesPerSecond:
                                                                            _countingFps,
                                                                        colorScheme:
                                                                            colorScheme,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              // The cursor layer carries
                                                              // the playhead + selection
                                                              // visuals; ticks repaint it
                                                              // alone.
                                                              Positioned.fill(
                                                                child: TimelineCursorLayer(
                                                                  axis: Axis
                                                                      .vertical,
                                                                  currentRow: widget
                                                                      .currentRowHooks
                                                                      ?.currentRow,
                                                                  selectedSemanticsKey:
                                                                      const ValueKey<
                                                                        String
                                                                      >(
                                                                        'xsheet-selected-cell',
                                                                      ),
                                                                  frameRangeSelection: widget
                                                                      .rangeHooks
                                                                      ?.selection,
                                                                  // R27 #14: one band
                                                                  // for cells and
                                                                  // lanes alike.
                                                                  laneRangeSelection: widget
                                                                      .laneRange
                                                                      ?.selection,
                                                                  frameCursor:
                                                                      widget
                                                                          .frameCursor,
                                                                  dragPreview:
                                                                      widget
                                                                          .dragPreview,
                                                                  rows: entries,
                                                                  activeLayerId:
                                                                      widget
                                                                          .activeLayerId,
                                                                  frameStartIndex:
                                                                      frameRange
                                                                          .startIndex,
                                                                  frameEndIndexExclusive:
                                                                      frameRange
                                                                          .endIndexExclusive,
                                                                  leadingFrameSpacerWidth:
                                                                      plan.leadingFrameSpacerWidth,
                                                                  metrics:
                                                                      _metrics,
                                                                  exposureStateForLayer:
                                                                      widget
                                                                          .exposureStateForLayer,
                                                                  crossAxisExtent:
                                                                      entries
                                                                          .length *
                                                                      _metrics
                                                                          .layerRowHeight,
                                                                ),
                                                              ),
                                                              // The out-of-cut wash,
                                                              // TOP of the stack with
                                                              // the cut-end line (the
                                                              // user's layer order):
                                                              // where the film stops
                                                              // is stated over
                                                              // everything, cursor and
                                                              // selection included.
                                                              Positioned.fill(
                                                                child: IgnorePointer(
                                                                  child: RepaintBoundary(
                                                                    child:
                                                                        widget.cutEndDrag ==
                                                                                null ||
                                                                            widget.dragPreview ==
                                                                                null
                                                                        ? CustomPaint(
                                                                            painter: TimelineOutsideCutWashPainter(
                                                                              axis: Axis.vertical,
                                                                              outsideStart: drawnEndOffset(null),
                                                                              colorScheme: colorScheme,
                                                                            ),
                                                                          )
                                                                        : ValueListenableBuilder<
                                                                            TimelineDragPreview?
                                                                          >(
                                                                            valueListenable:
                                                                                widget.dragPreview!,
                                                                            builder:
                                                                                (
                                                                                  context,
                                                                                  preview,
                                                                                  _,
                                                                                ) => CustomPaint(
                                                                                  painter: TimelineOutsideCutWashPainter(
                                                                                    axis: Axis.vertical,
                                                                                    outsideStart: drawnEndOffset(
                                                                                      preview,
                                                                                    ),
                                                                                    colorScheme: colorScheme,
                                                                                  ),
                                                                                ),
                                                                          ),
                                                                  ),
                                                                ),
                                                              ),
                                                              // UI-R18 #14: live
                                                              // line + trim grip
                                                              // on the frame axis
                                                              // (vertical here).
                                                              if (widget.cutEndDrag !=
                                                                      null &&
                                                                  widget.dragPreview !=
                                                                      null)
                                                                ValueListenableBuilder<
                                                                  TimelineDragPreview?
                                                                >(
                                                                  valueListenable:
                                                                      widget
                                                                          .dragPreview!,
                                                                  builder:
                                                                      (
                                                                        context,
                                                                        preview,
                                                                        _,
                                                                      ) => TimelineBodyCutEndBoundary(
                                                                        axis: Axis
                                                                            .vertical,
                                                                        left:
                                                                            timelineCutEndPreviewFrameCount(
                                                                              preview: preview,
                                                                              cutId: widget.cutEndDrag!.cutId,
                                                                              playbackFrameCount: widget.frameCount,
                                                                            ) *
                                                                            _metrics.frameCellWidth,
                                                                      ),
                                                                )
                                                              else
                                                                TimelineBodyCutEndBoundary(
                                                                  axis: Axis
                                                                      .vertical,
                                                                  left:
                                                                      cutEndBoundaryOffset,
                                                                ),
                                                              // のりしろ, over the
                                                              // wash: the same
                                                              // continuous mark
                                                              // the ruler draws.
                                                              if (widget.cutEndDrag !=
                                                                      null &&
                                                                  widget.dragPreview !=
                                                                      null)
                                                                ValueListenableBuilder<
                                                                  TimelineDragPreview?
                                                                >(
                                                                  valueListenable:
                                                                      widget
                                                                          .dragPreview!,
                                                                  builder:
                                                                      (
                                                                        context,
                                                                        preview,
                                                                        _,
                                                                      ) => TimelineBodyNoriShiroBoundary(
                                                                        axis: Axis
                                                                            .vertical,
                                                                        left: drawnEndOffset(
                                                                          preview,
                                                                        ),
                                                                        cutEnd:
                                                                            timelineCutEndPreviewFrameCount(
                                                                              preview: preview,
                                                                              cutId: widget.cutEndDrag!.cutId,
                                                                              playbackFrameCount: widget.frameCount,
                                                                            ) *
                                                                            _metrics.frameCellWidth,
                                                                      ),
                                                                )
                                                              else
                                                                TimelineBodyNoriShiroBoundary(
                                                                  axis: Axis
                                                                      .vertical,
                                                                  left:
                                                                      drawnEndOffset(
                                                                        null,
                                                                      ),
                                                                  cutEnd:
                                                                      cutEndBoundaryOffset,
                                                                ),
                                                              if (widget
                                                                      .cutEndDrag !=
                                                                  null)
                                                                TimelineCutEndDragHandle(
                                                                  axis: Axis
                                                                      .vertical,
                                                                  cellExtent:
                                                                      _metrics
                                                                          .frameCellWidth,
                                                                  playbackFrameCount:
                                                                      widget
                                                                          .frameCount,
                                                                  callbacks: widget
                                                                      .cutEndDrag!,
                                                                  dragPreview:
                                                                      widget
                                                                          .dragPreview,
                                                                ),
                                                            ],
                                                          );
                                                        },
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
                          ],
                        ),
                      ),
                    ],
                  ),
                  // The grip floats over the 5px slot all three columns
                  // reserve, so one grab spans the legend, the scrollbar
                  // column and the headers. It starts after the frame-number
                  // rail: that column is the FRAME axis's and the splitter
                  // has nothing to say about it.
                  Positioned(
                    left: _metrics.layerControlsWidth,
                    right: 0,
                    top: layerAxisScrollbarExtent + headerBlockHeight,
                    height: splitterSlotExtent,
                    child: LayerRailSplitter(
                      key: const ValueKey<String>('xsheet-rail-splitter'),
                      axis: Axis.vertical,
                      extent: _railExtent,
                      naturalExtent: naturalHeaderBlockExtent,
                      availableExtent: availableHeaderExtent,
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
}

/// The vertical frame-number rail: the X-sheet counterpart of the
/// horizontal grid's frame header row, sharing its styling and dim rules.
class _XSheetFrameNumberRail extends StatelessWidget {
  const _XSheetFrameNumberRail({
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerHeight,
    required this.trailingFrameSpacerHeight,
    required this.metrics,
    required this.onSelectFrame,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  });

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;
  final double leadingFrameSpacerHeight;
  final double trailingFrameSpacerHeight;
  final TimelineGridMetrics metrics;
  final ValueChanged<int> onSelectFrame;
  final int framesPerSecond;
  final bool showSeconds;

  /// PRO-TIMELINE scrolling (UI-R15→R16): the painter windows itself off
  /// the quantized bucket — pass full bounds, repaint per span crossing.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final height =
        leadingFrameSpacerHeight +
        (frameEndIndexExclusive - frameStartIndex) * metrics.frameCellWidth +
        trailingFrameSpacerHeight;
    // PAINTERIZED (UI-R14 #1, the ruler's UI-R13 #1 treatment — 통일화):
    // the whole rail is one CustomPaint; per-frame row widgets are gone.
    // Tests probe [XSheetFrameRailPainter.modelAt]/`rowRectFor` through
    // the 'xsheet-frame-rail-paint' key; selection stays on the rail's
    // viewport-level scrub listener.
    return SizedBox(
      key: const ValueKey<String>('xsheet-frame-number-rail'),
      width: metrics.layerControlsWidth,
      height: height,
      child: CustomPaint(
        key: const ValueKey<String>('xsheet-frame-rail-paint'),
        size: Size(metrics.layerControlsWidth, height),
        painter: XSheetFrameRailPainter(
          frameStartIndex: frameStartIndex,
          frameEndIndexExclusive: frameEndIndexExclusive,
          currentFrameIndex: currentFrameIndex,
          playbackFrameCount: playbackFrameCount,
          leadingFrameSpacerHeight: leadingFrameSpacerHeight,
          metrics: metrics,
          colorScheme: colorScheme,
          framesPerSecond: framesPerSecond,
          showSeconds: showSeconds,
          windowBucket: windowBucket,
          viewportMainExtent: viewportMainExtent,
        ),
      ),
    );
  }
}

/// The X-sheet frame rail as ONE CustomPainter (UI-R14 #1 — the shared
/// ruler's UI-R13 #1 treatment, transposed): number rows, the seconds
/// column, selection tint, playback dimming and the cached strip paint
/// in a single pass. Public for the test probe.
class XSheetFrameRailPainter extends CustomPainter {
  XSheetFrameRailPainter({
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerHeight,
    required this.metrics,
    required this.colorScheme,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  }) : super(repaint: windowBucket);

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;
  final double leadingFrameSpacerHeight;
  final TimelineGridMetrics metrics;
  final ColorScheme colorScheme;
  final int framesPerSecond;
  final bool showSeconds;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set the rail
  /// windows ITSELF off the quantized bucket — full bounds in, repaint
  /// once per span crossing.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// The row window paint() actually draws (probe surface).
  ({int startIndex, int endIndexExclusive}) visibleRowWindow() {
    final bucket = windowBucket;
    if (bucket == null ||
        viewportMainExtent <= 0 ||
        metrics.frameCellWidth <= 0) {
      return (
        startIndex: frameStartIndex,
        endIndexExclusive: frameEndIndexExclusive,
      );
    }
    final window = timelineFrameWindowFor(
      bucket: bucket.value,
      cellExtent: metrics.frameCellWidth,
      viewportExtent: viewportMainExtent,
    );
    return (
      startIndex: math.max(frameStartIndex, window.startIndex),
      endIndexExclusive: math.min(
        frameEndIndexExclusive,
        window.endIndexExclusive,
      ),
    );
  }

  /// The row's rect in the rail's local coordinates.
  Rect rowRectFor(int frameIndex) => Rect.fromLTWH(
    0,
    leadingFrameSpacerHeight +
        (frameIndex - frameStartIndex) * metrics.frameCellWidth,
    metrics.layerControlsWidth,
    metrics.frameCellWidth,
  );

  /// The resolved per-row model — the probe surface (the shared ruler's
  /// model class).
  ///
  /// R9 #4: the cadence is the SHARED one now
  /// ([TimelineGridMetrics.frameLabelEveryFrames], the paper-timesheet
  /// ladder anchored at frame 1). This painter is a transposed
  /// re-implementation of the horizontal ruler and had never called it —
  /// so zooming out crowded every row's number into the next, while the
  /// horizontal ruler thinned out correctly. A ruler is a SCALE, not cell
  /// content: the "never disappears" rule is about what a cell holds.
  TimelineRulerHeaderModel modelAt(int frameIndex) {
    final selected = frameIndex == currentFrameIndex;
    final outside = frameIndex >= playbackFrameCount;
    final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
    final labeled = frameIndex % metrics.frameLabelEveryFrames == 0;
    return TimelineRulerHeaderModel(
      frameIndex: frameIndex,
      label: !labeled
          ? ''
          : showSeconds
          ? '${frameIndex % safeFps + 1}'
          : '${frameIndex + 1}',
      secondsLabel: timelineRulerSecondsLabel(
        frameIndex: frameIndex,
        framesPerSecond: safeFps,
      ),
      selected: selected,
      outsidePlaybackRange: outside,
      background: selected
          ? Color.alphaBlend(
              timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
              colorScheme.surface,
            )
          : outside
          ? AppColors.washUp.withValues(alpha: 0.72)
          : colorScheme.surface,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint();
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final linePaint = Paint()..strokeWidth = 1;
    // Rows draw the shared FAINT grid ink (UI-R14 #4); the structural
    // right edge (the rail/scrollbar divider) paints once below.
    final borderColor = timelineBaseGridInk(
      colorScheme,
      frameCellExtent: metrics.frameCellWidth,
    );

    // Self-windowing (UI-R15): only the rows under the live viewport
    // record — a scroll is a repaint of this thin pass, never a rebuild.
    final window = visibleRowWindow();
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final model = modelAt(frameIndex);
      final rect = rowRectFor(frameIndex);
      canvas.drawRect(rect, fillPaint..color = model.background);
      if (borderColor.a > 0) {
        canvas.drawRect(rect.deflate(0.5), borderPaint..color = borderColor);
      }

      // Seconds on the row's leading CORNER (UI-R10 #27): the 1-based
      // second prints bold on its boundary row.
      //
      // R10 R6: the rail narrowed 72 → 28 with the frame-number rail now
      // derived from the ruler's height, and a centred 14pt three-digit
      // number filled the whole 28px — straight through a seconds glyph
      // that sat beside it. Both numbers converge on the SHARED ruler's
      // answers instead of the sheet growing an exception: the corner
      // placement (`rect.left + 2, rect.top + 1` there) and the 11pt base.
      if (model.secondsLabel.isNotEmpty) {
        final seconds = _label(
          model.secondsLabel,
          TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        );
        seconds.paint(canvas, Offset(rect.left + 2, rect.top + 1));
      }

      if (model.label.isNotEmpty) {
        // R9 #4: the number SHRINKS to fit its row before it thins out —
        // the horizontal ruler's rule, through the same helper. The 14 was
        // hard-coded, so a zoomed-out row printed a 14pt glyph into a 6px
        // slot.
        final number = _label(
          model.label,
          TextStyle(
            // 14 → 11, the SHARED ruler's base (R10 R6). The 14 was the
            // sheet's own number, affordable only while the rail was 72
            // wide.
            fontSize: timelineFittedGlyphFontSize(
              11,
              metrics.frameCellWidth,
              crossExtent: metrics.layerControlsWidth,
            ),
            color: model.outsidePlaybackRange
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                : colorScheme.onSurface,
          ),
        );
        number.paint(
          canvas,
          Offset(
            rect.center.dx - number.width / 2,
            rect.center.dy - number.height / 2,
          ),
        );
      }

      // The cached-range strip moved to [TimelineRulerCursorOverlay] (in
      // its vertical form, hugging the right edge): cached-ness is derived
      // state with no invalidation event, so it must repaint freely rather
      // than ride this gated painter.
    }

    // The structural right edge, full strength, whatever the zoom.
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      linePaint..color = colorScheme.outlineVariant,
    );
  }

  // Shared laid-out-TextPainter cache (UI-R16): rail numbers repeat
  // across repaints — fresh layout per label was the debug hot spot.
  TextPainter _label(String text, TextStyle style) =>
      timelineGlyphPainter(text, style);

  @override
  bool shouldRepaint(covariant XSheetFrameRailPainter oldDelegate) =>
      oldDelegate.frameStartIndex != frameStartIndex ||
      oldDelegate.frameEndIndexExclusive != frameEndIndexExclusive ||
      oldDelegate.currentFrameIndex != currentFrameIndex ||
      oldDelegate.playbackFrameCount != playbackFrameCount ||
      oldDelegate.leadingFrameSpacerHeight != leadingFrameSpacerHeight ||
      oldDelegate.metrics != metrics ||
      oldDelegate.framesPerSecond != framesPerSecond ||
      oldDelegate.showSeconds != showSeconds ||
      !identical(oldDelegate.windowBucket, windowBucket) ||
      oldDelegate.viewportMainExtent != viewportMainExtent ||
      // Value-compared, never `identical`: Theme.of(context).colorScheme is a
      // fresh instance every build, so an identity check re-recorded the
      // whole rail on every rebuild.
      oldDelegate.colorScheme != colorScheme;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final nodes = <CustomPainterSemantics>[];
    final window = visibleRowWindow();
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      nodes.add(
        CustomPainterSemantics(
          rect: rowRectFor(frameIndex),
          properties: SemanticsProperties(
            label: 'frame ${frameIndex + 1}',
            textDirection: TextDirection.ltr,
          ),
        ),
      );
    }
    return nodes;
  };
}

/// One cell of the section band above the layer headers: the paper sheet's
/// group heading wrapping its columns. Display-only — section visibility
/// lives on the toolbar toggles. The band label is horizontal already (the
/// band runs along the layer axis here).
class _XSheetSectionBandCell extends StatelessWidget {
  const _XSheetSectionBandCell({
    required this.run,
    required this.extent,
    required this.height,
  });

  /// Resolved per layout: the strip gives ground with the block (R10 R6).
  final double height;

  final TimelineSectionRun run;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: extent,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.washDown,
          border: Border.all(color: colorScheme.outline, width: 1),
        ),
        // The band runs ALONG the layer axis, so its label stays
        // horizontal. It used to SHRINK into a narrow run; the rail-window
        // round retired that everywhere on screen, so a one-column run
        // ellipsises like any other label that outgrows its slot.
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              timelineSectionLabel(run.section),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many nesting levels a COLUMN spells out before it stops.
///
/// The rail indents along a row's long axis, where the name keeps whatever
/// width is left. A column indents along its own length — the very run the
/// name is written down — so every level costs the name directly (#18's
/// "빈 칸 N개 + 화살표 1개", transposed). The name clips rather than
/// ellipsing (a vertical `…` costs one of the two or three characters that
/// identify the row, and dropping a run for it is a regression this repo
/// has already shipped once), and past this depth the arrow alone says
/// "nested" so the name never clips to nothing (user, 2026-08-09: 잘리게
/// 하되 추천 로직대로).
const int _xsheetMaxNestingLevels = 2;

class _LayerHeader extends StatelessWidget {
  const _LayerHeader({
    required this.layer,
    this.depth = 0,
    required this.active,
    this.selected = false,
    required this.onSelectLayer,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.opacityDragPreview,
    required this.onToggleLayerTimesheet,
    required this.onLayerMarkSelected,
    required this.metrics,
    this.onToggleLayerFillReference,
    this.onOpenLayerMixer,
    this.attachArrowPlacement,
    this.hasLanes = false,
    this.lanesExpanded = false,
    this.onToggleLanes,
    this.wearsBaseComposite = false,
    this.fxState = LayerFxState.on,
    this.onToggleLayerFx,
    this.isLayerSoloed = false,
    this.onToggleLayerOnionSkin,
    this.onionSkinEnabled = false,
    this.onLayerBlendModeSelected,
    this.blendLanguage = AppLanguage.en,
    this.hasGroupFold = false,
    this.groupFoldExpanded = true,
    this.onToggleGroupFold,
    required this.headerExtent,
  });

  /// The GROUP-FOLD twirl, transposed (R5 #2): the rail puts it right of
  /// the name, so the stood-up column puts it BELOW the name — one control
  /// in one place on both surfaces. Null [onToggleGroupFold] hides it, and
  /// the slot is not reserved: only rows that hold other rows have one, on
  /// either axis.
  final bool hasGroupFold;
  final bool groupFoldExpanded;
  final ValueChanged<LayerId>? onToggleGroupFold;

  final TimelineGridMetrics metrics;

  /// The column header's NATURAL height — the stood-up rail's full slot
  /// list. Always this, whatever the panel has: the rail window above
  /// decides how much of it shows.
  final double headerExtent;

  final Layer layer;

  /// The row's folder nesting depth, spelled out up to
  /// [_xsheetMaxNestingLevels].
  final int depth;
  final bool active;

  /// ⑨: in the rail's ROW SELECTION — the same wash as [active], because
  /// it is the same statement: this is what the verbs act on.
  final bool selected;

  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  /// The session's live opacity-drag preview (UI-R6 #2).
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  final ValueChanged<LayerId> onToggleLayerTimesheet;
  final void Function(LayerId layerId, LayerMark mark) onLayerMarkSelected;

  /// Drawing columns' fill-reference toggle (R20-C2); null hides it.
  final ValueChanged<LayerId>? onToggleLayerFillReference;

  /// SE columns' speaker button — the mixer's door, exactly as on the
  /// horizontal rail. Null hides the speaker.
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  final bool isLayerSoloed;

  /// Which way this column's attach ARROW points in the sheet slot, null
  /// off an attach group (R10 R3). Precomputed like [wearsBaseComposite]:
  /// a folder's direction is stack order against its base.
  final AttachedPlacement? attachArrowPlacement;

  /// AE-style property-lane twirl-down: layers with lanes lead their name
  /// row with a chevron (lane COLUMNS open beside the layer's). Headers
  /// without lanes skip the slot — names center per column here, so no
  /// cross-column alignment to preserve.
  final bool hasLanes;
  final bool lanesExpanded;
  final ValueChanged<LayerId>? onToggleLanes;

  /// The AE-style fx MASTER (R8: persisted, tri-state). Null hides it.
  /// R9: wears its BASE's composite (attach row, or the 공정 organizer
  /// folder) — see [attachRowWearsBaseComposite].
  final bool wearsBaseComposite;

  final LayerFxState fxState;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// The ONION and BLEND columns the sheet gained in R10 R6 — the last two
  /// the timeline rail had and this one did not.
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;
  final bool onionSkinEnabled;
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;
  final AppLanguage blendLanguage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showLaneToggle = hasLanes && onToggleLanes != null;

    final header = InkWell(
      key: ValueKey<String>('xsheet-layer-header-${layer.id}'),
      onTap: () => onSelectLayer(layer.id),
      child: Container(
        width: metrics.layerRowHeight,
        height: headerExtent,
        // No padding: a 28px column has none to give, and the shared slot
        // skeleton already carries the row's gaps.
        decoration: BoxDecoration(
          // R5 #17: the SAME wash the rail rows wear, resolved against this
          // surface's own resting colour so the column stays opaque (the
          // rail lays its translucent wash over `surface`; the sheet's
          // headers sit on `surfaceContainerHighest`). One value, one
          // saturation — the sheet used to paint `secondaryContainer` at
          // full strength and read a shade louder than the rail for the
          // same state.
          //
          // ㊴: the wash belongs to the ACTIVE column alone. A SELECTED one
          // takes the ring instead (below) — the sheet is the rail turned on
          // its side, so it splits the two states the same way.
          color: active
              ? Color.alphaBlend(
                  railSelectedRowColor(colorScheme),
                  colorScheme.surfaceContainerHighest,
                )
              : colorScheme.surfaceContainerHighest,
          // CONSTANT 1px borders, right/top/bottom only (UI-R10 #20):
          // side-by-side headers kept doubling their shared seam. The left
          // line is the neighbor's right (the frame rail closes the first
          // column).
          //
          // R5 #17: and they are constant in COLOUR too now. The accent
          // outline the active column drew was retired from the timeline
          // rows long ago (UI-R18 #5 — selection speaks through the
          // background alone) and survived here alone, which is the whole
          // shape of this round: one statement, said twice, in two ways.
          border: Border(
            right: BorderSide(color: colorScheme.outlineVariant),
            top: BorderSide(color: colorScheme.outlineVariant),
            bottom: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Semantics(
          key: active ? const ValueKey<String>('xsheet-selected-layer') : null,
          label: active ? 'selected layer' : 'layer',
          container: true,
          // R10 R6 — THE RAIL ROW, STOOD UP. This used to be a hand-rolled
          // two-row box 164px wide, which is why it had no fill-reference
          // slot (the toggle was Positioned over the name's balance), no
          // onion, no blend, and a "balance" SizedBox doing arithmetic to
          // keep the name centred. It is the shared skeleton now, in the
          // shared order, at the shared extents — the same list the
          // timeline's rows and the legend above read, running downward.
          //
          // `stretch`: a reserved (childless) slot keeps its extent either
          // way, but a POPULATED one would take its intrinsic width under
          // the default `center` and could out-grow a 28px column. Stretch
          // makes every slot exactly one column wide, which is what the
          // horizontal rail gets from its row height.
          //
          // The column is ALWAYS laid out whole. A panel too short for it
          // used to drop controls (R10 R6), then to scale the whole column
          // (R6a); it shows a shorter WINDOW now, and the difference is a
          // cut. Which means the legend beside it and the headers agree by
          // construction rather than by two mechanisms staying in step —
          // they did not, and 400px was where they visibly parted.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...layerRailLeadingCells(
                axis: Axis.vertical,
                // #18 transposed, capped: see [_xsheetMaxNestingLevels].
                depth: math.min(depth, _xsheetMaxNestingLevels),
                // The band is the strip above, not a slot in here.
                includeSectionSlot: false,
                laneToggle: showLaneToggle
                    ? InkWell(
                        key: ValueKey<String>('xsheet-lane-toggle-${layer.id}'),
                        onTap: () => onToggleLanes!(layer.id),
                        customBorder: const CircleBorder(), // R26 #28
                        child: Icon(
                          layerRailTwirlIcon(expanded: lanesExpanded),
                          size: 16,
                        ),
                      )
                    : null,
                // R10 R3: the attach ARROW takes the SHEET slot on attach
                // columns, and the gate matches the rail's — the x-sheet
                // had no `attachedToLayerId` check, so an attach column
                // showed a live sheet toggle the rail hides.
                timesheet: attachArrowPlacement != null
                    ? LayerAttachArrowCell(
                        keyPrefix: 'xsheet',
                        idValue: '${layer.id}',
                        placement: attachArrowPlacement!,
                      )
                    : (layerKindEligibleForTimesheetToggle(layer.kind) &&
                          layer.attachedToLayerId == null)
                    ? LayerTimesheetToggleButton(
                        keyPrefix: 'xsheet',
                        layerId: layer.id,
                        onTimesheet: layer.onTimesheet,
                        onToggle: onToggleLayerTimesheet,
                      )
                    : null,
                mark: LayerMarkChip(
                  keyPrefix: 'xsheet',
                  layerId: layer.id,
                  mark: layer.mark,
                  onMarkSelected: onLayerMarkSelected,
                ),
                typeButton: LayerTypeButton(
                  keyPrefix: 'xsheet',
                  idValue: '${layer.id}',
                  kind: layer.kind,
                  folderCollapsed: layer.collapsed,
                  onTap: () => onSelectLayer(layer.id),
                ),
              ),
              // The NAME takes the remainder, exactly as the row's
              // `Expanded` does — written vertically, because a 28px column
              // is a paper timesheet column and that is how one is read.
              Expanded(
                child: InkWell(
                  key: ValueKey<String>('xsheet-layer-name-${layer.id}'),
                  onTap: () => onSelectLayer(layer.id),
                  // Selection reads by COLOR only (user rule): no bold flip
                  // on the active column's name.
                  child: ClipRect(
                    child: VerticalWritingText(
                      text: layer.name,
                      // A name you READ, so the letters stand up and the
                      // column begins at the top — the rail's left-aligned
                      // name, transposed (user, 2026-08-08). It used to lie
                      // down AND float in the middle of its own column.
                      latinForm: VerticalLatinForm.upright,
                      mainAlignment: 0,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              // The fold twirl, transposed: the rail's "right of the name"
              // is the column's "below the name" (R5 #2). Same key grammar
              // as the rail so a folder and an attach base read alike here
              // too.
              if (hasGroupFold && onToggleGroupFold != null)
                InkWell(
                  key: ValueKey<String>(
                    layerKindGroupsLayers(layer.kind)
                        ? 'xsheet-folder-twirl-${layer.id}'
                        : 'xsheet-attach-twirl-${layer.id}',
                  ),
                  onTap: () => onToggleGroupFold!(layer.id),
                  customBorder: const CircleBorder(), // R26 #28
                  child: SizedBox(
                    height: layerLaneToggleSlotWidth,
                    child: Icon(
                      layerRailTwirlIcon(expanded: groupFoldExpanded),
                      size: 16,
                    ),
                  ),
                ),
              ...layerRailTrailingCells(
                axis: Axis.vertical,
                hasOnionColumn: onToggleLayerOnionSkin != null,
                hasBlendColumn: onLayerBlendModeSelected != null,
                // R20-C2: the fill-reference toggle finally has a SLOT
                // instead of an overlay. Drawing columns only.
                fillReference:
                    onToggleLayerFillReference != null &&
                        layer.kind == LayerKind.animation
                    ? IconButton(
                        key: ValueKey<String>(
                          'xsheet-layer-fill-reference-${layer.id}',
                        ),
                        tooltip: layer.isFillReference
                            ? 'Fill reference layer (on)'
                            : 'Fill reference layer',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 20,
                          height: 20,
                        ),
                        icon: Icon(
                          Icons.format_color_fill,
                          size: 13,
                          color: layer.isFillReference
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.45),
                        ),
                        onPressed: () => onToggleLayerFillReference!(layer.id),
                      )
                    : null,
                // Attach rows and their 공정 organizer folder hide the
                // switch in BOTH orientations: they wear their base's fx,
                // so a flip here would burn an undo step writing a flag
                // nothing reads.
                fx:
                    onToggleLayerFx != null &&
                        layerKindShowsFxToggle(layer.kind) &&
                        !wearsBaseComposite
                    ? FxToggleButton(
                        keyValue: 'xsheet-layer-fx-${layer.id}',
                        state: fxState,
                        onToggle: () => onToggleLayerFx!(layer.id),
                      )
                    : null,
                // Onion (UI-R17 #5) — the sheet went without it until
                // R10 R6's "싹다 넣어".
                onion:
                    onToggleLayerOnionSkin != null &&
                        layerKindAcceptsBrushInput(layer.kind)
                    ? IconButton(
                        key: ValueKey<String>('xsheet-layer-onion-${layer.id}'),
                        tooltip: onionSkinEnabled
                            ? 'Onion skin (on)'
                            : 'Onion skin',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: layerOnionSlotWidth,
                          height: layerOnionSlotWidth,
                        ),
                        icon: Icon(
                          Icons.filter_none,
                          size: 15,
                          color: onionSkinEnabled
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.45),
                        ),
                        onPressed: () => onToggleLayerOnionSkin!(layer.id),
                      )
                    : null,
                visibility: LayerVisibilityToggleButton(
                  keyValue: 'xsheet-layer-visibility-${layer.id}',
                  isVisible: layer.isVisible,
                  onToggle: () => onToggleLayerVisibility(layer.id),
                  size: layerVisibilitySlotWidth,
                  iconSize: 16,
                ),
                // SE columns carry the mute speaker — the mixer's door.
                mute: layer.kind == LayerKind.se && onOpenLayerMixer != null
                    ? LayerMuteToggleButton(
                        keyValue: 'xsheet-layer-mute-${layer.id}',
                        muted: layer.muted,
                        soloed: isLayerSoloed,
                        width: metrics.layerRowHeight,
                        height: layerMuteSlotWidth,
                        onOpenMixer: (anchorContext) =>
                            onOpenLayerMixer!(anchorContext, layer.id),
                      )
                    : null,
                // The camera column's slider drives the camera-view DIM
                // opacity (unified layer controls). Wrapped in the
                // session's opacity-drag preview (UI-R6 #2) so a
                // master-bar sweep updates it live.
                opacity: layerKindShowsOpacityControl(layer.kind)
                    ? Center(child: _opacityField(layer))
                    : null,
                // R27 #6: the BLEND chip, the sheet's copy of the rail's.
                blend:
                    onLayerBlendModeSelected != null &&
                        layerKindShowsBlendControl(layer.kind)
                    ? LayerBlendModeChip(
                        axis: Axis.vertical,
                        keyValue: 'xsheet-layer-blend-${layer.id}',
                        optionKeyPrefix: 'xsheet-layer-blend-option-',
                        blendMode: layer.blendMode,
                        language: blendLanguage,
                        isGroup: layerKindGroupsLayers(layer.kind),
                        subject: layerKindGroupsLayers(layer.kind)
                            ? 'Folder'
                            : 'Layer',
                        onBlendModeSelected: (mode) =>
                            onLayerBlendModeSelected!(layer.id, mode),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );

    // Section boundaries draw ONE shared hairline like every column
    // boundary (R3 feedback #6) — the extra 2px overlay double-lined them;
    // the band above carries the section identity.
    if (!selected) {
      return header;
    }
    // ㊴, transposed: the selection ring traces the column the wash would
    // have filled, so a column can read as ACTIVE and SELECTED at once.
    return Stack(
      children: [
        header,
        const Positioned.fill(
          child: TimelineSelectionRing(
            key: ValueKey<String>('xsheet-column-selection-ring'),
          ),
        ),
      ],
    );
  }

  /// The header's opacity slider, live-following the session's drag preview
  /// when it targets this layer (UI-R6 #2).
  Widget _opacityField(Layer layer) {
    // Stood up like every other control in this column: the fader fills
    // upward and its readout writes downward. `RotatedBox` was not an
    // option — see [FieldSlider.axis].
    Widget slider(double value) => FieldSlider(
      key: ValueKey<String>('xsheet-layer-opacity-${layer.id}'),
      axis: Axis.vertical,
      min: 0,
      max: 1,
      value: value,
      valueText: '${(value * 100).round()}%',
      valueTextBuilder: (next) => '${(next * 100).round()}%',
      height: 18,
      onChanged: (opacity) => onLayerOpacityChanged(layer.id, opacity),
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

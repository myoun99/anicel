import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/camera_instruction.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite;
import '../../models/attached_placement.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/timeline_row_address.dart';
import 'timeline_row_cross_offset.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import 'timeline_row_span_resolver.dart'
    show
        resolveLaneSpanEscalation,
        resolveSelectionSpanHead,
        resolveSelectionSpanRows;
import 'effect_lane_policy.dart' show parseEffectLaneId;
import 'layer_drop_policy.dart'
    show effectHeaderRowsOf, effectStepsBetween, slotForSteps;
import 'layer_row_drag.dart';
import 'timeline_current_row.dart';
import 'timeline_edge_auto_pan.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_ruler_cursor_overlay.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_frame_cursor_layer.dart';
import 'timeline_frame_grid_stack.dart';
import 'timeline_beat_lines.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_frame_scroll_viewport.dart';
import 'timeline_frame_ruler.dart';
import 'timeline_frame_rows_scroll_body.dart';
import 'timeline_frame_window.dart';
import 'layer_rail_window.dart';
import 'layer_label_controls.dart'
    show SectionBandZone, layerSectionLabelSlotWidth, layerVisibilitySlotWidth;
import 'layer_rail_columns.dart'
    show LayerRailTrailingSlot, layerRailTrailingWidth;
import 'timeline_grid_metrics.dart';
import 'timeline_horizontal_offset_policy.dart';
import 'timeline_horizontal_scrollbar_rail.dart';
import 'property_lane_model.dart';
import 'se_audio_lane.dart' show TimelineAudioLaneCallbacks;
import 'timeline_lane_rows.dart';
import 'timeline_layer_controls_header.dart';
import 'timeline_layer_frame_body_layout.dart';
import 'pen_friendly_scroll_controller.dart';
import 'stylus_glide_stop.dart';
import 'timeline_zoom_anchor_policy.dart';
import 'timeline_layer_controls_row.dart';
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';
import 'timeline_section_runs.dart';
import 'timeline_selected_exposure_outline.dart'
    show TimelineRowSelectionBands;
import 'timeline_vertical_scrollbar_rail.dart';
import 'timeline_visible_range.dart';

import '../../models/project_frame_rate.dart';

class LayerTimelineGrid extends StatefulWidget {
  const LayerTimelineGrid({
    super.key,
    required this.layers,
    required this.activeLayerId,
    required this.frameCursor,
    this.frameReadySignal,
    this.revealSelectionTick,
    required this.playbackFrameCount,
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
    this.seClipMarkerTooltip,
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
    required this.onToggleLayerTimesheet,
    this.layerFxStateOf,
    this.layerIsLinkedOf,
    this.onToggleLayerCollapsed,
    this.layerOnionSkinEnabledOf,
    this.onToggleLayerOnionSkin,
    this.displayedOnionSkinOn = false,
    this.onToggleLayerFx,
    required this.onLayerMarkSelected,
    this.onToggleLayerFillReference,
    this.commaDrag,
    this.rangeHooks,
    this.laneRange,
    this.currentRowHooks,
    this.rowDragHooks,
    this.onRowSelectionSpan,
    this.selectedRows = const {},
    this.runEdit,
    this.isFrameReady,
    this.metrics = TimelineGridMetrics.defaults,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.lanesForLayer,
    this.unionLaneForLayer,
    this.laneEdit,
    this.onToggleLaneGroup,
    this.onToggleLaneGroupEnabled,
    this.onResetLaneGroup,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.legend,
    this.rowFilter = TimelineRowFilter.none,
    this.onSetRowFilter,
    this.collapsedAttachBaseIds = const {},
    this.onToggleAttachGroup,
    this.visibilitySoloEnabled = false,
    this.dragPreview,
    this.opacityDragPreview,
    this.masterOpacityValue = 1.0,
    this.seSpillInLayerIds = const {},
    this.cutEndDrag,
    this.substrateGeneration = '',
    this.memoAux = const TimelineRowMemoAux(),
    this.onLayerBlendModeSelected,
    this.blendLanguage = AppLanguage.en,
    this.layerOpacityOverrideOf,
  });

  final List<Layer> layers;
  final LayerId? activeLayerId;

  /// R27 #6: the label's blend-mode dropdown (rightmost column) and the
  /// legend's bulk pick both commit through this.
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;

  /// PROGRAM language for the blend-mode names.
  final AppLanguage blendLanguage;

  /// R27 #9: rows whose opacity is a live VIEW notifier (the camera row's
  /// dim) hand it over here — the slider subscribes and the drag never
  /// touches the host.
  final ValueListenable<double>? Function(LayerId layerId)?
  layerOpacityOverrideOf;

  /// The session's edit-drag preview channel: a comma-drag step rebuilds
  /// only the dragged layer's row (its gate) and the cursor overlay —
  /// never this grid.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// End-line drag hooks (UI-R18 #14): the red cut-end boundary grows a
  /// grip that end-trims the ACTIVE cut through the session's trim
  /// channel; the line follows the live preview. Null = display-only.
  final TimelineCutEndDragCallbacks? cutEndDrag;

  /// Sparse-row memo identity tokens (UI-R20 #4) — see
  /// [TimelineFrameRowsScrollBody.memoAux].
  final TimelineRowMemoAux memoAux;

  /// #29: the (project, cut) world the rows' resolvers answer from — see
  /// [TimelineRowCellsPainter.substrateGeneration].
  final String substrateGeneration;

  /// Track-SE rows whose display clone starts with a spill-in block
  /// (UI-R7 #6: `~` at the cut start, start grip stands down).
  final Set<LayerId> seSpillInLayerIds;

  /// The frame cursor (editing playhead, or the playback position while
  /// playing). ONLY the cursor layer, the ruler and the lane labels
  /// subscribe — a tick never rebuilds the grid or its cells (the
  /// playback-performance architecture).
  final ValueListenable<int> frameCursor;

  /// Repaints the ruler's cached-range green strip as frames warm; never
  /// rebuilds anything else.
  final Listenable? frameReadySignal;

  /// R5: the session's "bring the selection back into view" tick. Null
  /// leaves the grid scrolling only where the user put it, which is what a
  /// passive host wants.
  final ValueListenable<int>? revealSelectionTick;

  final int playbackFrameCount;

  /// How many frames the cut is DRAWN for (尺 + のりしろ). Null keeps the
  /// ruler's blue handle boundary off, which is every cut no transition
  /// crosses.
  final int? drawnFrameCount;

  /// The word the ruler spells across the handle.
  final String noriShiroLabel;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact source + its memo token
  /// (see [TimelineFrameRowsScrollBody]); null = no tint.
  /// R26 #44: the unworked-block tint's fact and its event.
  final TimelineCelContentSource? celContent;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// 🚨T10's second half: a press that turned out to be a TAP clears
  /// whatever was selected (유저: 「클릭하고 떼면 뭐든 비우게」). Handed
  /// down to the cell rows; null leaves the grid display-only.
  final VoidCallback? onSettledPress;

  /// Ruler-scrub path: per-move frames go to [onScrubFrame] (cursor-only,
  /// no commit) and the pointer's release fires [onScrubEnd] to commit
  /// once. Null falls back to [onSelectFrame] per move.
  final ValueChanged<int>? onScrubFrame;
  final VoidCallback? onScrubEnd;

  /// Double-tap cell editor hook (SE label dialog; see
  /// [layerKindOpensCellEditorOnDoubleTap]).
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// Resolves instruction ids to defs for CAM row chips.
  final CameraInstructionDef? Function(String instructionId)?
  instructionDefById;

  /// Waveform peaks for SE rows' audio clips + the removal hook.
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// Clipped-take marker tooltip (REC1-D); null = markers off.
  final String? seClipMarkerTooltip;
  final ProjectFrameRate projectFrameRate;

  /// The ruler's bottom-line mode (UI-R10 #27): seconds display repeats
  /// 1..fps per second instead of absolute frame numbers.
  final bool showSeconds;

  /// The seconds toggle moved OUT of the command bar and onto the grid's
  /// top-left corner cell (the rail-window round) — it belongs beside the
  /// axis it relabels. Null leaves the corner as a plain spacer.
  final ValueChanged<bool>? onShowSecondsChanged;

  /// The rail's window size, set by this grid's splitter and persisted by
  /// the workspace. Null = a session-local one of our own (tests, and any
  /// host that has no place to keep it).
  final LayerRailExtent? railExtent;

  /// What the audio lane may ask the session to do; null = display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// A media-browser row dropped on a DRAWING layer: the window opens with
  /// this cut and this layer already answered.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onDropMediaAssetOnLayer;

  /// The SE row's mixer (R10 R3): its solo tint, and the speaker press
  /// that opens the window carrying mute/solo/fader/pan. Null hides the
  /// speaker.
  final bool Function(LayerId layerId)? isLayerSoloed;
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  /// Which way a row's attach ARROW points in its sheet slot (R10 R3), or
  /// null off an attach group. A RESOLVER, not a list: the answer depends
  /// on stack order against the base, and this grid holds the horizontal
  /// DISPLAY order (`sectionedLayerOrder(...).reversed`) — computing it
  /// here would invert every organizer folder's arrow on this surface
  /// alone.
  final AttachedPlacement? Function(LayerId layerId)? attachArrowPlacementOf;

  final VoidCallback onAddLayer;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;
  final ValueChanged<LayerId> onToggleLayerTimesheet;

  /// The AE-style layer fx MASTER (R8: persisted, tri-state); null hides it.
  final LayerFxState Function(LayerId layerId)? layerFxStateOf;

  /// Link badge state (L4): whether a layer's pictures are shared with a
  /// link group. Null shows no badges.
  final bool Function(LayerId layerId)? layerIsLinkedOf;

  /// The row twirl that folds a FOLDER's members (the attach fold has its
  /// own hook because it is session state, not layer state).
  final ValueChanged<LayerId>? onToggleLayerCollapsed;

  /// Per-layer onion skin (UI-R17 #5): the row toggles + the legend cell's
  /// engaged state. Null hides the onion column entirely.
  final bool Function(LayerId layerId)? layerOnionSkinEnabledOf;
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;
  final bool displayedOnionSkinOn;
  final ValueChanged<LayerId>? onToggleLayerFx;
  final void Function(LayerId layerId, LayerMark mark) onLayerMarkSelected;

  /// Drawing rows' fill-reference toggle (R20-C2); null hides it.
  final ValueChanged<LayerId>? onToggleLayerFillReference;

  /// Comma-drag hooks for the block edge grips (shared policy with the
  /// X-sheet); null hides the grips.
  final TimelineCommaDragCallbacks? commaDrag;

  /// The frame-range select/move hooks (UI-R8, the block-body move's
  /// successor): the grid resolves the pointer's row onto display rows and
  /// forwards frame delta + target layer to the session. Null keeps rows
  /// display-only.
  final TimelineFrameRangeHooks? rangeHooks;

  /// The LANE selection domain's gesture bundle (UI-R23 #3 part 2); null
  /// keeps the lane bands display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  /// Which row the frame-axis verbs act on, and the label press that moves
  /// it (R10 #19's rail half); null leaves lane labels inert and unwashed.
  final TimelineCurrentRowHooks? currentRowHooks;

  /// The row-order drag: grabbing a rail row moves it. Null leaves the rows
  /// undraggable, which is what a passive host wants.
  final TimelineRowDragHooks? rowDragHooks;

  /// ⑨: the row SELECT drag's span, in this rail's own DISPLAY rows.
  ///
  /// Separate from [rowDragHooks] because it carries the row list — the
  /// same reason the caret's slot updates do, and the same list the cell
  /// span already walks, so "visible means selectable" stays structural
  /// rather than being re-derived per verb (뿌리 A).
  final void Function(List<TimelineDisplayRow> rows, int rowDelta)?
  onRowSelectionSpan;

  /// ⑨: the rows currently in the selection, as layer ids — what the rail
  /// washes and what the row verbs act on.
  final Set<TimelineRowAddress> selectedRows;

  /// The run-edge [+]/[↻] handle hooks (UI-R8); null hides the handles.
  final TimelineRunEditCallbacks? runEdit;

  /// Cached-range resolver for the ruler's green strip.
  final bool Function(int frameIndex)? isFrameReady;

  /// Grid geometry; the frame-axis cell width carries the panel zoom.
  final TimelineGridMetrics metrics;

  /// AE-style property lanes: layers whose twirl-down is open, the toggle,
  /// and the lane provider (generic — transform lanes now, FX lanes later).
  final Set<LayerId> expandedLaneLayerIds;
  final ValueChanged<LayerId>? onToggleLayerLanes;
  final List<PropertyLaneRow> Function(Layer layer)? lanesForLayer;

  /// The union-summary provider (the CAMERA row's key markers, B4) — see
  /// [TimelineFrameRowsScrollBody.unionLaneForLayer].
  final PropertyLaneRow? Function(Layer layer)? unionLaneForLayer;

  /// Lane key editing hooks (navigator toggle, marker drags, hold/delete).
  final PropertyLaneEditCallbacks? laneEdit;

  /// Group headers: tapping twirls the group's member lanes (AE collapse).
  final void Function(Layer layer, PropertyLaneRow lane)? onToggleLaneGroup;

  /// The group header's own ON/OFF switch (R6), forwarded to the lane rows.
  final void Function(Layer layer, PropertyLaneRow lane)?
  onToggleLaneGroupEnabled;

  /// The group header's RESET (R5), forwarded to the lane rows.
  final void Function(Layer layer, PropertyLaneRow lane)? onResetLaneGroup;

  /// Sections folded to one stub row (SE/camera; drawing never folds) and
  /// the gutter-label toggle.
  /// Sections hidden from the grid entirely (toolbar visibility toggles).
  final Set<TimelineSection> hiddenSections;

  /// Folds/unfolds a hideable section (the legend corner's sections cell).
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The rail legend's bulk commands; null renders a display-only legend.
  final LayerLegendCallbacks? legend;

  /// The rail's row FILTER (R2): hides layer rows failing its predicate;
  /// the active layer is exempt.
  final TimelineRowFilter rowFilter;

  /// Applies a row-filter edit (legend solo toggles).
  final ValueChanged<TimelineRowFilter>? onSetRowFilter;

  /// Bases whose attach group is twirled shut (UI-R20 #9): their attach
  /// rows contribute no display rows; the base row's chevron reflects it.
  final Set<LayerId> collapsedAttachBaseIds;

  /// The base-row chevron's toggle; null hides the twirl UI.
  final ValueChanged<LayerId>? onToggleAttachGroup;

  /// Whether the visibility solo mode is engaged (legend eye state color).
  final bool visibilitySoloEnabled;

  /// The session's live opacity-drag preview (UI-R6 #2): rows follow it
  /// while the master bar sweeps them.
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  /// The master bar's resting value (the LAST committed sweep, UI-R6 #2).
  final double masterOpacityValue;

  @override
  State<LayerTimelineGrid> createState() => _LayerTimelineGridState();
}

/// The data snapshot a memoized RAIL row was built from (UI-R7 #1) —
/// zoom-independent by construction: nothing here reads frameCellWidth,
/// so zoom steps always hit.
typedef _RailRowMemoInputs = ({
  Layer layer,
  bool active,
  // ㉞: the row selection wash. SESSION state like [active] and invisible to
  // the Layer comparison — ⑨ passed `selected` to the row without giving the
  // memo a way to see it change, so the wash never appeared until some other
  // fact happened to invalidate the entry. The state was right the whole
  // time; the cache answered "unchanged" (the ㉘ shape).
  bool selected,
  bool hasLanes,
  bool lanesExpanded,
  int depth,
  bool hasAttachGroup,
  bool attachGroupExpanded,
  LayerFxState fxState,
  bool onionSkinEnabled,
  bool isLinked,
  bool soloed,
  AttachedPlacement? attachArrow,
  double layerRowHeight,
  double layerControlsWidth,
  double sectionLabelGutterWidth,
  ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview,
  // R27 #6: the blend chip prints a LANGUAGE-dependent name — a language
  // switch must invalidate the memo like any other visible fact.
  AppLanguage blendLanguage,
});

/// The legend header's memo token (UI-R7 #1): every legend-visible fact.
/// A new legend-reading cell must join this record — miss one and the
/// header shows stale state.
typedef _LegendMemoInputs = ({
  double layerRowHeight,
  double layerControlsWidth,
  bool hasLegend,
  Set<TimelineSection> hiddenSections,
  TimelineRowFilter rowFilter,
  Set<LayerMark> marksInUse,
  Set<LayerKind> kindsInUse,
  bool visibilitySoloEnabled,
  bool anyLanesExpanded,
  bool allSeMuted,
  Set<LayerId> displayedIds,
  double masterOpacityValue,
  bool hasLaneToggles,
  bool displayedOnionSkinOn,
  // R27 #6: the blend column's header prints language-dependent names in
  // its flyout and gates on the bulk callback's presence.
  AppLanguage blendLanguage,
  bool hasBlendBulk,
});

class _LayerTimelineGridState extends State<LayerTimelineGrid> {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.projectFrameRate.countingBase;

  TimelineGridMetrics get _metrics => widget.metrics;

  /// Identity-gated RAIL row memo (UI-R7 #1, the frame rows' memo idiom):
  /// a zoom step re-lays-out the frame grid, but the rail's Material-heavy
  /// control rows (tooltips, ink wells, sliders) don't depend on the zoom
  /// — identical inputs hand the SAME widget instance back so Flutter
  /// skips their whole subtree rebuild. Layer identity gates content
  /// (commits swap instances); callbacks follow the R13-2 rule (host
  /// callbacks close over the stable session only).
  final Map<LayerId, ({_RailRowMemoInputs inputs, Widget row})> _railRowMemo =
      {};

  /// The legend header's memo — same idea, token-gated (R13-2): the
  /// header's ~15 tooltip/flyout cells rebuild only when a legend-visible
  /// fact changes, never on zoom steps.
  ({_LegendMemoInputs inputs, Widget header})? _legendHeaderMemo;

  late final ScrollController _horizontalScrollController;
  late final ScrollController _verticalScrollController;

  /// The frame-axis scroll offset as a NOTIFIER (UI-R9 #12a): a scroll
  /// pixel updates this value only — the ruler's translate and the window
  /// token subscribe, and the grid itself never rebuilds per pixel (the
  /// body is a real scrollable; pixels are free there).
  final ValueNotifier<double> _frameAxisOffset = ValueNotifier<double>(0);

  /// The fallback rail extent for hosts that keep none of their own.
  LayerRailExtent? _ownedRailExtent;

  LayerRailExtent get _railExtent =>
      widget.railExtent ?? (_ownedRailExtent ??= LayerRailExtent());

  /// The rail's NATURAL extent — what it costs laid out in full. The
  /// window never changes it; that is the whole point of the model.
  double get _naturalRailWidth => _metrics.layerControlsWidth;

  /// The quantized frame-window token: the leading visible CELL index.
  /// Changes only on cell-boundary crossings — the rows body and the
  /// ruler content re-window from it (sub-cell movement rebuilds nothing).
  final ValueNotifier<int> _frameWindowBucket = ValueNotifier<int>(0);

  /// The scroll position whose activity we watch for the lazy endless
  /// SHRINK (UI-R9 #11: never rescale the extent mid-gesture).
  ScrollPosition? _watchedHorizontalPosition;

  double _verticalScrollOffset = 0;
  double _lastEffectiveHorizontalScrollOffset = 0;
  double? _scheduledHorizontalOffsetCorrection;
  double? _scheduledVerticalOffsetCorrection;
  int _endlessTrailingFrames = 0;
  final GlobalKey _rulerScrubViewportKey = GlobalKey();
  int? _lastRulerScrubbedFrameIndex;

  // Krita-style eye-column swipe (R2): a vertical drag over the eye column
  // toggles every crossed row's visibility to the value LATCHED from the
  // first row (paint-swipe). Null target = no swipe in progress.
  bool? _eyeSwipeTargetVisible;
  final Set<LayerId> _eyeSwipePainted = {};

  /// The eye column's horizontal band within the rail rows' Column, derived
  /// from the slot layout so it tracks the row's own control order.
  ({double left, double right}) _eyeColumnBand() {
    final rowWidth =
        _metrics.layerControlsWidth - _metrics.sectionLabelGutterWidth;
    // From the row's right edge: 8px padding, then every trailing slot the
    // rows actually draw, up to and including the eye.
    //
    // R10 R6: this used to restate the tail by hand — '8px padding,
    // opacity(64), mute(18)' — which was wrong twice over: opacity is 42,
    // and R27 #6 put the BLEND column to opacity's right without anyone
    // updating the arithmetic, so the swipe band sat 58px off the eye
    // whenever blend was shown. Restating derived geometry by hand is the
    // exact failure this round exists to retire; the tail is read from the
    // skeleton now, with the same host gates the rows use.
    const rightPadding = 8.0;
    final tailAfterEye = layerRailTrailingWidth(
      from: LayerRailTrailingSlot.mute,
      hasBlendColumn: widget.onLayerBlendModeSelected != null,
    );
    final eyeRight = rowWidth - rightPadding - tailAfterEye;
    final eyeLeft = eyeRight - layerVisibilitySlotWidth;
    // A little tolerance so the thin 22px band is easy to hit with a pen.
    return (left: eyeLeft - 4, right: eyeRight + 4);
  }

  /// Resolves a rail-local vertical position to a LAYER row (lane rows and
  /// spacer gaps return null), given the window slice currently built.
  Layer? _layerAtRailY(
    double localY,
    List<TimelineDisplayRow> windowRows,
    double leadingSpacerHeight,
  ) {
    final indexInWindow =
        ((localY - leadingSpacerHeight) / _metrics.layerRowHeight).floor();
    if (indexInWindow < 0 || indexInWindow >= windowRows.length) {
      return null;
    }
    final row = windowRows[indexInWindow];
    return row.isLane ? null : row.layer;
  }

  void _paintEyeSwipeAt(Layer? layer) {
    if (layer == null || _eyeSwipeTargetVisible == null) {
      return;
    }
    if (!_eyeSwipePainted.add(layer.id)) {
      return;
    }
    if (layer.isVisible != _eyeSwipeTargetVisible) {
      widget.onToggleLayerVisibility(layer.id);
    }
  }

  @override
  void initState() {
    super.initState();
    // PEN-10: pen-friendly positions — while a stylus is nearby, a
    // coasting fling stops hiding the cells from hit-testing.
    _horizontalScrollController = PenFriendlyScrollController();
    _verticalScrollController = PenFriendlyScrollController();
    _horizontalScrollController.addListener(_handleHorizontalScroll);
    _verticalScrollController.addListener(_handleVerticalScroll);
    widget.revealSelectionTick?.addListener(_handleRevealSelection);
  }

  /// The reveal runs AFTER the frame the selection moved in: the rows this
  /// pass built are what the row index counts in, and on a row step they
  /// have not been rebuilt yet when the tick arrives.
  void _handleRevealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _revealSelection();
      }
    });
  }

  @override
  void didUpdateWidget(covariant LayerTimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealSelectionTick != widget.revealSelectionTick) {
      oldWidget.revealSelectionTick?.removeListener(_handleRevealSelection);
      widget.revealSelectionTick?.addListener(_handleRevealSelection);
    }
    // Zoom-around-playhead: the playhead stays put on screen through zoom
    // when visible; otherwise the leading-edge frame anchors.
    final oldCell = oldWidget.metrics.frameCellWidth;
    final newCell = widget.metrics.frameCellWidth;
    if (oldCell != newCell && _horizontalScrollController.hasClients) {
      _horizontalScrollController.jumpTo(
        zoomAnchoredScrollOffset(
          oldOffset: _horizontalScrollController.offset,
          oldPixelsPerFrame: oldCell,
          newPixelsPerFrame: newCell,
          viewportExtent:
              _horizontalScrollController.position.viewportDimension,
          anchorFrame: widget.frameCursor.value,
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.revealSelectionTick?.removeListener(_handleRevealSelection);
    _watchedHorizontalPosition?.isScrollingNotifier.removeListener(
      _handleHorizontalScrollActivity,
    );
    _horizontalScrollController
      ..removeListener(_handleHorizontalScroll)
      ..dispose();
    _verticalScrollController
      ..removeListener(_handleVerticalScroll)
      ..dispose();
    _frameAxisOffset.dispose();
    _frameWindowBucket.dispose();
    _ownedRailExtent?.dispose();
    super.dispose();
  }

  /// The layer-axis position, or null when the controller is attached to
  /// anything other than exactly one view: `hasClients` only rules out
  /// zero, and `.offset` asserts on two as well.
  ScrollPosition? get _verticalPosition {
    final positions = _verticalScrollController.positions;
    return positions.length == 1 ? positions.first : null;
  }

  /// Re-read the layer-axis offset from the position itself.
  ///
  /// 🚨The position's pixels move WITHOUT notifying: when the rows shrink
  /// out from under it, `ScrollPosition` silently `correctPixels` back into
  /// range during layout, and [_handleVerticalScroll] never runs. An offset
  /// cached from notifications alone therefore freezes at the pre-collapse
  /// value — and (UI-R5 #3) comes back to life the moment the rows grow
  /// again, because the clamp below is applied to a COPY. Expanding an
  /// attach group then scrolled the view down by exactly the rows that had
  /// been folded, cancelling the insertion the user had just asked to see.
  void _readVerticalScrollOffset() {
    final position = _verticalPosition;
    if (position != null && position.hasPixels) {
      _verticalScrollOffset = position.pixels;
    }
  }

  /// Layer-axis virtualization: re-plan only when the scroll crosses a
  /// row boundary (the ≥2-row overscan absorbs sub-row movement).
  void _handleVerticalScroll() {
    final offset = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;
    if (offset == _verticalScrollOffset) {
      return;
    }
    final rowExtent = _metrics.layerRowHeight;
    final oldBucket = (_verticalScrollOffset / rowExtent).floor();
    final newBucket = (offset / rowExtent).floor();
    _verticalScrollOffset = offset;
    if (oldBucket != newBucket) {
      setState(() {});
    }
  }

  /// Frame-axis scroll (UI-R9 #12a): NO setState per pixel. The offset
  /// notifier drives the ruler translate; the window bucket drives the
  /// re-windowing; only an ENDLESS-extent growth (a real relayout, rare)
  /// still rebuilds the grid.
  void _handleHorizontalScroll() {
    if (!_horizontalScrollController.hasClients) {
      return;
    }
    _watchHorizontalScrollActivity();
    final offset = _horizontalScrollController.offset;
    if (offset == _frameAxisOffset.value) {
      return;
    }
    _frameAxisOffset.value = offset;
    // Quantized span buckets (UI-R16): the bucket notifier — the
    // painters' repaint trigger — fires once per span crossing, so the
    // frames between crossings are pure translation.
    final bucket = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: _metrics.frameCellWidth,
    );
    if (bucket != _frameWindowBucket.value) {
      _frameWindowBucket.value = bucket;
    }
    final position = _horizontalScrollController.position;
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _visibleFrameCount,
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _metrics.frameCellWidth,
      // Discrete moves (wheel ticks, programmatic jumps) may shrink right
      // away; gesture pixels never rescale the extent mid-drag (the
      // settle listener below applies the release).
      allowShrink: !position.isScrollingNotifier.value,
    );
    if (nextTrailingFrames != _endlessTrailingFrames) {
      setState(() => _endlessTrailingFrames = nextTrailingFrames);
    }
  }

  void _watchHorizontalScrollActivity() {
    final position = _horizontalScrollController.position;
    if (identical(position, _watchedHorizontalPosition)) {
      return;
    }
    _watchedHorizontalPosition?.isScrollingNotifier.removeListener(
      _handleHorizontalScrollActivity,
    );
    _watchedHorizontalPosition = position;
    position.isScrollingNotifier.addListener(_handleHorizontalScrollActivity);
  }

  /// Scroll settled: apply the lazy endless SHRINK (UI-R9 #11) — the
  /// extent contracts back toward the base + runway so the scrollbar
  /// thumb recovers, never mid-gesture.
  void _handleHorizontalScrollActivity() {
    final position = _watchedHorizontalPosition;
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
        playbackFrameCount: widget.playbackFrameCount,
        minimumVisibleFrameCells: _metrics.minimumVisibleFrameCells,
      );

  int get _visibleFrameCount => _frameRangePolicy.visibleFrameCount;

  /// Frame cells the current viewport needs to be fully papered (UI-R12
  /// #16) — recorded by build's outer LayoutBuilder, like the effective
  /// offsets. Zero until the first layout.
  int _viewportFillFrameCells = 0;

  /// Render extent (UI-R12 #16 contract): the cells the user has scrolled
  /// into existence PLUS whatever the viewport needs to read as one
  /// continuous sheet — never a runway beyond that. The scrollbar and
  /// scroll physics clamp here; only the ruler edge-drag overshoots (and
  /// the growth listener then materializes what the view needs).
  int get _renderedFrameCount => math.max(
    _visibleFrameCount + _endlessTrailingFrames,
    _viewportFillFrameCells,
  );

  double _effectiveHorizontalScrollOffset({
    required double requestedOffset,
    required double viewportWidth,
  }) {
    final totalFrameContentWidth =
        _renderedFrameCount * _metrics.frameCellWidth;

    return resolveTimelineHorizontalOffset(
      requestedOffset: requestedOffset,
      totalContentWidth: totalFrameContentWidth,
      viewportWidth: viewportWidth,
    ).effectiveOffset;
  }

  void _synchronizeHorizontalScrollController(double effectiveOffset) {
    if (!_horizontalScrollController.hasClients ||
        _horizontalScrollController.offset == effectiveOffset ||
        _scheduledHorizontalOffsetCorrection == effectiveOffset) {
      return;
    }

    _scheduledHorizontalOffsetCorrection = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_horizontalScrollController.hasClients) {
        _scheduledHorizontalOffsetCorrection = null;
        return;
      }

      final maxScrollExtent =
          _horizontalScrollController.position.maxScrollExtent;
      final targetOffset = effectiveOffset
          .clamp(0.0, maxScrollExtent)
          .toDouble();

      _scheduledHorizontalOffsetCorrection = null;
      if (_horizontalScrollController.offset != targetOffset) {
        _horizontalScrollController.jumpTo(targetOffset);
      }
    });
  }

  /// The vertical mirror of the horizontal clamp machinery (UI-R9 #9):
  /// collapsing transform lanes SHRINKS the row content, but the scroll
  /// controller's pixels don't move on their own — windowing from the
  /// stale, now-out-of-range offset inflated the leading spacer and pushed
  /// every section downward (top alignment broke).
  double _effectiveVerticalScrollOffset({
    required double requestedOffset,
    required double viewportHeight,
    required double contentHeight,
  }) {
    final maxOffset = math.max(0.0, contentHeight - viewportHeight);
    return requestedOffset.clamp(0.0, maxOffset).toDouble();
  }

  void _synchronizeVerticalScrollController(double effectiveOffset) {
    if (!_verticalScrollController.hasClients ||
        _verticalScrollController.offset == effectiveOffset ||
        _scheduledVerticalOffsetCorrection == effectiveOffset) {
      return;
    }

    _scheduledVerticalOffsetCorrection = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalScrollController.hasClients) {
        _scheduledVerticalOffsetCorrection = null;
        return;
      }

      final maxScrollExtent =
          _verticalScrollController.position.maxScrollExtent;
      final targetOffset = effectiveOffset
          .clamp(0.0, maxScrollExtent)
          .toDouble();

      _scheduledVerticalOffsetCorrection = null;
      if (_verticalScrollController.offset != targetOffset) {
        _verticalScrollController.jumpTo(targetOffset);
      }
    });
  }

  int? _frameIndexForRulerLocalX(double localX) {
    return frameIndexFromLocalX(
      localX: localX,
      horizontalScrollOffset: _lastEffectiveHorizontalScrollOffset,
      frameCellWidth: _metrics.frameCellWidth,
      visibleFrameCount: _renderedFrameCount,
    );
  }

  void _selectClampedFrameFromRuler(int frameIndex) {
    // The endless runway IS the selectable tail now (UI-R10 #23 retired
    // the fixed safety frames): clamp against the BUILT extent.
    final clampedFrameIndex = clampFrameIndex(
      frameIndex: frameIndex,
      visibleFrameCount: _renderedFrameCount,
    );
    if (clampedFrameIndex == null ||
        clampedFrameIndex == _lastRulerScrubbedFrameIndex) {
      return;
    }

    _lastRulerScrubbedFrameIndex = clampedFrameIndex;
    (widget.onScrubFrame ?? widget.onSelectFrame)(clampedFrameIndex);
  }

  /// The scrub gesture's release (raw pointer up/cancel — fires for taps
  /// AND drags, wherever the pointer ends up). Tracking is NOT reset here
  /// so the ruler InkWell's trailing onTap stays deduplicated.
  void _endRulerScrub() {
    widget.onScrubEnd?.call();
  }

  double? _rulerViewportLocalXFromGlobal(Offset globalPosition) {
    final renderObject = _rulerScrubViewportKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }

    return renderObject.globalToLocal(globalPosition).dx;
  }

  void _selectFrameFromRulerGlobalPosition(Offset globalPosition) {
    final localX = _rulerViewportLocalXFromGlobal(globalPosition);
    if (localX == null) {
      return;
    }
    _autoPanRulerEdge(localX);

    final frameIndex = _frameIndexForRulerLocalX(localX);
    if (frameIndex == null) {
      return;
    }

    _selectClampedFrameFromRuler(frameIndex);
  }

  /// Edge auto-pan (UI-R10 #24, the pro-standard ruler drag): a scrub
  /// pointer past the viewport edge scrolls the frame axis under it.
  /// Rightward it deliberately OVERSHOOTS the built extent (UI-R12 #16):
  /// the ruler drag is THE way past the last built cell — the growth
  /// listener materializes the frames the overshot view needs, while the
  /// scrollbar and scroll physics stay clamped at the built cells.
  void _autoPanRulerEdge(double localX) {
    if (!_horizontalScrollController.hasClients) {
      return;
    }
    final viewport = _rulerScrubViewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return;
    }
    final delta = edgeAutoPanDelta(localX, viewport.size.width);
    if (delta == 0) {
      return;
    }
    final position = _horizontalScrollController.position;
    final target = math.max(0.0, position.pixels + delta);
    if (target != position.pixels) {
      _horizontalScrollController.jumpTo(target);
    }
  }

  void _resetRulerScrubTracking() {
    _lastRulerScrubbedFrameIndex = null;
  }

  /// Brings the SELECTION back into view on both axes (R5, user
  /// 2026-08-09): the frame under the cursor along the frame axis, the row
  /// it stands on along the rail.
  ///
  /// Answered here rather than sent here, because "where is the selection"
  /// is a question about THIS surface's geometry — the sheet asks it of the
  /// other axis and the storyboard of a global one, off the same tick.
  ///
  /// One row/cell of margin, so a walk keeps a neighbour in sight and reads
  /// as a walk rather than as a jump to the edge.
  void _revealSelection() {
    final cell = _metrics.frameCellWidth;
    if (_horizontalScrollController.hasClients && cell > 0) {
      final position = _horizontalScrollController.position;
      final target = revealScrollOffset(
        offset: position.pixels,
        viewport: position.viewportDimension,
        start: widget.frameCursor.value * cell,
        extent: cell,
        margin: cell,
      ).clamp(position.minScrollExtent, position.maxScrollExtent);
      if (target != position.pixels) {
        _horizontalScrollController.jumpTo(target);
      }
    }
    final rowHeight = _metrics.layerRowHeight;
    final rowIndex = _selectedRowIndex();
    if (!_verticalScrollController.hasClients ||
        rowIndex == null ||
        rowHeight <= 0) {
      return;
    }
    final position = _verticalScrollController.position;
    final target = revealScrollOffset(
      offset: position.pixels,
      viewport: position.viewportDimension,
      start: rowIndex * rowHeight,
      extent: rowHeight,
      margin: rowHeight,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      _verticalScrollController.jumpTo(target);
    }
  }

  /// Which DISPLAY row the selection sits on — the row the current-row
  /// address names, and the active layer's row when it names none.
  int? _selectedRowIndex() {
    final rows = _dragRows;
    if (rows.isEmpty) {
      return null;
    }
    final current = widget.currentRowHooks?.currentRow.value;
    if (current is LaneRowAddress) {
      final at = rows.indexWhere(
        (row) => row.layer.id == current.layerId &&
            row.lane?.laneId == current.laneId,
      );
      if (at >= 0) {
        return at;
      }
    }
    final activeId = widget.activeLayerId;
    if (activeId == null) {
      return null;
    }
    final at = rows.indexWhere(
      (row) => !row.isLane && row.layer.id == activeId,
    );
    return at < 0 ? null : at;
  }

  List<PropertyLaneRow> _lanesFor(Layer layer) =>
      widget.lanesForLayer?.call(layer) ?? const [];

  /// Marks assigned across the current layer list — the mark-solo menu's
  /// "solo color X" list is built from these.
  Set<LayerMark> _marksInUse() => {
    for (final layer in widget.layers)
      if (layer.mark != LayerMark.none) layer.mark,
  };

  /// Kinds present across the current layer list — the kind-solo menu
  /// (R4 #8) is built from these.
  Set<LayerKind> _kindsInUse() => {
    for (final layer in widget.layers) layer.kind,
  };

  /// The rows the rail currently DISPLAYS (layer rows only, camera
  /// excluded) — the master opacity bar's target set (R4 #6).
  Set<LayerId> _displayedLayerIds(List<TimelineDisplayRow> rows) => {
    for (final row in rows)
      if (!row.isLane && layerKindHasPictureOpacity(row.layer.kind))
        row.layer.id,
  };

  /// Whether every SE row is muted — the legend mute cell's toggle state
  /// (no SE rows reads as unmuted, so the first tap mutes).
  bool _allSeMuted() {
    var sawSe = false;
    for (final layer in widget.layers) {
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

  /// Legend LAYER-cell sweeps: the grid owns the lane knowledge (which
  /// layers HAVE lanes, which are expanded), so the all-lane fold rides its
  /// existing per-layer toggle.
  void _expandAllLanes() {
    final onToggle = widget.onToggleLayerLanes;
    if (onToggle == null) {
      return;
    }
    for (final layer in widget.layers) {
      if (_lanesFor(layer).isNotEmpty &&
          !widget.expandedLaneLayerIds.contains(layer.id)) {
        onToggle(layer.id);
      }
    }
  }

  void _collapseAllLanes() {
    final onToggle = widget.onToggleLayerLanes;
    if (onToggle == null) {
      return;
    }
    for (final layerId in widget.expandedLaneLayerIds.toList()) {
      onToggle(layerId);
    }
  }

  /// The memo gate for [_railRow] (UI-R7 #1): a controls row whose inputs
  /// match hands back the CACHED widget instance — a zoom step (or any
  /// rebuild that didn't touch the row) skips its whole Material subtree.
  /// Lane label rows stay unmemoized: they subscribe to the frame cursor
  /// themselves and their lane models churn identity per build.
  /// R28 #11: ONE selection — and now there is only one THING that can be
  /// selected. A folder is a layer, so `activeLayerId` answers for both
  /// and two rows can no longer read as selected at once by construction.
  bool _layerRowIsActive(Layer layer) => layer.id == widget.activeLayerId;

  /// The display rows of the pass in flight — see [_effectHeaderRows].
  List<TimelineDisplayRow> _dragRows = const [];

  Widget _railRowMemoized(TimelineDisplayRow row) {
    if (row.isLane) {
      return _effectDraggable(row, _railRow(row));
    }
    final inputs = (
      layer: row.layer,
      active: _layerRowIsActive(row.layer),
      selected: widget.selectedRows.contains(row.address),
      hasLanes: _lanesFor(row.layer).isNotEmpty,
      lanesExpanded: widget.expandedLaneLayerIds.contains(row.layer.id),
      depth: row.depth,
      hasAttachGroup: row.isFolder || _hasAttachGroup(row.layer),
      attachGroupExpanded: !widget.collapsedAttachBaseIds.contains(
        row.layer.id,
      ),
      fxState: widget.layerFxStateOf?.call(row.layer.id) ?? LayerFxState.on,
      onionSkinEnabled:
          widget.layerOnionSkinEnabledOf?.call(row.layer.id) ?? false,
      isLinked: widget.layerIsLinkedOf?.call(row.layer.id) ?? false,
      // Solo is SESSION state, not a Layer field, so the layer comparison
      // cannot see it: the speaker's accent tint went stale the moment
      // solo moved anywhere but this row. It has always been shown here —
      // R10 R3 only made it settable from every rail, which is what turned
      // a latent staleness into one a user would hit.
      soloed: widget.isLayerSoloed?.call(row.layer.id) ?? false,
      // The arrow reads the STACK (a folder's direction is its position
      // against its base), so the Layer comparison cannot see it change.
      attachArrow: widget.attachArrowPlacementOf?.call(row.layer.id),
      layerRowHeight: _metrics.layerRowHeight,
      layerControlsWidth: _metrics.layerControlsWidth,
      sectionLabelGutterWidth: _metrics.sectionLabelGutterWidth,
      opacityDragPreview: widget.opacityDragPreview,
      blendLanguage: widget.blendLanguage,
    );
    final cached = _railRowMemo[row.layer.id];
    if (cached != null && _railRowInputsMatch(cached.inputs, inputs)) {
      return _draggable(row, cached.row);
    }
    final built = _railRow(row);
    _railRowMemo[row.layer.id] = (inputs: inputs, row: built);
    return _draggable(row, built);
  }

  /// The row, made draggable. The wrapper is built fresh every pass and the
  /// memoized row travels through it untouched — the drag state lives in a
  /// notifier the wrapper subscribes to, so a caret moving does not
  /// invalidate one cached row.
  ///
  /// [TimelineDisplayRow.layerIndex] is the slot: it is this row's place in
  /// the DISPLAY layer list, which is exactly what a caret between layer
  /// rows counts in.
  Widget _draggable(TimelineDisplayRow row, Widget child) {
    final hooks = widget.rowDragHooks;
    return LayerRowDragTarget(
      subject: LayerRowSubject(row.layer.id),
      slotBefore: row.layerIndex,
      rowExtent: _metrics.layerRowHeight,
      axis: Axis.horizontal,
      hooks: hooks,
      isLastRow: row.layerIndex == widget.layers.length - 1,
      onCrossed: hooks == null
          ? (_, _) {}
          : (steps, onRow) {
              // R5 #15: ON a row wins over the gap beside it — that is the
              // whole point of the middle band. The row it names is read
              // from the DISPLAY list, so which way this rail runs stays
              // the surface's business as it already is for slots.
              final slot = slotForSteps(
                row.layerIndex,
                steps,
                widget.layers.length,
              );
              final target = onRow == null ? null : row.layerIndex + onRow;
              if (target != null &&
                  target >= 0 &&
                  target < widget.layers.length) {
                hooks.onRowTarget(
                  widget.layers,
                  slot,
                  widget.layers[target].id,
                );
                return;
              }
              hooks.onUpdate(widget.layers, slot);
            },
      // ⑨: the SELECT half of the same drag. It counts in the rail's own
      // DISPLAY rows (`_dragRows`) rather than in the layer list the caret
      // uses — the span must be able to stop on a lane row, which the layer
      // list does not contain.
      onSelectCrossed: hooks?.onSelectBegin == null
          ? null
          : (rowDelta) => widget.onRowSelectionSpan?.call(_dragRows, rowDelta),
      child: child,
    );
  }

  /// An fx header, made draggable: grabbing it re-orders the layer's effect
  /// CHAIN. The Transform group header is never wrapped — it is not a chain
  /// member, it is where the chain ends.
  Widget _effectDraggable(TimelineDisplayRow row, Widget child) {
    final hooks = widget.rowDragHooks;
    final lane = row.lane;
    if (hooks == null || lane == null || !lane.isGroupHeader) {
      return child;
    }
    final parsed = parseEffectLaneId(lane.laneId);
    if (parsed == null || parsed.parameterId != null) {
      return child;
    }
    final headers = effectHeaderRowsOf(_dragRows, row.layer.id);
    final slot = headers.indexWhere((h) => h.effectId == parsed.effectId);
    if (slot < 0) {
      return child;
    }
    final displayEffects = [for (final header in headers) header.effectId];
    final myRowIndex = headers[slot].rowIndex;
    return LayerRowDragTarget(
      subject: EffectRowSubject(row.layer.id, parsed.effectId),
      slotBefore: slot,
      rowExtent: _metrics.layerRowHeight,
      axis: Axis.horizontal,
      hooks: hooks,
      isLastRow: slot == headers.length - 1,
      // An fx chain has no "inside a row" to drop into — an effect holds
      // nothing — so the on-row band is ignored here and the caret stays
      // the only answer (R5 #15).
      onCrossed: (steps, _) => hooks.onEffectUpdate(
        row.layer.id,
        displayEffects,
        slotForSteps(
          slot,
          effectStepsBetween(headers, myRowIndex, steps),
          headers.length,
        ),
      ),
      child: child,
    );
  }

  bool _railRowInputsMatch(_RailRowMemoInputs a, _RailRowMemoInputs b) {
    // What the row SHOWS gates content, not the Layer's identity: a
    // timesheet edit rebuilds the edited layer's instance while every
    // rail-visible field stays put (see the completeness contract on
    // [timelineLayerControlsRowShowsSameState]).
    return timelineLayerControlsRowShowsSameState(a.layer, b.layer) &&
        a.active == b.active &&
        a.selected == b.selected &&
        a.hasLanes == b.hasLanes &&
        a.lanesExpanded == b.lanesExpanded &&
        a.depth == b.depth &&
        a.hasAttachGroup == b.hasAttachGroup &&
        a.attachGroupExpanded == b.attachGroupExpanded &&
        a.fxState == b.fxState &&
        a.onionSkinEnabled == b.onionSkinEnabled &&
        a.isLinked == b.isLinked &&
        a.soloed == b.soloed &&
        a.attachArrow == b.attachArrow &&
        a.layerRowHeight == b.layerRowHeight &&
        a.layerControlsWidth == b.layerControlsWidth &&
        a.sectionLabelGutterWidth == b.sectionLabelGutterWidth &&
        identical(a.opacityDragPreview, b.opacityDragPreview) &&
        a.blendLanguage == b.blendLanguage;
  }

  /// The legend header's memo gate (UI-R7 #1): rebuilt only when a
  /// legend-visible fact changes — zoom steps and unrelated session
  /// notifies reuse the instance, skipping its ~15 tooltip/flyout cells.
  Widget _legendHeaderMemoized(List<TimelineDisplayRow> rows) {
    final displayedIds = _displayedLayerIds(rows);
    final inputs = (
      layerRowHeight: _metrics.layerRowHeight,
      layerControlsWidth: _metrics.layerControlsWidth,
      hasLegend: widget.legend != null,
      hiddenSections: widget.hiddenSections,
      rowFilter: widget.rowFilter,
      marksInUse: _marksInUse(),
      kindsInUse: _kindsInUse(),
      visibilitySoloEnabled: widget.visibilitySoloEnabled,
      anyLanesExpanded: widget.expandedLaneLayerIds.isNotEmpty,
      allSeMuted: _allSeMuted(),
      displayedIds: displayedIds,
      masterOpacityValue: widget.masterOpacityValue,
      hasLaneToggles: widget.onToggleLayerLanes != null,
      displayedOnionSkinOn: widget.displayedOnionSkinOn,
      blendLanguage: widget.blendLanguage,
      hasBlendBulk: widget.legend?.onSetBlendModeForDisplayed != null,
    );
    final cached = _legendHeaderMemo;
    if (cached != null && _legendInputsMatch(cached.inputs, inputs)) {
      return cached.header;
    }
    final header = TimelineLayerControlsHeader(
      metrics: _metrics,
      legend: widget.legend,
      hiddenSections: widget.hiddenSections,
      onToggleSection: widget.onToggleSection,
      rowFilter: widget.rowFilter,
      marksInUse: inputs.marksInUse,
      kindsInUse: inputs.kindsInUse,
      visibilitySoloEnabled: widget.visibilitySoloEnabled,
      anyLanesExpanded: inputs.anyLanesExpanded,
      allSeMuted: inputs.allSeMuted,
      // The fresh set is captured here — the token's setEquals invalidates
      // the cached header whenever the displayed rows change.
      displayedLayerIds: () => displayedIds,
      displayedOpacity: widget.masterOpacityValue,
      displayedOnionSkinOn: widget.displayedOnionSkinOn,
      onExpandAllLanes: widget.onToggleLayerLanes == null
          ? null
          : _expandAllLanes,
      onCollapseAllLanes: widget.onToggleLayerLanes == null
          ? null
          : _collapseAllLanes,
      blendLanguage: widget.blendLanguage,
    );
    _legendHeaderMemo = (inputs: inputs, header: header);
    return header;
  }

  bool _legendInputsMatch(_LegendMemoInputs a, _LegendMemoInputs b) {
    return a.layerRowHeight == b.layerRowHeight &&
        a.layerControlsWidth == b.layerControlsWidth &&
        a.hasLegend == b.hasLegend &&
        setEquals(a.hiddenSections, b.hiddenSections) &&
        a.rowFilter == b.rowFilter &&
        setEquals(a.marksInUse, b.marksInUse) &&
        setEquals(a.kindsInUse, b.kindsInUse) &&
        a.visibilitySoloEnabled == b.visibilitySoloEnabled &&
        a.anyLanesExpanded == b.anyLanesExpanded &&
        a.allSeMuted == b.allSeMuted &&
        setEquals(a.displayedIds, b.displayedIds) &&
        a.masterOpacityValue == b.masterOpacityValue &&
        a.hasLaneToggles == b.hasLaneToggles &&
        a.displayedOnionSkinOn == b.displayedOnionSkinOn &&
        a.blendLanguage == b.blendLanguage &&
        a.hasBlendBulk == b.hasBlendBulk;
  }

  /// One rail row (layer controls or a lane label), extracted so the
  /// windowed rail loop stays readable. Rows reserve an empty leading
  /// section slot — the section ZONES overlay whole runs (UI-R7 #2).
  Widget _railRow(TimelineDisplayRow row) {
    if (row.isLane) {
      // Lane labels show the value AT the cursor: subscribe here so a
      // tick rebuilds only these small cells.
      //
      // R10: and through the drag gate, so the blue value column follows a
      // key move per step. The band moved live while the number beside it
      // still read the committed track — the label is where you WATCH the
      // value, so it is the half that most needed to be live.
      return ValueListenableBuilder<int>(
        valueListenable: widget.frameCursor,
        builder: (context, cursorFrame, _) => TimelineDragPreviewRowGate(
          dragPreview: widget.dragPreview,
          layer: row.layer,
          rowBuilder: (context, layer) => TimelineLaneControlsRow(
            layer: layer,
            lane: previewedLaneRow(
              row: row,
              previewLayer: layer,
              lanesForLayer: _lanesFor,
            ),
            metrics: _metrics,
            currentFrameIndex: cursorFrame,
            onSelectFrame: widget.onSelectFrame,
            laneEdit: widget.laneEdit,
            onToggleLaneGroup: widget.onToggleLaneGroup,
            onToggleLaneGroupEnabled: widget.onToggleLaneGroupEnabled,
            onResetLaneGroup: widget.onResetLaneGroup,
            currentRowHooks: widget.currentRowHooks,
            leadingInset: layerSectionLabelSlotWidth,
            // The SAME flags the layer row below passes, so a group
            // header's fx lands in the layer rows' fx column (R5 #7).
            hasOnionColumn: widget.onToggleLayerOnionSkin != null,
            hasBlendColumn: widget.onLayerBlendModeSelected != null,
          ),
        ),
      );
    }
    return TimelineLayerControlsRow(
      layer: row.layer,
      wearsBaseComposite: attachRowWearsBaseComposite(row.layer, widget.layers),
      active: _layerRowIsActive(row.layer),
      // ⑨: in the row selection the row verbs act on.
      selected: widget.selectedRows.contains(row.address),
      metrics: _metrics,
      onSelectLayer: widget.onSelectLayer,
      // T10: the rail row and the frame cells take the SAME settled-tap
      // clear, because 「행이든 뭐든 동일하게」.
      onSettledPress: widget.onSettledPress,
      onToggleLayerVisibility: widget.onToggleLayerVisibility,
      onLayerOpacityChanged: widget.onLayerOpacityChanged,
      onLayerOpacityChangeEnd: widget.onLayerOpacityChangeEnd,
      onToggleLayerTimesheet: widget.onToggleLayerTimesheet,
      fxState: widget.layerFxStateOf?.call(row.layer.id) ?? LayerFxState.on,
      onToggleLayerFx: widget.onToggleLayerFx,
      onionSkinEnabled:
          widget.layerOnionSkinEnabledOf?.call(row.layer.id) ?? false,
      onToggleLayerOnionSkin: widget.onToggleLayerOnionSkin,
      onLayerMarkSelected: widget.onLayerMarkSelected,
      onToggleLayerFillReference: widget.onToggleLayerFillReference,
      onOpenLayerMixer: widget.onOpenLayerMixer,
      isLayerSoloed: widget.isLayerSoloed?.call(row.layer.id) ?? false,
      attachArrowPlacement: widget.attachArrowPlacementOf?.call(row.layer.id),
      hasLanes: _lanesFor(row.layer).isNotEmpty,
      lanesExpanded: widget.expandedLaneLayerIds.contains(row.layer.id),
      onToggleLanes: widget.onToggleLayerLanes,
      depth: row.depth,
      // One fold twirl: a folder folds its members, an attach base folds
      // its attach rows.
      hasGroupFold: row.isFolder || _hasAttachGroup(row.layer),
      groupFoldExpanded: row.isFolder
          ? !row.layer.collapsed
          : !widget.collapsedAttachBaseIds.contains(row.layer.id),
      onToggleGroupFold: row.isFolder
          ? widget.onToggleLayerCollapsed
          : widget.onToggleAttachGroup,
      opacityDragPreview: widget.opacityDragPreview,
      isLinked: widget.layerIsLinkedOf?.call(row.layer.id) ?? false,
      onLayerBlendModeSelected: widget.onLayerBlendModeSelected,
      blendLanguage: widget.blendLanguage,
      opacityOverride: widget.layerOpacityOverrideOf?.call(row.layer.id),
    );
  }

  /// Whether [layer] carries attach rows — the base-row twirl shows only
  /// then (UI-R20 #9).
  bool _hasAttachGroup(Layer layer) =>
      widget.layers.any((other) => other.attachedToLayerId == layer.id);

  /// The section ZONES over the rail rows' reserved band slots (UI-R7 #2):
  /// one tinted zone per section run — the pre-R5 gutter bracket inside
  /// the rows (upright label centered across the run, tap = section
  /// flyout).
  ///
  /// Fed the FULL display-row list, never the window (A3 2026-08-17): a
  /// zone spans its section's first-to-last row in content coordinates, so
  /// the label sits at the section's true middle and scrolls away with the
  /// content instead of chasing the viewport, and a section scrolled out of
  /// view keeps its bracket mounted (reserve space, swap content). The
  /// x-sheet (full `entries`) and the storyboard (full group Column)
  /// already anchor their bands this way — the three surfaces share the
  /// same run functions on full lists now. Runs tile contiguously from row
  /// zero ([timelineSectionRuns] assigns every row a section), so the
  /// Column needs no leading spacer.
  Widget _sectionBandOverlay(List<TimelineDisplayRow> rows) {
    final runs = timelineSectionRuns(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final run in runs)
          KeyedSubtree(
            key: ValueKey<String>('section-bracket-${run.section.name}'),
            child: SectionBandZone(
              label: timelineSectionLabel(run.section),
              extent: timelineSectionRunExtent(run, rows, _metrics),
            ),
          ),
      ],
    );
  }

  /// Resolves range-move row deltas against the rows built this pass.
  final TimelineRangeMoveRowResolver _rangeMoveResolver =
      TimelineRangeMoveRowResolver();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const bottomScrollbarRailHeight = timelineBottomScrollbarRailHeight;
    final rows = buildTimelineDisplayRows(
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
    );
    // The row drag counts ROWS and lands on SLOTS, and only this list knows
    // how many rows sit between two fx headers (their members may be
    // twirled open). Held for the wrappers built below in the same pass.
    _dragRows = rows;
    final rangeHooks = widget.rangeHooks;
    _rangeMoveResolver
      ..rows = rows
      ..session = rangeHooks?.move;
    final rangeGesture = rangeHooks == null
        ? null
        : TimelineRangeGestureCallbacks(
            // Every row this grid mounts is a LAYER row, so the address
            // resolves back to a layer id at this one seam.
            isInSelection: (row, frameIndex) {
              final selection = rangeHooks.selection.value;
              return row is LayerRowAddress &&
                  selection != null &&
                  selection.coversLayer(row.layerId) &&
                  selection.contains(frameIndex);
            },
            // Cross-row select (UI-R17 #8): the gesture's row delta maps
            // onto the display rows exactly like the move drags do.
            //
            // 🚨Resolved against the STATE-HELD [_dragRows] at CALL time,
            // never the build-local list. The cells rows are MEMOIZED: a
            // memo hit hands back the widget of an older build, and that
            // widget's gesture bundle carries THESE closures. Capturing
            // `rows` froze the row list as of the build the row was cached
            // in — twirl a lane group open and a memo-kept row's drag still
            // swept yesterday's three rows (the engine shards caught it
            // first: their tile inputs keep the memo warm). The MOVE path
            // never had the bug because [_rangeMoveResolver] is exactly
            // this pattern — one State-held object, refreshed per build.
            onSelectUpdate: (row, anchorIndex, headIndex, headCrossOffset) {
              // ⛔No kind gate on the anchor. WHICH rows a drag may sweep is
              // answered by the row LIST below and by nothing else — a test
              // here is how the transition clone and the lane rows came to
              // be unanchorable one kind at a time (유저 2026-08-12: 「헤더니까
              // 뭐 다르게한다거나 제발좀 절대로좀 그만좀하자」).
              final layerId = switch (row) {
                LayerRowAddress(:final layerId) => layerId,
                LaneRowAddress(:final layerId) => layerId,
                TrackRowAddress() => null,
              };
              if (layerId == null) {
                return;
              }
              // R9 #25: the gesture hands up raw pixels; this surface's
              // rows are one height (layer rows and lane rows alike), so
              // the resolve is the uniform one — the same arithmetic as
              // before, now stated where the heights are known.
              final headRowDelta = uniformRowDeltaForCrossOffset(
                crossOffset: headCrossOffset,
                rowExtent: _metrics.layerRowHeight,
              );
              // R27 #14: the head row may be a LANE row of the dragged
              // layer — the span then runs cell → lane → lane and stops
              // where the pointer is, instead of stepping over the whole
              // lane group to the next layer's cells.
              final head = headRowDelta == 0
                  ? null
                  : resolveSelectionSpanHead(
                      rows: _dragRows,
                      sourceLayerId: layerId,
                      rowDelta: headRowDelta,
                    );
              rangeHooks.onSelectUpdate(
                layerId,
                anchorIndex,
                headIndex,
                headLayerId: head?.layerId,
                headLaneId: head?.laneId,
                // 🚨★ THE SPAN, sliced off what this grid actually drew.
                spanRows: resolveSelectionSpanRows(
                  rows: _dragRows,
                  anchor: row,
                  rowDelta: headRowDelta,
                ),
              );
            },
            onTapClear: (_) => rangeHooks.onClear(),
            onMoveBegin: (row, _) =>
                row is LayerRowAddress && _rangeMoveResolver.begin(row.layerId),
            onMoveUpdate: _rangeMoveResolver.update,
            onMoveEnd: _rangeMoveResolver.end,
            onMoveCancel: _rangeMoveResolver.cancel,
          );

    // 🚨B4-④: a lane-anchored select drag that leaves its own lane group
    // JOINS the cells law above — same display-row slice, same hooks, same
    // arguments a cells anchor would report (유저: 「선택범위는 어떤
    // 레이어를 건너든 자유롭게, 규칙 두지 말 것」). Inside the group the
    // host's lane-span path keeps the drag, unchanged.
    final hostLaneRange = widget.laneRange;
    final laneRange = hostLaneRange == null
        ? null
        : TimelineLaneRangeCallbacks(
            selection: hostLaneRange.selection,
            onSelectUpdate:
                (layerId, laneId, anchorIndex, headIndex, headRowDelta) {
                  // [_dragRows], not the build-local list — the same
                  // stale-closure rule as the cells handler above (lane
                  // rows are not memoized today, but the bundle they mount
                  // must not depend on that staying true).
                  final escalation = rangeHooks == null
                      ? null
                      : resolveLaneSpanEscalation(
                          rows: _dragRows,
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

    // PEN-9: a stylus approach stops a coasting fling — mid-glide the
    // viewports ignore-pointer their children, so without the stop a pen
    // landing right after a touch fling scrolls instead of selecting.
    return StylusGlideStop(
      controllers: [_horizontalScrollController, _verticalScrollController],
      // PEN-12 #7: no overscroll stretch/glow — the painterized ruler
      // and rails mirror the offset and cannot stretch with the cells,
      // so Android's stretch tore the two apart at the edges. A hard
      // clamp matches the desktop feel everywhere.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.hasBoundedHeight
                ? (constraints.maxHeight - bottomScrollbarRailHeight)
                      .clamp(0.0, double.infinity)
                      .toDouble()
                : 0.0;
            // The splitter's value is read HERE and nowhere deeper. The
            // rail itself keeps being laid out at its natural width, so a
            // drag frame re-lays-out the window box and the frame area and
            // rebuilds not one rail row — which is why the extent is a
            // listenable instead of a metrics field (a metrics field is a
            // memo key, and the frame geometry already paid that price
            // once at ~60% of a step).
            return ValueListenableBuilder<double?>(
              valueListenable: _railExtent,
              builder: (context, _, child) {
                // What the panel can spare for the rail: everything but its
                // own chrome and the frame area's two-cell reserve. This is
                // also what closes the grid's old <448px overflow — the
                // rail used to be a fixed 434 whatever the panel had.
                // Computed ONCE and handed to every part of the rail so
                // they cannot disagree.
                final availableRailExtent = constraints.hasBoundedWidth
                    ? (constraints.maxWidth -
                              _metrics.verticalScrollbarWidth -
                              LayerRailSplitter.thickness -
                              layerRailFrameReserveExtent)
                          .clamp(0.0, double.infinity)
                          .toDouble()
                    : null;
                final railWindowExtent = _railExtent.windowExtent(
                  _naturalRailWidth,
                  availableExtent: availableRailExtent,
                );
                // Viewport paper fill (UI-R12 #16): however wide the cell
                // area is, cells run to its edge — recorded here so every
                // consumer of [_renderedFrameCount] below sees it
                // (build-recorded like the effective offsets).
                _viewportFillFrameCells = endlessViewportFillFrames(
                  viewportExtent: constraints.hasBoundedWidth
                      ? (constraints.maxWidth -
                                _metrics.verticalScrollbarWidth -
                                railWindowExtent -
                                LayerRailSplitter.thickness)
                            .clamp(0.0, double.infinity)
                            .toDouble()
                      : 0.0,
                  frameCellExtent: _metrics.frameCellWidth,
                );

                return KeyedSubtree(
                  key: const ValueKey<String>('timeline-scrollbar-area'),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final headerHeight = _metrics.layerRowHeight;
                                final bodyViewportHeight =
                                    constraints.hasBoundedHeight
                                    ? (constraints.maxHeight - headerHeight)
                                          .clamp(0.0, double.infinity)
                                          .toDouble()
                                    : viewportHeight;
                                // Rows are no longer uniformly tall: collapsed sections
                                // fold to a slim strip.
                                final verticalContentHeight = math.max(
                                  timelineDisplayRowsExtent(rows, _metrics),
                                  _metrics.layerRowHeight,
                                );
                                // Layer-axis window: only the rows in view (plus
                                // overscan) are built; spacers preserve the scroll
                                // geometry of the rest. The cursor and preview
                                // overlays keep the FULL row list — their offsets are
                                // absolute. Without a real viewport measurement
                                // (unbounded hosts) every row builds, like before.
                                // The offset is CLAMPED to the current content before
                                // windowing (UI-R9 #9): lane collapses shrink the rows
                                // under a stale scroll offset, and the raw value would
                                // inflate the leading spacer (sections pushed down).
                                // The clamp is read fresh off the position every build
                                // so it can never outlive the shrink that caused it
                                // (UI-R5 #3 — see [_readVerticalScrollOffset]).
                                _readVerticalScrollOffset();
                                final effectiveVerticalScrollOffset =
                                    _effectiveVerticalScrollOffset(
                                      requestedOffset: _verticalScrollOffset,
                                      viewportHeight: bodyViewportHeight,
                                      contentHeight: verticalContentHeight,
                                    );
                                _synchronizeVerticalScrollController(
                                  effectiveVerticalScrollOffset,
                                );
                                final rowWindow = bodyViewportHeight <= 0
                                    ? TimelineVisibleRange(
                                        startIndex: 0,
                                        endIndexExclusive: rows.length,
                                      )
                                    : calculateVisibleIndexRange(
                                        scrollOffset:
                                            effectiveVerticalScrollOffset,
                                        viewportExtent: bodyViewportHeight,
                                        itemExtent: _metrics.layerRowHeight,
                                        itemCount: rows.length,
                                      );
                                final windowRows = rows.sublist(
                                  rowWindow.startIndex,
                                  rowWindow.endIndexExclusive,
                                );
                                final leadingRowSpacerHeight =
                                    rowWindow.startIndex *
                                    _metrics.layerRowHeight;
                                final trailingRowSpacerHeight =
                                    (rows.length -
                                        rowWindow.endIndexExclusive) *
                                    _metrics.layerRowHeight;

                                return Column(
                                  children: [
                                    KeyedSubtree(
                                      key: const ValueKey<String>(
                                        'timeline-sticky-header-row',
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // The corner above the layer-axis
                                          // scrollbar: the seconds toggle, moved
                                          // off the command bar and onto the axis
                                          // whose labels it rewrites.
                                          TimelineSecondsToggleCorner(
                                            width:
                                                _metrics.verticalScrollbarWidth,
                                            height: headerHeight,
                                            showSeconds: widget.showSeconds,
                                            onChanged:
                                                widget.onShowSecondsChanged,
                                          ),
                                          // The legend rides INSIDE the rail's
                                          // window: it is the rail's own top row,
                                          // not a strip beside it, so one cut and
                                          // one push serve both (the user's rule —
                                          // "the legend and the rows are one body,
                                          // like the ruler and the cells").
                                          LayerRailWindow(
                                            axis: Axis.horizontal,
                                            rail: _railExtent,
                                            naturalExtent: _naturalRailWidth,
                                            availableExtent:
                                                availableRailExtent,
                                            // Memo-gated (UI-R7 #1): zoom steps
                                            // reuse the identical header instance.
                                            child: _legendHeaderMemoized(rows),
                                          ),
                                          const SizedBox(
                                            width: LayerRailSplitter.thickness,
                                          ),
                                          Expanded(
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final viewportWidth =
                                                    constraints.hasBoundedWidth
                                                    ? constraints.maxWidth
                                                    : 0.0;
                                                // R9 #3: the clamp answers ONE
                                                // question — does the controller
                                                // need correcting after a viewport
                                                // resize. What the ruler renders
                                                // and hit-tests at is the scroll
                                                // position itself.
                                                _lastEffectiveHorizontalScrollOffset =
                                                    _frameAxisOffset.value;
                                                _synchronizeHorizontalScrollController(
                                                  _effectiveHorizontalScrollOffset(
                                                    requestedOffset:
                                                        _frameAxisOffset.value,
                                                    viewportWidth:
                                                        viewportWidth,
                                                  ),
                                                );
                                                final totalFrameContentWidth =
                                                    _renderedFrameCount *
                                                    _metrics.frameCellWidth;

                                                // PRO-TIMELINE scrolling (UI-R15):
                                                // the strip builds ONCE at full width
                                                // — its painter windows itself off
                                                // the live offset (repaint-only),
                                                // sub-cell pixels move the TRANSLATE
                                                // alone, and the bucket re-windowing
                                                // is gone. Ticks/warming still
                                                // rebuild just this one host.
                                                // The ruler is SPLIT (the storyboard's
                                                // shape, now shared): a static strip
                                                // that lays out a glyph per labeled
                                                // frame, and a thin overlay carrying
                                                // everything that moves. Keeping the
                                                // cursor tint in the strip meant every
                                                // SEEK re-recorded the whole O(frames)
                                                // glyph pass; and the cached bar reads
                                                // DERIVED state (composites
                                                // self-validate, nothing raises an
                                                // "invalidated" event), so it must be
                                                // cheap to repaint rather than gated.
                                                final rulerContent = SizedBox(
                                                  width: totalFrameContentWidth,
                                                  height: headerHeight,
                                                  child: Stack(
                                                    children: [
                                                      RepaintBoundary(
                                                        child: TimelineFrameRuler(
                                                          frameStartIndex: 0,
                                                          frameEndIndexExclusive:
                                                              _renderedFrameCount,
                                                          // The tint lives in the
                                                          // overlay now.
                                                          currentFrameIndex: -1,
                                                          playbackFrameCount: widget
                                                              .playbackFrameCount,
                                                          drawnFrameCount: widget
                                                              .drawnFrameCount,
                                                          noriShiroLabel: widget
                                                              .noriShiroLabel,
                                                          leadingFrameSpacerWidth:
                                                              0,
                                                          trailingFrameSpacerWidth:
                                                              0,
                                                          metrics: _metrics,
                                                          onSelectFrame:
                                                              _selectClampedFrameFromRuler,
                                                          framesPerSecond:
                                                              _countingFps,
                                                          showSeconds: widget
                                                              .showSeconds,
                                                          windowBucket:
                                                              _frameWindowBucket,
                                                          viewportMainExtent:
                                                              viewportWidth,
                                                          dragPreview: widget
                                                              .dragPreview,
                                                          previewCutId: widget
                                                              .cutEndDrag
                                                              ?.cutId,
                                                        ),
                                                      ),
                                                      Positioned.fill(
                                                        child: TimelineRulerCursorOverlay(
                                                          keyValue:
                                                              'timeline-ruler-cursor-overlay',
                                                          playhead: widget
                                                              .frameCursor,
                                                          repaintSignal: widget
                                                              .frameReadySignal,
                                                          windowBucket:
                                                              _frameWindowBucket,
                                                          viewportMainExtent:
                                                              viewportWidth,
                                                          renderedFrames:
                                                              _renderedFrameCount,
                                                          cellWidth: _metrics
                                                              .frameCellWidth,
                                                          isFrameReady: widget
                                                              .isFrameReady,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );

                                                return Listener(
                                                  key: const ValueKey<String>(
                                                    'timeline-frame-ruler-scrub-area',
                                                  ),
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  onPointerDown: (event) {
                                                    _resetRulerScrubTracking();
                                                    _selectFrameFromRulerGlobalPosition(
                                                      event.position,
                                                    );
                                                  },
                                                  onPointerUp: (_) =>
                                                      _endRulerScrub(),
                                                  onPointerCancel: (_) =>
                                                      _endRulerScrub(),
                                                  child: GestureDetector(
                                                    behavior: HitTestBehavior
                                                        .translucent,
                                                    onHorizontalDragStart:
                                                        (details) {
                                                          _selectFrameFromRulerGlobalPosition(
                                                            details
                                                                .globalPosition,
                                                          );
                                                        },
                                                    onHorizontalDragUpdate:
                                                        (details) {
                                                          _selectFrameFromRulerGlobalPosition(
                                                            details
                                                                .globalPosition,
                                                          );
                                                        },
                                                    onHorizontalDragEnd: (_) =>
                                                        _resetRulerScrubTracking(),
                                                    onHorizontalDragCancel:
                                                        _resetRulerScrubTracking,
                                                    child: SizedBox(
                                                      key:
                                                          _rulerScrubViewportKey,
                                                      width: viewportWidth,
                                                      height: headerHeight,
                                                      child: ClipRect(
                                                        child: OverflowBox(
                                                          alignment:
                                                              Alignment.topLeft,
                                                          minWidth:
                                                              totalFrameContentWidth,
                                                          maxWidth:
                                                              totalFrameContentWidth,
                                                          minHeight:
                                                              headerHeight,
                                                          maxHeight:
                                                              headerHeight,
                                                          // Per-pixel scrolls move the
                                                          // TRANSLATE only; the content
                                                          // is the stable child below.
                                                          child: ValueListenableBuilder<double>(
                                                            valueListenable:
                                                                _frameAxisOffset,
                                                            child: rulerContent,
                                                            // R9 #3: the RAW scroll
                                                            // position, overscroll
                                                            // included. Clamping here
                                                            // pinned the ruler at the
                                                            // end while the body kept
                                                            // sliding — this file's
                                                            // own contract, broken by
                                                            // the clamp meant for a
                                                            // different job (deciding
                                                            // whether the CONTROLLER
                                                            // needs correcting after
                                                            // a viewport resize).
                                                            builder:
                                                                (
                                                                  context,
                                                                  offset,
                                                                  child,
                                                                ) {
                                                                  _lastEffectiveHorizontalScrollOffset =
                                                                      offset;
                                                                  return Transform.translate(
                                                                    offset:
                                                                        Offset(
                                                                          -offset,
                                                                          0,
                                                                        ),
                                                                    child:
                                                                        child,
                                                                  );
                                                                },
                                                          ),
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
                                    ),
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          ScrollConfiguration(
                                            // The pinned rail IS the scrollbar — the
                                            // desktop auto-overlay would double it
                                            // over the cells (UI-R10 #22 unification).
                                            behavior: ScrollConfiguration.of(
                                              context,
                                            ).copyWith(scrollbars: false),
                                            child: SingleChildScrollView(
                                              key: const ValueKey<String>(
                                                'timeline-vertical-scroll-viewport',
                                              ),
                                              controller:
                                                  _verticalScrollController,
                                              child: KeyedSubtree(
                                                key: const ValueKey<String>(
                                                  'timeline-scrollable-body',
                                                ),
                                                child: TimelineLayerFrameBodyLayout(
                                                  layerAxisScrollbarSlot: SizedBox(
                                                    width: _metrics
                                                        .verticalScrollbarWidth,
                                                    height:
                                                        verticalContentHeight,
                                                  ),
                                                  layerControlsRail: LayerRailWindow(
                                                    axis: Axis.horizontal,
                                                    rail: _railExtent,
                                                    naturalExtent:
                                                        _naturalRailWidth,
                                                    availableExtent:
                                                        availableRailExtent,
                                                    child: KeyedSubtree(
                                                      key: const ValueKey<String>(
                                                        'timeline-layer-controls-rail',
                                                      ),
                                                      child: KeyedSubtree(
                                                        key: const ValueKey<String>(
                                                          'timeline-layer-rows-scroll-body',
                                                        ),
                                                        // Sections live INSIDE the rows
                                                        // (UI-R5) as run-spanning ZONES
                                                        // (UI-R7 #2): the rows reserve the
                                                        // leading slot, the zone overlay
                                                        // paints the old gutter bracket
                                                        // over it.
                                                        child: _EyeSwipeDetector(
                                                          band:
                                                              _eyeColumnBand(),
                                                          onStart: (localY) {
                                                            final layer =
                                                                _layerAtRailY(
                                                                  localY,
                                                                  windowRows,
                                                                  leadingRowSpacerHeight,
                                                                );
                                                            if (layer == null) {
                                                              return false;
                                                            }
                                                            _eyeSwipeTargetVisible =
                                                                !layer
                                                                    .isVisible;
                                                            _eyeSwipePainted
                                                                .clear();
                                                            _paintEyeSwipeAt(
                                                              layer,
                                                            );
                                                            return true;
                                                          },
                                                          onUpdate: (localY) =>
                                                              _paintEyeSwipeAt(
                                                                _layerAtRailY(
                                                                  localY,
                                                                  windowRows,
                                                                  leadingRowSpacerHeight,
                                                                ),
                                                              ),
                                                          onEnd: () {
                                                            _eyeSwipeTargetVisible =
                                                                null;
                                                            _eyeSwipePainted
                                                                .clear();
                                                          },
                                                          child: Stack(
                                                            children: [
                                                              Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  // The rail is windowed
                                                                  // with the same
                                                                  // layer-axis slice as the
                                                                  // frame rows; keys keep
                                                                  // row state glued to its
                                                                  // layer through window
                                                                  // shifts.
                                                                  if (leadingRowSpacerHeight >
                                                                      0)
                                                                    SizedBox(
                                                                      height:
                                                                          leadingRowSpacerHeight,
                                                                    ),
                                                                  for (final row
                                                                      in windowRows)
                                                                    KeyedSubtree(
                                                                      key: ValueKey<String>(
                                                                        'timeline-rail-row-'
                                                                        '${row.layer.id}-'
                                                                        '${row.isFolder ? 'folder-${row.layer.id}' : row.lane?.laneId ?? 'row'}',
                                                                      ),
                                                                      child:
                                                                          _railRowMemoized(
                                                                            row,
                                                                          ),
                                                                    ),
                                                                  if (trailingRowSpacerHeight >
                                                                      0)
                                                                    SizedBox(
                                                                      height:
                                                                          trailingRowSpacerHeight,
                                                                    ),
                                                                  if (widget
                                                                      .layers
                                                                      .isEmpty)
                                                                    SizedBox(
                                                                      width:
                                                                          _metrics
                                                                              .layerControlsWidth -
                                                                          _metrics
                                                                              .sectionLabelGutterWidth,
                                                                      height: _metrics
                                                                          .layerRowHeight,
                                                                      child: Padding(
                                                                        padding:
                                                                            const EdgeInsets.all(
                                                                              8,
                                                                            ),
                                                                        child: Text(
                                                                          'No layers',
                                                                          style: TextStyle(
                                                                            color:
                                                                                colorScheme.onSurfaceVariant,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                              // The section ZONES over the
                                                              // rows' reserved band slots
                                                              // (UI-R7 #2): the old gutter
                                                              // bracket inside the rows.
                                                              // Full rows, not the window
                                                              // (A3) — labels anchor to the
                                                              // section's true extent.
                                                              Positioned(
                                                                left: 0,
                                                                top: 0,
                                                                child: _sectionBandOverlay(
                                                                  rows,
                                                                ),
                                                              ),
                                                              // T1's one band
                                                              // per contiguous
                                                              // run — but only
                                                              // over the LAYER
                                                              // area (A2
                                                              // 2026-08-17
                                                              // reversed T1's
                                                              // full-width
                                                              // call): the
                                                              // section zone
                                                              // is the
                                                              // sections' own
                                                              // plate, not
                                                              // part of the
                                                              // selection.
                                                              Positioned(
                                                                left: layerSectionLabelSlotWidth,
                                                                top: 0,
                                                                right: 0,
                                                                bottom: 0,
                                                                child: TimelineRowSelectionBands(
                                                                  selectedFlags: [
                                                                    for (final row in windowRows)
                                                                      widget.selectedRows.contains(row.address),
                                                                  ],
                                                                  rowExtent: _metrics.layerRowHeight,
                                                                  leadingSpacer: leadingRowSpacerHeight,
                                                                  crossExtent: _metrics.layerControlsWidth -
                                                                      layerSectionLabelSlotWidth,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  railSplitterSlot:
                                                      const SizedBox(
                                                        width: LayerRailSplitter
                                                            .thickness,
                                                      ),
                                                  frameGridArea: Expanded(
                                                    child: KeyedSubtree(
                                                      key: const ValueKey<String>(
                                                        'timeline-frame-grid-area',
                                                      ),
                                                      child: LayoutBuilder(
                                                        builder: (context, constraints) {
                                                          final viewportWidth =
                                                              constraints
                                                                  .hasBoundedWidth
                                                              ? constraints
                                                                    .maxWidth
                                                              : 0.0;
                                                          _lastEffectiveHorizontalScrollOffset =
                                                              _frameAxisOffset
                                                                  .value;
                                                          _synchronizeHorizontalScrollController(
                                                            _effectiveHorizontalScrollOffset(
                                                              requestedOffset:
                                                                  _frameAxisOffset
                                                                      .value,
                                                              viewportWidth:
                                                                  viewportWidth,
                                                            ),
                                                          );

                                                          // PRO-TIMELINE scrolling
                                                          // (UI-R15): the body builds
                                                          // ONCE for the full frame
                                                          // bounds — the drawing rows'
                                                          // painters window themselves
                                                          // off the live offset
                                                          // (repaint-only), sparse
                                                          // rows re-window internally
                                                          // under the bucket, and the
                                                          // overlays position
                                                          // content-absolutely. A
                                                          // scroll rebuilds NOTHING
                                                          // here.
                                                          final totalFrameContentWidth =
                                                              _renderedFrameCount *
                                                              _metrics
                                                                  .frameCellWidth;
                                                          return TimelineFrameScrollViewport(
                                                            controller:
                                                                _horizontalScrollController,
                                                            contentWidth:
                                                                totalFrameContentWidth,
                                                            contentHeight:
                                                                verticalContentHeight,
                                                            child: TimelineFrameGridStack(
                                                              rowsBody: TimelineFrameRowsScrollBody(
                                                                rows:
                                                                    windowRows,
                                                                leadingLayerSpacerHeight:
                                                                    leadingRowSpacerHeight,
                                                                trailingLayerSpacerHeight:
                                                                    trailingRowSpacerHeight,
                                                                dragPreview: widget
                                                                    .dragPreview,
                                                                activeLayerId:
                                                                    widget
                                                                        .activeLayerId,
                                                                playbackFrameCount:
                                                                    widget
                                                                        .playbackFrameCount,
                                                                frameStartIndex:
                                                                    0,
                                                                frameEndIndexExclusive:
                                                                    _renderedFrameCount,
                                                                leadingFrameSpacerWidth:
                                                                    0,
                                                                trailingFrameSpacerWidth:
                                                                    0,
                                                                totalFrameContentWidth:
                                                                    totalFrameContentWidth,
                                                                windowBucket:
                                                                    _frameWindowBucket,
                                                                viewportMainExtent:
                                                                    viewportWidth,
                                                                metrics:
                                                                    _metrics,
                                                                exposureStateForLayer:
                                                                    widget
                                                                        .exposureStateForLayer,
                                                                frameNameForLayer:
                                                                    widget
                                                                        .frameNameForLayer,
                                                                celContent: widget
                                                                    .celContent,
                                                                onSelectLayer:
                                                                    widget
                                                                        .onSelectLayer,
                                                                onSelectFrame:
                                                                    widget
                                                                        .onSelectFrame,
                                                                onSettledPress:
                                                                    widget
                                                                        .onSettledPress,
                                                                onActivateCell:
                                                                    widget
                                                                        .onActivateCell,
                                                                instructionDefById:
                                                                    widget
                                                                        .instructionDefById,
                                                                audioPeaksFor:
                                                                    widget
                                                                        .audioPeaksFor,
                                                                seClipMarkerTooltip:
                                                                    widget
                                                                        .seClipMarkerTooltip,
                                                                projectFrameRate:
                                                                    widget
                                                                        .projectFrameRate,
                                                                audioLane: widget
                                                                    .audioLane,
                                                                onDropMediaAssetOnLayer:
                                                                    widget
                                                                        .onDropMediaAssetOnLayer,
                                                                showSeconds: widget
                                                                    .showSeconds,
                                                                commaDrag: widget
                                                                    .commaDrag,
                                                                rangeGesture:
                                                                    rangeGesture,
                                                                laneRange:
                                                                    laneRange,
                                                                lanesForLayer:
                                                                    _lanesFor,
                                                                unionLaneForLayer:
                                                                    widget
                                                                        .unionLaneForLayer,
                                                                runEdit: widget
                                                                    .runEdit,
                                                                laneEdit: widget
                                                                    .laneEdit,
                                                                seSpillInLayerIds:
                                                                    widget
                                                                        .seSpillInLayerIds,
                                                                memoAux: widget
                                                                    .memoAux,
                                                                substrateGeneration:
                                                                    widget
                                                                        .substrateGeneration,
                                                              ),
                                                              // UI-R13 #7: the
                                                              // beat lines span
                                                              // EVERY row now, one
                                                              // grid-wide overlay.
                                                              beatLines: RepaintBoundary(
                                                                child: CustomPaint(
                                                                  key:
                                                                      const ValueKey<
                                                                        String
                                                                      >(
                                                                        'timeline-beat-lines',
                                                                      ),
                                                                  painter: TimelineBeatLinesPainter(
                                                                    frameCellExtent:
                                                                        _metrics
                                                                            .frameCellWidth,
                                                                    framesPerSecond:
                                                                        _countingFps,
                                                                    colorScheme:
                                                                        colorScheme,
                                                                    crossCellExtent:
                                                                        _metrics
                                                                            .layerRowHeight,
                                                                  ),
                                                                ),
                                                              ),
                                                              cutEndBoundaryLeft:
                                                                  timelineCutEndBoundaryX(
                                                                    playbackFrameCount:
                                                                        widget
                                                                            .playbackFrameCount,
                                                                    metrics:
                                                                        _metrics,
                                                                  ),
                                                              // UI-R18 #14: the end
                                                              // line grows a trim
                                                              // grip and follows the
                                                              // live preview.
                                                              cutEndDrag: widget
                                                                  .cutEndDrag,
                                                              dragPreview: widget
                                                                  .dragPreview,
                                                              frameCellExtent:
                                                                  _metrics
                                                                      .frameCellWidth,
                                                              playbackFrameCount:
                                                                  widget
                                                                      .playbackFrameCount,
                                                              // のりしろ: the blue
                                                              // line runs through
                                                              // the body too, and
                                                              // the wash starts
                                                              // behind it.
                                                              drawnFrameCount:
                                                                  widget
                                                                      .drawnFrameCount,
                                                              // The cursor layer decides
                                                              // per frame what to show —
                                                              // the slot itself is static
                                                              // so ticks rebuild nothing
                                                              // here.
                                                              showPlayhead:
                                                                  true,
                                                              playheadWidth:
                                                                  totalFrameContentWidth,
                                                              playhead: TimelineCursorLayer(
                                                                currentRow: widget
                                                                    .currentRowHooks
                                                                    ?.currentRow,
                                                                frameCursor: widget
                                                                    .frameCursor,
                                                                dragPreview: widget
                                                                    .dragPreview,
                                                                frameRangeSelection:
                                                                    rangeHooks
                                                                        ?.selection,
                                                                // R27 #14: the lane
                                                                // span draws the SAME
                                                                // band here.
                                                                laneRangeSelection:
                                                                    widget
                                                                        .laneRange
                                                                        ?.selection,
                                                                rows: rows,
                                                                activeLayerId:
                                                                    widget
                                                                        .activeLayerId,
                                                                frameStartIndex:
                                                                    0,
                                                                frameEndIndexExclusive:
                                                                    _renderedFrameCount,
                                                                leadingFrameSpacerWidth:
                                                                    0,
                                                                metrics:
                                                                    _metrics,
                                                                exposureStateForLayer:
                                                                    widget
                                                                        .exposureStateForLayer,
                                                                crossAxisExtent:
                                                                    verticalContentHeight,
                                                                windowBucket:
                                                                    _frameWindowBucket,
                                                                viewportMainExtent:
                                                                    viewportWidth,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          // The layer-axis bar sat between the rail
                                          // and the cells, and its opaque hit lane
                                          // owned the only gap a splitter could
                                          // have lived in. It is the grid's left
                                          // EDGE now, and the gap it vacated is
                                          // the splitter's.
                                          Positioned(
                                            left: 0,
                                            top: 0,
                                            bottom: 0,
                                            width:
                                                _metrics.verticalScrollbarWidth,
                                            child:
                                                TimelineVerticalScrollbarRail(
                                                  controller:
                                                      _verticalScrollController,
                                                  viewportHeight:
                                                      bodyViewportHeight,
                                                  contentHeight:
                                                      verticalContentHeight,
                                                  width: _metrics
                                                      .verticalScrollbarWidth,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          Row(
                            children: [
                              SizedBox(
                                key: const ValueKey<String>(
                                  'timeline-vertical-scrollbar-bottom-spacer',
                                ),
                                width: _metrics.verticalScrollbarWidth,
                                height: bottomScrollbarRailHeight,
                              ),
                              // The rail's own bar — the second of the panel's
                              // three. The rail is not a Scrollable (it is a
                              // clipped box), so this one is offset-driven.
                              LayerRailScrollbar(
                                axis: Axis.horizontal,
                                rail: _railExtent,
                                naturalExtent: _naturalRailWidth,
                                availableExtent: availableRailExtent,
                                laneExtent: bottomScrollbarRailHeight,
                                keyPrefix: 'timeline',
                              ),
                              const SizedBox(
                                key: ValueKey<String>(
                                  'timeline-bottom-scrollbar-splitter-spacer',
                                ),
                                width: LayerRailSplitter.thickness,
                              ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final viewportWidth =
                                        constraints.hasBoundedWidth
                                        ? constraints.maxWidth
                                        : 0.0;
                                    final effectiveFrameCount =
                                        _renderedFrameCount;
                                    final contentWidth =
                                        effectiveFrameCount *
                                        _metrics.frameCellWidth;

                                    return TimelineHorizontalScrollbarRail(
                                      key: const ValueKey<String>(
                                        'timeline-horizontal-scrollbar',
                                      ),
                                      controller: _horizontalScrollController,
                                      viewportWidth: viewportWidth,
                                      contentWidth: contentWidth,
                                      height: bottomScrollbarRailHeight,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // The grip FLOATS over the 5px slot the three rows
                      // reserve, so one grab spans the legend, the rows
                      // and the scrollbar line instead of three stacked
                      // stubs — the same slot-plus-overlay idiom the
                      // scrollbar rail has always used here.
                      Positioned(
                        left:
                            _metrics.verticalScrollbarWidth + railWindowExtent,
                        top: 0,
                        bottom: 0,
                        width: LayerRailSplitter.thickness,
                        child: LayerRailSplitter(
                          key: const ValueKey<String>('timeline-rail-splitter'),
                          axis: Axis.horizontal,
                          extent: _railExtent,
                          naturalExtent: _naturalRailWidth,
                          availableExtent: availableRailExtent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Wraps the rail rows' Column and turns a vertical drag STARTING inside
/// [band] (the eye column's x-range) into a Krita-style paint-swipe.
/// [onStart] latches (returns false to decline, e.g. the down landed on a
/// spacer); [onUpdate] paints each crossed row; [onEnd] clears. Uses a
/// vertical-drag recognizer so single taps still reach the eye buttons and
/// the outer vertical scroll keeps working outside the band.
class _EyeSwipeDetector extends StatefulWidget {
  const _EyeSwipeDetector({
    required this.band,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final ({double left, double right}) band;
  final bool Function(double localY) onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_EyeSwipeDetector> createState() => _EyeSwipeDetectorState();
}

class _EyeSwipeDetectorState extends State<_EyeSwipeDetector> {
  bool _engaged = false;

  bool _inBand(Offset local) =>
      local.dx >= widget.band.left && local.dx <= widget.band.right;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragDown: (details) {
        _engaged = _inBand(details.localPosition);
      },
      onVerticalDragStart: (details) {
        if (!_engaged) {
          return;
        }
        _engaged = widget.onStart(details.localPosition.dy);
      },
      onVerticalDragUpdate: (details) {
        if (_engaged) {
          widget.onUpdate(details.localPosition.dy);
        }
      },
      onVerticalDragEnd: (_) {
        if (_engaged) {
          widget.onEnd();
        }
        _engaged = false;
      },
      onVerticalDragCancel: () {
        if (_engaged) {
          widget.onEnd();
        }
        _engaged = false;
      },
      child: widget.child,
    );
  }
}

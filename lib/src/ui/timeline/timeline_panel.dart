import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../panels/panel_collapsed_scope.dart';
import '../../models/app_language.dart' show AppLanguage;
import '../../models/camera_instruction.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/timeline_row_address.dart';
import '../../models/attached_layer_resolve.dart' show attachArrowPlacement;
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart' show LayerFxState;
import '../../models/layer_mark.dart';
import 'layer_timeline_display_adapter.dart';
import 'layer_rail_window.dart'
    show
        LayerRailExtent,
        LayerRailSplitter,
        layerRailFrameReserveExtent,
        layerRailMinimumWindowExtent;
import 'layer_timeline_grid.dart';
import 'property_lane_model.dart';
import 'se_audio_lane.dart' show TimelineAudioLaneCallbacks;
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'layer_row_drag.dart' show TimelineRowDragHooks;
import 'timeline_current_row.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_rows_scroll_body.dart' show TimelineRowMemoAux;
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_grid_metrics.dart';
import '../widgets/app_icon_button.dart';
import 'timeline_command_bar.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_layer_controls_header.dart' show LayerLegendCallbacks;
import 'timeline_row_filter.dart';
import 'timeline_view_cluster.dart';
import 'timeline_orientation.dart';
import 'timeline_section_policy.dart';
import 'xsheet_timeline_grid.dart';

import '../../models/project_frame_rate.dart';

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.layers,
    required this.activeLayerId,
    required this.frameCursor,
    this.frameCachedSignal,
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
    this.audioLane,
    this.onDropMediaAssetOnLayer,
    this.isLayerSoloed,
    this.onOpenLayerMixer,
    required this.onAddLayer,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    required this.onToggleLayerTimesheet,
    this.onToggleLayerFillReference,
    required this.onLayerMarkSelected,
    this.layerFxStateOf,
    this.layerIsLinkedOf,
    this.onToggleLayerCollapsed,
    this.layerOnionSkinEnabledOf,
    this.onToggleLayerOnionSkin,
    this.displayedOnionSkinOn = false,
    this.onToggleLayerFx,
    this.commaDrag,
    this.rangeHooks,
    this.laneRange,
    this.currentRowHooks,
    this.rowDragHooks,
    this.onRowSelectionSpan,
    this.selectedRows = const {},
    this.runEdit,
    this.isFrameCached,
    required this.orientation,
    required this.onOrientationChanged,
    this.timelineActionToolbar,
    this.pixelsPerFrame = TimelinePanel.defaultPixelsPerFrame,
    this.onPixelsPerFrameChanged,
    this.showSeconds = false,
    this.onShowSecondsChanged,
    this.timelineRailExtent,
    this.xsheetRailExtent,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.lanesForLayer,
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
    this.opacityDragPreview,
    this.masterOpacityValue = 1.0,
    this.dragPreview,
    this.seSpillInLayerIds = const {},
    this.cutEndDrag,
    this.memoAux = const TimelineRowMemoAux(),
    this.onLayerBlendModeSelected,
    this.blendLanguage = AppLanguage.en,
    this.layerOpacityOverrideOf,
  });

  final List<Layer> layers;
  final LayerId? activeLayerId;

  /// R27 #6: the layer label's blend-mode column.
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;
  final AppLanguage blendLanguage;

  /// R27 #9: live opacity source for view-state rows (the camera dim).
  final ValueListenable<double>? Function(LayerId layerId)?
  layerOpacityOverrideOf;

  /// The session's edit-drag preview channel (comma/trim drags), consumed
  /// by both grids' row gates and cursor overlays.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// End-line drag hooks (UI-R18 #14), threaded to both grids: the red
  /// cut-end boundary grows a grip that end-trims the ACTIVE cut and the
  /// line follows the live trim preview. Null = display-only.
  final TimelineCutEndDragCallbacks? cutEndDrag;

  /// Sparse-row memo identity tokens (UI-R20 #4).
  final TimelineRowMemoAux memoAux;

  /// Track-SE rows whose display clone starts with a spill-in block
  /// (UI-R7 #6: `~` at the cut start, start grip stands down).
  final Set<LayerId> seSpillInLayerIds;

  /// The frame cursor (editing playhead / playback position). Only the
  /// cursor-driven widgets subscribe — a tick never rebuilds the panel or
  /// its grids (the playback-performance architecture, both orientations).
  final ValueListenable<int> frameCursor;

  /// Repaints the rulers' cached-range green strip as frames warm.
  final Listenable? frameCachedSignal;

  /// R5: the session's "bring the selection back into view" tick, handed
  /// to whichever grid this panel is showing.
  final ValueListenable<int>? revealSelectionTick;

  final int playbackFrameCount;

  /// How many frames the cut is DRAWN for (尺 + のりしろ) and the word the
  /// ruler spells across the difference. Null/empty keeps the handle off.
  final int? drawnFrameCount;
  final String noriShiroLabel;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact source + its row-memo token
  /// (see [TimelineFrameRowsScrollBody]); null = no tint.
  /// R26 #44: the unworked-block tint's fact and its event.
  final TimelineCelContentSource? celContent;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// 🚨T10's second half: a press that turned out to be a TAP clears
  /// whatever was selected (유저: 「클릭하고 떼면 뭐든 비우게」). Both
  /// orientations get it, because the law is 「행이든 셀이든 동일」 and an
  /// x-sheet column is the same surface stood up.
  final VoidCallback? onSettledPress;

  /// Ruler-scrub path (both orientations): per-move frames go to
  /// [onScrubFrame] (cursor-only, no commit) and the release fires
  /// [onScrubEnd] to commit once. Null falls back to [onSelectFrame] per
  /// move (immediate-commit behavior).
  final ValueChanged<int>? onScrubFrame;
  final VoidCallback? onScrubEnd;

  /// Double-tap cell editor hook (SE label dialog), shared by both
  /// orientations.
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// Resolves instruction ids to defs for CAM row chips.
  final CameraInstructionDef? Function(String instructionId)?
  instructionDefById;

  /// Waveform peaks for SE rows' audio clips + the removal hook (both
  /// orientations; frames↔seconds via [projectFrameRate]).
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// Clipped-take marker tooltip (REC1-D); null = markers off. Horizontal
  /// rows only for now — the xsheet's marker joins with its page work.
  final String? seClipMarkerTooltip;

  /// What the audio lane may ask the session to do, both orientations;
  /// null = display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// A media-browser row dropped on a drawing layer; null refuses the drag.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onDropMediaAssetOnLayer;

  /// The SE row's mixer (R10 R3), both orientations: its solo tint, and
  /// the speaker press that opens the window carrying mute/solo/fader/pan.
  /// Null hides the speaker.
  final bool Function(LayerId layerId)? isLayerSoloed;
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  final VoidCallback onAddLayer;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;
  final ValueChanged<LayerId> onToggleLayerTimesheet;

  /// Drawing rows' fill-reference toggle (R20-C2); null hides it.
  final ValueChanged<LayerId>? onToggleLayerFillReference;
  final void Function(LayerId layerId, LayerMark mark) onLayerMarkSelected;

  /// The AE-style layer fx MASTER (R8: persisted, tri-state), both
  /// orientations;
  /// null hides it.
  final LayerFxState Function(LayerId layerId)? layerFxStateOf;

  /// Link badge state (L4); null shows no badges.
  final bool Function(LayerId layerId)? layerIsLinkedOf;

  /// A folder is a LAYER: its eye, opacity, blend, fx switch, FX lanes and
  /// selection all arrive through the layer hooks above. R10 R3 took its
  /// last two of its own — rename went to the Layer ▾ menu it always
  /// shared, dissolve is waiting on the layer-label drag system — so only
  /// the members' twirl is left.
  final ValueChanged<LayerId>? onToggleLayerCollapsed;

  /// Per-layer onion skin (UI-R17 #5) — threaded to the horizontal grid's
  /// rail rows + legend (the xsheet rail keeps its compact control set).
  final bool Function(LayerId layerId)? layerOnionSkinEnabledOf;
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;
  final bool displayedOnionSkinOn;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// Comma-drag hooks for the block edge grips, shared by both
  /// orientations; null hides the grips.
  final TimelineCommaDragCallbacks? commaDrag;

  /// The frame-range select/move hooks (UI-R8), shared by both
  /// orientations; null keeps rows display-only.
  final TimelineFrameRangeHooks? rangeHooks;

  /// The LANE selection domain's gesture bundle (UI-R23 #3 part 2),
  /// shared by both orientations; null keeps lane bands display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  /// Which row the frame-axis verbs act on, and the label press that moves
  /// it (R10 #19's rail half) — one bundle for both orientations, so the
  /// sheet cannot end up with a different answer than the rail.
  final TimelineCurrentRowHooks? currentRowHooks;

  /// The row-order drag (P2b). The horizontal rail takes it today; the
  /// sheet's stood-up headers are the same widget and follow.
  final TimelineRowDragHooks? rowDragHooks;

  /// ⑨: the row SELECT drag's span, in the rail's own display rows.
  final void Function(List<TimelineDisplayRow> rows, int rowDelta)?
  onRowSelectionSpan;

  /// ⑨: the rows currently selected, as ADDRESSES.
  ///
  /// 🚨T1 — this used to be a `Set<LayerId>`, which cannot spell a lane row
  /// or an fx header. T5 made both selectable, so the loss ③ found inside the
  /// span would have reappeared here: selected, and not drawn.
  final Set<TimelineRowAddress> selectedRows;

  /// The run-edge [+]/[↻] handle hooks (UI-R8), both orientations; null
  /// hides the handles.
  final TimelineRunEditCallbacks? runEdit;

  /// Cached-range resolver for the green strip (horizontal ruler and the
  /// X-sheet frame rail).
  final bool Function(int frameIndex)? isFrameCached;

  final TimelineOrientation orientation;
  final ValueChanged<TimelineOrientation> onOrientationChanged;
  final Widget? timelineActionToolbar;

  /// Frame-axis zoom, DaVinci/AE-style continuous slider value in pixels
  /// per frame; the shared range covers the storyboard's overview zooms
  /// and the timeline's classic cell width alike. The X-sheet's frame row
  /// height scales proportionally so its classic geometry sits at the
  /// same default.
  // 4 → 2.4 (UI-R18 #11): the shared zoom floor drops to 10% of the
  // default density across all three frame panels.
  static const double minPixelsPerFrame = 2.4;
  static const double maxPixelsPerFrame = 96;
  // 48 → 24 (R-toolbar slim round): the zoom slider's 100% now reads the
  // CSP/TVPaint-density default.
  static const double defaultPixelsPerFrame = 24;

  /// The shortest this panel is laid out at — the floor the dock splitter
  /// stops on and the tab shell's minimum content height.
  ///
  /// The user's rule (2026-08-02): shrinking the panel shrinks the BODY,
  /// and the body stops at TWO ROWS. Two is the same number the frame area
  /// reserves ([layerRailFrameReserveExtent]) and for the same reason — the
  /// vertical scrollbar's thumb has a 32px minimum, so a body shorter than
  /// that becomes one solid bar with nowhere to travel.
  ///
  /// Everything else in the column is chrome that does NOT shrink: the
  /// command bar, the grid's frame ruler, and the pinned bottom scrollbar
  /// row. That bottom row is what the user watched disappear.
  static const double minPanelHeight =
      TimelineCommandBar.height +
      timelineFrameRulerExtent +
      2 * timelineLayerRowHeight +
      timelineBottomScrollbarRailHeight;

  /// The x-sheet's floor, which is NOT the timeline's even though they
  /// share a tab.
  ///
  /// Stood on its side the sheet spends the panel's HEIGHT on what the
  /// timeline spends its width on: the rail. Its column-header block is the
  /// timeline's layer rail turned vertical, so the number that governs it
  /// is [layerRailMinimumWindowExtent] — the leading control cluster plus
  /// the first character of a name, the same floor the rail splitter obeys
  /// on both surfaces.
  ///
  /// Measured, not assumed: at the timeline's 154 the sheet does not
  /// overflow, but its header window lands at 31px. That is under the 32px
  /// thumb minimum, so the rail scrollbar fills its lane with nowhere to
  /// travel AND the splitter's ceiling collapses — 405px of header is
  /// hidden behind a control that says there is nothing to scroll. The
  /// panel fits and is useless, which is not what the floor is for.
  ///
  /// Below the header block sit the layer-axis scrollbar strip, the rail
  /// splitter, and the frame area's own two-cell reserve — two cells at the
  /// default zoom, which is how [layerRailFrameReserveExtent] states it.
  static const double minSheetPanelHeight =
      TimelineCommandBar.height +
      timelineBottomScrollbarRailHeight +
      layerRailMinimumWindowExtent +
      LayerRailSplitter.thickness +
      layerRailFrameReserveExtent;

  /// The ACTIVE view's zoom (the host routes it to the timeline or the
  /// storyboard value depending on the shown mode).
  final double pixelsPerFrame;
  final ValueChanged<double>? onPixelsPerFrameChanged;

  /// Frames↔seconds display toggle, shared by the timeline counter and the
  /// storyboard cut totals (conte-sheet `s+ff` notation).
  final bool showSeconds;
  final ValueChanged<bool>? onShowSecondsChanged;

  /// The two grids' rail windows. SEPARATE by the user's decision: the
  /// sheet's stood-up header block and the timeline's rail are sized
  /// independently, and R6's "the sheet derives its header from the
  /// timeline's rail width" is retired with them.
  final LayerRailExtent? timelineRailExtent;
  final LayerRailExtent? xsheetRailExtent;

  final ProjectFrameRate projectFrameRate;

  /// AE-style property lanes (twirl-down rows under a layer): expansion
  /// state, toggle and the generic lane provider.
  final Set<LayerId> expandedLaneLayerIds;
  final ValueChanged<LayerId>? onToggleLayerLanes;
  final List<PropertyLaneRow> Function(Layer layer)? lanesForLayer;
  final PropertyLaneEditCallbacks? laneEdit;

  /// Group headers: tapping twirls the group's member lanes (AE collapse),
  /// both orientations.
  final void Function(Layer layer, PropertyLaneRow lane)? onToggleLaneGroup;

  /// The group header's own ON/OFF switch (R6), forwarded to the lane rows.
  final void Function(Layer layer, PropertyLaneRow lane)?
  onToggleLaneGroupEnabled;

  /// The group header's RESET (R5), forwarded to the lane rows.
  final void Function(Layer layer, PropertyLaneRow lane)? onResetLaneGroup;

  /// SE/camera sections folded to stub rows (columns in the X-sheet), and
  /// the gutter/header toggle. Shared by both orientations.
  final Set<TimelineSection> hiddenSections;

  /// Folds/unfolds a hideable section (the legend corner's sections cell).
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The rail legend's bulk commands (horizontal timeline only).
  final LayerLegendCallbacks? legend;

  /// The rail's row filter and its editor (R2); shared by both orientations.
  final TimelineRowFilter rowFilter;
  final ValueChanged<TimelineRowFilter>? onSetRowFilter;

  /// The attach-group fold state (UI-R20 #9), shared by both orientations;
  /// the toggle chevron renders on the horizontal rail's base rows.
  final Set<LayerId> collapsedAttachBaseIds;
  final ValueChanged<LayerId>? onToggleAttachGroup;

  /// Whether the visibility solo mode is engaged (legend eye state color).
  final bool visibilitySoloEnabled;

  /// The session's live opacity-drag preview + the master bar's resting
  /// value (UI-R6 #2).
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;
  final double masterOpacityValue;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final horizontalLayers = horizontalLayerDisplayOrder(widget.layers);
    // The attach arrow is resolved HERE and handed down as a resolver: an
    // organizer folder's direction is its stack position against its base,
    // and `widget.layers` is the only list in this subtree that is still
    // the MODEL order. Both grids below get a display order — the
    // horizontal one reversed — so computing it there points the arrow the
    // wrong way on that surface alone (R10 R3).
    final attachArrows = <LayerId, AttachedPlacement>{};
    for (final layer in widget.layers) {
      final placement = attachArrowPlacement(layer, widget.layers);
      if (placement != null) {
        attachArrows[layer.id] = placement;
      }
    }
    final nextOrientation = widget.orientation == TimelineOrientation.horizontal
        ? TimelineOrientation.vertical
        : TimelineOrientation.horizontal;
    final showToolbar = widget.timelineActionToolbar != null;

    // The slider value is the frame-axis extent for BOTH orientations.
    //
    // R10 R6: this used to scale the sheet by 36/24, because the sheet's
    // frame row was its own hand-typed number. A frame row is a frame cell
    // turned on its side now, so the ratio is 1 and the zoom means the same
    // thing on both surfaces — one slider position, one frame extent.
    final horizontalMetrics = TimelineGridMetrics.defaults.copyWith(
      frameCellWidth: widget.pixelsPerFrame,
    );
    final xsheetMetrics = XSheetTimelineGrid.defaultMetrics.copyWith(
      frameCellWidth: widget.pixelsPerFrame,
    );
    final collapsed = PanelCollapsedScope.of(context);

    return Material(
      color: colorScheme.surfaceContainerHighest,
      // Height comes from the hosting panel region (the tab group).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ONE command-bar row (R-toolbar round), and now literally the
          // same widget the storyboard mounts: the host's transport +
          // action toolbar on the left, the shared view cluster pinned
          // right.
          TimelineCommandBar(
            leading: showToolbar ? widget.timelineActionToolbar : null,
            cluster: TimelineViewCluster(
              frameCursor: widget.frameCursor,
              projectFrameRate: widget.projectFrameRate,
              showSeconds: widget.showSeconds,
              pixelsPerFrame: widget.pixelsPerFrame,
              onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
              trailing: [
                // R26 #42's standard button, like every other control on
                // this bar. It was the last plain Material `IconButton`
                // here — a 24px glyph in 8px of padding, which made the
                // timeline's bar 18px taller than the storyboard's and
                // then got written down as the bar's measured height.
                AppIconButton(
                  keyValue: 'timeline-orientation-toggle-button',
                  tooltip: widget.orientation == TimelineOrientation.horizontal
                      ? 'Show X-sheet'
                      : 'Show timeline',
                  onPressed: () =>
                      widget.onOrientationChanged(nextOrientation),
                  icon: const Icon(Icons.swap_horiz),
                ),
              ],
            ),
          ),
          // ★COLLAPSED = the command bar and nothing else (유저 확정,
          // 2026-08-10: 「접으면 버튼행만 남는다」). The grid goes OFFSTAGE
          // rather than out of the tree: it keeps its scroll positions, its
          // tile caches and its whole element subtree, so unfolding is a
          // flag flip instead of a rebuild — and the parent chain never
          // changes, which is the thing that silently remounts a panel
          // (the flip-HUD round paid for that lesson once already).
          //
          // The `Expanded` stays too, and it is what makes the arithmetic
          // work out: at the collapsed height the bar takes the whole
          // column, this gets zero, and an offstage child does not lay out
          // at all — so there is nothing to overflow.
          Expanded(
            child: Offstage(
              offstage: collapsed,
              child: widget.orientation == TimelineOrientation.horizontal
                ? LayerTimelineGrid(
                    layers: horizontalLayers,
                    activeLayerId: widget.activeLayerId,
                    dragPreview: widget.dragPreview,
                    frameCursor: widget.frameCursor,
                    frameCachedSignal: widget.frameCachedSignal,
                    revealSelectionTick: widget.revealSelectionTick,
                    playbackFrameCount: widget.playbackFrameCount,
                    drawnFrameCount: widget.drawnFrameCount,
                    noriShiroLabel: widget.noriShiroLabel,
                    exposureStateForLayer: widget.exposureStateForLayer,
                    frameNameForLayer: widget.frameNameForLayer,
                    celContent: widget.celContent,
                    onSelectLayer: widget.onSelectLayer,
                    onSelectFrame: widget.onSelectFrame,
                    onSettledPress: widget.onSettledPress,
                    onScrubFrame: widget.onScrubFrame,
                    onScrubEnd: widget.onScrubEnd,
                    onActivateCell: widget.onActivateCell,
                    instructionDefById: widget.instructionDefById,
                    audioPeaksFor: widget.audioPeaksFor,
                    seClipMarkerTooltip: widget.seClipMarkerTooltip,
                    projectFrameRate: widget.projectFrameRate,
                    showSeconds: widget.showSeconds,
                    onShowSecondsChanged: widget.onShowSecondsChanged,
                    railExtent: widget.timelineRailExtent,
                    audioLane: widget.audioLane,
                    onDropMediaAssetOnLayer: widget.onDropMediaAssetOnLayer,
                    onAddLayer: widget.onAddLayer,
                    onOpenLayerMixer: widget.onOpenLayerMixer,
                    attachArrowPlacementOf: (layerId) => attachArrows[layerId],
                    isLayerSoloed: widget.isLayerSoloed,
                    onToggleLayerFillReference:
                        widget.onToggleLayerFillReference,
                    onToggleLayerVisibility: widget.onToggleLayerVisibility,
                    onLayerOpacityChanged: widget.onLayerOpacityChanged,
                    onLayerOpacityChangeEnd: widget.onLayerOpacityChangeEnd,
                    onToggleLayerTimesheet: widget.onToggleLayerTimesheet,
                    onLayerMarkSelected: widget.onLayerMarkSelected,
                    layerFxStateOf: widget.layerFxStateOf,
                    layerIsLinkedOf: widget.layerIsLinkedOf,
                    onToggleLayerCollapsed: widget.onToggleLayerCollapsed,
                    onToggleLayerFx: widget.onToggleLayerFx,
                    layerOnionSkinEnabledOf: widget.layerOnionSkinEnabledOf,
                    onToggleLayerOnionSkin: widget.onToggleLayerOnionSkin,
                    displayedOnionSkinOn: widget.displayedOnionSkinOn,
                    commaDrag: widget.commaDrag,
                    rangeHooks: widget.rangeHooks,
                    laneRange: widget.laneRange,
                    currentRowHooks: widget.currentRowHooks,
                    rowDragHooks: widget.rowDragHooks,
                    onRowSelectionSpan: widget.onRowSelectionSpan,
                    selectedRows: widget.selectedRows,
                    runEdit: widget.runEdit,
                    isFrameCached: widget.isFrameCached,
                    metrics: horizontalMetrics,
                    expandedLaneLayerIds: widget.expandedLaneLayerIds,
                    onToggleLayerLanes: widget.onToggleLayerLanes,
                    lanesForLayer: widget.lanesForLayer,
                    laneEdit: widget.laneEdit,
                    onToggleLaneGroup: widget.onToggleLaneGroup,
                    onToggleLaneGroupEnabled: widget.onToggleLaneGroupEnabled,
                    onResetLaneGroup: widget.onResetLaneGroup,
                    hiddenSections: widget.hiddenSections,
                    onToggleSection: widget.onToggleSection,
                    legend: widget.legend,
                    rowFilter: widget.rowFilter,
                    onSetRowFilter: widget.onSetRowFilter,
                    collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
                    onToggleAttachGroup: widget.onToggleAttachGroup,
                    visibilitySoloEnabled: widget.visibilitySoloEnabled,
                    opacityDragPreview: widget.opacityDragPreview,
                    masterOpacityValue: widget.masterOpacityValue,
                    seSpillInLayerIds: widget.seSpillInLayerIds,
                    cutEndDrag: widget.cutEndDrag,
                    memoAux: widget.memoAux,
                    onLayerBlendModeSelected: widget.onLayerBlendModeSelected,
                    blendLanguage: widget.blendLanguage,
                    layerOpacityOverrideOf: widget.layerOpacityOverrideOf,
                  )
                : XSheetTimelineGrid(
                    layers: xsheetLayerDisplayOrder(widget.layers),
                    activeLayerId: widget.activeLayerId,
                    seSpillInLayerIds: widget.seSpillInLayerIds,
                    seClipMarkerTooltip: widget.seClipMarkerTooltip,
                    dragPreview: widget.dragPreview,
                    frameCursor: widget.frameCursor,
                    frameCachedSignal: widget.frameCachedSignal,
                    revealSelectionTick: widget.revealSelectionTick,
                    frameCount: widget.playbackFrameCount,
                    drawnFrameCount: widget.drawnFrameCount,
                    noriShiroLabel: widget.noriShiroLabel,
                    exposureStateForLayer: widget.exposureStateForLayer,
                    frameNameForLayer: widget.frameNameForLayer,
                    celContent: widget.celContent,
                    onSelectLayer: widget.onSelectLayer,
                    onSelectFrame: widget.onSelectFrame,
                    onSettledPress: widget.onSettledPress,
                    onScrubFrame: widget.onScrubFrame,
                    onScrubEnd: widget.onScrubEnd,
                    onActivateCell: widget.onActivateCell,
                    instructionDefById: widget.instructionDefById,
                    audioPeaksFor: widget.audioPeaksFor,
                    projectFrameRate: widget.projectFrameRate,
                    showSeconds: widget.showSeconds,
                    onShowSecondsChanged: widget.onShowSecondsChanged,
                    railExtent: widget.xsheetRailExtent,
                    audioLane: widget.audioLane,
                    onDropMediaAssetOnLayer: widget.onDropMediaAssetOnLayer,
                    onAddLayer: widget.onAddLayer,
                    onOpenLayerMixer: widget.onOpenLayerMixer,
                    // R10 R6: the sheet carries every column the rail does —
                    // these two were the last it was missing, and the panel
                    // had been holding them for the horizontal grid alone.
                    onToggleLayerOnionSkin: widget.onToggleLayerOnionSkin,
                    layerOnionSkinEnabledOf: widget.layerOnionSkinEnabledOf,
                    onLayerBlendModeSelected: widget.onLayerBlendModeSelected,
                    blendLanguage: widget.blendLanguage,
                    attachArrowPlacementOf: (layerId) => attachArrows[layerId],
                    isLayerSoloed: widget.isLayerSoloed,
                    onToggleLayerFillReference:
                        widget.onToggleLayerFillReference,
                    onToggleLayerVisibility: widget.onToggleLayerVisibility,
                    onLayerOpacityChanged: widget.onLayerOpacityChanged,
                    onLayerOpacityChangeEnd: widget.onLayerOpacityChangeEnd,
                    opacityDragPreview: widget.opacityDragPreview,
                    onToggleLayerTimesheet: widget.onToggleLayerTimesheet,
                    onLayerMarkSelected: widget.onLayerMarkSelected,
                    layerFxStateOf: widget.layerFxStateOf,
                    onToggleLayerFx: widget.onToggleLayerFx,
                    commaDrag: widget.commaDrag,
                    rangeHooks: widget.rangeHooks,
                    laneRange: widget.laneRange,
                    currentRowHooks: widget.currentRowHooks,
                    rowDragHooks: widget.rowDragHooks,
                    onRowSelectionSpan: widget.onRowSelectionSpan,
                    selectedRows: widget.selectedRows,
                    runEdit: widget.runEdit,
                    isFrameCached: widget.isFrameCached,
                    metrics: xsheetMetrics,
                    expandedLaneLayerIds: widget.expandedLaneLayerIds,
                    onToggleLayerLanes: widget.onToggleLayerLanes,
                    lanesForLayer: widget.lanesForLayer,
                    laneEdit: widget.laneEdit,
                    onToggleLaneGroup: widget.onToggleLaneGroup,
                    onToggleLaneGroupEnabled: widget.onToggleLaneGroupEnabled,
                    onResetLaneGroup: widget.onResetLaneGroup,
                    hiddenSections: widget.hiddenSections,
                    rowFilter: widget.rowFilter,
                    collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
                    onToggleLayerCollapsed: widget.onToggleLayerCollapsed,
                    onToggleAttachGroup: widget.onToggleAttachGroup,
                    cutEndDrag: widget.cutEndDrag,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

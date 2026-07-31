import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/audio_clip.dart' show AudioFadeCurve, AudioVolumeKey;
import '../../models/camera_instruction.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../text/app_strings.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart' show LayerFxState;
import '../../models/layer_mark.dart';
import 'layer_timeline_display_adapter.dart';
import 'layer_timeline_grid.dart';
import 'property_lane_model.dart';
import 'se_audio_lane.dart' show TimelineAudioLaneCallbacks;
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_rows_scroll_body.dart' show TimelineRowMemoAux;
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_layer_controls_header.dart' show LayerLegendCallbacks;
import 'timeline_row_filter.dart';
import 'timeline_section_bracket_rail.dart' show TimelineSectionRailCallbacks;
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
    required this.playbackFrameCount,
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    this.celContent,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onScrubFrame,
    this.onScrubEnd,
    this.onActivateCell,
    this.instructionDefById,
    this.audioPeaksFor,
    this.seClipMarkerTooltip,
    this.audioLane,
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
    this.runEdit,
    this.isFrameCached,
    required this.orientation,
    required this.onOrientationChanged,
    this.timelineActionToolbar,
    this.pixelsPerFrame = TimelinePanel.defaultPixelsPerFrame,
    this.onPixelsPerFrameChanged,
    this.showSeconds = false,
    this.onShowSecondsChanged,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.lanesForLayer,
    this.laneEdit,
    this.onToggleLaneGroup,
    this.onToggleLaneGroupEnabled,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.legend,
    this.sectionRail,
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

  final int playbackFrameCount;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact source + its row-memo token
  /// (see [TimelineFrameRowsScrollBody]); null = no tint.
  /// R26 #44: the unworked-block tint's fact and its event.
  final TimelineCelContentSource? celContent;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

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

  /// The ACTIVE view's zoom (the host routes it to the timeline or the
  /// storyboard value depending on the shown mode).
  final double pixelsPerFrame;
  final ValueChanged<double>? onPixelsPerFrameChanged;

  /// Frames↔seconds display toggle, shared by the timeline counter and the
  /// storyboard cut totals (conte-sheet `s+ff` notation).
  final bool showSeconds;
  final ValueChanged<bool>? onShowSecondsChanged;
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

  /// SE/camera sections folded to stub rows (columns in the X-sheet), and
  /// the gutter/header toggle. Shared by both orientations.
  final Set<TimelineSection> hiddenSections;

  /// Folds/unfolds a hideable section (legend corner + bracket chevrons).
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The rail legend's bulk commands (horizontal timeline only).
  final LayerLegendCallbacks? legend;

  /// The section brackets' flyout commands (horizontal timeline only).
  final TimelineSectionRailCallbacks? sectionRail;

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
    final nextOrientation = widget.orientation == TimelineOrientation.horizontal
        ? TimelineOrientation.vertical
        : TimelineOrientation.horizontal;
    final showToolbar = widget.timelineActionToolbar != null;

    // The slider value is the horizontal cell width; the X-sheet's frame
    // row height scales proportionally (36 at the classic 48).
    final horizontalMetrics = TimelineGridMetrics.defaults.copyWith(
      frameCellWidth: widget.pixelsPerFrame,
    );
    final xsheetMetrics = XSheetTimelineGrid.defaultMetrics.copyWith(
      frameCellWidth:
          widget.pixelsPerFrame *
          (XSheetTimelineGrid.defaultMetrics.frameCellWidth /
              TimelineGridMetrics.defaults.frameCellWidth),
    );

    return Material(
      color: colorScheme.surfaceContainerHighest,
      // Height comes from the hosting panel region (the tab group).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ONE command-bar row (R-toolbar round): the host's transport +
          // action toolbar on the left, the shared view cluster pinned
          // right. The old separate top row is gone.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                if (showToolbar)
                  Expanded(child: widget.timelineActionToolbar!)
                else
                  const Spacer(),
                const SizedBox(width: 8),
                TimelineViewCluster(
                  frameCursor: widget.frameCursor,
                  projectFrameRate: widget.projectFrameRate,
                  showSeconds: widget.showSeconds,
                  onShowSecondsChanged: widget.onShowSecondsChanged,
                  pixelsPerFrame: widget.pixelsPerFrame,
                  onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
                  trailing: [
                    IconButton(
                      key: const ValueKey<String>(
                        'timeline-orientation-toggle-button',
                      ),
                      tooltip:
                          widget.orientation == TimelineOrientation.horizontal
                          ? 'Show X-sheet'
                          : 'Show timeline',
                      onPressed: () =>
                          widget.onOrientationChanged(nextOrientation),
                      icon: const Icon(Icons.swap_horiz),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.orientation == TimelineOrientation.horizontal
                ? LayerTimelineGrid(
                    layers: horizontalLayers,
                    activeLayerId: widget.activeLayerId,
                    dragPreview: widget.dragPreview,
                    frameCursor: widget.frameCursor,
                    frameCachedSignal: widget.frameCachedSignal,
                    playbackFrameCount: widget.playbackFrameCount,
                    exposureStateForLayer: widget.exposureStateForLayer,
                    frameNameForLayer: widget.frameNameForLayer,
                    celContent: widget.celContent,
                    onSelectLayer: widget.onSelectLayer,
                    onSelectFrame: widget.onSelectFrame,
                    onScrubFrame: widget.onScrubFrame,
                    onScrubEnd: widget.onScrubEnd,
                    onActivateCell: widget.onActivateCell,
                    instructionDefById: widget.instructionDefById,
                    audioPeaksFor: widget.audioPeaksFor,
                    seClipMarkerTooltip: widget.seClipMarkerTooltip,
                    projectFrameRate: widget.projectFrameRate,
                    showSeconds: widget.showSeconds,
                    audioLane: widget.audioLane,
                    onAddLayer: widget.onAddLayer,
                    onOpenLayerMixer: widget.onOpenLayerMixer,
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
                    runEdit: widget.runEdit,
                    isFrameCached: widget.isFrameCached,
                    metrics: horizontalMetrics,
                    expandedLaneLayerIds: widget.expandedLaneLayerIds,
                    onToggleLayerLanes: widget.onToggleLayerLanes,
                    lanesForLayer: widget.lanesForLayer,
                    laneEdit: widget.laneEdit,
                    onToggleLaneGroup: widget.onToggleLaneGroup,
                    onToggleLaneGroupEnabled: widget.onToggleLaneGroupEnabled,
                    hiddenSections: widget.hiddenSections,
                    onToggleSection: widget.onToggleSection,
                    legend: widget.legend,
                    sectionRail: widget.sectionRail,
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
                    frameCount: widget.playbackFrameCount,
                    exposureStateForLayer: widget.exposureStateForLayer,
                    frameNameForLayer: widget.frameNameForLayer,
                    celContent: widget.celContent,
                    onSelectLayer: widget.onSelectLayer,
                    onSelectFrame: widget.onSelectFrame,
                    onScrubFrame: widget.onScrubFrame,
                    onScrubEnd: widget.onScrubEnd,
                    onActivateCell: widget.onActivateCell,
                    instructionDefById: widget.instructionDefById,
                    audioPeaksFor: widget.audioPeaksFor,
                    projectFrameRate: widget.projectFrameRate,
                    showSeconds: widget.showSeconds,
                    audioLane: widget.audioLane,
                    onAddLayer: widget.onAddLayer,
                    onOpenLayerMixer: widget.onOpenLayerMixer,
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
                    runEdit: widget.runEdit,
                    isFrameCached: widget.isFrameCached,
                    metrics: xsheetMetrics,
                    expandedLaneLayerIds: widget.expandedLaneLayerIds,
                    onToggleLayerLanes: widget.onToggleLayerLanes,
                    lanesForLayer: widget.lanesForLayer,
                    laneEdit: widget.laneEdit,
                    onToggleLaneGroup: widget.onToggleLaneGroup,
                    onToggleLaneGroupEnabled: widget.onToggleLaneGroupEnabled,
                    hiddenSections: widget.hiddenSections,
                    rowFilter: widget.rowFilter,
                    collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
                    cutEndDrag: widget.cutEndDrag,
                  ),
          ),
        ],
      ),
    );
  }
}

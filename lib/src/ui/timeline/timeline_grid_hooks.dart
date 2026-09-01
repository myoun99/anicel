import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/app_language.dart' show AppLanguage;
import '../../models/camera_instruction.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/timeline_row_address.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import 'layer_row_drag.dart';
import 'timeline_current_row.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_rows_scroll_body.dart';
import 'property_lane_model.dart';
import 'se_audio_lane.dart' show TimelineAudioLaneCallbacks;
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';
import '../../models/project_frame_rate.dart';

/// What the session answers to a timeline grid — the hooks, resolvers and
/// live reads a grid needs to show a cut and act on it — as ONE bundle that
/// both grids take.
///
/// 🚨★★★The rail and the x-sheet each declared these seventy-odd
/// parameters, and the panel passed them twice. Two lists that must agree
/// are how the sheet came to lack the link badge, the camera column's live
/// opacity, the onion and blend columns, the live twirl read — one per
/// round, each found by the user (F-26: 「몇번째인지 모를 통일화 미스」).
/// A grid cannot lack an answer now: there is one list, and
/// `one_grid_hooks_test` says a parameter both grids take lives here.
///
/// The three a grid keeps for itself are genuinely its own: its layer ORDER
/// (`layers` — the rail's display order and the sheet's are different
/// reversals), its rail WINDOW (`railExtent` — persisted per surface) and
/// its METRICS (the sheet's are the timeline's turned on their side).
///
/// Every doc below is the rail's, verbatim; where the sheet's copy carried a
/// decision of its own it follows, marked (x-sheet).
class TimelineGridHooks {
  const TimelineGridHooks({
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
    this.instructionCrossingTooltip,
    this.audioPeaksFor,
    this.seClipMarkerTooltip,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.showSeconds = false,
    this.onShowSecondsChanged,
    this.audioLane,
    this.onDropMediaAssetOnLayer,
    this.isLayerSoloed,
    this.onOpenLayerMixer,
    this.attachArrowPlacementOf,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    required this.onToggleLayerTimesheet,
    this.layerFxStateOf,
    this.layerIsLinkedOf,
    this.onToggleLayerCollapsed,
    this.layerOnionSkinEnabledOf,
    this.onToggleLayerOnionSkin,
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
    this.expandedLaneLayerIds = const {},
    this.laneOpenOf,
    this.laneGroupOnOf,
    this.layerEyeOnOf,
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
    this.onToggleAttachGroup,
    this.dragPreview,
    this.opacityDragPreview,
    this.seSpillInLayerIds = const {},
    this.cutEndDrag,
    this.substrateGeneration = '',
    this.onLayerBlendModeSelected,
    this.blendLanguage = AppLanguage.en,
    this.layerOpacityOverrideOf,
  });

  final LayerId? activeLayerId;

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

  /// D26: crossing-fade warning resolver, by span start key (the display
  /// clone's projected key on this cut-local surface).
  final String? Function(int spanStartKey)? instructionCrossingTooltip;

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

  final ValueChanged<LayerId> onToggleLayerVisibility;

  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  final ValueChanged<LayerId> onToggleLayerTimesheet;

  /// The AE-style layer fx MASTER (R8: persisted, tri-state); null hides it.
  final LayerFxState Function(LayerId layerId)? layerFxStateOf;

  /// Link badge state (L4): whether a layer's pictures are shared with a
  /// link group. Null shows no badges.
  ///
  /// (x-sheet) The link badge (L4) and the camera column's live opacity (R27 #9):
  /// two answers the panel held for the rail alone, until the sheet's
  /// header became the rail's row stood up and asked for them too.
  final bool Function(LayerId layerId)? layerIsLinkedOf;

  /// The row twirl that folds a FOLDER's members (the attach fold has its
  /// own hook because it is session state, not layer state).
  ///
  /// (x-sheet) The GROUP-FOLD twirl's two commits — a folder folding its members, an
  /// attach base folding its rows. R5 #2: the sheet already HID what those
  /// sets say (it reads [collapsedAttachBaseIds] and `subtreeCollapsed`
  /// like the rail does), but it carried no control to say it with, so a
  /// folder could only be folded from the other panel. One skeleton, one
  /// row vocabulary — a column that shows a fold has to offer it.
  final ValueChanged<LayerId>? onToggleLayerCollapsed;

  /// Per-layer onion skin (UI-R17 #5): the row toggles + the legend cell's
  /// engaged state. Null hides the onion column entirely.
  final bool Function(LayerId layerId)? layerOnionSkinEnabledOf;

  /// (x-sheet) The ONION and BLEND columns (UI-R17 #5, R27 #6). The sheet went
  /// without them until the user's R10 R6 call — "타임라인에 있는거 싹다
  /// 넣어" — and the panel had been holding both callbacks all along,
  /// passing them to the horizontal grid only.
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;

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

  /// The LANE selection domain's host hooks (UI-R23 #3 part 2); null
  /// keeps the lane bands display-only. The grid resolves geometry and
  /// mounts the gesture-level bundle itself (C②'s two-level shape).
  final TimelineLaneRangeHooks? laneRange;

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

  /// AE-style property lanes: layers whose twirl-down is open, the toggle,
  /// and the lane provider (generic — transform lanes now, FX lanes later).
  final Set<LayerId> expandedLaneLayerIds;

  /// A LIVE read of the twirl state, when the host can give one.
  ///
  /// 🚨[expandedLaneLayerIds] is a widget property: the host mutates its set
  /// and the new value reaches here on the NEXT build, which is a frame too
  /// late for a bulk-drag that started on the twirl itself (the button fires
  /// on the down — 유저 2026-08-30 — and the sweep spreads what it set).
  final bool Function(LayerId layerId)? laneOpenOf;

  /// A LIVE read of a lane GROUP’s switch, when the host can give one — the
  /// transform group’s flag is the layer’s own field, and a lane row built
  /// last frame carries a stale copy.
  final bool Function(LayerId layerId)? laneGroupOnOf;

  /// A LIVE read of a layer’s own eye — the rail’s bulk-drag needs the value
  /// the press just set, and a captured [Layer] still reports the last
  /// frame.
  final bool Function(LayerId layerId)? layerEyeOnOf;

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

  /// The rail's row FILTER (R2): hides layer rows failing its predicate;
  /// the active layer is exempt.
  final TimelineRowFilter rowFilter;

  /// Bases whose attach group is twirled shut (UI-R20 #9): their attach
  /// rows contribute no display rows; the base row's chevron reflects it.
  ///
  /// (x-sheet) Bases whose attach group is twirled shut (UI-R20 #9): their attach
  /// columns drop — the shared view state; the fold toggle lives on the
  /// horizontal rail.
  final Set<LayerId> collapsedAttachBaseIds;

  /// The base-row chevron's toggle; null hides the twirl UI.
  final ValueChanged<LayerId>? onToggleAttachGroup;

  /// The session's edit-drag preview channel: a comma-drag step rebuilds
  /// only the dragged layer's row (its gate) and the cursor overlay —
  /// never this grid.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// The session's live opacity-drag preview (UI-R6 #2): rows follow it
  /// while the master bar sweeps them.
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  /// Track-SE rows whose display clone starts with a spill-in block
  /// (UI-R7 #6: `~` at the cut start, start grip stands down).
  ///
  /// (x-sheet) Track-SE layers whose sound spills in from the previous cut (UI-R7 #6):
  /// their first block shows the `~` continuation mark instead of a start
  /// grip. Mirrors the horizontal timeline's plumbing.
  final Set<LayerId> seSpillInLayerIds;

  /// End-line drag hooks (UI-R18 #14): the red cut-end boundary grows a
  /// grip that end-trims the ACTIVE cut through the session's trim
  /// channel; the line follows the live preview. Null = display-only.
  final TimelineCutEndDragCallbacks? cutEndDrag;

  /// #29: the (project, cut) world the rows' resolvers answer from — see
  /// [TimelineRowCellsPainter.substrateGeneration].
  final String substrateGeneration;

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
}

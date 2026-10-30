import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/camera_instruction.dart';
import '../../models/cut_id.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/sound_cannot_play.dart';
import '../input/two_axis_drag.dart' show SheetZoom, sheetZoom;
import 'layer_label_controls.dart' show LayerMarkEdit;
import 'layer_rail_columns.dart' show LayerRailOptionalColumns;
import 'layer_row_drag.dart';
import 'timeline_current_row.dart';
import 'timeline_double_tap.dart' show TimelineLabelDoubleClick;
import 'timeline_frame_range_gesture.dart';
import 'timeline_grid_legend.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'lane_graph.dart' show LaneGraphVerbs, LaneGraphsView;
import 'lane_graph_seats.dart' show LaneGraphLine, seatLaneGraphs;
import 'property_lane_model.dart';
import 'timeline_row_filter.dart';
import 'frame_ruler_view.dart';
import 'timeline_ruler_cursor_overlay.dart' show ReadyRunsIn;
import 'timeline_section_policy.dart';
import '../../models/project_frame_rate.dart';

/// See [TimelineGridHooks.memoAux].
class TimelineRowMemoAux {
  const TimelineRowMemoAux({this.cameraTrack, this.instructionDefs});

  /// The active cut's camera track object (immutable — a key edit is a
  /// new instance).
  final Object? cameraTrack;

  /// The camera-instruction registry object.
  final Object? instructionDefs;
}


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
    this.playbackFrame,
    this.stepsUntilShown,
    required this.playbackFrameCount,
    this.noriShiro,
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    this.celContent,
    required this.onSelectLayer,
    this.labelDoubleClick,
    required this.onSelectFrame,
    this.onSettledPress,
    this.onScrubFrame,
    this.onScrubEnd,
    this.onActivateCell,
    this.instructionDefById,
    this.instructionCrossingTooltip,
    this.audioPeaksFor,
    this.soundCannotPlay,
    this.seClipMarkerTooltip,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.rulerView = FrameRulerView.frames,
    this.sheetPages,
    this.onRulerViewChanged,
    this.onPixelsPerFrameChanged,
    this.onDropMediaAssetOnSeBlock,
    this.onDropMediaAssetOnLayer,
    this.acceptsMediaAssetOnLayer,
    this.onHoverMediaAssetOnLayer,
    this.onLeaveMediaAssetOnLayer,
    this.onDropMediaAssetBetweenLayers,
    this.isLayerSoloed,
    this.onOpenLayerMixer,
    this.onOpenLayerReference,
    this.onOpenLayerLinks,
    this.onOpenCameraPath,
    this.layerSourceIsShortOf,
    this.attachArrowPlacementOf,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    required this.onToggleLayerTimesheet,
    this.layerFxStateOf,
    this.layerLinkPartnersOf,
    this.onToggleLayerCollapsed,
    this.layerOnionSkinEnabledOf,
    this.onToggleLayerOnionSkin,
    this.onToggleLayerFx,
    required this.onLayerMarkSelected,
    this.onToggleLayerClip,
    this.commaDrag,
    this.rangeHooks,
    this.laneRange,
    this.currentRowHooks,
    this.rowDragHooks,
    this.onRowSelectionSpan,
    this.selectedRows = const {},
    this.runEdit,
    this.readyRunsIn,
    this.expandedLaneLayerIds = const {},
    this.laneGraphs = LaneGraphsView.none,
    this.laneGraphVerbs,
    this.laneGraphsNow,
    this.laneGraphLineOf,
    this.laneOpenOf,
    this.laneGroupOnOf,
    this.layerEyeOnOf,
    this.layerOnTimesheetOf,
    this.layerClipsOf,
    this.groupFoldOpenOf,
    this.laneGroupOpenOf,
    this.onToggleLayerLanes,
    this.lanesForLayer,
    this.unionLaneForLayer,
    this.laneEdit,
    this.onToggleLaneGroup,
    this.onToggleLaneGroupEnabled,
    this.onResetLaneGroup,
    this.hiddenSections = const {},
    this.rowFilter = TimelineRowFilter.none,
    this.legend = const TimelineGridLegend(),
    this.collapsedAttachBaseIds = const {},
    this.onToggleAttachGroup,
    this.dragPreview,
    this.opacityDragPreview,
    this.spillInLeadFrames = const {},
    this.cutId,
    this.cutEndDrag,
    this.substrateGeneration = '',
    this.memoAux = const TimelineRowMemoAux(),
    this.onLayerBlendModeSelected,
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

  /// F-110: WHETHER PLAYBACK IS RUNNING — the playback position, or null
  /// while nothing plays. It is the gate on the frame axis turning its page
  /// (유저 2026-09-12: 「**재생시에도** 플레이헤드 밖 나갈때 스크롤하도록.
  /// **룰러 드래그랑은 다르게 다음 페이지? 로 간다는 느낌**임」).
  ///
  /// ⛔Not the tick, and not read for a number. The surface pages off its
  /// own [frameCursor] — which is what already carries the playback frame
  /// here, in the frames THIS axis counts in (the rail the cut's local ones,
  /// the storyboard the track's global ones). Listening to this instead
  /// would ask every surface to undo that mapping again, and would depend on
  /// two listeners on one notifier firing in the order they were added.
  final ValueListenable<int?>? playbackFrame;

  /// How many steps on the playing run shows this grid's frame [frame] (its
  /// own count — the cut's frames here as [frameCursor] counts them), or
  /// null for a frame the run does not show and wherever nothing plays: the
  /// run's own order (`FrameDemand.stepOf`), which the substrate tiles are
  /// let go by ([TimelineTileRasterSource.stepsUntilShown]). Null where no
  /// run reaches the host.
  ///
  /// ⛔Asked live, never read for a build: a tick rebuilds nothing, and a
  /// run begins and ends under rows kept the whole time.
  final int? Function(int frame)? stepsUntilShown;

  final int playbackFrameCount;

  /// How many frames the cut is DRAWN for (尺 + のりしろ) and the word the
  /// ruler spells across the handle, as the timeline shows them NOW. Null
  /// keeps the ruler's blue handle boundary off.
  ///
  /// 🚨Asked, not handed over: every surface that draws the margin asks it
  /// again wherever it hears a drag, so the blue line, the wash's edge and
  /// the name across the margin ride a transition span dragged over the
  /// cut's boundary. ↩️They were two values the host handed over when it
  /// built, and the host never rebuilds for a drag step — the ruler stood
  /// on the committed margin until the release
  /// (`ruler-norishiro-follows-drags`).
  final TimelineNoriShiro Function()? noriShiro;

  /// How many frames a run of the cut plays before it wraps: every frame it
  /// is DRAWN for ([noriShiro]) — F-227, 「재생도 타임라인패널의 재생이면
  /// 여백까지 재생」 — its 尺 where nothing crosses it.
  int get runFrames => noriShiro?.call().drawnFrameCount ?? playbackFrameCount;

  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;

  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact AND its event (null = no
  /// tint). The event replaced a per-layer "empty cels" token that joined
  /// the memo key: the token forced a row REBUILD and only when something
  /// else already announced, while the revision repaints the row painter
  /// the moment a cel gains pixels — and costs no per-row string build.
  final TimelineCelContentSource? celContent;

  final ValueChanged<LayerId> onSelectLayer;

  /// A double click on a row's LABEL — the rename (I-48) — asked at its
  /// first press ([TimelineLabelDoubleClick]). Null mounts none.
  final TimelineLabelDoubleClick? labelDoubleClick;

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
  /// clone's projected key on this cut-local surface). A callback, so it
  /// stays OUT of the row memo token (R13-2); its ANSWERS are covered —
  /// instruction edits move the [memoAux] identity and the display clone's
  /// layer identity, and a cut-duration change moves [playbackFrameCount].
  final String? Function(int spanStartKey)? instructionCrossingTooltip;

  /// Waveform peaks for SE rows' audio clips + the removal hook.
  final AudioPeaks? Function(String filePath)? audioPeaksFor;

  /// Why an SE row's sound cannot be played (`PlaybackRig.soundCannotPlay`)
  /// — a red warning line on its block saying so
  /// (playback-says-the-sound-it-cannot-play). Its paper goes red by the
  /// cel content source's [TimelineCelContentSource.cannotRead].
  final SoundCannotPlay? Function(String filePath)? soundCannotPlay;

  /// Clipped-take marker tooltip (REC1-D); null = markers off.
  final String? seClipMarkerTooltip;

  final ProjectFrameRate projectFrameRate;

  /// How the ruler counts (UI-R10 #27 · I-81): the seconds display repeats
  /// 1..fps per second, the page view 1..a page, instead of absolute frame
  /// numbers. The block duration labels share it (R26 #7) — [showSeconds].
  final FrameRulerView rulerView;

  /// Whether a length reads as seconds+frames ([FrameRulerView.seconds]).
  bool get showSeconds => rulerView.seconds;

  /// The pages of the open cut's X-sheet — where the page view's ruler
  /// starts again; null with no cut open.
  final TimelineRulerPages? sheetPages;

  /// The display's pick moved OUT of the command bar and onto the grid's
  /// top-left corner cell (the rail-window round) — it belongs beside the
  /// axis it relabels. Null leaves the corner as a plain spacer.
  final ValueChanged<FrameRulerView>? onRulerViewChanged;

  /// The panel's zoom writer — the readout's and the zoom keys' — which a
  /// pinch on the grid writes through too (F-506, [SheetZoom]). Null names
  /// no zoom, and fingers only move the grid.
  final ValueChanged<double>? onPixelsPerFrameChanged;

  /// What a pinch on a grid laid out at [pixelsPerFrame] zooms.
  SheetZoom? zoomAt(double pixelsPerFrame) =>
      sheetZoom(pixelsPerFrame, projectFrameRate, onPixelsPerFrameChanged);

  /// A media-browser sound dropped on an SE block: linked to that block's
  /// instance. Null mounts no drop place. ↩️It rode the audio lane's
  /// callbacks, which went with the lane (I-140).
  final void Function(LayerId layerId, int blockStartFrame, String path)?
  onDropMediaAssetOnSeBlock;

  /// A media-browser row dropped on a DRAWING layer: the window opens with
  /// this cut and this layer already answered.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onDropMediaAssetOnLayer;

  /// Whether a file at a frame of a row can land there — the session's
  /// answer the drag's chip wears (「불가능 = 칩의 금지 표시」). Null is yes.
  final bool Function(LayerId layerId, int frameIndex, String path)?
  acceptsMediaAssetOnLayer;

  /// Where a file being dragged STANDS on a row, per pointer step — the
  /// session draws what letting go there would make (「끄는 동안 보이는
  /// 것은 놓았을 때 생길 것이다」). Both grids hand it over, so the sheet
  /// and the timeline show one answer.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onHoverMediaAssetOnLayer;

  /// The file is off the rows, left or let go: the drawing goes with it.
  final void Function()? onLeaveMediaAssetOnLayer;

  /// A media-browser row let go on the LAYER AREA, at the gap [slot] of
  /// [displayLayers]: a new layer there (「레이어 영역(가로선) → 새
  /// 레이어」). Null leaves the layer area refusing the drag.
  final void Function(List<Layer> displayLayers, int slot, String path)?
  onDropMediaAssetBetweenLayers;

  /// The SE row's mixer (R10 R3): its solo tint, and the speaker press
  /// that opens the window carrying mute/solo/fader/pan. Null hides the
  /// speaker.
  final bool Function(LayerId layerId)? isLayerSoloed;

  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  /// A reference row's file button: the popover that bakes it (미디어 배치
  /// 라운드 3). Null hides the button.
  final Future<void> Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerReference;

  /// A linked row's badge: the link window (I-25). Null leaves the badge a
  /// picture.
  final Future<void> Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerLinks;

  /// The camera row's path button: how the canvas shows the camera's path
  /// (I-89 ④). Null mounts no button.
  final Future<void> Function(BuildContext anchorContext)? onOpenCameraPath;

  /// Whether that row asks its file for more than the file can show — the
  /// button goes red and the popover says by how much (유저 2026-09-12).
  final bool Function(LayerId layerId)? layerSourceIsShortOf;

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

  /// Link badge (L4): the rows a layer shares its pictures with (empty: not
  /// linked). Null shows no badges.
  ///
  /// (x-sheet) The link badge (L4) and the camera column's live opacity (R27 #9):
  /// two answers the panel held for the rail alone, until the sheet's
  /// header became the rail's row stood up and asked for them too.
  final List<String> Function(LayerId layerId)? layerLinkPartnersOf;

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

  final void Function(LayerId layerId, LayerMarkEdit edit) onLayerMarkSelected;

  /// The clip toggle (I-92) of every row that can clip; null hides it.
  final ValueChanged<LayerId>? onToggleLayerClip;

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
  final ReadyRunsIn? readyRunsIn;

  /// AE-style property lanes: layers whose twirl-down is open, the toggle,
  /// and the lane provider (generic — transform lanes now, FX lanes later).
  final Set<LayerId> expandedLaneLayerIds;

  /// The rail's header graphs (I-89 ③): which groups' lanes are drawn as
  /// one graph, and how. View state, like the twirls beside it.
  final LaneGraphsView laneGraphs;

  /// What the header graphs' buttons tell — a group's graph on or off, a
  /// lane pinned or let go. Null mounts none of them.
  final LaneGraphVerbs? laneGraphVerbs;

  /// A LIVE read of the header graphs, when the host can give one — what
  /// [laneOpenOf] is to the twirls: [laneGraphs] reaches here a build late,
  /// and a sweep begun on a graph button spreads what the down just set.
  final LaneGraphsView Function()? laneGraphsNow;

  /// The lane a pin names, by its key in [LaneGraphsView.pinned], as a
  /// graph draws it — read whether or not the rail shows its row, so a pin
  /// reaches every graph from wherever it was pinned. Null draws no
  /// guests.
  final LaneGraphLine? Function(String key)? laneGraphLineOf;

  /// A LIVE read of the twirl state, when the host can give one.
  ///
  /// 🚨[expandedLaneLayerIds] is a widget property: the host mutates its set
  /// and the new value reaches here on the NEXT build, which is a frame too
  /// late for a bulk-drag that started on the twirl itself (the button fires
  /// on the down — 유저 2026-08-30 — and the sweep spreads what it set).
  final bool Function(LayerId layerId)? laneOpenOf;

  /// A LIVE read of a lane GROUP’s switch, when the host can give one — the
  /// one [onToggleLaneGroupEnabled] flips, named by the group’s header (the
  /// Transform group’s flag, an effect’s eyeball); null where the header
  /// names none. A lane row built last frame carries a stale copy.
  ///
  /// ↩️It was asked by the layer alone and answered the TRANSFORM flag for
  /// every group (I-89 ①ⓒ).
  final bool? Function(LayerId layerId, String headerLaneId)? laneGroupOnOf;

  /// A LIVE read of a layer’s own eye — the rail’s bulk-drag needs the value
  /// the press just set, and a captured [Layer] still reports the last
  /// frame.
  final bool Function(LayerId layerId)? layerEyeOnOf;

  /// A LIVE read of a layer’s sheet flag, for the same reason as
  /// [layerEyeOnOf] — the read the session keeps for it
  /// (`isLayerOnTimesheet`).
  final bool Function(LayerId layerId)? layerOnTimesheetOf;

  /// A LIVE read of a layer’s clip to the layer below, for the same reason
  /// as [layerEyeOnOf] — the read the session keeps for it
  /// (`isLayerClipping`).
  final bool Function(LayerId layerId)? layerClipsOf;

  /// A LIVE read of a row's group fold — a folder's, or a base's attach
  /// group — for the same reason as [laneOpenOf]: [collapsedAttachBaseIds]
  /// and the row's layer reach here a build late (`isGroupFoldOpen`).
  final bool Function(LayerId layerId)? groupFoldOpenOf;

  /// A LIVE read of a lane GROUP's twirl, named by the group's header, for
  /// the same reason as [laneOpenOf] (`isLaneGroupOpen`).
  final bool Function(LayerId layerId, String headerLaneId)? laneGroupOpenOf;

  final ValueChanged<LayerId>? onToggleLayerLanes;

  /// The host's lane provider — THE one the display rows were built with.
  /// A lane row re-derives through it when the drag gate hands it a
  /// previewed layer (R10), so the band's keys follow the drag per step
  /// instead of sitting where they were when the row was built.
  final List<PropertyLaneRow> Function(Layer layer)? lanesForLayer;

  /// The union-summary provider (the CAMERA row's key markers, B4) —
  /// resolved per row BUILD, so the drag gate's per-step rebuild re-derives
  /// the union from the session's preview-aware camera track exactly as
  /// [lanesForLayer] re-derives the member lanes. Null = no union overlays.
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

  /// What the legend over the rail is told — the x-sheet's corner the same
  /// ([TimelineGridLegend], F-408 ②).
  final TimelineGridLegend legend;

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

  /// Track-owned rows (the SE rows, the transition row) whose display clone
  /// starts with a block spilling in from an earlier cut, each with how far
  /// into that block the cut starts — both grids read it (UI-R7 #6: the
  /// block's start grip stands down, and an SE row draws `~` at the cut
  /// start; F-113: its waveform starts that far into the sound).
  final Map<LayerId, int> spillInLeadFrames;

  /// The cut the rows are seen in — what an SE block's delivery is read in
  /// ([SeLineTypes.inCut], F-386 · F-496). Null for a grid in no cut.
  final CutId? cutId;

  /// End-line drag hooks (UI-R18 #14): the red cut-end boundary grows a
  /// grip that end-trims the ACTIVE cut through the session's trim
  /// channel; the line follows the live preview. Null = display-only.
  final TimelineCutEndDragCallbacks? cutEndDrag;

  /// #29: the (project, cut) world the rows' resolvers answer from — see
  /// [TimelineRowCellsPainter.substrateGeneration]. Joins the row MEMO key
  /// too: linked cuts can share Layer instances, and a memoized row from
  /// another generation would carry its old token into the tile store's
  /// live-generation tracking.
  final String substrateGeneration;

  /// Identity tokens for the sparse rows' EXTERNAL inputs (UI-R20 #4):
  /// the camera row reads the cut's camera track and instruction rows
  /// read the instruction registry — both outside the Layer value, so
  /// their identities join the memo key and the painter's coverage
  /// ([timelineRowCoverageIdentity]). Hosts pass the live objects; a key
  /// change is exactly an edit. (x-sheet) The sheet was handed none, so a
  /// camera key never redrew its camera column — ㉘ on the timeline only.
  final TimelineRowMemoAux memoAux;

  /// R27 #6: the label's blend-mode dropdown (rightmost column) and the
  /// legend's bulk pick both commit through this.
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;

  /// Whether ANY of [layerId]'s FX apply — [layerFxStateOf]'s answer read
  /// through the one rule ([fxEnabledFromState]); no resolver means on.
  bool isLayerFxEnabled(LayerId layerId) =>
      fxEnabledFromState(layerFxStateOf?.call(layerId));

  /// The lanes [layer]'s header shows — [lanesForLayer]'s answer; none
  /// where the host gives no provider.
  List<PropertyLaneRow> lanesOf(Layer layer) =>
      lanesForLayer?.call(layer) ?? const [];

  /// The optional columns this host's rail carries — each one as far as the
  /// host handed over its verb. Read here once for the rows, the legend,
  /// the swipe and the sheet's header block alike.
  LayerRailOptionalColumns get optionalRailColumns => (
    onion: onToggleLayerOnionSkin != null,
    blend: onLayerBlendModeSelected != null,
  );

  /// The rows a grid shows for [layers]: [buildTimelineDisplayRows] fed the
  /// bundle's own view state — open twirls, hidden sections, the row
  /// filter, folded attach groups, the active layer and the fx predicate —
  /// with the lanes of every open header graph seated in it, the row
  /// selection and the pins told to each seat.
  ///
  /// The rail and the sheet each listed these six hand-offs (the audit's
  /// clone scan, 2026-09-06); a grid that forgot one showed rows the other
  /// hid. What is a surface's own stays a parameter: its lane provider and
  /// which side of the layer its lanes open on ([lanesPrecedeLayer], R9
  /// #23 — the sheet's open LEFTWARD: [laneRunsMovedAhead], laid on the
  /// rows once they are seated).
  List<TimelineDisplayRow> displayRows(
    List<Layer> layers, {
    required List<PropertyLaneRow> Function(Layer layer) lanesForLayer,
    bool lanesPrecedeLayer = false,
  }) {
    final rows = seatLaneGraphs(
      buildTimelineDisplayRows(
        layers: layers,
        expandedLayerIds: expandedLaneLayerIds,
        lanesForLayer: lanesForLayer,
        hiddenSections: hiddenSections,
        rowFilter: rowFilter,
        collapsedAttachBaseIds: collapsedAttachBaseIds,
        activeLayerId: activeLayerId,
        fxEnabledOf: isLayerFxEnabled,
      ),
      laneGraphs,
      selection: selectedRows,
    );
    return lanesPrecedeLayer ? laneRunsMovedAhead(rows) : rows;
  }
}

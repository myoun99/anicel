import 'widgets/empty_state_text.dart';
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/camera_instruction.dart' show CameraInstructionDef;
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/sheet_sources.dart' show sheetPageFramesOf;
import '../models/timeline_row_address.dart';
import '../models/working_panel.dart';
import 'panels/working_panel_surface.dart';
import 'camera/camera_path_settings_rows.dart' show showCameraPathSettings;
import 'timeline/frame_ruler_view.dart';
import 'timeline/layer_link_window.dart';
import 'timeline/layer_reference_popover.dart';
import 'timeline/movie_source_shortfall.dart';
import 'timeline/se_layer_mixer.dart';
import 'brush/transform_tool_options.dart';
import 'editor_command_actions.dart';
import 'editor_session_manager.dart';
import 'range_move_asking_first.dart';
import 'session/session_legend_callbacks.dart';
import 'session/panel_view_memory.dart';
import 'session/session_row_button_presses.dart';
import 'session/tab_rail_wiring.dart';
import 'timeline/session_lane_callbacks.dart';
import 'timeline/timeline_tile_raster_source.dart'
    show timelineSubstrateGeneration;
import 'text/app_strings.dart';
import '../models/timeline_coverage.dart' show TimelineBlockEdge;
import 'timeline/layer_rail_window.dart' show LayerRailExtent, LayerRailId;
import 'timeline/property_lane_model.dart';
import 'timeline/timeline_lane_provider.dart';
import 'timeline/layer_row_drag.dart'
    show TimelineRowDragHooks, timelineRowAddressOfDragSubject;
import 'timeline/timeline_cel_content_source.dart';
import 'timeline/timeline_current_row.dart';
import 'timeline/timeline_cut_end_handle.dart';
import 'timeline/timeline_grid_hooks.dart' show TimelineRowMemoAux;
import 'timeline/instance_editor_commands.dart';
import 'timeline/layer_name_commands.dart';
import 'timeline/timeline_action_toolbar.dart';
import 'timeline/frame_panel_transport.dart' show FramePanelTransport;
import 'timeline/timeline_command_bar.dart' show TimelineCommandBar;
import 'timeline/toolbar_panel_context.dart';
import 'timeline/timeline_frame_range_gesture.dart';
import 'timeline/timeline_run_end_handles.dart';
import 'timeline/timeline_exposure_comma_drag_policy.dart';
import 'timeline/timeline_orientation.dart';
import 'timeline/rail_column_swipe.dart' show RailSweepHistory;
import 'timeline/timeline_panel.dart';
import 'timeline/timeline_section_policy.dart';
import 'timeline/timeline_view_cluster.dart';
import 'timeline/memo_token.dart'
    show ByIdentity, BySet, Kept, keptWhileSame;

/// The Timeline tab's content: the timeline panel with its transport, cell
/// action toolbar and the layer/frame dialogs it triggers. All wiring lives
/// HERE (not in HomePage) so parallel work on other panels stays in other
/// files.
class TimelineTabHost extends StatefulWidget {
  const TimelineTabHost({
    super.key,
    required this.session,
    this.onPlaceMediaAsset,
    this.onPlaceMediaAssetBetweenLayers,
    required this.orientation,
    required this.onOrientationChanged,
    required this.pixelsPerFrame,
    this.pixelsPerFrameListenable,
    required this.onPixelsPerFrameChanged,
    this.onZoomFit,
    required this.rulerView,
    required this.onRulerViewChanged,
    this.timelineRailExtent,
    this.xsheetRailExtent,
    required this.rail,
    this.onRevealOnionSkinPanel,
    this.transformOptions,
  });

  final EditorSessionManager session;

  /// A media-browser row dropped on a drawing layer — the host opens the
  /// place window with the drop's answers filled in. Null leaves the rows
  /// refusing the drag, which is what a surface with nowhere to open a
  /// window should do.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onPlaceMediaAsset;

  /// A media-browser row let go on the LAYER AREA, at the gap [slot] of
  /// [displayLayers] — the host opens the place window for a new layer
  /// there. Null leaves the layer area refusing the drag.
  final void Function(List<Layer> displayLayers, int slot, String path)?
  onPlaceMediaAssetBetweenLayers;
  final TimelineOrientation orientation;
  final ValueChanged<TimelineOrientation> onOrientationChanged;
  final double pixelsPerFrame;

  /// Zoom scoping (UI-R6 #4): when provided, ONLY the panel subtree
  /// rebuilds per zoom step (the workspace shell and this host's build
  /// stay out of the loop). [pixelsPerFrame] is the fallback for hosts
  /// without the notifier.
  final ValueListenable<double>? pixelsPerFrameListenable;
  final ValueChanged<double> onPixelsPerFrameChanged;

  /// The zoom fit (I-111) — the workspace's, which keeps the zoom.
  final VoidCallback? onZoomFit;
  final FrameRulerView rulerView;
  final ValueChanged<FrameRulerView> onRulerViewChanged;

  /// The two grids' rail window sizes (workspace-owned so they survive a
  /// tab switch AND a restart).
  final LayerRailExtent? timelineRailExtent;
  final LayerRailExtent? xsheetRailExtent;

  /// The rail's view and its verbs — the session's, as the conte's tab
  /// takes them ([TabRailWiring]): the lane twirls and their groups, the
  /// header graphs (I-89 ③), the hidden SE / camera sections, the row
  /// filter, the folded attach groups (UI-R20 #9).
  ///
  /// ↩️Each was an argument of its own, defaulting to 「nothing open, no
  /// button」 — a tab only a test ever built (tests-hand-roll-the-tab-hosts).
  /// Where each grid's axes stand is the session's too
  /// ([EditorSessionManager.panelViews], F-143 · F-267), and read there.
  final TabRailWiring rail;

  /// The workspace's onion-panel reveal (UI-R17 #5): open when hidden,
  /// flash-in-place when already open. Null hides the legend entry.
  final VoidCallback? onRevealOnionSkinPanel;

  /// The transform tool's options: a layer's Scale lane links by its
  /// 「배율 연동」, and the chain on that row flips it
  /// ([sessionLaneEditCallbacks]). Null reads the tool's defaults, with no
  /// chain to show.
  final ValueNotifier<TransformToolOptions>? transformOptions;

  @override
  State<TimelineTabHost> createState() => _TimelineTabHostState();
}

class _TimelineTabHostState extends State<TimelineTabHost> {
  EditorSessionManager get _session => widget.session;

  /// Where each grid's axes stand — the project's, saved with it (F-267),
  /// and held above the grids so a fold keeps them (F-143).
  PanelViewMemory get _axes => _session.panelViews;

  // ⛔The frame cursor the panel's cursor-driven widgets subscribe to
  // (playhead, rulers, lane values) is the SESSION's now
  // ([PlayheadCursors.cutFrame]): the row this panel folds into follows the
  // same one, and that row is built by the workspace, which could not reach
  // a cursor kept here (유저 2026-09-27,
  // folded-row-playhead-during-playback-Q1).

  /// Everything that can change whether a frame reads as CACHED: frames
  /// warming in, and pixel edits invalidating composites. The rulers' green
  /// bar re-reads on this instead of comparing a token — cached-ness is
  /// derived state (composites self-validate by signature), so there is no
  /// token to compare. Built once: a fresh merge per build would make the
  /// painters re-subscribe on every rebuild.
  /// R26 #44: the unworked-block tint's fact and its event, bound once —
  /// a fresh bundle per build would re-subscribe the row painters on every
  /// pass and defeat their repaint gating.
  late final TimelineCelContentSource _celContent = TimelineCelContentSource(
    hasContent: _session.layerStack.celHasContentForLayer,
    cannotRead: _session.layerStack.celCannotBeReadForLayer,
    revision: _session.layerStack.celTintRevision,
  );

  late final Listenable _frameReadySignal = Listenable.merge([
    _session.playbackRig.prerenderScheduler.progress,
    _session.renderCaches.brushFrameStore.celPixelRevision,
  ]);

  /// P2b: the rail row IS the handle. Pen and mouse move it; a finger
  /// scrolls, because the rail scrolls along the very axis this drag runs.
  ///
  /// 🚨Bound ONCE, like the sources above (F-244): the rail keeps each row's
  /// drag wrapper across an edit only while this is the same object — a
  /// fresh set per build rebuilt every row's wrapper at every commit (~170
  /// elements on 24 rows). Nothing in it reads the build it was made in: the
  /// verbs are the session's, and the closures ask the session at the event.
  late final TimelineRowDragHooks _rowDragHooks = TimelineRowDragHooks(
    drag: _session.layerRowDragVerbs.inFlight,
    onBegin: _session.layerRowDragVerbs.beginLayerRowDrag,
    onUpdate: _session.layerRowDragVerbs.updateLayerRowDrag,
    onRowTarget: _session.layerRowDragVerbs.updateLayerRowDropOnRow,
    onEffectUpdate: _session.layerRowDragVerbs.updateEffectRowDrag,
    onEnd: _session.layerRowDragVerbs.endLayerRowDrag,
    onCancel: _session.layerRowDragVerbs.cancelLayerRowDrag,
    // A file from the pool over the layer area raises the caret a
    // moved row does (「레이어 영역(가로선) → 새 레이어」) AND the
    // row it would make, standing in that gap (라운드 2d 2부).
    // ⛔One verb, not two hooks: the line and the row are one
    // answer, and a surface that raised only one of them would be
    // showing half of what the release does.
    onPlacementHover: _session.showLayerPlacement,
    onPlacementLeave: _session.clearLayerPlacement,
    acceptsPlacement: (displayLayers, slot, path) =>
        _session.layerSlotSpotFor(displayLayers, slot, path) != null,
    // ⑨: the first drag SELECTS, and a drag that starts INSIDE the
    // selection moves it — the cells' grammar, transposed.
    //
    // 🚨T5 (유저 2026-08-13): 「모든 셀은 선택범위 자유롭게 규칙없이
    // 가능하듯이 **모든 행은 자유롭게 규칙없이 선택가능.** 지금 fx랑
    // fx멤버가 선택범위 안됨」 — and on the fx header's chain drag
    // specifically: 「셀과 같은문법으로 통일」.
    //
    // ⛔The old answer here was `null` for every subject that is not
    // a layer row, which this file called "not a row selection's
    // business". That was a KIND deciding whether a row may be
    // selected, and the whole of ③/⑨'s law is that kind decides
    // what an edit DOES, never whether the row can be named.
    //
    // The chain drag is not lost by this: it is the second phase
    // now, exactly as a layer row's move is. Start outside the
    // selection and the drag selects; start inside it and the drag
    // re-orders the chain.
    isInRowSelection: (subject) =>
        _session.rowSelectionVerbs.rowIsSelected(
          timelineRowAddressOfDragSubject(subject),
        ),
    onSelectBegin: (subject) => _session.rowSelectionVerbs.beginRowSelection(
      timelineRowAddressOfDragSubject(subject),
    ),
    onSelectEnd: _session.rowSelectionVerbs.endRowSelection,
    // I-39: what a picked-up row carries, named at the pointer.
    rowsActedOnBy: _session.rowSelectionVerbs.rowsActedOnBy,
  );

  /// Every kind's twirl-down lanes — the SAME AE Transform lanes on truly
  /// every layer (unified layer controls): the camera rides the cut camera
  /// track, every other kind its own layer track (applied at composite
  /// time; SE transforms move the canvas dialogue, instruction transforms
  /// are authored state for parity). SE layers lead with their 「오디오」
  /// group.
  /// R26 #3: maps a lane select-drag's cross-row delta onto the layer's
  /// DISPLAYED lane list (the same one the grids render) and returns the
  /// A plain tap on a property band: STAND there (R10).
  ///
  /// The user's rule when this was settled: wherever frame cells exist the
  /// playhead can be put, with no exceptions — and a lane band was the one
  /// place with visible cells that refused it, because the seek lived on
  /// the cell WIDGET and a band paints its cells.
  ///
  /// It still takes the lane's owner as the ACTIVE layer, but that no
  /// longer means you can draw (2026-08-08). Standing on a property is
  /// standing on a property; the canvas refuses strokes until you step
  /// back onto a row that is a surface. The active layer is what you
  /// return TO — pressing the layer's own row is one tap away.
  /// T4: through [EditorSessionManager.standOnRow], which is where 「어떤
  /// 행이든 액티브 바꾸면 선택이 풀린다」 lives now. This used to clear the
  /// LANE selection alone and reach for the session directly, so standing on
  /// a property row left a cell or row selection standing — 유저 2026-08-13:
  /// 「트랜스폼 멤버 행 액티브로하면 안풀림」.
  void _standOnLane(LayerId layerId, String laneId, int frameIndex) {
    _session.standOnRow(
      LaneRowAddress(layerId, laneId),
      frameIndex: frameIndex,
    );
  }

  /// The LABEL half of the same rule: pressing a lane's name stands on it,
  /// exactly as the layer row's name selects its layer. No seek — a label
  /// names a ROW, and the frame stays where it was.
  void _standOnLaneRow(LayerId layerId, String laneId) {
    _session.standOnRow(LaneRowAddress(layerId, laneId));
  }

  // ⛔The host's own lane-span head walk is GONE (C②): the grid resolves
  // the head lane off the display rows it draws, so a hand-kept lane list
  // here could only ever drift from them — which is exactly what happened
  // on the storyboard host's copy.

  /// R10 moved the lane list out to [timelineLanesForLayer] — the ↑/↓ row
  /// nav needs the same answer, and a second copy would have drifted from
  /// what the grids draw.
  List<PropertyLaneRow> _lanesForLayer(Layer layer) => timelineLanesForLayer(
    layer: layer,
    session: _session,
    expandedGroupKeys: widget.rail.expandedLaneGroupKeys,
  );

  /// The CAMERA row's union summary (B4): the shared transform-header union
  /// lane, re-derived per row rebuild from the session's preview-aware
  /// camera track.
  ///
  /// A method, as the term lookup below is: a kept cells row holds its
  /// resolvers by equality ([TimelineCellsRowFacts]), and a closure built
  /// per pass would build every row again at every pass (I-57, 10-13).
  PropertyLaneRow? _cameraUnionLane(Layer layer) =>
      timelineCameraUnionLane(layer: layer, session: _session);

  /// The term a CAM row's chip names, from the registry as it stands.
  CameraInstructionDef? _instructionDefById(String instructionId) =>
      _session.camera.cameraInstructionSet.defById(instructionId);

  // ⛔THE HOST'S LANE-EDIT BODIES ARE GONE (F-102, 2026-09-15). The key
  // toggle, the typed value and the effect eyeball are [LaneVerbs]' now, for
  // this panel and the storyboard alike. They read the row the host was
  // SHOWN — for a track-SE row, the cut-local clone — and put the edit back
  // through the cut window (R5 #8, which is still why an SE row keys at all:
  // it once showed lanes and refused every key). The clone had dropped every
  // key made in an earlier cut, so keying S1 in cut 2 erased cut 1's key.
  // The verbs read the row the project holds, at the frame on its own axis.

  // A folder's FX lanes used to need their own routing here: the lane id
  // carried a `folder-fx:<folderId>` ADDRESS because the carrier layer on
  // those rows was only a representative member, and the commit had to
  // reach a folder table the layer path could not see. A folder is a layer
  // now — the carrier IS the folder, so every lane edit below takes the
  // one path.

  // ↩️The callbacks' body is [sessionLaneEditCallbacks] (F-101): the
  // storyboard's S rows take the same one, on their own axis.
  PropertyLaneEditCallbacks get _laneEdit => sessionLaneEditCallbacks(
    _session,
    frameIsGlobal: false,
    transformOptions: widget.transformOptions,
  );

  // ⛔The two LAYER dialogs left this host (2026-08-10): the layer pill is
  // mounted on the storyboard's bar too now, and nothing in either flow was
  // ever about the timeline. See [layer_name_commands.dart].

  // ⛔THE INSTANCE EDITOR left this host (2026-08-11). Every flow it held —
  // the kind dispatch, the camera keys, the SE entry, the
  // instruction event and its vocabulary editor, the frame rename and the
  // lane-key rename — is [instance_editor_commands.dart] now, because the
  // storyboard's bar carries the same `Edit Instance` entry and had to grey
  // it out for want of a way to reach them. Nothing in the dispatch was ever
  // about the timeline; the one thing a host still decides is the preview
  // axis, and it passes that.

  /// Toolbar 'Add' — kind-dispatched creation. NO dialogs anywhere
  /// (UI-R25 #2, 조작 통일화): SE/instruction create a DEFAULT instance
  /// directly — the Edit Instance button / double-tap edits it after.
  /// A live selection fills the WHOLE selection instead (UI-R25 #3):
  /// anywhere selectable creates — drawing gaps, SE gaps, instruction
  /// gaps, camera keys, lane keys.
  void _createActiveInstance() => createActiveInstance(_session);

  /// The preview inside the instance dialogs follows the visible
  /// orientation (Axis policy in miniature).
  Axis get _previewAxis => widget.orientation.axis;

  Future<void> _activateCellEditor(LayerId layerId, int frameIndex) =>
      activateCellOnDoubleTap(
        context,
        _session,
        layerId: layerId,
        frameIndex: frameIndex,
        previewAxis: _previewAxis,
      );

  /// I-48: a double click on a row's label renames the rows its first
  /// press acted on.
  VoidCallback _renameOnLabelDoubleClick(LayerId pressed) =>
      renameOnLabelDoubleClick(context, _session, pressed);

  /// 🚨T25 — the SELECTION's instance, not the playhead's.
  ///
  /// The button moved to the shared pill, so its subject moved with it:
  /// 「인스턴스 편집 버튼도 공통버튼으로 이동. 그래서 **선택범위 통해
  /// 동사통일화** 가능하게」. `editSelectionInstance` walks delete's ladder
  /// and falls through to the playhead's cell when nothing is selected,
  /// which is what this used to do unconditionally.
  ///
  /// F-261: through [editOnPanel], the door its key opens too.
  Future<void> _editActiveInstance() => editOnPanel(
    context,
    _session,
    panel: TimelineToolbarPanelContext(_session, waitIn: context),
    previewAxis: _previewAxis,
  );

  /// How many steps on the playing run shows the active cut's frame
  /// [frame] ([PlaybackRig.stepsUntilShown]) — the grids' frames are the
  /// cut's own. A method, so the rows kept across builds ask one answer.
  int? _stepsUntilShown(int frame) {
    final cutId = _session.activeCutId;
    return cutId == null
        ? null
        : _session.playbackRig.stepsUntilShown(cutId, frame);
  }

  /// The end-line drag's session hooks (UI-R18 #14): the boundary grip
  /// end-trims the ACTIVE cut through the storyboard's trim channel.
  /// Null while no cut is active (gap parking) — the line stays static.
  TimelineCutEndDragCallbacks? _cutEndDragCallbacks() {
    final cutId = _session.activeCutId;
    if (cutId == null) {
      return null;
    }
    return TimelineCutEndDragCallbacks(
      cutId: cutId,
      onBegin: () =>
          _session.edgeDrag.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end),
      onUpdate: _session.edgeDrag.updateCutEdgeDrag,
      onEnd: _session.edgeDrag.endCutEdgeDrag,
      onCancel: _session.edgeDrag.cancelCutEdgeDrag,
    );
  }

  /// The layer stack as the GRIDS should render it — display clones for
  /// the rows whose cells are not their own.
  ///
  /// R10 puts the folder band here, which is the one seam both grids read:
  /// the X-sheet has always sent folder columns to the shared cells row
  /// and drawn them blank, so the clone lights that column with no X-sheet
  /// edit at all. Same rule the SE clones live under — it never leaves the
  /// display path, because commands re-read the real layer by id.
  ///
  /// ↩️The camera row was cloned here too, wearing the window's camera view
  /// on its eye, until its eye became its own (F-363).
  List<Layer> _displayLayers() => [
    for (final layer in _session.layers)
      if (layer.kind.groupsLayers)
        _session.folderBands.folderBandLayerFor(layer)
      else
        layer,
  ];

  /// The rail rows' buttons as a press asks them — spread over the row
  /// selection when the pressed row is in it.
  SessionRowButtonPresses get _rowPresses => SessionRowButtonPresses(_session);

  /// The pages of the open cut's X-sheet — where the page view's rulers
  /// start again (I-81); null with no cut open.
  TimelineRulerPages? get _sheetPages => switch (_session.activeCutOrNull) {
    null => null,
    final cut => TimelineRulerPages.every(
      sheetPageFramesOf(
        cut,
        _session.projectSettings.projectFrameRate.countingBase,
      ),
    ),
  };

  @override
  Widget build(BuildContext context) => RailSweepHistory(
    history: _session.historyManager.gestures,
    changed: _session.notifyChanged,
    child: _panel(context),
  );

  Widget _panel(BuildContext context) {
    // Playback ticks flow into the frame cursor ([PlayheadCursors]) —
    // NEVER as a panel rebuild: only the cursor-driven widgets (playhead
    // layer, rulers, lane values, counter) subscribe, so the grids'
    // hundreds of cells stay untouched frame to frame. The prerender
    // progress listenable repaints the rulers' green bars the same way.
    //
    // Touching this panel makes it the one the frame-axis verbs answer to
    // (user, 2026-08-05). A row pick is no longer the only way to move the
    // flip's subject — working here at all is, which is what picking up a
    // panel actually feels like. Putting it away hands the work on to the
    // storyboard when that is on the screen (user, 2026-09-25).
    return WorkingPanelSurface(
      onTouch: _session.claimTimelineRow,
      onSight: (surface, {required inSight}) => _session.panelInSight(
        WorkingPanel.timeline,
        surface: surface,
        inSight: inSight,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          // Live take preview (REC1-C): the armed SE lane swaps identity at
          // most once per FRAME while recording — this panel-scoped rebuild
          // is the notify-free channel (R12-B: ticks never notify the
          // session).
          _session.voiceRecording.voiceRecordPreviewLane,
          // R27 #13: the empty-cel tint must clear the INSTANT a stroke
          // lands. Cel pixels live outside the Layer value, so nothing in
          // the ordinary notify path told this panel to look again — the
          // tint sat until an unrelated rebuild. Only EMPTY↔drawn crossings
          // bump this, so ordinary strokes cost nothing.
          _session.renderCaches.brushFrameStore.celContentRevision,
          // ⑨: the row selection grows PER POINTER MOVE inside a gesture,
          // which is exactly the contract the session's own notify does not
          // have (a drag is silent until release). Its notifier is the
          // channel, the same way the current row's is.
          _session.rowSelection,
        ]),
        builder: (context, _) {
          // Zoom scoping (UI-R6 #4): the toolbar widget is built ONCE per
          // host rebuild and reused across zoom steps — the identical
          // instance lets its ~25 buttons skip rebuilding while the
          // ValueListenableBuilder below re-lays-out just the panel. The
          // transport beside it, likewise.
          final timelineToolbar = _buildTimelineToolbar();
          final timelineTransport = _buildTimelineTransport();
          Widget buildPanel(
            BuildContext context,
            double pixelsPerFrame,
            Widget? child,
          ) => TimelinePanel(
            layers: _displayLayers(),
            activeLayerId: _session.activeLayerId,
            // #29: the (project, cut) world the rows' resolvers answer
            // from. Travels WITH the rebuild that carries the new cut's
            // rows — a setter could skew from what is on screen; a build
            // argument cannot.
            substrateGeneration: timelineSubstrateGeneration(
              projectId: _session.repository.requireProject().id.value,
              cutId: _session.activeCutId?.value,
            ),
            // ⑨: the rows the row verbs act on, banded on both surfaces.
            //
            // 🚨T1: ADDRESSES, not layer ids. T5 made every row kind
            // selectable, and a `Set<LayerId>` cannot spell a lane or an fx
            // header — the same shape of loss ③ found in the span itself.
            selectedRows: _session.rowSelection.value.toSet(),
            // Edit drags (comma/trim) preview through the scoped channel: a
            // step rebuilds the dragged row's gate + the cursor overlay only,
            // never this host (the release commit is the one session notify).
            dragPreview: _session.dragPreview,
            frameCursor: _session.playheadCursors.cutFrame,
            frameReadySignal: _frameReadySignal,
            revealSelectionTick: _session.rangeSelections.revealSelectionTick,
            // F-110: the page-turn tick. This is the same listenable
            // [PlayheadCursors.cutFrameNow] reads playback out of — null while
            // nothing plays, which is what keeps a keyboard walk on the walk
            // law.
            playbackFrame:
                _session.playbackRig.playback.globalFrameIndexListenable,
            stepsUntilShown: _stepsUntilShown,
            readyRunsIn:
                _session.playbackRig.playbackCache.playbackReadyRuns,
            playbackFrameCount:
                _session.activeCutSpan.activeCutPlaybackFrameCount,
            // The のりしろ: how far past the cut's end line it is DRAWN, and
            // the word the ruler spells across that. Same derivation the
            // sheet pages by, so the two cannot disagree — ASKED by each
            // surface wherever it hears a drag, which this host never
            // rebuilds for.
            noriShiro: _session.activeCutSpan.activeCutNoriShiro,
            exposureStateForLayer: _session.exposureStateForLayer,
            frameNameForLayer: _session.frameVerbs.frameNameForLayer,
            // R26 #44: ACTION-section blocks whose cel is still blank gray
            // their paper; the token keys the row memo (cel pixels live
            // outside the Layer value).
            celContent: _celContent,
            // A CLICK CLEARS (유저 확정) — and T4 moved that law OUT of this
            // wrapper into [EditorSessionManager.standOnRow], because a
            // wrapper only covers the doors that go through it. Standing on a
            // property lane went straight to the session and kept its
            // selection, and the next new door would have done the same.
            //
            // A claimed pan never reaches this callback, which is what keeps
            // the move-from-inside drag working.
            onSelectLayer: (layerId) =>
                _session.standOnRow(LayerRowAddress(layerId)),
            labelDoubleClick: _renameOnLabelDoubleClick,
            // Ruler scrubs during playback SEEK the playback clock instead of
            // moving the (hidden) editing playhead.
            onSelectFrame: (frameIndex) {
              if (_session.playbackRig.playback.isActive) {
                _session.playbackRig.playback.seekToLocalFrame(frameIndex);
              } else {
                _session.selectFrameIndex(frameIndex);
              }
            },
            // 🚨T10's second half (유저: 「클릭하고 떼면 뭐든 비우게」). The
            // press picks and may deliberately hold the selection — it could
            // be the start of a move — so something has to clear when the
            // press turns out to have been a tap. This is that something,
            // and it is the same verb for the cells and the rail rows.
            // ⛔The timeline's selections, not the marquee (F-86 — moving
            // the playhead is not putting the selection tool down).
            onSettledPress: _session.clearTimelineSelections,
            // Ruler drags: per-move seeks ride the cursor path (value-only —
            // the playhead and the canvas preview follow, nothing rebuilds);
            // the release commits the selection as ONE ordinary seek.
            onScrubFrame: (frameIndex) {
              if (_session.playbackRig.playback.isActive) {
                _session.playbackRig.playback.seekToLocalFrame(frameIndex);
              } else {
                _session.frameScrub.scrubFrameIndex(frameIndex);
              }
            },
            onScrubEnd: () {
              if (!_session.playbackRig.playback.isActive) {
                _session.frameScrub.commitFrameScrub();
              }
            },
            // End-line drag = cut length (UI-R18 #14): the boundary grip
            // end-trims the ACTIVE cut through the storyboard's trim
            // channel — live preview, ONE undo on release.
            cutEndDrag: _cutEndDragCallbacks(),
            // Sparse-row memo identities (UI-R20 #4): camera/instruction
            // rows re-enter the row memo, invalidated exactly by these.
            memoAux: TimelineRowMemoAux(
              cameraTrack: _session.activeCutOrNull?.camera.track,
              instructionDefs: _session.camera.cameraInstructionSet,
            ),
            onActivateCell: _activateCellEditor,
            instructionDefById: _instructionDefById,
            // D26: the crossing-fade refusal marker — this surface shows
            // the cut-local display clone, so the session answers by the
            // clone's PROJECTED keys. Always-on (a refusal warning takes
            // no settings gate).
            instructionCrossingTooltip:
                _session.transitions.transitionCrossingWarningInCutAt,
            // Display resolver: the live take's sentinel path maps to the
            // growing envelope (REC1-C), everything else to the conform
            // store's peaks.
            audioPeaksFor: _session.voiceRecording.audioPeaksForDisplay,
            soundCannotPlay: _session.playbackRig.soundCannotPlay,
            // The tooltip string doubles as the marker switch (REC1-D):
            // null while the clipping notice is off.
            seClipMarkerTooltip: _session.appSettings.audioSyncSettings.value.clippingNotice
                ? _session.uiStrings.recordClipMarkerTooltip
                : null,
            onDropMediaAssetOnLayer: widget.onPlaceMediaAsset,
            // The same question the drop's door asks, asked while the file
            // only hovers — so the chip wears the answer before the release.
            acceptsMediaAssetOnLayer: (layerId, frameIndex, path) =>
                _session.dropSpotFor(layerId, frameIndex, path) != null,
            // And what that landing would MAKE, drawn where it would make
            // it (미디어 배치 라운드 2d 2부). The verb asks the same door
            // again rather than being told the answer: 그려지는 것과 놓았을
            // 때 생기는 것이 한 질문에서 나온다.
            onHoverMediaAssetOnLayer: _session.showMediaPlacement,
            onLeaveMediaAssetOnLayer: _session.mediaPlacement.clear,
            onDropMediaAssetBetweenLayers:
                widget.onPlaceMediaAssetBetweenLayers,
            // A sound dropped on an SE block — the storyboard's S rows take the
            // same wiring (F-101).
            onDropMediaAssetOnSeBlock: sessionSeBlockDrop(_session),
            onAddLayer: _session.layerStack.addLayer,
            isLayerSoloed: (layerId) => _session
                .visibilitySolo
                .soloedSeLayerIds
                .value
                .contains(layerId),
            onOpenLayerMixer: (anchorContext, layerId) => unawaited(
              showSeLayerMixer(
                anchorContext,
                session: _session,
                layerId: layerId,
              ),
            ),
            onOpenLayerReference: (anchorContext, layerId) =>
                showLayerReferencePopover(
                  anchorContext,
                  session: _session,
                  layerId: layerId,
                ),
            onOpenLayerLinks: (anchorContext, layerId) => showLayerLinkWindow(
              anchorContext,
              session: _session,
              layerId: layerId,
            ),
            onOpenCameraPath: (anchorContext) => showCameraPathSettings(
              anchorContext,
              _session.appSettings.setCameraPathSettings,
            ),
            // ONE law, two readers: the rail asks whether to go red, the
            // popover asks by how much, and both get the answer from
            // [movieSourceShortfall].
            layerSourceIsShortOf: (layerId) {
              final layer = _session.layerById(layerId);
              return layer != null && movieSourceShortfall(_session, layer) > 0;
            },
            onToggleLayerVisibility: _rowPresses.toggleVisibility,
            onLayerOpacityChanged: _rowPresses.previewOpacity,
            onLayerOpacityChangeEnd: _rowPresses.commitOpacity,
            onToggleLayerTimesheet: _rowPresses.toggleTimesheet,
            onToggleLayerClip: _rowPresses.toggleClip,
            onLayerMarkSelected: _rowPresses.pickMark,
            // The AE-style fx MASTER over the row's per-group switches (R8:
            // model state, read straight off the layer).
            layerFxStateOf: _session.effectsAndFx.layerFxState,
            layerLinkPartnersOf: _session.layerVerbs.linkPartnersOf,
            // Folder rows are layer rows: their eye, opacity, blend, fx
            // switch, FX lanes and selection all ride the layer hooks
            // already threaded above. Only the members' twirl lands here.
            onToggleLayerCollapsed: _rowPresses.toggleGroupFold,
            onToggleLayerFx: _rowPresses.toggleFx,
            // Per-layer onion skin (UI-R17 #5, TVPaint style).
            layerOnionSkinEnabledOf: _session.onionSkin.isLayerOnionSkinEnabled,
            onToggleLayerOnionSkin: _rowPresses.toggleOnionSkin,
            displayedOnionSkinOn: _session.onionSkin.displayedLayersOnionSkinEnabled,
            // Comma edge drags preview live from the session's drag-start
            // snapshot and commit as ONE undo entry on release.
            commaDrag: TimelineCommaDragCallbacks(
              onBegin: (layerId, blockStartIndex, edge) =>
                  _session.edgeDrag.beginCutRowEdgeDrag(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    edge: edge,
                  ),
              onUpdate: _session.edgeDrag.updateCutRowEdgeDrag,
              onEnd: _session.edgeDrag.endCutRowEdgeDrag,
              onCancel: _session.edgeDrag.cancelCutRowEdgeDrag,
            ),
            // TVP-style frame ranges (UI-R8): a cell drag SELECTS a range
            // (block-snapped), a drag starting inside the selection MOVES it
            // — the block-body immediate move's successor, same live-preview
            // + one-undo discipline.
            rangeHooks: TimelineFrameRangeHooks(
              selection: _session.frameRangeSelection,
              onSelectUpdate:
                  (
                    layerId,
                    anchorIndex,
                    headIndex, {
                    headLayerId,
                    spanRows = const [],
                  }) => _session.updateFrameRangeSelectionDrag(
                    layerId: layerId,
                    anchorIndex: anchorIndex,
                    headIndex: headIndex,
                    headLayerId: headLayerId,
                    spanRows: spanRows,
                  ),
              onClear: _session.clearFrameRangeSelection,
              move: TimelineRangeMoveCallbacks(
                holds: _session.rangeMove.grabHolds,
                onBegin: _session.rangeMove.beginFrameRangeMoveDrag,
                onUpdate: ({required frameDelta, targetLayerId}) =>
                    _session.rangeMove.updateFrameRangeMoveDrag(
                      frameDelta: frameDelta,
                      targetLayerId: targetLayerId,
                    ),
                onEnd: () => unawaited(
                  releaseRangeMoveAskingFirst(context, _session),
                ),
                onCancel: _session.rangeMove.cancelFrameRangeMoveDrag,
              ),
            ),
            // The LANE selection domain (UI-R23 #3 part 2; MULTI-LANE since
            // R26 #3): a lane-band pan selects lane rows — the cross-row
            // delta spans the layer's lane group like cells span layers,
            // the group header anchors the WHOLE group — and a pan inside
            // the selection moves every spanned lane's keys. Frame
            // selection ⊥ transform keys, mutually exclusive domains.
            laneRange: TimelineLaneRangeHooks(
              // This panel is a CUT's window. A track-owned SE row's span
              // is stated on the track's global axis, so what this rail
              // shows — and reads at press to pick its mode — is the part
              // of it that falls inside the window, on the window's own
              // numbers.
              selection: _session.cutLocalLaneRangeSelection,
              // C②: the span arrives resolved by the grid, off the rows it
              // actually draws — the host's own lane-list walk retired with
              // it.
              onSelectUpdate:
                  (layerId, laneId, anchorIndex, headIndex, span) =>
                      _session.updateLaneRangeSelectionDrag(
                        layerId: layerId,
                        laneId: laneId,
                        anchorIndex: anchorIndex,
                        headIndex: headIndex,
                        spanLaneIds: span,
                      ),
              onTapAt: _standOnLane,
              // 유저 2026-09-11: 「트랜스폼행에서 더블클릭으로 편집창
              // 안열리는것등 이런거 싹 법 하나로 통일」 — the cells' double
              // tap, on a lane. The first tap already stood here.
              onActivateAt: (layerId, laneId, frameIndex) =>
                  _activateCellEditor(layerId, frameIndex),
              // H18: the cells family's release rule, on lanes too — a press
              // that turned out to be a tap takes its anchor span back
              // instead of leaving a one-cell band behind.
              onTapClear: _session.clearLaneRangeSelection,
              onCreateKeys: _session.cellInstances.createInstancesForSelection,
              onMoveBegin: _session.laneMove.beginLaneRangeMoveDrag,
              onMoveUpdate: (frameDelta, {stretch, values, landings}) =>
                  _session.laneMove.updateLaneRangeMoveDrag(
                    frameDelta: frameDelta,
                    stretch: stretch,
                    values: values,
                    landings: landings,
                  ),
              onMoveEnd: _session.laneMove.endLaneRangeMoveDrag,
              onMoveCancel: _session.laneMove.cancelLaneRangeMoveDrag,
            ),
            // R10 #19's rail half: the row you are standing on is DRAWN,
            // and a lane's label is a place you can stand.
            currentRowHooks: TimelineCurrentRowHooks(
              currentRow: _session.standing.currentRowListenable,
              onStandOnLane: _standOnLaneRow,
              onSettledPress: _session.clearTimelineSelections,
            ),
            rowDragHooks: _rowDragHooks,
            onRowSelectionSpan: _session.rowSelectionVerbs.updateRowSelection,
            // The TVP run-edge cluster (UI-R9 #10): [+] drags new one-frame
            // drawings onto a run; the property tag sets the edge's
            // None/Hold/Repeat mode (ghosts fill to the cut boundary).
            runEdit: TimelineRunEditCallbacks(
              onAddBegin: (layerId, blockStartIndex, {required atEnd}) =>
                  _session.runFramesAdd.beginRunFramesAddDrag(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    atEnd: atEnd,
                  ),
              onAddUpdate: _session.runFramesAdd.updateRunFramesAddDrag,
              onAddEnd: _session.runFramesAdd.endRunFramesAddDrag,
              onAddCancel: _session.runFramesAdd.cancelRunFramesAddDrag,
              onEdgeModeSelected:
                  (
                    layerId,
                    blockStartIndex,
                    side,
                    mode, {
                    scopeToSelection = false,
                  }) => _session.rangeMove.setRunEdgeBehavior(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    side: side,
                    mode: mode,
                    scopeToSelection: scopeToSelection,
                  ),
              // The flyout's "Repeat selection" entry gates on this
              // (UI-R19 #2).
              canScopeToSelection: (layerId, blockStartIndex, side) =>
                  _session.canScopeRepeatToSelection(
                    layerId: layerId,
                    blockStartIndex: blockStartIndex,
                    side: side,
                  ),
            ),
            orientation: widget.orientation,
            onOrientationChanged: widget.onOrientationChanged,
            pixelsPerFrame: pixelsPerFrame,
            onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
            onZoomFit: widget.onZoomFit,
            rulerView: widget.rulerView,
            sheetPages: _sheetPages,
            onRulerViewChanged: widget.onRulerViewChanged,
            timelineRailExtent: widget.timelineRailExtent,
            xsheetRailExtent: widget.xsheetRailExtent,
            timelineFrameAxisOffset:
                _axes.frameAxisOffsets[LayerRailId.timeline],
            xsheetFrameAxisOffset: _axes.frameAxisOffsets[LayerRailId.xsheet],
            timelineLayerAxisOffset:
                _axes.layerAxisOffsets[LayerRailId.timeline],
            xsheetLayerAxisOffset: _axes.layerAxisOffsets[LayerRailId.xsheet],
            projectFrameRate: _session.projectSettings.projectFrameRate,
            expandedLaneLayerIds: widget.rail.expandedLaneLayerIds,
            laneGraphs: widget.rail.laneGraphs,
            laneGraphVerbs: widget.rail.laneGraphVerbs,
            // Live, for the reason the twirls' read below is.
            laneGraphsNow: () => _session.railView.laneGraphs.value,
            laneGraphLineOf: (key) =>
                timelineLaneGraphLine(key, session: _session),
            // LIVE, as the hook asks: the widget's set is the one this build
            // was handed — so a sweep that toggles row after row inside one
            // frame (the legend's 「all」, or a press spread across the
            // selection) read every row it had already turned as still
            // unturned. ↩️It read the session's set, which a twirl replaced
            // at once until the twirl was the row's (F-360): the set is read
            // back off the document when a step lands, and the legend's
            // 「all」 is one step.
            laneOpenOf: _session.layerSwitches.isLayerLanesOpen,
            laneGroupOnOf: _session.laneVerbs.isLaneGroupOn,
            layerEyeOnOf: _session.layerSwitches.isLayerEyeOn,
            layerOnTimesheetOf: _session.layerSwitches.isLayerOnTimesheet,
            layerClipsOf: _session.layerSwitches.isLayerClipping,
            groupFoldOpenOf: _session.layerSwitches.isGroupFoldOpen,
            laneGroupOpenOf: _session.layerSwitches.isLaneGroupOpen,
            onToggleLayerLanes: widget.rail.toggleLayerLanes,
            hiddenSections: widget.rail.hiddenSections,
            onToggleSection: widget.rail.toggleSection,
            rowFilter: widget.rail.rowFilter,
            onSetRowFilter: widget.rail.setRowFilter,
            collapsedAttachBaseIds: widget.rail.collapsedAttachBaseIds,
            onToggleAttachGroup: widget.rail.toggleAttachGroup,
            visibilitySoloEnabled: _session.visibilitySolo.layerVisibilitySoloEnabled,
            // Master-bar drags (UI-R6 #2): rows' sliders follow the preview
            // channel live; at rest the bar shows the last committed value.
            opacityDragPreview: _session.opacityVerbs.dragPreview,
            masterOpacityValue: _session.opacityVerbs.lastMasterOpacity,
            // R27 #6: the blend mode reads and commits from the LABEL now.
            onLayerBlendModeSelected: _rowPresses.pickBlendMode,
            // Blocks carrying over from the previous cut (UI-R7 #6): the
            // spill block's start grip stands down, a sound's cut start
            // draws `~` and its waveform starts that far in (F-113) — and
            // the transition row's mark answers the same way.
            spillInLeadFrames:
                _session.activeCutSpan.activeCutSpillInLeadFrames,
            // Where a track SE block reads its delivery (F-496).
            cutId: _session.activeCutId,
            // The rail legend's bulk sweeps + the section brackets' flyout —
            // all session-backed (R-toolbar round); the R2 filter/dim/opacity
            // facets ride the same struct.
            // What its legend opens, for a key on this panel (I-40).
            legendHand: _session.railLegends.handOf(WorkingPanel.timeline),
            legend: sessionLegendCallbacks(
              _session,
              rowFilter: widget.rail.rowFilter,
              onSetRowFilter: widget.rail.setRowFilter,
              onRevealOnionSkinPanel: widget.onRevealOnionSkinPanel,
            ),
            lanesForLayer: _lanesForLayer,
            unionLaneForLayer: _cameraUnionLane,
            laneEdit: _laneEdit,
            // A group header's twirl (AE collapse) — Transform or one of the
            // row's effects, told apart by the lane the tap carries.
            onToggleLaneGroup: (layer, lane) => widget.rail.toggleLaneGroup(
              laneGroupKey(layer.id, lane.laneId),
            ),
            // R6: the per-effect eyeball on an effect's header row. One undo
            // step through the ordinary effect-chain commit.
            // ↩️R8's transform switch and this eyeball are one verb since
            // F-101 — the storyboard's S rows press it too.
            onToggleLaneGroupEnabled: (layer, lane) =>
                _session.laneVerbs.toggleLaneGroupEnabled(
                  layer.id,
                  lane.laneId,
                  description: 'Toggle ${lane.label}',
                ),
            // R5: AE's group Reset. The session owns the scope rule (the
            // playhead, or a live lane range's keys) so both grids and the
            // storyboard ask the same question.
            onResetLaneGroup: (layer, lane) =>
                _session.laneVerbs.resetLaneGroup(layer.id, lane.laneId),
            transport: timelineTransport,
            cutName: _session.cutUnderPlayhead.cutName,
            timelineActionToolbar: timelineToolbar,
          );
          // The GAP empty state (UI-R9 #3): no cut selected — no rows, no
          // grid; the toolbar stays (its cut-scoped commands disable via
          // their own enablement gates).
          if (_session.activeCutOrNull == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 🚨The SAME bar the panel wears ([TimelineCommandBar]): the
                // transport stands where it stands with a cut, and the
                // toolbar scrolls in the bar's overflow scroller (유저
                // 2026-08-10: 「버튼 사라지기 시작하면 생기는 스크롤바」).
                // ↩️This state mounted the toolbar WITHOUT that bar, so it
                // was the one place a bar too wide for the window overflowed
                // instead of scrolling — it only showed once ㉕ put three
                // more buttons on it — and then the one place with a
                // scroller of its own.
                TimelineCommandBar(
                  transport: timelineTransport,
                  leading: timelineToolbar,
                  cluster: _gapCluster(),
                ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _session.languageSettings,
                    builder: (context, settings, _) => EmptyStateText(
                      AppStrings.of(settings.programLanguage).noCutSelected,
                      key: const ValueKey<String>('timeline-empty-no-cut'),
                      place: EmptyStatePlace.stage,
                    ),
                  ),
                ),
              ],
            );
          }
          final zoom = widget.pixelsPerFrameListenable;
          if (zoom == null) {
            return buildPanel(context, widget.pixelsPerFrame, null);
          }
          return ValueListenableBuilder<double>(
            valueListenable: zoom,
            builder: buildPanel,
          );
        },
      ),
    );
  }

  /// The bar, kept while it is built for the same thing: this session and
  /// the sections its layer pill checks ([keptWhileSame] — the words too).
  ///
  /// ↩️(a-gate-rebuilds-the-whole-toolbar, 2026-10-24) It was cached on a
  /// TOKEN of every value its buttons show, re-read on every seek, band and
  /// host rebuild (`_SeekGatedTimelineToolbar`, R13-2): the naive per-seek
  /// rebuild reconstructed the whole transport + ~25 Material buttons on
  /// every frame flip — measured on device as the flip hitch — and a seek
  /// that lands in the same enablement state (almost all of them) rebuilt
  /// nothing. But a token that moved built the whole bar again, for one
  /// gate as for all of them, and every gate was written twice — in the
  /// token and in the group that shows it — and went stale where the two
  /// came apart (F-75, F-338, I-77, I-123). Each group hears its own gates
  /// now ([toolbarGateNews]): what a seek or a notify moves builds the group
  /// that shows it, and nothing else.
  final Map<Type, Kept<_ToolbarFacts>> _keptToolbar = {};

  Widget _buildTimelineToolbar() => keptWhileSame(
    _keptToolbar,
    TimelineActionToolbar,
    (ByIdentity(_session), BySet(widget.rail.hiddenSections)),
    // ⛔The TRANSPORT and the camera-view toggle are not on this toolbar:
    // the bar seats them at the head of its left group, outside the
    // toolbar's scroller ([_buildTimelineTransport]; in its right group
    // from F-463 to F-491). What is here is what reaches into THIS panel's
    // own contents.
    () => TimelineActionToolbar(
      session: _session,
      // B8: this panel's dispatch context — the session's cut-local
      // verbs, verbatim (the baseline the storyboard's own context
      // diverges from).
      panelContext: TimelineToolbarPanelContext(_session, waitIn: context),
      onAddLayer: _session.layerStack.addLayer,
      onRenameLayer: () =>
          unawaited(renameActiveLayerWithDialog(context, _session)),
      onDeleteLayer: () =>
          unawaited(deleteActiveLayerWithDialog(context, _session)),
      // F: the shared delete's ROW rung keeps the confirmation the loose
      // layer button used to carry.
      onDeleteRowSelection: () =>
          unawaited(deleteRowSelectionWithDialog(context, _session)),
      onEditInstance: _editActiveInstance,
      onCreateInstance: _createActiveInstance,
      hiddenSections: widget.rail.hiddenSections,
      onToggleSection: widget.rail.toggleSection,
    ),
  );

  /// The transport at the start of the bar's left group (F-491), kept while
  /// it is built for this session — what its buttons show, they hear
  /// themselves.
  final Map<Type, Kept<ByIdentity<EditorSessionManager>>> _keptTransport = {};

  Widget _buildTimelineTransport() => keptWhileSame(
    _keptTransport,
    FramePanelTransport,
    ByIdentity(_session),
    () => FramePanelTransport(session: _session, panel: WorkingPanel.timeline),
  );

  /// The view cluster the bar wears with no cut to show: the panel's, with
  /// nothing to zoom or fit. Its place is kept, so the bar's right group
  /// stands where it stands with a cut — ⛔없다가 생기는 UI. ↩️The gap's bar
  /// ended in nothing while the transport led it (F-111-Q1), and the
  /// transport stood beside this cluster from F-463 to F-491.
  Widget _gapCluster() {
    Widget cluster(double pixelsPerFrame) => TimelineViewCluster(
      projectFrameRate: _session.projectSettings.projectFrameRate,
      pixelsPerFrame: pixelsPerFrame,
      onPixelsPerFrameChanged: null,
      cutName: _session.cutUnderPlayhead.cutName,
      trailing: [
        TimelineOrientationToggle(
          orientation: widget.orientation,
          onChanged: widget.onOrientationChanged,
        ),
      ],
    );
    final zoom = widget.pixelsPerFrameListenable;
    if (zoom == null) {
      return cluster(widget.pixelsPerFrame);
    }
    return ValueListenableBuilder<double>(
      valueListenable: zoom,
      builder: (context, pixelsPerFrame, _) => cluster(pixelsPerFrame),
    );
  }
}

/// What the timeline's bar is built for ([_TimelineTabHostState._keptToolbar]).
typedef _ToolbarFacts = (
  ByIdentity<EditorSessionManager>,
  BySet<TimelineSection>,
);

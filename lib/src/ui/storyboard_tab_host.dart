import 'dart:async';

import 'package:flutter/material.dart';

import '../models/cut_id.dart';
import '../models/layer.dart' show LayerStackQueries;
import '../models/layer_id.dart';
import '../models/layer_kind.dart' show LayerKind;
import '../models/timeline_row_address.dart';
import '../models/track.dart';
import '../models/track_id.dart';
import '../models/working_panel.dart';
import '../services/import/import_layer_spot.dart';
import 'camera/camera_path_settings_rows.dart' show showCameraPathSettings;
import 'storyboard/cut_link_window.dart';
import 'timeline/instance_editor_commands.dart';
import 'timeline/layer_name_commands.dart';
import 'timeline/rail_column_swipe.dart' show RailSweepHistory;
import 'timeline/timeline_action_toolbar.dart';
import 'timeline/toolbar_panel_context.dart';
import 'timeline/timeline_grid_metrics.dart'
    show timelineLayerRowGrowthIn;
import 'brush/transform_tool_options.dart';
import 'editor_session_manager.dart';
import 'range_move_asking_first.dart';
import 'session/session_legend_callbacks.dart';
import 'session/session_row_button_presses.dart';
import 'timeline/session_lane_callbacks.dart';
import 'panels/panel_collapsed_scope.dart';
import 'panels/working_panel_surface.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnails;
import 'storyboard_panel.dart';
import 'storyboard/storyboard_rows_channel.dart';
import 'timeline/timeline_row_filter.dart' show TimelineRowFilter;
import 'timeline/timeline_section_policy.dart' show TimelineSection;
import 'timeline/lane_graph.dart' show LaneGraphVerbs, LaneGraphsView;
import 'timeline/layer_rail_window.dart' show LayerRailExtent;
import 'timeline/property_lane_model.dart'
    show PropertyLaneEditCallbacks;
import 'timeline/layer_row_drag.dart'
    show TimelineRowDragHooks, timelineRowAddressOfDragSubject;
import 'timeline/se_layer_mixer.dart';
import 'timeline/timeline_current_row.dart';
import 'timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'storyboard_playhead_mapping.dart';
import 'timeline/timeline_frame_range_gesture.dart' show TimelineLaneRangeHooks;
import 'timeline/timeline_command_bar.dart';
import 'timeline/memo_token.dart' show Kept, keptWhileSame;
import 'timeline/timeline_view_cluster.dart';

/// The Storyboard tab's content: its own toolbar row (frame counter,
/// seconds toggle, zoom slider — the same keys as the timeline tab's, only
/// one is ever on screen), the all-cuts transport, the storyboard panel and
/// the cut dialogs it triggers. All wiring lives HERE (not in HomePage).
class StoryboardTabHost extends StatefulWidget {
  const StoryboardTabHost({
    super.key,
    required this.session,
    this.onPlaceMediaAsset,
    required this.pixelsPerFrame,
    required this.onPixelsPerFrameChanged,
    required this.showSeconds,
    required this.onShowSecondsChanged,
    this.railExtent,
    this.frameAxisOffset,
    this.layerAxisOffset,
    this.trackLaneHeight = StoryboardPanel.defaultTrackLaneHeight,
    this.onResizeTrackLanes,
    required this.thumbnails,
    this.rowFilter = TimelineRowFilter.none,
    this.onSetRowFilter,
    this.hiddenSections = const {},
    this.onToggleSection,
    this.collapsedAttachBaseIds = const {},
    this.onToggleAttachGroup,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.expandedLaneGroupKeys = const {},
    this.onToggleLaneGroupKey,
    this.laneGraphs = LaneGraphsView.none,
    this.laneGraphVerbs,
    this.rowsChannel,
    this.transformOptions,
  });

  /// The legend's row filter, shared with the timeline and the sheet
  /// (R5 #9). Null [onSetRowFilter] leaves the chips inert.
  final TimelineRowFilter rowFilter;
  final ValueChanged<TimelineRowFilter>? onSetRowFilter;

  /// The hidden SE and camera sections, shared with the timeline — the same
  /// toggles, from the same legend menu (F-199).
  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

  /// The folded attach groups, shared with the timeline — the same set and
  /// the same verb ([TimelineTabHost.collapsedAttachBaseIds]): the conte
  /// row's twirl folds the attach rows riding it (I-73).
  final Set<LayerId> collapsedAttachBaseIds;
  final ValueChanged<LayerId>? onToggleAttachGroup;

  /// The rows' twirled-down lanes, shared with the timeline — the same set
  /// and the same verb ([TimelineTabHost.expandedLaneLayerIds]): the camera
  /// row's twirl opens its lanes here as on the timeline's rail (I-73 ④ⓔ).
  final Set<LayerId> expandedLaneLayerIds;
  final ValueChanged<LayerId>? onToggleLayerLanes;

  /// …and the lane GROUPS twirled open in them, the same set and verb
  /// ([TimelineTabHost.expandedLaneGroupKeys]): a conte row's groups twirl
  /// here as on the timeline's rail (I-73 ④ⓔ).
  final Set<String> expandedLaneGroupKeys;
  final ValueChanged<String>? onToggleLaneGroupKey;

  /// …and the header graphs standing open over them, the same state and
  /// verbs ([TimelineTabHost.laneGraphs]): a graph opened here is open on
  /// the timeline's rail, and the other way round (I-89 ①).
  final LaneGraphsView laneGraphs;
  final LaneGraphVerbs? laneGraphVerbs;

  /// Where the panel hands its stacked rows to the shell's walkers — see
  /// [StoryboardPanel.rowsChannel].
  final StoryboardRowsChannel? rowsChannel;

  /// The transform tool's options — the timeline host's own
  /// ([TimelineTabHost.transformOptions]): an S row's Scale lane links by
  /// the same switch.
  final ValueNotifier<TransformToolOptions>? transformOptions;

  /// The shortest this tab is laid out at — the dock splitter's floor and
  /// the tab shell's minimum content height. See
  /// [StoryboardPanel.minPanelHeight] for the two-row rule.
  ///
  /// The bar's own height is [TimelineCommandBar.height], which the
  /// timeline reads too. The two used to measure themselves separately and
  /// come back 18px apart.
  static const double minPanelHeight =
      TimelineCommandBar.height + StoryboardPanel.minPanelHeight;

  /// [minPanelHeight] where the tab is shown — the bar grows with the OS
  /// text size ([TimelineCommandBar.heightIn]), and so do the THREE rows
  /// under it: the legend's band, and the two floor rows the body keeps,
  /// each the timeline's row ([timelineLayerRowGrowthIn],
  /// text-scale-rail-rows) — so both panels still stop on the same budget
  /// ([StoryboardPanel.minPanelHeight]; the timeline's floor grows by the
  /// same three rows).
  static double minPanelHeightIn(BuildContext context) =>
      minPanelHeight +
      TimelineCommandBar.growthIn(context) +
      3 * timelineLayerRowGrowthIn(context);

  final EditorSessionManager session;
  final double pixelsPerFrame;
  final ValueChanged<double> onPixelsPerFrameChanged;
  final bool showSeconds;
  final ValueChanged<bool> onShowSecondsChanged;

  /// This panel's rail window size (workspace-owned so it survives a tab
  /// switch AND a restart).
  final LayerRailExtent? railExtent;

  /// Where the storyboard's frame axis stands — held above the panel beside
  /// [railExtent] so it outlives a fold (F-143), and the project's, saved
  /// with it (F-267). Null = the panel's own.
  final ValueNotifier<double>? frameAxisOffset;

  /// Where the storyboard's rows are scrolled to — the project's too
  /// (F-267). Null = nobody keeps it.
  final ValueNotifier<double>? layerAxisOffset;

  /// The V rows' shared height, owned above the tabs so it survives a tab
  /// switch like the zoom does. ⛔No steppers any more (B7, 유저 2026-08-17):
  /// the bar's push/pull height pair is deleted, and its one writer is the
  /// V rows' splitter ([onResizeTrackLanes]).
  final double trackLaneHeight;

  /// The V rows' splitter ([StoryboardPanel.onResizeTrackLanes]).
  final double Function(double delta)? onResizeTrackLanes;

  /// The panel pictures, owned above the tabs so the cache survives tab
  /// switches — a landed one repaints the blocks, never this host.
  final StoryboardThumbnails? thumbnails;

  /// A media-browser row let go on the storyboard — the host opens the place
  /// window with the drop's answer: a NEW cut on a track's frames
  /// ([NewCutSpot]), a new block on an SE row's empty cell ([SeCellSpot]),
  /// or the SE rows' rule on the rail. Null leaves the rows and the rail
  /// refusing the drag, which is what a surface with nowhere to open a
  /// window should do.
  final void Function(String path, ImportLayerSpot spot)? onPlaceMediaAsset;

  @override
  State<StoryboardTabHost> createState() => _StoryboardTabHostState();
}

class _StoryboardTabHostState extends State<StoryboardTabHost> {
  EditorSessionManager get _session => widget.session;

  /// The rows' buttons as a press asks them — the timeline rail's own
  /// wiring, spread over the row selection when the pressed row is in it.
  SessionRowButtonPresses get _rowPresses => SessionRowButtonPresses(_session);

  /// The view cluster, kept by what it shows across this host's rebuilds —
  /// the timeline panel's keep (F-244 ⑧).
  final Map<Type, Kept<TimelineViewClusterFacts>> _kept = {};

  // ⛔The storyboard's playhead channel is the SESSION's now
  // ([PlayheadCursors.trackFrame]): the row this panel folds into draws the
  // same playhead and turns the same pages, and that row is built by the
  // workspace, which could not reach a channel kept here (유저 2026-09-27,
  // folded-row-playhead-during-playback-Q1). It is still the cursor-layer
  // pattern (W4 perf pass): scrub moves, committed seeks, playback ticks
  // and session changes move the channel, and only the panel's playhead
  // overlay + ruler subscribe — the strips, blocks, rails and waveforms
  // never rebuild on a tick.

  // ⛔The ACTIVE cut's local cursor channel is GONE (F-102, 2026-09-15): its
  // one reader was the S rows' lane labels, and an S row's keys are the
  // track's — they read the track channel now, as the V rows' labels do.
  // #844's point survives on that channel: the labels subscribe, and a
  // committed seek repaints those cells instead of rebuilding the panel.

  /// F-357: the unworked-block tint's fact for the conte row, which crosses
  /// every cut — and its event, bound once like the timeline host's
  /// (a fresh record per build would re-subscribe the row's painter).
  late final ConteCelContent _conteCelContent = (
    holdsAPicture: _session.layerStack.celHoldsAPicture,
    revision: _session.layerStack.celTintRevision,
  );

  /// Whatever can change a frame's cached-ness — warm progress AND pixel
  /// edits (composites self-validate by signature, so an edit raises no
  /// event of its own). The ruler's green bar repaints off this; the
  /// timeline host carries the identical signal.
  late final Listenable _frameReadySignal = Listenable.merge([
    _session.playbackRig.prerenderScheduler.progress,
    _session.renderCaches.brushFrameStore.celPixelRevision,
  ]);

  /// The rail's row-order drag: the S rows re-order their track's list, the
  /// V rows the tracks.
  ///
  /// 🚨Bound ONCE, as the timeline host binds its own (F-244): the rail
  /// keeps each of its rows — the drag wrapper with it — only while this is
  /// the same object (I-57, 10-14). Nothing in it reads the build it was
  /// made in: the verbs are the session's, and the closures ask the session
  /// at the event.
  late final TimelineRowDragHooks _rowDragHooks = TimelineRowDragHooks(
    drag: _session.layerRowDragVerbs.inFlight,
    onBegin: _session.layerRowDragVerbs.beginLayerRowDrag,
    onUpdate: _session.layerRowDragVerbs.updateLayerRowDrag,
    onRowTarget: _session.layerRowDragVerbs.updateLayerRowDropOnRow,
    // R5 #9: the V row re-orders TRACKS, and the track list is the
    // composite order (user, 2026-08-09) — so this is only offered where
    // tracks are on screen.
    onTrackUpdate: _session.layerRowDragVerbs.updateTrackRowDrag,
    onEffectUpdate: _session.layerRowDragVerbs.updateEffectRowDrag,
    onEnd: _session.layerRowDragVerbs.endLayerRowDrag,
    onCancel: _session.layerRowDragVerbs.cancelLayerRowDrag,
    // 🚨A5-3② (유저 2026-08-22): 「스토리보드패널에서는 되긴 하는데 **통일이
    // 안 돼 있다** — 선택범위로 선택하고 이동하는 게 규칙인데 **그냥 바로
    // 드래그 작동**해버림」.
    //
    // ⑨'s law is ONE law: the first drag SELECTS, and a drag that starts
    // INSIDE the selection moves it. It was never the timeline's own — it
    // is the cells' grammar transposed, and both rails draw cells. This
    // rail simply passed null for the three hooks, and null means "this
    // surface takes no part in row selection", so every press here went
    // straight to the move.
    //
    // 🚨THE V ROWS ARE IN NOW (유저 2026-08-29). They used to answer null —
    // "this subject takes no part in row selection" — which left a track
    // drag moving on the first press. The comment here said putting tracks
    // behind a select step was "not mine to make unasked". It was then
    // asked:
    //
    // > 「v행트랙이든 뭐든 **선택범위는 작동하게**. 거기서 드래그는 뭐
    // > 트랜지션은 불가로 남아있잖아? 그런식으로 **행에따라 불가는
    // > 남아있지만 선택범위는 다 작동해야해**」
    //
    // ⇒ And it is CLAUDE.md's second absolute command spelled out:
    // 「선택범위는 레이어 불문 자유롭게. 행의 종류로 막지 않는다」. A row
    // type may still refuse to MOVE — that rule lives with the drop policy,
    // where it can say which rows accept what — but it may not refuse to be
    // SELECTED.
    isInRowSelection: (subject) => _session.rowSelectionVerbs.rowIsSelected(
      timelineRowAddressOfDragSubject(subject),
    ),
    onSelectBegin: (subject) => _session.rowSelectionVerbs.beginRowSelection(
      timelineRowAddressOfDragSubject(subject),
    ),
    onSelectEnd: _session.rowSelectionVerbs.endRowSelection,
    // I-39: what a picked-up row carries, named at the pointer.
    rowsActedOnBy: _session.rowSelectionVerbs.rowsActedOnBy,
  );

  // ⛔"To start" (REC1-B) is a free function now
  // ([seekStoryboardPlayheadToTrackStart]): the button that calls it is the
  // 문턱's, built by the workspace. One implementation, two possible
  // callers, no host method to reach for.

  // ↩️This rail's own twirls — its S rows', its V rows' and their groups —
  // were sets the host kept and turned here, handing the storyboard's
  // standing on as one folded. They are the rows' (F-360): the session's
  // twirl writes them, and its fold hands on in both rails
  // (`Standing.handOffCurrentRowOnFold`).

  /// Lane edit hooks for the V TRACK's own lanes — its EFFECT chain, which is
  /// all a track row has since the transform teardown
  /// ([timelineRowOwnsTransform]). Keys land on the GLOBAL axis and commit as
  /// ONE undo through [LaneVerbs], exactly as a layer effect's do.
  ///
  /// ↩️F-195: this was a copy of [sessionLaneEditCallbacks] addressed to the
  /// track's carrier, each hook fenced to effect lanes — and a value's
  /// preview would have been its third copied hook. The rail hands the hooks
  /// the CARRIER as the row's layer, so the carrier id arrives as the row's
  /// own; [LaneVerbs] sends it home to the track ([laneVerbLayerFor]), and a
  /// transform edit there lands nowhere by the verbs' own answer
  /// (`_TransformHome.nowhere`), so the fence answered a question the verbs
  /// already answer. One wiring, as the S rows take it.
  PropertyLaneEditCallbacks _trackLaneEditFor(Track track) => _layerLaneEdit;

  // ⛔The host's lane-span head walk is GONE (C②): it walked TRANSFORM
  // lanes for a V rail that draws FX lanes and answered null for every SE
  // anchor — a hand-kept copy of what the panel draws, drifted. The panel
  // resolves the head lane off its own row geometry now.

  /// Lane edit hooks for the S rows' lanes — the verbs the timeline's lanes
  /// key through, handed this rail's GLOBAL frames.
  ///
  /// ↩️This was 「the timeline host's layer-transform editing verbatim」 — a
  /// copy, which keyed the row at whatever frame the label passed, and the S
  /// labels passed the ACTIVE cut's local cursor to a row whose keys are
  /// global (F-102). [LaneVerbs] holds the one body now, and the labels read
  /// the global playhead.
  ///
  /// ↩️「SE layers only here; no camera or audio-lane dispatch on these
  /// lanes」 stopped being true with F-101: an S row twirls down the
  /// timeline's own list, Audio lane included, so both hosts take
  /// [sessionLaneEditCallbacks] and the typed offset goes where the
  /// timeline's does.
  PropertyLaneEditCallbacks get _layerLaneEdit => sessionLaneEditCallbacks(
    _session,
    frameIsGlobal: true,
    transformOptions: widget.transformOptions,
  );

  /// THE cells' press (the timeline's cell contract): pick the row, then
  /// seek to the frame under the pointer. The seek is the ruler's own, so a
  /// press in a GAP parks there — an empty cell is still a cell, and the two
  /// paths cannot disagree about what a frame means.
  ///
  /// The row half comes FIRST and does only the row: a track row that
  /// promoted the playhead's cut here would switch cuts twice, since the
  /// pressed frame decides the cut.
  void _pressRowFrame(TimelineRowAddress row, int globalFrame) {
    switch (row) {
      case LayerRowAddress():
        _session.selectRow(row);
        // ⑭: the INDEX decides the active cut, whichever row was pressed.
        // This used to park — an SE row owns no cuts, so pressing one said
        // where you ARE without saying which cut you edit (feedback #7) —
        // but that sentence was written while SEVERAL tracks could cover one
        // frame and "which cut did you mean" had no answer. One track later
        // there is exactly one cut under the press, so every row lands the
        // same seek and a gap still parks (the seek's own gap branch).
        seekStoryboardGlobalFrame(_session, globalFrame);
      case LaneRowAddress():
        // A property strip lands the way its layer row does: the row you
        // pressed was never what chose the cut.
        _session.selectRow(row);
        seekStoryboardGlobalFrame(_session, globalFrame);
      case TrackRowAddress(:final trackId):
        _session.selectTrackRow(trackId);
        seekStoryboardGlobalFrame(_session, globalFrame);
    }
  }

  /// THE cells' press, standing in this panel: [_pressRowFrame] stands
  /// without the verb, so it names the timeline's seat itself (F-187).
  void _pressRowFrameHere(TimelineRowAddress row, int globalFrame) =>
      _session.standing.standInStoryboard(
        () => _pressRowFrame(row, globalFrame),
      );

  /// 🗣️F-255 (유저 2026-10-01): 「이름변경 입구 확대. 지금 프레임블록이랑
  /// 레이어라벨 더블클릭하면 이름편집인데 콘티블록이나 컷블록에도
  /// 통일적용」 — a CUT block's double click: its cut, renamed through the
  /// Edit button's own door ([renameActiveCutWithDialog]).
  ///
  /// The press lands first, as a frame block's double tap picks its cell
  /// before it opens it: that door renames the cut in hand, and a first
  /// press inside a cut selection stood nowhere — it may have been the
  /// start of a move.
  Future<void> _editCutBlock(TrackId trackId, int globalFrame) {
    _pressRowFrameHere(TrackRowAddress(trackId), globalFrame);
    return renameActiveCutWithDialog(context, _session);
  }

  /// …and a CONTE block's: the frame block's own double tap
  /// ([activateCellOnDoubleTap]) on the cell it is — its cut's storyboard
  /// row at the cut's own frame. The first click was the pick: the conte
  /// row's cells are pressed like the timeline's, so the row is stood on
  /// and the cut's conte layer seated ([Standing.layerAConteStandSeats])
  /// before the second click arrives — the cell is in hand the way the
  /// timeline's is when its double tap opens it, and nothing is pressed
  /// here. ↩️This door pressed first, on the CUT, while the conte blocks
  /// were the cut block's (F-187, 「컷에서면 콘티레이어가 있다면
  /// 콘티레이어에 서도록」) — a first press inside a cut selection stood
  /// nowhere there, as [_editCutBlock]'s still may. The blocks are the
  /// conte row's now (I-73), whose press always lands (🧪2026-10-08: with
  /// the press gone no double click opened another cell or stood
  /// elsewhere).
  ///
  /// ↩️In a cut an O.L arrives into, the frame the storyboard's seek left
  /// the session on was short of the row's own by the のりしろ, so the cell
  /// that opened was that much early (🧪2026-10-08: a double click on the
  /// second panel named the first). The seek counts the cut's own frames
  /// now, for every verb at once (I-73-ol-index-space, `TrackFrameAxis`).
  /// ⛔It was not this door's to put right: adding the のりしろ to the
  /// frame handed on moved the playhead, and the name still landed where
  /// the session stood.
  Future<void> _editConteBlock(TrackId _, LayerId layerId, int _) =>
      activateCellOnDoubleTap(
        context,
        _session,
        layerId: layerId,
        frameIndex: _session.currentFrameIndex,
      );

  /// THE CAMERA ROW's press that lands in a cut (I-73 ④) — the row's, or
  /// one of its lanes' (④ⓔ): the [row], then the cut and the frame of its
  /// own the press named — over an O.L, the cut of the line pressed — the
  /// cells' press ([_pressRowFrame]) with the seek that names its cut
  /// ([seekStoryboardCutFrame]), standing in this panel.
  void _pressCameraCut(TimelineRowAddress row, CutId cutId, int ownFrame) =>
      _session.standing.standInStoryboard(() {
        _session.selectRow(row);
        seekStoryboardCutFrame(_session, cutId, ownFrame);
      });

  /// The lane edits a projection row's lane labels hand over — the
  /// timeline's, on the frames of the cut's own (I-73 ④ⓔ).
  PropertyLaneEditCallbacks get _cutLaneEdit => sessionLaneEditCallbacks(
    _session,
    frameIsGlobal: false,
    transformOptions: widget.transformOptions,
  );

  /// …and its double click: the timeline camera row's own
  /// ([activateCellOnDoubleTap] — a key opens, an empty cell is keyed), on
  /// the camera layer the first click seated, at the frame it stood on.
  Future<void> _editCameraCell() async {
    final camera = _session.activeCutOrNull?.layers.cameraLayer;
    if (camera == null) {
      return;
    }
    await activateCellOnDoubleTap(
      context,
      _session,
      layerId: camera.id,
      frameIndex: _session.currentFrameIndex,
    );
  }

  /// The cells' double tap on a LANE (유저 2026-09-11: 「…싹 법 하나로
  /// 통일」) — the timeline's own door ([activateCellOnDoubleTap]: a key
  /// opens, an empty cell is keyed) on the layer in hand, at the cell the
  /// double click names ([globalFrame]). The first click stood on the frame
  /// under the pointer, and under a pixel a cell the double click names the
  /// pixel's ([timelineDoubleTapAim]), so it lands there first — as the
  /// timeline's door seeks its own frame.
  ///
  /// ↩️It forked by itself on this rail's Edit and ＋, and answered where
  /// the first click had stood (I-89 ① ⓕ, 2026-10-20).
  Future<void> _activateLaneCell(int globalFrame) async {
    if (_session.editingGlobalFrame != globalFrame) {
      _session.selectGlobalFrame(globalFrame);
    }
    await activateCellOnDoubleTap(
      context,
      _session,
      layerId: _session.activeLayer?.id,
      frameIndex: _session.currentFrameIndex,
    );
  }

  /// I-48: a double click on a layer's label renames the rows its first
  /// press acted on — the timeline rail's door, on this rail's rows.
  VoidCallback _renameOnLabelDoubleClick(LayerId pressed) =>
      renameOnLabelDoubleClick(context, _session, pressed);

  /// The row's double-tap: the SHARED transition instance editor at the tapped
  /// frame. The implementation moved to [editTransitionSpanInstance] so this
  /// gesture and the Edit Instance verb cannot drift apart — a second copy here
  /// is how "delete works from the dialog but not from the pill" starts.
  ///
  /// 🚨★★★I-9: an EMPTY cell CREATES, and that fork lives in the shared verb
  /// too — it has since 2026-08-11. What was broken was the STRIP: it tested
  /// 「is there a span here」 itself and returned in silence, so the verb's
  /// own create branch was unreachable from the double tap. The strip asks
  /// unconditionally now, and there is still exactly one copy of the answer.
  ///
  /// ↩️The fork moved out of the Edit door into the double tap's own
  /// ([activateTransitionSpanCell]; F-105, 유저 2026-09-15 「통일 — 편집 버튼은
  /// 빈 칸에서 꺼진다」): the button edits, the double tap forks, ＋ creates.
  Future<void> _editTransitionSpan(int globalFrame) =>
      activateTransitionSpanCell(context, _session, globalFrame: globalFrame);

  /// The S row's double-tap, the transition row's twin — same shape, same
  /// reason, and now the same I-9 fork inside [editSeEntryInstance].
  ///
  /// ↩️…inside [activateSeEntryCell] (F-105): [editSeEntryInstance] is the
  /// Edit button's door and no longer creates.
  Future<void> _editSeEntry(LayerId layerId, int globalFrame) =>
      activateSeEntryCell(
        context,
        _session,
        layerId: layerId,
        globalFrame: globalFrame,
      );

  /// B8: THIS PANEL's dispatch context for the shared toolbar — the standing
  /// row crossed with the track-global playhead, instead of the session's
  /// cut-local reads. Rebuilt per access (a stateless wrapper over the
  /// session), so it can never hold a stale answer.
  StoryboardToolbarPanelContext get _toolbarPanel =>
      StoryboardToolbarPanelContext(_session, waitIn: context);

  /// ③/B8 Edit Instance on THIS panel: [editOnPanel] with this panel's
  /// context — the door its key opens too (F-261).
  void _editInstanceHere() =>
      unawaited(editOnPanel(context, _session, panel: _toolbarPanel));

  /// ONE command-bar row — the timeline's own widget now, not a parallel
  /// copy of it: transport + cut group left, the shared view cluster right.
  Widget _commandBar(BuildContext context) {
    return TimelineCommandBar(
      // ⑫: the inset and the overflow scroller are the BAR's. This row used
      // to bring its own — on top of the toolbar's — which is what put an
      // extra 2px in front of the cut button here and nowhere else.
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ⛔The TRANSPORT and the camera-view toggle left this bar (유저
          // 확정, 2026-08-10): they are the 문턱's now, mounted by the
          // workspace through `EditorPanelTab.sillTrailing` (see
          // [FramePanelSillControls]). What stays here is what reaches into
          // THIS panel's own contents.
          //
          // ★THE SAME FOUR PILLS the timeline mounts — literally the same
          // widget (유저: 스토리보드 레이어의 프레임을 조절해야 하고 레이어도
          // 만들고 지워야 한다). 컷 · 레이어 · 프레임 · FX, in the order the
          // data nests, and every verb on them works here: the instance
          // editor is a free function now, so `Edit Instance` opens on this
          // panel too.
          // B8: the bar's gates read the CURSOR now (standing row × global
          // playhead), and neither a committed seek nor a standing move is
          // a session notify — so the toolbar re-derives through its own
          // token gate, the timeline host's pattern said of this panel.
          _CursorGatedStoryboardToolbar(
            session: _session,
            actionsBuilder: (context) => TimelineActionToolbar(
              session: _session,
              // B8: THIS panel's dispatch context — every layer/frame/
              // shared/fx verb acts against the storyboard's standing row
              // and global cursor, or greys out honestly.
              panelContext: _toolbarPanel,
              onAddLayer: _session.layerStack.addLayer,
              onRenameLayer: () =>
                  unawaited(renameActiveLayerWithDialog(context, _session)),
              onDeleteLayer: () =>
                  unawaited(deleteActiveLayerWithDialog(context, _session)),
              // F: the shared delete's ROW rung, confirmation included.
              onDeleteRowSelection: () =>
                  unawaited(deleteRowSelectionWithDialog(context, _session)),
              // ⑬: the same dispatch Edit Instance takes. Standing on the
              // transition row, `＋` makes a span — that row's only creation
              // verb, and the one the rail's own `＋` carried before #926
              // retired it.
              onCreateInstance: _toolbarPanel.createInstance,
              // This panel reads left-to-right like the horizontal timeline,
              // so its dialogs' miniatures do too.
              onEditInstance: _editInstanceHere,
              // Which rail is asking — this panel's own answer, the one its
              // push/pull KEYS read too ([ToolbarPanelContext.shiftCurrentRow]).
              currentRow: _toolbarPanel.shiftCurrentRow,
            ),
          ),
          // ⛔The storyboard's own tail is GONE (B7, 유저 2026-08-17: 「완전
          // 동일 버튼 2개 — 삭제」): the 'V' fx pill duplicated the shared
          // toolbar's Fx entrance, and the row-height steppers leave with it
          // — the V-track height's next writer is the planned splitter. The
          // bar carries exactly what the timeline's does.
        ],
      ),
      // The facts typed at the call, as the timeline panel's are.
      cluster: keptWhileSame<Type, TimelineViewClusterFacts>(
        _kept,
        TimelineViewCluster,
        (
          frameCursor: _session.editingFrameCursor,
          globalFrame: _session.playheadCursors.trackFrame,
          projectFrameRate: _session.projectSettings.projectFrameRate,
          showSeconds: widget.showSeconds,
          pixelsPerFrame: widget.pixelsPerFrame,
          onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
          cutName: _session.cutUnderPlayhead.cutName,
          trailing: null,
        ),
        () => TimelineViewCluster(
          frameCursor: _session.editingFrameCursor,
          // Global · cut-local pair (UI-R9 #6) — the channel already
          // follows scrubs, gap parking and playback ticks.
          globalFrame: _session.playheadCursors.trackFrame,
          cutName: _session.cutUnderPlayhead.cutName,
          projectFrameRate: _session.projectSettings.projectFrameRate,
          showSeconds: widget.showSeconds,
          pixelsPerFrame: widget.pixelsPerFrame,
          onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RailSweepHistory(
    history: _session.historyManager.gestures,
    changed: _session.notifyChanged,
    child: _panel(context),
  );

  Widget _panel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // No per-tick host rebuild (W4 perf pass): playback ticks and scrub
    // moves ride the session's track cursor into the panel's playhead
    // overlay + ruler; the green bar rides the prerender progress into the
    // ruler; the counter subscribes to the cursor. Cut crossings during
    // playback still notify the session (cut follow), which rebuilds the
    // host from the workspace subscription.
    // The panel being worked in owns the frame-axis verbs (user,
    // 2026-08-05): touching the storyboard hands the flip its rail's row,
    // so the arrows count CUTS from here without having to pick a row
    // first. Putting it away hands the work on to the timeline when that is
    // on the screen (user, 2026-09-25).
    return WorkingPanelSurface(
      onTouch: _session.claimStoryboardRow,
      onSight: (surface, {required inSight}) => _session.panelInSight(
        WorkingPanel.storyboard,
        surface: surface,
        inSight: inSight,
      ),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // No seek subscription HERE: the one control on this bar a
            // committed seek can change is the push/pull pair, and it owns
            // that subscription itself ([TimelineShiftButtons]).
            _commandBar(context),
            // ★COLLAPSED = the command bar and nothing else, the same rule
            // the timeline panel follows (유저 확정, 2026-08-10). Offstage
            // and not removed: the panel keeps its scroll positions and its
            // thumbnail cache, and — the part that matters more — its parent
            // chain never changes, so folding cannot silently remount it.
            Expanded(
              // Edit drags (cut trims, SE comma drags) preview through the
              // session's scoped channel. The PANEL consumes it internally
              // (R10-③): only its cut-layout-dependent pieces rebuild per
              // step — the SE rows (waveforms!) and rails hold their built
              // subtrees, which is what makes trim drags glide.
              //
              // Live take preview (REC1-C): the armed SE lane swaps identity
              // at most once per FRAME while recording — this panel-scoped
              // rebuild is the notify-free channel (R12-B: ticks never
              // notify the session), same as the timeline host's merge.
              child: Offstage(
                offstage: PanelCollapsedScope.of(context),
                child: ListenableBuilder(
                  listenable: _session.voiceRecording.voiceRecordPreviewLane,
                  builder: (context, _) => StoryboardPanel(
                    project: _session.repository.requireProject(),
                    rowFilter: widget.rowFilter,
                    hiddenSections: widget.hiddenSections,
                    onToggleSection: widget.onToggleSection,
                    collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
                    onToggleAttachGroup: widget.onToggleAttachGroup,
                    expandedLaneLayerIds: widget.expandedLaneLayerIds,
                    onToggleLayerLanes: widget.onToggleLayerLanes,
                    expandedLaneGroupKeys: widget.expandedLaneGroupKeys,
                    onToggleLaneGroupKey: widget.onToggleLaneGroupKey,
                    laneGraphs: widget.laneGraphs,
                    laneGraphVerbs: widget.laneGraphVerbs,
                    laneGraphsNow: () => _session.railView.laneGraphs.value,
                    seLanePreview: _session.voiceRecording.voiceRecordPreviewLane.value,
                    dragPreview: _session.dragPreview,
                    conteCelContent: _conteCelContent,
                    // ↩️While playing, this named the PLAYING cut and the
                    // stop caught the active cut up; a run's crossing lands
                    // the cut it reaches since I-57 ②, so they are one.
                    activeCutId: _session.activeCutId,
                    // A pool row let go on a row's frames (the row has already
                    // stood there through its press below): the place window
                    // opens on what the session names there — a NEW cut on a
                    // track's frames, a new block on an SE row's empty cell.
                    // The chip and the drop read that one answer (T25).
                    onDropMediaAsset: widget.onPlaceMediaAsset == null
                        ? null
                        : (row, globalFrame, path) {
                            final spot = _session.storyboardDropSpotFor(
                              row,
                              globalFrame,
                              path,
                            );
                            if (spot != null) {
                              widget.onPlaceMediaAsset?.call(path, spot);
                            }
                          },
                    acceptsMediaAsset: (row, globalFrame, path) =>
                        _session.storyboardDropSpotFor(row, globalFrame, path) !=
                        null,
                    // …and on the rail, by the layer area's law. Nothing is
                    // stood on: a rail names no row, and the timeline's drop
                    // between rows stands on nothing either.
                    onDropMediaAssetOnRail: widget.onPlaceMediaAsset == null
                        ? null
                        : (path) {
                            final spot = _session.storyboardRailDropSpotFor(
                              path,
                            );
                            if (spot != null) {
                              widget.onPlaceMediaAsset?.call(path, spot);
                            }
                          },
                    acceptsMediaAssetOnRail: (path) =>
                        _session.storyboardRailDropSpotFor(path) != null,
                    onRowFramePress: _pressRowFrameHere,
                    activeLayerId: _session.activeLayerId,
                    // The rail speaks ROW ADDRESSES, and selecting one lands
                    // the editing focus on it (user 2026-07-29, superseding
                    // #741's "row picks never move the focus"): the row lands
                    // where the playhead already stands — the same landing its
                    // own cell press makes — and ⑭ then reads the INDEX for the
                    // cut, so an S row and a V row agree about which cut is
                    // active (a gap still parks, on either).
                    selectedRow: _session.selectedRow,
                    // A CLICK CLEARS (유저 확정) — this rail's taps too, through
                    // the same verb since T4. Standing on THIS panel is this
                    // panel's own rule: the row you stand on and the layer you
                    // draw on are separate states here (유저 2026-07-27) —
                    // ↩️and the verb seats the timeline once it has stood
                    // (F-187). The seek afterwards is the storyboard's — a row
                    // press says where you ARE on the global axis.
                    onSelectLayer: (layerId) {
                      _session.standOnRow(
                        LayerRowAddress(layerId),
                        panel: WorkingPanel.storyboard,
                      );
                      final frame = _session.playheadCursors.trackFrameNow();
                      if (frame != null) {
                        seekStoryboardGlobalFrame(_session, frame);
                      }
                    },
                    // And the press that stood INSIDE the selection and
                    // turned out to be a tap lets it go — the timeline
                    // rail's verb, as is (T10's second half).
                    onSettledPress: _session.clearTimelineSelections,
                    labelDoubleClick: _renameOnLabelDoubleClick,
                    onSelectTrack: (trackId) =>
                        _session.standOnRow(TrackRowAddress(trackId)),
                    pixelsPerFrame: widget.pixelsPerFrame,
                    trackLaneHeight: widget.trackLaneHeight,
                    onResizeTrackLanes: widget.onResizeTrackLanes,
                    showSeconds: widget.showSeconds,
                    onShowSecondsChanged: widget.onShowSecondsChanged,
                    railExtent: widget.railExtent,
                    frameAxisOffset: widget.frameAxisOffset,
                    layerAxisOffset: widget.layerAxisOffset,
                    projectFrameRate: _session.projectSettings.projectFrameRate,
                    // The strip's edges preview live and commit ONE undo on
                    // release, like the timeline's comma drags. Which verb a
                    // drag belongs to is settled at BEGIN — by where the grip
                    // sat — and the SESSION keeps that answer (feedback #5's
                    // first attempt kept it here, where a rebuild mid-drag
                    // could re-route the release onto a verb whose fields
                    // were never set): the continuations are one funnel.
                    stripEdges: StoryboardStripEdgeCallbacks(
                      onCutEdgeBegin: (cutId, edge, panelIndex) =>
                          _session.edgeDrag.beginCutEdgeDrag(
                            cutId: cutId,
                            edge: edge,
                            panelIndex: panelIndex,
                          ),
                      onCommaBegin: (cutId, blockStartIndex) =>
                          _session.edgeDrag.beginStoryboardCommaDrag(
                            cutId: cutId,
                            blockStartIndex: blockStartIndex,
                          ),
                      onRowEdgeBegin: (cutId, layerId, blockStartIndex, edge) =>
                          _session.edgeDrag.beginStripRowEdgeDrag(
                            cutId: cutId,
                            layerId: layerId,
                            blockStartIndex: blockStartIndex,
                            edge: edge,
                          ),
                      onUpdate: _session.edgeDrag.updateCutEdgeDrag,
                      onEnd: _session.edgeDrag.endCutEdgeDrag,
                      onCancel: _session.edgeDrag.cancelCutEdgeDrag,
                    ),
                    // Whole-block moves (R10-④): a drag re-times the cut where
                    // it has room and REORDERS the track where it reaches past
                    // a neighbour — one rule, one undo per drag.
                    cutMove: StoryboardCutMoveCallbacks(
                      onBegin: _session.cutMove.beginCutMoveDrag,
                      onUpdate: _session.cutMove.updateCutMoveDrag,
                      onEnd: _session.cutMove.endCutMoveDrag,
                      onCancel: _session.cutMove.cancelCutMoveDrag,
                    ),
                    // Cut range selection (UI-R18 #1): drag = select a run,
                    // drag inside the selection = slide the whole run, tap =
                    // clear; the delete command batches the selection.
                    cutSelect: StoryboardCutSelectCallbacks(
                      selectedRange: _session.trackFrameRangeSelection,
                      onDrag: _session.updateStoryboardCutSelectionByFrame,
                      onClear: _session.clearStoryboardCutSelection,
                    ),
                    // The STRIP's selection is the CUT-LOCAL one — the same
                    // object the timeline uses, on that cut's storyboard layer.
                    // It has to be: a cut-local index can only name frames of
                    // the active cut, which the cells press has just made
                    // active by pressing there.
                    stripSelect: StoryboardStripSelectCallbacks(
                      selection: _session.frameRangeSelection,
                      onDrag:
                          ({
                            required layerId,
                            required anchorIndex,
                            required headIndex,
                          }) => _session.updateFrameRangeSelectionDrag(
                            layerId: layerId,
                            anchorIndex: anchorIndex,
                            headIndex: headIndex,
                          ),
                      onClear: _session.clearFrameRangeSelection,
                      // Sliding the panels is the CUT-LOCAL move — the same
                      // one the timeline's rows use, because the strip's
                      // selection is that same object on that same axis.
                      move: StoryboardRangeMoveCallbacks(
                        onBegin: _session.rangeMove.beginFrameRangeMoveDrag,
                        onUpdate: (frameDelta, targetLayerId) =>
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
                    // D30: the no-layer cut's create affordance — gate and
                    // dispatch are the session's ONE add-layer pair (T25),
                    // aimed at the cut the press just activated.
                    onCreateStoryboardLayer: (cutId) {
                      if (_session.activeCutOrNull?.id == cutId &&
                          _session.layerStack.canAddLayerOfKind(LayerKind.storyboard)) {
                        _session.layerStack.addLayerOfKind(LayerKind.storyboard);
                      }
                    },
                    // I-25: a linked cut's name wears the link icon, and the
                    // icon opens the link window.
                    linkedCutIds: _session.cutVerbs.linkedCutIds,
                    onOpenCutLinks: (context, cutId) => showCutLinkWindow(
                      context,
                      session: _session,
                      cutId: cutId,
                    ),
                    // The end line edits the MOVIE length (UI-R20 #3): the
                    // project's trailing gap, never the cuts.
                    movieEnd: StoryboardMovieEndCallbacks(
                      onBegin: _session.movieEnd.beginMovieEndDrag,
                      onUpdate: _session.movieEnd.updateMovieEndDrag,
                      onEnd: _session.movieEnd.endMovieEndDrag,
                      onCancel: _session.movieEnd.cancelMovieEndDrag,
                    ),
                    playheadFrame: _session.playheadCursors.trackFrame,
                    cutUnderPlayhead: _session.cutUnderPlayhead.listenable,
                    // F-110: the gate on the page turn. Null while nothing
                    // plays, which is what keeps a hand's seek on the walk.
                    playbackFrame: _session
                        .playbackRig
                        .playback
                        .globalFrameIndexListenable,
                    revealSelectionTick:
                        _session.rangeSelections.revealSelectionTick,
                    frameReadySignal: _frameReadySignal,
                    onSeekGlobalFrame: (frame) =>
                        seekStoryboardGlobalFrame(_session, frame),
                    // Ruler drags ride the cursor path (the host rebuilds
                    // per cursor move — the same cost playback ticks pay);
                    // the release commits the selection once.
                    onScrubGlobalFrame: (frame) =>
                        scrubStoryboardGlobalFrame(_session, frame),
                    onScrubEnd: () => commitStoryboardScrub(_session),
                    readyRunsIn: (start, end) =>
                        storyboardReadyRuns(_session, start, end),
                    thumbnails: widget.thumbnails,
                    audioPeaksFor: _session.voiceRecording.audioPeaksForDisplay,
                    // The tooltip string doubles as the clip-marker switch
                    // (REC1-D), matching the timeline host: null while the
                    // clipping notice setting is off.
                    seClipMarkerTooltip:
                        _session.appSettings.audioSyncSettings.value.clippingNotice
                        ? _session.uiStrings.recordClipMarkerTooltip
                        : null,
                    // The V track's OWN Transform lanes (AE precomp: the
                    // whole picture moving on the screen; R4b: global axis,
                    // no cut needed) and the S rows' layer Transform lanes.
                    trackLaneEditFor: _trackLaneEditFor,
                    laneRange: TimelineLaneRangeHooks(
                      // This rail IS the track's global axis — the master
                      // one — so it reads and writes the span unshifted.
                      selection: _session.laneRangeSelection,
                      // C②: the span arrives resolved by the PANEL off its
                      // own row geometry — the stale hand-kept walk
                      // (transform lanes for a rail that draws fx lanes,
                      // null for every SE anchor) retired with it.
                      onSelectUpdate:
                          (layerId, laneId, anchorIndex, headIndex, span) =>
                              _session.updateLaneRangeSelectionDrag(
                                layerId: layerId,
                                laneId: laneId,
                                anchorIndex: anchorIndex,
                                headIndex: headIndex,
                                panel: WorkingPanel.storyboard,
                                spanLaneIds: span,
                              ),
                      // R10: a lane band is a place you can STAND. The
                      // storyboard's strips run on the GLOBAL axis, so the
                      // frame the tap reports is a global one.
                      //
                      // R5 #9: and it STANDS there. This used to seek and
                      // stop, so pressing a member's frame cell lit nothing
                      // here while the same press on the timeline moved the
                      // subject — the rail label was the only half of
                      // "stand" this panel had.
                      //
                      // C6 (2026-08-17): through THE standing verb, like the
                      // timeline's twin — the hand-rolled clear+seek that
                      // stood here restated `standOnRow` without its T10
                      // guard, and with standing on the DOWN now (the cells'
                      // press law) an unguarded clear would wipe the very
                      // lane selection a move-press was about to slide.
                      //
                      // Standing on THIS panel is this rail's one stated
                      // difference (유저 2026-07-27) — it also keeps a V
                      // row's SYNTHETIC carrier id out of the layer
                      // selection, which was the old shape's whole reason.
                      // ↩️The verb seats the timeline after it (F-187): a
                      // carrier id is no row of the cut, so it seats none.
                      onTapAt: (layerId, laneId, globalFrame) =>
                          _session.standOnRow(
                            LaneRowAddress(layerId, laneId),
                            panel: WorkingPanel.storyboard,
                            globalFrameIndex: globalFrame,
                          ),
                      // H18: the cells family's release rule, here too.
                      onTapClear: _session.clearLaneRangeSelection,
                      onActivateAt: (_, _, globalFrame) =>
                          unawaited(_activateLaneCell(globalFrame)),
                      onMoveBegin: _session.laneMove.beginLaneRangeMoveDrag,
                      onMoveUpdate: (frameDelta) => _session
                          .laneMove.updateLaneRangeMoveDrag(frameDelta: frameDelta),
                      onMoveEnd: _session.laneMove.endLaneRangeMoveDrag,
                      onMoveCancel: _session.laneMove.cancelLaneRangeMoveDrag,
                    ),
                    // R10 #19's rail half. Standing is not seeking, so a
                    // label press moves the SUBJECT and leaves the playhead
                    // (and the active cut) exactly where they were — the
                    // band's press is the one that lands on a frame.
                    currentRowHooks: TimelineCurrentRowHooks(
                      currentRow: _session.standing.currentRowListenable,
                      // T4: standing here clears too — 「어떤 행이든 액티브
                      // 바꾸면 풀리도록」 is not a timeline-only law.
                      onStandOnLane: (layerId, laneId) => _session.standOnRow(
                        LaneRowAddress(layerId, laneId),
                        panel: WorkingPanel.storyboard,
                      ),
                    ),
                    rowDragHooks: _rowDragHooks,
                    // The span half — the select hooks of [_rowDragHooks] only
                    // ARM the selection; without this the press would select
                    // one row and then refuse to grow.
                    onRowSelectionSpan:
                        _session.rowSelectionVerbs.updateRowSelectionOver,
                    rowSelection: _session.rowSelection,
                    layerLaneEdit: _layerLaneEdit,
                    cutLaneEdit: _cutLaneEdit,
                    // An S row's group headers: the timeline's own switch and
                    // reset (F-101).
                    onToggleLaneGroupEnabled: (layer, lane) =>
                        _session.laneVerbs.toggleLaneGroupEnabled(
                          layer.id,
                          lane.laneId,
                          description: 'Toggle ${lane.label}',
                        ),
                    onResetLaneGroup: (layer, lane) =>
                        _session.laneVerbs.resetLaneGroup(
                          layer.id,
                          lane.laneId,
                        ),
                    laneGroupOnOf: _session.laneVerbs.isLaneGroupOn,
                    poseDisplaySize: _session.camera.cameraFrameSize,
                    // No onSetCutFade: the fade handles went with the V row's
                    // transform. F.I/F.O spans on the transition row are the
                    // fade now — an always-visible row rather than two twirls
                    // deep, and the user did not want the block-edge drag kept
                    // ("애초에 마음에 안 들었었으니까", 2026-08-10).
                    // Timeline-parity layer controls on the ACTIVE cut's SE
                    // rows — the SAME session hooks the timeline host wires.
                    onToggleLayerVisibility: _rowPresses.toggleVisibility,
                    onOpenLayerMixer: (anchorContext, layerId) => unawaited(
                      showSeLayerMixer(
                        anchorContext,
                        session: _session,
                        layerId: layerId,
                      ),
                    ),
                    onOpenCameraPath: (anchorContext) =>
                        showCameraPathSettings(
                          anchorContext,
                          _session.appSettings.setCameraPathSettings,
                        ),
                    isLayerSoloed: (layerId) => _session
                        .visibilitySolo
                        .soloedSeLayerIds
                        .value
                        .contains(layerId),
                    onLayerOpacityChanged: _rowPresses.previewOpacity,
                    onLayerOpacityChangeEnd: _rowPresses.commitOpacity,
                    onLayerMarkSelected: _rowPresses.pickMark,
                    // B5③ (ordered twice): the timeline rows' sheet toggle on
                    // this rail too — the same session verb.
                    onToggleLayerTimesheet: _rowPresses.toggleTimesheet,
                    layerOnTimesheetOf: _session.layerSwitches.isLayerOnTimesheet,
                    layerEyeOnOf: _session.layerSwitches.isLayerEyeOn,
                    layerLanesOpenOf: _session.layerSwitches.isLayerLanesOpen,
                    layerFxStateOf: _session.effectsAndFx.layerFxState,
                    onToggleLayerFx: _rowPresses.toggleFx,
                    // The conte rows' heads are the timeline's rows (I-73):
                    // their blend is that rail's own verb.
                    onLayerBlendModeSelected: _rowPresses.pickBlendMode,
                    // The timeline's rail legend on this panel too (UI-R5): the
                    // same session-backed bulk flyouts, solos and master
                    // opacity bar (#904: every chip). ↩️The row solos stood
                    // down here, with no row filter, until then.
                    visibilitySoloEnabled: _session.visibilitySolo.layerVisibilitySoloEnabled,
                    // What its legend opens, for a key on this panel (I-40).
                    legendHand: _session.railLegends.handOf(
                      WorkingPanel.storyboard,
                    ),
                    legend: sessionLegendCallbacks(
                      _session,
                      rowFilter: widget.rowFilter,
                      onSetRowFilter: widget.onSetRowFilter,
                      // The blend column came to this rail with the conte
                      // row's head (I-73): its heading sweeps as the
                      // timeline's does.
                      onSetBlendModeForDisplayed:
                          _session.layerSwitches.setBlendModeForLayers,
                    ),
                    // Master-bar drags (UI-R6 #2): S-row sliders follow the
                    // preview channel live; the bar rests on the last committed
                    // value instead of an average.
                    opacityDragPreview: _session.opacityVerbs.dragPreview,
                    legendOpacityValue: _session.opacityVerbs.lastMasterOpacity,
                    // R9 #21: the TRACK's own fx master — persisted model
                    // state. ↩️Its picture eye and its static opacity stood
                    // beside it on the V row's head until I-73 (2026-10-08).
                    trackFxStateOf: (track) => _session.effectsAndFx.trackFxState(track.id),
                    onToggleTrackFx: (track) =>
                        _session.effectsAndFx.toggleTrackFx(track.id),
                    // The V row's chain: one effect's own bypass, from its lane
                    // group header.
                    onToggleTrackEffectEnabled: (track, effectId) =>
                        _session.effectsAndFx.toggleTrackEffectEnabled(track.id, effectId),
                    // R5: AE's group Reset on the V row's chain.
                    onResetTrackEffectGroup: (track, headerLaneId) =>
                        _session.effectsAndFx.resetTrackEffectGroup(track.id, headerLaneId),
                    // S-row range selection: the SAME track-axis selection the
                    // cut row paints, one row up. The timeline mounts its range
                    // gesture on every layer row (UI-R20 #2) and these rows had
                    // none, which is the last place the two panels' cells still
                    // behaved differently.
                    seSelect: StoryboardSeSelectCallbacks(
                      selectedRange: _session.trackFrameRangeSelection,
                      onDrag: _session.updateTrackRowRangeSelectionByFrame,
                      onClear: _session.clearStoryboardCutSelection,
                      // Sliding the selection: the timeline's own range-move
                      // machine, entered on the track axis (its sources commit
                      // to the global layer either way).
                      move: StoryboardRangeMoveCallbacks(
                        onBegin: (layerId) =>
                            _session.rangeMove.beginTrackRangeMoveDrag(layerId),
                        onUpdate: (frameDelta, targetLayerId) =>
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
                    // The ACTIVE cut's SE blocks reuse the timeline's comma
                    // edge grips (live preview + ONE undo per drag).
                    // The strip passes GLOBAL block starts (UI-R7 #5: every
                    // cut's blocks drag here, not just the active cut's).
                    seCommaDrag: TimelineCommaDragCallbacks(
                      onBegin: (layerId, blockStartIndex, edge) =>
                          _session.edgeDrag.beginExposureEdgeDrag(
                            layerId: layerId,
                            blockStartIndex: blockStartIndex,
                            edge: edge,
                            blockStartIsGlobal: true,
                          ),
                      onUpdate: _session.edgeDrag.updateExposureEdgeDrag,
                      onEnd: _session.edgeDrag.endExposureEdgeDrag,
                      onCancel: _session.edgeDrag.cancelExposureEdgeDrag,
                    ),
                    // The S rows' sound edits — the timeline's own (F-101).
                    audioLane: sessionAudioLaneCallbacks(_session),
                    // The TRANSITION row. This panel is its only editor: the
                    // row is track-owned and its spans address the global
                    // axis, so the cut timeline shows them read-only.
                    transitionDefById: _session.camera.cameraInstructionSet.defById,
                    transitionRowShown: _session.transitions.names.rowNamed,
                    rowsChannel: widget.rowsChannel,
                    // D26: crossing fades are refused and wear the red
                    // corner — the session answers by global key on this
                    // authoring axis, with the SAME predicate the ramp and
                    // のりしろ read.
                    transitionCrossingTooltip:
                        _session.transitions.transitionCrossingWarningAtGlobalKey,
                    transitionCommaDrag: TimelineCommaDragCallbacks(
                      onBegin: (layerId, blockStartIndex, edge) =>
                          _session.edgeDrag.beginTransitionEdgeDrag(
                            layerId: layerId,
                            spanStartIndex: blockStartIndex,
                            edge: edge,
                          ),
                      onUpdate: _session.edgeDrag.updateTransitionEdgeDrag,
                      onEnd: _session.edgeDrag.endTransitionEdgeDrag,
                      onCancel: _session.edgeDrag.cancelTransitionEdgeDrag,
                    ),
                    onEditTransitionSpan: _editTransitionSpan,
                    // B6: the SE blocks' same-cell double tap opens the SAME
                    // instance dialog the timeline's SE cells open, addressed
                    // on the global axis (this rail's standing row never
                    // moves the drawing target).
                    // 🚨★★★I-9: and an EMPTY one CREATES — one fork, inside
                    // that shared verb, exactly like the transition row's.
                    onEditSeEntry: _editSeEntry,
                    // F-255: the cut blocks and the conte blocks open their
                    // names on the same double tap.
                    onEditCutBlock: _editCutBlock,
                    onEditConteBlock: _editConteBlock,
                    // The CAMERA row (I-73 ④): a press stands in the cut it
                    // names, a double click is the timeline camera row's, and
                    // its head is that row's.
                    onCameraCutPress: _pressCameraCut,
                    onEditCameraCell: () => unawaited(_editCameraCell()),
                    // A projection row's lane labels read the cut stood in
                    // at its own frame and walk its keys there, as the
                    // timeline's lane labels do (I-73 ④ⓔ).
                    cutFrameCursor: _session.playheadCursors.cutFrame,
                    onSeekCutFrame: (cutId, ownFrame) =>
                        seekStoryboardCutFrame(_session, cutId, ownFrame),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// B8: caches the storyboard's action toolbar and rebuilds it ONLY when
/// what its buttons SHOW changes — the timeline host's seek-gate pattern
/// (`_SeekGatedTimelineToolbar`), said of THIS panel's gates.
///
/// It has to exist here now: the bar used to render nothing a committed
/// seek could change (the old comment on [_StoryboardTabHostState.build]),
/// but B8 made the frame/shared gates read the CURSOR — the standing row ×
/// the global playhead — and neither a seek, a standing move, a gap
/// parking, nor a selection change is a session notify.
///
/// COMPLETENESS CONTRACT (the timeline gate's, restated): any NEW
/// directly-rendered value the storyboard context serves MUST join
/// [_CursorGatedStoryboardToolbarState._deriveToken], and if its source
/// does not travel through a host rebuild it needs a listener too.
class _CursorGatedStoryboardToolbar extends StatefulWidget {
  const _CursorGatedStoryboardToolbar({
    required this.session,
    required this.actionsBuilder,
  });

  final EditorSessionManager session;
  final WidgetBuilder actionsBuilder;

  @override
  State<_CursorGatedStoryboardToolbar> createState() =>
      _CursorGatedStoryboardToolbarState();
}

class _CursorGatedStoryboardToolbarState
    extends State<_CursorGatedStoryboardToolbar> {
  // Eager for the timeline gate's reason: a `late` initializer would run on
  // first access, which can coincide with the very signal it must catch.
  late Object _token;

  Widget? _cached;

  /// Every signal that can move a gate WITHOUT a session notify. The host
  /// rebuild (a notify) funnels through [didUpdateWidget].
  List<Listenable> get _signals => _signalsOf(widget);

  /// Every value the toolbar's directly-rendered widgets read from THIS
  /// panel's context. ↩️The blank X, the mark, the cell clipboard four and
  /// 링크 독립 were absent as constants — a cell band makes them the
  /// timeline's answers now (F-186), and a band moves nothing else here.
  Object _deriveToken() {
    final panel = StoryboardToolbarPanelContext(widget.session);
    return (
      panel.canCreateInstance,
      panel.canSetComma,
      panel.canEditInstance,
      panel.deleteSubject,
      panel.canBlankExposure,
      panel.canToggleMark,
      panel.canCutRun,
      panel.canCopyFrame,
      panel.canPasteIndependentFrame,
      panel.canPasteLinkedFrame,
      panel.canUnlink,
      // I-18: 자동 이름 지정 lights over a cut and dims in a gap — the
      // playhead moves it, and a playhead move is no notify.
      panel.canAutoName,
      // F-75: the 색 편집 head on this bar reads the session's own answer —
      // whether the cel under the playhead has a drawing — which none of the
      // entries above moves with. (I-55: the head's gate is every row's now.)
      widget.session.pixelVerbs.canOpenColourEdit,
      // The shift pair aims at the standing row, passed by VALUE.
      widget.session.selectedRow,
      widget.session.languageSettings.value,
    );
  }

  void _handleExternalSignal() {
    final next = _deriveToken();
    if (next != _token) {
      setState(() {
        _token = next;
        _cached = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _token = _deriveToken();
    for (final signal in _signals) {
      signal.addListener(_handleExternalSignal);
    }
  }

  @override
  void didUpdateWidget(covariant _CursorGatedStoryboardToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      for (final signal in _signalsOf(oldWidget)) {
        signal.removeListener(_handleExternalSignal);
      }
      for (final signal in _signals) {
        signal.addListener(_handleExternalSignal);
      }
      _cached = null;
    }
    final next = _deriveToken();
    if (next != _token) {
      _token = next;
      _cached = null;
    }
  }

  static List<Listenable> _signalsOf(_CursorGatedStoryboardToolbar widget) => [
    // #10 (2026-08-21): ONE channel for the playhead, shared with the
    // timeline's bar and the shift pair. This listed the committed seek
    // and the gap parking by hand and missed the cursor, so a ruler drag
    // INSIDE the film left the bar answering about the frame the drag
    // began on — a committed seek fires on the release.
    widget.session.playheadMoved,
    widget.session.standing.currentRowListenable,
    widget.session.languageSettings,
    // The selections the gates read are notifiers on purpose (they grow
    // per pointer move): the S-row/cut range, the strip's cut-local range,
    // and lane spans.
    widget.session.trackFrameRangeSelection,
    widget.session.frameRangeSelection,
    widget.session.laneRangeSelection,
    // F-75: the token carries `canRunPixelVerb`, and a cel emptied in place
    // (픽셀 비우기) moves that answer with no seek and no session notify —
    // its one signal is the tint's crossing. Unheard, the token kept the
    // answer from before the clear, and a seek onto a drawn cel then read
    // "unchanged" and left the head dim. ↩️The thumbnail store's landing
    // rebuilt this whole panel and re-derived the token by accident, until
    // the store left the panel's merge. (The timeline's gate does not list
    // it: that host rebuilds on the clear itself, measured, and its F-75 pin
    // holds without it.)
    widget.session.layerStack.celTintRevision,
  ];

  @override
  void dispose() {
    for (final signal in _signals) {
      signal.removeListener(_handleExternalSignal);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _cached ??= widget.actionsBuilder(context);
}

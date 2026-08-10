import 'dart:async';

import 'package:flutter/material.dart';


import '../models/camera_instruction.dart' show InstructionEvent;
import '../models/cut_id.dart';
import 'dialogs/instruction_event_dialog.dart';
import '../models/layer_id.dart';
import '../models/timeline_row_address.dart';
import '../models/track.dart';
import '../models/track_transform_lane_carrier.dart';
import '../models/transform_track.dart';
import 'cut_command_group.dart';
import 'editor_session_manager.dart';
import 'panels/panel_collapsed_scope.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnailResolver;
import 'storyboard_panel.dart';
import 'timeline/timeline_row_filter.dart' show TimelineRowFilter;
import 'timeline/layer_rail_window.dart' show LayerRailExtent;
import '../models/layer_effect.dart' show LayerEffect;
import 'timeline/effect_lane_editing.dart'
    show effectsWithLaneKeyToggled, effectsWithLaneValueEdited;
import 'timeline/effect_lane_policy.dart' show laneIsEffectLane;
import 'timeline/property_lane_model.dart' show PropertyLaneEditCallbacks;
import 'timeline/layer_row_drag.dart' show TimelineRowDragHooks;
import 'timeline/se_layer_mixer.dart';
import 'timeline/timeline_current_row.dart';
import 'timeline/timeline_layer_controls_header.dart' show LayerLegendCallbacks;
import 'timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'storyboard_playhead_mapping.dart';
import 'storyboard_timeline_layout.dart';
import 'text/app_strings.dart';
import 'timeline/timeline_frame_range_gesture.dart'
    show TimelineLaneRangeCallbacks;
import 'timeline/timeline_shift_buttons.dart';
import 'timeline/timeline_command_bar.dart';
import 'timeline/timeline_view_cluster.dart';
import 'track_fx_command_group.dart';
import 'timeline/transform_lane_editing.dart';
import 'timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;

/// The Storyboard tab's content: its own toolbar row (frame counter,
/// seconds toggle, zoom slider — the same keys as the timeline tab's, only
/// one is ever on screen), the all-cuts transport, the storyboard panel and
/// the cut dialogs it triggers. All wiring lives HERE (not in HomePage).
class StoryboardTabHost extends StatefulWidget {
  const StoryboardTabHost({
    super.key,
    required this.session,
    required this.pixelsPerFrame,
    required this.onPixelsPerFrameChanged,
    required this.showSeconds,
    required this.onShowSecondsChanged,
    this.railExtent,
    this.trackLaneHeight = StoryboardPanel.defaultTrackLaneHeight,
    this.onTrackLaneHeightChanged,
    required this.thumbnailFor,
    this.rowFilter = TimelineRowFilter.none,
    this.onSetRowFilter,
  });

  /// The legend's row filter, shared with the timeline and the sheet
  /// (R5 #9). Null [onSetRowFilter] leaves the chips inert.
  final TimelineRowFilter rowFilter;
  final ValueChanged<TimelineRowFilter>? onSetRowFilter;

  /// The shortest this tab is laid out at — the dock splitter's floor and
  /// the tab shell's minimum content height. See
  /// [StoryboardPanel.minPanelHeight] for the two-row rule.
  ///
  /// The bar's own height is [TimelineCommandBar.height], which the
  /// timeline reads too. The two used to measure themselves separately and
  /// come back 18px apart.
  static const double minPanelHeight =
      TimelineCommandBar.height + StoryboardPanel.minPanelHeight;

  final EditorSessionManager session;
  final double pixelsPerFrame;
  final ValueChanged<double> onPixelsPerFrameChanged;
  final bool showSeconds;
  final ValueChanged<bool> onShowSecondsChanged;

  /// This panel's rail window size (workspace-owned so it survives a tab
  /// switch AND a restart).
  final LayerRailExtent? railExtent;

  /// The V rows' shared height, owned above the tabs so it survives a tab
  /// switch like the zoom does. A null setter keeps the rows fixed and
  /// stands the steppers down.
  final double trackLaneHeight;
  final ValueChanged<double>? onTrackLaneHeightChanged;

  /// Build-time thumbnail resolver, owned above the tabs so the cache
  /// survives tab switches.
  final StoryboardThumbnailResolver? thumbnailFor;

  // ⛔The camera-view notifier is no longer this host's business. R28 #1 put
  // the toggle beside the transport, and the transport moved to the 문턱
  // (2026-08-10) — the workspace hands both to [FramePanelSillControls] now,
  // so this panel neither mounts the button nor needs the state behind it.

  @override
  State<StoryboardTabHost> createState() => _StoryboardTabHostState();
}

class _StoryboardTabHostState extends State<StoryboardTabHost> {
  EditorSessionManager get _session => widget.session;

  /// Rail view state (twirled-down lanes, Transform group collapse).
  /// Session-scoped like the timeline's lane expansion; lost on tab switch
  /// for now (the host rebuilds) — hoist to the workspace if that stings.
  final Set<String> _expandedSeAudioRows = {};
  final Set<String> _expandedTransformTracks = {};
  final Set<String> _expandedTransformGroups = {};

  /// The storyboard playhead's track-global frame — the cursor-layer
  /// pattern (W4 perf pass): scrub moves, committed seeks, playback ticks
  /// and session changes update THIS notifier, and only the panel's
  /// playhead overlay + ruler subscribe. The panel itself (strips, blocks,
  /// rails, waveforms) never rebuilds on a tick.
  final ValueNotifier<int?> _playheadGlobalFrame = ValueNotifier<int?>(null);

  /// The ACTIVE cut's LOCAL playhead, as a channel (timeline parity with
  /// [_TimelineTabHostState]'s `_frameCursor`): the rail's lane labels read
  /// the value at the cursor and subscribe to THIS, so a committed seek
  /// repaints those cells instead of rebuilding the panel.
  late final ValueNotifier<int> _activeCutFrameCursor = ValueNotifier<int>(
    _session.currentFrameIndex,
  );

  /// Whatever can change a frame's cached-ness — warm progress AND pixel
  /// edits (composites self-validate by signature, so an edit raises no
  /// event of its own). The ruler's green bar repaints off this; the
  /// timeline host carries the identical signal.
  late final Listenable _frameCachedSignal = Listenable.merge([
    _session.prerenderScheduler.progress,
    _session.brushFrameStore.celPixelRevision,
  ]);

  /// Identity-memoized active-track layout (R12-⑥): the playhead refresh
  /// fires per playback tick and the ruler's green bar asks per visible
  /// frame column per repaint — none of them may rebuild the layout list
  /// each time. Cuts are immutable, so the project + active cut identity
  /// pair decides staleness.
  List<StoryboardTimelineLayoutEntry>? _trackLayoutCache;
  Object? _trackLayoutProject;
  CutId? _trackLayoutActiveCutId;

  List<StoryboardTimelineLayoutEntry> _activeTrackLayout() {
    final project = _session.repository.requireProject();
    final activeCutId = _session.activeCutId;
    if (_trackLayoutCache == null ||
        !identical(project, _trackLayoutProject) ||
        activeCutId != _trackLayoutActiveCutId) {
      _trackLayoutProject = project;
      _trackLayoutActiveCutId = activeCutId;
      _trackLayoutCache = storyboardActiveTrackLayout(_session);
    }
    return _trackLayoutCache!;
  }

  void _refreshPlayheadGlobalFrame() {
    _playheadGlobalFrame.value = storyboardPlayheadFrame(
      _session,
      layout: _activeTrackLayout(),
    );
    _activeCutFrameCursor.value = _session.currentFrameIndex;
  }

  // ⛔"To start" (REC1-B) is a free function now
  // ([seekStoryboardPlayheadToTrackStart]): the button that calls it is the
  // 문턱's, built by the workspace, and the layout cache it wants lives here.
  // One implementation, two possible callers, no host method to reach for.

  @override
  void initState() {
    super.initState();
    _refreshPlayheadGlobalFrame();
    _session.addListener(_refreshPlayheadGlobalFrame);
    _session.editingFrameCursor.addListener(_refreshPlayheadGlobalFrame);
    _session.frameSeekCommitted.addListener(_refreshPlayheadGlobalFrame);
    // Gap scrubs park per move (UI-R7 #9); the leading gap pins the
    // cut-local cursor at 0, so the parking is the only move signal there.
    _session.gapParkingListenable.addListener(_refreshPlayheadGlobalFrame);
    _session.playback.globalFrameIndexListenable.addListener(
      _refreshPlayheadGlobalFrame,
    );
  }

  @override
  void dispose() {
    _session.removeListener(_refreshPlayheadGlobalFrame);
    _session.editingFrameCursor.removeListener(_refreshPlayheadGlobalFrame);
    _session.frameSeekCommitted.removeListener(_refreshPlayheadGlobalFrame);
    _session.gapParkingListenable.removeListener(_refreshPlayheadGlobalFrame);
    _session.playback.globalFrameIndexListenable.removeListener(
      _refreshPlayheadGlobalFrame,
    );
    _playheadGlobalFrame.dispose();
    _activeCutFrameCursor.dispose();
    super.dispose();
  }

  void _toggleSetEntry(Set<String> set, String key) {
    setState(() {
      if (!set.add(key)) {
        set.remove(key);
      }
    });
  }

  /// Lane edit hooks for the V TRACK's own lanes — its EFFECT chain, which is
  /// all a track row has since the transform teardown
  /// ([timelineRowOwnsTransform]). Keys land on the GLOBAL axis and commit as
  /// ONE undo through the session, exactly as a layer effect's do.
  ///
  /// A transform lane cannot reach here any more: the rail builds none for a
  /// track row, so the dispatch is effects or nothing.
  PropertyLaneEditCallbacks _trackLaneEditFor(Track track) {
    void commitEffects(List<LayerEffect>? next, String description) {
      if (next == null) {
        return;
      }
      _session.updateTrackEffects(track.id, next, description: description);
    }

    return PropertyLaneEditCallbacks(
      onToggleKeyAt: (_, lane, frameIndex) {
        if (!laneIsEffectLane(lane)) {
          return;
        }
        commitEffects(
          effectsWithLaneKeyToggled(
            track.effects,
            laneId: lane.laneId,
            frameIndex: frameIndex,
          ),
          '${lane.label} keyframe at frame ${frameIndex + 1}',
        );
      },
      onSetValue: (_, lane, frameIndex, input) {
        if (!laneIsEffectLane(lane)) {
          return;
        }
        commitEffects(
          effectsWithLaneValueEdited(
            track.effects,
            laneId: lane.laneId,
            frameIndex: frameIndex,
            input: input,
          ),
          'Set ${lane.label} at frame ${frameIndex + 1}',
        );
      },
    );
  }

  /// The storyboard's lane-span head mapping (R26 #3 Excel rule): the
  /// pointer's row offset from the anchor lane row, walked over the V
  /// lanes' DISPLAYED rows — the header alone when the group is folded,
  /// header + members when twirled open (the Opacity slot is the fade
  /// envelope row, not a lane band row).
  String? _laneSpanHeadLane(
    LayerId carrierId,
    String anchorLaneId,
    int headRowDelta,
  ) {
    if (headRowDelta == 0) {
      return null;
    }
    final trackId = trackIdOfTransformLaneCarrier(carrierId);
    if (trackId == null) {
      return null;
    }
    // Screen rows only: the Opacity slot is the fade-envelope row, so the
    // walk skips it (a header endpoint still spans the whole group,
    // opacity included — [transformLaneSpan]'s rule).
    final rows = [
      transformGroupHeaderLane.laneId,
      if (_expandedTransformGroups.contains(trackId.value))
        ...transformLaneDisplayOrder.where((laneId) => laneId != 'opacity'),
    ];
    final anchor = rows.indexOf(anchorLaneId);
    if (anchor < 0) {
      return null;
    }
    final head = (anchor + headRowDelta).clamp(0, rows.length - 1).toInt();
    return rows[head];
  }

  /// Lane edit hooks for the S rows' Transform lanes — the timeline
  /// host's layer-transform editing verbatim (SE layers only here; no
  /// camera or audio-lane dispatch on these lanes).
  PropertyLaneEditCallbacks get _layerLaneEdit => PropertyLaneEditCallbacks(
    onToggleKeyAt: (layer, lane, frameIndex) => _commitLayerLaneEdit(
      layer.id,
      transformTrackWithLaneKeyToggled(
        layer.transformTrack,
        laneId: lane.laneId,
        frameIndex: frameIndex,
        resolvedPose: _session.layerPoseAtFrame(layer, frameIndex),
        resolvedAnchorPoint: _session.layerAnchorPointAtFrame(
          layer,
          frameIndex,
        ),
        resolvedOpacity: _session.layerOpacityAtFrame(layer, frameIndex),
      ),
      '${lane.label} keyframe at frame ${frameIndex + 1}',
    ),
    onSetValue: (layer, lane, frameIndex, input) => _commitLayerLaneEdit(
      layer.id,
      transformTrackWithLaneValueEdited(
        layer.transformTrack,
        laneId: lane.laneId,
        frameIndex: frameIndex,
        input: input,
      ),
      'Set ${lane.label} at frame ${frameIndex + 1}',
    ),
  );

  void _commitLayerLaneEdit(
    LayerId layerId,
    TransformTrack? next,
    String description,
  ) {
    if (next == null) {
      return;
    }
    _session.updateLayerTransformTrack(layerId, next, description: description);
  }

  /// The transition span's term dialog — the direction row's dialog verbatim,
  /// with two differences: the picker's vocabulary is filtered to the 場面
  /// 転換 terms, and the vocabulary EDITOR is not offered (it commits the
  /// whole set, so editing a filtered copy would drop the camera-work terms).
  ///
  /// Length is NOT taken from the dialog: the grips own it here, so a re-pick
  /// can never resize the span out from under the boundary it fires across.
  Future<void> _editTransitionSpan(int globalFrame) async {
    final covering = _session.transitionSpanAt(globalFrame);
    if (covering == null) {
      return;
    }
    final result = await showDialog<InstructionEventDialogResult>(
      context: context,
      builder: (context) => InstructionEventDialog(
        instructionSet: _session.transitionInstructionSet,
        initialInstructionId: covering.value.instructionId,
        initialText: covering.value.text,
        initialValueA: covering.value.valueA,
        initialValueB: covering.value.valueB,
        initialMemo: covering.value.memo,
        editing: true,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    if (result.delete) {
      _session.removeTransitionSpanAt(globalFrame);
      return;
    }
    final instructionId = result.instructionId;
    if (instructionId == null) {
      return;
    }
    _session.replaceTransitionEventAt(
      globalFrame,
      InstructionEvent(
        instructionId: instructionId,
        length: covering.value.length,
        text: result.text,
        valueA: result.valueA,
        valueB: result.valueB,
        memo: result.memo,
      ),
    );
  }

  /// ONE command-bar row — the timeline's own widget now, not a parallel
  /// copy of it: transport + cut group left, the shared view cluster right.
  Widget _commandBar(BuildContext context) {
    return TimelineCommandBar(
      // Barred like the timeline's (유저, 2026-08-10: 「버튼 사라지기
      // 시작하면 생기는 스크롤바」) — the app's overflow bar exists only
      // while it overflows and costs no layout when it does not.
      leading: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ⛔The TRANSPORT and the camera-view toggle left this bar
                  // (유저 확정, 2026-08-10): they are the 문턱's now, mounted
                  // by the workspace through `EditorPanelTab.sillTrailing`
                  // (see [FramePanelSillControls]). What stays here is what
                  // reaches into THIS panel's own contents.
                  CutCommandGroup(session: _session),
                  const SizedBox(width: 6),
                  // The V row's fx (user 2026-08-08): a chain over the whole
                  // composited cut, authored from this panel.
                  TrackFxCommandGroup(session: _session),
                  const SizedBox(width: 6),
                  // ⚠️The LAYER and FRAME pills are not here yet. The
                  // storyboard needs them — 유저: 스토리보드 레이어의 프레임을
                  // 조절해야 하고 레이어도 만들고 지워야 한다 — but they are
                  // the timeline host's dialog flows (rename layer, delete
                  // layer, the kind-dispatched instance editor), and lifting
                  // those out is a refactor of that host rather than a line
                  // here. Until then this panel keeps the two nouns it can
                  // honestly serve.
                  //
                  // THE push/pull pair, the timeline rail's own widget: the
                  // rail asks as ITSELF, so with nothing selected the shove
                  // aims at the row this rail is on (a cut row shoves cuts,
                  // an S row shoves sounds).
                  // ⛔These two are deliberately NOT in a pill. A pill is a
                  // noun and its verbs; these are loose verbs whose noun is
                  // not on this bar yet — push/pull belongs to the FRAME
                  // pill (it is a frame-axis shove) and it will move there
                  // when that pill arrives. Inventing a "rows" noun to hold
                  // them in the meantime would be a border drawn around a
                  // gap.
                  TimelineShiftButtons(
                    session: _session,
                    currentRow: _session.selectedRow,
                  ),
                  const SizedBox(width: 4),
                  // V ROW HEIGHT — one pair for every V track, because there
                  // is one height (user's rule). Steppers rather than a
                  // slider: this panel is worked on an iPad, and the
                  // push/pull pair beside it already reads that way.
                  _TrackLaneHeightButtons(
                    height: widget.trackLaneHeight,
                    onChanged: widget.onTrackLaneHeightChanged,
                  ),
                ],
              ),
            ),
      ),
      cluster: TimelineViewCluster(
        frameCursor: _session.editingFrameCursor,
        // Global · cut-local pair (UI-R9 #6) — the channel already
        // follows scrubs, gap parking and playback ticks.
        globalFrame: _playheadGlobalFrame,
        projectFrameRate: _session.projectFrameRate,
        showSeconds: widget.showSeconds,
        pixelsPerFrame: widget.pixelsPerFrame,
        onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // No per-tick host rebuild (W4 perf pass): playback ticks and scrub
    // moves ride _playheadGlobalFrame into the panel's playhead overlay +
    // ruler; the green bar rides the prerender progress into the ruler;
    // the counter subscribes to the cursor. Cut crossings during playback
    // still notify the session (cut follow), which rebuilds the host from
    // the workspace subscription.
    // The panel being worked in owns the frame-axis verbs (user,
    // 2026-08-05): touching the storyboard hands the flip its rail's row,
    // so the arrows count CUTS from here without having to pick a row
    // first. Translucent — this only listens.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _session.claimStoryboardRow(),
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
                listenable: _session.voiceRecordPreviewLane,
                builder: (context, _) => StoryboardPanel(
                  project: _session.repository.requireProject(),
                  rowFilter: widget.rowFilter,
                  seLanePreview: _session.voiceRecordPreviewLane.value,
                  dragPreview: _session.dragPreview,
                  // While playing, the highlight follows the PLAYING cut
                  // (onStopped syncs the real active cut).
                  activeCutId: _session.playback.isActive
                      ? _session.playback.position?.cutId ??
                            _session.activeCutId
                      : _session.activeCutId,
                  // THE cells' press (the timeline's cell contract): pick the
                  // row, then seek to the frame under the pointer. The seek
                  // is the ruler's own, so a press in a GAP parks there — an
                  // empty cell is still a cell, and the two paths cannot
                  // disagree about what a frame means.
                  //
                  // The row half comes FIRST and does only the row: a track
                  // row that promoted the playhead's cut here would switch
                  // cuts twice, since the pressed frame decides the cut.
                  onRowFramePress: (row, globalFrame) {
                    switch (row) {
                      case LayerRowAddress():
                        _session.selectRow(row);
                        // An SE row owns no cuts, so pressing one says where
                        // you ARE without saying which cut you are editing
                        // (feedback #7): the playhead lands and the active
                        // cut is RELEASED, even where the V row has one. The
                        // canvas then shows the parked composite. Taking a
                        // cut active is the cut row's own verb.
                        parkStoryboardGlobalFrame(_session, globalFrame);
                      case LaneRowAddress():
                        // A property strip owns no cuts either, so it lands
                        // the same way an S row does — where you are, not
                        // which cut you edit.
                        _session.selectRow(row);
                        parkStoryboardGlobalFrame(_session, globalFrame);
                      case TrackRowAddress(:final trackId):
                        _session.selectTrackRow(trackId);
                        seekStoryboardGlobalFrame(_session, globalFrame);
                    }
                  },
                  activeLayerId: _session.activeLayerId,
                  // The rail speaks ROW ADDRESSES, and selecting one lands
                  // the editing focus on it (user 2026-07-29, superseding
                  // #741's "row picks never move the focus"): an S row
                  // releases the active cut and PARKS where the playhead
                  // stands — the same landing its own cell press makes — and
                  // a V row promotes that track's playhead-index cut (gap =
                  // park, the same sentence).
                  selectedRow: _session.selectedRow,
                  onSelectLayer: (layerId) {
                    _session.selectRow(LayerRowAddress(layerId));
                    final frame = storyboardPlayheadFrame(_session);
                    if (frame != null) {
                      parkStoryboardGlobalFrame(_session, frame);
                    }
                  },
                  onSelectTrack: (trackId) =>
                      _session.selectRow(TrackRowAddress(trackId)),
                  pixelsPerFrame: widget.pixelsPerFrame,
                  trackLaneHeight: widget.trackLaneHeight,
                  showSeconds: widget.showSeconds,
                  onShowSecondsChanged: widget.onShowSecondsChanged,
                  railExtent: widget.railExtent,
                  projectFrameRate: _session.projectFrameRate,
                  // The strip's edges preview live and commit ONE undo on
                  // release, like the timeline's comma drags. Which verb a
                  // drag belongs to is settled at BEGIN — by where the grip
                  // sat — and the SESSION keeps that answer (feedback #5's
                  // first attempt kept it here, where a rebuild mid-drag
                  // could re-route the release onto a verb whose fields
                  // were never set): the continuations are one funnel.
                  stripEdges: StoryboardStripEdgeCallbacks(
                    onCutEdgeBegin: (cutId, edge, panelIndex) =>
                        _session.beginCutEdgeDrag(
                          cutId: cutId,
                          edge: edge,
                          panelIndex: panelIndex,
                        ),
                    onCommaBegin: (cutId, blockStartIndex) =>
                        _session.beginStoryboardCommaDrag(
                          cutId: cutId,
                          blockStartIndex: blockStartIndex,
                        ),
                    onUpdate: _session.updateCutEdgeDrag,
                    onEnd: _session.endCutEdgeDrag,
                    onCancel: _session.cancelCutEdgeDrag,
                  ),
                  // Whole-block moves (R10-④): a drag re-times the cut where
                  // it has room and REORDERS the track where it reaches past
                  // a neighbour — one rule, one undo per drag.
                  cutMove: StoryboardCutMoveCallbacks(
                    onBegin: _session.beginCutMoveDrag,
                    onUpdate: _session.updateCutMoveDrag,
                    onEnd: _session.endCutMoveDrag,
                    onCancel: _session.cancelCutMoveDrag,
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
                      onBegin: _session.beginFrameRangeMoveDrag,
                      onUpdate: (frameDelta, targetLayerId) =>
                          _session.updateFrameRangeMoveDrag(
                            frameDelta: frameDelta,
                            targetLayerId: targetLayerId,
                          ),
                      onEnd: _session.endFrameRangeMoveDrag,
                      onCancel: _session.cancelFrameRangeMoveDrag,
                    ),
                  ),
                  // The end line edits the MOVIE length (UI-R20 #3): the
                  // project's trailing gap, never the cuts.
                  movieEnd: StoryboardMovieEndCallbacks(
                    onBegin: _session.beginMovieEndDrag,
                    onUpdate: _session.updateMovieEndDrag,
                    onEnd: _session.endMovieEndDrag,
                    onCancel: _session.cancelMovieEndDrag,
                  ),
                  playheadFrame: _playheadGlobalFrame,
                  revealSelectionTick: _session.revealSelectionTick,
                  frameCachedSignal: _frameCachedSignal,
                  onSeekGlobalFrame: (frame) =>
                      seekStoryboardGlobalFrame(_session, frame),
                  // Ruler drags ride the cursor path (the host rebuilds
                  // per cursor move — the same cost playback ticks pay);
                  // the release commits the selection once.
                  onScrubGlobalFrame: (frame) =>
                      scrubStoryboardGlobalFrame(_session, frame),
                  onScrubEnd: () => commitStoryboardScrub(_session),
                  isFrameCached: (frame) => storyboardFrameCached(
                    _session,
                    frame,
                    layout: _activeTrackLayout(),
                  ),
                  thumbnailFor: widget.thumbnailFor,
                  audioPeaksFor: _session.audioPeaksForDisplay,
                  // The tooltip string doubles as the clip-marker switch
                  // (REC1-D), matching the timeline host: null while the
                  // clipping notice setting is off.
                  seClipMarkerTooltip:
                      _session.audioSyncSettings.value.clippingNotice
                      ? _session.uiStrings.recordClipMarkerTooltip
                      : null,
                  // Rail parity with the timeline rows: twirl-down audio
                  // lanes and the V track's cut-fade (Opacity) lane.
                  expandedSeAudioRows: _expandedSeAudioRows,
                  onToggleSeRowLane: (track, slot) => _toggleSetEntry(
                    _expandedSeAudioRows,
                    StoryboardPanel.seRowKey(track, slot),
                  ),
                  expandedTransformTracks: _expandedTransformTracks,
                  onToggleTrackLane: (track) =>
                      _toggleSetEntry(_expandedTransformTracks, track.id.value),
                  // AE group collapse for the V tracks' and S rows'
                  // Transform groups (default collapsed).
                  expandedTransformGroups: _expandedTransformGroups,
                  onToggleTransformGroup: (groupKey) =>
                      _toggleSetEntry(_expandedTransformGroups, groupKey),
                  // The V track's OWN Transform lanes (AE precomp: the
                  // whole picture moving on the screen; R4b: global axis,
                  // no cut needed) and the S rows' layer Transform lanes.
                  trackLaneEditFor: _trackLaneEditFor,
                  laneRange: TimelineLaneRangeCallbacks(
                    // This rail IS the track's global axis — the master
                    // one — so it reads and writes the span unshifted.
                    selection: _session.laneRangeSelection,
                    onSelectUpdate:
                        (
                          layerId,
                          laneId,
                          anchorIndex,
                          headIndex,
                          headRowDelta,
                        ) => _session.updateLaneRangeSelectionDrag(
                          layerId: layerId,
                          laneId: laneId,
                          anchorIndex: anchorIndex,
                          headIndex: headIndex,
                          framesAreGlobal: true,
                          headLaneId: _laneSpanHeadLane(
                            layerId,
                            laneId,
                            headRowDelta,
                          ),
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
                    // ⛔`selectLayer` is deliberately absent, unlike the
                    // timeline's twin: a V row's lanes hang off a SYNTHETIC
                    // carrier id (the track's transform substrate), and
                    // handing that to the layer selection would name a
                    // layer that does not exist. The label press next door
                    // has always taken this shape for the same reason;
                    // what the BAND adds over it is the seek.
                    onTapAt: (layerId, laneId, globalFrame) {
                      _session.clearLaneRangeSelection();
                      _session.selectGlobalFrame(globalFrame);
                      _session.selectRow(LaneRowAddress(layerId, laneId));
                    },
                    onMoveBegin: _session.beginLaneRangeMoveDrag,
                    onMoveUpdate: (frameDelta) => _session
                        .updateLaneRangeMoveDrag(frameDelta: frameDelta),
                    onMoveEnd: _session.endLaneRangeMoveDrag,
                    onMoveCancel: _session.cancelLaneRangeMoveDrag,
                  ),
                  // R10 #19's rail half. Standing is not seeking, so a
                  // label press moves the SUBJECT and leaves the playhead
                  // (and the active cut) exactly where they were — the
                  // band's press is the one that lands on a frame.
                  currentRowHooks: TimelineCurrentRowHooks(
                    currentRow: _session.currentRowListenable,
                    onStandOnLane: (layerId, laneId) =>
                        _session.selectRow(LaneRowAddress(layerId, laneId)),
                  ),
                  // The S rows take the rail's row-order drag; the V rows
                  // are tracks and keep their order.
                  rowDragHooks: TimelineRowDragHooks(
                    drag: _session.layerRowDrag,
                    onBegin: _session.beginLayerRowDrag,
                    onUpdate: _session.updateLayerRowDrag,
                    onRowTarget: _session.updateLayerRowDropOnRow,
                    // R5 #9: the V row re-orders TRACKS, and the track list
                    // is the composite order (user, 2026-08-09) — so this
                    // is only offered where tracks are on screen.
                    onTrackUpdate: _session.updateTrackRowDrag,
                    onEffectUpdate: _session.updateEffectRowDrag,
                    onEnd: _session.endLayerRowDrag,
                    onCancel: _session.cancelLayerRowDrag,
                  ),
                  layerLaneEdit: _layerLaneEdit,
                  activeCutFrameCursor: _activeCutFrameCursor,
                  onSelectFrameIndex: _session.selectFrameIndex,
                  poseDisplaySize: _session.cameraFrameSize,
                  // No onSetCutFade: the fade handles went with the V row's
                  // transform. F.I/F.O spans on the transition row are the
                  // fade now — an always-visible row rather than two twirls
                  // deep, and the user did not want the block-edge drag kept
                  // ("애초에 마음에 안 들었었으니까", 2026-08-10).
                  // Timeline-parity layer controls on the ACTIVE cut's SE
                  // rows — the SAME session hooks the timeline host wires.
                  onToggleLayerVisibility: _session.toggleLayerVisibility,
                  onOpenLayerMixer: (anchorContext, layerId) => unawaited(
                    showSeLayerMixer(
                      anchorContext,
                      session: _session,
                      layerId: layerId,
                    ),
                  ),
                  isLayerSoloed: (layerId) =>
                      _session.soloedSeLayerIds.value.contains(layerId),
                  onLayerOpacityChanged: _session.previewLayerOpacity,
                  onLayerOpacityChangeEnd: _session.commitLayerOpacity,
                  onLayerMarkSelected: _session.setLayerMark,
                  layerFxStateOf: _session.layerFxState,
                  onToggleLayerFx: _session.toggleLayerFx,
                  // The timeline's rail legend on this panel too (UI-R5): the
                  // same session-backed bulk flyouts + master opacity bar; the
                  // row solos stand down (the storyboard rail is track-global,
                  // no row filter here).
                  visibilitySoloEnabled: _session.layerVisibilitySoloEnabled,
                  legend: LayerLegendCallbacks(
                    onShowAllLayers: () =>
                        _session.setAllLayersVisibility(true),
                    onHideAllLayers: () =>
                        _session.setAllLayersVisibility(false),
                    onToggleVisibilitySolo: _session.toggleLayerVisibilitySolo,
                    onSheetAllOn: () => _session.setAllLayersOnTimesheet(true),
                    onSheetAllOff: () =>
                        _session.setAllLayersOnTimesheet(false),
                    onClearAllMarks: _session.clearAllLayerMarks,
                    onClearAllFillReferences: _session.clearAllFillReferences,
                    onMuteAllSe: () => _session.setAllSeLayersMuted(true),
                    onUnmuteAllSe: () => _session.setAllSeLayersMuted(false),
                    onBypassAllFx: () => _session.setAllLayersFxBypassed(true),
                    onEnableAllFx: () => _session.setAllLayersFxBypassed(false),
                    // R5 #9: the chips are LIVE here now — same filter
                    // object as the timeline's, so setting one on either
                    // surface sets it on both.
                    onToggleMarkFilter: (mark) =>
                        widget.onSetRowFilter?.call(
                          widget.rowFilter.toggledMark(mark),
                        ),
                    onToggleKindFilter: (kind) =>
                        widget.onSetRowFilter?.call(
                          widget.rowFilter.toggledKind(kind),
                        ),
                    onToggleSheetOnlyFilter: () =>
                        widget.onSetRowFilter?.call(
                          widget.rowFilter.copyWith(
                            onTimesheetOnly: !widget.rowFilter.onTimesheetOnly,
                          ),
                        ),
                    onToggleFxOnlyFilter: () => widget.onSetRowFilter?.call(
                      widget.rowFilter.copyWith(
                        fxOnly: !widget.rowFilter.fxOnly,
                      ),
                    ),
                    onToggleFillReferenceOnlyFilter: () =>
                        widget.onSetRowFilter?.call(
                          widget.rowFilter.copyWith(
                            fillReferenceOnly:
                                !widget.rowFilter.fillReferenceOnly,
                          ),
                        ),
                    onPreviewLayersOpacity: _session.previewLayersOpacity,
                    onCommitLayersOpacity: _session.commitLayersOpacity,
                  ),
                  // Master-bar drags (UI-R6 #2): S-row sliders follow the
                  // preview channel live; the bar rests on the last committed
                  // value instead of an average.
                  opacityDragPreview: _session.opacityDragPreview,
                  legendOpacityValue: _session.lastMasterOpacity,
                  // The V row's picture eye (R9): session view state the
                  // playback display reads.
                  cutPictureVisibleOf: _session.isCutPictureVisible,
                  onToggleCutPictureVisibility:
                      _session.toggleCutPictureVisibility,
                  // R9 #21: the TRACK's own fx master and static opacity —
                  // persisted model state, unlike the cut toggles above.
                  trackFxStateOf: (track) => _session.trackFxState(track.id),
                  onToggleTrackFx: (track) => _session.toggleTrackFx(track.id),
                  // The V row's chain: one effect's own bypass, from its lane
                  // group header.
                  onToggleTrackEffectEnabled: (track, effectId) =>
                      _session.toggleTrackEffectEnabled(track.id, effectId),
                  // R5: AE's group Reset on the V row's chain.
                  onResetTrackEffectGroup: (track, headerLaneId) =>
                      _session.resetTrackEffectGroup(track.id, headerLaneId),
                  trackOpacityOf: (track) =>
                      _session.trackStaticOpacity(track.id),
                  onTrackOpacityChanged: (track, opacity) =>
                      _session.previewTrackOpacity(track.id, opacity),
                  onTrackOpacityChangeEnd: (track, opacity) =>
                      _session.commitTrackOpacity(track.id, opacity),
                  // S-row range selection: the SAME track-axis selection the
                  // cut row paints, one row up. The timeline mounts its range
                  // gesture on every layer row (UI-R20 #2) and these rows had
                  // none, which is the last place the two panels' cells still
                  // behaved differently.
                  seSelect: StoryboardSeSelectCallbacks(
                    selectedRange: _session.trackFrameRangeSelection,
                    onDrag: _session.updateTrackSeRangeSelectionByFrame,
                    onClear: _session.clearStoryboardCutSelection,
                    // Sliding the selection: the timeline's own range-move
                    // machine, entered on the track axis (its sources commit
                    // to the global layer either way).
                    move: StoryboardRangeMoveCallbacks(
                      onBegin: (layerId) =>
                          _session.beginTrackRangeMoveDrag(layerId),
                      onUpdate: (frameDelta, targetLayerId) =>
                          _session.updateFrameRangeMoveDrag(
                            frameDelta: frameDelta,
                            targetLayerId: targetLayerId,
                          ),
                      onEnd: _session.endFrameRangeMoveDrag,
                      onCancel: _session.cancelFrameRangeMoveDrag,
                    ),
                  ),
                  // The ACTIVE cut's SE blocks reuse the timeline's comma
                  // edge grips (live preview + ONE undo per drag).
                  // The strip passes GLOBAL block starts (UI-R7 #5: every
                  // cut's blocks drag here, not just the active cut's).
                  seCommaDrag: TimelineCommaDragCallbacks(
                    onBegin: (layerId, blockStartIndex, edge) =>
                        _session.beginExposureEdgeDrag(
                          layerId: layerId,
                          blockStartIndex: blockStartIndex,
                          edge: edge,
                          blockStartIsGlobal: true,
                        ),
                    onUpdate: _session.updateExposureEdgeDrag,
                    onEnd: _session.endExposureEdgeDrag,
                    onCancel: _session.cancelExposureEdgeDrag,
                  ),
                  // The Audio lane's slide edit (active cut).
                  onSetAudioClipOffset: _session.setAudioClipOffset,
                  // The TRANSITION row. This panel is its only editor: the
                  // row is track-owned and its spans address the global
                  // axis, so the cut timeline shows them read-only.
                  transitionDefById: _session.cameraInstructionSet.defById,
                  transitionPreview: _session.transitionEdgeDragPreview,
                  transitionCommaDrag: TimelineCommaDragCallbacks(
                    onBegin: (layerId, blockStartIndex, edge) =>
                        _session.beginTransitionEdgeDrag(
                          layerId: layerId,
                          spanStartIndex: blockStartIndex,
                          edge: edge,
                        ),
                    onUpdate: _session.updateTransitionEdgeDrag,
                    onEnd: _session.endTransitionEdgeDrag,
                    onCancel: _session.cancelTransitionEdgeDrag,
                  ),
                  resolveCanCreateTransition: () =>
                      _session.canCreateTransitionSpanAtPlayhead,
                  onCreateTransition: _session.createTransitionSpanAtPlayhead,
                  onEditTransitionSpan: _editTransitionSpan,
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

/// The V rows' height stepper — one pair for every V track.
///
/// Steppers rather than a slider: the panel is worked on an iPad, where a
/// thin slider handle is the worst target on the bar, and the push/pull
/// pair beside it already reads as "two buttons, one dimension".
class _TrackLaneHeightButtons extends StatelessWidget {
  const _TrackLaneHeightButtons({
    required this.height,
    required this.onChanged,
  });

  final double height;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    void step(double delta) => onChanged!(
      (height + delta).clamp(
        StoryboardPanel.minTrackLaneHeight,
        StoryboardPanel.maxTrackLaneHeight,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey<String>('storyboard-row-shorter-button'),
          tooltip: AppText.strings.sbShorterRows,
          onPressed:
              onChanged == null || height <= StoryboardPanel.minTrackLaneHeight
              ? null
              : () => step(-StoryboardPanel.trackLaneHeightStep),
          icon: const Icon(Icons.unfold_less, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          key: const ValueKey<String>('storyboard-row-taller-button'),
          tooltip: AppText.strings.sbTallerRows,
          onPressed:
              onChanged == null || height >= StoryboardPanel.maxTrackLaneHeight
              ? null
              : () => step(StoryboardPanel.trackLaneHeightStep),
          icon: const Icon(Icons.unfold_more, size: 18),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

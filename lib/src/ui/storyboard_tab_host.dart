import 'dart:async';

import 'package:flutter/material.dart';

import 'theme/app_scroll_behavior.dart';

import '../models/canvas_point.dart';
import '../models/cut_id.dart';
import '../models/layer_id.dart';
import '../models/timeline_row_address.dart';
import '../models/track.dart';
import '../models/track_transform_lane_carrier.dart';
import '../models/transform_track.dart';
import 'camera/camera_view_toggle_button.dart';
import 'cut_command_group.dart';
import 'editor_session_manager.dart';
import 'playback/canvas_playback_controller.dart';
import 'playback/playback_transport_controls.dart';
import 'storyboard_cut_fade_policy.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnailResolver;
import 'storyboard_panel.dart';
import 'timeline/layer_rail_window.dart' show LayerRailExtent;
import '../models/layer_effect.dart' show LayerEffect;
import 'timeline/effect_lane_editing.dart'
    show
        effectsWithLaneKeyMoved,
        effectsWithLaneKeyToggled,
        effectsWithLaneValueEdited;
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
    this.cameraViewEnabled,
  });

  /// The ONE command-bar row's height, padding included.
  ///
  /// MEASURED, not chosen: the row sizes itself from the tallest control in
  /// it, and it is NOT the timeline's number even though it mounts the same
  /// [TimelineViewCluster] — the timeline's bar also carries a plain
  /// Material `IconButton` (the orientation toggle) that opts out of the
  /// app theme's compact icon sizing, and this bar has no equivalent.
  ///
  /// ⚠️ Measure it under the SHIPPED theme ([buildAppTheme]). The first
  /// round of this change measured 48 against a bare `MaterialApp`, where
  /// Material's 48px `minimumSize` applies instead of the app theme's
  /// compact 32 — 12px the user never spends.
  /// `panel_shrink_floor_test.dart` pins this against the real host.
  static const double commandBarHeight = 36;

  /// The shortest this tab is laid out at — the dock splitter's floor and
  /// the tab shell's minimum content height. See
  /// [StoryboardPanel.minPanelHeight] for the two-row rule.
  static const double minPanelHeight =
      commandBarHeight + StoryboardPanel.minPanelHeight;

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

  /// R28 #1: the workspace's camera-view state. The storyboard's command
  /// bar carries the same toggle the timeline's does — one notifier, so
  /// the two entrances can never disagree. Null = no button.
  final ValueNotifier<bool>? cameraViewEnabled;

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

  /// "To start" (REC1-B): the first cut's first frame — where an
  /// all-cuts roll begins.
  void _seekPlayheadToTrackStart() {
    final layout = _activeTrackLayout();
    if (layout.isEmpty) {
      return;
    }
    final firstCutId = layout.first.cutId;
    if (_session.activeCutOrNull?.id != firstCutId) {
      _session.selectCut(firstCutId);
    }
    _session.selectFrameIndex(0);
  }

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

  /// Lane edit hooks for the V TRACK's own Transform lanes (R4b): the
  /// timeline's per-lane track edits applied straight to
  /// [Track.transformTrack] at GLOBAL frames — the continuous rows and
  /// the rail both speak the track's axis now, so there is no window
  /// translation and no cut in the loop ("keys exist with no cut under
  /// them"). Committed as ONE undo through the session — the same command
  /// the fade handles use, so fades and pose keys share history cleanly.
  PropertyLaneEditCallbacks _trackLaneEditFor(Track track) {
    final transform = track.transformTrack;
    void commit(TransformTrack? next, String description) {
      if (next == null) {
        return;
      }
      _session.updateTrackTransformTrack(
        track.id,
        next,
        description: description,
      );
    }

    // The V row's fx lanes ride the SAME bundle, dispatched by lane id — the
    // layer path's arrangement (one callback set, two chains behind it), so
    // a track effect keys exactly like a layer effect does.
    void commitEffects(List<LayerEffect>? next, String description) {
      if (next == null) {
        return;
      }
      _session.updateTrackEffects(track.id, next, description: description);
    }

    // The pose lives in DISPLAY space (the camera's output frame — what
    // playback and the MP4 bake apply it over), so resolved values freeze
    // against that space's identity.
    final displaySize = _session.cameraFrameSize;
    return PropertyLaneEditCallbacks(
      onToggleKeyAt: (_, lane, frameIndex) {
        final description = '${lane.label} keyframe at frame ${frameIndex + 1}';
        if (laneIsEffectLane(lane)) {
          commitEffects(
            effectsWithLaneKeyToggled(
              track.effects,
              laneId: lane.laneId,
              frameIndex: frameIndex,
            ),
            description,
          );
          return;
        }
        commit(
          transformTrackWithLaneKeyToggled(
            transform,
            laneId: lane.laneId,
            frameIndex: frameIndex,
            resolvedPose: trackPoseAt(transform, frameIndex, displaySize),
            resolvedAnchorPoint:
                trackAnchorPointAt(transform, frameIndex) ??
                CanvasPoint(x: displaySize.width / 2, y: displaySize.height / 2),
            resolvedOpacity: trackFadeOpacityAt(transform, frameIndex),
          ),
          description,
        );
      },
      onMoveKey: (_, lane, fromFrame, toFrame) {
        final description =
            'Move ${lane.label} keyframe to frame ${toFrame + 1}';
        if (laneIsEffectLane(lane)) {
          commitEffects(
            effectsWithLaneKeyMoved(
              track.effects,
              laneId: lane.laneId,
              fromFrame: fromFrame,
              toFrame: toFrame,
            ),
            description,
          );
          return;
        }
        commit(
          transformTrackWithLaneKeyMoved(
            transform,
            laneId: lane.laneId,
            fromFrame: fromFrame,
            toFrame: toFrame,
          ),
          description,
        );
      },
      onSetValue: (_, lane, frameIndex, input) {
        final description = 'Set ${lane.label} at frame ${frameIndex + 1}';
        if (laneIsEffectLane(lane)) {
          commitEffects(
            effectsWithLaneValueEdited(
              track.effects,
              laneId: lane.laneId,
              frameIndex: frameIndex,
              input: input,
            ),
            description,
          );
          return;
        }
        commit(
          transformTrackWithLaneValueEdited(
            transform,
            laneId: lane.laneId,
            frameIndex: frameIndex,
            input: input,
          ),
          description,
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
    onMoveKey: (layer, lane, fromFrame, toFrame) => _commitLayerLaneEdit(
      layer.id,
      transformTrackWithLaneKeyMoved(
        layer.transformTrack,
        laneId: lane.laneId,
        fromFrame: fromFrame,
        toFrame: toFrame,
      ),
      'Move ${lane.label} keyframe to frame ${toFrame + 1}',
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

  /// ONE command-bar row (timeline parity): transport + cut group left,
  /// the shared view cluster pinned right.
  Widget _commandBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: UnbarredScrollable(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlaybackTransportControls(
                    controller: _session.playback,
                    scope: PlaybackScope.allCuts,
                    quality: _session.playbackQuality,
                    onQualityChanged: _session.setPlaybackQuality,
                    resolveMeterPeaks: () =>
                        _session.audioDeviceTransport.meterPeaks,
                    isVoiceRecording: _session.isVoiceRecording,
                    onToggleVoiceRecording: () =>
                        toggleVoiceRecordingWithFeedback(context, _session),
                    voiceRecordClipLit: _session.voiceRecordClipLit,
                    resolveStrings: () => _session.uiStrings,
                    // Play from the storyboard playhead, like the
                    // timeline's transport does.
                    playbackStartFrame: () =>
                        storyboardPlayheadFrame(_session) ?? 0,
                    onSkipToStart: _seekPlayheadToTrackStart,
                  ),
                  // R28 #1: camera view is a VIEW MODE, so every panel
                  // with a transport carries the toggle beside it.
                  CameraViewToggleButton(
                    enabled: widget.cameraViewEnabled,
                    keyValue: 'storyboard-camera-view-button',
                  ),
                  const SizedBox(width: 8),
                  CutCommandGroup(session: _session),
                  const SizedBox(width: 4),
                  // The V row's fx (user 2026-08-08): a chain over the whole
                  // composited cut, authored from this panel.
                  TrackFxCommandGroup(session: _session),
                  const SizedBox(width: 4),
                  // THE push/pull pair, the timeline rail's own widget: the
                  // rail asks as ITSELF, so with nothing selected the shove
                  // aims at the row this rail is on (a cut row shoves cuts,
                  // an S row shoves sounds).
                  TimelineShiftButtons(
                    session: _session,
                    currentRow: _session.selectedRow,
                  ),
                  const SizedBox(width: 4),
                  // V ROW HEIGHT — one pair for every V track, because
                  // there is one height (user's rule). A pair of steppers
                  // rather than a slider: this panel is worked on an iPad,
                  // and the push/pull pair beside it already reads this
                  // way.
                  _TrackLaneHeightButtons(
                    height: widget.trackLaneHeight,
                    onChanged: widget.onTrackLaneHeightChanged,
                  ),
                ],
              ),
            ),
            ),
          ),
          const SizedBox(width: 8),
          TimelineViewCluster(
            frameCursor: _session.editingFrameCursor,
            // Global · cut-local pair (UI-R9 #6) — the channel already
            // follows scrubs, gap parking and playback ticks.
            globalFrame: _playheadGlobalFrame,
            projectFrameRate: _session.projectFrameRate,
            showSeconds: widget.showSeconds,
            pixelsPerFrame: widget.pixelsPerFrame,
            onPixelsPerFrameChanged: widget.onPixelsPerFrameChanged,
          ),
        ],
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
              child: ListenableBuilder(
                listenable: _session.voiceRecordPreviewLane,
                builder: (context, _) => StoryboardPanel(
                  project: _session.repository.requireProject(),
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
                          headLaneId: _laneSpanHeadLane(
                            layerId,
                            laneId,
                            headRowDelta,
                          ),
                        ),
                    // R10: a lane band is a place you can STAND. The
                    // storyboard's strips run on the GLOBAL axis, so the
                    // frame the tap reports is a global one.
                    onTapAt: (layerId, laneId, globalFrame) {
                      _session.clearLaneRangeSelection();
                      _session.selectGlobalFrame(globalFrame);
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
                    onEffectUpdate: _session.updateEffectRowDrag,
                    onEnd: _session.endLayerRowDrag,
                    onCancel: _session.cancelLayerRowDrag,
                  ),
                  layerLaneEdit: _layerLaneEdit,
                  activeCutFrameCursor: _activeCutFrameCursor,
                  onSelectFrameIndex: _session.selectFrameIndex,
                  poseDisplaySize: _session.cameraFrameSize,
                  onSetCutFade: (cutId, fadeIn, fadeOut) => _session.setCutFade(
                    cutId,
                    fadeInFrames: fadeIn,
                    fadeOutFrames: fadeOut,
                  ),
                  // FO=black / WO=white — the fade span's context menu.
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
                    // Row solos stand down here (showRowSolos: false).
                    onToggleMarkFilter: (_) {},
                    onToggleKindFilter: (_) {},
                    onToggleSheetOnlyFilter: () {},
                    onToggleFxOnlyFilter: () {},
                    onToggleFillReferenceOnlyFilter: () {},
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

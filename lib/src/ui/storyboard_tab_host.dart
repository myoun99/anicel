import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/canvas_point.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer_id.dart';
import '../models/timeline_row_address.dart';
import '../models/transform_track.dart';
import 'camera/camera_view_toggle_button.dart';
import 'cut_command_group.dart';
import 'editor_session_manager.dart';
import 'playback/canvas_playback_controller.dart';
import 'playback/playback_transport_controls.dart';
import 'storyboard_cut_fade_policy.dart';
import 'storyboard_panel.dart';
import 'timeline/property_lane_model.dart' show PropertyLaneEditCallbacks;
import 'timeline/timeline_layer_controls_header.dart' show LayerLegendCallbacks;
import 'timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'storyboard_playhead_mapping.dart';
import 'storyboard_timeline_layout.dart';
import 'timeline/timeline_view_cluster.dart';
import 'timeline/transform_lane_editing.dart';

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
    required this.thumbnailFor,
    this.cameraViewEnabled,
  });

  final EditorSessionManager session;
  final double pixelsPerFrame;
  final ValueChanged<double> onPixelsPerFrameChanged;
  final bool showSeconds;
  final ValueChanged<bool> onShowSecondsChanged;

  /// Build-time thumbnail resolver, owned above the tabs so the cache
  /// survives tab switches.
  final ui.Image? Function(Cut cut)? thumbnailFor;

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
    super.dispose();
  }

  void _toggleSetEntry(Set<String> set, String key) {
    setState(() {
      if (!set.add(key)) {
        set.remove(key);
      }
    });
  }

  /// Lane edit hooks for one CUT's Transform lanes (the V track): the
  /// timeline's per-lane track edits applied to the cut-level transform,
  /// committed as ONE undo through the session — the same command the
  /// fade handles use, so fades and pose keys share history cleanly.
  /// The carrier Layer the substrate hands back is synthetic; the cut is
  /// captured here.
  PropertyLaneEditCallbacks _cutLaneEditFor(Cut cut) {
    void commit(TransformTrack? next, String description) {
      if (next == null) {
        return;
      }
      _session.updateCutTransformTrack(cut.id, next, description: description);
    }

    // The cut pose lives in DISPLAY space (the camera's output frame —
    // what playback and the MP4 bake apply it over), so resolved values
    // freeze against that space's identity.
    final displaySize = _session.cameraFrameSize;
    return PropertyLaneEditCallbacks(
      onToggleKeyAt: (_, lane, frameIndex) => commit(
        transformTrackWithLaneKeyToggled(
          cut.transformTrack,
          laneId: lane.laneId,
          frameIndex: frameIndex,
          resolvedPose: cutPoseAt(cut, frameIndex, displaySize),
          resolvedAnchorPoint:
              cutAnchorPointAt(cut, frameIndex) ??
              CanvasPoint(x: displaySize.width / 2, y: displaySize.height / 2),
          resolvedOpacity: cut.fadeOpacityAt(frameIndex),
        ),
        '${lane.label} keyframe at frame ${frameIndex + 1}',
      ),
      onMoveKey: (_, lane, fromFrame, toFrame) => commit(
        transformTrackWithLaneKeyMoved(
          cut.transformTrack,
          laneId: lane.laneId,
          fromFrame: fromFrame,
          toFrame: toFrame,
        ),
        'Move ${lane.label} keyframe to frame ${toFrame + 1}',
      ),
      onRemoveKey: (_, lane, frameIndex) => commit(
        transformTrackWithLaneKeyRemoved(
          cut.transformTrack,
          laneId: lane.laneId,
          frameIndex: frameIndex,
        ),
        'Delete ${lane.label} keyframe',
      ),
      onToggleHold: (_, lane, frameIndex) => commit(
        transformTrackWithLaneHoldToggled(
          cut.transformTrack,
          laneId: lane.laneId,
          frameIndex: frameIndex,
        ),
        'Toggle hold on ${lane.label} keyframe',
      ),
      onSetValue: (_, lane, frameIndex, input) => commit(
        transformTrackWithLaneValueEdited(
          cut.transformTrack,
          laneId: lane.laneId,
          frameIndex: frameIndex,
          input: input,
        ),
        'Set ${lane.label} at frame ${frameIndex + 1}',
      ),
    );
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
    onRemoveKey: (layer, lane, frameIndex) => _commitLayerLaneEdit(
      layer.id,
      transformTrackWithLaneKeyRemoved(
        layer.transformTrack,
        laneId: lane.laneId,
        frameIndex: frameIndex,
      ),
      'Delete ${lane.label} keyframe',
    ),
    onToggleHold: (layer, lane, frameIndex) => _commitLayerLaneEdit(
      layer.id,
      transformTrackWithLaneHoldToggled(
        layer.transformTrack,
        laneId: lane.laneId,
        frameIndex: frameIndex,
      ),
      'Toggle hold on ${lane.label} keyframe',
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
                ],
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
            onShowSecondsChanged: widget.onShowSecondsChanged,
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
    return Material(
      color: colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    ? _session.playback.position?.cutId ?? _session.activeCutId
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
                    case TrackRowAddress(:final trackId):
                      _session.selectTrackRow(trackId);
                  }
                  seekStoryboardGlobalFrame(_session, globalFrame);
                },
                activeLayerId: _session.activeLayerId,
                // The rail speaks ROW ADDRESSES, and its selection is its
                // OWN: picking a row here never moves the drawing target
                // (the CUT's row, which the timeline rail highlights and
                // each cut remembers). A V row still promotes that track's
                // playhead-index cut (UI-R18 #6) — that is the track
                // selection landing, not a row selection following.
                selectedRow: _session.selectedRow,
                onSelectLayer: (layerId) =>
                    _session.selectRow(LayerRowAddress(layerId)),
                onSelectTrack: (trackId) =>
                    _session.selectRow(TrackRowAddress(trackId)),
                pixelsPerFrame: widget.pixelsPerFrame,
                showSeconds: widget.showSeconds,
                projectFrameRate: _session.projectFrameRate,
                // Edge-grip trims preview live and commit ONE undo on
                // release, like the timeline's comma drags.
                cutTrim: StoryboardCutTrimCallbacks(
                  onBegin: (cutId, edge) =>
                      _session.beginCutEdgeDrag(cutId: cutId, edge: edge),
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
                // The V track's cut-level Transform lanes (AE precomp:
                // the whole cut moving on the screen) and the S rows'
                // layer Transform lanes.
                cutLaneEditFor: _cutLaneEditFor,
                layerLaneEdit: _layerLaneEdit,
                activeCutFrameIndex: _session.currentFrameIndex,
                onSelectFrameIndex: _session.selectFrameIndex,
                poseDisplaySize: _session.cameraFrameSize,
                onSetCutFade: (cutId, fadeIn, fadeOut) => _session.setCutFade(
                  cutId,
                  fadeInFrames: fadeIn,
                  fadeOutFrames: fadeOut,
                ),
                // FO=black / WO=white — the fade span's context menu.
                onSetCutFadeTarget: _session.setCutFadeTarget,
                // Timeline-parity layer controls on the ACTIVE cut's SE
                // rows — the SAME session hooks the timeline host wires.
                onToggleLayerVisibility: _session.toggleLayerVisibility,
                onToggleLayerMuted: _session.toggleLayerMuted,
                onLayerOpacityChanged: _session.previewLayerOpacity,
                onLayerOpacityChangeEnd: _session.commitLayerOpacity,
                onLayerMarkSelected: _session.setLayerMark,
                layerFxEnabledOf: _session.isLayerFxEnabled,
                onToggleLayerFx: _session.toggleLayerFx,
                // The timeline's rail legend on this panel too (UI-R5): the
                // same session-backed bulk flyouts + master opacity bar; the
                // row solos stand down (the storyboard rail is track-global,
                // no row filter here).
                visibilitySoloEnabled: _session.layerVisibilitySoloEnabled,
                legend: LayerLegendCallbacks(
                  onShowAllLayers: () => _session.setAllLayersVisibility(true),
                  onHideAllLayers: () => _session.setAllLayersVisibility(false),
                  onToggleVisibilitySolo: _session.toggleLayerVisibilitySolo,
                  onSheetAllOn: () => _session.setAllLayersOnTimesheet(true),
                  onSheetAllOff: () => _session.setAllLayersOnTimesheet(false),
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
                // V-row display toggles (R9): cut FX bypass + picture
                // eye — session view state the playback display reads.
                cutFxEnabledOf: _session.isCutFxEnabled,
                onToggleCutFx: _session.toggleCutFx,
                cutPictureVisibleOf: _session.isCutPictureVisible,
                onToggleCutPictureVisibility:
                    _session.toggleCutPictureVisibility,
                // S-row range selection: the SAME track-axis selection the
                // cut row paints, one row up. The timeline mounts its range
                // gesture on every layer row (UI-R20 #2) and these rows had
                // none, which is the last place the two panels' cells still
                // behaved differently.
                seSelect: StoryboardSeSelectCallbacks(
                  selectedRange: _session.trackFrameRangeSelection,
                  onDrag: _session.updateTrackSeRangeSelectionByFrame,
                  onClear: _session.clearStoryboardCutSelection,
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
    );
  }
}

// The machinery a run of the film needs: the transport state machine, the
// three audio paths that may carry it, the warmer that fills the cache in
// front of it and the budget that trims what it leaves behind.
//
// Its own object since round 8 (G1, 2026-09-06). ⛔What is NOT here is the
// session's REACTION to a run — where the playhead lands, which cut goes
// active, what a take does when the transport stops. Those touch the
// selection, the standing row and the voice recorder, so they stay with
// the session and arrive here as the three callbacks the transport was
// always shaped to take. Keeping them out is also what keeps this
// acyclic: `Standing` and `RangeSelections` reach IN here for the warmer,
// and if the rig reached back out for `selectCut` neither could be built.

import 'dart:io';

import '../../models/playback_quality.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../native/qa_audio_device.dart' show audioOutputUnlessTesting;
import '../audio/audio_conform_store.dart';
import '../playback/audio_device_transport.dart';
import '../playback/audio_playback_sync.dart';
import '../playback/audio_scrubber.dart';
import '../playback/audioplayers_clip_player.dart';
import '../../services/playback/playback_frame_mapping.dart';
import '../playback/canvas_playback_controller.dart';
import '../playback/playback_cache_budget.dart';
import '../playback/playback_prerender_scheduler.dart';
import '../playback/playback_transport.dart';
import 'editor_voice_recording.dart';
import 'movie_cel_hydrator.dart';
import 'playback_cache_budget.dart';
import 'project_settings.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// Playback's own machinery: the transport, its audio paths, the
/// prerender warmer and the cache budget that follows them.
class PlaybackRig implements PlaybackRun {
  PlaybackRig({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required ProjectSettings settings,
    required EditorVoiceRecording voiceRecording,
    required AudioConformStore audioConformStore,
    required MovieCelHydrator movieCels,
    required void Function(PlaybackPosition lastPosition) onStopped,
    required void Function(int globalFrame) onStoppedInGap,
    required void Function(
      List<StoryboardTimelineLayoutEntry> playlist,
      PlaybackScope scope,
      int startGlobalFrame,
    )
    onPlaylistWarmRequested,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _renderCaches = renderCaches,
       _settings = settings,
       _voiceRecording = voiceRecording,
       _audioConformStore = audioConformStore,
       _movieCels = movieCels,
       _onStopped = onStopped,
       _onStoppedInGap = onStoppedInGap,
       _onPlaylistWarmRequested = onPlaylistWarmRequested;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;
  final ProjectSettings _settings;
  final EditorVoiceRecording _voiceRecording;
  final AudioConformStore _audioConformStore;
  final MovieCelHydrator _movieCels;
  final void Function(PlaybackPosition lastPosition) _onStopped;
  final void Function(int globalFrame) _onStoppedInGap;
  final void Function(
    List<StoryboardTimelineLayoutEntry> playlist,
    PlaybackScope scope,
    int startGlobalFrame,
  )
  _onPlaylistWarmRequested;

  // ── the playback cache budget: its own object ───────────────────────
  //
  // A collaborator (session/playback_cache_budget.dart). It reads the
  // transport and the quality off this rig, which is why the rig builds
  // it rather than being handed one.
  late final PlaybackCacheBudget playbackCache = PlaybackCacheBudget(
    project: _project,
    renderCaches: _renderCaches,
    run: this,
  );

  late final PlaybackPrerenderScheduler prerenderScheduler =
      PlaybackPrerenderScheduler(
        composites: _renderCaches.cutFrameCompositeCache,
        resolveCut: _project.cutById,
        // Widget tests: zero idle delay, like before R13-3 — the
        // quiet-window polls otherwise leave a pending gate timer at
        // teardown (the session's tearDown dispose runs AFTER the
        // binding's timer invariant). The debounce/hold semantics have
        // their own scheduler unit tests with injected delays.
        //
        // Production: 1200ms (R13-4) — during an active work session the
        // warmer resumes only in REAL pauses; per-tile abort granularity
        // covers whatever still collides at the resume boundary.
        //
        // ⚠️MUTANT SURVIVES, wrong axis (2026-09-08): swapping the two
        // branches leaves every suite green. What the DELAY does is pinned
        // by the scheduler's own unit tests, which inject a duration; this
        // line only picks which one, and no suite that names the rig arms
        // the quiet-window poll. A test that noticed would have to assert
        // on a timer, which is the shape those unit tests already are.
        idleDelay: Platform.environment['FLUTTER_TEST'] == 'true'
            ? Duration.zero
            : const Duration(milliseconds: 1200),
        afterFrameCached: playbackCache.enforcePlaybackCacheBudget,
        // A movie kept as a reference decodes before its frame composes.
        beforeCompose: _movieCels.hydrate,
      );

  /// Playback preview quality (Premiere/AE monitor resolution analogue).
  @override
  PlaybackQuality playbackQuality = defaultPlaybackQuality;

  void setPlaybackQuality(PlaybackQuality quality) {
    if (playbackQuality == quality) {
      return;
    }
    playbackQuality = quality;
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// Canvas playback state machine; only the playback view and transport
  /// controls listen (the session playhead syncs once on stop).
  @override
  late final CanvasPlaybackController playback = CanvasPlaybackController(
    resolveProject: _project.repository.requireProject,
    resolveActiveCutId: () => _timeline.editingSession.activeCutId,
    resolveActiveTrackId: () => _selection.selectedTrackId,
    resolveFrameRate: () => _settings.projectFrameRate,
    onStopped: _onStopped,
    onStoppedInGap: _onStoppedInGap,
    onPlaylistWarmRequested: _onPlaylistWarmRequested,
  );

  /// Everything in the app that plays, so the actuation gate can ask ONE
  /// object 「누가 재생 중인가」 and stop it.
  ///
  /// 🚨★★★Here rather than on the session because this is playback's own
  /// machinery, and because the gate and the media viewers both reach it
  /// through `session.playbackRig` — the same door the canvas already uses.
  /// ⛔Do not give a surface its own copy: a second registry is a second
  /// answer to the same question, and exclusive playback (유저 09-07) is
  /// only ONE law while there is only one list.
  late final PlaybackTransports transports = PlaybackTransports()
    ..add(playback);

  /// The native device transport (audio program wiring): when it carries a
  /// run, playback rides the audio master clock — the picture follows the
  /// samples handed to the device, and cumulative drift is structurally
  /// zero. Stands down per run (no binary/device, PCM not resident) onto
  /// [audioPlaybackSync].
  late final AudioDeviceTransport audioDeviceTransport = AudioDeviceTransport(
    controller: playback,
    resolveFrameRate: () => _settings.projectFrameRate,
    resolveProject: () => _project.repository.currentProject,
    conformStore: _audioConformStore,
    // Widget tests must never open a real OS audio device.
    resolveDevice: audioOutputUnlessTesting,
    resolveUserOffsetSamples: (sampleRate) =>
        _internals.appSettings.audioSyncSettings.value.offsetSamples(
          sampleRate: sampleRate,
          frameRateNumerator: _settings.projectFrameRate.numerator,
          frameRateDenominator: _settings.projectFrameRate.denominator,
        ),
    resolveSoloedLayerIds: () => _internals.soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => _voiceRecording.recordingMutedLayerIds,
    resolveCueClips: () => _voiceRecording.voiceRecordCueClips,
    resolveOutputDeviceName: () =>
        _internals.appSettings.audioSyncSettings.value.outputDeviceName,
  );

  /// The output/input device lists for the Preferences pickers (AUDIO-PRO
  /// R4); empty without a native binary (widget tests, engine-less runs).
  List<({String name, bool isDefault})> audioDevicesOf({
    required bool capture,
  }) =>
      audioOutputUnlessTesting()?.devicesOf(capture: capture) ?? const [];

  /// Scrubbing the playhead plays each crossed frame's slice of the mix
  /// (2D): one `play(frame, frame+1)` per crossed frame on the same
  /// transport playback uses. Stands down silently without a device or
  /// resident PCM — the scrub stays visual-only, as before.
  late final AudioScrubber audioScrubber = AudioScrubber(
    controller: playback,
    resolveFrameRate: () => _settings.projectFrameRate,
    resolveProject: () => _project.repository.currentProject,
    conformStore: _audioConformStore,
    // Widget tests must never open a real OS audio device.
    resolveDevice: audioOutputUnlessTesting,
    resolveSoloedLayerIds: () => _internals.soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => _voiceRecording.recordingMutedLayerIds,
    resolveOutputDeviceName: () =>
        _internals.appSettings.audioSyncSettings.value.outputDeviceName,
  );

  /// Frame-synced SE audio riding [playback]'s frame signals; clip lengths
  /// come from the conform store (exact sample counts, with the ffmpeg
  /// peaks approximation as its own fallback). Fallback path — stands down
  /// for runs the device transport carries.
  late final AudioPlaybackSync audioPlaybackSync = AudioPlaybackSync(
    controller: playback,
    resolveFrameRate: () => _settings.projectFrameRate,
    durationSecondsFor: _audioConformStore.durationSecondsFor,
    playerFactory: AudioplayersClipPlayer.new,
    // Track-owned SE rows schedule from the tracks' global axes.
    resolveProject: () => _project.repository.currentProject,
    deviceCarriesPlayback: () => audioDeviceTransport.carryingPlayback,
    resolveSoloedLayerIds: () => _internals.soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => _voiceRecording.recordingMutedLayerIds,
    resolveCueClips: () => _voiceRecording.voiceRecordCueClips,
  );

  /// Transport FIRST: listener order is its contract with the fallback —
  /// carryingPlayback must be decided before the sync consults it.
  void attach() {
    audioDeviceTransport.attach();
    audioPlaybackSync.attach();
  }

  /// ⚠️The ORDER is the same one the session's `dispose` used to spell:
  /// the two fallback listeners come off the transport before the
  /// transport and the controller they ride go down. [transports] joins
  /// the front of that rule for the same reason — it holds a listener on
  /// [CanvasPlaybackController.isActiveListenable], which [playback]
  /// disposes.
  void dispose() {
    transports.dispose();
    audioPlaybackSync.dispose();
    audioScrubber.dispose();
    audioDeviceTransport.dispose();
    playback.dispose();
    prerenderScheduler.dispose();
  }
}

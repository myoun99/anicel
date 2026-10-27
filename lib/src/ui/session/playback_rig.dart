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


import 'package:flutter/foundation.dart' show Listenable, ValueListenable;

import '../../services/flutter_test_run.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/playback_mode.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../native/qa_audio_device.dart'
    show QaAudioDevice, audioDeviceUnlessTesting;
import '../audio/audio_conform_store.dart';
import '../audio/sound_cannot_play.dart';
import '../playback/audio_device_transport.dart';
import '../playback/audio_scrubber.dart';
import '../../services/playback/frame_demand.dart';
import '../../services/playback/playback_frame_mapping.dart';
import '../../services/playback/playback_wait.dart';
import '../../models/composite_tree.dart';
import '../canvas/canvas_layer_stack_view.dart' show CanvasStackRow;
import '../playback/frame_pictures.dart';
import '../playback/canvas_playback_controller.dart';
import '../playback/playback_prerender_scheduler.dart';
import '../playback/playback_transport.dart';
import 'editor_voice_recording.dart';
import 'movie_cel_hydrator.dart';
import 'playback_cache_budget.dart';
import 'project_settings.dart';
import 'render_caches.dart';
import 'editor_app_settings.dart';
import 'session_roles.dart';

/// Playback's own machinery: the transport, its audio paths, the
/// prerender warmer and the cache budget that follows them.
class PlaybackRig implements PlaybackRun {
  PlaybackRig({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required EditorAppSettings appSettings,
    required ValueListenable<Set<LayerId>> soloedSeLayerIds,
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
    required List<CompositeNode<CanvasStackRow>> Function(Cut cut, int frameIndex)
    stackOf,
  }) : _stackOf = stackOf,
       _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _appSettings = appSettings,
       _soloedSeLayerIds = soloedSeLayerIds,
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
  final EditorAppSettings _appSettings;

  /// The SE rows soloed for monitoring (`VisibilitySolo` holds it) — every
  /// audio path narrows to them while any are.
  final ValueListenable<Set<LayerId>> _soloedSeLayerIds;
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

  /// The tree a cut's frame stacks on the screen while a run plays it — the
  /// session's editing canvas answers ([FramePictures.stackOf]).
  final List<CompositeNode<CanvasStackRow>> Function(Cut cut, int frameIndex)
  _stackOf;

  // ── what the screen shows a frame from ──────────────────────────────

  /// A frame as every screen shows it — the canvas a cut, the track stack
  /// the film: its one picture, made once ahead of the playhead.
  /// ↩️The screens stacked a frame from its rows' images, each at the level
  /// that frame was drawn at (`CanvasPictures`), and the film before that
  /// from a composite per frame beside them.
  late final FramePictures framePictures = FramePictures(
    store: _renderCaches.framePictureStore,
    layerImages: _renderCaches.layerFrameImageCache,
    stackOf: (picture) => _stackOf(picture.cut, picture.frameIndex),
    pageOf: (picture) => (
      canvasSize: picture.cut.canvasSize,
      pasteboardReach: _project.repository.requireProject().pasteboardReach,
      paintPaper: picture.paintPaper,
      paperBackground: _settings.projectBackground,
    ),
  );

  @override
  FramePictures get pictures => framePictures;

  /// Whether the canvas shows the run — a cut played alone, through the
  /// camera or not — and not the track stack, which shows the whole film.
  bool get playsOnTheCanvas =>
      !(playback.isActive && playback.scope == PlaybackScope.allCuts);

  // ── the playback cache budget: its own object ───────────────────────
  //
  // A collaborator (session/playback_cache_budget.dart). It reads the
  // transport off this rig, which is why the rig builds it rather than
  // being handed one.
  late final PlaybackCacheBudget playbackCache = PlaybackCacheBudget(
    project: _project,
    renderCaches: _renderCaches,
    run: this,
  );

  late final PlaybackPrerenderScheduler prerenderScheduler =
      PlaybackPrerenderScheduler(
        pictures: framePictures,
        resolveCut: _project.cutById,
        room: playbackCache,
        // Widget tests: zero idle delay, like before R13-3 — the
        // quiet-window polls otherwise leave a pending gate timer at
        // teardown (the session's tearDown dispose runs AFTER the
        // binding's timer invariant). The debounce/hold semantics have
        // their own scheduler unit tests with injected delays.
        //
        // Production: 1200ms (R13-4) — during an active work session the
        // warmer resumes only in REAL pauses; per-tile abort granularity
        // covers whatever still collides at the resume boundary. A run
        // that PLAYS does not wait it out ([FrameDemand.yieldsToEditing]).
        //
        // ⚠️MUTANT SURVIVES, wrong axis (2026-09-08): swapping the two
        // branches leaves every suite green. What the DELAY does is pinned
        // by the scheduler's own unit tests, which inject a duration; this
        // line only picks which one, and no suite that names the rig arms
        // the quiet-window poll. A test that noticed would have to assert
        // on a timer, which is the shape those unit tests already are.
        idleDelay: underFlutterTest
            ? Duration.zero
            : const Duration(milliseconds: 1200),
        // A movie kept as a reference decodes before its frame composes.
        beforeCompose: _movieCels.hydrate,
      );

  @override
  FrameDemand? get demand => prerenderScheduler.demand;

  /// What a run does at a frame whose picture is not made yet
  /// ([PlaybackMode]).
  ///
  /// A project setting kept beside the project and not in it, as the
  /// playback quality whose seat it took was (유저 답
  /// playback-quality-undo-Q1 「언두 안 됨 — 보기 설정처럼(저장은 됨)」):
  /// picking one is no edit.
  PlaybackMode get playbackMode => _playbackMode;
  PlaybackMode _playbackMode = defaultPlaybackMode;

  void setPlaybackMode(PlaybackMode mode) {
    if (_playbackMode == mode) {
      return;
    }
    _playbackMode = mode;
    // A run that waits under the old mode may not wait under the new one.
    playback.lookAgain();
    _changes.notifyChanged();
  }

  /// Whether a run's clock waits — for its picture, the mode read against
  /// what the warmer has made of the run it follows, or for its sound — and
  /// whether a run behind its clock shows every picture.
  late final PlaybackWait _wait = PlaybackWait(
    mode: () => playbackMode,
    pictureIsThere: pictureIsThere,
    aheadIsFilled: () => prerenderScheduler.isResting,
    soundIsComing: () => audioDeviceTransport.soundIsComing,
  );

  /// Whether the run's picture at [playlistFrame] is there to show — or can
  /// never be — or null while the warmer follows no run, and so nothing
  /// would ever say one had come. What the run's clock asks of a frame
  /// before it goes on ([_wait]), and what a frame is shown by
  /// ([frameIsThere]).
  bool? pictureIsThere(int playlistFrame) {
    final wanted = prerenderScheduler.demand;
    return wanted is PlayingDemand
        ? prerenderScheduler.has(wanted.picturesOf(playlistFrame))
        : null;
  }

  /// Whether the run's frame at [playlistFrame] goes up when asked for: its
  /// picture is there — or nothing makes the run's pictures, and what the
  /// cuts hold is all there will be. What the film changes frames by
  /// (`TrackStackRun.frameIsThere`) and what the run's clock counts a frame
  /// it leaves by ([CanvasPlaybackController.frameIsThere]) — one answer,
  /// so the count is of the frames the screen did not show.
  bool frameIsThere(int playlistFrame) => pictureIsThere(playlistFrame) ?? true;

  /// How many steps on the playing run shows [cutId]'s frame [frameIndex] —
  /// its own order ([FrameDemand.stepOf]), the one its pictures are made in
  /// and let go by — or null for a frame it does not show, and while the
  /// warmer follows no run that plays: what the timeline's substrate tiles
  /// are let go by (`TimelineGridTileStore`).
  int? stepsUntilShown(CutId cutId, int frameIndex) {
    final wanted = prerenderScheduler.demand;
    return wanted is PlayingDemand ? wanted.stepOf(cutId, frameIndex) : null;
  }

  /// The question the run's clock asks of every frame it would stand on
  /// ([CanvasPlaybackController.waitsOn]).
  bool _waitsOn(int playlistFrame, {required bool placed}) {
    if (placed) {
      // A run put somewhere has the warmer look at that place — awake or at
      // rest, it comes to rest again and says so, which is what a run that
      // fills before it goes waits to hear. The playhead moving wakes it
      // too, but a run dragged onto the frame it already stands on moves
      // nothing.
      prerenderScheduler.wake();
    }
    return _wait.holds(playlistFrame, placed: placed);
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
  )
    ..waitsOn = _waitsOn
    ..frameIsThere = frameIsThere
    ..showsEveryPicture = _wait.showsEveryPicture;

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

  /// The user's own A/V correction in samples at [sampleRate] — the residual
  /// no device report accounts for (screen pipeline, Bluetooth, an AV
  /// receiver), taken off by every clock that reads what the device has
  /// played (`HeardOnTheDevice`): the canvas's transport, and the media
  /// viewer's sound.
  int userOffsetSamples(int sampleRate) =>
      _appSettings.audioSyncSettings.value.offsetSamples(
        sampleRate: sampleRate,
        frameRateNumerator: _settings.projectFrameRate.numerator,
        frameRateDenominator: _settings.projectFrameRate.denominator,
      );

  /// The output [audioDeviceTransport] plays on: [audioDeviceUnlessTesting],
  /// or what a test hands in — a device IT opened on the null backend, so
  /// the bench can hear a run the session plays (the transport's own tests
  /// hand theirs in the same way). ⛔Never the hardware: the transport plays
  /// on an open device as it stands and opens only a closed one — ahead of
  /// a run or at it — or reopens one open for another output setting, which
  /// a test that hands one in leaves alone.
  QaAudioDevice? Function() debugTransportOutput = audioDeviceUnlessTesting;

  /// The native device transport (audio program wiring): when it carries a
  /// run, playback rides the audio master clock — the picture follows the
  /// samples handed to the device, and cumulative drift is structurally
  /// zero. A run whose sound is on its way waits for it ([_wait]); one with
  /// no output plays without sound.
  ///
  /// 🗣️유저 2026-10-16 (se-fallback-opens-the-original-path-Q2): 「대체
  /// 재생을 안 쓰고, 소리가 준비될 때까지 기다린다」. ↩️A run the device did
  /// not carry stood down onto the platform players (`AudioPlaybackSync`),
  /// on the wall clock — playback stopped calling them in
  /// playback-waits-for-its-sound, and the stack and its `audioplayers`
  /// went with se-fallback-opens-the-original-path (2026-10-23).
  late final AudioDeviceTransport audioDeviceTransport = AudioDeviceTransport(
    controller: playback,
    resolveFrameRate: () => _settings.projectFrameRate,
    resolveProject: () => _project.repository.currentProject,
    conformStore: _audioConformStore,
    // Widget tests must never open a real OS audio device.
    resolveDevice: () => debugTransportOutput(),
    resolveUserOffsetSamples: userOffsetSamples,
    resolveSoloedLayerIds: () => _soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => _voiceRecording.recordingMutedLayerIds,
    resolveCueClips: () => _voiceRecording.voiceRecordCueClips,
    resolveOutputDeviceName: () =>
        _appSettings.audioSyncSettings.value.outputDeviceName,
  );

  /// Why the sound at [filePath] cannot be played — the one verdict
  /// ([AudioConformStore.cannotPlayAt]) at the rate a run plays at
  /// ([AudioDeviceTransport.soundRate]): what a sound's cell shows, before
  /// any run as well as during one (playback-says-the-sound-it-cannot-play,
  /// 유저 2026-10-17: 「재생하지 않을 때도 늘」).
  SoundCannotPlay? soundCannotPlay(String filePath) => _audioConformStore
      .cannotPlayAt(filePath, audioDeviceTransport.soundRate);

  /// Fires when [soundCannotPlay]'s answers may have moved: a conform or a
  /// conversion landed, or a run armed the output at another rate.
  late final Listenable soundsMoved = Listenable.merge([
    _audioConformStore,
    audioDeviceTransport.armedRate,
  ]);

  /// The output/input device lists for the Preferences pickers (AUDIO-PRO
  /// R4); empty without a native binary (widget tests, engine-less runs).
  List<({String name, bool isDefault})> audioDevicesOf({
    required bool capture,
  }) =>
      audioDeviceUnlessTesting()?.devicesOf(capture: capture) ?? const [];

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
    resolveDevice: audioDeviceUnlessTesting,
    resolveSoloedLayerIds: () => _soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => _voiceRecording.recordingMutedLayerIds,
    resolveOutputDeviceName: () =>
        _appSettings.audioSyncSettings.value.outputDeviceName,
  );

  void attach() {
    audioDeviceTransport.attach();
    // The warmer rests once what is wanted is made, or no more fits; a
    // playhead that moves on is what it looks again for.
    playback.globalFrameIndexListenable.addListener(prerenderScheduler.wake);
    playback.isActiveListenable.addListener(_onRunToggled);
    // A run that waits looks again whenever the warmer says the answer
    // may have changed: a picture landed, one was given up on, or it has
    // come to rest — which is what a run that renders first waits for.
    prerenderScheduler.changes.addListener(playback.lookAgain);
  }

  /// A run that ends is followed no further. What is wanted next is the
  /// session's to say — its warm of the cut the playhead lands on — and
  /// until it does nothing is.
  void _onRunToggled() {
    if (!playback.isActive) {
      prerenderScheduler.cancel();
    }
  }

  /// ⚠️The ORDER is the same one the session's `dispose` used to spell:
  /// the scrubber comes off the transport before the transport and the
  /// controller they ride go down. [transports] joins the front of that
  /// rule for the same reason — it holds a listener on
  /// [CanvasPlaybackController.isActiveListenable], which [playback]
  /// disposes.
  void dispose() {
    prerenderScheduler.changes.removeListener(playback.lookAgain);
    playback.isActiveListenable.removeListener(_onRunToggled);
    playback.globalFrameIndexListenable.removeListener(
      prerenderScheduler.wake,
    );
    transports.dispose();
    audioScrubber.dispose();
    audioDeviceTransport.dispose();
    playback.dispose();
    prerenderScheduler.dispose();
    framePictures.dispose();
  }
}

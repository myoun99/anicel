import 'dart:async' show Timer, unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../services/import/media_identity_reader.dart';
import '../../core/path_names.dart';
import '../../services/persistence/media_staging_store.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_frame_range.dart';
import '../playback/audio_device_transport.dart';
import '../../models/audio_sync_settings.dart';
import '../playback/canvas_playback_controller.dart';
import '../text/app_strings.dart';
import '../../services/command.dart';
import '../../services/commands/cut_command_coordinator.dart';
import '../../services/commands/update_layer_timeline_command.dart';
import '../../native/qa_audio_native.dart' show QaAudioNative;
import '../../native/qa_audio_device.dart'
    show QaAudioDevice, audioDeviceIndexByName, openAudioOutput;
import '../../services/audio/audio_mixer_reference.dart'
    show AudioMixClip, AudioMixSource;
import '../playback/audio_input_monitor.dart';
import '../playback/audio_playback_schedule.dart' show ScheduledAudioClip;
import '../../services/audio/conform_pcm_codec.dart' show encodeConform;
import '../../services/commands/update_media_assets_command.dart';
import '../../models/se_take_placement.dart';
import '../../services/audio/audio_peaks_extractor.dart'
    show AudioPeakBucketFold, AudioPeaks, loudestChannelMagnitude;
import '../playback/audio_recorder.dart';
import '../playback/voice_take_processing.dart';
import '../../services/project_repository.dart';
import '../audio/audio_conform_store.dart';

/// The voice-recording section of the editor session: guide takes and ADR
/// cueing (AUDIO-PRO R5, REC1-E), the settings input meter and test tone
/// (REC1-D2), the live take preview (REC1-C), and the take's landing.
///
/// It moved out of [EditorSessionManager] whole, and its public verbs are
/// still called on the session — every one of them has a one-line delegation
/// there.
///
/// What it needs from the session it NAMES: the twenty-one members in the
/// constructor below. That width is the finding, not an accident of the move
/// — this block is a client of most of the session's audio and timeline
/// state rather than a passenger on it, and a constructor that lists them is
/// the only honest way to say so. (The settings block that moved first
/// needed none, which is why it looks nothing like this.)
///
/// They arrive as closures rather than values on purpose. Several —
/// `playback`, `audioConformStore`, `audioDeviceTransport` — are `late final`
/// on the session, so taking them by value here would force them into
/// existence at a different moment than the app does today.
///
/// The four test hooks below lost their `@visibleForTesting` on the way: the
/// session forwards them, and that forwarding is production code. The
/// annotation moved with the member that callers actually see, which is the
/// one on [EditorSessionManager].
class EditorVoiceRecording {
  EditorVoiceRecording({
    required CanvasPlaybackController Function() playback,
    required AudioDeviceTransport Function() audioDeviceTransport,
    required AudioConformStore Function() audioConformStore,
    required ValueNotifier<AudioSyncSettings> Function() audioSyncSettings,
    required ProjectRepository Function() repository,
    required CutCommandCoordinator Function() cutCommandCoordinator,
    required AppStrings Function() uiStrings,
    required ProjectFrameRate Function() projectFrameRate,
    required int Function() activeCutGlobalStartFrame,
    required int Function() editingGlobalFrame,
    required int? Function() gapParkedGlobalFrame,
    required TimelineRowAddress Function() standingRow,
    required LayerId Function() openSeLane,
    required Layer? Function(LayerId) trackSeGlobalLayerById,
    required FrameId Function(LayerId) mintFrameId,
    required List<MediaAsset> Function() mediaAssets,
    required void Function(String, Uint8List) rememberMediaFingerprint,
    required MediaStagingStore staging,
    required ValueNotifier<TimelineFrameRangeSelection?> Function()
    frameRangeSelection,
    required ValueNotifier<TrackFrameRangeSelection?> Function()
    trackFrameRangeSelection,
    required void Function() notify,
  }) : _playback = playback,
       _audioDeviceTransport = audioDeviceTransport,
       _audioConformStore = audioConformStore,
       _audioSyncSettings = audioSyncSettings,
       _staging = staging,
       _repositoryRef = repository,
       _cutCommandCoordinatorRef = cutCommandCoordinator,
       _uiStrings = uiStrings,
       _projectFrameRate = projectFrameRate,
       _activeCutGlobalStartFrame = activeCutGlobalStartFrame,
       _editingGlobalFrame = editingGlobalFrame,
       _gapParkedGlobalFrame = gapParkedGlobalFrame,
       _standingRow = standingRow,
       _openSeLane = openSeLane,
       _trackSeGlobalLayerById = trackSeGlobalLayerById,
       _mintFrameIdRef = mintFrameId,
       _mediaAssets = mediaAssets,
       _rememberMediaFingerprint = rememberMediaFingerprint,
       _frameRangeSelection = frameRangeSelection,
       _trackFrameRangeSelection = trackFrameRangeSelection,
       _notify = notify;

  // --- The session, seen from here -----------------------------------------
  //
  // Each accessor keeps the name the session calls it by, so the body below
  // this line is the session's own text, unedited. A move that retyped 964
  // lines would be a rewrite wearing a move's diff.

  final CanvasPlaybackController Function() _playback;
  CanvasPlaybackController get playback => _playback();

  final AudioDeviceTransport Function() _audioDeviceTransport;
  AudioDeviceTransport get audioDeviceTransport => _audioDeviceTransport();

  final AudioConformStore Function() _audioConformStore;
  AudioConformStore get audioConformStore => _audioConformStore();

  final ValueNotifier<AudioSyncSettings> Function() _audioSyncSettings;
  ValueNotifier<AudioSyncSettings> get audioSyncSettings =>
      _audioSyncSettings();

  final ProjectRepository Function() _repositoryRef;
  ProjectRepository get _repository => _repositoryRef();

  final CutCommandCoordinator Function() _cutCommandCoordinatorRef;
  CutCommandCoordinator get _cutCommandCoordinator =>
      _cutCommandCoordinatorRef();

  final AppStrings Function() _uiStrings;
  AppStrings get uiStrings => _uiStrings();

  final ProjectFrameRate Function() _projectFrameRate;
  ProjectFrameRate get projectFrameRate => _projectFrameRate();

  final int Function() _activeCutGlobalStartFrame;
  int get activeCutGlobalStartFrame => _activeCutGlobalStartFrame();

  final int Function() _editingGlobalFrame;
  int get editingGlobalFrame => _editingGlobalFrame();

  final int? Function() _gapParkedGlobalFrame;
  int? get gapParkedGlobalFrame => _gapParkedGlobalFrame();

  /// The row the user stands on — on either panel.
  final TimelineRowAddress Function() _standingRow;

  /// Adds a track SE lane and answers its id — the verb 「Add layer ▸ SE」
  /// runs, so the new lane lands and reads as that one would.
  final LayerId Function() _openSeLane;

  /// The track SE lane under the user's feet, or null when they stand on
  /// any other row.
  LayerId? _laneUnderfoot() {
    final layerId = _standingRow().owningLayerId;
    return layerId != null && trackSeGlobalLayerById(layerId) != null
        ? layerId
        : null;
  }

  final Layer? Function(LayerId) _trackSeGlobalLayerById;
  Layer? trackSeGlobalLayerById(LayerId layerId) =>
      _trackSeGlobalLayerById(layerId);

  final FrameId Function(LayerId) _mintFrameIdRef;
  FrameId _mintFrameId(LayerId layerId) => _mintFrameIdRef(layerId);

  final List<MediaAsset> Function() _mediaAssets;
  List<MediaAsset> get mediaAssets => _mediaAssets();

  /// Where a take's bytes go the moment it lands — the same store every
  /// import that carries writes into.
  ///
  /// 🚨The STORE, not a `stageCarriedBytes` closure. A take is the one
  /// carried asset with no file of its own, so this needs two things the
  /// closure could not offer: `stageCarriedBytesInMemory` to write bytes
  /// that were never on disk, and `find` to walk for a free take name at
  /// an address that is not a file.
  final MediaStagingStore _staging;

  final void Function(String, Uint8List) _rememberMediaFingerprint;
  void rememberMediaFingerprint(String poolPath, Uint8List bytes) =>
      _rememberMediaFingerprint(poolPath, bytes);

  final ValueNotifier<TimelineFrameRangeSelection?> Function()
  _frameRangeSelection;
  ValueNotifier<TimelineFrameRangeSelection?> get frameRangeSelection =>
      _frameRangeSelection();

  final ValueNotifier<TrackFrameRangeSelection?> Function()
  _trackFrameRangeSelection;

  // 🪦**`_projectFilePath` STOOD HERE** and its one reader was
  // `releaseShelfTakesToProject`, which asked「has this project got a file
  // yet?」to decide whether its shelf takes were the first save's to hand
  // over. A take is staged like every other carried asset now, so the save
  // absorbs it by the same rule as an import and this section no longer
  // needs to know whether the project has a home.

  /// The session's own `notifyListeners`, which is `@protected` there and so
  /// cannot be called across the file boundary without this.
  final void Function() _notify;
  void notifyListeners() => _notify();

  // --- Guide voice recording (AUDIO-PRO R5) --------------------------------

  /// True while the microphone is live — the record button's state.
  final ValueNotifier<bool> isVoiceRecording = ValueNotifier<bool>(false);

  /// A take the TRANSPORT finished (stop pressed mid-take): the message
  /// the toggle path would have returned, for whoever hosts the snackbar.
  /// Null = finished clean (or nothing to say).
  final ValueNotifier<String?> voiceRecordingNotice = ValueNotifier<String?>(
    null,
  );

  AudioRecorder? _voiceRecorder;
  LayerId? _voiceRecordLaneId;
  int _voiceRecordAnchorFrame = 0;
  int? _voiceRecordPunchEndFrame;
  int _voiceRecordHeadTrimSamples = 0;
  bool _voiceRecordStartedRoll = false;

  // 🪦**THE TAKE SHELF IS GONE, AND SO IS ITS BOOKKEEPING** (유저
  // 2026-09-08). Two fields stood here — the folder this session pinned at
  // its first take, and the set of WAVs it had written there — and both
  // existed because the shelf was a CONFIGURABLE folder outside the app:
  // a mid-session settings change could scatter one session's takes, and
  // somebody had to remember which ones were this session's to hand over.
  // A take is staged like every other carried asset now, so the staging
  // store owns where it is and how long it lives, and there is nothing
  // left here to remember.

  /// Capture-chain settings SNAPSHOT at arm time (REC1-D): a take records
  /// with the gain/fold it started under; mid-take settings edits apply
  /// to the next one.
  int _voiceRecordGainDb = 0;
  VoiceInputChannelMode _voiceRecordChannelMode = VoiceInputChannelMode.device;
  bool _voiceRecordDenoise = false;
  bool _lastVoiceTakeClipped = false;

  /// The transport's clip light (REC1-D): latches on the first post-gain
  /// sample at the ceiling and stays lit for the rest of the take — the
  /// performer sees "that pass clipped" without reading a meter. Always
  /// on duty (the toast and block marker sit behind the notice toggle;
  /// this does not).
  final ValueNotifier<bool> voiceRecordClipLit = ValueNotifier<bool>(false);

  // --- ADR cueing (REC1-E) --------------------------------------------------

  /// Cue beeps riding the playback schedule while a take approaches its
  /// punch-in (REC1-E): three one-second-spaced beeps ending AT the
  /// punch — the "삐-삐-삐-(대사)" timing anchor, leaving the CHOSEN
  /// output device because they are ordinary schedule clips. Empty
  /// outside recording.
  List<ScheduledAudioClip> _voiceRecordCueClips = const [];
  List<ScheduledAudioClip> get voiceRecordCueClips => _voiceRecordCueClips;

  /// The streamer's window on the PLAYBACK axis (REC1-E): non-null while
  /// a take rolls toward a punch-in with the streamer enabled — the
  /// canvas overlay sweeps from [startFrame] to [punchFrame].
  ({int startFrame, int punchFrame})? _voiceRecordStreamerWindow;
  ({int startFrame, int punchFrame})? get voiceRecordStreamerWindow =>
      _voiceRecordStreamerWindow;

  Timer? _voiceRecordCountInTimer;
  String? _cueBeepPath;

  /// The OS temp folder holding [_cueBeepPath], kept so dispose can take it
  /// back. It is one small wav, but it was one small wav PER APP RUN left
  /// behind in the system temp forever.
  Directory? _cueBeepDirectory;

  void _deleteCueBeepDirectory() {
    final directory = _cueBeepDirectory;
    _cueBeepDirectory = null;
    _cueBeepPath = null;
    if (directory == null) {
      return;
    }
    try {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    } on Object {
      // A locked temp file is the OS's to clean up, not a shutdown failure.
    }
  }

  /// THE CUE BEEP, one sample at a time: 1 kHz for 90 ms with a 5 ms ramp
  /// at each end.
  ///
  /// ⛔TWO PLAYERS MADE IT — the WAV the take store plays and the PCM the
  /// device schedules for a count-in — and each spelled out the frequency,
  /// the length and the ramp. Two beeps that stopped agreeing would be two
  /// different cues for one moment, which is exactly what a count-in must
  /// not be. Only the LEVEL differs, so only the level is an argument.
  ///
  /// ⚠️The ramp is not decoration: a square-edged tone clicks, and the
  /// click is louder than the beep on a small speaker.
  static Float32List _cueBeepSamples({
    required int sampleRate,
    required double level,
  }) {
    final toneSamples = sampleRate * 9 ~/ 100;
    final ramp = sampleRate ~/ 200;
    final samples = Float32List(toneSamples);
    for (var sample = 0; sample < toneSamples; sample += 1) {
      var value = level * math.sin(2 * math.pi * 1000 * sample / sampleRate);
      if (sample < ramp) {
        value *= sample / ramp;
      } else if (sample >= toneSamples - ramp) {
        value *= (toneSamples - sample) / ramp;
      }
      samples[sample] = value;
    }
    return samples;
  }

  /// The cue beep on disk (project-rate mono, ~90 ms of 1 kHz with 5 ms
  /// ramps), written once per session and registered with the conform
  /// store like any take.
  String? _ensureCueBeepWav() {
    final existing = _cueBeepPath;
    if (existing != null && File(existing).existsSync()) {
      return existing;
    }
    try {
      final sampleRate = audioConformStore.projectSampleRate;
      final samples = _cueBeepSamples(sampleRate: sampleRate, level: 0.5);
      final wav = encodeConform(
        samples: samples,
        channels: 1,
        sampleRate: sampleRate,
      );
      _deleteCueBeepDirectory(); // A stale one only happens if the file vanished.
      final directory = Directory.systemTemp.createTempSync('qa_cue_');
      _cueBeepDirectory = directory;
      final file = File('${directory.path}/cue-beep.wav');
      file.writeAsBytesSync(wav);
      audioConformStore.invalidate(file.path);
      audioConformStore.warmPaths([file.path]);
      _cueBeepPath = file.path;
      return file.path;
    } on Object {
      return null; // No beep is a degraded cue, never a failed take.
    }
  }

  /// Stopped-⏺ count-in beeps: the same standalone device path as the
  /// test tone — [seconds] beeps a second apart, then the device closes
  /// so the transport can take it for the roll.
  /// The audio device, opened for a short cue, or null when it cannot be.
  ///
  /// ⛔TWO CUES OPENED IT — the count-in beeps and the output test tone —
  /// with the same four refusals and the same FALLBACK: a saved device
  /// that will not open drops back to the system default rather than
  /// leaving the user with silence and no reason. Written twice, the
  /// fallback is one edit away from existing on only one of them.
  ///
  /// ⚠️Refuses under FLUTTER_TEST: a widget test must never bind a real
  /// output, and the gate belongs with the opening, not at each caller.
  QaAudioDevice? _openDeviceForCue() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return null;
    }
    final device = QaAudioDevice.instance;
    if (device == null || playback.isActive || device.isOpen) {
      return null;
    }
    return openAudioOutput(
          device,
          sampleRate: 48000,
          preferredName: audioSyncSettings.value.outputDeviceName,
        )
        ? device
        : null;
  }

  void _playCountInBeeps(int seconds) {
    final device = _openDeviceForCue();
    if (device == null) {
      return;
    }
    final sampleRate = device.sampleRate;
    final channels = device.channels;
    final tone = _cueBeepSamples(sampleRate: sampleRate, level: 0.4);
    final toneSamples = tone.length;
    final pcm = Float32List(toneSamples * channels);
    for (var sample = 0; sample < toneSamples; sample += 1) {
      for (var channel = 0; channel < channels; channel += 1) {
        pcm[sample * channels + channel] = tone[sample];
      }
    }
    device.setSchedule(
      clips: [
        for (var beep = 0; beep < seconds; beep += 1)
          AudioMixClip(
            sourceIndex: 0,
            startSample: beep * sampleRate,
            endSample: beep * sampleRate + toneSamples,
          ),
      ],
      sources: [AudioMixSource(samples: pcm, channels: channels)],
    );
    device.play(
      startSample: 0,
      stopSample: (seconds - 1) * sampleRate + toneSamples,
    );
    _testToneTimer?.cancel();
    _testToneTimer = Timer(Duration(milliseconds: seconds * 1000), () {
      if (!playback.isActive && device.isOpen) {
        device.stop();
        device.close();
      }
    });
  }

  // --- Settings input meter + test tone (REC1-D2) --------------------------

  AudioInputMonitor? _inputMonitor;
  Timer? _testToneTimer;

  /// The settings dialog's live input meter: attach while the section is
  /// mounted, detach when it goes. The monitor yields to the recorder
  /// (capture is single-open) and resumes when the take finishes.
  AudioInputMonitor attachInputMeter() {
    final monitor = _inputMonitor ??= AudioInputMonitor(
      device: Platform.environment['FLUTTER_TEST'] == 'true'
          ? null
          : QaAudioDevice.instance,
    );
    _resumeInputMeter();
    return monitor;
  }

  void detachInputMeter() {
    _inputMonitor?.dispose();
    _inputMonitor = null;
  }

  /// The input device choice changed while the dialog is open: reopen on
  /// the new microphone.
  void restartInputMeter() {
    _inputMonitor?.stop();
    _resumeInputMeter();
  }

  void _resumeInputMeter() {
    final monitor = _inputMonitor;
    if (monitor == null || monitor.isRunning || isVoiceRecording.value) {
      return;
    }
    final device = Platform.environment['FLUTTER_TEST'] == 'true'
        ? null
        : QaAudioDevice.instance;
    monitor.start(
      sampleRate: audioConformStore.projectSampleRate,
      deviceIndex: device == null
          ? -1
          : audioDeviceIndexByName(
              device,
              capture: true,
              name: audioSyncSettings.value.inputDeviceName,
            ),
    );
  }

  /// A short tone through the CHOSEN output device — the settings
  /// dialog's "is this speaker alive" button. Refuses while a transport
  /// run holds the device (it is busy making real sound). Returns false
  /// when nothing could open; the button stays quiet then.
  bool playOutputTestTone() {
    final device = _openDeviceForCue();
    if (device == null) {
      return false;
    }
    final sampleRate = device.sampleRate;
    final channels = device.channels;
    final toneSamples = sampleRate ~/ 2;
    final pcm = Float32List(toneSamples * channels);
    for (var sample = 0; sample < toneSamples; sample += 1) {
      final value = 0.25 * math.sin(2 * math.pi * 440 * sample / sampleRate);
      for (var channel = 0; channel < channels; channel += 1) {
        pcm[sample * channels + channel] = value;
      }
    }
    device.setSchedule(
      clips: [
        AudioMixClip(
          sourceIndex: 0,
          startSample: 0,
          endSample: toneSamples,
          // 10 ms ramps: a bare sine edge lands as a click.
          fadeInSamples: sampleRate ~/ 100,
          fadeOutSamples: sampleRate ~/ 100,
        ),
      ],
      sources: [AudioMixSource(samples: pcm, channels: channels)],
    );
    device.play(startSample: 0, stopSample: toneSamples);
    _testToneTimer?.cancel();
    _testToneTimer = Timer(const Duration(milliseconds: 700), () {
      // The transport may have started meanwhile — never yank ITS device.
      if (!playback.isActive && device.isOpen) {
        device.stop();
        device.close();
      }
    });
    return true;
  }

  /// The SE lane whose playback yields to the microphone while a take
  /// rolls (the DAW armed-track rule); null when not recording.
  LayerId? get voiceRecordingMutedLaneId =>
      isVoiceRecording.value ? _voiceRecordLaneId : null;

  /// [voiceRecordingMutedLaneId] as the set the schedule builders take.
  Set<LayerId> get recordingMutedLayerIds {
    final lane = voiceRecordingMutedLaneId;
    return lane == null ? const <LayerId>{} : <LayerId>{lane};
  }

  // --- Live take preview (REC1-C) ------------------------------------------

  /// The sentinel clip path a rolling take's preview carries — never a
  /// real file; [audioPeaksForDisplay] resolves it to the live envelope.
  static const String voiceRecordPreviewPath = 'qa://recording-take';

  /// The armed lane WITH the in-flight take landed on it, recomputed
  /// through the same tape-style planner the stop uses — the timeline
  /// shows the real final state, not an overlay (user decision). Null
  /// outside recording. Changes at most once per FRAME (the boundary
  /// gate), and NEVER through a session notify: the timeline host
  /// subscribes directly (the R12-B playback-performance contract).
  final ValueNotifier<Layer?> voiceRecordPreviewLane = ValueNotifier<Layer?>(
    null,
  );

  /// The growing |peak| envelope of the take being recorded, folded from
  /// the recorder's chunk tap in the waveform store's own format.
  AudioPeaks? _voiceRecordLivePeaks;

  /// The same bucket fold the file path uses ([AudioPeakBucketFold]);
  /// non-null between arm and stop. The live path never [flush]es — a
  /// partial bucket waits for the next chunk, because a take in progress
  /// has no end yet.
  AudioPeakBucketFold? _voiceRecordPeakFold;
  int _voiceRecordLastPreviewLength = 0;

  /// What the waveform strips should paint for [path]: the live envelope
  /// for the preview sentinel, the conform store's peaks otherwise.
  AudioPeaks? audioPeaksForDisplay(String path) =>
      path == voiceRecordPreviewPath
      ? _voiceRecordLivePeaks
      : audioConformStore.peaksFor(path);

  /// Folds one captured chunk into the live envelope (the recorder's tap;
  /// split out so tests can feed made chunks).
  ///
  /// POST-chain (REC1-D): the channel fold picks what the take will
  /// keep, the gain scales it — the envelope and the clip light both
  /// show what lands in the file, which is the whole point of baking.
  void debugIngestVoiceRecordChunk(Float32List interleaved, int channels) {
    final fold = _voiceRecordPeakFold;
    if (channels <= 0 || fold == null) {
      return;
    }
    final factor = micGainFactor(_voiceRecordGainDb);
    final mode = channels >= 2
        ? _voiceRecordChannelMode
        : VoiceInputChannelMode.device;
    final frames = interleaved.length ~/ channels;
    for (var frame = 0; frame < frames; frame += 1) {
      final base = frame * channels;
      double magnitude;
      if (mode == VoiceInputChannelMode.device) {
        // ⛔NOT the fold. `device` keeps every channel in the TAKE, so
        // there is nothing to fold — and a meter needs one scalar, so it
        // takes the loudest channel, the same honest single-lane answer
        // [peaksFromSamples] gives a file. Same rule, same function.
        magnitude = loudestChannelMagnitude(interleaved, base, channels);
      } else {
        final picked = mode.pickFrame(interleaved, base, channels);
        magnitude = picked < 0 ? -picked : picked;
      }
      final scaled = magnitude * factor;
      if (scaled >= voiceClipThreshold && !voiceRecordClipLit.value) {
        voiceRecordClipLit.value = true;
      }
      fold.add(scaled);
    }
  }

  /// Recomputes the preview when the roll crosses into a new frame —
  /// listener on the playback frame channel while recording. The planner
  /// runs on the lane's COMMIT form with the elapsed length; preview
  /// instance ids are minted fresh per pass (display-only material).
  void _syncVoiceRecordPreview() {
    if (!isVoiceRecording.value) {
      return;
    }
    final laneId = _voiceRecordLaneId;
    final lane = laneId == null ? null : trackSeGlobalLayerById(laneId);
    final global = _playbackTrackGlobalFrame();
    if (lane == null || global == null) {
      return;
    }
    if (_takeEndsWhereThePlayheadTurnedBack(global)) {
      return;
    }
    // The playhead's frame is the one being spoken into: it counts.
    var end = global + 1;
    final punchEnd = _voiceRecordPunchEndFrame;
    if (punchEnd != null && end > punchEnd) {
      end = punchEnd;
    }
    final length = end - _voiceRecordAnchorFrame;
    if (length < 1) {
      if (voiceRecordPreviewLane.value != null) {
        voiceRecordPreviewLane.value = null;
      }
      return;
    }
    if (length == _voiceRecordLastPreviewLength &&
        voiceRecordPreviewLane.value != null) {
      return; // Same frame: the boundary gate holds the rebuild back.
    }
    _voiceRecordLastPreviewLength = length;
    // No flush: a take in progress has no end, so its partial bucket
    // waits for the next chunk rather than landing short.
    _voiceRecordLivePeaks = AudioPeaks(
      bucketsPerSecond: 40,
      peaks: _voiceRecordPeakFold?.toFloat32List() ?? Float32List(0),
    );
    var minted = 0;
    final plan = planSeTakePlacement(
      layer: lane,
      startFrame: _voiceRecordAnchorFrame,
      lengthFrames: length,
      filePath: voiceRecordPreviewPath,
      takeFrameId: const FrameId('rec-preview-take'),
      newFrameId: () => FrameId('rec-preview-${minted++}'),
    );
    voiceRecordPreviewLane.value = plan?.layer;
  }

  /// The frame the roll last showed during this take; null until it rolls.
  int? _voiceRecordLastGlobal;

  /// 🗣️F-178 ④ (유저 2026-09-24): 「지금 루프재생켜두면 녹음이 매번? 되서 뭔가
  /// 꼬이는거같은데」. A take lands at ONE anchor and runs forward from it, so
  /// it is one pass: once the playhead steps BACK — the loop wrapping, or a
  /// seek — what the microphone hears next belongs somewhere else on the
  /// track, and the take ends where the playhead had reached. Carrying on is
  /// what tangled it: the preview regrew from the anchor every lap, and the
  /// take landed as one block several laps long.
  bool _takeEndsWhereThePlayheadTurnedBack(int global) {
    final last = _voiceRecordLastGlobal;
    _voiceRecordLastGlobal = global;
    if (last == null || global >= last) {
      return false;
    }
    final reached = last + 1;
    final punchEnd = _voiceRecordPunchEndFrame;
    _voiceRecordPunchEndFrame = punchEnd == null
        ? reached
        : math.min(punchEnd, reached);
    unawaited(finishTakeThroughTheNotice());
    return true;
  }

  /// Finishes a rolling take where no button waits for the answer — the
  /// transport stopping, over a cut or a gap, or the playhead turning back —
  /// so what it has to say goes out on [voiceRecordingNotice].
  Future<void> finishTakeThroughTheNotice() async {
    if (!isVoiceRecording.value) {
      return;
    }
    voiceRecordingNotice.value = await stopVoiceRecordingAndPlace();
  }

  void _clearVoiceRecordPreview() {
    playback.globalFrameIndexListenable.removeListener(_syncVoiceRecordPreview);
    _voiceRecordLivePeaks = null;
    _voiceRecordPeakFold = null;
    _voiceRecordLastPreviewLength = 0;
    _voiceRecordLastGlobal = null;
    voiceRecordClipLit.value = false;
    // The ADR cueing retires with the take (REC1-E): the stop's own
    // notify rebuilds the schedules without the beeps.
    _voiceRecordCountInTimer?.cancel();
    _voiceRecordCountInTimer = null;
    _voiceRecordCueClips = const [];
    _voiceRecordStreamerWindow = null;
    if (voiceRecordPreviewLane.value != null) {
      voiceRecordPreviewLane.value = null;
    }
  }

  /// Test hook: stand in for the microphone.
  AudioRecorder Function()? debugVoiceRecorderFactory;

  /// Test hook: stand in for the native RNNoise pass. Null result =
  /// "declined, keep the raw take" — the same contract as the C.
  Float32List? Function(Float32List samples, int channels, int sampleRate)?
  debugVoiceDenoiser;

  /// RNNoise runs at exactly this rate; capture asks for it when the
  /// suppression toggle is on, and the take conforms once on placement.
  static const int voiceDenoiseCaptureRate = 48000;

  static Float32List? _nativeVoiceDenoiser(
    Float32List samples,
    int channels,
    int sampleRate,
  ) => QaAudioNative.instance?.denoiseVoice(
    samples: samples,
    channels: channels,
    sampleRate: sampleRate,
  );

  /// The playing position on the TRACK-global axis, or null while
  /// playback is inactive. The all-cuts playlist IS the track axis
  /// (gaps included); the active-cut playlist is that cut alone, so its
  /// frames shift by the cut's global start.
  int? _playbackTrackGlobalFrame() {
    final global = playback.globalFrameIndexListenable.value;
    if (global == null) {
      return null;
    }
    return playback.scope == PlaybackScope.allCuts
        ? global
        : activeCutGlobalStartFrame + global;
  }

  /// Opens the microphone and ROLLS the transport (REC1-B): record =
  /// play + capture, the DAW rule — the playhead moves, every other row
  /// is audible, and the take lands where the roll started.
  ///
  /// The take lands on the track SE lane the user STANDS ON, and on a new
  /// lane when they stand anywhere else. A range selection on that lane is
  /// the PUNCH window: capture begins when playback enters it and ends at
  /// its far edge, however long the transport keeps rolling.
  ///
  /// 🗣️F-178 (유저 2026-09-24): 「일단 지금 se행에 서있는데도 녹음버튼누르면
  /// se행에 서있으라고 메시지뜸. 그리고 서있으라고 할게아니라 어디에 서있든
  /// 녹음가능하게하고, 동작을 se행에 안서있으면 새 se레이어만들고 거기서하고,
  /// 서있으면 해당se행에서 시작하도록」. ⛔The refusal read the ACTIVE layer,
  /// and the storyboard's SE rows stand a row apart from the layer you draw
  /// on (유저 2026-07-27) — so standing on one there never counted.
  VoiceRecordStartResult startVoiceRecording() {
    if (isVoiceRecording.value) {
      return VoiceRecordStartResult.alreadyRecording;
    }
    // The settings meter yields the microphone to the take (REC1-D2).
    _inputMonitor?.stop();
    final opened = _openVoiceRecorder();
    if (opened == null) {
      return VoiceRecordStartResult.deviceFailed;
    }
    // Only once the microphone is open: a device that refused leaves no
    // empty lane behind.
    final laneId = _laneUnderfoot() ?? _openSeLane();
    final rollStart = _voiceRollStartFrame();
    final punch = _voicePunchWindow(laneId, rollStart: rollStart);

    _voiceRecorder = opened.recorder;
    _voiceRecordLaneId = laneId;
    _voiceRecordAnchorFrame = punch.anchor;
    _voiceRecordPunchEndFrame = punch.end;
    // The performer speaks against what they HEAR, which runs the output
    // latency behind the mix clock — that much comes off the take's head
    // (the DAW recording-compensation rule) — plus the run-up between
    // the roll start and the punch-in.
    _voiceRecordHeadTrimSamples =
        audioDeviceTransport.report.reportedLatencySamples +
        projectFrameRate.frameToSample(punch.anchor - rollStart, opened.rate);
    isVoiceRecording.value = true;
    // Capture-chain snapshot (REC1-D): gain and channel fold ride the
    // whole take; the clip light re-arms per take.
    _voiceRecordGainDb = AudioSyncSettings.clampMicGainDb(
      audioSyncSettings.value.micGainDb,
    );
    _voiceRecordChannelMode = audioSyncSettings.value.inputChannelMode;
    _voiceRecordDenoise = opened.denoise;
    _lastVoiceTakeClipped = false;
    voiceRecordClipLit.value = false;
    // Live preview (REC1-C): the recorder's chunk tap feeds the growing
    // waveform; the playback frame channel drives the block preview at
    // frame boundaries — no session notify per tick (R12-B).
    _voiceRecordPeakFold = AudioPeakBucketFold(
      samplesPerBucket: opened.rate ~/ 40,
    );
    opened.recorder.onChunk = debugIngestVoiceRecordChunk;
    playback.globalFrameIndexListenable.addListener(_syncVoiceRecordPreview);

    _rollVoiceTransport(
      rollStart: rollStart,
      punchEnd: punch.end,
      rate: opened.rate,
    );
    _armVoiceCues(anchor: punch.anchor, rollStart: rollStart);
    _syncVoiceRecordPreview();
    notifyListeners(); // Armed-lane mute + cue clips join the schedules.
    return VoiceRecordStartResult.started;
  }

  /// Opens the microphone, or null when the device refused to start.
  ///
  /// Suppression captures at RNNoise's native 48 kHz; the take conforms
  /// ONCE on placement, like any imported rate. ⛔A device that refused
  /// 48 kHz records CLEAN — RNNoise has no other rate, and a silently
  /// resampled pass would be a different promise.
  ({AudioRecorder recorder, int rate, bool denoise})? _openVoiceRecorder() {
    final device = Platform.environment['FLUTTER_TEST'] == 'true'
        ? null
        : QaAudioDevice.instance;
    final recorder =
        debugVoiceRecorderFactory?.call() ?? AudioRecorder(device: device);
    final wantDenoise = audioSyncSettings.value.denoiseVoice;
    final rate = recorder.start(
      sampleRate: wantDenoise
          ? voiceDenoiseCaptureRate
          : audioConformStore.projectSampleRate,
      deviceIndex: device == null
          ? -1
          : audioDeviceIndexByName(
              device,
              capture: true,
              name: audioSyncSettings.value.inputDeviceName,
            ),
    );
    if (rate == 0) {
      return null;
    }
    return (
      recorder: recorder,
      rate: rate,
      denoise: wantDenoise && rate == voiceDenoiseCaptureRate,
    );
  }

  /// Where the roll starts, on the track-global axis: the playing (or
  /// paused) position when the transport is active, otherwise the
  /// editing playhead — gap parking included (a gap is a place on the
  /// track; the lane is cut-independent).
  int _voiceRollStartFrame() => playback.isActive
      ? (_playbackTrackGlobalFrame() ??
            (gapParkedGlobalFrame ?? editingGlobalFrame))
      : (gapParkedGlobalFrame ?? editingGlobalFrame);

  /// The punch window: a range selection on the armed lane, on the track
  /// axis. Without one the take simply anchors at the roll.
  ({int anchor, int? end}) _voicePunchWindow(
    LayerId laneId, {
    required int rollStart,
  }) {
    final span = _rangeOnLane(laneId);
    if (span == null || rollStart >= span.end) {
      return (anchor: rollStart, end: null);
    }
    return (anchor: math.max(rollStart, span.start), end: span.end);
  }

  /// The range selected on [laneId], from whichever panel made it.
  ///
  /// #16's law (유저: 「스토리보드패널에서 S행의 프레임생성이 안됨」): THE
  /// TRACK RANGE SPEAKS FIRST. The storyboard's S-row drag writes it (on the
  /// track axis already) and clears the cut-local one, so a punch that read
  /// the timeline's cells alone ignored every range made on the storyboard —
  /// which F-178 made reachable, by letting a take start from an S row there.
  ({int start, int end})? _rangeOnLane(LayerId laneId) {
    final rows = _trackFrameRangeSelection().value;
    if (rows != null && rows.coversRow(LayerRowAddress(laneId))) {
      return (start: rows.startFrame, end: rows.endFrameExclusive);
    }
    final cells = frameRangeSelection.value;
    if (cells == null || !cells.coversLayer(laneId)) {
      return null;
    }
    final offset = activeCutGlobalStartFrame;
    return (
      start: cells.startIndex + offset,
      end: cells.endIndexExclusive + offset,
    );
  }

  /// Starts the transport under the take, after the count-in if there is
  /// one.
  ///
  /// Stopped-⏺ count-in (REC1-E): the mic is ALREADY rolling, the
  /// transport waits — the wait rides the head trim, so the take still
  /// anchors where the roll will start. A punch has its own run-up; the
  /// count-in stays out of its way.
  void _rollVoiceTransport({
    required int rollStart,
    required int? punchEnd,
    required int rate,
  }) {
    if (playback.isActive && playback.isPlaying) {
      _voiceRecordStartedRoll = false;
      return;
    }
    _voiceRecordStartedRoll = true;
    final countInSeconds = punchEnd == null
        ? AudioSyncSettings.clampCountInSeconds(
            audioSyncSettings.value.countInSeconds,
          )
        : 0;
    if (countInSeconds <= 0) {
      _startVoiceRoll(rollStart);
      return;
    }
    _voiceRecordHeadTrimSamples += countInSeconds * rate;
    if (audioSyncSettings.value.cueBeeps) {
      _playCountInBeeps(countInSeconds);
    }
    _voiceRecordCountInTimer?.cancel();
    _voiceRecordCountInTimer = Timer(Duration(seconds: countInSeconds), () {
      if (!isVoiceRecording.value) {
        return;
      }
      _startVoiceRoll(rollStart);
    });
  }

  /// 🚨T28: with pause gone, "active" already means rolling — there is
  /// nothing to resume, only a transport to start when there is none.
  void _startVoiceRoll(int rollStart) {
    if (!playback.isPlaying) {
      playback.play(scope: PlaybackScope.allCuts, startGlobalFrame: rollStart);
    }
  }

  /// ADR cue clips + the streamer window (REC1-E): only with a punch
  /// AHEAD of the roll — the approach is what they count down.
  void _armVoiceCues({required int anchor, required int rollStart}) {
    _voiceRecordCueClips = const [];
    _voiceRecordStreamerWindow = null;
    final secondFrames = projectFrameRate.framesCoveringExactSeconds(1, 1);
    // ⛔No `punchEnd == null` case: a window that is not a punch anchors
    // AT the roll, so `anchor <= rollStart` is the same question and one
    // flag must not answer two. This early-out is EQUIVALENT — both
    // builders below refuse a zero run-up on their own — and is here so
    // a plain record does not walk the cue machinery at all.
    if (anchor <= rollStart || secondFrames <= 0) {
      return;
    }
    // A cut-scoped transport plays its own axis, so the cues have to be
    // stated in it.
    final axisShift =
        playback.isActive && playback.scope == PlaybackScope.activeCut
        ? activeCutGlobalStartFrame
        : 0;
    final settingsNow = audioSyncSettings.value;
    if (settingsNow.cueBeeps) {
      _voiceRecordCueClips = _countdownBeeps(
        anchor: anchor,
        rollStart: rollStart,
        axisShift: axisShift,
        secondFrames: secondFrames,
      );
    }
    if (settingsNow.streamerEnabled) {
      final approach = math.min(3 * secondFrames, anchor - rollStart);
      if (approach >= 1) {
        _voiceRecordStreamerWindow = (
          startFrame: anchor - approach - axisShift,
          punchFrame: anchor - axisShift,
        );
      }
    }
  }

  /// The three beeps before the punch — only the ones that fall after the
  /// roll start, because a beep before the roll is a beep nobody hears.
  List<ScheduledAudioClip> _countdownBeeps({
    required int anchor,
    required int rollStart,
    required int axisShift,
    required int secondFrames,
  }) {
    final beepPath = _ensureCueBeepWav();
    if (beepPath == null) {
      return const [];
    }
    final beepFrames = math.max(
      1,
      projectFrameRate.framesCoveringExactSeconds(9, 100),
    );
    return [
      for (var beep = 3; beep >= 1; beep -= 1)
        if (anchor - beep * secondFrames >= rollStart)
          ScheduledAudioClip(
            filePath: beepPath,
            startFrame: anchor - beep * secondFrames - axisShift,
            endFrameExclusive:
                anchor - beep * secondFrames - axisShift + beepFrames,
            gain: 0.8,
          ),
    ];
  }

  /// Stops the take and lands it on the armed lane: WAV to disk, pool
  /// entry, and the lane's tape-style swap (trims, erasures, the new
  /// block and its link) — ONE undo for the whole landing.
  ///
  /// A roll this take started stops with it (record = play + capture,
  /// both directions). Returns null on clean success, otherwise a
  /// message for the user — including the case where the take was PLACED
  /// but the capture ring dropped frames (a damaged take must say so).
  Future<String?> stopVoiceRecordingAndPlace() async {
    final recorder = _voiceRecorder;
    _voiceRecorder = null;
    final laneId = _voiceRecordLaneId;
    _voiceRecordLaneId = null;
    final startedRoll = _voiceRecordStartedRoll;
    _voiceRecordStartedRoll = false;
    isVoiceRecording.value = false;
    // The preview retires FIRST (listener off, sentinel peaks gone) —
    // every return path below shows committed rows again; a successful
    // placement swaps the real take in within the same stop.
    _clearVoiceRecordPreview();
    final recording = recorder?.stop();
    // The recorder released the microphone: the settings meter (if the
    // dialog is still open) takes it back.
    _resumeInputMeter();
    if (startedRoll && playback.isActive) {
      // Re-enters _onPlaybackStopped; the recorder is already detached.
      playback.stop();
    }
    notifyListeners(); // The armed lane unmutes.
    if (recording == null) {
      return uiStrings.recordNothingRecording;
    }
    if (recording.length == 0) {
      return uiStrings.recordTakeEmpty;
    }
    final placed = await placeVoiceRecording(
      recording,
      laneId: laneId,
      anchorFrame: _voiceRecordAnchorFrame,
      punchEndFrame: _voiceRecordPunchEndFrame,
      headTrimSamples: _voiceRecordHeadTrimSamples,
      gainDb: _voiceRecordGainDb,
      channelMode: _voiceRecordChannelMode,
      denoise: _voiceRecordDenoise,
    );
    if (!placed) {
      return uiStrings.recordPlacementFailed;
    }
    if (recording.droppedFrames > 0) {
      return uiStrings.recordDroppedFramesTemplate.replaceAll(
        '{count}',
        '${recording.droppedFrames}',
      );
    }
    if (_lastVoiceTakeClipped && audioSyncSettings.value.clippingNotice) {
      return uiStrings.recordTakeClipped;
    }
    return null;
  }

  /// Lands a finished take (split out so tests can drive it with a made
  /// recording): trims the head (latency + punch run-up), clamps to the
  /// punch window, writes the WAV, and swaps the lane through the
  /// tape-style planner — pool entry and lane swap in ONE undo step.
  Future<bool> placeVoiceRecording(
    AudioRecording recording, {
    required LayerId? laneId,
    required int anchorFrame,
    int? punchEndFrame,
    int headTrimSamples = 0,
    int gainDb = 0,
    VoiceInputChannelMode channelMode = VoiceInputChannelMode.device,
    bool denoise = false,
  }) async {
    final lane = laneId == null ? null : trackSeGlobalLayerById(laneId);
    if (lane == null ||
        anchorFrame < 0 ||
        recording.channels <= 0 ||
        recording.sampleRate <= 0) {
      return false;
    }
    var samples = recording.samples;
    if (headTrimSamples > 0) {
      final trimFloats = headTrimSamples * recording.channels;
      if (trimFloats >= samples.length) {
        return false; // Shorter than the run-up it rode on: nothing real.
      }
      samples = Float32List.sublistView(samples, trimFloats);
    }
    // Suppression first, on the trimmed raw capture (per channel, the
    // OBS filter order) — the RNNoise round. A declined pass (no native
    // engine, wrong rate) keeps the raw take: recording never fails
    // because a denoiser is missing.
    if (denoise) {
      final suppressed = (debugVoiceDenoiser ?? _nativeVoiceDenoiser)(
        samples,
        recording.channels,
        recording.sampleRate,
      );
      if (suppressed != null) {
        samples = suppressed;
      }
    }
    // The capture chain (REC1-D): channel fold + baked gain, applied to
    // the trimmed take — the file holds exactly what the meter showed.
    final processed = processVoiceTake(
      samples: samples,
      channels: recording.channels,
      gainDb: gainDb,
      channelMode: channelMode,
    );
    samples = processed.samples;
    final channels = processed.channels;
    _lastVoiceTakeClipped = processed.clipped;
    // Whole frames covering the take, so the block window matches what
    // was actually said (min 1 — a sub-frame take still needs a cell).
    var lengthFrames = math.max(
      1,
      projectFrameRate.framesCoveringExactSeconds(
        samples.length ~/ channels,
        recording.sampleRate,
      ),
    );
    final window = punchEndFrame == null ? null : punchEndFrame - anchorFrame;
    if (window != null) {
      if (window < 1) {
        return false;
      }
      if (lengthFrames > window) {
        lengthFrames = window;
        // The file carries the window alone — capture past the punch-out
        // is context the performer heard, not part of the take.
        final windowFloats =
            projectFrameRate.frameToSample(window, recording.sampleRate) *
            channels;
        if (windowFloats > 0 && windowFloats < samples.length) {
          samples = Float32List.sublistView(samples, 0, windowFloats);
        }
      }
    }
    final wav = encodeConform(
      samples: samples,
      channels: channels,
      sampleRate: recording.sampleRate,
    );
    final carry = await _stageRecordingWav(wav, laneName: lane.name);
    if (carry == null) {
      return false;
    }
    final path = carry.poolPath;

    final plan = planSeTakePlacement(
      layer: lane,
      startFrame: anchorFrame,
      lengthFrames: lengthFrames,
      filePath: path,
      takeFrameId: _mintFrameId(lane.id),
      newFrameId: () => _mintFrameId(lane.id),
      takeClipped: processed.clipped,
    );
    if (plan == null) {
      return false;
    }
    // The ONE undo step — pool entry + the lane's whole swap — and then the
    // conform (below).
    audioConformStore.invalidate(path);
    // 🪦A second `stageCarriedBytes(...)` stood here, and its comment said
    // 「⛔BEFORE the pool records it, like every other way an asset becomes
    // carried」. The law is unchanged and the call is gone because
    // [_stageRecordingWav] above IS the staging now — it already ran, and
    // it ran before this line, so the bytes are held before the pool ever
    // hears the name.
    final pool = mediaAssets;
    _cutCommandCoordinator.historyManager.execute(
      CompositeCommand(
        description: 'Record voice',
        commands: [
          if (!pool.any((asset) => asset.path == path))
            UpdateMediaAssetsCommand(
              repository: _repository,
              mediaAssets: [
                ...pool,
                MediaAsset(
                  path: path,
                  name: mediaAssetDefaultName(path),
                  // A take is the project's own recording, so the project
                  // carries it. The shelf copy stays where it is — losing
                  // a performance because a save never happened is not a
                  // trade anyone would take.
                  //
                  // 🚨And that sentence is exactly why the bytes are staged
                  // just below: the shelf file is on the user's disk, so
                  // clearing the Recordings folder before saving used to
                  // take the performance with it. Carrying now means held,
                  // not just flagged.
                  carriedAs: carry.token,
                  identity: readMediaIdentity(path),
                ),
              ],
              description: 'Record voice',
            ),
          UpdateLayerTimelineCommand(
            repository: _repository,
            before: lane,
            after: plan.layer,
          ),
        ],
      ),
    );
    // ⚠️AFTER the pool records the take, not before: a take has no file of
    // its own, and its bytes are found through the carry the pool names
    // (`ProjectFile.mediaByteSourceFor`) — asked before the record, there
    // was none, and the conform read a path where nothing is.
    audioConformStore.warmPaths([path]);
    notifyListeners();
    return true;
  }

  /// Stages a take's bytes and answers the carry they are held as — the
  /// pool path it is known by, and its own token — or null when the write
  /// failed.
  ///
  /// Named `<lane>_T<n>.wav` (REC1-B): the recording-session convention —
  /// the pool line alone says whose take it is and which pass.
  ///
  /// 🚨★★★**THE POOL PATH NEVER EXISTS AS A FILE, AND THAT IS THE HONEST
  /// SHAPE** (유저 2026-09-08: 앱이 쓰는 곳은 컨테이너와 프로젝트 파일
  /// 둘뿐). Every other carried asset has an original the user made
  /// somewhere else and a staged copy derived from its path. A take has no
  /// original — this app made it — so the pool path is its ADDRESS and the
  /// staged file is the ONLY file, written once, at the name the store
  /// derives.
  ///
  /// 🪦It used to write a plain WAV onto a visible shelf outside the
  /// container and then hand that file to the staging store, which read it
  /// back and wrote a second copy. One performance, two files, and one of
  /// them in a folder the app had no business writing to — on this machine
  /// `%USERPROFILE%/Documents/Anicel` resolved case-insensitively onto the
  /// source repository itself, which somebody had papered over with a
  /// `.gitignore` line rather than fixed.
  ///
  /// ⚠️The free-name walk asks the STORE and the POOL, never the
  /// filesystem: the pool path is not a file, and the room is per-run, so
  /// a walk over disk alone would restart at `T01` every launch and put two
  /// `S1_T01.wav` rows in one project — which is exactly the thing the
  /// naming convention exists to prevent.
  Future<MediaCarry?> _stageRecordingWav(
    Uint8List bytes, {
    required String laneName,
  }) async {
    final base = laneName.replaceAll(RegExp(r'[\\/:*?"<>|.\s]+'), '_');
    final safeBase = base.isEmpty ? 'REC' : base;
    final taken = {
      for (final asset in mediaAssets) fileNameOfPath(asset.path),
    };
    try {
      for (var take = 1; take < 10000; take += 1) {
        final name = '${safeBase}_T${take.toString().padLeft(2, '0')}.wav';
        final poolPath = normalizedMediaPath(
          '${_staging.directoryPath}/$name',
        );
        if (taken.contains(name) || _staging.holdsAnyCopyOf(poolPath)) {
          continue;
        }
        final carry = (poolPath: poolPath, token: mintMediaCarry(poolPath));
        await _staging.stageCarriedBytesInMemory(carry, bytes);
        // We just wrote these, so we know what they hash to without
        // reading anything back.
        rememberMediaFingerprint(poolPath, bytes);
        return carry;
      }
      return null;
    } on Object {
      return null; // Full disk, permissions: the take reports, not crashes.
    }
  }

  // 🪦**TWO SHELF VERBS STOOD HERE AND BOTH WERE BOOKKEEPING FOR A FOLDER
  // THAT NO LONGER EXISTS.** `releaseShelfTakesToProject` ran at the first
  // save and `forgetShelfTakes` at an open, and by the end each one only
  // cleared the two fields above — the set of paths this session had
  // written to the shelf and the folder it had pinned. ⛔The LAW they
  // carried is not gone, it stopped needing a keeper: 「nothing moves」.
  // A take was once renamed out of the shelf into the project's `Media/`
  // folder, which made that folder the only copy of a performance — delete
  // it and the recording was gone with no original to relink to. The
  // project carries its own audio, so the save absorbs the take from where
  // it already sits, and「where it sits」is now the staging store, which
  // owns the lifetime for every carried asset alike.

  /// The nine lines the session's own `dispose` used to spend on this
  /// section, in the same order. The cue-beep directory goes with them: it is
  /// a temp folder this object made, and nothing else knows where it is.
  void dispose() {
    _voiceRecorder?.dispose();
    isVoiceRecording.dispose();
    voiceRecordingNotice.dispose();
    voiceRecordPreviewLane.dispose();
    voiceRecordClipLit.dispose();
    _testToneTimer?.cancel();
    _voiceRecordCountInTimer?.cancel();
    _deleteCueBeepDirectory();
    detachInputMeter();
  }
}

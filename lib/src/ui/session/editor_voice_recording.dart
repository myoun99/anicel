import 'dart:async' show Timer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../services/import/media_identity_reader.dart';
import '../../services/persistence/app_documents.dart'
    show appRecordingsDirectory;
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../models/timeline_frame_range.dart';
import '../playback/audio_device_transport.dart';
import '../playback/audio_sync_settings.dart';
import '../playback/canvas_playback_controller.dart';
import '../text/app_strings.dart';
import '../../services/command.dart';
import '../../services/commands/cut_command_coordinator.dart';
import '../../services/commands/update_layer_timeline_command.dart';
import '../../native/qa_audio_native.dart' show QaAudioNative;
import '../../native/qa_audio_device.dart'
    show
        QaAudioDevice,
        audioInputDeviceIndexByName,
        audioOutputDeviceIndexByName;
import '../../services/audio/audio_mixer_reference.dart'
    show AudioMixClip, AudioMixSource;
import '../playback/audio_input_monitor.dart';
import '../playback/audio_playback_schedule.dart' show ScheduledAudioClip;
import '../../services/audio/conform_wav_codec.dart' show encodeConformWav;
import '../../services/commands/update_media_assets_command.dart';
import '../../models/se_take_placement.dart';
import '../../services/audio/audio_peaks_extractor.dart' show AudioPeaks;
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
/// What it needs from the session it NAMES: the nineteen members in the
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
    required LayerId? Function() activeLayerId,
    required Layer? Function(LayerId) trackSeGlobalLayerById,
    required FrameId Function(LayerId) mintFrameId,
    required List<MediaAsset> Function() mediaAssets,
    required void Function(String, Uint8List) rememberMediaFingerprint,
    required ValueNotifier<TimelineFrameRangeSelection?> Function()
    frameRangeSelection,
    required String? Function() projectFilePath,
    required void Function() notify,
  }) : _playback = playback,
       _audioDeviceTransport = audioDeviceTransport,
       _audioConformStore = audioConformStore,
       _audioSyncSettings = audioSyncSettings,
       _repositoryRef = repository,
       _cutCommandCoordinatorRef = cutCommandCoordinator,
       _uiStrings = uiStrings,
       _projectFrameRate = projectFrameRate,
       _activeCutGlobalStartFrame = activeCutGlobalStartFrame,
       _editingGlobalFrame = editingGlobalFrame,
       _gapParkedGlobalFrame = gapParkedGlobalFrame,
       _activeLayerId = activeLayerId,
       _trackSeGlobalLayerById = trackSeGlobalLayerById,
       _mintFrameIdRef = mintFrameId,
       _mediaAssets = mediaAssets,
       _rememberMediaFingerprint = rememberMediaFingerprint,
       _frameRangeSelection = frameRangeSelection,
       _projectFilePathRef = projectFilePath,
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

  final LayerId? Function() _activeLayerId;
  LayerId? get activeLayerId => _activeLayerId();

  final Layer? Function(LayerId) _trackSeGlobalLayerById;
  Layer? trackSeGlobalLayerById(LayerId layerId) =>
      _trackSeGlobalLayerById(layerId);

  final FrameId Function(LayerId) _mintFrameIdRef;
  FrameId _mintFrameId(LayerId layerId) => _mintFrameIdRef(layerId);

  final List<MediaAsset> Function() _mediaAssets;
  List<MediaAsset> get mediaAssets => _mediaAssets();

  final void Function(String, Uint8List) _rememberMediaFingerprint;
  void rememberMediaFingerprint(String poolPath, Uint8List bytes) =>
      _rememberMediaFingerprint(poolPath, bytes);

  final ValueNotifier<TimelineFrameRangeSelection?> Function()
  _frameRangeSelection;
  ValueNotifier<TimelineFrameRangeSelection?> get frameRangeSelection =>
      _frameRangeSelection();

  final String? Function() _projectFilePathRef;
  String? get _projectFilePath => _projectFilePathRef();

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

  /// REC1-B2: the take shelf for a never-saved project — pinned at the
  /// first take so a mid-session settings change never scatters one
  /// session's takes across folders.
  String? _voiceRecordShelfDirectory;

  /// Every WAV this session recorded onto the shelf. The FIRST save
  /// adopts the still-referenced ones into `Media/`; undone takes stay
  /// on the shelf, findable.
  final Set<String> _voiceRecordShelfPaths = <String>{};

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
      final toneSamples = sampleRate * 9 ~/ 100;
      final ramp = sampleRate ~/ 200;
      final samples = Float32List(toneSamples);
      for (var sample = 0; sample < toneSamples; sample += 1) {
        var value = 0.5 * math.sin(2 * math.pi * 1000 * sample / sampleRate);
        if (sample < ramp) {
          value *= sample / ramp;
        } else if (sample >= toneSamples - ramp) {
          value *= (toneSamples - sample) / ramp;
        }
        samples[sample] = value;
      }
      final wav = encodeConformWav(
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
  void _playCountInBeeps(int seconds) {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return;
    }
    final device = QaAudioDevice.instance;
    if (device == null || playback.isActive || device.isOpen) {
      return;
    }
    final index = audioOutputDeviceIndexByName(
      device,
      audioSyncSettings.value.outputDeviceName,
    );
    var opened = device.open(
      sampleRate: 48000,
      channels: 2,
      deviceIndex: index,
    );
    if (opened == 0 && index >= 0) {
      opened = device.open(sampleRate: 48000, channels: 2);
    }
    if (opened == 0) {
      return;
    }
    final sampleRate = device.sampleRate;
    final channels = device.channels;
    final toneSamples = sampleRate * 9 ~/ 100;
    final ramp = sampleRate ~/ 200;
    final pcm = Float32List(toneSamples * channels);
    for (var sample = 0; sample < toneSamples; sample += 1) {
      var value = 0.4 * math.sin(2 * math.pi * 1000 * sample / sampleRate);
      if (sample < ramp) {
        value *= sample / ramp;
      } else if (sample >= toneSamples - ramp) {
        value *= (toneSamples - sample) / ramp;
      }
      for (var channel = 0; channel < channels; channel += 1) {
        pcm[sample * channels + channel] = value;
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
          : audioInputDeviceIndexByName(
              device,
              audioSyncSettings.value.inputDeviceName,
            ),
    );
  }

  /// A short tone through the CHOSEN output device — the settings
  /// dialog's "is this speaker alive" button. Refuses while a transport
  /// run holds the device (it is busy making real sound). Returns false
  /// when nothing could open; the button stays quiet then.
  bool playOutputTestTone() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return false;
    }
    final device = QaAudioDevice.instance;
    if (device == null || playback.isActive || device.isOpen) {
      return false;
    }
    final index = audioOutputDeviceIndexByName(
      device,
      audioSyncSettings.value.outputDeviceName,
    );
    var opened = device.open(
      sampleRate: 48000,
      channels: 2,
      deviceIndex: index,
    );
    if (opened == 0 && index >= 0) {
      opened = device.open(sampleRate: 48000, channels: 2);
    }
    if (opened == 0) {
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
  final List<double> _voiceRecordPeakBuckets = [];
  double _voiceRecordBucketMax = 0;
  int _voiceRecordBucketFill = 0;
  int _voiceRecordSamplesPerBucket = 0;
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
    final perBucket = _voiceRecordSamplesPerBucket;
    if (channels <= 0 || perBucket <= 0) {
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
      switch (mode) {
        case VoiceInputChannelMode.monoMix:
          var sum = 0.0;
          for (var channel = 0; channel < channels; channel += 1) {
            sum += interleaved[base + channel];
          }
          final mixed = sum / channels;
          magnitude = mixed < 0 ? -mixed : mixed;
        case VoiceInputChannelMode.left:
          final value = interleaved[base];
          magnitude = value < 0 ? -value : value;
        case VoiceInputChannelMode.right:
          final value = interleaved[base + 1];
          magnitude = value < 0 ? -value : value;
        case VoiceInputChannelMode.device:
          magnitude = 0;
          for (var channel = 0; channel < channels; channel += 1) {
            final value = interleaved[base + channel];
            final size = value < 0 ? -value : value;
            if (size > magnitude) {
              magnitude = size;
            }
          }
      }
      final scaled = magnitude * factor;
      if (scaled >= voiceClipThreshold && !voiceRecordClipLit.value) {
        voiceRecordClipLit.value = true;
      }
      final clamped = scaled > 1.0 ? 1.0 : scaled;
      if (clamped > _voiceRecordBucketMax) {
        _voiceRecordBucketMax = clamped;
      }
      _voiceRecordBucketFill += 1;
      if (_voiceRecordBucketFill == perBucket) {
        _voiceRecordPeakBuckets.add(_voiceRecordBucketMax);
        _voiceRecordBucketMax = 0;
        _voiceRecordBucketFill = 0;
      }
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
    _voiceRecordLivePeaks = AudioPeaks(
      bucketsPerSecond: 40,
      peaks: Float32List.fromList(_voiceRecordPeakBuckets),
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

  void _clearVoiceRecordPreview() {
    playback.globalFrameIndexListenable.removeListener(_syncVoiceRecordPreview);
    _voiceRecordLivePeaks = null;
    _voiceRecordPeakBuckets.clear();
    _voiceRecordBucketMax = 0;
    _voiceRecordBucketFill = 0;
    _voiceRecordSamplesPerBucket = 0;
    _voiceRecordLastPreviewLength = 0;
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
  /// The take lands on the ACTIVE track SE lane; any other active layer
  /// refuses (the armed-track contract — nothing records without an
  /// armed destination). A range selection on that lane is the PUNCH
  /// window: capture begins when playback enters it and ends at its far
  /// edge, however long the transport keeps rolling.
  VoiceRecordStartResult startVoiceRecording() {
    if (isVoiceRecording.value) {
      return VoiceRecordStartResult.alreadyRecording;
    }
    final laneId = activeLayerId;
    final lane = laneId == null ? null : trackSeGlobalLayerById(laneId);
    if (lane == null || laneId == null) {
      return VoiceRecordStartResult.needsSeLane;
    }
    // The settings meter yields the microphone to the take (REC1-D2).
    _inputMonitor?.stop();
    final device = Platform.environment['FLUTTER_TEST'] == 'true'
        ? null
        : QaAudioDevice.instance;
    final recorder =
        debugVoiceRecorderFactory?.call() ?? AudioRecorder(device: device);
    final deviceIndex = device == null
        ? -1
        : audioInputDeviceIndexByName(
            device,
            audioSyncSettings.value.inputDeviceName,
          );
    // Suppression captures at RNNoise's native 48 kHz; the take conforms
    // ONCE on placement, like any imported rate.
    final wantDenoise = audioSyncSettings.value.denoiseVoice;
    final rate = recorder.start(
      sampleRate: wantDenoise
          ? voiceDenoiseCaptureRate
          : audioConformStore.projectSampleRate,
      deviceIndex: deviceIndex,
    );
    if (rate == 0) {
      return VoiceRecordStartResult.deviceFailed;
    }

    // Where the roll starts, on the track-global axis: the playing (or
    // paused) position when the transport is active, otherwise the
    // editing playhead — gap parking included (a gap is a place on the
    // track; the lane is cut-independent).
    final rollStart = playback.isActive
        ? (_playbackTrackGlobalFrame() ??
              (gapParkedGlobalFrame ?? editingGlobalFrame))
        : (gapParkedGlobalFrame ?? editingGlobalFrame);

    // The punch window: a range selection on the armed lane, mapped from
    // its cut-local display axis onto the track axis.
    var anchor = rollStart;
    int? punchEnd;
    final selection = frameRangeSelection.value;
    if (selection != null && selection.coversLayer(laneId)) {
      final offset = activeCutGlobalStartFrame;
      final punchStart = selection.startIndex + offset;
      final windowEnd = selection.endIndexExclusive + offset;
      if (rollStart < windowEnd) {
        anchor = math.max(rollStart, punchStart);
        punchEnd = windowEnd;
      }
    }

    _voiceRecorder = recorder;
    _voiceRecordLaneId = laneId;
    _voiceRecordAnchorFrame = anchor;
    _voiceRecordPunchEndFrame = punchEnd;
    // The performer speaks against what they HEAR, which runs the output
    // latency behind the mix clock — that much comes off the take's head
    // (the DAW recording-compensation rule) — plus the run-up between
    // the roll start and the punch-in.
    _voiceRecordHeadTrimSamples =
        audioDeviceTransport.report.reportedLatencySamples +
        projectFrameRate.frameToSample(anchor - rollStart, rate);
    isVoiceRecording.value = true;
    // Capture-chain snapshot (REC1-D): gain and channel fold ride the
    // whole take; the clip light re-arms per take.
    _voiceRecordGainDb = AudioSyncSettings.clampMicGainDb(
      audioSyncSettings.value.micGainDb,
    );
    _voiceRecordChannelMode = audioSyncSettings.value.inputChannelMode;
    // A device that refused 48 kHz records clean — RNNoise has no other
    // rate, and a silently resampled pass would be a different promise.
    _voiceRecordDenoise = wantDenoise && rate == voiceDenoiseCaptureRate;
    _lastVoiceTakeClipped = false;
    voiceRecordClipLit.value = false;
    // Live preview (REC1-C): the recorder's chunk tap feeds the growing
    // waveform; the playback frame channel drives the block preview at
    // frame boundaries — no session notify per tick (R12-B).
    _voiceRecordSamplesPerBucket = rate ~/ 40;
    recorder.onChunk = debugIngestVoiceRecordChunk;
    playback.globalFrameIndexListenable.addListener(_syncVoiceRecordPreview);
    final wasRolling = playback.isActive && playback.isPlaying;
    // Stopped-⏺ count-in (REC1-E): the mic is ALREADY rolling, the
    // transport waits — the wait rides the head trim, so the take still
    // anchors where the roll will start. A punch has its own run-up; the
    // count-in stays out of its way.
    final countInSeconds = !wasRolling && punchEnd == null
        ? AudioSyncSettings.clampCountInSeconds(
            audioSyncSettings.value.countInSeconds,
          )
        : 0;
    if (wasRolling) {
      _voiceRecordStartedRoll = false;
    } else if (countInSeconds > 0) {
      _voiceRecordStartedRoll = true;
      _voiceRecordHeadTrimSamples += countInSeconds * rate;
      if (audioSyncSettings.value.cueBeeps) {
        _playCountInBeeps(countInSeconds);
      }
      _voiceRecordCountInTimer?.cancel();
      _voiceRecordCountInTimer = Timer(Duration(seconds: countInSeconds), () {
        if (!isVoiceRecording.value) {
          return;
        }
        // 🚨T28: with pause gone, "active" already means rolling — there is
        // nothing to resume, only a transport to start when there is none.
        if (!playback.isPlaying) {
          playback.play(
            scope: PlaybackScope.allCuts,
            startGlobalFrame: rollStart,
          );
        }
      });
    } else {
      _voiceRecordStartedRoll = true;
      if (!playback.isPlaying) {
        playback.play(
          scope: PlaybackScope.allCuts,
          startGlobalFrame: rollStart,
        );
      }
    }
    // ADR cue clips + the streamer window (REC1-E): only with a punch
    // AHEAD of the roll — the approach is what they count down.
    _voiceRecordCueClips = const [];
    _voiceRecordStreamerWindow = null;
    if (punchEnd != null && anchor > rollStart) {
      final axisShift =
          playback.isActive && playback.scope == PlaybackScope.activeCut
          ? activeCutGlobalStartFrame
          : 0;
      final secondFrames = projectFrameRate.framesCoveringExactSeconds(1, 1);
      if (secondFrames > 0) {
        final settingsNow = audioSyncSettings.value;
        if (settingsNow.cueBeeps) {
          final beepPath = _ensureCueBeepWav();
          if (beepPath != null) {
            final beepFrames = math.max(
              1,
              projectFrameRate.framesCoveringExactSeconds(9, 100),
            );
            _voiceRecordCueClips = [
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
    }
    _syncVoiceRecordPreview();
    notifyListeners(); // Armed-lane mute + cue clips join the schedules.
    return VoiceRecordStartResult.started;
  }

  /// Stops the take and lands it on the armed lane: WAV to disk, pool
  /// entry, and the lane's tape-style swap (trims, erasures, the new
  /// block and its link) — ONE undo for the whole landing.
  ///
  /// A roll this take started stops with it (record = play + capture,
  /// both directions). Returns null on clean success, otherwise a
  /// message for the user — including the case where the take was PLACED
  /// but the capture ring dropped frames (a damaged take must say so).
  String? stopVoiceRecordingAndPlace() {
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
    final placed = placeVoiceRecording(
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
  bool placeVoiceRecording(
    AudioRecording recording, {
    required LayerId? laneId,
    required int anchorFrame,
    int? punchEndFrame,
    int headTrimSamples = 0,
    int gainDb = 0,
    VoiceInputChannelMode channelMode = VoiceInputChannelMode.device,
    bool denoise = false,
  }) {
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
    final wav = encodeConformWav(
      samples: samples,
      channels: channels,
      sampleRate: recording.sampleRate,
    );
    final path = _writeRecordingWav(wav, laneName: lane.name);
    if (path == null) {
      return false;
    }

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
    // Conform first (same order as an import), then the ONE undo step:
    // pool entry + the lane's whole swap.
    audioConformStore.invalidate(path);
    audioConformStore.warmPaths([path]);
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
                  carried: true,
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
    notifyListeners();
    return true;
  }

  /// Writes a take's WAV under the project's `Media/` folder (the visible
  /// Recordings shelf when the project was never saved — REC1-B2, no
  /// hidden OS temp) and returns its path, or null when even that failed.
  ///
  /// Named `<lane>_T<n>.wav` (REC1-B): the recording-session convention —
  /// the pool line alone says whose take it is and which pass. On the
  /// shelf the walk continues past earlier sessions' takes.
  String? _writeRecordingWav(Uint8List bytes, {required String laneName}) {
    final base = laneName.replaceAll(RegExp(r'[\\/:*?"<>|.\s]+'), '_');
    final safeBase = base.isEmpty ? 'REC' : base;
    try {
      // ALWAYS the shelf, saved project or not. A take used to land in
      // the project's `Media/` folder once it had one, which made that
      // folder the only copy of a performance — and the project carries
      // its own audio now, so writing it there buys nothing and costs the
      // one place a recording could be found again.
      //
      // The shelf is also somewhere a person can look: on desktop it is a
      // folder they chose, and losing a take to a `.assets` directory
      // nobody opens is not a thing to keep.
      final directory = (_voiceRecordShelfDirectory ??=
          appRecordingsDirectory());
      Directory(directory).createSync(recursive: true);
      for (var take = 1; take < 10000; take += 1) {
        final file = File(
          '$directory/${safeBase}_T${take.toString().padLeft(2, '0')}.wav',
        );
        if (!file.existsSync()) {
          file.writeAsBytesSync(bytes);
          _voiceRecordShelfPaths.add(file.path);
          // We just wrote these, so we know what they hash to without
          // reading anything back.
          rememberMediaFingerprint(file.path, bytes);
          return file.path;
        }
      }
      return null;
    } on Object {
      return null; // Full disk, permissions: the take reports, not crashes.
    }
  }

  /// The FIRST save hands this session's shelf takes over to the project:
  /// the shelf list clears, and nothing on disk moves.
  ///
  /// 🔑 Nothing MOVING is the whole point, and it is why this is no longer
  /// the "adopt" it used to be. A take was once renamed out of the shelf
  /// into the project's `Media/` folder, which made that folder the only
  /// copy of a performance — delete it and the recording is gone, with no
  /// original anywhere to relink to. The project carries its own audio
  /// now, so the save absorbs the take from wherever it sits and the shelf
  /// copy simply stays a file. Closing without saving must not cost a
  /// recording that cannot be made again.
  ///
  /// The list still clears because these takes belong to the project now;
  /// the shelf is for the ones a session made before it had a home.
  /// A REPLACED project's shelf takes are no longer this session's to hand
  /// over — they stay on the shelf, findable. Unconditional where
  /// [releaseShelfTakesToProject] is guarded, because the project underneath
  /// just changed rather than acquired a file.
  void forgetShelfTakes() {
    _voiceRecordShelfPaths.clear();
    _voiceRecordShelfDirectory = null;
  }

  void releaseShelfTakesToProject() {
    if (_projectFilePath != null || _voiceRecordShelfPaths.isEmpty) {
      return;
    }
    _voiceRecordShelfPaths.clear();
    _voiceRecordShelfDirectory = null;
  }

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

/// The device transport (audio program wiring): playback on the audio
/// master clock.
///
/// This is where the program's central promise is cashed. The native
/// device counts samples handed to the hardware; this class uploads the
/// mix schedule, arms the transport alongside the playback controller,
/// and answers "what frame is being heard" — which the controller shows
/// instead of its wall clock. Cumulative drift is structurally zero
/// because there is no second clock to drift against.
///
/// Standing down is graceful BY DESIGN, never silent in effect: no native
/// binary, a device that refuses to open, or PCM not resident yet (a
/// conform still building, a device-rate conversion in flight) leaves
/// [carryingPlayback] false — the platform-player fallback carries the
/// run, the wall clock drives the picture, and the missing pieces are
/// kicked so the NEXT run rides the device. Silence is never an
/// acceptable outcome for audio.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart';
import '../../services/playback/playback_frame_mapping.dart';
import '../audio/audio_conform_store.dart';
import 'audio_playback_schedule.dart';
import 'audio_sync_settings.dart';
import 'audio_windowed_upload.dart';
import 'canvas_playback_controller.dart';

class AudioDeviceTransport {
  AudioDeviceTransport({
    required this.controller,
    required this.resolveFrameRate,
    required this.resolveProject,
    required this.conformStore,
    QaAudioDevice? Function()? resolveDevice,
    int Function(int sampleRate)? resolveUserOffsetSamples,
    this.resolveSoloedLayerIds,
    this.resolveRecordingMutedLayerIds,
    this.resolveCueClips,
    this.resolveOutputDeviceName,
  }) : _resolveDevice = resolveDevice ?? (() => QaAudioDevice.instance),
       _resolveUserOffsetSamples = resolveUserOffsetSamples ?? ((_) => 0);

  /// The session's solo set (monitoring state, AUDIO-PRO R1).
  final Set<LayerId> Function()? resolveSoloedLayerIds;

  /// The armed lane while a take rolls (REC1-B) — muted on top of the
  /// layers' own flags, never written into them.
  final Set<LayerId> Function()? resolveRecordingMutedLayerIds;

  /// ADR cue clips joining the schedule while a take approaches its
  /// punch-in (REC1-E); empty otherwise.
  final List<ScheduledAudioClip> Function()? resolveCueClips;

  /// The chosen output device by name (AUDIO-PRO R4); null = system
  /// default. Read at each activation — a changed setting reopens the
  /// device on the NEXT run (mid-run output hopping is not a thing any
  /// pro tool does either).
  final String? Function()? resolveOutputDeviceName;

  /// What the open device was opened as, to detect a setting change.
  String? _openedDeviceName;

  final CanvasPlaybackController controller;
  final ProjectFrameRate Function() resolveFrameRate;
  final Project? Function() resolveProject;
  final AudioConformStore conformStore;
  final QaAudioDevice? Function() _resolveDevice;

  /// The user's A/V offset in samples at the given device rate — the
  /// residual no device report can account for (screen pipeline,
  /// Bluetooth, an AV receiver).
  final int Function(int sampleRate) _resolveUserOffsetSamples;

  bool _attached = false;
  bool _wasActive = false;
  bool _wasPlaying = false;

  /// Whether THIS activation runs on the device. Decided once at
  /// activation (like the schedule itself); the platform-player sync
  /// consults it before building players.
  bool _carrying = false;

  QaAudioDevice? _device;
  ProjectFrameRate _rate = ProjectFrameRate.fps24;
  int _deviceRate = 0;
  int _totalFrames = 0;

  /// Streaming window geometry (AUDIO-PRO R6). A window trails a little
  /// (loop wraps and small seeks land just behind the playhead) and leads
  /// a lot (the next advance must upload long before the mix reads past
  /// the edge). ~5.5 MB per streaming stereo clip resident at a time.
  static const int _windowBackSeconds = 2;
  static const int _windowAheadSeconds = 30;

  /// The activation's mix schedule, kept so window advances can rebuild
  /// sources without re-deriving the timeline.
  AudioMixSchedule? _mix;
  bool _hasStreaming = false;
  int _windowCenterSample = 0;
  bool _windowAdvanceInFlight = false;

  /// The frame the current arm started at: the clock clamp while the
  /// device's own latency drains (pressing play at frame 100 must not
  /// flash frame 99), reset by the loop re-arm to 0.
  int _armFrame = 0;

  /// A loop run armed mid-timeline plays its first pass without the C
  /// loop flag (the C wraps to where play STARTED; the picture loops to
  /// 0) and re-arms from 0 — every later seam is the C's sample-exact
  /// wrap.
  bool _needsLoopRearm = false;

  bool get carryingPlayback => _carrying;

  /// Listener order matters: attach BEFORE the platform-player sync so
  /// [carryingPlayback] is decided by the time the fallback asks.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    controller.addListener(_onControllerChanged);
    controller.onSeeked = _onSeeked;
    controller.resolveAudioClock = clockStatus;
  }

  void dispose() {
    if (_attached) {
      controller.removeListener(_onControllerChanged);
      if (controller.onSeeked == _onSeeked) {
        controller.onSeeked = null;
      }
      if (controller.resolveAudioClock == clockStatus) {
        controller.resolveAudioClock = null;
      }
      _attached = false;
    }
    _device?.stop();
    _device?.close();
    _device = null;
  }

  /// Rebuilds and re-uploads the schedule MID-RUN (AUDIO-PRO R3): an
  /// audio edit during playback is heard within one mixed block. No-op
  /// unless this transport carries the run. A clip whose PCM is not
  /// resident yet (a just-imported file mid-conform) keeps the OLD
  /// schedule playing rather than dropping sound — the conform was
  /// kicked, and the next refresh or activation picks it up.
  void refreshSchedule() {
    final device = _device;
    if (!_carrying || device == null) {
      return;
    }
    final schedule = buildAudioPlaybackSchedule(
      playlist: controller.playlist,
      project: resolveProject(),
      rate: _rate,
      durationSecondsFor: conformStore.durationSecondsFor,
      soloedLayerIds: resolveSoloedLayerIds?.call(),
      mutedLayerIds: resolveRecordingMutedLayerIds?.call(),
      extraClips: resolveCueClips?.call(),
    );
    final mix = audioMixScheduleFrom(
      schedule: schedule,
      rate: _rate,
      sampleRate: _deviceRate,
    );
    _mix = mix;
    _uploadWindowedSchedule(mix, device.positionSamples);
  }

  /// Uploads [mix] with streaming windows around [centerSample] (the shared
  /// [uploadWindowedSchedule] — the scrubber streams on the same geometry).
  /// False uploads nothing, so any old schedule keeps playing.
  bool _uploadWindowedSchedule(AudioMixSchedule mix, int centerSample) {
    final hasStreaming = uploadWindowedSchedule(
      device: _device,
      mix: mix,
      conformStore: conformStore,
      deviceRate: _deviceRate,
      centerSample: centerSample,
      backSeconds: _windowBackSeconds,
      aheadSeconds: _windowAheadSeconds,
    );
    if (hasStreaming == null) {
      return false;
    }
    _hasStreaming = hasStreaming;
    _windowCenterSample = centerSample;
    return true;
  }

  /// The level meter's read (AUDIO-PRO R2): the last mixed block's
  /// pre-clip bus peak per side. Zeros while the device does not carry
  /// playback — a silent meter, not a frozen one.
  ({double left, double right}) get meterPeaks {
    final device = _device;
    if (!_carrying || device == null || !device.isOpen) {
      return (left: 0, right: 0);
    }
    return (left: device.peakFor(0), right: device.peakFor(1));
  }

  /// The inspector's evidence line (audio program 2D): everything the
  /// sync correction is built from, readable off a real machine.
  AudioSyncReport get report {
    final device = _device;
    final rate = resolveFrameRate();
    if (device == null || !device.isOpen) {
      return const AudioSyncReport(deviceOpen: false);
    }
    return AudioSyncReport(
      deviceOpen: true,
      deviceSampleRate: device.sampleRate,
      deviceChannels: device.channels,
      reportedLatencySamples: device.latencySamples,
      userOffsetSamples: _resolveUserOffsetSamples(device.sampleRate),
      positionSamples: device.positionSamples,
      frameRateNumerator: rate.numerator,
      frameRateDenominator: rate.denominator,
    );
  }

  void _onControllerChanged() {
    final active = controller.isActive;
    final playing = controller.isPlaying;
    if (active && !_wasActive) {
      _activate();
      if (playing && _carrying) {
        _arm(controller.globalFrameIndexListenable.value ?? 0);
      }
    } else if (!active && _wasActive) {
      _carrying = false;
      _device?.stop();
    } else if (active && _carrying) {
      if (playing && !_wasPlaying) {
        // Resume re-arms at the controller's frame — a paused seek moved
        // it, and play() from stopped is exactly a seek-and-go.
        _arm(controller.globalFrameIndexListenable.value ?? 0);
      } else if (!playing && _wasPlaying) {
        // Pause = stop the transport where it stands. The position is
        // irrelevant afterwards; resume re-arms from the controller.
        _device?.stop();
      }
    }
    _wasActive = active;
    _wasPlaying = playing;
  }

  /// Decides whether this run rides the device, and uploads the schedule
  /// if so. Every stand-down kicks the missing piece so the next run
  /// converges onto the device path.
  void _activate() {
    _carrying = false;
    final device = _resolveDevice();
    if (device == null) {
      return;
    }
    _rate = resolveFrameRate();
    final schedule = buildAudioPlaybackSchedule(
      playlist: controller.playlist,
      project: resolveProject(),
      rate: _rate,
      durationSecondsFor: conformStore.durationSecondsFor,
      soloedLayerIds: resolveSoloedLayerIds?.call(),
      mutedLayerIds: resolveRecordingMutedLayerIds?.call(),
      extraClips: resolveCueClips?.call(),
    );

    // The device opens lazily and stays open across runs (opening tears
    // down and rebuilds an OS audio graph — not a per-play cost). A
    // changed output-device setting reopens here, at the run boundary.
    final desiredName = resolveOutputDeviceName?.call();
    if (device.isOpen && _openedDeviceName != desiredName) {
      device.stop();
      device.close();
    }
    if (!device.isOpen) {
      final index = audioDeviceIndexByName(
        device,
        capture: false,
        name: desiredName,
      );
      var opened = device.open(
        sampleRate: conformStore.projectSampleRate,
        deviceIndex: index,
      );
      if (opened <= 0 && index >= 0) {
        // The named device failed to open (unplugged mid-enumeration):
        // fall back to the system default deliberately, never to silence.
        opened = device.open(sampleRate: conformStore.projectSampleRate);
      }
      if (opened <= 0) {
        return;
      }
      _openedDeviceName = desiredName;
    }
    _device = device;
    _deviceRate = device.sampleRate;

    // Every scheduled file must be resident at the DEVICE rate — or
    // streamable from its conform (AUDIO-PRO R6) — before the device can
    // promise anything. A missing one stands this run down and is kicked
    // (conform or rate conversion) for the next.
    final mix = audioMixScheduleFrom(
      schedule: schedule,
      rate: _rate,
      sampleRate: _deviceRate,
    );
    device.stop();
    _mix = mix;
    if (!_uploadWindowedSchedule(
      mix,
      _rate.frameToSample(
        controller.globalFrameIndexListenable.value ?? 0,
        _deviceRate,
      ),
    )) {
      return;
    }
    _totalFrames = _playbackTotalFrames();
    _carrying = true;
  }

  /// The playback run's total frames — the playlist plus, for all-cuts
  /// runs, the movie's trailing gap (the controller's own total, same
  /// arithmetic).
  int _playbackTotalFrames() {
    var total = playlistTotalFrames(controller.playlist);
    if (total > 0 && controller.scope == PlaybackScope.allCuts) {
      total += resolveProject()?.trailingFrames ?? 0;
    }
    return total;
  }

  void _arm(int frame) {
    final device = _device;
    if (device == null) {
      return;
    }
    final loop = controller.loopMode == PlaybackLoopMode.loop;
    _armFrame = frame;
    _needsLoopRearm = loop && frame != 0;
    final startSample = _rate.frameToSample(frame, _deviceRate);
    // Streaming windows re-center on the arm point (a seek can land
    // anywhere in a long clip) — one synchronous read at a press, the
    // same budget as opening any file on click.
    final mix = _mix;
    if (_hasStreaming && mix != null) {
      _uploadWindowedSchedule(mix, startSample);
    }
    device.play(
      startSample: startSample,
      stopSample: _rate.frameToSample(_totalFrames, _deviceRate),
      looping: loop && frame == 0,
    );
  }

  void _onSeeked(int globalFrame) {
    if (!_carrying) {
      return;
    }
    if (controller.isPlaying) {
      // A live seek re-arms rather than seeks: the arm owns the loop
      // bookkeeping (seeking mid-first-pass changes where the wrap must
      // land) and a play() from a seek is indistinguishable from one.
      _arm(globalFrame);
    }
    // Paused: nothing to move — resume re-arms from the controller frame.
  }

  /// What the controller shows instead of its wall clock; null while the
  /// device does not carry this run.
  AudioClockStatus? clockStatus() {
    final device = _device;
    if (!_carrying || device == null) {
      return null;
    }
    if (!controller.isPlaying) {
      return null;
    }
    if (!device.isPlaying) {
      if (_needsLoopRearm) {
        // First pass of a mid-timeline loop ran out: every later pass is
        // the full timeline, so the C's wrap target (its start) is now
        // the right one. One poll interval of seam, once.
        _needsLoopRearm = false;
        _armFrame = 0;
        device.play(
          startSample: 0,
          stopSample: _rate.frameToSample(_totalFrames, _deviceRate),
          looping: true,
        );
        return const AudioClockStatus(globalFrame: 0);
      }
      return AudioClockStatus(globalFrame: _totalFrames - 1, ended: true);
    }
    // Streaming windows advance from here (AUDIO-PRO R6): this poll runs
    // every displayed frame, and the halfway trigger leaves ~15 s of
    // margin before the mix could read past a window's edge. The read
    // runs off this frame's stack; in-flight guard so polls cannot stack
    // reads.
    if (_hasStreaming && !_windowAdvanceInFlight) {
      final position = device.positionSamples;
      final recenter =
          position > _windowCenterSample +
              (_windowAheadSeconds * _deviceRate) ~/ 2 ||
          position < _windowCenterSample - _windowBackSeconds * _deviceRate;
      if (recenter) {
        _windowAdvanceInFlight = true;
        unawaited(Future(() {
          try {
            final mix = _mix;
            if (_carrying && mix != null && _device != null) {
              _uploadWindowedSchedule(mix, _device!.positionSamples);
            }
          } finally {
            _windowAdvanceInFlight = false;
          }
        }));
      }
    }
    final heard = math.max(
      0,
      device.positionSamples -
          device.latencySamples +
          _resolveUserOffsetSamples(_deviceRate),
    );
    var frame = _rate.sampleToFrame(heard, _deviceRate);
    if (frame < _armFrame) {
      // The device's own latency is still draining the first samples of
      // this arm; showing an EARLIER frame than the one play was pressed
      // on would read as a jump back. (After a loop wrap the arm frame is
      // 0, so this clamp never fights the wrap.)
      frame = _armFrame;
    }
    return AudioClockStatus(globalFrame: frame);
  }
}

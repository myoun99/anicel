/// Audio scrub (audio program 2D, final piece): dragging the playhead
/// plays each frame's slice of the mix.
///
/// This is the anime-tool scrub — TVPaint, and every NLE's JKL shuttle at
/// its slowest, do the same thing: as the playhead crosses a frame, that
/// frame's worth of sound plays. Because the mixer builds a mix rather
/// than starting clips, a scrub tick is just `play(frame, frame+1)` on
/// the same transport playback uses — one arm per crossed frame, samples
/// exact, no media pipeline opened per tick.
///
/// The schedule uploads ONCE per gesture (the first frame the scrub
/// actually crosses), from the same scheduler playback uses, over the
/// active-cut playlist — so scrubbed sound and played sound can never
/// disagree. Standing down is silent and per-gesture: no device, no
/// resident PCM, or a cut with no sound leaves the scrub visual-only,
/// exactly as it was before this class existed.
library;

import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart';
import '../audio/audio_conform_store.dart';
import 'audio_playback_schedule.dart';
import 'audio_windowed_upload.dart';
import 'canvas_playback_controller.dart';

class AudioScrubber {
  AudioScrubber({
    required this.controller,
    required this.resolveFrameRate,
    required this.resolveProject,
    required this.conformStore,
    QaAudioDevice? Function()? resolveDevice,
    this.resolveSoloedLayerIds,
    this.resolveRecordingMutedLayerIds,
    this.resolveOutputDeviceName,
  }) : _resolveDevice = resolveDevice ?? (() => QaAudioDevice.instance);

  /// The session's solo set — a scrub monitors exactly what playback
  /// would.
  final Set<LayerId> Function()? resolveSoloedLayerIds;

  /// The armed lane while a take rolls (REC1-B) — a scrub mid-take
  /// monitors what playback does: everything but the armed lane.
  final Set<LayerId> Function()? resolveRecordingMutedLayerIds;

  /// The chosen output device (AUDIO-PRO R4) — a scrub plays through the
  /// same speaker playback would. Only consulted when the device is not
  /// already open (the transport owns reopen-on-change).
  final String? Function()? resolveOutputDeviceName;

  final CanvasPlaybackController controller;
  final ProjectFrameRate Function() resolveFrameRate;
  final Project? Function() resolveProject;
  final AudioConformStore conformStore;
  final QaAudioDevice? Function() _resolveDevice;

  bool _armed = false;
  bool _stoodDown = false;
  QaAudioDevice? _device;
  ProjectFrameRate _rate = ProjectFrameRate.fps24;
  int _deviceRate = 0;

  /// Streaming state (AUDIO-PRO R6): the gesture's mix is kept so the
  /// window can re-center when a long drag leaves it.
  AudioMixSchedule? _mix;
  bool _hasStreaming = false;
  int _windowCenterSample = 0;

  /// Whether the current gesture is playing sound (test surface).
  bool get isArmed => _armed;

  /// A scrub move that CHANGED the frame: plays that frame's slice.
  ///
  /// [localFrame] is the active cut's local frame — the same coordinate
  /// the editing scrub rides.
  void onScrubFrame(int localFrame) {
    if (controller.isActive) {
      // Playback (even paused) owns the device and its schedule.
      return;
    }
    if (!_armed && !_stoodDown) {
      _prepare(localFrame);
    }
    if (!_armed) {
      return;
    }
    final startSample = _rate.frameToSample(localFrame, _deviceRate);
    // A drag that left the streaming window re-centers it — a small
    // synchronous read, same budget as the gesture's first upload.
    final mix = _mix;
    if (_hasStreaming &&
        mix != null &&
        (startSample - _windowCenterSample).abs() >
            (_windowAheadSeconds * _deviceRate) ~/ 2) {
      _uploadWindowedSchedule(mix, startSample);
    }
    _device!.play(
      startSample: startSample,
      stopSample: _rate.frameToSample(localFrame + 1, _deviceRate),
    );
  }

  /// The gesture's release: silence, and a fresh decision next gesture.
  void onScrubEnd() {
    if (_armed) {
      _device?.stop();
    }
    _armed = false;
    _stoodDown = false;
  }

  /// The transport's window lead, reused so scrub and playback stream on
  /// the same geometry (AUDIO-PRO R6).
  static const int _windowAheadSeconds = 30;
  static const int _windowBackSeconds = 2;

  /// One decision per gesture, mirroring the transport's activation: the
  /// schedule from the shared scheduler, PCM from the conform store, all
  /// resident — or streamable from its conform — or nothing. A stand-down
  /// kicks the missing pieces so the NEXT gesture (or the next play) has
  /// them.
  void _prepare(int localFrame) {
    _stoodDown = true;
    _rate = resolveFrameRate();
    final schedule = buildAudioPlaybackSchedule(
      playlist: controller.playlistForScope(PlaybackScope.activeCut),
      project: resolveProject(),
      rate: _rate,
      durationSecondsFor: conformStore.durationSecondsFor,
      soloedLayerIds: resolveSoloedLayerIds?.call(),
      mutedLayerIds: resolveRecordingMutedLayerIds?.call(),
    );
    if (schedule.isEmpty) {
      // A silent cut: do not even open a device for it.
      return;
    }
    final device = _resolveDevice();
    if (device == null) {
      return;
    }
    if (!device.isOpen) {
      final index = audioDeviceIndexByName(
        device,
        capture: false,
        name: resolveOutputDeviceName?.call(),
      );
      var opened = device.open(
        sampleRate: conformStore.projectSampleRate,
        deviceIndex: index,
      );
      if (opened <= 0 && index >= 0) {
        opened = device.open(sampleRate: conformStore.projectSampleRate);
      }
      if (opened <= 0) {
        return;
      }
    }
    _deviceRate = device.sampleRate;
    final mix = audioMixScheduleFrom(
      schedule: schedule,
      rate: _rate,
      sampleRate: _deviceRate,
    );
    device.stop();
    _device = device;
    _mix = mix;
    if (!_uploadWindowedSchedule(
      mix,
      _rate.frameToSample(localFrame, _deviceRate),
    )) {
      _device = null;
      return; // kicked by the lookups; this gesture stays visual
    }
    _armed = true;
    _stoodDown = false;
  }

  /// Uploads [mix] with streaming windows around [centerSample] — the shared
  /// [uploadWindowedSchedule], so scrubbed and played streaming can never
  /// disagree. False uploads nothing.
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

  void dispose() {
    if (_armed) {
      _device?.stop();
      _armed = false;
    }
  }
}

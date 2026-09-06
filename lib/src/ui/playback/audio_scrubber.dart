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
  /// window can re-center when a long drag leaves it. The same object the
  /// transport owns, which is what keeps scrub and playback on one
  /// geometry.
  final AudioStreamingWindow _window = AudioStreamingWindow();

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
    if (_window.hasStreaming &&
        (startSample - _window.centerSample).abs() >
            (AudioStreamingWindow.aheadSeconds * _deviceRate) ~/ 2) {
      _uploadWindow(startSample);
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
    if (!device.isOpen &&
        !openAudioOutput(
          device,
          sampleRate: conformStore.projectSampleRate,
          preferredName: resolveOutputDeviceName?.call(),
        )) {
      return;
    }
    _deviceRate = device.sampleRate;
    final mix = audioMixScheduleFrom(
      schedule: schedule,
      rate: _rate,
      sampleRate: _deviceRate,
    );
    device.stop();
    _device = device;
    _window.mix = mix;
    if (!_uploadWindow(_rate.frameToSample(localFrame, _deviceRate))) {
      _device = null;
      return; // kicked by the lookups; this gesture stays visual
    }
    _armed = true;
    _stoodDown = false;
  }

  /// Moves the streaming window to [centerSample]. False uploads nothing.
  bool _uploadWindow(int centerSample) => _window.upload(
    device: _device,
    conformStore: conformStore,
    deviceRate: _deviceRate,
    centerSample: centerSample,
  );

  void dispose() {
    if (_armed) {
      _device?.stop();
      _armed = false;
    }
  }
}

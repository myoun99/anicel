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
/// The schedule uploads ONCE per window a gesture stands in — the cut, or
/// the track where it stands in no cut (F-341) — at the first frame the
/// scrub crosses there, from the same scheduler playback uses, over the
/// same window a run there plays — so scrubbed sound and played sound can
/// never disagree. Standing down is silent and per window: no device, no
/// resident PCM, or a stretch with no sound leaves the scrub visual-only
/// there, exactly as it was before this class existed.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

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
    this.resolvePlaybackLevel,
  }) : _resolveDevice = resolveDevice ?? (() => QaAudioDevice.instance);

  /// How loud the canvas plays (I-85) — a scrub is heard at the level a
  /// run is; null plays at full.
  final double Function()? resolvePlaybackLevel;

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

  /// What the decision was made for — the cut the scrub stands in, or the
  /// track where it stands in no cut: the mix is that window's, so a scrub
  /// that crosses into another cut (I-57 ②), or out of every cut onto the
  /// track (F-341), decides again for what it reached. ↩️One decision a
  /// gesture was enough while a scrub left the active cut alone, and after
  /// a crossing it played the cut it left at the frame numbers of the cut
  /// it reached.
  ({PlaybackScope scope, Object? on})? _decidedFor;
  QaAudioDevice? _device;
  ProjectFrameRate _rate = ProjectFrameRate.fps24;
  int _deviceRate = 0;

  /// The run the latest slice put on the device — all a release silences
  /// ([QaAudioDevice.stopRun]).
  int _run = 0;

  /// Streaming state (AUDIO-PRO R6): the gesture's mix is kept so the
  /// window can re-center when a drag leaves it. The same object the
  /// transport owns — one upload, and one law for when a window moves —
  /// over the reach a scrub needs ([AudioStreamingWindow.scrubbing]).
  final AudioStreamingWindow _window = AudioStreamingWindow(
    reach: AudioStreamingWindow.scrubbing,
  );

  /// Whether the current gesture is playing sound (test surface).
  bool get isArmed => _armed;

  /// The window the gesture streams out of (test surface).
  @visibleForTesting
  AudioStreamingWindow get debugWindow => _window;

  /// A scrub move that CHANGED the frame: plays that frame's slice.
  ///
  /// [localFrame] is the active cut's local frame — the same coordinate
  /// the editing scrub rides.
  void onScrubFrame(int localFrame) => _scrub(
    (scope: PlaybackScope.activeCut, on: controller.resolveActiveCutId()),
    localFrame,
  );

  /// A scrub move that CHANGED the frame where no cut is — a gap, the
  /// movie's trailing frames, a track with no cut (F-341): plays
  /// [trackFrame]'s slice of the track's own sound.
  void onScrubTrackFrame(int trackFrame) => _scrub(
    (scope: PlaybackScope.allCuts, on: controller.resolveActiveTrackId()),
    trackFrame,
  );

  void _scrub(({PlaybackScope scope, Object? on}) where, int frame) {
    if (controller.isActive) {
      // Playback (even paused) owns the device and its schedule.
      return;
    }
    if (where != _decidedFor) {
      _letGo();
      _decidedFor = where;
    }
    if (!_armed && !_stoodDown) {
      _prepare(where.scope, frame);
    }
    if (!_armed) {
      return;
    }
    final startSample = _rate.frameToSample(frame, _deviceRate);
    // A drag the window wants centred on again — by its own law — moves it
    // there before the slice plays: a small read where the drag stands.
    _window.cover(
      startSample,
      device: _device,
      conformStore: conformStore,
      deviceRate: _deviceRate,
    );
    _run = _device!.play(
      startSample: startSample,
      stopSample: _rate.frameToSample(frame + 1, _deviceRate),
    );
  }

  /// The gesture's release: silence, and a fresh decision next gesture.
  void onScrubEnd() {
    _letGo();
    _decidedFor = null;
  }

  /// Silence, and the decision undone.
  void _letGo() {
    if (_armed) {
      _device?.stopRun(_run);
    }
    _armed = false;
    _stoodDown = false;
  }

  /// One decision per window, mirroring the transport's activation: the
  /// schedule from the shared scheduler, PCM from the conform store, all
  /// resident — or streamable from its conform — or nothing. A stand-down
  /// kicks the missing pieces so the NEXT gesture (or the next play) has
  /// them.
  void _prepare(PlaybackScope scope, int frame) {
    _stoodDown = true;
    _rate = resolveFrameRate();
    final schedule = buildAudioPlaybackSchedule(
      window: controller.windowForScope(scope),
      project: resolveProject(),
      rate: _rate,
      durationSecondsFor: conformStore.durationSecondsFor,
      soloedLayerIds: resolveSoloedLayerIds?.call(),
      mutedLayerIds: resolveRecordingMutedLayerIds?.call(),
      level: resolvePlaybackLevel?.call() ?? 1,
    );
    if (schedule.isEmpty) {
      // A silent stretch: do not even open a device for it.
      return;
    }
    final device = _resolveDevice();
    if (device == null) {
      return;
    }
    // Not armed — its sound on its way, kicked by the lookups or an open,
    // or no output at all — this gesture stays visual: a drag is the hand's,
    // and a scrub does not wait for its sound as a run does.
    if (armAudioOutput(
      device: device,
      conformStore: conformStore,
      window: _window,
      schedule: schedule,
      rate: _rate,
      centerFrame: frame,
      preferredDeviceName: resolveOutputDeviceName?.call(),
    ) case OutputArmed(:final deviceRate)) {
      _deviceRate = deviceRate;
      _device = device;
      _armed = true;
      _stoodDown = false;
    }
  }

  void dispose() => _letGo();
}

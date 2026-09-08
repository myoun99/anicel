import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart';
import '../audio/audio_conform_store.dart';
import '../playback/audio_playback_schedule.dart';
import '../playback/audio_windowed_upload.dart';

/// The media viewer's sound: ONE conformed file, played out of the same
/// device the timeline plays out of.
///
/// 🚨★★★**THE VIEWER THINKS IN SECONDS, AND THAT IS THE ONLY DIFFERENCE.**
/// A timeline clip is placed on a frame axis; a viewer plays a whole file
/// from wherever the playhead stands. So the schedule here is one clip at
/// zero, and the frame rate handed to the shared arming is ONE FRAME PER
/// SECOND — which makes a frame a second exactly, with no conversion to get
/// wrong. The waveform does the same thing for the same reason
/// (`WaveformPainter.perSecond`).
///
/// ⛔Nothing here opens a device, builds a mix or uploads a window of its
/// own: [armAudioOutput] owns that order, and the transport and the
/// scrubber ride it too. This class is only the part that is the viewer's —
/// which file, from what second, and where the device has got to.
///
/// Standing down is silent and total, exactly as the other two paths stand
/// down: no binary, no device, or a conform not resident yet leaves
/// [isCarrying] false and the viewer plays its pictures without sound. ⛔A
/// viewer that refused to play because there was no audio device would be
/// worse than a silent one.
class ViewerSound {
  ViewerSound({
    required this.conformStore,
    QaAudioDevice? Function()? resolveDevice,
    this.resolveOutputDeviceName,
  }) : _resolveDevice = resolveDevice ?? audioOutputUnlessTesting;

  final AudioConformStore conformStore;
  final QaAudioDevice? Function() _resolveDevice;

  /// The chosen output (AUDIO-PRO R4). ⚠️Only consulted when the device is
  /// not already open — the playback transport owns reopen-on-change, and
  /// the note on [armAudioOutput] says why that stays in one place.
  final String? Function()? resolveOutputDeviceName;

  /// One frame per second, so every number below is a second.
  static const ProjectFrameRate _perSecond = ProjectFrameRate.integer(1);

  final AudioStreamingWindow _window = AudioStreamingWindow();
  QaAudioDevice? _device;
  int _deviceRate = 0;

  /// Where the uploaded file ENDS, in device samples — kept so [resume] can
  /// hand the transport the same span [play] gave it.
  int _endSample = 0;

  /// Whether sound is actually coming out for the current file.
  bool get isCarrying => _device != null;

  /// Starts [sourcePath] at [fromSeconds]; false stands down silently.
  ///
  /// ⚠️It asks the conform store rather than a decoder: the sound of a
  /// media asset — a `.wav` on its own or the track inside a movie — is
  /// conformed at import, and a compressed codec cannot promise to decode
  /// inside a real-time buffer. That is the same reason playback conforms
  /// (`record-what-gets-conformed`), and it is why this needs no engine of
  /// its own.
  bool play(String sourcePath, {double fromSeconds = 0}) {
    stop();
    final seconds = conformStore.durationSecondsFor(sourcePath);
    if (seconds == null || seconds <= 0) {
      // Not conformed yet — the lookup KICKED it, so the next press has it.
      return false;
    }
    final device = _resolveDevice();
    if (device == null) {
      return false;
    }
    final armed = armAudioOutput(
      device: device,
      conformStore: conformStore,
      window: _window,
      schedule: [
        ScheduledAudioClip(
          filePath: sourcePath,
          startFrame: 0,
          endFrameExclusive: seconds.ceil(),
        ),
      ],
      rate: _perSecond,
      centerFrame: fromSeconds.floor(),
      preferredDeviceName: resolveOutputDeviceName?.call(),
    );
    if (armed == null || !armed.uploaded) {
      return false;
    }
    _device = device;
    _deviceRate = armed.deviceRate;
    _endSample = (seconds * _deviceRate).round();
    // ⚠️The START is in SAMPLES, not in whole seconds: the window only has
    // to be centred near the playhead, but the sound has to begin exactly
    // where the picture says it does.
    resume(fromSeconds);
    return true;
  }

  /// Stops the sound WITHOUT letting go of what was uploaded, so [resume]
  /// can pick it up again.
  ///
  /// 🚨★★★**THE WHOLE TRANSPORT WAITS — sound included.** 유저 2026-08-31
  /// gave this viewer its law: 「유지하지말고 **로드할때까지 멈춰있어야지**」,
  /// because a held picture cannot be told apart from a hold the animator
  /// DREW. Once the picture has sound beside it that law has to reach the
  /// sound too, and the alternative proves it: letting the sound run on
  /// while the picture parks means the picture must later CATCH UP by
  /// dropping frames — which is exactly what the user rejected for this
  /// surface. So a movie whose buffer runs dry stutters in both, together,
  /// and comes back in sync.
  ///
  /// ⚠️This is a DERIVED decision, not one that was asked for: it applies
  /// the law this surface already has to the thing that was added to it.
  /// Written here so the next reader can disagree with the derivation
  /// rather than guess at the intent.
  void hold() => _device?.stop();

  /// Starts (or picks back up) at [fromSeconds] on the schedule already
  /// uploaded. ⛔Not a seek: the streaming window is where [play] centred
  /// it, and a jump far from there would read past its edge.
  void resume(double fromSeconds) => _device?.play(
    startSample: (fromSeconds * _deviceRate).round(),
    stopSample: _endSample,
  );

  /// Where the device has got to, or null while nothing is carrying.
  ///
  /// 🚨★★★**THIS IS THE CLOCK.** The device counts samples handed to the
  /// hardware, so a picture that follows this cannot drift from the sound
  /// — the same promise the timeline's device transport is built on.
  double? get positionSeconds {
    final device = _device;
    if (device == null || _deviceRate <= 0) {
      return null;
    }
    return device.positionSamples / _deviceRate;
  }

  /// Whether the device reached the end of the file it was given.
  ///
  /// ⛔It compares POSITIONS rather than asking `isPlaying`. A sound being
  /// [hold]d is also not playing, and a viewer that read that as 「끝났다」
  /// would stop the whole run every time a buffer ran dry.
  bool get ended {
    final device = _device;
    return device != null &&
        _endSample > 0 &&
        device.positionSamples >= _endSample;
  }

  /// Silence, and nothing held. ⚠️Idempotent — the viewer stops on every
  /// path out (a new file, a closed tab, the actuation gate).
  void stop() {
    _device?.stop();
    _device = null;
    _deviceRate = 0;
    _endSample = 0;
  }
}

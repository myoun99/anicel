import 'dart:math' as math;

import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart';
import '../../services/playback/first_look_start.dart';
import '../../services/playback/heard_on_the_device.dart';
import '../audio/audio_conform_store.dart';
import '../editor_session_manager.dart';
import '../playback/audio_playback_schedule.dart';
import '../playback/audio_windowed_upload.dart';

/// How loud a surface plays its sound: the level its bar stands at, and
/// whether the speaker beside it is off — the transport's sound cell
/// (`TransportSound`), held by whoever outlives the surface.
///
/// Muting keeps the level: the bar stands where it was, and a press of the
/// speaker comes back to it.
class ViewerLoudness {
  const ViewerLoudness({this.level = 1, this.muted = false});

  /// 0..1.
  final double level;
  final bool muted;

  /// What the sound is started at ([ViewerSound.play]).
  double get gain => muted ? 0 : level;

  @override
  bool operator ==(Object other) =>
      other is ViewerLoudness && other.level == level && other.muted == muted;

  @override
  int get hashCode => Object.hash(level, muted);
}

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
/// A sound on its way — a conform not resident yet, an output being opened
/// ([OutputComing]) — is waited for: the run stands where it was put and
/// asks again ([prepare]) until it comes (`MediaRun`, playback-waits-for-
/// its-sound: 「소리가 준비될 때까지 기다린다」). No binary, no device, or a
/// file that will never be ready leaves [isCarrying] false and the viewer
/// plays its pictures without sound ([OutputRefused]). ⛔A viewer that
/// refused to play because there was no audio device would be worse than a
/// silent one. ↩️A conform not resident yet stood down as silently: the
/// movie played without its sound, and a sound alone did not play at all
/// until the next press.
class ViewerSound {
  ViewerSound({
    required this.conformStore,
    QaAudioDevice? Function()? resolveDevice,
    this.resolveOutputDeviceName,
    int Function(int sampleRate)? resolveUserOffsetSamples,
  }) : _resolveDevice = resolveDevice ?? audioOutputUnlessTesting,
       resolveUserOffsetSamples = resolveUserOffsetSamples ?? ((_) => 0);

  /// [session]'s sound — every surface that plays a file's sound in it:
  /// the media viewer, and the import window's preview.
  ///
  /// ⚠️The SAME conform store the timeline plays out of, so a file conformed
  /// for one is conformed for the other and nothing is decoded twice; the
  /// output the settings chose; and the user's A/V correction the canvas
  /// reads ([PlaybackRig.userOffsetSamples]).
  factory ViewerSound.ofSession(EditorSessionManager session) => ViewerSound(
    conformStore: session.audioConformStore,
    resolveOutputDeviceName: () =>
        session.appSettings.audioSyncSettings.value.outputDeviceName,
    resolveUserOffsetSamples: session.playbackRig.userOffsetSamples,
  );

  final AudioConformStore conformStore;
  final QaAudioDevice? Function() _resolveDevice;

  /// The user's own A/V correction, in samples at a device's rate.
  final int Function(int sampleRate) resolveUserOffsetSamples;

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

  /// Where a listener is on the run ([heardAt]) — the canvas's own reading
  /// of the same device.
  final HeardOnTheDevice _heard = HeardOnTheDevice();

  /// When a started sound's device starts: on the run's first look
  /// ([FirstLookStart]) — the canvas's own law.
  final FirstLookStart _start = FirstLookStart();

  /// The sample the latest start put the device on: what is heard stands
  /// there while the device's latency drains, so a playhead never steps
  /// back at a press.
  int _startSample = 0;

  /// Whether sound is actually coming out for the current file.
  bool get isCarrying => _device != null;

  /// Starts [sourcePath] at [fromSeconds], as loud as [gain]
  /// ([ViewerLoudness.gain]) — once it is armed there ([prepare]), which
  /// it says.
  ///
  /// ⚠️It asks the conform store rather than a decoder: the sound of a
  /// media asset — a `.wav` on its own or the track inside a movie — is
  /// conformed at import, and a compressed codec cannot promise to decode
  /// inside a real-time buffer. That is the same reason playback conforms
  /// (`record-what-gets-conformed`), and it is why this needs no engine of
  /// its own.
  ///
  /// ⚠️The gain is the one clip's, mixed into what is uploaded: the device
  /// has no fader of its own, so a sound already going hears a new level by
  /// being started again where it stands (`MediaRun.soundCell`).
  OutputArm play(String sourcePath, {double fromSeconds = 0, double gain = 1}) {
    final armed = prepare(sourcePath, fromSeconds: fromSeconds, gain: gain);
    if (armed is OutputArmed) {
      // ⚠️The START is in SAMPLES, not in whole seconds: the window only has
      // to be centred near the playhead, but the sound has to begin exactly
      // where the picture says it does.
      resume(fromSeconds);
    }
    return armed;
  }

  /// Arms [sourcePath] around [fromSeconds], as loud as [gain], without
  /// starting it: [OutputArmed] and [isCarrying] once it is on the device,
  /// [OutputComing] while its conform or its output is on its way — what a
  /// run that waits for its sound asks again until it has come (`MediaRun`)
  /// — and [OutputRefused] where it never will be: no output, or a file
  /// nothing will make ready.
  OutputArm prepare(
    String sourcePath, {
    required double fromSeconds,
    required double gain,
  }) {
    stop();
    final seconds = conformStore.durationSecondsFor(sourcePath);
    if (seconds == null || seconds <= 0) {
      // Not conformed: the lookup KICKED it, and it lands — or it never will.
      return conformStore.isLanding(sourcePath, conformStore.projectSampleRate)
          ? const OutputComing()
          : const OutputRefused();
    }
    final device = _resolveDevice();
    if (device == null) {
      return const OutputRefused();
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
          gain: gain,
        ),
      ],
      rate: _perSecond,
      centerFrame: fromSeconds.floor(),
      preferredDeviceName: resolveOutputDeviceName?.call(),
    );
    if (armed case OutputArmed(:final deviceRate, :final cannotPlay)) {
      if (cannotPlay.isNotEmpty) {
        // The one file the viewer plays is the one left out.
        return const OutputRefused();
      }
      _device = device;
      _deviceRate = deviceRate;
      _endSample = (seconds * _deviceRate).round();
    }
    return armed;
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
  void hold() => _silence();

  /// Starts (or picks back up) at [fromSeconds] on the schedule already
  /// uploaded — on the run's first look ([FirstLookStart]: [keepStreaming],
  /// [heardAt]) — with the streaming window centred there first where it
  /// does not hold it ([AudioStreamingWindow.cover]): a run behind its clock
  /// puts its sound back as far as the app was late (`MediaRun`).
  /// ↩️It was 「not a seek」, picking up only where the window already was.
  void resume(double fromSeconds) {
    final device = _device;
    if (device == null) {
      return;
    }
    final startSample = _startSample = (fromSeconds * _deviceRate).round();
    _window.cover(
      startSample,
      device: device,
      conformStore: conformStore,
      deviceRate: _deviceRate,
    );
    _start.arm(() {
      device.play(startSample: startSample, stopSample: _endSample);
      _heard.arm(deviceRate: _deviceRate, carriesFor: device.latencySamples);
    });
  }

  /// Silence — and a sound started but not looked at yet never starts.
  void _silence() {
    _start.disarm();
    _device?.stop();
  }

  /// Moves the streaming window along with the sound — asked every tick of
  /// a run. A file past two minutes streams from disk, and a window left
  /// where [play] centred it runs dry half a minute in
  /// ([AudioStreamingWindow.followPlayback], the timeline's own rule).
  void keepStreaming() {
    final device = _device;
    if (device == null) {
      return;
    }
    // A look of the run: a sound started since the last one starts now.
    _start.look();
    _window.followPlayback(
      positionSamples: device.positionSamples,
      deviceRate: _deviceRate,
      conformStore: conformStore,
      current: () {
        final carrying = _device;
        return carrying == null
            ? null
            : (device: carrying, deviceRate: _deviceRate);
      },
    );
  }

  /// Where the sound is HEARD at [frameTime] — the frame the reading is
  /// for — in seconds, and whether the last of the file has been heard; null
  /// while nothing is carrying.
  ///
  /// 🚨★★★**THIS IS THE CLOCK — the canvas's, in its code**
  /// ([HeardOnTheDevice], viewer-plays-by-the-one-playback-law ④-b): the
  /// line through what the device was handed, at the frame's own time, less
  /// what the device still holds to play, and less the user's own
  /// correction. A picture that follows it cannot drift from the sound, and
  /// stands where the canvas's would. ↩️It read what had been HANDED, the
  /// stair, as the tick ran: a picture ahead of what was heard by the
  /// device's latency, and a correction set in the settings that never
  /// reached it.
  ///
  /// ⛔The end is told by POSITION rather than by asking `isPlaying`: a
  /// sound being [hold]d is not playing either, and a viewer that read that
  /// as 「끝났다」 would stop the whole run every time a buffer ran dry.
  ({double seconds, bool ended})? heardAt({Duration? frameTime}) {
    final device = _device;
    if (device == null || _deviceRate <= 0) {
      return null;
    }
    // A look of the run: a sound started since the last one starts now.
    _start.look();
    final heard = math.max(
      _startSample,
      _heard.heard(
        device.readClock(),
        frameTime: frameTime,
        latencySamples: device.latencySamples,
        userOffsetSamples: resolveUserOffsetSamples(_deviceRate),
      ),
    );
    return (
      seconds: heard / _deviceRate,
      ended: _endSample > 0 && heard >= _endSample,
    );
  }

  /// How far the device has been handed the file, in seconds — where a
  /// held sound picks up ([hold], [resume]), so what it played before the
  /// hold is not played again; null while nothing is carrying. ⛔Not the
  /// clock: what is heard trails it by the device's latency ([heardAt]).
  double? get handedSeconds {
    final device = _device;
    if (device == null || _deviceRate <= 0) {
      return null;
    }
    return device.positionSamples / _deviceRate;
  }

  /// Silence, and nothing held. ⚠️Idempotent — the viewer stops on every
  /// path out (a new file, a closed tab, the actuation gate).
  void stop() {
    _silence();
    _device = null;
    _deviceRate = 0;
    _endSample = 0;
  }
}

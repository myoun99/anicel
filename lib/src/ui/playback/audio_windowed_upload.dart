import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart';
import '../audio/audio_conform_store.dart';
import 'audio_playback_schedule.dart';

/// THE STREAMING WINDOW a device is currently playing out of: the mix it
/// was built from, whether anything in it streams, and where the window is
/// centred — plus the one upload that moves it.
///
/// The transport and the scrubber both own one of these, so streamed
/// playback and streamed scrubbing drive the device on identical geometry.
/// Each used to keep the three fields and a byte-identical private upload
/// of its own around one shared free function.
class AudioStreamingWindow {
  /// Streaming window geometry (AUDIO-PRO R6). A window trails a little
  /// (loop wraps and small seeks land just behind the playhead) and leads
  /// a lot (the next advance must upload long before the mix reads past
  /// the edge). ~5.5 MB per streaming stereo clip resident at a time.
  ///
  /// Reused so scrub and playback stream on the same geometry
  /// (AUDIO-PRO R6) — the numbers were spelled four times across this
  /// layer before they had a home.
  static const int backSeconds = 2;
  static const int aheadSeconds = 30;

  /// The mix this window streams, kept so a window advance can rebuild
  /// sources without re-deriving the timeline. Set it before [upload].
  AudioMixSchedule? mix;

  /// Whether anything in the uploaded schedule streams (rather than being
  /// fully resident) — what makes a window advance necessary at all.
  bool hasStreaming = false;

  /// Where the last successful upload centred the window.
  int centerSample = 0;

  /// Uploads [mix] to [device] with streaming windows around
  /// [centerSample], and moves this window there on success.
  ///
  /// 🚨FALSE means NOTHING WAS UPLOADED — no mix held, no device, an
  /// incomplete upload, or a device that rejected the schedule — so the
  /// caller LEAVES ANY OLD SCHEDULE PLAYING rather than cutting the sound
  /// to silence. Nothing about this window moves in that case either.
  bool upload({
    required QaAudioDevice? device,
    required AudioConformStore conformStore,
    required int deviceRate,
    required int centerSample,
  }) {
    final held = mix;
    if (held == null || device == null) {
      return false;
    }
    final prepared = windowedMixUpload(
      mix: held,
      conformStore: conformStore,
      deviceRate: deviceRate,
      centerSample: centerSample,
      backSeconds: backSeconds,
      aheadSeconds: aheadSeconds,
    );
    if (prepared == null) {
      return false;
    }
    if (!device.setSchedule(clips: prepared.clips, sources: prepared.sources)) {
      return false;
    }
    hasStreaming = prepared.hasStreaming;
    this.centerSample = centerSample;
    return true;
  }
}

/// Opens the output if it is closed, converts [schedule] to samples and
/// uploads it centred on [centerFrame].
///
/// 🚨★★★**ONE ORDER, BECAUSE GETTING IT WRONG IS SILENT.** Open, read the
/// device's OWN rate, build the mix at that rate, stop, upload. Every step
/// depends on the one before it — the mix cannot be built before the rate
/// is known, and the rate is not known until the device is open, because
/// WASAPI shared mode hands back whatever rate it likes however nicely 48k
/// was asked for. A caller that reorders any of it gets sound at the wrong
/// speed, or none, and nothing throws.
///
/// ⚠️Written down once when the media viewer became the THIRD caller
/// (2026-09-08). The transport and the scrubber had spelled the same five
/// steps out separately; the rule is that a third makes it a law
/// ([[no-copy-to-share]] · the rule of three).
///
/// ⛔What is NOT here, deliberately: WHEN to reopen for a changed output
/// device. The transport owns that at the run boundary and the scrubber
/// explicitly defers to it, so a reopen decided in here would be a second
/// answer. A caller that wants one closes the device first and calls this.
///
/// Null = the output would not open, and nothing was touched. `uploaded:
/// false` = it is open at [deviceRate] but the sources are not resident
/// yet — the lookups have KICKED their conforms, so the caller stands this
/// attempt down and the next one converges.
({int deviceRate, bool uploaded})? armAudioOutput({
  required QaAudioDevice device,
  required AudioConformStore conformStore,
  required AudioStreamingWindow window,
  required List<ScheduledAudioClip> schedule,
  required ProjectFrameRate rate,
  required int centerFrame,
  required String? preferredDeviceName,
}) {
  if (!device.isOpen &&
      !openAudioOutput(
        device,
        sampleRate: conformStore.projectSampleRate,
        preferredName: preferredDeviceName,
      )) {
    return null;
  }
  final deviceRate = device.sampleRate;
  window.mix = audioMixScheduleFrom(
    schedule: schedule,
    rate: rate,
    sampleRate: deviceRate,
  );
  device.stop();
  return (
    deviceRate: deviceRate,
    uploaded: window.upload(
      device: device,
      conformStore: conformStore,
      deviceRate: deviceRate,
      centerSample: rate.frameToSample(centerFrame, deviceRate),
    ),
  );
}

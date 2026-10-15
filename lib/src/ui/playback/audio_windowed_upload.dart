import 'dart:async';
import 'dart:ffi' show Float, FloatPointer, Pointer;
import 'dart:typed_data';

import '../../core/on_a_worker.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart';
import '../../services/audio/audio_mixer_reference.dart'
    show AudioMixSource;
import '../audio/audio_conform_store.dart';
import 'audio_playback_schedule.dart';

/// How far a streaming window reaches behind where it is centred and ahead
/// of it ([AudioStreamingWindow.reach]).
typedef StreamWindowReach = ({int backSeconds, int aheadSeconds});

/// THE STREAMING WINDOW a device is currently playing out of: the mix it
/// was built from, whether anything in it streams, and where the window is
/// centred — plus the one upload that moves it.
///
/// The transport, the media viewer's sound and the scrubber each own one of
/// these: one upload, and one law for when a window moves
/// ([wantsRecentreAt]) — each over the reach its motion needs ([playing],
/// [scrubbing]). Each used to keep the three fields and a byte-identical
/// private upload of its own around one shared free function.
class AudioStreamingWindow {
  AudioStreamingWindow({
    this.readWindows = readStreamWindowsOnAWorker,
    this.reach = playing,
  });

  /// How an advance reads its windows: on a worker, into buffers of the
  /// device's own ([readStreamWindowsOnAWorker]) — null when one did not
  /// land whole. A test holds the read to put something in meanwhile.
  final Future<List<AudioMixSource>?> Function(
    List<StreamWindowRead> reads,
    QaAudioDevice device,
  )
  readWindows;

  /// A stream that PLAYS (AUDIO-PRO R6). A window trails a little (loop
  /// wraps and small seeks land just behind the playhead) and leads a lot
  /// (the next advance must upload long before the mix reads past the
  /// edge). ~5.5 MB per streaming stereo clip resident at a time.
  ///
  /// The numbers were spelled four times across this layer before they had
  /// a home.
  static const StreamWindowReach playing = (backSeconds: 2, aheadSeconds: 30);

  /// A SCRUB: a frame's slice at a time, backwards as often as forwards,
  /// each window read where the drag stands (scrub-recentres-by-its-own-
  /// rule, 10-15). A second behind and two ahead hold the longest slice — a
  /// whole second, at one frame a second — past a move of half the lead.
  /// ↩️A scrub read the playing reach: 32 seconds at the gesture's first
  /// frame, and again every two seconds of a drag backwards, on the thread
  /// that draws — 🔬15ms a read (30 seconds read in place, the AMMI OP
  /// press, 10-15): two frames lost at 144Hz, each time.
  static const StreamWindowReach scrubbing = (backSeconds: 1, aheadSeconds: 2);

  /// How far this window reaches ([playing], [scrubbing]).
  final StreamWindowReach reach;

  /// The mix this window streams, kept so a window advance can rebuild
  /// sources without re-deriving the timeline. Set it before [upload].
  AudioMixSchedule? mix;

  /// Whether anything in the uploaded schedule streams (rather than being
  /// fully resident) — what makes a window advance necessary at all.
  bool hasStreaming = false;

  /// Where the last successful upload centred the window.
  int centerSample = 0;

  /// Whether a stream that has got to [positionSamples] needs this window
  /// centred on it again: past halfway to its leading edge — for one that
  /// plays, ~15 s before the mix could read past it — or behind its
  /// trailing one.
  ///
  /// 🚨ONE LAW for every surface that streams (scrub-recentres-by-its-own-
  /// rule, 10-15). The scrubber asked its own — more than half the playing
  /// lead away, either way — and a drag 2~15 s behind the centre, outside
  /// the window, played silence.
  bool wantsRecentreAt(int positionSamples, int deviceRate) =>
      hasStreaming &&
      (positionSamples >
              centerSample + (reach.aheadSeconds * deviceRate) ~/ 2 ||
          positionSamples < centerSample - reach.backSeconds * deviceRate);

  /// An advance is out — polls cannot stack disk reads.
  bool _advancing = false;

  /// Uploads so far — what tells an advance that lands late that the
  /// window was put somewhere meanwhile.
  int _uploads = 0;

  /// Moves this window along with a stream that is PLAYING (AUDIO-PRO R6):
  /// asked every tick, it re-centres on the device when [wantsRecentreAt]
  /// says so, off the caller's stack and one advance at a time. [current]
  /// answers when the advance sets out and again when its windows land —
  /// the device still carrying this window and its rate, or null once the
  /// player has stopped, which uploads nothing.
  ///
  /// 🚨ONE rule for every player that streams (import-preview-plays-silent,
  /// 2026-09-29). It lived inside the timeline's transport alone, and the
  /// media viewer's sound never moved its window at all: a file past two
  /// minutes streams from disk, so the viewer went silent half a minute
  /// after play was pressed.
  ///
  /// 🚨THE WINDOWS ARE READ ON A WORKER, straight into buffers of the
  /// device's own ([readWindows]; streaming-advance-reads-on-the-ui-thread,
  /// 10-15): the thread that draws plans the reads, takes over what landed
  /// and swaps the schedule. ↩️It read them itself — 🔬47~50ms every
  /// fifteen seconds of a long sound (18~21 the read, 23~30 the upload's
  /// copies), and the picture skipped a frame.
  void followPlayback({
    required int positionSamples,
    required int deviceRate,
    required AudioConformStore conformStore,
    required ({QaAudioDevice device, int deviceRate})? Function() current,
  }) {
    if (_advancing || !wantsRecentreAt(positionSamples, deviceRate)) {
      return;
    }
    _advancing = true;
    unawaited(
      Future(
        () => _advance(conformStore, current),
      ).whenComplete(() => _advancing = false),
    );
  }

  /// One advance: planned and put here, its windows read by [readWindows]
  /// in between.
  ///
  /// 🚨WINDOWS THAT LAND LATE UPLOAD NOTHING when the player has stopped,
  /// when another mix was put in (they are not its windows), or when the
  /// window was uploaded anew meanwhile — a seek or an edit put it where
  /// the playhead is, and these would take it back.
  ///
  /// 🚨NOR DO WINDOWS THAT DID NOT LAND WHOLE — a file gone from under the
  /// read (a save that moved the conform), or no memory for a buffer. An
  /// advance REPLACES a window that still has fifteen seconds to play, so
  /// the old one plays on and the next tick reads again; a broken window
  /// put in its place would be silence until the advance after. (An arm
  /// has no window at the new place to keep, and puts in what came back.)
  Future<void> _advance(
    AudioConformStore conformStore,
    ({QaAudioDevice device, int deviceRate})? Function() current,
  ) async {
    final now = current();
    final held = mix;
    if (now == null || held == null) {
      return;
    }
    final centerSample = now.device.positionSamples;
    final plan = planWindowedMixUpload(
      mix: held,
      conformStore: conformStore,
      deviceRate: now.deviceRate,
      centerSample: centerSample,
      backSeconds: reach.backSeconds,
      aheadSeconds: reach.aheadSeconds,
    );
    if (plan == null) {
      return;
    }
    final uploads = _uploads;
    final List<AudioMixSource>? windows;
    try {
      windows = await readWindows(plan.reads, now.device);
    } on StateError {
      return;
    }
    final after = current();
    if (windows == null ||
        after == null ||
        !identical(mix, held) ||
        _uploads != uploads) {
      return;
    }
    _put(after.device, plan.withWindows(windows), centerSample);
  }

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
    final prepared = planWindowedMixUpload(
      mix: held,
      conformStore: conformStore,
      deviceRate: deviceRate,
      centerSample: centerSample,
      backSeconds: reach.backSeconds,
      aheadSeconds: reach.aheadSeconds,
    )?.readHere(place: device.newSamples);
    return prepared != null && _put(device, prepared, centerSample);
  }

  /// [prepared] on [device], and this window centred on [centerSample] —
  /// or false, with nothing moved, when the device would not take it.
  bool _put(
    QaAudioDevice device,
    WindowedUpload prepared,
    int centerSample,
  ) {
    if (!device.setSchedule(clips: prepared.clips, sources: prepared.sources)) {
      return false;
    }
    hasStreaming = prepared.hasStreaming;
    this.centerSample = centerSample;
    _uploads += 1;
    return true;
  }
}

/// [reads] read on a worker into buffers of [device]'s own, which this
/// isolate takes over — all an advance asks of the thread that draws
/// (streaming-advance-reads-on-the-ui-thread, 10-15). Null when one did not
/// land whole ([readStreamWindowsInto]).
Future<List<AudioMixSource>?> readStreamWindowsOnAWorker(
  List<StreamWindowRead> reads,
  QaAudioDevice device,
) async {
  final landed = await _readOnAWorker(reads, device.buffers);
  if (landed == null) {
    return null;
  }
  return [
    for (final (index, window) in landed.indexed)
      AudioMixSource(
        samples: window.floats == 0
            ? Float32List(0)
            : device.adoptSamples(window.address, window.floats),
        channels: reads[index].reader.channels,
        sourceStart: window.startSample,
      ),
  ];
}

/// The worker's job, in a function of its own: `Isolate.run` copies the
/// closure's whole context, and this one holds [reads] and two addresses.
Future<List<LandedStreamWindow>?> _readOnAWorker(
  List<StreamWindowRead> reads,
  AudioBuffers buffers,
) => onAWorker(() => readStreamWindowsInto(reads, audioBuffersHere(buffers)));

/// Where a window read on a worker landed: [floats] samples from
/// [startSample] in the buffer at [address] — none, at 0, for a window
/// with nothing in it.
typedef LandedStreamWindow = ({int startSample, int address, int floats});

/// [reads] read into buffers [hands] makes, handed over by address — or,
/// when one does not land whole (its file gone from under it) or its buffer
/// cannot be made (a throw), none at all: every buffer made goes back, for
/// nothing else knows of them.
List<LandedStreamWindow>? readStreamWindowsInto(
  List<StreamWindowRead> reads,
  AudioBufferHands hands,
) {
  final made = <Pointer<Float>>[];
  void releaseAll() {
    for (final buffer in made) {
      hands.release(buffer);
    }
  }

  try {
    final landed = <LandedStreamWindow>[];
    for (final read in reads) {
      final window = _readInto(read, hands, made);
      if (window == null) {
        releaseAll();
        return null;
      }
      landed.add(window);
    }
    return landed;
  } on Object {
    releaseAll();
    rethrow;
  }
}

/// [read] into a buffer [hands] makes for it — kept in [made] until it is
/// handed over — and where it landed; null when it did not land whole.
LandedStreamWindow? _readInto(
  StreamWindowRead read,
  AudioBufferHands hands,
  List<Pointer<Float>> made,
) {
  final reader = read.reader;
  final at = reader.windowAt(read.start, read.count);
  final floats = at.count * reader.channels;
  if (floats == 0) {
    return (startSample: at.start, address: 0, floats: 0);
  }
  final buffer = hands.make(floats);
  made.add(buffer);
  final window = reader.readWindow(
    at.start,
    at.count,
    place: (_) => buffer.asTypedList(floats),
  );
  if (window.samples.length != floats) {
    return null;
  }
  return (startSample: at.start, address: buffer.address, floats: floats);
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

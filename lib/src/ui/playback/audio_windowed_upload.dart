import 'dart:async';
import 'dart:ffi' show Float, FloatPointer, Pointer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

import '../../core/on_a_worker.dart';
import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_device.dart';
import '../../services/audio/audio_mixer_reference.dart'
    show AudioMixSource;
import '../../services/audio/filtered_stream.dart'
    show StreamWindowRead, readStreamedWindow;
import '../audio/audio_conform_store.dart';
import '../audio/sound_cannot_play.dart';
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
///
/// 🚨ONE ROAD FOR EVERY MOVE (long-sound-windows-are-read-on-the-ui-isolate,
/// 관제 2026-11-15): planned here, read on a worker straight into buffers
/// of the device's own ([readWindows]), put here. A move whose windows are
/// on their way answers [OutputComing]; once they land its owner is told
/// ([onLanded]) and asks again, and is answered from them. ↩️An arm, a seek
/// past the window, a mid-run edit, a scrub and the viewer's sound read
/// their windows here — 🔬38ms a long stereo sound's 32 seconds, 74ms two
/// (debug, 11-15) — and only the advance under a playing stream went to a
/// worker.
class AudioStreamingWindow {
  AudioStreamingWindow({
    this.readWindows = readStreamWindowsOnAWorker,
    this.reach = playing,
    this.onLanded,
  });

  /// How a move reads its windows: on a worker, into buffers of the
  /// device's own ([readStreamWindowsOnAWorker]) — null when one did not
  /// land whole. A test holds the read to put something in meanwhile.
  final Future<List<AudioMixSource>?> Function(
    List<StreamWindowRead> reads,
    QaAudioDevice device,
  )
  readWindows;

  /// Told when the windows a move asked for have landed, whole or not:
  /// whoever waits for them asks again ([upload], [cover]).
  final void Function()? onLanded;

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

  /// The windows read last — kept to be put again, by an arm that takes
  /// the device back.
  _ReadWindows? _read;

  /// The windows on their way.
  _AskedWindows? _asked;

  /// Whether a stream that has got to [positionSamples] needs this window
  /// centred on it again: past halfway to either edge — for one that
  /// plays, ~15 s before the mix could read past its leading one.
  ///
  /// 🚨ONE LAW for every surface that streams (scrub-recentres-by-its-own-
  /// rule, 10-15). The scrubber asked its own — more than half the playing
  /// lead away, either way — and a drag 2~15 s behind the centre, outside
  /// the window, played silence.
  ///
  /// ↩️Behind its trailing edge, while a move was read on the thread that
  /// drew: one read on a worker is asked for before what plays leaves the
  /// old window, backwards as forwards, and the old one plays on till it
  /// lands — a scrub dragged back past the edge would play its first slice
  /// there silent (long-sound-windows-are-read-on-the-ui-isolate, 11-15).
  bool wantsRecentreAt(int positionSamples, int deviceRate) =>
      hasStreaming && !_holds(centerSample, positionSamples, deviceRate);

  /// Whether a window centred on [center] holds [position], by the law
  /// [wantsRecentreAt] reads — the window on the device, the windows read
  /// and those on their way alike.
  bool _holds(int center, int position, int deviceRate) =>
      position <= center + (reach.aheadSeconds * deviceRate) ~/ 2 &&
      position >= center - (reach.backSeconds * deviceRate) ~/ 2;

  /// Whether the window on the device plays [position] at all: inside its
  /// edges, as its windows were read ([planWindowedMixUpload]).
  bool _plays(int position, int deviceRate) =>
      hasStreaming &&
      position <= centerSample + reach.aheadSeconds * deviceRate &&
      position >= centerSample - reach.backSeconds * deviceRate;

  /// Before a device plays from [startSample] — a seek's arm, a drag's
  /// slice, a run put back to its picture: whether the device plays it
  /// now, this window centred on it again where it wants to be
  /// ([wantsRecentreAt]). The windows there are read on a worker
  /// ([upload]); till they land, the window as it stands plays what lies
  /// inside its edges, and a start outside them answers false — its owner
  /// is told when they land ([onLanded]). Where that upload fails nothing
  /// moved, and the start plays out of the window as it stands.
  ///
  /// 🚨ONE LAW for every surface that starts a device somewhere — the
  /// transport, the scrubber and the media viewer's sound. ↩️The transport
  /// and the scrubber each asked [wantsRecentreAt] and uploaded themselves,
  /// and the viewer's sound did not: it picked up only where its window
  /// already was, until a run behind its clock had its sound put back
  /// (F-364-every-picture-even-when-late-Q1 a) — as far back as the app
  /// was late.
  bool cover(
    int startSample, {
    required QaAudioDevice? device,
    required AudioConformStore conformStore,
    required int deviceRate,
  }) =>
      !wantsRecentreAt(startSample, deviceRate) ||
      upload(
            device: device,
            conformStore: conformStore,
            deviceRate: deviceRate,
            centerSample: startSample,
          )
          is! OutputComing ||
      _plays(startSample, deviceRate);

  /// Moves this window along with a stream that is PLAYING (AUDIO-PRO R6):
  /// asked every tick, it re-centres on the device when [wantsRecentreAt]
  /// says so, and puts what a move read meanwhile — by [upload], on the
  /// device [current] answers, still carrying this window, at its rate; or
  /// null once the player has stopped, which moves nothing.
  ///
  /// 🚨ONE rule for every player that streams (import-preview-plays-silent,
  /// 2026-09-29). It lived inside the timeline's transport alone, and the
  /// media viewer's sound never moved its window at all: a file past two
  /// minutes streams from disk, so the viewer went silent half a minute
  /// after play was pressed.
  ///
  /// 🚨NOR ARE WINDOWS THAT DID NOT LAND WHOLE put here — a file gone from
  /// under the read (a save that moved the conform), or no memory for a
  /// buffer. An advance REPLACES a window that still has fifteen seconds to
  /// play, so the old one plays on and the next tick reads again; a broken
  /// window put in its place would be silence until the advance after. (An
  /// arm has no window at the new place to keep, and puts in what came
  /// back.)
  void followPlayback({
    required int positionSamples,
    required int deviceRate,
    required AudioConformStore conformStore,
    required ({QaAudioDevice device, int deviceRate})? Function() current,
  }) {
    final read = _read;
    if (read != null && !read.whole && !read.onDevice) {
      _read = null;
    }
    final landed = _read?.onDevice == false;
    if (!landed && !wantsRecentreAt(positionSamples, deviceRate)) {
      return;
    }
    final now = current();
    if (now == null) {
      return;
    }
    upload(
      device: now.device,
      conformStore: conformStore,
      deviceRate: now.deviceRate,
      centerSample: now.device.positionSamples,
    );
  }

  /// Uploads [mix] to [device] with streaming windows around
  /// [centerSample], and moves this window there on success — every clip
  /// but those of the sources nothing will make ready
  /// ([OutputArmed.cannotPlay]).
  ///
  /// A streamed clip's windows are read on a worker ([readWindows]):
  /// [OutputComing] while they are on their way, and the owner is told when
  /// they land ([onLanded]). Asked again where the windows read hold
  /// [centerSample], for the same streamed clips, it puts those and reads
  /// nothing; where the windows on their way hold it, it waits for them.
  ///
  /// 🚨ANYTHING BUT [OutputArmed] means NOTHING WAS UPLOADED — a source
  /// still landing or a window on its way ([OutputComing]), or no mix held,
  /// no device, or a device that rejected the schedule ([OutputRefused]) —
  /// so the caller LEAVES ANY OLD SCHEDULE PLAYING rather than cutting the
  /// sound to silence. Nothing about this window moves in that case either.
  OutputArm upload({
    required QaAudioDevice? device,
    required AudioConformStore conformStore,
    required int deviceRate,
    required int centerSample,
  }) {
    final held = mix;
    if (held == null || device == null) {
      return const OutputRefused();
    }
    WindowedUploadPlan? planAround(int center) => planWindowedMixUpload(
      mix: held,
      conformStore: conformStore,
      deviceRate: deviceRate,
      centerSample: center,
      backSeconds: reach.backSeconds,
      aheadSeconds: reach.aheadSeconds,
    );
    // [plan], its windows [read], put on the device and this window centred
    // on [center] — or refused, with nothing moved.
    OutputArm armedBy(
      WindowedUploadPlan plan,
      List<AudioMixSource> read,
      int center,
    ) => _put(device, plan.withWindows(read), center)
        ? OutputArmed(deviceRate: deviceRate, cannotPlay: plan.cannotPlay)
        : const OutputRefused();

    final plan = planAround(centerSample);
    if (plan == null) {
      return const OutputComing();
    }
    if (!plan.hasStreaming) {
      _read = null;
      _asked = null;
      return armedBy(plan, const [], centerSample);
    }
    // The same streamed clips' windows, around a centre that holds this
    // one ([_holds]) — planned there, as they were read.
    WindowedUploadPlan? sameAround(_AskedWindows? at) {
      if (at == null || !_holds(at.center, centerSample, deviceRate)) {
        return null;
      }
      final there = planAround(at.center);
      return there != null && listEquals(there.reads, at.reads) ? there : null;
    }

    final read = _read;
    final readThere = read == null
        ? null
        : sameAround((center: read.center, reads: read.reads));
    if (read != null && readThere != null) {
      final armed = armedBy(readThere, read.windows, read.center);
      if (armed is OutputArmed) {
        _read = (
          center: read.center,
          reads: read.reads,
          windows: read.windows,
          whole: read.whole,
          onDevice: true,
        );
      }
      return armed;
    }
    if (sameAround(_asked) == null) {
      _ask(plan, device, centerSample);
    }
    return const OutputComing();
  }

  /// [plan]'s windows read on a worker for [device], around [center] — the
  /// latest asked: what lands for an earlier ask is not kept.
  void _ask(WindowedUploadPlan plan, QaAudioDevice device, int center) {
    final asked = _asked = (center: center, reads: plan.reads);
    unawaited(_land(asked, device));
  }

  /// [asked]'s windows, once read — kept where no later move was asked
  /// meanwhile, each empty where they did not land whole, and the owner
  /// told ([onLanded]).
  Future<void> _land(_AskedWindows asked, QaAudioDevice device) async {
    List<AudioMixSource>? windows;
    try {
      windows = await readWindows(asked.reads, device);
    } on StateError {
      windows = null;
    }
    if (!identical(_asked, asked)) {
      return;
    }
    _asked = null;
    _read = (
      center: asked.center,
      reads: asked.reads,
      windows:
          windows ??
          [
            for (final read in asked.reads)
              AudioMixSource(
                samples: Float32List(0),
                channels: read.reader.channels,
                sourceStart: read.start,
              ),
          ],
      whole: windows != null,
      onDevice: false,
    );
    onLanded?.call();
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
    return true;
  }
}

/// The windows a move read ([AudioStreamingWindow.upload]): [reads] around
/// [center] — [whole], or each empty where one did not land whole — and
/// whether they are [onDevice] yet.
typedef _ReadWindows = ({
  int center,
  List<StreamWindowRead> reads,
  List<AudioMixSource> windows,
  bool whole,
  bool onDevice,
});

/// The windows a move asked for and has not had yet: [reads], around
/// [center].
typedef _AskedWindows = ({int center, List<StreamWindowRead> reads});

/// [reads] read on a worker into buffers of [device]'s own, which this
/// isolate takes over — all a window's move asks of the thread that draws
/// (streaming-advance-reads-on-the-ui-thread, 10-15; every move since
/// long-sound-windows-are-read-on-the-ui-isolate, 11-15). Null when one
/// did not land whole ([readStreamWindowsInto]).
Future<List<AudioMixSource>?> readStreamWindowsOnAWorker(
  List<StreamWindowRead> reads,
  QaAudioDevice device,
) async {
  final landed = await _readOnAWorker(reads);
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
/// closure's whole context, and this one holds [reads].
Future<List<LandedStreamWindow>?> _readOnAWorker(
  List<StreamWindowRead> reads,
) => onAWorker(() => readStreamWindowsInto(reads, audioBuffersHere()));

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
  final window = readStreamedWindow(
    (
      reader: reader,
      start: at.start,
      count: at.count,
      filtered: read.filtered,
    ),
    place: (_) => buffer.asTypedList(floats),
  );
  if (window.samples.length != floats) {
    return null;
  }
  return (startSample: at.start, address: buffer.address, floats: floats);
}

/// What an output was given — by an arm ([armAudioOutput]) or an upload
/// ([AudioStreamingWindow.upload]).
///
/// 🚨THREE ANSWERS, because a run does three things with them
/// (playback-waits-for-its-sound — 유저 2026-10-16: 「대체 재생을 안 쓰고,
/// 소리가 준비될 때까지 기다린다」 · 「재생못하거나 하는 상황에선 제대로
/// 메시지라던가 뭔가 표시」): it plays ([OutputArmed]), it waits for its
/// sound ([OutputComing]), or it goes on without it ([OutputRefused], and
/// [OutputArmed.cannotPlay] for single sources). ↩️An arm answered null or
/// `uploaded: false` for all of it, the run stood down, and the platform
/// players carried whatever the device did not.
sealed class OutputArm {
  const OutputArm();
}

/// On the output, at [deviceRate]: every clip but those of [cannotPlay].
final class OutputArmed extends OutputArm {
  const OutputArmed({required this.deviceRate, required this.cannotPlay});

  final int deviceRate;

  /// The sources the run plays without, and why
  /// ([WindowedUploadPlan.cannotPlay]).
  final Map<String, SoundCannotPlay> cannotPlay;
}

/// Not yet: the output being opened ([QaAudioDevice.opening]), a source
/// being made ready ([AudioConformStore.isLanding]), or a long sound's
/// windows being read on a worker ([AudioStreamingWindow.onLanded]) — each
/// says so when it lands. Nothing was uploaded.
final class OutputComing extends OutputArm {
  const OutputComing();
}

/// The output would not open, or would not take the schedule: nothing
/// plays out of it.
final class OutputRefused extends OutputArm {
  const OutputRefused();
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
/// ⚠️What IS: an output open at another RATE than the sound was conformed
/// at is opened again at it, off this thread, and the arm says
/// [OutputComing]. That is no setting but the run's own sound, which only
/// an arm knows — the device stays open for the first project's rate when
/// a second opens at another, or when the project's rate is changed — and
/// a long sound streams only at the rate its conform is
/// ([planWindowedMixUpload]). ↩️Such a sound never uploaded, and the
/// platform players carried the run.
///
/// [OutputComing] = the output is being opened off this thread
/// ([QaAudioDevice.opening]), or a source is being made ready — the
/// lookups have KICKED their conforms — or a long sound's windows are being
/// read on a worker ([AudioStreamingWindow.upload]). [OutputRefused] = it
/// would not open, and nothing was touched.
///
/// ⛔An output being opened ahead is not opened here as well: the C makes
/// a device one call at a time, so this thread would wait out the worker's
/// open — the stall the open ahead is there to take off it.
OutputArm armAudioOutput({
  required QaAudioDevice device,
  required AudioConformStore conformStore,
  required AudioStreamingWindow window,
  required List<ScheduledAudioClip> schedule,
  required ProjectFrameRate rate,
  required int centerFrame,
  required String? preferredDeviceName,
}) {
  final soundRate = conformStore.projectSampleRate;
  if (device.isOpening) {
    return const OutputComing();
  }
  if (!device.isOpen &&
      !openAudioOutput(
        device,
        sampleRate: soundRate,
        preferredName: preferredDeviceName,
      )) {
    return const OutputRefused();
  }
  if (device.openedAtRate != soundRate) {
    unawaited(
      openAudioOutputAhead(
        device,
        sampleRate: soundRate,
        preferredName: device.openedFor,
        atThatRate: true,
      ),
    );
    return const OutputComing();
  }
  final deviceRate = device.sampleRate;
  window.mix = audioMixScheduleFrom(
    schedule: schedule,
    rate: rate,
    sampleRate: deviceRate,
  );
  device.stop();
  return window.upload(
    device: device,
    conformStore: conformStore,
    deviceRate: deviceRate,
    centerSample: rate.frameToSample(centerFrame, deviceRate),
  );
}

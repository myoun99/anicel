import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/project_frame_rate.dart';
import '../../models/rgba_image_bytes.dart' show estimatedImageBytes;
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/viewer_document.dart';
import '../widgets/transport_bar.dart' show TransportSound;
import 'audio_viewer_document.dart';
import 'page_rasters.dart';
import 'viewer_sound.dart';

/// What a run asks of the surface it runs on — the only things only the
/// surface knows.
abstract interface class MediaRunSurface {
  /// The document shown, or null while there is none.
  ViewerDocument? get document;

  /// The page the playhead stands on.
  int get page;

  /// Moves the playhead to [page], inside the document.
  void turnToPage(int page);

  /// The file whose SOUND plays beside the pages, or null when the thing
  /// shown cannot carry any.
  String? get soundPath;

  /// How loud that sound plays — asked each time it starts.
  ViewerLoudness get loudness;

  bool get mounted;

  void setState(VoidCallback fn);
}

/// A RUN of a document: the timer that turns its pages, the sound beside
/// them, and the law that the whole transport waits.
///
/// 🚨One run for every surface that plays a [ViewerDocument] — the media
/// viewer, and the import window's preview (import-preview-plays-silent,
/// 2026-09-29: 「뷰어패널이랑 통일할거하면서 소리나게」). It lived inside the
/// viewer, and a second surface that plays would have been a second copy.
class MediaRun {
  MediaRun({
    required MediaRunSurface surface,
    required PageRasters rasters,
    required this.sound,
  }) : _surface = surface,
       _rasters = rasters;

  final MediaRunSurface _surface;
  final PageRasters _rasters;

  /// The surface's sound, or silence if the app has no audio device.
  final ViewerSound sound;

  /// The timer turning pages while playing, and null while stopped —
  /// 🚨the ONLY thing that says whether this run is playing, so a second
  /// flag cannot disagree with it ([[make-the-invariant-unrepresentable]]).
  ///
  /// ⚠️Write it through the setter below and nowhere else. [playingFlips]
  /// has to fire for the actuation gate, and a notifier poked at the call
  /// sites would be exactly the second flag this comment forbids — here it
  /// cannot be written except by the assignment that changes the timer.
  Timer? _timerField;

  Timer? get _timer => _timerField;

  set _timer(Timer? timer) {
    _timerField?.cancel();
    _timerField = timer;
    playingFlips.value = timer != null;
  }

  /// Fires when this run starts or stops, and on nothing else — never per
  /// turned page (the actuation gate wraps the whole editor).
  final ValueNotifier<bool> playingFlips = ValueNotifier<bool>(false);

  bool get playing => _timer != null;

  /// True while the playhead is parked waiting for its cushion to refill.
  /// ⛔Reset with the cache: it is a fact about a document that is gone.
  bool buffering = false;

  /// Where the sound has got to, in seconds — the playhead's position on
  /// the waveform.
  ///
  /// 🚨It is read from the DEVICE every tick, never counted up here: the
  /// device counts samples handed to the hardware, so a playhead that
  /// follows it cannot drift from what is being heard. A local counter
  /// would be a second clock, and the timeline's transport spends its
  /// whole header explaining why there is only ever one.
  double soundSeconds = 0;

  int get _pageCount => _surface.document?.pageCount ?? 0;

  int get _page => _surface.page;

  /// How long the sound beside the pages is, once its conform has answered
  /// — asked of the store the sound plays out of, so no surface can answer
  /// it from another.
  double? get soundLengthSeconds {
    final path = _surface.soundPath;
    return path == null ? null : sound.conformStore.durationSecondsFor(path);
  }

  /// How far a cached page is from being wanted again — the measure the
  /// page cache lets pages go by ([PageRasters]).
  ///
  /// 🚨**PLAYBACK ONLY MOVES FORWARD**, so a page already shown is never
  /// wanted again and is farther than any page ahead. Measuring both with
  /// `abs()` — which is what stood here — made the read-ahead buffer evict
  /// ITSELF to keep frames that had just been displayed: a page five ahead
  /// and a page five behind tied, and the tie went to whichever the map
  /// listed first.
  ///
  /// ⚠️Paging by hand is a different question and keeps `abs()`: someone
  /// stepping through a PDF is as likely to go back as forward.
  int distanceTo(int page) {
    if (!playing) {
      return (page - _page).abs();
    }
    return page >= _page ? page - _page : _pageCount + (_page - page);
  }

  /// Whether this document turns its own pages — 유저 2026-08-29:
  /// 「비디오 … 불러와서 재생가능하게」. It asks the DOCUMENT, so an
  /// animated GIF gets the same button a movie does; nothing here knows
  /// what a movie is.
  bool get turnsItsOwnPages =>
      (_surface.document?.framesPerSecond ?? 0) > 0 && _pageCount > 1;

  /// Whether there is anything to PLAY: pages that advance by themselves,
  /// or sound. 유저 2026-09-08: 「뷰어 소리 내는 범위는 싹 다야」 — so a
  /// waveform, which turns no pages at all, still gets the button.
  bool get canPlay => turnsItsOwnPages || _surface.soundPath != null;

  // --- What a transport counts over this run --------------------------------

  /// The sound shown as its own picture — a waveform, one page — or null
  /// when the document is not one.
  AudioPeaks? get _waveform => switch (_surface.document) {
    final AudioViewerDocument waveform => waveform.peaks,
    _ => null,
  };

  /// The instant of a frame and back, in microseconds, rounded the way the
  /// mixer's samples are ([ProjectFrameRate.frameToSample]) so the pair
  /// round-trips: a seek to a frame reads back as that frame.
  static const int _micros = Duration.microsecondsPerSecond;

  /// How many frames a transport runs over: a waveform's length in
  /// [rate]'s frames, anything else its pages — one when there is nothing,
  /// and the bar sits there inert.
  ///
  /// 🚨ONE COUNT for every surface that puts a transport under a run — the
  /// import window's preview and the media viewer (F-289). ↩️It was the
  /// import preview's own, and the viewer's transport would have been the
  /// second place a sound is counted in frames.
  int frameCount(ProjectFrameRate rate) =>
      _waveform?.durationFrames(rate) ?? math.max(1, _pageCount);

  /// Where the playhead stands, in those frames: the page, or a waveform's
  /// seconds ([soundSeconds]) — a waveform is one page.
  int frameAt(ProjectFrameRate rate) => _waveform == null
      ? _page
      : rate.sampleToFrame((soundSeconds * _micros).round(), _micros);

  /// The hand moved the playhead to [frame]. A waveform's seconds move with
  /// it; anything else turns to the page. A run going picks up from there,
  /// sound and all ([movedByHand]).
  void seekToFrame(int frame, ProjectFrameRate rate) {
    _surface.setState(() {
      if (_waveform != null) {
        soundSeconds = rate.frameToSample(frame, _micros) / _micros;
      } else {
        _surface.turnToPage(frame);
      }
      // TURNING A PAGE IS ASKING AGAIN — the viewer's law for a page its
      // engine once refused (`MediaViewerTabHost`'s `_forgetRefusals`).
      _rasters.forgetRefusals();
    });
    movedByHand();
  }

  /// The transport's sound cell over this run: the surface's loudness as it
  /// stands, and what a hand on the speaker or the bar asks of it
  /// ([onChanged] — the surface keeps the answer) — or null when the thing
  /// shown carries no sound, and the cell stands off.
  ///
  /// A level is mixed into what the device is handed ([ViewerSound.play]),
  /// so a sound already going is armed again where it stands — once the
  /// hand lets go of the bar, not on every step under it. Moving the bar
  /// un-mutes: the hand is asking to hear it.
  TransportSound? soundCell({
    required ValueChanged<ViewerLoudness> onChanged,
  }) {
    if (_surface.soundPath == null) {
      return null;
    }
    final loudness = _surface.loudness;
    void set(ViewerLoudness next, {required bool settled}) {
      if (next != loudness) {
        onChanged(next);
      }
      if (settled) {
        movedByHand();
      }
    }

    return TransportSound(
      level: loudness.level,
      muted: loudness.muted,
      onLevelChanged: (level) =>
          set(ViewerLoudness(level: level), settled: false),
      onLevelSettled: (level) =>
          set(ViewerLoudness(level: level), settled: true),
      onMuteToggled: () => set(
        ViewerLoudness(level: loudness.level, muted: !loudness.muted),
        settled: true,
      ),
    );
  }

  // --- The playback buffer (a player, not a slideshow) --------------------

  /// How much movie the read-ahead tries to keep ready, in SECONDS.
  ///
  /// 유저 2026-08-31: 「10초? 5초? **메모리 제한에 맞춰서 알아서** 로드하고」
  /// — so this is a ceiling, not the number that usually decides. On any
  /// document big enough to matter [bufferAheadPages] hits the byte budget
  /// first, and the budget is the one that knows the device.
  static const double bufferAheadSeconds = 5;

  /// Frames of read-ahead this document affords: whichever of the time
  /// window and the memory budget runs out first, and zero when nothing is
  /// playing (paging by hand needs no cushion).
  ///
  /// 🚨The budget has to hold the frame being LOOKED AT as well, so the
  /// read-ahead gets what is left after it. Without that subtraction the
  /// buffer fetches exactly enough to evict its own oldest entry, and the
  /// eviction re-issues the render it just dropped.
  int bufferAheadPages() {
    final document = _surface.document;
    final scale = _rasters.scale;
    if (document == null || scale == null || !playing) {
      return 0;
    }
    final fps = document.framesPerSecond ?? 0;
    final size = document.pageSize(_page);
    final bytes = estimatedImageBytes(
      (size.width * scale).round().clamp(1, 1 << 13).toInt(),
      (size.height * scale).round().clamp(1, 1 << 13).toInt(),
    );
    final affordable = bytes <= 0
        ? 0
        : (_rasters.budget.byteBudget ~/ bytes) - 1;
    final window = (fps * bufferAheadSeconds).round();
    return math.max(0, math.min(affordable, window));
  }

  /// What the buffer must hold before a parked playhead moves again.
  ///
  /// 유저 2026-08-31: 「로드가 안되고있으면 5초분만큼? 로드될떄까지 멈추는?」
  /// — resuming on ONE ready frame is the stutter this replaces: play a
  /// frame, run dry, park, play a frame. It is the SAME cushion
  /// [bufferAheadPages] fills, capped by what is left of the movie so the
  /// last seconds do not become unplayable.
  int _resumeAfterFrames() =>
      math.min(bufferAheadPages(), _pageCount - _page - 1);

  /// Issues the NEXT missing raster the playhead will need, one at a time.
  ///
  /// ⛔Not all of them at once: both decoders behind [ViewerDocument] are
  /// serial (PDFium runs one worker, and the video decoder's fast path is
  /// sequential reads), so a hundred outstanding requests would finish in
  /// the same order and the same time while holding a hundred futures. Each
  /// landing rebuilds, which issues the next — the queue walks forward on
  /// its own.
  void fillBuffer() {
    final scale = _rasters.scale;
    if (scale == null || _rasters.rendering) {
      return;
    }
    final ahead = bufferAheadPages();
    for (var offset = 1; offset <= ahead; offset += 1) {
      final page = _page + offset;
      if (page >= _pageCount) {
        return;
      }
      if (!_rasters.readyAt(page, scale)) {
        _rasters.ensureRendered(page, scale);
        return;
      }
    }
  }

  /// Stops the run — silently, for the surface to rebuild around.
  void stop() {
    _timer = null;
    buffering = false;
    // ⚠️Unconditional: [ViewerSound.stop] is idempotent, and every path out
    // of a run — the button, the actuation gate, a new file, a closed tab —
    // comes through here. A sound left playing under a stopped viewer is
    // the one failure this panel cannot show on screen.
    //
    // 🪦This line carried a 「MUTANT SURVIVES HERE」 note for one round: the
    // bench has no audio device, so nothing could be left playing and
    // deleting it changed nothing. The note was right about the bench and
    // wrong about the conclusion — the answer was a SEAM, not a shrug.
    // `MediaViewerTabHost.sound` is that seam, and the mutant dies now.
    sound.stop();
  }

  /// Stops, and forgets where the sound stood — a fact about a document
  /// that is gone, as [buffering] is. A surface calls it when its document
  /// goes: a new sound used to start where the last one had stopped.
  void letGo() {
    stop();
    soundSeconds = 0;
  }

  /// One tick of a run that has SOUND and no pages: move the playhead to
  /// wherever the device has got to.
  ///
  /// 🚨★★★**THE PICTURE FOLLOWS THE SOUND, NEVER A COUNTER.** The device
  /// counts samples handed to the hardware, so a playhead read from it
  /// cannot drift from what is being heard however late this tick runs.
  /// Counting up here instead would be a second clock, which is the exact
  /// thing the timeline's device transport exists to avoid.
  void _followTheSound() {
    if (!_surface.mounted) {
      return;
    }
    final at = sound.positionSeconds;
    if (at == null || sound.ended) {
      // Ran out: a viewer that kept ticking on a silent device would say
      // 「재생 중」 to the actuation gate forever. A sound that reached its
      // end leaves the playhead ON the end — the last tick read it a tick
      // short, and a press from there would play one tick and stop.
      _surface.setState(() {
        if (sound.ended) {
          soundSeconds = soundLengthSeconds ?? soundSeconds;
        }
        stop();
      });
      return;
    }
    _surface.setState(() => soundSeconds = at);
  }

  /// Where a press picks the sound up: where the playhead STANDS — the
  /// instant of the page in a document that turns its own, the waveform's
  /// playhead otherwise — and from the top once it has reached the end.
  ///
  /// 🗣️The playhead line says it itself (「where the playhead STANDS is
  /// what tells you where a second press would resume from」), and every
  /// press started the sound at 0 all the same: a movie resumed mid-way
  /// played its picture from the page and its sound from the top
  /// (import-preview-plays-silent, 2026-09-29).
  double _resumeSeconds() {
    if (turnsItsOwnPages) {
      return _page / _surface.document!.framesPerSecond!;
    }
    final length = soundLengthSeconds;
    return length == null || soundSeconds >= length ? 0 : soundSeconds;
  }

  /// How often a run of THIS document has something to do: once per
  /// frame while pages advance, and otherwise once per screen frame,
  /// which is all a playhead sliding along a waveform needs. Null = there
  /// is nothing to run.
  Duration? get _tickPeriod {
    final fps = _surface.document?.framesPerSecond ?? 0;
    if (turnsItsOwnPages) {
      return Duration(microseconds: (1000000 / fps).round().clamp(1, 1000000));
    }
    return _surface.soundPath == null
        ? null
        : const Duration(milliseconds: 16);
  }

  /// The play button: starts a run, or stops the one going.
  void toggle() {
    if (playing) {
      _surface.setState(stop);
      return;
    }
    _start(fromTheTopAtTheEnd: true);
  }

  /// The hand moved the playhead while this run goes: it picks up from
  /// there, sound and all — a sound left where it was would put the
  /// picture and the sound on two clocks ([_followTheSound]).
  ///
  /// ⚠️Not 「from the top at the end」: that answers a PRESS of play on the
  /// last frame, and a hand that puts the playhead on the end has asked to
  /// stand there.
  void movedByHand() {
    if (!playing) {
      return;
    }
    stop();
    _start(fromTheTopAtTheEnd: false);
  }

  void _start({required bool fromTheTopAtTheEnd}) {
    final period = _tickPeriod;
    if (period == null) {
      return;
    }
    final soundPath = _surface.soundPath;
    _surface.setState(() {
      // From the top when the playhead is already at the end: pressing play
      // on the last frame has to DO something, and the only sensible
      // something is to play it again.
      if (fromTheTopAtTheEnd && _page >= _pageCount - 1) {
        _surface.turnToPage(0);
      }
      if (soundPath != null) {
        soundSeconds = _resumeSeconds();
        sound.play(
          soundPath,
          fromSeconds: soundSeconds,
          gain: _surface.loudness.gain,
        );
      }
      // ⛔A run with neither pages to turn nor sound coming out is a timer
      // saying 「재생 중」 to the actuation gate while nothing happens — and
      // the gate would then eat the next press for it. Standing down is
      // silent BY DESIGN (no audio device, a conform still landing), so
      // this is the shape that keeps a stand-down from becoming a lie.
      if (!turnsItsOwnPages && !sound.isCarrying) {
        return;
      }
      _timer = Timer.periodic(period, (_) => _onTick());
    });
  }

  /// One tick of a run.
  ///
  /// 🚨★★★**AND THE RETRY CLOCK.** A frame the decoder refused is forgotten
  /// here, so it is asked for again at the rate the movie actually needs
  /// it — once per frame time — instead of as fast as the decoder can keep
  /// saying no. See [PageRasters] for what that cost.
  ///
  /// ⛔The fill has to be driven from here rather than left to the next
  /// build: while the buffer is dry [_turnThePage] returns WITHOUT a
  /// `setState`, so a parked viewer rebuilds for nothing and the walk
  /// forward would have no one to start it. That is why forgetting the
  /// failure is not enough on its own.
  void _onTick() {
    if (!_surface.mounted) {
      return;
    }
    _rasters.forgetRefusals();
    sound.keepStreaming();
    // 🚨BEFORE the turn, from the page on screen — the page the cache will
    // not let go ([PageRasters.shown]). Asked after it, the new frame could
    // land while the screen still showed the old one, and a budget holding
    // that page because it is ON SCREEN dropped the far end of the cushion
    // instead, which the next build asked for again: at a four-frame
    // budget every frame from the fifth on was decoded twice (measured
    // 2026-09-30). The turn's own rebuild asks from the new page.
    fillBuffer();
    if (turnsItsOwnPages) {
      _turnThePage();
    } else {
      _followTheSound();
    }
  }

  /// 🚨★★★**THE PLAYHEAD WAITS. IT DOES NOT WALK PAST A FRAME THAT IS NOT
  /// THERE — AND NEITHER DOES THE SOUND.**
  ///
  /// This used to be 「best effort, deliberately」: the page advanced on the
  /// clock and whichever raster had landed was drawn. What that produced
  /// was a picture standing still while the playhead moved — and a held
  /// picture cannot be told apart from a hold the animator DREW, which is
  /// the one judgement this panel exists to support. 유저 2026-08-31:
  /// 「유지하지말고 로드할때까지 멈춰있어야지」, and 「그림을 유지한다는게
  /// 아니라 그 곳에 멈춘다는거야」.
  ///
  /// ⚠️The CANVAS does the opposite and that is also right: it judges
  /// TIMING against sound, so it holds real time and drops frames —
  /// `AudioPlaybackSync` says so in one line, 「frames drop, time never
  /// stretches」.
  ///
  /// 🪦That last paragraph used to end 「This is a player looking at
  /// reference, where nothing is riding on the clock, so it buffers」, and
  /// as of 2026-09-08 something IS riding on it: the movie's own
  /// soundtrack. The law did not change — it reached further. A buffer
  /// that runs dry now holds the SOUND at the same instant, so the two
  /// stutter together and come back in step; letting the sound run on
  /// would leave the picture to catch up by dropping frames, which is the
  /// behaviour this surface was given its law to refuse.
  void _turnThePage() {
    if (_page >= _pageCount - 1) {
      _surface.setState(stop);
      return;
    }
    final ready = _rasters.readyFrom(_page + 1, _pageCount);
    if (buffering) {
      // ⛔Not「one frame is ready, go」: that plays a frame, runs dry
      // and parks again, which is a stutter rather than playback.
      if (ready < _resumeAfterFrames()) {
        return;
      }
      sound.resume(soundSeconds);
      _surface.setState(() => buffering = false);
    } else if (ready < 1) {
      // Remember where the sound was, because that is where BOTH pick up.
      soundSeconds = sound.positionSeconds ?? soundSeconds;
      sound.hold();
      _surface.setState(() => buffering = true);
      return;
    }
    _surface.turnToPage(_page + 1);
  }

  /// Stops and lets go of the notifier — the surface is going.
  void dispose() {
    stop();
    playingFlips.dispose();
  }
}

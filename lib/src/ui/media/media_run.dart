import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show TickerProvider;

import '../../models/playback_mode.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/viewer_document.dart';
import '../../services/playback/frame_demand.dart';
import '../../services/playback/playback_picture_wait.dart';
import '../../services/playback/playhead_way.dart';
import '../playback/looking_ticker.dart';
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

  /// Where the run's clock looks from — the surface's own vsync, so a
  /// surface not shown silences it ([LookingTicker]).
  TickerProvider get vsync;
}

/// A RUN of a document: the clock that turns its pages, the sound beside
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

  /// The clock's looks — one at every vsync while playing, none while
  /// stopped: 🚨the ONLY thing that says whether this run is playing, so a
  /// second flag cannot disagree with it
  /// ([[make-the-invariant-unrepresentable]]).
  ///
  /// 🚨THE CANVAS'S TICK, IN ITS CODE (viewer-plays-by-the-one-playback-
  /// law, ④). ↩️A `Timer.periodic` of a frame's length turned a page each
  /// time it fired — and it fired early: Dart's timers count whole
  /// milliseconds, so a 24fps run asked for 41,667µs and got 41ms (🔬10-11,
  /// this machine: 24.374 a second — a ten-second movie over in 9.846s),
  /// with the movie's sound running at its own speed beside it.
  late final LookingTicker _clock = LookingTicker(_onTick);

  /// ⚠️Started and stopped here and nowhere else. [playingFlips] has to fire
  /// for the actuation gate, and a notifier poked at the call sites would be
  /// exactly the second flag the note above forbids.
  void _runs(bool going) {
    if (going) {
      _clock.start(_surface.vsync);
    } else {
      _clock.stop();
    }
    playingFlips.value = going;
  }

  /// Fires when this run starts or stops, and on nothing else — never per
  /// turned page (the actuation gate wraps the whole editor).
  final ValueNotifier<bool> playingFlips = ValueNotifier<bool>(false);

  bool get playing => _clock.isRunning;

  /// Where the clock's span began: the film's time then, in seconds, and
  /// the clock's own time then — a run put on a page, or a parked run going
  /// on ([_filmSeconds]).
  double _spanFrom = 0;
  Duration _spanAt = Duration.zero;

  /// The clock's own time at its latest look.
  Duration _elapsed = Duration.zero;

  /// When a refused page was last asked for again ([_onTick]).
  Duration? _retriedAt;

  /// True while the playhead is parked — the clock standing ([_wait]) and
  /// the sound held with it.
  /// ⛔Reset with the cache: it is a fact about a document that is gone.
  bool buffering = false;

  /// Whether the clock stands before the page ahead: the canvas's law
  /// ([PlaybackPictureWait]) at the setting this run plays by — render
  /// first, with the cushion as what lies ahead ([fillBuffer]). A page that
  /// is not there parks the playhead before it, and a parked playhead goes
  /// on once the read-ahead has come to rest where it stands.
  ///
  /// 🚨ONE LAW, ONE CODE (viewer-plays-by-the-one-playback-law, 유저
  /// 2026-10-08: 「쓸수있는 로직 뷰어패널에서도 법 통일된거 재사용하게」,
  /// 「옵션은 안둬도 되니까」). ↩️This run spelled the law's steps itself in
  /// [_turnThePage], beside the canvas's spelling of the same steps.
  ///
  /// ⛔Asked with `placed: false` always — a press is not where this run
  /// fills. The viewer's law (유저 2026-08-31: 「로드가 안되고있으면 5초분
  /// 만큼? 로드될떄까지 멈추는?」) stands where a page is NOT there; a press
  /// on pages that come as fast as they are shown just plays. Filling at a
  /// press — what render-first does for a canvas run put somewhere — held
  /// every press for the whole cushion, up to five seconds of pages, however
  /// fast they came (tried 10-10; the transport pins said so).
  late final PlaybackPictureWait _wait = PlaybackPictureWait(
    mode: () => PlaybackMode.renderFirst,
    pictureIsThere: (page) {
      final at = _rasters.scale;
      return at != null && _rasters.readyAt(page, at);
    },
    aheadIsFilled: () => _restingAt == _page,
  );

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

  /// How many steps on [page] is next wanted, or null where it is not — the
  /// order the page cache lets pages go by, latest first ([PageRasters]).
  ///
  /// 🚨THE CANVAS'S ORDERS, IN THEIR CODE (viewer-plays-by-the-one-playback-
  /// law, ②): a run that plays once ([playingStepOf]), and a run that
  /// stands, from the page on screen outwards ([standingStepOf]). ↩️This
  /// measured both itself (`distanceTo`), the same two orders spelled
  /// again.
  ///
  /// 🚨**PLAYBACK ONLY MOVES FORWARD**, so a page already shown is never
  /// wanted again and goes before any page ahead. Measuring both with
  /// `abs()` — which is what once stood here — made the read-ahead buffer
  /// evict ITSELF to keep frames that had just been displayed: a page five
  /// ahead and a page five behind tied, and the tie went to whichever the
  /// map listed first.
  ///
  /// ⚠️Paging by hand is a different question and goes outwards both ways:
  /// someone stepping through a PDF is as likely to go back as forward.
  int? wantedAt(int page) {
    if (_pageCount == 0) {
      return null;
    }
    final at = _page.clamp(0, _pageCount - 1);
    return playing
        ? playingStepOf(page, playhead: at, total: _pageCount, loops: false)
        : standingStepOf(page, center: at, count: _pageCount);
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
  /// document big enough to matter the room runs out first ([fillBuffer]),
  /// and the budget is the one that knows the device.
  static const double bufferAheadSeconds = 5;

  /// The page the playhead stood on when the read-ahead last came to rest —
  /// every page of the window ahead there, or no room for the next one —
  /// and null while it is still asking ([fillBuffer]). A parked playhead
  /// goes on when it rests where the playhead stands ([_wait]).
  int? _restingAt;

  /// Issues the NEXT missing raster the playhead will need, one at a time —
  /// the walk the canvas's warmer walks (viewer-plays-by-the-one-playback-
  /// law, ③): in the order a run that plays wants its pages, within the
  /// time window, each asked for only when room is made for it by letting
  /// go of pages wanted later ([PageRasters.makeRoomFor]). A page with no
  /// room rests the walk, and what is held is the cushion.
  ///
  /// ↩️It counted the room up front — the budget over the page on screen,
  /// less that page (`bufferAheadPages`) — which held while every page
  /// weighed what the one on screen did; a document's pages need not.
  ///
  /// ⛔Not all of them at once: both decoders behind [ViewerDocument] are
  /// serial (PDFium runs one worker, and the video decoder's fast path is
  /// sequential reads), so a hundred outstanding requests would finish in
  /// the same order and the same time while holding a hundred futures. Each
  /// landing rebuilds, which issues the next — the queue walks forward on
  /// its own.
  ///
  /// 🚨THE PAGE THE CLOCK WAITS ON IS ASKED FOR WHATEVER THE ROOM — as the
  /// canvas's warmer makes the picture under its playhead. The playhead
  /// parks BEFORE a page that is not there ([_turnThePage]), so nothing
  /// else asks for that page: a page bigger than half the budget leaves no
  /// room beside the one on screen, and a run that asked for nothing ahead
  /// would stand for good. ↩️Such a run turned onto pages that had not
  /// landed — the blank frames the wait exists to refuse.
  void fillBuffer() {
    _restingAt = null;
    final document = _surface.document;
    final scale = _rasters.scale;
    if (document == null || scale == null || !playing || _rasters.rendering) {
      return;
    }
    final window = math.max(
      1,
      ((document.framesPerSecond ?? 0) * bufferAheadSeconds).round(),
    );
    for (var step = 1; step <= window; step += 1) {
      final page = _page + step;
      if (page >= _pageCount) {
        break;
      }
      if (_rasters.readyAt(page, scale)) {
        continue;
      }
      if (step > 1 && !_rasters.makeRoomFor(page, scale, step: step)) {
        break;
      }
      _rasters.ensureRendered(page, scale);
      return;
    }
    _restingAt = _page;
  }

  /// Stops the run — silently, for the surface to rebuild around.
  void stop() {
    _runs(false);
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

  /// How long one of this document's frames lasts — null for a document
  /// that turns no pages of its own.
  Duration? get _framePeriod {
    final fps = _surface.document?.framesPerSecond ?? 0;
    return turnsItsOwnPages
        ? Duration(microseconds: (1000000 / fps).round().clamp(1, 1000000))
        : null;
  }

  /// Where the film has got to at this look, in seconds: the sound while it
  /// is heard — the picture follows the sound, never a counter
  /// ([_followTheSound]) — and the clock's span otherwise.
  ///
  /// 🚨The span is put where the sound is at every look that hears it, so a
  /// sound that ends before the pictures hands the film on to the span from
  /// where it ended: a movie whose track is shorter than its pictures plays
  /// on to its last page. ↩️Read without that, its picture stood at the
  /// sound's end, playing for good.
  double _filmSecondsAtThisLook() {
    final heard = _surface.soundPath != null && !sound.ended
        ? sound.positionSeconds
        : null;
    if (heard != null) {
      _spanFromNow(heard);
      return heard;
    }
    return _spanFrom + (_elapsed - _spanAt).inMicroseconds / 1e6;
  }

  /// The clock's span begins again at [seconds] of the film, now.
  void _spanFromNow(double seconds) {
    _spanFrom = seconds;
    _spanAt = _elapsed;
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
    final soundPath = _surface.soundPath;
    // Nothing to run: no pages that turn themselves, no sound.
    if (!turnsItsOwnPages && soundPath == null) {
      return;
    }
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
      // ⛔A run with neither pages to turn nor sound coming out is a clock
      // saying 「재생 중」 to the actuation gate while nothing happens — and
      // the gate would then eat the next press for it. Standing down is
      // silent BY DESIGN (no audio device, a conform still landing), so
      // this is the shape that keeps a stand-down from becoming a lie.
      if (!turnsItsOwnPages && !sound.isCarrying) {
        return;
      }
      _elapsed = Duration.zero;
      _retriedAt = null;
      if (turnsItsOwnPages) {
        _spanFromNow(_page / _surface.document!.framesPerSecond!);
      }
      _runs(true);
    });
  }

  /// One look of a run's clock — every vsync.
  ///
  /// 🚨★★★**AND THE RETRY CLOCK.** A frame the decoder refused is forgotten
  /// here, so it is asked for again at the rate the movie actually needs
  /// it — once per frame time, however often the clock looks — instead of
  /// as fast as the decoder can keep saying no. See [PageRasters] for what
  /// that cost.
  ///
  /// ⛔The fill has to be driven from here rather than left to the next
  /// build: while the buffer is dry [_turnThePage] returns WITHOUT a
  /// `setState`, so a parked viewer rebuilds for nothing and the walk
  /// forward would have no one to start it. That is why forgetting the
  /// failure is not enough on its own.
  void _onTick(Duration elapsed) {
    if (!_surface.mounted) {
      return;
    }
    _elapsed = elapsed;
    final retried = _retriedAt;
    final period = _framePeriod;
    if (retried == null || period == null || elapsed - retried >= period) {
      _rasters.forgetRefusals();
      _retriedAt = elapsed;
    }
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
  /// As of 2026-09-08 the movie's own soundtrack rides beside the pictures,
  /// and the law reached it: a buffer that runs dry holds the SOUND at the
  /// same instant, so the two stutter together and come back in step.
  ///
  /// 🚨THE CLOCK SAYS WHICH PAGE, AND THE PLAYHEAD GOES THE CANVAS'S WAY
  /// ([playheadWay], viewer-plays-by-the-one-playback-law ④). The clock is
  /// the sound while it is heard, the run's own span otherwise
  /// ([_filmSecondsAtThisLook]). A clock that got ahead — a busy frame — is
  /// followed to its page, and the pages on the way that are there drop:
  /// time never stretches, as the canvas's never does. The way stops at a
  /// page that is not there, and the run parks on the page before it.
  /// ↩️This said the CANVAS did the opposite, holding real time and
  /// dropping frames while this buffered. The canvas waits for a picture
  /// that is not made too now ([PlaybackPictureWait]); the two part only on
  /// where a waiting run stands — the canvas on the frame, this panel
  /// before it, on a page it has.
  void _turnThePage() {
    final fps = _surface.document!.framesPerSecond!;
    if (buffering && !_goesOn(fps)) {
      return;
    }
    final due = (_filmSecondsAtThisLook() * fps + _sliver).floor();
    // Its time not come: the page on screen stays.
    if (due <= _page) {
      return;
    }
    if (_page >= _pageCount - 1) {
      _surface.setState(stop);
      return;
    }
    final (:landing, passed: _, :waits) = playheadWay(
      from: _page,
      to: math.min(due, _pageCount - 1),
      total: _pageCount,
      waitsOn: (page) => _wait.holds(page, placed: false),
    );
    if (waits) {
      _parkBefore(landing);
    } else {
      _surface.turnToPage(landing);
    }
  }

  /// Whether a parked run goes on at this look — and when it does, the
  /// sound picks up where it was held, and the clock from the page ahead.
  ///
  /// ⛔Not「one frame is ready, go」: that plays a frame, runs dry and parks
  /// again, which is a stutter rather than playback — the wait goes on when
  /// the cushion has filled (유저 2026-08-31: 「로드가 안되고있으면 5초분만큼?
  /// 로드될떄까지 멈추는?」), the read-ahead at rest ([fillBuffer]).
  bool _goesOn(double fps) {
    if (_wait.holds(_page + 1, placed: false)) {
      return false;
    }
    sound.resume(soundSeconds);
    // Goes on from here: the page it turns to has a whole frame's time, as
    // if the clock had been stopped and started.
    _spanFromNow((_page + 1) / fps);
    _surface.setState(() => buffering = false);
    return true;
  }

  /// The way stopped at [page], which is not there: the playhead parks on
  /// the page before it — the last on the way that is — and the sound is
  /// held with it.
  void _parkBefore(int page) {
    if (page - 1 > _page) {
      _surface.turnToPage(page - 1);
    }
    // Remember where the sound was, because that is where BOTH pick up.
    soundSeconds = sound.positionSeconds ?? soundSeconds;
    sound.hold();
    _surface.setState(() => buffering = true);
  }

  /// What a page's time is read short by — a millionth of a frame, so a
  /// clock that reads exactly a page's time is not taken for one short of
  /// it by a rounding.
  static const double _sliver = 1e-6;

  /// Stops and lets go of the notifier — the surface is going.
  void dispose() {
    stop();
    playingFlips.dispose();
  }
}

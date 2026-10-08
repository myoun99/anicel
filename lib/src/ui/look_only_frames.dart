import 'package:flutter/widgets.dart';

/// 🚨A FRAME THAT WAS ASKED FOR ONLY TO LOOK IS NOT DRAWN (유저 2026-10-08:
/// 「3 화면을 프레임만큼만 다시그리도록」 — and, of the clock that looks:
/// 「소리 싱크나 영상이나 뭐 그런거 정확하기만하면되. 그게 제일 최우선.」).
///
/// A clock that follows time has to look at it on EVERY vsync: that is what
/// changes its frame on the vsync the frame is due on, and no later. But
/// asking the scheduler for a vsync is asking it for a frame, and the
/// framework composites every frame it begins whether or not anything
/// changed (`RendererBinding.drawFrame` → `RenderView.compositeFrame`). At
/// 24 frames a second that is three screen frames in five drawn for nothing
/// at 60Hz, and five in six at 144.
///
/// So whoever asks says what the frame is FOR. A frame asked for inside
/// [askingOnlyToLook] is begun like any other — its callbacks are called,
/// on the vsync — and is DRAWN only when something wants a picture:
///
/// - what the look found changed. Every element and every render object
///   that is made dirty comes through [ensureVisualUpdate], and what is
///   dirty in a frame is drawn in that frame — the frame that looked;
/// - anyone else asked for the frame, to draw ([scheduleFrame] outside a
///   look, [scheduleForcedFrame]);
/// - nobody here asked to look in it at all: the engine's own frame, a
///   warm-up frame. Those are drawn as every frame always was.
///
/// 🔬Measured 2026-10-08 in the Windows app itself (the debug build, a
/// screen the engine paces at 144Hz, a cut of 132 frames at 24 a second
/// with every picture made), ten seconds a round, turn about:
///
/// - DRAWN at every vsync, an ordinary ticker beside the clock — how it
///   was: 690~754 frames drawn, which is all the app could draw of the
///   screen's 1440, and 55~62 frames in a hundred of the film on screen a
///   screen frame or more off their length;
/// - LOOKED at, this: 944~986 frames begun and 255~274 of them drawn, for
///   the 235~244 the film changed in, and 16 in a hundred a screen frame or
///   more off. A frame that was only looked in took 0.30~0.35ms of the UI
///   thread.
///
/// ↩️FOR A DAY THE CLOCK SLEPT INSTEAD (`SleepingTicker`, 2026-10-08). Its
/// ticker was muted between frames and a TIMER woke it 4ms before the next
/// one was due. That draws as little — and it hands the moment a frame
/// changes to the timer. 🔬On the Windows app that timer fired 1.1ms late
/// at the median and 7.1ms at the ninetieth percentile in a quiet stretch,
/// and 18~27ms late at the median once the machine was busy; every wake
/// later than its lead is a frame changed a screen frame late, or several.
/// A vsync is not late like that, and nothing here waits on a timer.
/// ↩️Before that the device's clock — which could not yet say when its
/// next frame was due — was ASKED every 3ms, off the ticker; a frame asked
/// for between vsyncs changes up to a screen frame later than one read on a
/// vsync (유저: 「늦게바뀌는건 좀 많이 신경쓰이는데」).
///
/// ⚠️WHAT THIS CANNOT TELL APART: a frame the ENGINE began by itself — a
/// repaint the platform asked for — on the very vsync a look was asked for,
/// with nothing changed. It passes as the look, undrawn, and the next frame
/// that is drawn puts it right: while a clock runs, that is the next frame
/// of the film.
mixin LookOnlyFrames on WidgetsBinding {
  bool _asksOnlyToLook = false;

  /// What the frame to come was asked for: to look in, to be drawn — or
  /// both, when both were asked.
  bool _lookAsked = false;
  bool _drawAsked = false;

  /// Whether the frame under way is drawn.
  bool _draws = true;

  /// Runs [asks]; a frame it asks the scheduler for is asked for only to
  /// LOOK — to be called back in, on the vsync.
  void askingOnlyToLook(VoidCallback asks) {
    final outer = _asksOnlyToLook;
    _asksOnlyToLook = true;
    try {
      asks();
    } finally {
      _asksOnlyToLook = outer;
    }
  }

  @override
  void scheduleFrame() {
    if (_asksOnlyToLook) {
      _lookAsked = true;
    } else {
      _drawAsked = true;
    }
    super.scheduleFrame();
  }

  @override
  void scheduleForcedFrame() {
    _drawAsked = true;
    super.scheduleForcedFrame();
  }

  @override
  void ensureVisualUpdate() {
    // Something is dirty. A frame under way draws it; with none under way
    // this asks for one (below) — outside any look, so to be drawn.
    _draws = true;
    super.ensureVisualUpdate();
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _draws = _drawAsked || !_lookAsked;
    _drawAsked = false;
    _lookAsked = false;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void drawFrame() {
    if (_draws) {
      super.drawFrame();
    }
  }
}

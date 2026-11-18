import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../../models/cut.dart' show Cut;
import '../../models/cut_id.dart';
import '../../models/onion_skin_settings.dart' show OnionSkinPlacement;
import '../../services/playback/frame_demand.dart'
    show DemandedPicture, standingPicturesOf;
import '../playback/frame_pictures.dart' show FramePictures;
import '../playback/playback_pictures.dart' show PictureState;

/// 🚨★★★A CANVAS THAT STANDS GOES TO A FRAME WITH ITS PICTURE (유저
/// 2026-11-18, the-standing-canvas-composes-a-frame-twice-before-its-
/// picture-Q1 = B 「임시 그리기를 뺀다」; 11-15 「재생헤드는 바꼈는데 화면이
/// 이전그림인 순간이 있는게 어긋나는거지」): a move of the playhead to a frame
/// whose pictures are not there leaves the session standing on the frame
/// it shows — the playhead, the timeline's current cell and the frame
/// number with it — and lands, all of it together, once they are. They are
/// made at once, at the front of the store's line
/// ([FramePictures.makeShown]). 🗣️Q2 = none 「따로 표시하지 않는다」:
/// standing where it was is the sign that it waits.
///
/// The law a run keeps (`playheadWay`, 유저 2026-10-15 F-365-Q1 「직전
/// 프레임에 서서 기다린다」), with its exception: where the frame it stands on
/// shows no picture either — a cut just switched to, a project just opened
/// — there is nothing to stand on, and the move lands at once, the canvas
/// waiting on the frame itself. So does every move where no canvas stands
/// to show it ([shownBy]).
///
/// 🚨A MOVE WAITS FOR ITS OWN MAKING, NOT FOR EVER: what it made lands it,
/// there or not — a frame its maker could not lay is the canvas's to wait
/// on then. ↩️A screen that asked for its frame again for as long as the
/// frame would not come never came back (🔬2026-11-11, `FramePictureView`).
///
/// ↩️The playhead went at once and the canvas composed the frame as it
/// stood, at the canvas's own resolution, until its picture came: the same
/// frame composed twice, one after the other (🔬Surface Pro 11, S5_BA cut
/// 352: move → picture on screen p50 58 ms, 28 ms without, 11-18).
class StandsWithItsPicture {
  StandsWithItsPicture({
    required FramePictures Function() pictures,
    required Cut? Function() cut,
    required int Function() frame,
    required OnionSkinPlacement Function() placement,
  }) : _pictures = pictures,
       _cut = cut,
       _frame = frame,
       _placement = placement;

  final FramePictures Function() _pictures;
  final Cut? Function() _cut;
  final int Function() _frame;
  final OnionSkinPlacement Function() _placement;

  /// The canvases that stand on the session's frame, showing its pictures.
  final Set<Object> _canvases = Set.identity();

  /// The move that waits for its pictures, null while none does.
  _Move? _waiting;

  final ValueNotifier<int?> _waitsFor = ValueNotifier<int?>(null);

  /// The frame of the cut stood in a move waits for the pictures of — where
  /// the playhead goes once they are there; null while none waits.
  ValueListenable<int?> get waitsFor => _waitsFor;

  /// Whether a press on the canvas is held for the frame a move waits for:
  /// it draws there once the move lands, from its first point (🗣️11-15 ①
  /// (나), as TVPaint does), and no other move goes under it meanwhile —
  /// the playhead never moves under a pen (R15-⑤).
  bool _pressHeld = false;

  /// [canvas] stands on the session's frame and shows its pictures — a
  /// move waits for them from now on.
  void shownBy(Object canvas) => _canvases.add(canvas);

  /// [canvas] no longer shows them: a move that waits lands where no other
  /// canvas does, and no step in line is shown one at a time any more.
  void noLongerShownBy(Object canvas) {
    _canvases.remove(canvas);
    if (_canvases.isEmpty) {
      _steps.clear();
      _landTheOneWaiting();
    }
  }

  /// A press on the canvas is held, or let go ([_pressHeld]).
  void holdsAPress({required bool held}) => _pressHeld = held;

  /// A press came on the canvas: the steps in line go with it — the pen
  /// draws on the frame it came on, or the one a move waits for, and the
  /// playhead does not walk on from under it once it is up. A press held
  /// for that frame comes again as it is handed on to the canvas, before
  /// any step is taken there: what was asked under it goes too.
  void aPressCame() => _steps.clear();

  /// The steps asked while a move waits or steps are in line, in the order
  /// they were asked.
  final List<VoidCallback> _steps = [];

  /// Whether a step in line is being taken: its move is the step's, and
  /// leaves the steps after it in line.
  bool _stepping = false;

  /// Whether the next step in line is to be taken after the frame being
  /// built.
  bool _stepsOn = false;

  /// 🚨EVERY STEP PRESSED IS A STEP TAKEN, ONE AT A TIME (유저 2026-11-18
  /// 14:02, as TVPaint's flip keys: 「빠르게 세 번 누르면 하나씩 하나씩
  /// 바뀌어 기다리면 누른 만큼 움직여 있다」): a step of the playhead from
  /// where it stands — a frame, a block — [walk]s now where no move waits.
  /// Where one does, it is in line, and taken where the moves before it
  /// land, each once the frame it lands on is shown: the frame it is
  /// counted from is that one. A move to a place ([moveTo], not a step's)
  /// leaves no step in line.
  ///
  /// 🗣️Q4 = 1 (11-18 14:05, 「누르고 있는 동안은 그림이 오는 속도로 걷고,
  /// 떼면 그 자리에 선다」): a [repeated] step — a key held, the OS's repeats
  /// of it — is not lined up. One that comes while a move waits goes; the
  /// next after the move lands takes the step after it.
  ///
  /// ↩️A step was counted from the frame stood on: two pressed within one
  /// wait asked for the same frame, and went one.
  void step(VoidCallback walk, {required bool repeated}) {
    if (_waiting == null && _steps.isEmpty) {
      walk();
      return;
    }
    if (!repeated) {
      _steps.add(walk);
    }
  }

  /// Takes the first step in line, where no move waits.
  void _takeTheNextStep() {
    _stepsOn = false;
    if (_waiting != null || _steps.isEmpty) {
      return;
    }
    final walk = _steps.removeAt(0);
    _stepping = true;
    try {
      walk();
    } finally {
      _stepping = false;
    }
    if (_waiting == null) {
      _stepOnAfterTheFrame();
    }
  }

  /// The next step in line, once the frame the one before it landed on is
  /// built: each step's frame is shown.
  void _stepOnAfterTheFrame() {
    if (_steps.isEmpty || _stepsOn) {
      return;
    }
    _stepsOn = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _takeTheNextStep())
      ..ensureVisualUpdate();
  }

  /// Moves the playhead to [frame] of the cut stood in: [land] now, where
  /// its pictures are there or nothing shows them; once they are, else.
  /// The move after replaces it.
  void moveTo(int frame, VoidCallback land) {
    if (!_stepping) {
      _steps.clear();
    }
    if (_pressHeld) {
      return;
    }
    final cut = _cut();
    if (cut == null ||
        _canvases.isEmpty ||
        _there(cut, frame) ||
        !_there(cut, _frame())) {
      _letGoOfTheOneWaiting();
      land();
      return;
    }
    final waiting = _waiting;
    if (waiting != null && waiting.cut == cut.id && waiting.frame == frame) {
      waiting.land = land;
      return;
    }
    final move = _waiting = _Move(cut: cut.id, frame: frame, land: land);
    _waitsFor.value = frame;
    _make(cut, move);
  }

  /// Whether every picture a canvas standing on [cut]'s [frame] shows is
  /// there, or will not come.
  bool _there(Cut cut, int frame) {
    final shown = standingPicturesOf(cut, frame, _placement());
    final over = shown.over;
    return _isThere(shown.frame) && (over == null || _isThere(over));
  }

  bool _isThere(DemandedPicture picture) =>
      _pictures().standingOf(picture).state != PictureState.toCome;

  /// Makes [move]'s pictures at once, and lands it once they are made.
  void _make(Cut cut, _Move move) {
    final pictures = _pictures();
    final shown = standingPicturesOf(cut, move.frame, _placement());
    unawaited(
      Future.wait([
        for (final picture in [shown.frame, ?shown.over])
          if (!_isThere(picture)) _madeNow(pictures, picture, move),
      ]).whenComplete(() {
        if (identical(_waiting, move)) {
          _landTheOneWaiting();
        }
      }),
    );
  }

  /// [picture] made now for [move] — given up where its making threw, as
  /// a screen's own making gives up (`FramePictureView`).
  Future<void> _madeNow(
    FramePictures pictures,
    DemandedPicture picture,
    _Move move,
  ) => pictures
      .makeShown(
        pictures.stackOf(picture),
        picture,
        shouldAbort: () => !identical(_waiting, move),
        // Kept as the canvas that goes to the frame keeps them where it
        // makes it itself (`FramePictureView`, a screen that draws live):
        // the pen's steps patch into them (🔬S5_BA cut 352, Surface Pro 11:
        // with the cels in hand p50 83–154 ms to the picture, 186 ms not
        // kept, 249 ms where the canvas made it itself, 11-18).
        keepsNodes: true,
      )
      .then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          pictures.noteFailure(picture);
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'stands with its picture',
              context: ErrorDescription('making the frame a move waits for'),
            ),
          );
        },
      );

  /// Lands the move that waits, and the steps in line walk on from where it
  /// does — where it lands: one whose cut was left meanwhile does not, and
  /// no step is counted from where it would have.
  void _landTheOneWaiting() {
    final waiting = _waiting;
    _letGoOfTheOneWaiting();
    if (waiting == null) {
      return;
    }
    if (_cut()?.id != waiting.cut) {
      _steps.clear();
      return;
    }
    waiting.land();
    _stepOnAfterTheFrame();
  }

  void _letGoOfTheOneWaiting() {
    _waiting = null;
    _waitsFor.value = null;
  }

  /// Lets go of the move that waits — its making may answer after this —
  /// of the steps in line, and of [waitsFor].
  void dispose() {
    _waiting = null;
    _steps.clear();
    _waitsFor.dispose();
  }
}

/// A move of the playhead that waits for its frame's pictures.
final class _Move {
  _Move({required this.cut, required this.frame, required this.land});

  final CutId cut;
  final int frame;

  /// What the move does once they are there — the last asked for it.
  VoidCallback land;
}

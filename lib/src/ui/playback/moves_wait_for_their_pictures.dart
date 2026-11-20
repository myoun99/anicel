import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

/// Where a playhead stands, or goes: place [at] of [scope] — a frame of a
/// cut on the canvas, a page of the document a viewer shows.
typedef PicturePlace = ({Object scope, int at});

/// 🚨★★★A PLAYHEAD THAT STANDS GOES TO A PLACE WITH ITS PICTURE (유저
/// 2026-11-18, the-standing-canvas-composes-a-frame-twice-before-its-
/// picture-Q1 = B 「임시 그리기를 뺀다」; 11-15 「재생헤드는 바꼈는데 화면이
/// 이전그림인 순간이 있는게 어긋나는거지」): a move of the playhead to a place
/// whose picture is not there leaves it standing on the place it shows —
/// and lands, all of it together, once the picture is. 🗣️Q2 = none 「따로
/// 표시하지 않는다」: standing where it was is the sign that it waits.
///
/// The law a run keeps (`playheadWay`, 유저 2026-10-15 F-365-Q1 「직전
/// 프레임에 서서 기다린다」), with its exception: where the place it stands
/// on shows no picture either — a cut a command opened, a file just opened
/// — there is nothing to stand on, and the move lands at once, the screen
/// waiting on the place itself. So does every move where nothing shows the
/// places ([shownBy]), or nothing stands ([PicturePlace] null).
///
/// 🚨A MOVE WAITS FOR ITS OWN MAKING, NOT FOR EVER: what it made lands it,
/// there or not — a picture its maker could not lay is the screen's to
/// wait on then. ↩️A screen that asked for its frame again for as long as
/// the frame would not come never came back (🔬2026-11-11,
/// `FramePictureView`).
///
/// 🗣️F-617 (유저 2026-11-19): 「법을 그냥 타임라인 플립이랑 똑같이 준비안되면
/// 이전 재생헤드에 서고 이전 그림 보여주게 통일」 — ONE law for the canvas
/// ([StandsWithItsPicture], its frames) and a viewer's pages
/// (`MediaRun.moves`). ↩️It was the canvas's alone, written
/// against its frame store.
class MovesWaitForTheirPictures {
  MovesWaitForTheirPictures({
    required PicturePlace? Function() stood,
    required bool Function(PicturePlace place) isThere,
    required Future<void> Function(
      PicturePlace place, {
      required bool Function() givenUp,
    })
    make,
  }) : _stood = stood,
       _isThere = isThere,
       _make = make;

  /// Where the playhead stands now — null where it stands nowhere.
  final PicturePlace? Function() _stood;

  /// Whether every picture a screen standing on a place shows is there, or
  /// will not come.
  final bool Function(PicturePlace place) _isThere;

  /// Makes a place's pictures at once, at the front of the line —
  /// answering once they are made, or given up: no longer wanted where
  /// [givenUp] says so.
  final Future<void> Function(
    PicturePlace place, {
    required bool Function() givenUp,
  })
  _make;

  /// The screens that stand on the playhead's place, showing its pictures.
  final Set<Object> _screens = Set.identity();

  /// The move that waits for its pictures, null while none does.
  _Move? _waiting;

  final ValueNotifier<int?> _waitsFor = ValueNotifier<int?>(null);

  /// The place a move waits for the pictures of — of [waiting]'s scope:
  /// where the playhead goes once they are there; null while none waits.
  ValueListenable<int?> get waitsFor => _waitsFor;

  /// The move that waits: where it was asked from, and where it goes —
  /// null while none waits.
  ({PicturePlace from, PicturePlace to})? get waiting => switch (_waiting) {
    final move? => (from: move.from, to: move.to),
    null => null,
  };

  /// Whether a press on the screen is held for the place a move waits for:
  /// it draws there once the move lands, from its first point (🗣️11-15 ①
  /// (나), as TVPaint does), and no other move goes under it meanwhile —
  /// the playhead never moves under a pen (R15-⑤).
  bool _pressHeld = false;

  /// [screen] stands on the playhead's place and shows its pictures — a
  /// move waits for them from now on.
  void shownBy(Object screen) => _screens.add(screen);

  /// [screen] no longer shows them: a move that waits lands where no other
  /// screen does, and no step in line is shown one at a time any more.
  void noLongerShownBy(Object screen) {
    _screens.remove(screen);
    if (_screens.isEmpty) {
      _steps.clear();
      _landTheOneWaiting();
    }
  }

  /// A press on the screen is held, or let go ([_pressHeld]).
  void holdsAPress({required bool held}) => _pressHeld = held;

  /// A press came on the screen: the steps in line go with it — the pen
  /// draws on the place it came on, or the one a move waits for, and the
  /// playhead does not walk on from under it once it is up. A press held
  /// for that place comes again as it is handed on to the screen, before
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
  /// land, each once the place it lands on is shown: the place it is
  /// counted from is that one. A move to a place ([moveToPlace], not a
  /// step's) leaves no step in line.
  ///
  /// 🗣️Q4 = 1 (11-18 14:05, 「누르고 있는 동안은 그림이 오는 속도로 걷고,
  /// 떼면 그 자리에 선다」): a [repeated] step — a key held, the OS's repeats
  /// of it — is not lined up. One that comes while a move waits goes; the
  /// next after the move lands takes the step after it.
  ///
  /// ↩️A step was counted from the place stood on: two pressed within one
  /// wait asked for the same place, and went one.
  ///
  /// A press that acts where the playhead stands is a step of its own —
  /// the cell a double click opens where the press before it moved
  /// (`activateCellOnDoubleTap`): taken in its turn, on the place that
  /// press lands on, never on the one stood on while it waits.
  ///
  /// 🗣️Q6 = turn (유저 2026-11-18 「차례를 기다린다」): so is every key —
  /// what the shortcut funnel acts on (`HomePage._invokeAction`), on the
  /// place the move before it lands on.
  void inTurn(VoidCallback walk, {required bool repeated}) {
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
  /// built: each step's place is shown.
  void _stepOnAfterTheFrame() {
    if (_steps.isEmpty || _stepsOn) {
      return;
    }
    _stepsOn = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _takeTheNextStep())
      ..ensureVisualUpdate();
  }

  /// Moves the playhead to [to]: [land] now, where its pictures are there
  /// or nothing shows them; once they are, else. The move after replaces
  /// it. [to] null is a place nothing stands for, landed at once.
  void moveToPlace(PicturePlace? to, VoidCallback land) {
    if (!_stepping) {
      _steps.clear();
    }
    if (_pressHeld) {
      return;
    }
    final stood = _stood();
    if (stood == null ||
        to == null ||
        _screens.isEmpty ||
        _isThere(to) ||
        !_isThere(stood)) {
      _letGoOfTheOneWaiting();
      land();
      return;
    }
    final waiting = _waiting;
    if (waiting != null && waiting.from == stood && waiting.to == to) {
      waiting.land = land;
      return;
    }
    final move = _waiting = _Move(from: stood, to: to, land: land);
    _waitsFor.value = to.at;
    unawaited(
      _make(
        to,
        givenUp: () => !identical(_waiting, move),
      ).whenComplete(() {
        if (identical(_waiting, move)) {
          _landTheOneWaiting();
        }
      }),
    );
  }

  /// Lands the move that waits, and the steps in line walk on from where it
  /// does — where it lands: one whose scope was left meanwhile does not,
  /// and no step is counted from where it would have.
  void _landTheOneWaiting() {
    final waiting = _waiting;
    _letGoOfTheOneWaiting();
    if (waiting == null) {
      return;
    }
    if (_stood()?.scope != waiting.from.scope) {
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

  /// Lets go of the move that waits, unlanded, and of the steps in line —
  /// the places it went among are gone (a viewer's document changed).
  void letGo() {
    _letGoOfTheOneWaiting();
    _steps.clear();
  }

  /// Lets go of the move that waits — its making may answer after this —
  /// of the steps in line, and of [waitsFor].
  void dispose() {
    _waiting = null;
    _steps.clear();
    _waitsFor.dispose();
  }
}

/// A move of the playhead that waits for its place's pictures.
final class _Move {
  _Move({required this.from, required this.to, required this.land});

  /// The place stood on as it was asked: it lands only from its scope.
  final PicturePlace from;

  /// The place it goes to.
  final PicturePlace to;

  /// What the move does once they are there — the last asked for it.
  VoidCallback land;
}

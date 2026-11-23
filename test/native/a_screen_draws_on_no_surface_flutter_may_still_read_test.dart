import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/screen_turns.dart';

/// Card the-galaxy-tab-canvas-went-slow-on-build-1095, risk 1 (관제
/// 2026-11-24): a screen draws its next frame on no surface Flutter's GPU
/// may still read — and where Flutter tells nothing of its reads, it
/// waits no more than the two surfaces alternated did (관제 02:4x: 「신호
/// 없는 판에서 매 프레임 그려도 기다림 0」).
void main() {
  late int now;
  late ScreenWaits counted;
  late List<int> unread;

  ScreenTurns turns(int surfaces) {
    now = 0;
    counted = ScreenWaits();
    unread = List.filled(surfaces, 0);
    return ScreenTurns(
      surfaces,
      unread: (surface) => unread[surface],
      micros: () => now,
      counted: counted,
    )..shown(0, 0);
  }

  test('🎯where Flutter tells nothing, a frame drawn at every paint never '
      'waits, and never lands on a surface a tree may still show', () {
    // The GPU done one to three frames after the paint that drew it: what
    // is up goes up between frames, as an event of the engine's does.
    for (final finishes in [0, 1, 2, 3]) {
      final screen = turns(3);
      final letGoAt = <int, int>{};
      var shown = 0;
      var drawn = 0;
      int? drawing;
      var upAt = 0;
      for (var frame = 1; frame <= 600; frame += 1) {
        now = frame * 16667;
        // Between the frame before and this one: the frame finished is up.
        if (drawing != null && frame - 1 >= upAt) {
          letGoAt[shown] = frame - 1;
          screen.shown(drawing, frame - 1);
          shown = drawing;
          drawing = null;
        }
        // At this frame's paint.
        if (drawing == null) {
          final surface = screen.take(frame);
          expect(surface, isNotNull, reason: 'finishes $finishes, $frame');
          expect(surface, isNot(shown));
          if (letGoAt[surface!] case final at?) {
            expect(frame, greaterThanOrEqualTo(at + 2));
          }
          drawing = surface;
          upAt = frame + finishes;
          drawn += 1;
        }
      }
      expect(counted.waits, 0, reason: 'finishes $finishes');
      expect(counted.readsPastTheBound, 0);
      expect(drawn, greaterThan(600 ~/ (finishes + 1) - 2));
    }
  });

  test('a surface let go of is drawn on once two frames of the app\'s have '
      'begun since — the tree that showed it submitted', () {
    final screen = turns(2);
    expect(screen.take(1), 1);
    screen.shown(1, 1);
    expect(screen.take(2), isNull, reason: 'its tree may be unsubmitted');
    expect(counted.waits, 1);
    expect(screen.wouldTake(2), isFalse);
    expect(screen.wouldTake(3), isTrue);
    now = 5000;
    expect(screen.take(3), 0);
    expect(counted.waitMicros, 5000);
    expect(screen.waiting, isFalse);
  });

  test('🎯a surface Flutter has still to read of is waited for till it is '
      'read — whatever frames went by that did not paint it', () {
    final screen = turns(3);
    expect(screen.take(1), 1);
    screen.shown(1, 1);
    expect(screen.take(2), 2);
    screen.shown(2, 2);
    // Surface 0, let go of at 1, was painted and not yet read; 1 was let go
    // of at 2. Ten frames that paint neither go by.
    unread[0] = 1;
    unread[1] = 1;
    for (var frame = 3; frame < 13; frame += 1) {
      now = frame * 1000;
      expect(screen.take(frame), isNull, reason: 'frame $frame');
    }
    expect(counted.waits, 1, reason: 'one wait, however often asked');
    unread[1] = 0;
    now = 13000;
    expect(screen.take(13), 1, reason: 'the one read');
    expect(counted.waitMicros, 10000);
    expect(counted.readsPastTheBound, 0);
  });

  test('a word that never comes is waited for no longer than the bound, '
      'and the frame past it is counted', () {
    final screen = turns(3);
    expect(screen.take(1), 1);
    screen.shown(1, 1);
    unread[0] = 2;
    unread[2] = 1;
    now = 1000;
    expect(screen.take(4), isNull);
    now = 1000 + ScreenTurns.readBoundMicros - 1;
    expect(screen.wouldTake(5), isFalse);
    expect(screen.take(5), isNull);
    now = 1000 + ScreenTurns.readBoundMicros;
    expect(screen.wouldTake(6), isTrue);
    // The one never up first: it was in no tree.
    expect(screen.take(6), 2);
    expect(counted.readsPastTheBound, 1);
    expect(counted.waits, 1);
    expect(counted.waitMicros, ScreenTurns.readBoundMicros);
  });

  test('the surface the widget names before any frame is up is not drawn '
      'on first', () {
    final screen = turns(3);
    expect(screen.take(0), isNot(0));
  });
}

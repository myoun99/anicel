import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';

/// F-28 — 유저 2026-08-27: 「플립이랑 화살표랑 **입구는 달라도 통하는건
/// 하나**니까 둘 다 적용해야하는거지」.
///
/// The frame axis is sideways on the timeline and downward on the X-sheet,
/// and every input that walks the sheet has to agree. This is that one
/// question; `CanvasViewportGestureLayer._flipsFrames` and the shell's arrow
/// walk both call it, which is the whole point — the two disagreed because
/// #1216 taught the flip to read the sheet and nobody told the arrows.
void main() {
  test('the TIMELINE reading: frames run sideways', () {
    final hud = FlipHudController()..framesRunVertically = false;
    addTearDown(hud.dispose);
    expect(
      hud.framesRunAlong(horizontal: true),
      isTrue,
      reason: '←→ walks drawings on a timeline',
    );
    expect(
      hud.framesRunAlong(horizontal: false),
      isFalse,
      reason: '↑↓ walks the row stack there',
    );
  });

  test('the X-SHEET reading: frames run down, so the two swap', () {
    final hud = FlipHudController()..framesRunVertically = true;
    addTearDown(hud.dispose);
    expect(
      hud.framesRunAlong(horizontal: false),
      isTrue,
      reason: '유저: 「세로가 프레임이동 가로가 레이어이동 되도록. 그게 '
          '직관적임」',
    );
    expect(hud.framesRunAlong(horizontal: true), isFalse);
  });

  test('a step ACROSS the frame axis walks the stack the way the sheet lays '
      'it out', () {
    final timeline = FlipHudController()..framesRunVertically = false;
    final xsheet = FlipHudController()..framesRunVertically = true;
    addTearDown(timeline.dispose);
    addTearDown(xsheet.dispose);
    expect(
      timeline.rowStepAcross(forward: true),
      1,
      reason: '↓ is the next row down the timeline',
    );
    expect(timeline.rowStepAcross(forward: false), -1);
    expect(
      xsheet.rowStepAcross(forward: true),
      -1,
      reason:
          '유저 2026-08-31: 「좌우가 방향이 반대임」 — the X-sheet lays the '
          'stack out right to left, so → is a step back through it',
    );
    expect(xsheet.rowStepAcross(forward: false), 1);
  });
}

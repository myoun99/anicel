import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';

/// F-377 (유저 2026-10-17): 「변형중 언두가 직전변형 취소라던가. 끝나면
/// 한번에 취소라던가 하듯이 변형 상태는 모두 기본적으로 그걸 따르도록」. A
/// canvas or the camera's frame adjusted on the canvas (I-79 · I-80) steps
/// back a grab at a time while it is open, as the transform box does —
/// and what it opened as is where the steps run out.
void main() {
  const cut = CutId('cut');
  const size = CanvasSize(width: 100, height: 80);
  CanvasEdgesDraft edges(double right) => CanvasEdgesDraft(
    cut: cut,
    edges: Rect.fromLTRB(0, 0, right, 80),
  );
  Rect? edgesOf(CanvasAdjust adjust) =>
      (adjust.draft as CanvasEdgesDraft?)?.edges;

  test('each grab let go is a step back, to where the one before let go, '
      'and the last is the edges it opened with', () {
    final adjust = CanvasAdjust()
      ..begin(CanvasEdgesDraft.of(cut, size))
      ..move(edges(120))
      ..move(edges(140));
    addTearDown(adjust.dispose);

    expect(adjust.canStepBack, isTrue);
    adjust.stepBack();
    expect(edgesOf(adjust), edges(120).edges);
    adjust.stepBack();
    expect(edgesOf(adjust), const Rect.fromLTRB(0, 0, 100, 80));
    expect(adjust.canStepBack, isFalse, reason: 'it stands as it opened');
    expect(adjust.isOpen, isTrue, reason: 'stepping back closes nothing');
  });

  test('a grab under way is no step, and a step back drops it', () {
    final adjust = CanvasAdjust()
      ..begin(CanvasEdgesDraft.of(cut, size))
      ..move(edges(120))
      ..show(edges(160));
    addTearDown(adjust.dispose);

    adjust.stepBack();

    expect(adjust.canStepBack, isFalse, reason: 'the shown edges were none');
    expect(edgesOf(adjust), const Rect.fromLTRB(0, 0, 100, 80));
    expect(adjust.shown, same(adjust.draft), reason: 'nothing left shown');
  });

  test('the camera\'s ratio picked on the pill is a step too', () {
    const opened = CameraSizeDraft(size: CanvasSize(width: 1920, height: 1000));
    final adjust = CanvasAdjust()
      ..begin(opened)
      ..move(opened.locked(CameraRatioLock.wide));
    addTearDown(adjust.dispose);

    adjust.stepBack();

    expect(adjust.draft, same(opened));
  });

  test('the steps go with the adjust: one opened again has none', () {
    final adjust = CanvasAdjust()
      ..begin(CanvasEdgesDraft.of(cut, size))
      ..move(edges(120))
      ..end();
    addTearDown(adjust.dispose);
    expect(
      adjust.canStepBack,
      isFalse,
      reason: 'closed, it has nothing an undo could open again',
    );

    adjust
      ..move(edges(120))
      ..move(edges(140));
    expect(adjust.canStepBack, isTrue, reason: '⛔premise: a grab to take');
    adjust.begin(CanvasEdgesDraft.of(cut, size));
    expect(adjust.canStepBack, isFalse, reason: 'begun over an open one');
  });
}

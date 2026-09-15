import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// F-28 — **the canvas flip reads its frame direction off the sheet.**
///
/// 유저 2026-08-24: 「타임라인패널 x시트일 경우, 플립 그냥 반전시키자. 세로가
/// 프레임이동 가로가 레이어이동 되도록. 그게 직관적임」.
///
/// ↩️This pinned the flip resolving the axis ITSELF — sideways fired
/// row-walk ids on the X-sheet. The shell asks the same question again when
/// those ids arrive, so on the X-sheet the answer flipped twice: 유저
/// 2026-08-31 실기: 「터치는 위아래 터치 조작이 여전히 레이어이동, 심각한건
/// 플립ui는 프레임이동의 ui 보여주고있음」. The gesture now fires the arrow
/// keys' DIRECTION ids on every sheet, and what the sheet decides is the
/// HUD's axis — the same question the shell's walk asks, answered once there.
void main() {
  const flipFingers = 3;

  setUp(() {
    // Whatever the machine's saved settings are, this test needs the finger
    // count it drives to BE the flip gesture.
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragThreeFingers: CanvasTouchDragAction.flip,
    );
  });

  Future<({List<String> actions, FlipHudAxis? axis})> flipDrag(
    WidgetTester tester, {
    required Offset travel,
    required bool framesRunVertically,
  }) async {
    final actions = <String>[];
    final hud = FlipHudController()..framesRunVertically = framesRunVertically;
    addTearDown(hud.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasViewportGestureLayer(
            viewport: CanvasViewport(),
            onViewportChanged: (_) {},
            onInvokeAction: actions.add,
            flipHud: hud,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    const origin = Offset(400, 300);
    final gestures = <TestGesture>[];
    for (var finger = 0; finger < flipFingers; finger += 1) {
      gestures.add(
        await tester.startGesture(origin + Offset(finger * 20.0, 0)),
      );
    }
    await tester.pump();
    for (final gesture in gestures) {
      await gesture.moveBy(travel);
      await tester.pump();
    }
    // The LIVE axis is dropped the moment the fingers lift.
    final axis = hud.axis;
    for (final gesture in gestures) {
      await gesture.up();
    }
    await tester.pumpAndSettle();
    return (actions: actions, axis: axis);
  }

  testWidgets('on the TIMELINE, sideways fires the sideways ids and the HUD '
      'shows frames', (tester) async {
    final flip = await flipDrag(
      tester,
      travel: const Offset(160, 0),
      framesRunVertically: false,
    );
    expect(
      flip.actions,
      isNotEmpty,
      reason: 'fixture premise: the drag crossed at least one step',
    );
    expect(flip.actions.every((id) => id.startsWith('drawing-')), isTrue);
    expect(flip.axis, FlipHudAxis.frame);
  });

  testWidgets('on the X-SHEET, sideways fires the SAME sideways ids — and the '
      'HUD shows rows', (tester) async {
    final flip = await flipDrag(
      tester,
      travel: const Offset(160, 0),
      framesRunVertically: true,
    );
    expect(flip.actions, isNotEmpty);
    expect(
      flip.actions.every((id) => id.startsWith('drawing-')),
      isTrue,
      reason: 'a direction, not a meaning: the shell reads the sheet once',
    );
    expect(flip.axis, FlipHudAxis.row);
  });

  testWidgets('and downward fires the downward ids there, with the HUD on '
      'frames', (tester) async {
    final flip = await flipDrag(
      tester,
      travel: const Offset(0, 160),
      framesRunVertically: true,
    );
    expect(flip.actions, isNotEmpty);
    expect(
      flip.actions.every((id) => id.startsWith('selection-nudge-')),
      isTrue,
    );
    expect(
      flip.axis,
      FlipHudAxis.frame,
      reason: '유저: 「세로가 프레임이동」 — the picture and the walk agree',
    );
  });

  testWidgets('while on the timeline downward fires the downward ids with the '
      'HUD on rows', (tester) async {
    final flip = await flipDrag(
      tester,
      travel: const Offset(0, 160),
      framesRunVertically: false,
    );
    expect(flip.actions, isNotEmpty);
    expect(
      flip.actions.every((id) => id.startsWith('selection-nudge-')),
      isTrue,
    );
    expect(flip.axis, FlipHudAxis.row);
  });
}

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton, kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🗣️R26 #34 (유저 2026-07-20): 「팬이 발동하는 숏컷(현 기본값인 2핑거
/// 드래그나 휠클릭)의 경우, 타임라인에서는 팬으로 작동하도록 로직공통화」 —
/// R26-rest-Q2 (2026-09-30): 「캔버스 설정을 그대로 따른다 — 「없음」이면
/// 거기서도 안 움직인다」. The canvas's pan — Space held, a mouse button
/// 「손바닥」 — moves the timeline and the conte panel the way it moves the
/// canvas.
void main() {
  tearDown(() {
    CanvasPanHold.held.value = false;
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  EditorSessionManager tallSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    for (var i = 0; i < 30; i++) {
      s.layerStack.addLayerOfKind(LayerKind.animation);
    }
    return s;
  }

  Future<void> pumpTimeline(WidgetTester tester, EditorSessionManager s) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: s,
            builder: (context, _) => TimelineTabHost(
              session: s,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition rows(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-vertical-scroll-viewport'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset by, {
    required int buttons,
  }) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await tester.pump();
    await gesture.moveBy(by / 2);
    await tester.pump();
    await gesture.moveBy(by / 2);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Offset gridMiddle(WidgetTester tester) => tester.getCenter(
    find.byKey(const ValueKey<String>('timeline-vertical-scroll-viewport')),
  );

  testWidgets('Space held: a drag on the timeline moves its rows with the '
      'hand, and seeks nothing', (tester) async {
    final s = tallSession();
    await pumpTimeline(tester, s);
    final frameBefore = s.currentFrameIndex;
    expect(rows(tester).pixels, 0, reason: 'the premise: at the top');

    CanvasPanHold.held.value = true;
    await tester.pump();
    await drag(
      tester,
      gridMiddle(tester),
      const Offset(0, -120),
      buttons: kPrimaryMouseButton,
    );

    expect(rows(tester).pixels, greaterThan(0), reason: 'dragged up = down');
    expect(s.currentFrameIndex, frameBefore);
  });

  testWidgets('a wheel click mapped to 「손바닥」 pans; left unmapped it does '
      'nothing', (tester) async {
    final s = tallSession();
    await pumpTimeline(tester, s);

    await drag(
      tester,
      gridMiddle(tester),
      const Offset(0, -120),
      buttons: kMiddleMouseButton,
    );
    expect(rows(tester).pixels, 0, reason: 'the wheel click is 「없음」');

    AppInput.settings.value = AppInput.settings.value.copyWith(
      canvasWheelClick: const CanvasPointerMapping(
        action: CanvasPointerAction.pan,
      ),
    );
    await tester.pump();
    await drag(
      tester,
      gridMiddle(tester),
      const Offset(0, -120),
      buttons: kMiddleMouseButton,
    );
    expect(rows(tester).pixels, greaterThan(0));
  });

  testWidgets('the conte panel pans the same way', (tester) async {
    final s = tallSession();
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: s,
            builder: (context, _) => StoryboardTabHost(
              session: s,
              pixelsPerFrame: 40,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.byKey(
      const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
    );
    ScrollPosition along() => tester
        .state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(along().maxScrollExtent, greaterThan(0), reason: 'the premise');
    final before = along().pixels;

    CanvasPanHold.held.value = true;
    await tester.pump();
    await drag(
      tester,
      tester.getCenter(strip),
      const Offset(-150, 0),
      buttons: kPrimaryMouseButton,
    );

    expect(along().pixels, greaterThan(before));
  });
}

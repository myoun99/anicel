import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// **F-8 — the layer area answers a finger the way the frame area does.**
///
/// 유저 2026-08-24: 「레이어영역도 프레임영역이랑 똑같이 선택범위 작동-드래그로
/// 통일되었으니, **터치로 스크롤할수있게** 사양 통일. 물론 통일이니까 **1핑거
/// 드로잉모드시 레이어 선택범위 작동**하게하는것도 통일적용되도록」
///
/// One switch answers both halves — [AppInput.timelineEditPanDevices], 결정
/// 10's set — and the rail's row drag already reads it. So this pins the
/// BEHAVIOUR rather than adding any: a finger scrolls the rail while the
/// timeline owns touch scrolling, and edits it the moment one finger is the
/// drawing hand.
void main() {
  Project project() => Project(
    id: const ProjectId('rail-touch'),
    name: 'Rail Touch',
    createdAt: DateTime.utc(2026, 8, 24),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'T',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              for (var i = 0; i < 14; i += 1)
                Layer(id: LayerId('l$i'), name: 'L$i', frames: const []),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
  }

  ScrollController railScroll(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey<String>('timeline-vertical-scroll-viewport')),
      )
      .controller!;

  Finder railRow(String id) =>
      find.byKey(ValueKey<String>('timeline-layer-row-$id'));

  Future<void> fingerDrag(WidgetTester tester, Finder at, Offset by) async {
    final gesture = await tester.startGesture(
      tester.getCenter(at),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 4; step += 1) {
      await gesture.moveBy(by / 4);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a finger on a LAYER row scrolls the rail', (tester) async {
    AppInput.settings.value = const AppInputSettings();
    await pump(tester);
    final controller = railScroll(tester);
    expect(
      controller.position.maxScrollExtent,
      greaterThan(0),
      reason: 'fixture premise: there is somewhere to scroll to',
    );

    await fingerDrag(tester, railRow('l13'), const Offset(0, -120));

    expect(
      controller.offset,
      greaterThan(0),
      reason:
          'the rail scrolls under a finger, exactly as the frame area '
          'beside it does — the row drag declines the device rather than '
          'swallowing it',
    );
  });

  testWidgets('fixture premise: the FRAME area beside it already did', (
    tester,
  ) async {
    // 🚨The measurement that found the cause: the same finger, one row's
    // width to the right, moved the list 90px. So the scroll view was
    // willing and something over the RAIL was taking the drag first.
    AppInput.settings.value = const AppInputSettings();
    await pump(tester);
    final controller = railScroll(tester);
    final rail = tester.getRect(railRow('l13'));
    final gesture = await tester.startGesture(
      Offset(rail.right + 80, rail.center.dy),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 4; step += 1) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('and in 1-finger DRAWING mode that same finger selects rows', (
    tester,
  ) async {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await pump(tester);
    final controller = railScroll(tester);
    final session = sessionOf(tester);
    expect(
      session.rowSelection.value.length,
      0,
      reason: 'nothing selected yet',
    );

    await fingerDrag(tester, railRow('l13'), const Offset(0, -120));

    expect(
      session.rowSelection.value.length,
      greaterThan(1),
      reason:
          '결정 10: a finger is a mouse when it draws, so the rail takes '
          'the range selection the mouse would have made',
    );
    expect(
      controller.offset,
      0,
      reason:
          'the cost the user named first — 「1핑거 드로잉에선 타임라인 '
          '스크롤 불가해지는거지 … 그걸 원해서 한 말이야」',
    );
  });
}

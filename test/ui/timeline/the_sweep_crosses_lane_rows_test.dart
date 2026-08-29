import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart' show LayerFxState;
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';

/// 🚨★★★A LANE ROW IS A ROW THE SWEEP CROSSES, AND IT HAS AN FX SWITCH.
///
/// 유저 2026-08-29: 「그건 **버튼이면 다 가능**하도록」.
///
/// The rail's row resolver used to answer null for lane rows, so a sweep
/// down the fx column stepped over every one it passed. That rule had a
/// source AND an expiry: `git log -S` puts it in c07cfa40 (#509), when the
/// sweep was THE EYE AND NOTHING ELSE and lane rows carried no eye. The
/// sweep later widened to columns (I-1) and lane rows grew an fx toggle of
/// their own; the exclusion outlived its reason.
///
/// ⛔The tell was that it contradicted the code's own rule — only rows with
/// NO control in a column are skipped, and a lane row has one.
void main() {
  testWidgets('🚨an fx sweep paints the LANE rows it crosses, not just the '
      'layer rows', (tester) async {
    // The WHOLE app: lane expansion is HomePage's state, so a bare
    // TimelineTabHost has no twirl to tap at all.
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final layerId = session.activeLayerId!;

    final laneToggle = find.byKey(
      ValueKey<String>('timeline-lane-toggle-$layerId'),
    );
    await tester.ensureVisible(laneToggle);
    await tester.pumpAndSettle();
    await tester.tap(laneToggle);
    await tester.pumpAndSettle();

    final layerFx = find.byKey(ValueKey<String>('timeline-layer-fx-$layerId'));
    final laneFx = find.byKey(
      ValueKey<String>('timeline-lane-group-fx-$layerId-transform-group'),
    );
    expect(layerFx, findsOneWidget, reason: 'the layer row carries fx');
    expect(
      laneFx,
      findsOneWidget,
      reason:
          'and so does the lane row — this is the whole premise, and the '
          'case would prove nothing on a rail where it did not',
    );

    // 🚨THE LANE ROW SITS BELOW ITS LAYER ROW, so a sweep begun on the
    // layer's fx and dragged DOWN crosses it. Measured rather than assumed:
    // if that ever stops being true the drag below aims at nothing.
    final from = tester.getCenter(laneFx);
    final to = tester.getCenter(layerFx);
    expect(
      from.dy,
      greaterThan(to.dy),
      reason: 'the lane row sits BELOW the layer row, so this drag runs UP',
    );
    expect(
      (to.dx - from.dx).abs(),
      lessThan(6),
      reason:
          'and in the SAME column — the sweep paints by column, so a lane '
          'fx sitting elsewhere would be a different question entirely',
    );

    // 🚨THE LAYER ROW'S OWN FX, read from the session. The sweep STARTS on
    // the lane row here, so the layer row is the one it CROSSES — and the
    // lane row could not begin a sweep at all until its button took the
    // claim, which is the other half of this round.
    //
    // ⛔The lane button's TOOLTIP was measured first and it is a SHADOW: it
    // moves with the layer's fx, so a mutant that restored the lane
    // exclusion survived on it. So did `layer.transformEnabled`, which the
    // master switch writes too. 「내가 지금 세는 게 X인가, X의 그림자인가」.
    LayerFxState layerFxState() => session.layerFxState(layerId);
    final before = layerFxState();

    // 🚨MOUSE, not the default touch: a finger is not in
    // [AppInput.timelineEditPanDevices] unless one-finger drawing is on, so
    // a touch gesture here measures nothing at all (it did).
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(
        Offset(from.dx, from.dy + (to.dy - from.dy) * step / 6),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      layerFxState(),
      isNot(before),
      reason:
          'the sweep crossed this lane row and it carries the same column — '
          '유저: 「버튼이면 다 가능하도록」. It was skipped by a rule written '
          'when the sweep was the eye alone',
    );
  });
}

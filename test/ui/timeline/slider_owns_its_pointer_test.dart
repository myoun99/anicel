import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨T11 (유저 2026-08-13): 「불투명도 조절시, 제스쳐가 가끔 행 선택이
/// 작동해버림. 불편한데 **원리적인 해결 가능한가**?」 · 「**마우스**, 드래그는
/// 슬라이더위에서 작동시키다가 **제스쳐끊기고 레이어선택 작동**해버렷던거같음」.
///
/// 🔴**THESE PIN THE CURRENT BEHAVIOUR. THEY DO NOT GUARD THE REPORT.**
///
/// The report has not been reproduced here, across three attempts — touch,
/// stylus, and now mouse with a diagonal first move. In every one of them the
/// slider keeps its pointer and no row selection begins. What IS in the code
/// is a real race:
///
///  * the slider is a HORIZONTAL drag — it measures `|dx|` alone;
///  * the row is an EAGER PAN — it measures the vector LENGTH, and it is
///    "eager" precisely because it lowered its threshold to a hit slop.
///
/// Both thresholds are `computeHitSlop` (1px for a mouse, 18px otherwise), so
/// on paper a first move of (1, 1) gives the pan √2 against the slider's 1.
/// In practice the slider's recognizer is the deeper one and resolves the
/// arena first on the same event, which is why it keeps winning here.
///
/// ⚠️So do not "fix" this from the code alone. The app has the instrument
/// already: `EagerPanGestureRecognizer` prints `ep acc`/`ep rej` with the
/// distance and the threshold at the moment of the verdict, and the Input
/// Inspector (top strip ▸ Input Inspector) shows them. One reproduction with
/// it open says whether the pan accepted at all.
///
/// ⛔And do not reach for "the row may only start on a drag ALONG the rail":
/// the sideways nudge below is how a single row is selected, so that rule
/// removes a feature along with the bug. That was tried and reverted.
void main() {
  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  testWidgets('a MOUSE drag on a row\'s opacity slider adjusts the value and '
      'starts no row selection', (tester) async {
    final session = await pump(tester);
    final layerId = session.activeLayer!.id;
    final slider = find.byKey(
      ValueKey<String>('timeline-layer-opacity-$layerId'),
    );
    expect(slider, findsOneWidget);
    expect(session.rowSelection.value, isEmpty);
    final opacityBefore = session.activeLayer!.opacity;

    final gesture = await tester.startGesture(
      tester.getCenter(slider),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // The first move is DIAGONAL, which on a mouse is all it takes: the pan's
    // length crosses 1px before the slider's |dx| does.
    await gesture.moveBy(const Offset(-6, 4));
    await tester.pump();
    await gesture.moveBy(const Offset(-18, -2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      session.rowSelection.value,
      isEmpty,
      reason: 'the pointer went down on the slider; the row it is drawn in '
          'must not take it away mid-drag',
    );
    expect(
      session.activeLayer!.opacity,
      lessThan(opacityBefore),
      reason: 'and the slider still did its own job',
    );
  });

  testWidgets('a drag that starts on the ROW still selects it — the fix is '
      'about WHOSE pointer it is, not about direction', (tester) async {
    final session = await pump(tester);
    final layerId = session.activeLayer!.id;
    final row = find.byKey(ValueKey<String>('timeline-layer-row-$layerId'));
    expect(row, findsOneWidget);

    // The sideways nudge: the rail counts only its own axis as travel, so
    // this selects exactly the row it began on. ⛔It is why a "the row only
    // starts on a drag ALONG the rail" rule was rejected for T11 — that would
    // have taken the single-row selection away along with the bug.
    await tester.drag(row, const Offset(30, 0));
    await tester.pumpAndSettle();

    expect(session.rowSelection.value, isNotEmpty);
  });
}

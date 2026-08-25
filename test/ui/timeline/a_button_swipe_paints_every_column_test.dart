import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
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

/// **I-1 — a row button's swipe is about the COLUMN, not about the eye.**
///
/// 유저 2026-08-24: 「레이어의 버튼 조작하는거 **일괄조작**하는 기능 넣고싶음
/// … 탭 다운 한 채로 아래로 드래그하면 **해당 다른 레이어도 버튼조작**되도록.
/// 즉 여러 레이어 드래그하면서 **비지블버튼 off**한다거나 그런느낌」
///
/// The Krita-style paint-swipe existed for the EYE alone, with the eye's
/// x-range typed into the widget that owned it. The swipe was never about
/// the eye — so the column is the argument now, and the rail lists the
/// toggle columns it has.
void main() {
  Project project() => Project(
    id: const ProjectId('swipe'),
    name: 'Swipe',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (var i = 0; i < 5; i += 1)
                Layer(id: LayerId('l$i'), name: 'L$i', frames: const []),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    return sessionOf(tester);
  }

  /// Presses the button on [fromKey] and drags DOWN across [rows] rows.
  Future<void> swipeDown(
    WidgetTester tester,
    String fromKey, {
    required int rows,
  }) async {
    final start = tester.getCenter(find.byKey(ValueKey<String>(fromKey)));
    final rowHeight = tester
        .getRect(find.byKey(const ValueKey<String>('timeline-layer-row-l4')))
        .height;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= rows; step += 1) {
      await gesture.moveBy(Offset(0, rowHeight));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  List<bool> visibility(EditorSessionManager s) => [
    for (final layer in s.requireActiveCut.layers) layer.isVisible,
  ];

  testWidgets('the EYE column still paints down the rows', (tester) async {
    final s = await pump(tester);
    expect(visibility(s).every((on) => on), isTrue, reason: 'premise');

    // The rail renders the stack reversed, so l4 is the TOP row: a downward
    // swipe from it crosses l3, l2, …
    await swipeDown(tester, 'timeline-layer-visibility-l4', rows: 2);

    final hidden = [
      for (final layer in s.requireActiveCut.layers)
        if (!layer.isVisible) layer.id.value,
    ];
    expect(
      hidden.length,
      greaterThan(1),
      reason: 'the swipe painted more than the row it started on',
    );
  });

  testWidgets('and so does the ONION column — the swipe is the column\'s, '
      'not the eye\'s', (tester) async {
    final s = await pump(tester);
    expect(
      s.onionSkinLayerIds.value,
      isEmpty,
      reason: 'premise: nothing ghosting yet',
    );

    await swipeDown(tester, 'timeline-layer-onion-l4', rows: 2);

    expect(
      s.onionSkinLayerIds.value.length,
      greaterThan(1),
      reason: 'I-1: 「타임시트버튼이든 뭐 그런것들」 — every toggle column, '
          'not the one that happened to be built first',
    );
  });

  testWidgets('⛔a swipe that starts between columns paints nothing', (
    tester,
  ) async {
    final s = await pump(tester);
    final row = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-row-l4')),
    );
    // The NAME area — a place to grab the row by, never a column.
    final gesture = await tester.startGesture(
      Offset(row.left + 40, row.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 2; step += 1) {
      await gesture.moveBy(Offset(0, row.height));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(visibility(s).every((on) => on), isTrue);
    expect(s.onionSkinLayerIds.value, isEmpty);
  });
}

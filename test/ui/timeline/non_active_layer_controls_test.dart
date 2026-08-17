import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨★★★ 유저 #1 (2026-08-14): 「액티브 레이어가 아닌 **다른 레이어의 버튼
/// 누르면 작동안함.** 불투명도 슬라이더는 **한번 움직이고 드래그가 풀림.**
/// 액티브 레이어만 작용같은 규칙 두지말고 **자유롭게 가능하도록.** 레이어에
/// 있는 **모든 버튼이나 편집이** 그럼」
///
/// ★The scope is 「모든 버튼」, so this is a law rather than one button —
/// a rail row's controls act on the row they are drawn on, whichever row
/// the drawing target happens to be.
///
/// 🚨B3 (유저 2026-08-17): 「비지블·불투명도만 구현돼 있음. 나머지 버튼 전부
/// 완성」 — the eye and the slider were the only two claiming their press;
/// every other control of the row is driven here now, each with the same
/// two-part pin: the action lands on THAT row's layer, and the drawing
/// target does not move.
void main() {
  Future<EditorSessionManager> pumpRail(
    WidgetTester tester, {
    EditorSessionManager? existing,
    ValueChanged<LayerId>? onToggleLayerLanes,
  }) async {
    final session =
        existing ??
        (EditorSessionManager(initialProject: createDefaultProject())
          ..addLayerOfKind(LayerKind.animation));
    if (existing == null) {
      addTearDown(session.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              onToggleLayerLanes: onToggleLayerLanes,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  /// The animation row that is NOT the drawing target — the row every
  /// control below is pressed on.
  LayerId otherAnimationRow(EditorSessionManager session) => session.layers
      .firstWhere(
        (layer) =>
            layer.kind == LayerKind.animation &&
            layer.id != session.activeLayerId,
      )
      .id;

  testWidgets('a NON-active layer\'s visibility button works on the first '
      'press', (tester) async {
    final session = await pumpRail(tester);

    // The row that is NOT the drawing target.
    final other = session.layers
        .map((layer) => layer.id)
        .firstWhere((id) => id != session.activeLayerId);
    final before = session.layers.firstWhere((l) => l.id == other).isVisible;

    await tester.tap(
      find.byKey(ValueKey<String>('timeline-layer-visibility-$other')),
    );
    await tester.pumpAndSettle();

    expect(
      session.layers.firstWhere((l) => l.id == other).isVisible,
      !before,
      reason:
          'the press landed on that row\'s button and did nothing — 「액티브 '
          '레이어만 작용같은 규칙 두지말고」',
    );
  });

  testWidgets('and it did not need to steal the drawing target to do it', (
    tester,
  ) async {
    final session = await pumpRail(tester);
    final active = session.activeLayerId;
    final other = session.layers
        .map((layer) => layer.id)
        .firstWhere((id) => id != active);

    await tester.tap(
      find.byKey(ValueKey<String>('timeline-layer-visibility-$other')),
    );
    await tester.pumpAndSettle();

    // ⚠️Pinned deliberately. If the button only works BECAUSE the press
    // first made that row active, the row rebuilds under the gesture — and
    // that is the other half of the report: 「슬라이더는 한번 움직이고
    // 드래그가 풀림」.
    expect(
      session.activeLayerId,
      active,
      reason: 'pressing a row control moved the drawing target',
    );
  });

  // B3: the rest of the row, control by control. Each test drives a real
  // tap on a NON-active row and pins BOTH halves at once: the action lands
  // on that row's layer, and the drawing target does not move.
  group('B3 — every row control operates on a NON-active row', () {
    testWidgets('timesheet toggle', (tester) async {
      final session = await pumpRail(tester);
      final active = session.activeLayerId;
      final other = otherAnimationRow(session);
      final before = session.layers
          .firstWhere((l) => l.id == other)
          .onTimesheet;

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-timesheet-$other')),
      );
      await tester.pumpAndSettle();

      expect(
        session.layers.firstWhere((l) => l.id == other).onTimesheet,
        !before,
        reason: 'the timesheet toggle did not land on its own row',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('color mark chip', (tester) async {
      final session = await pumpRail(tester);
      final active = session.activeLayerId;
      final other = otherAnimationRow(session);

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-mark-$other')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('layer-mark-option-red')),
      );
      await tester.pumpAndSettle();

      expect(
        session.layers.firstWhere((l) => l.id == other).mark,
        LayerMark.red,
        reason: 'the mark pick did not land on its own row',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('fx master switch', (tester) async {
      final session = await pumpRail(tester);
      final active = session.activeLayerId;
      final other = otherAnimationRow(session);
      expect(session.layerFxState(other), LayerFxState.on);

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-fx-$other')),
      );
      await tester.pumpAndSettle();

      expect(
        session.layerFxState(other),
        LayerFxState.off,
        reason: 'the fx switch did not land on its own row',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('onion-skin toggle', (tester) async {
      final session = await pumpRail(tester);
      final active = session.activeLayerId;
      final other = otherAnimationRow(session);
      expect(session.isLayerOnionSkinEnabled(other), isFalse);

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-onion-$other')),
      );
      await tester.pumpAndSettle();

      expect(
        session.isLayerOnionSkinEnabled(other),
        isTrue,
        reason: 'the onion toggle did not land on its own row',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('fill-reference toggle', (tester) async {
      final session = await pumpRail(tester);
      final active = session.activeLayerId;
      final other = otherAnimationRow(session);
      final before = session.layers
          .firstWhere((l) => l.id == other)
          .isFillReference;

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-fill-reference-$other')),
      );
      await tester.pumpAndSettle();

      expect(
        session.layers.firstWhere((l) => l.id == other).isFillReference,
        !before,
        reason: 'the fill-reference toggle did not land on its own row',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('blend-mode chip', (tester) async {
      final session = await pumpRail(tester);
      final active = session.activeLayerId;
      final other = otherAnimationRow(session);

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-blend-$other')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('timeline-layer-blend-option-multiply'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        session.layers.firstWhere((l) => l.id == other).blendMode,
        LayerBlendMode.multiply,
        reason: 'the blend pick did not land on its own row',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('property-lane twirl', (tester) async {
      final toggled = <LayerId>[];
      final session = await pumpRail(
        tester,
        onToggleLayerLanes: toggled.add,
      );
      final active = session.activeLayerId;
      final other = otherAnimationRow(session);

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-lane-toggle-$other')),
      );
      await tester.pumpAndSettle();

      expect(
        toggled,
        [other],
        reason: 'the lane twirl did not land on its own row',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('folder fold twirl', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      // A folder around the new layer, then stand OUTSIDE it: the twirl is
      // pressed on a row that is neither active nor holding the active.
      session.addLayerOfKind(LayerKind.animation);
      session.groupActiveLayerIntoFolder();
      final folder = session.layers
          .firstWhere((l) => l.kind == LayerKind.folder)
          .id;
      final outside = session.layers
          .firstWhere(
            (l) => l.kind == LayerKind.animation && l.folderId == null,
          )
          .id;
      session.selectLayer(outside);
      await pumpRail(tester, existing: session);
      expect(session.activeLayerId, outside);

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-folder-twirl-$folder')),
      );
      await tester.pumpAndSettle();

      expect(
        session.layers.firstWhere((l) => l.id == folder).collapsed,
        isTrue,
        reason: 'the fold twirl did not land on its own row',
      );
      expect(
        session.activeLayerId,
        outside,
        reason: 'pressing a row control moved the drawing target',
      );
    });

    testWidgets('SE speaker opens the mixer without stealing the target', (
      tester,
    ) async {
      final session = await pumpRail(tester);
      final active = session.activeLayerId;
      final se = session.layers.firstWhere((l) => l.kind == LayerKind.se).id;

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-mute-$se')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('se-layer-mixer')),
        findsOneWidget,
        reason: 'the speaker did not open its own row\'s mixer',
      );
      expect(
        session.activeLayerId,
        active,
        reason: 'pressing a row control moved the drawing target',
      );
    });
  });
}

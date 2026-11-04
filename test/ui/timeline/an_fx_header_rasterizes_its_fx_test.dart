import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/project_lookup.dart'
    show requireLayerAnywhere;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/wait_window.dart';

/// 🗣️I-120-Q10 「A」 (유저 2026-11-04): RASTERIZE stands in the EYE column
/// of every fx group header and the Transform's — a header has no eye —
/// its tooltip naming the fx (「fx 이름 래스터라이즈」); and Q8 「폴더 · 조정 레이어 둘 다
/// 버튼이 꺼진다」: there, lit off in its place.
void main() {
  Future<EditorSessionManager> theApp(WidgetTester tester) async {
    // The WHOLE app: the lanes are HomePage's state.
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
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  String buttonOf(LayerId row, String header) =>
      'timeline-lane-group-rasterize-$row-$header';

  RailGlyphButton button(WidgetTester tester, String name) =>
      tester.widget<RailGlyphButton>(find.named(name));

  testWidgets('🎯an fx header\'s button, and the Transform\'s, stand lit on '
      'a drawing row — pressed, the fx is baked in one undo step', (
    tester,
  ) async {
    final session = await theApp(tester);
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    await tester.pumpAndSettle();
    final row = session.activeLayerId!;
    final blur = _rowOf(session, row).effects.single.id;
    final fx = buttonOf(row, effectGroupLaneId(blur));
    session.effectsAndFx.updateLayerEffects(row, [
      LayerEffect(
        id: blur,
        kind: EffectKind.blur,
        parameters: {'blurriness': EffectParameter(value: 12)},
      ),
    ]);
    await tester.pumpAndSettle();

    expect(button(tester, buttonOf(row, 'transform-group')).onPressed,
        isNotNull);
    expect(button(tester, fx).onPressed, isNotNull);
    expect(button(tester, fx).tooltip, contains('Blur'));

    final before = session.historyManager.undoCount;
    await tester.ensureVisible(find.named(fx));
    await tester.pumpAndSettle();
    await tester.tap(find.named(fx));
    await settleBehindTheWaitWindow(
      tester,
      () =>
          session.historyManager.undoCount == before + 1 &&
          find
              .byKey(const ValueKey<String>('fx-rasterize-progress'))
              .evaluate()
              .isEmpty,
    );

    expect(
      _rowOf(session, row).effects.single,
      LayerEffect(id: blur, kind: EffectKind.blur),
      reason: 'it stays, at its defaults',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a folder\'s fx header holds the button lit off (Q8)', (
    tester,
  ) async {
    final session = await theApp(tester);
    session.layerStack.addLayerOfKind(LayerKind.folder);
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    await tester.pumpAndSettle();
    final folder = session.activeLayerId!;
    final blur = _rowOf(session, folder).effects.single.id;

    expect(
      button(tester, buttonOf(folder, effectGroupLaneId(blur))).onPressed,
      isNull,
    );
  });
}

/// The row as the project holds it now — what every write lands in.
Layer _rowOf(EditorSessionManager session, LayerId id) =>
    requireLayerAnywhere(session.repository.requireProject(), id);

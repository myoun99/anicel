import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/fx_basis.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/project_lookup.dart'
    show requireLayerAnywhere;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;

import '../../helpers/named_finders.dart';

/// 🗣️AN FX HEADER'S CHIP PICKS WHAT ITS GROUP READS ITS KEYS BY (I-120-Q10:
/// 「프레임/블록 고르는거 리스트팝오버로」 — the blend chip's list, in the
/// blend column) — an effect's for that effect, the Transform's for the
/// row's transform, each one undo step.
void main() {
  Future<_Row> aBlurredRow(WidgetTester tester) async {
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
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    await tester.pumpAndSettle();
    final row = session.activeLayerId!;
    return (
      session: session,
      row: row,
      blur: _rowOf(session, row).effects.single.id,
    );
  }

  Future<void> pick(
    WidgetTester tester,
    String chip,
    FxBasis basis,
  ) async {
    await tester.ensureVisible(find.named(chip));
    await tester.pumpAndSettle();
    await tester.tap(find.named(chip));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('$chip-option-${basis.name}')),
    );
    await tester.pumpAndSettle();
  }

  String chipOf(_Row f, String header) =>
      'timeline-lane-group-basis-${f.row}-$header';

  testWidgets('an effect\'s chip sets that effect\'s basis — not the '
      'transform\'s — and one undo puts it back', (tester) async {
    final f = await aBlurredRow(tester);
    final before = f.session.historyManager.undoCount;

    await pick(tester, chipOf(f, effectGroupLaneId(f.blur)), FxBasis.block);

    expect(_blurOf(f).basis, FxBasis.block);
    expect(_rowOf(f.session, f.row).transformBasis, FxBasis.frame);
    expect(f.session.historyManager.undoCount, before + 1);
    f.session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(_blurOf(f).basis, FxBasis.frame);
  });

  testWidgets('the Transform\'s chip sets the row\'s transform basis, and '
      'one undo puts it back', (tester) async {
    final f = await aBlurredRow(tester);
    final before = f.session.historyManager.undoCount;

    await pick(tester, chipOf(f, 'transform-group'), FxBasis.block);

    expect(_rowOf(f.session, f.row).transformBasis, FxBasis.block);
    expect(_blurOf(f).basis, FxBasis.frame);
    expect(f.session.historyManager.undoCount, before + 1);
    f.session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(_rowOf(f.session, f.row).transformBasis, FxBasis.frame);
  });

  testWidgets('a pick of what the group already reads writes nothing', (
    tester,
  ) async {
    final f = await aBlurredRow(tester);
    final before = f.session.historyManager.undoCount;

    await pick(tester, chipOf(f, effectGroupLaneId(f.blur)), FxBasis.frame);
    await pick(tester, chipOf(f, 'transform-group'), FxBasis.frame);

    expect(f.session.historyManager.undoCount, before);
  });
}

typedef _Row = ({EditorSessionManager session, LayerId row, EffectId blur});

/// The row as the project holds it now — what every write lands in.
Layer _rowOf(EditorSessionManager session, LayerId id) =>
    requireLayerAnywhere(session.repository.requireProject(), id);

LayerEffect _blurOf(_Row f) => _rowOf(
  f.session,
  f.row,
).effects.singleWhere((effect) => effect.id == f.blur);

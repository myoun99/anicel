import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart'
    show storyboardLayerForCut;

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/home_page_probes.dart';
import '../storyboard_conte_row_probe.dart';

/// 🗣️F-369 (유저 2026-10-16): 「콘티패널에서 콘티행에 +같은거 눌러서
/// 콘티레이어 생성될때, 컷 들어가면 액션섹션의 젤 위에 생성되는데 그게아니라
/// 젤 밑에 생성되도록」 — a cut's conte row is born at the bottom of ACTION,
/// the stack's first row, from every door that makes one: the conte row's
/// `+` and Add Layer's conte entry (here), and a first stroke on a cut that
/// has none (a_picture_of_a_cut_with_no_conte_row_test).
///
/// [conteTrackProject]'s cut-2 has no conte row and one drawing row, so the
/// row stood on is the bottom one: above it — where they went — is not the
/// bottom.
void main() {
  const cut2 = CutId('cut-2');
  const cel2 = LayerId('cut-2-cel');

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Cut cutOf(EditorSessionManager session, CutId id) =>
      session.repository.requireProject().tracks.single.cuts.singleWhere(
        (cut) => cut.id == id,
      );

  Future<EditorSessionManager> pumpStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: conteTrackProject())),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    return sessionOf(tester);
  }

  testWidgets('the conte row\'s + makes the cut\'s conte layer at the bottom '
      'of ACTION', (tester) async {
    final session = await pumpStoryboard(tester);
    expect(storyboardLayerForCut(cutOf(session, cut2)), isNull);

    final plate = conteCreatePlates(tester, conteTrackId.value).single;
    await tester.tapAt(
      tester.getTopLeft(conteCreateFinder(conteTrackId.value)) +
          plate.center,
    );
    await tester.pumpAndSettle();

    final cut = cutOf(session, cut2);
    final conte = storyboardLayerForCut(cut);
    expect(conte, isNotNull, reason: 'the + made it');
    expect(cut.layers.first.id, conte!.id, reason: 'the stack\'s first row');
    expect(cut.layers[1].id, cel2, reason: 'under the drawing row');
    expect(conte.folderId, isNull);
  });

  testWidgets('Add Layer\'s conte entry makes it there too, under the row it '
      'stands on', (tester) async {
    final session = await pumpStoryboard(tester);
    session.selectCut(cut2);
    session.selectLayer(cel2);
    await tester.pumpAndSettle();

    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    await tester.pumpAndSettle();

    final cut = cutOf(session, cut2);
    expect(cut.layers.first.id, storyboardLayerForCut(cut)!.id);
    expect(cut.layers[1].id, cel2);
  });
}

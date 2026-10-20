import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️F-359 (유저 2026-10-14): 「콘티패널에서 s행선택하고 삭제/편집버튼
/// 활성화안됨. 타임라인패널은 되는데. 그러니 통일하고 추가로 s행은 삭제창통해
/// 삭제해도 삭제가안됨」 — a selected S row is the shared pill's ROWS rung on
/// both panels, and the delete that rung confirms takes it off its track.
void main() {
  late EditorSessionManager s;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
    // A third S row: the track keeps two (S1 · S2), so one may go.
    s.selectLayer(
      s.layers.firstWhere((layer) => layer.kind == LayerKind.se).id,
    );
    s.layerStack.addLayerOfKind(LayerKind.se);
  });
  tearDown(() => s.dispose());

  List<LayerId> sRows() => [
    for (final row in s.repository.requireProject().tracks.single.seLayers)
      row.id,
  ];

  void select(List<LayerId> ids) =>
      s.rowSelection.value = [for (final id in ids) LayerRowAddress(id)];

  test('both panels light Delete and Edit on a selected S row', () {
    expect(sRows(), hasLength(3), reason: '⛔전제');
    select([sRows().last]);

    final timeline = TimelineToolbarPanelContext(s);
    final storyboard = StoryboardToolbarPanelContext(s);
    expect(timeline.deleteSubject, PillSubject.layers);
    expect(storyboard.deleteSubject, PillSubject.layers);
    expect(timeline.canEditInstance, isTrue);
    expect(storyboard.editTarget, isA<StoryboardEditRows>());
  });

  test('the delete takes the S row off its track — one undo puts it back', () {
    final going = sRows().last;
    select([going]);

    s.deleteSelectionSubject();

    expect(sRows(), hasLength(2));
    expect(sRows(), isNot(contains(going)));
    s.undo();
    expect(sRows(), contains(going));
  });

  test('the storyboard\'s press deletes it too', () {
    final going = sRows().last;
    select([going]);

    StoryboardToolbarPanelContext(s).deleteSelectionSubject();

    expect(sRows(), isNot(contains(going)));
  });

  test('two S rows selected over the floor of two: one goes, two stay', () {
    select(sRows().sublist(1));

    s.deleteSelectionSubject();

    expect(sRows(), hasLength(2), reason: 'the track keeps S1 · S2\'s two');
  });
}

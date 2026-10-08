import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨F-292 (유저 2026-10-05): 「어태치 레이어 생성시 이미 있는 레이어가
/// 생성되기도함. A랑 A-2만 있을때 추가하면 A-2가 만들어짐. 이유는 모르겠는데.
/// 그래서 ABCD라는 이름을 나눠쓰는 규칙 그대로 쓰면서 통일할거 통일해서
/// 제대로 순서대로 생성하도록」.
///
/// The number was the side's COUNT plus one. Take a row away and the count
/// names a row that is still there. The rule itself is pinned on the
/// function (`models/attached_layer_resolve_test.dart`); this is the user's
/// own sequence, through the door that makes the row.
void main() {
  test('A with only A-2 left: the next row below is A-1, and no two rows '
      'wear one name', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!;
    List<String> names() => [
      for (final layer in s.requireActiveCut.layers) layer.name,
    ];

    s.folders.addAttachedLayer(AttachedPlacement.below);
    final first = s.activeLayer!;
    s.selectLayer(base.id);
    s.folders.addAttachedLayer(AttachedPlacement.below);
    expect(
      [first.name, s.activeLayer!.name],
      ['${base.name}-1', '${base.name}-2'],
      reason: '⛔전제: two rows below, numbered as they came',
    );
    s.selectLayer(first.id);
    s.layerVerbs.deleteActiveLayer();
    expect(names(), isNot(contains('${base.name}-1')), reason: '⛔전제');

    s.selectLayer(base.id);
    s.folders.addAttachedLayer(AttachedPlacement.below);

    expect(s.activeLayer!.name, '${base.name}-1');
    expect(names().toSet(), hasLength(names().length));
  });
}

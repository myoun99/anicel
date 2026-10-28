import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/visibility_solo.dart';

/// 🚨F-470 — SOLOING A ROW THAT CLIPS SHOWS ITS BASE.
///
/// 유저 2026-10-25: 「활성레이어 솔로, 클리핑 기능이 작동하는 레이어에 솔로시
/// 지금 한 행만 보여서 그림이 사라지는데, 클튜나 포토샵 확인한 바로는
/// 보여야할것들이 보임. 즉 a,b,c가 아래서부터 위로 있고, b랑c 둘다 클리핑
/// 적용된 상황이라면, a를 솔로하면 지금처럼 a만보이는데, b를 솔로하면 b랑 a랑
/// 남아서 보임. c를 솔로하면 a랑 c랑 남아서 보임.」
///
/// ↩️The solo showed the row alone, and a row that clips shows only where its
/// base has pixels — so it showed nothing.
void main() {
  /// Held by its own type — `tool/mutation_run.dart` picks a file's
  /// witnesses by which tests IMPORT it.
  VisibilitySolo soloOf(EditorSessionManager s) => s.visibilitySolo;

  const a = LayerId('clip-a');
  const b = LayerId('clip-b');
  const c = LayerId('clip-c');

  Layer rowOf(LayerId id, {bool clips = false, LayerId? folderId}) => Layer(
    id: id,
    name: id.value,
    frames: const [],
    timeline: const {},
    clipsToBelow: clips,
    folderId: folderId,
  );

  /// [rows] stacked bottom-up over the drawing row.
  EditorSessionManager stacked(List<Layer> rows) {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    final at = cut.layers.indexWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    for (final (i, row) in rows.indexed) {
      s.repository.insertLayer(cutId: cut.id, layer: row, index: at + 1 + i);
    }
    expect(
      folderStructureProblem(s.requireActiveCut.layers),
      isNull,
      reason: 'the premise: a well-formed stack',
    );
    s.refreshAfterCutCommand();
    return s;
  }

  /// a · b · c bottom-up, b and c clipping — the user's stack.
  EditorSessionManager theUsersStack() =>
      stacked([rowOf(a), rowOf(b, clips: true), rowOf(c, clips: true)]);

  /// The rows shown, of those the solo answers for — not the camera, whose
  /// eye is the camera view (F-363-Q2).
  Set<LayerId> shownIn(EditorSessionManager s) => {
    for (final layer in s.requireActiveCut.layers)
      if (layer.kind.hasPictureEye && layer.isVisible) layer.id,
  };

  test('soloing the base shows it alone — not what clips to it', () {
    final s = theUsersStack();
    s.selectLayer(a);

    soloOf(s).toggleLayerVisibilitySolo();

    expect(shownIn(s), {a});
  });

  test('soloing a row that clips shows it on its base', () {
    final s = theUsersStack();
    s.selectLayer(b);

    soloOf(s).toggleLayerVisibilitySolo();

    expect(shownIn(s), {a, b});
  });

  test('and the row above it, which clips to the same base, shows on that '
      'base — not on the row between', () {
    final s = theUsersStack();
    s.selectLayer(c);

    soloOf(s).toggleLayerVisibilitySolo();

    expect(shownIn(s), {a, c});
  });

  test('following you from row to row, and the base the user had switched off '
      'comes back off on the way out', () {
    final s = theUsersStack();
    s.layerSwitches.toggleLayerVisibility(a);
    s.selectLayer(a);
    soloOf(s).toggleLayerVisibilitySolo();
    expect(shownIn(s), {a}, reason: 'the solo shows the row you stand on');

    s.selectLayer(c);
    expect(shownIn(s), {a, c});

    s.selectLayer(b);
    expect(shownIn(s), {a, b});

    soloOf(s).toggleLayerVisibilitySolo();
    expect(
      s.requireActiveCut.layers.byId(a)!.isVisible,
      isFalse,
      reason: 'the eye it had before the solo',
    );
    expect(s.requireActiveCut.layers.byId(c)!.isVisible, isTrue);
  });

  test('a folder it clips to shows what it holds as it was (F-324)', () {
    const folder = LayerId('clip-folder');
    const shown = LayerId('clip-folder-shown');
    const hidden = LayerId('clip-folder-hidden');
    final s = stacked([
      rowOf(shown, folderId: folder),
      rowOf(hidden, folderId: folder),
      createFolderLayer(id: folder, name: 'F'),
      rowOf(c, clips: true),
    ]);
    s.layerSwitches.toggleLayerVisibility(hidden);
    s.selectLayer(c);

    soloOf(s).toggleLayerVisibilitySolo();

    expect(shownIn(s), {folder, shown, c});
  });

  test('a row at the bottom of its folder clips to nothing, and shows with '
      'the folders above it alone', () {
    const folder = LayerId('clip-folder');
    final s = stacked([
      rowOf(a),
      rowOf(c, clips: true, folderId: folder),
      createFolderLayer(id: folder, name: 'F'),
    ]);
    s.selectLayer(c);

    soloOf(s).toggleLayerVisibilitySolo();

    expect(shownIn(s), {folder, c}, reason: '$a is outside its folder');
  });
}

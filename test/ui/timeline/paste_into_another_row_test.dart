import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★ 유저 #4 (2026-08-14): 「프레임블록 복사하고 **다른 애니메이션행 등
/// 이동가능한행에 붙혀넣기 불가.** 이런 붙혀넣기같은건 **같은 섹션 등
/// 허용되는곳이라면 가능하도록**」.
///
/// ★The two pastes are not the same question and were sharing one gate.
/// A LINK means *the same cel*, and a cel belongs to a layer — so 「is that
/// cel in this row」 is exactly right for it. An INDEPENDENT paste mints a
/// cel, so that question does not apply: what it needs to ask is whether
/// this row can hold an authored drawing, which is what 「허용되는곳」 names.
///
/// ⚠️Only reachable because the clipboard carries its cels by value (유저
/// #3's fix): a cross-row paste has no source in `layer.frames` by
/// definition.
void main() {
  ({EditorSessionManager session, LayerId from, LayerId to}) twoRows() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final from = session.activeLayerId!;
    session.addLayerOfKind(LayerKind.animation);
    final to = session.activeLayerId!;
    expect(to, isNot(from));

    // Something to copy on the first row.
    session.selectLayer(from);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    return (session: session, from: from, to: to);
  }

  test('an INDEPENDENT paste reaches another animation row', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();

    f.session.selectLayer(f.to);
    f.session.selectFrameIndex(0);
    expect(
      f.session.canPasteIndependentFrameAtCurrentFrame,
      isTrue,
      reason: 'the row can hold a drawing, so the paste is allowed there',
    );

    f.session.pasteIndependentFrameAtCurrentFrame();

    final target = f.session.layers.firstWhere((l) => l.id == f.to);
    expect(target.timeline[0]?.frameId, isNotNull);
    expect(
      target.frames.any((frame) => frame.id == target.timeline[0]!.frameId),
      isTrue,
      reason: 'the minted cel has to be a real cel in THIS row',
    );
  });

  test('⛔the LINKED paste still refuses — a link means the SAME cel, and a '
      'cel belongs to a layer', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();

    f.session.selectLayer(f.to);
    f.session.selectFrameIndex(0);

    expect(f.session.canPasteLinkedFrameAtCurrentFrame, isFalse);
  });

  test('⛔a row that cannot hold a drawing still refuses', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();

    // ⚠️Selected by KIND, not by adding one: the camera row is a singleton
    // per cut, so `addLayerOfKind` hands back the row that already exists
    // and the active layer never moves — the first version of this test
    // was still standing on an animation row while claiming otherwise.
    f.session.addLayerOfKind(LayerKind.camera);
    final camera = f.session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    f.session.selectLayer(camera.id);
    f.session.selectFrameIndex(0);
    expect(f.session.activeLayer?.kind, LayerKind.camera);

    expect(
      f.session.canPasteIndependentFrameAtCurrentFrame,
      isFalse,
      reason: '「허용되는곳이라면」 — a camera row is not one',
    );
  });

  test('pasting into the SAME row still works', () {
    final f = twoRows();
    f.session.selectLayer(f.from);
    f.session.selectFrameIndex(0);
    f.session.copyFrameAtCurrentFrame();
    f.session.selectFrameIndex(4);

    expect(f.session.canPasteIndependentFrameAtCurrentFrame, isTrue);
  });
}

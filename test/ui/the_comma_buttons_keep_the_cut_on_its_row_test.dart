import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/exposure_verbs.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// F-91 · F-100 — the comma BUTTONS keep the cut on its storyboard row, by the
/// same law the comma drag has kept since feedback #9: the cut ends where the
/// row ends.
///
/// 유저 2026-09-12: 「스토리보드레이어의 마지막 프레임 블록에 대한 코마 편집이
/// 안먹힘. 컷길이 바뀌는걸 원하는게 맞으니까 법 나누지말고 작동하도록」 (F-91)
/// and 「노출 편집 버튼, 1,2,3,4,n 을 통해 콘티레이어 편집하면 컷길이랑 어긋남.
/// 근본/구조적으로 어긋나지 않도록」 (F-100).
///
/// The drag's half is pinned in `storyboard_cut_length_sync_test.dart`; these
/// press the buttons.
void main() {
  /// The default project's cut (24 frames) with a storyboard row divided at
  /// frame 5: {0: 5, 5: 19}.
  (EditorSessionManager, LayerId) scene() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    session.selectFrameIndex(5);
    session.createDrawingAtCurrentFrame();
    final storyboardId = storyboardLayerForCut(session.requireActiveCut)!.id;
    expect(rowOf(session, storyboardId), {0: 5, 5: 19}, reason: 'fixture');
    expect(session.requireActiveCut.duration, 24, reason: 'fixture');
    return (session, storyboardId);
  }

  ExposureVerbs commaOf(EditorSessionManager session) => session.exposureVerbs;

  test('F-91: the LAST panel\'s comma set from the button takes the cut with '
      'it', () {
    final (session, storyboardId) = scene();
    session.selectLayer(storyboardId);
    session.selectFrameIndex(5);

    commaOf(session).setCommaForSelectionOrCurrent(3);

    expect(rowOf(session, storyboardId), {0: 5, 5: 3});
    expect(session.requireActiveCut.duration, 8);
  });

  test('F-100: a MIDDLE panel grown past the cut\'s end takes the cut out to '
      'the row\'s new end', () {
    final (session, storyboardId) = scene();
    session.selectLayer(storyboardId);
    session.selectFrameIndex(0);

    commaOf(session).setCommaForSelectionOrCurrent(8);

    expect(rowOf(session, storyboardId), {0: 8, 8: 19});
    expect(session.requireActiveCut.duration, 27);
  });

  test('a band over the panel answers the same as the playhead', () {
    final (session, storyboardId) = scene();
    session.updateFrameRangeSelectionDrag(
      layerId: storyboardId,
      anchorIndex: 0,
      headIndex: 4,
    );

    commaOf(session).setCommaForSelectionOrCurrent(8);

    expect(rowOf(session, storyboardId), {0: 8, 8: 19});
    expect(session.requireActiveCut.duration, 27);
  });

  test('one undo takes the row and the cut back together', () {
    final (session, storyboardId) = scene();
    session.selectLayer(storyboardId);
    session.selectFrameIndex(5);
    commaOf(session).setCommaForSelectionOrCurrent(3);

    session.undo();

    expect(rowOf(session, storyboardId), {0: 5, 5: 19});
    expect(session.requireActiveCut.duration, 24);
  });

  test('⛔a drawing row\'s comma still leaves the cut alone', () {
    final (session, _) = scene();
    final celId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(celId);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();

    commaOf(session).setCommaForSelectionOrCurrent(30);

    expect(session.requireActiveCut.duration, 24);
  });
}

Map<int, int?> rowOf(EditorSessionManager session, LayerId id) => session
    .layers
    .firstWhere((layer) => layer.id == id)
    .timeline
    .map((key, value) => MapEntry(key, value.length));

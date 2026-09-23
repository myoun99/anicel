import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// F-76 ① · F-133 — a row is born with its label.
///
/// F-76 (유저 2026-09-12): 「그리고 콘티패널 생성시 색라벨 기본값을
/// 콘티소재로. 콘티레이어 생성하면 색라벨 콘티 소재가 되도록. 이미지 레이어는
/// 미술 소재, 애니메이션 레이어는 LO 소재」.
///
/// F-133 (유저 2026-09-14): 「+ 종류버튼 통해 어태치 레이어 생성시, 색라벨의
/// 초기값은 대상 레이어의 색라벨을 이어받음. 현재 서있는 곳을 기준으로
/// 어태치레이어 생기니, 그 대상은 일단 서있는 레이어가 됨. … 예를들어 어태치
/// 레이어에서 서있는채로 만들면 해당 어태치레이어의 값을 이어받음. 이어받는건
/// 초기 값을 그렇게 세팅한단거지 이후 변경가능」.
void main() {
  EditorSessionManager freshSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  Layer layerById(EditorSessionManager session, LayerId id) =>
      session.layers.firstWhere((layer) => layer.id == id);

  Set<LayerId> attachRowsOf(EditorSessionManager session) => {
    for (final layer in session.layers)
      if (layer.attachedToLayerId != null) layer.id,
  };

  for (final (kind, process) in [
    (LayerKind.storyboard, LayerProcess.conte),
    (LayerKind.image, LayerProcess.art),
    (LayerKind.animation, LayerProcess.layout),
  ]) {
    test('F-76: a ${kind.name} row made from the add button is born '
        '${process.abbreviation} 소재', () {
      final session = freshSession();

      session.layerStack.addLayerOfKind(kind);

      expect(session.activeLayer!.kind, kind, reason: 'fixture');
      expect(session.activeLayer!.mark, LayerMark(process: process));
    });
  }

  test('⛔a kind the user did not name is born unlabelled', () {
    final session = freshSession();

    session.layerStack.addLayerOfKind(LayerKind.adjustment);

    expect(session.activeLayer!.kind, LayerKind.adjustment, reason: 'fixture');
    expect(session.activeLayer!.mark, LayerMark.none);
  });

  test('F-76: a new cut\'s drawing row is born LO 소재', () {
    final session = freshSession();

    session.cutVerbs.createCut();

    final drawingRows = [
      for (final layer in session.requireActiveCut.layers)
        if (layer.kind == LayerKind.animation) layer,
    ];
    expect(drawingRows, hasLength(1), reason: 'fixture');
    expect(
      drawingRows.single.mark,
      const LayerMark(process: LayerProcess.layout),
    );
  });

  test('F-133: an attach row made from a labelled row starts with its colour '
      'label, and only starts with it', () {
    final session = freshSession();
    final base = session.activeLayer!.id;
    session.layerMarks.setLayerMark(
      base,
      const LayerMark(process: LayerProcess.key, take: 3),
    );
    final before = attachRowsOf(session);

    session.folders.addAttachedLayer(AttachedPlacement.above);

    final made = attachRowsOf(session).difference(before).single;
    expect(
      layerById(session, made).mark,
      const LayerMark(process: LayerProcess.key),
      reason: 'the colour label comes across; the take is the new row\'s own',
    );

    session.layerMarks.setLayerMark(
      made,
      const LayerMark(process: LayerProcess.finish),
    );
    expect(
      layerById(session, base).mark,
      const LayerMark(process: LayerProcess.key, take: 3),
      reason: 'an initial value, not a tie',
    );
  });

  test('F-133: made while standing on an attach row, it starts with THAT '
      'row\'s label', () {
    final session = freshSession();
    session.layerMarks.setLayerMark(
      session.activeLayer!.id,
      const LayerMark(process: LayerProcess.key),
    );
    var before = attachRowsOf(session);
    session.folders.addAttachedLayer(AttachedPlacement.above);
    final first = attachRowsOf(session).difference(before).single;
    session.layerMarks.setLayerMark(
      first,
      const LayerMark(process: LayerProcess.inbetween),
    );
    session.selectLayer(first);

    before = attachRowsOf(session);
    session.folders.addAttachedLayer(AttachedPlacement.above);

    final second = attachRowsOf(session).difference(before).single;
    expect(
      layerById(session, second).mark,
      const LayerMark(process: LayerProcess.inbetween),
    );
  });
}

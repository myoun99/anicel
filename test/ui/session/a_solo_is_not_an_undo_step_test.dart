import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/visibility_solo.dart';

/// 🚨F-125 — THE VISIBILITY SOLO IS NOT AN UNDO STEP, AND UNDO WALKS PAST IT.
///
/// 유저 2026-09-13: 「이전에 스트로크가 5개있고, 활성레이어 솔로하고 스트로크
/// 1개 그으면, 그을때마다 언두되서 스트로크 0개되야하는데 활성레이어 솔로하고
/// 그린 1개 스트로크만 언두되고 언두버튼 눌러도 그 전은 안됨」.
/// 유저 2026-09-15: 「비지블 솔로모드 전환은 언두에 기록안되게 … 캔버스 관련
/// 확대나 축소가 언두에 기록안되는거랑 같은 느낌 … 진짜 표시용만 바꿀뿐」.
///
/// The solo's eye flips were undo entries while the mode stayed outside
/// history. Undoing them moved the document, the tidy-up after the step
/// re-soloed for the mode that was still on, and the re-solo pushed a fresh
/// entry — so each press from there undid the one the press before it had
/// made. The entries here are drawings: they reach the solo's place in
/// history the way a stroke does, and they can be counted on the row.
void main() {
  /// Held by its own type — `tool/mutation_run.dart` picks a file's
  /// witnesses by which tests IMPORT it.
  VisibilitySolo soloOf(EditorSessionManager s) => s.visibilitySolo;

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  Map<LayerId, bool> eyesOf(EditorSessionManager s) => {
    for (final layer in s.layers) layer.id: layer.isVisible,
  };

  /// A row to stand on other than the active one — not the camera.
  LayerId otherRowOf(EditorSessionManager s) => s.layers
      .firstWhere(
        (layer) =>
            layer.id != s.activeLayerId && layer.kind != LayerKind.camera,
      )
      .id;

  int drawingsOn(EditorSessionManager s, LayerId row) =>
      s.layers.firstWhere((layer) => layer.id == row).frames.length;

  test('draw, solo, undo: the drawing comes back and the solo stays on', () {
    final s = session();
    final row = s.activeLayerId!;
    final drawingsBefore = drawingsOn(s, row);
    s.createDrawingAtCurrentFrame();
    soloOf(s).toggleLayerVisibilitySolo();
    final soloed = eyesOf(s);

    s.undo();

    expect(
      drawingsOn(s, row),
      drawingsBefore,
      reason:
          'the first press undid the solo\'s eyes instead of the drawing '
          'before it',
    );
    expect(soloOf(s).layerVisibilitySoloEnabled, isTrue);
    expect(eyesOf(s), soloed, reason: 'the solo is display, like zoom');
  });

  test('five drawings, a solo, one more drawing: every press goes back ONE '
      'entry, all the way to where the row started', () {
    final s = session();
    final row = s.activeLayerId!;
    final drawingsBefore = drawingsOn(s, row);
    final entriesBefore = s.historyManager.undoCount;

    for (var frame = 0; frame < 5; frame += 1) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
    }
    soloOf(s).toggleLayerVisibilitySolo();
    s.selectFrameIndex(5);
    s.createDrawingAtCurrentFrame();
    expect(
      drawingsOn(s, row),
      drawingsBefore + 6,
      reason: 'the CONTROL — six drawings landed',
    );
    final entries = s.historyManager.undoCount - entriesBefore;

    for (var press = 1; press <= entries; press += 1) {
      final before = s.historyManager.undoCount;
      s.undo();
      expect(
        s.historyManager.undoCount,
        before - 1,
        reason:
            'press $press went back one entry and pushed another: the '
            're-solo after the step wrote history, and undo stood still on '
            'the solo from there on',
      );
    }

    expect(drawingsOn(s, row), drawingsBefore);
    expect(soloOf(s).layerVisibilitySoloEnabled, isTrue);
  });

  test('turning the solo on and off leaves undo exactly as it was', () {
    final s = session();
    s.createDrawingAtCurrentFrame();
    final eyesBefore = eyesOf(s);
    final entries = s.historyManager.undoCount;

    soloOf(s).toggleLayerVisibilitySolo();
    expect(
      eyesOf(s),
      isNot(eyesBefore),
      reason: 'the CONTROL — the solo hid something',
    );
    expect(s.historyManager.undoCount, entries, reason: 'entering');

    soloOf(s).toggleLayerVisibilitySolo();
    expect(eyesOf(s), eyesBefore, reason: 'the CONTROL — leaving restored');
    expect(s.historyManager.undoCount, entries, reason: 'leaving');
  });

  test('the row the solo follows costs no entry either', () {
    final s = session();
    final active = s.activeLayerId!;
    final other = otherRowOf(s);
    soloOf(s).toggleLayerVisibilitySolo();
    final entries = s.historyManager.undoCount;

    s.selectLayer(other);

    expect(
      eyesOf(s)[other],
      isTrue,
      reason: 'the CONTROL — the solo followed the row',
    );
    expect(eyesOf(s)[active], isFalse);
    expect(s.historyManager.undoCount, entries);
  });
}

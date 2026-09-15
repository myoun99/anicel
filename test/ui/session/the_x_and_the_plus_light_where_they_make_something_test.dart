import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_command_actions.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// F-107 — the frame pill's X and ＋ light only where their press makes
/// something.
///
/// 유저 2026-09-12: 「콘티레이어에선 불가능한 버튼 비활성화. 우선 프레임의
/// x버튼. 그 외도 있나 확인」.
///
/// The X makes an EMPTY cell, and a covering row has none: the storyboard
/// row's write normalization runs every panel on to the next division in the
/// same write, so the X lit on the conte row and its press left the row as it
/// was, one undo step heavier. The ＋ said yes on every drawing row while its
/// press refuses a block's first cell. The conte row's other buttons are
/// pinned here too — each lit, and each press lands.
void main() {
  /// The default project's cut (24 frames) with a storyboard row divided at
  /// frame 5 — {0: 5, 5: 19} — standing on that row.
  (EditorSessionManager, LayerId) conteScene() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    session.selectFrameIndex(5);
    session.createDrawingAtCurrentFrame();
    final storyboardId = storyboardLayerForCut(session.requireActiveCut)!.id;
    session.selectLayer(storyboardId);
    expect(rowOf(session, storyboardId), {0: 5, 5: 19}, reason: 'fixture');
    return (session, storyboardId);
  }

  LayerId animationRowOf(EditorSessionManager session) => session.layers
      .firstWhere((layer) => layer.kind == LayerKind.animation)
      .id;

  group('the X on a conte row', () {
    test('is dark inside a panel', () {
      final (session, _) = conteScene();
      session.selectFrameIndex(8);

      expect(session.exposureVerbs.canBlankExposureAtCurrentFrame, isFalse);
    });

    test('pressed anyway, leaves the row and the undo stack as they were', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(8);
      final steps = session.historyManager.undoCount;

      session.exposureVerbs.blankExposureAtCurrentFrame();

      expect(rowOf(session, id), {0: 5, 5: 19});
      expect(
        session.historyManager.undoCount,
        steps,
        reason: 'the hole was filled in the same write — a step here undoes '
            'nothing',
      );
    });

    test('is dark over a band on the panel', () {
      final (session, id) = conteScene();
      session.updateFrameRangeSelectionDrag(
        layerId: id,
        anchorIndex: 7,
        headIndex: 10,
      );

      expect(session.exposureVerbs.canBlankExposureAtCurrentFrame, isFalse);
    });

    test('pressed anyway over the band, leaves the row and the undo stack as '
        'they were', () {
      final (session, id) = conteScene();
      session.updateFrameRangeSelectionDrag(
        layerId: id,
        anchorIndex: 7,
        headIndex: 10,
      );
      final steps = session.historyManager.undoCount;

      session.exposureVerbs.blankExposureAtCurrentFrame();

      expect(rowOf(session, id), {0: 5, 5: 19});
      expect(session.historyManager.undoCount, steps);
    });

    test('⛔an animation row still lights its X inside a hold', () {
      final (session, _) = conteScene();
      session.selectLayer(animationRowOf(session));
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      session.exposureVerbs.setCommaForSelectionOrCurrent(4);
      session.selectFrameIndex(2);

      expect(session.exposureVerbs.canBlankExposureAtCurrentFrame, isTrue);
    });
  });

  group('the ＋', () {
    test('is dark on a conte panel\'s first cell', () {
      final (session, _) = conteScene();
      session.selectFrameIndex(5);

      expect(session.canCreateInstance, isFalse);
    });

    test('pressed anyway on that cell, makes nothing', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(5);
      final steps = session.historyManager.undoCount;

      createActiveInstance(session);

      expect(rowOf(session, id), {0: 5, 5: 19});
      expect(session.historyManager.undoCount, steps);
    });

    test('is lit inside a conte panel, where its press divides the panel', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(8);

      expect(session.canCreateInstance, isTrue);
      createActiveInstance(session);
      expect(rowOf(session, id), {0: 5, 5: 3, 8: 16});
    });

    test('answers the same on an animation row: dark on a block\'s first '
        'cell, lit inside its hold and on an empty cell', () {
      final (session, _) = conteScene();
      session.selectLayer(animationRowOf(session));
      session.selectFrameIndex(0);
      expect(session.canCreateInstance, isTrue, reason: 'an empty cell');
      session.createDrawingAtCurrentFrame();
      session.exposureVerbs.setCommaForSelectionOrCurrent(4);

      expect(
        session.canCreateInstance,
        isFalse,
        reason: 'the block\'s first cell',
      );
      session.selectFrameIndex(2);
      expect(session.canCreateInstance, isTrue, reason: 'inside the hold');
      session.selectFrameIndex(10);
      expect(session.canCreateInstance, isTrue, reason: 'an empty cell');
    });

    test('stays dark on a picture row whose one cel exists (D22)', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.layerStack.addLayerOfKind(LayerKind.image);

      for (final frameIndex in [0, 3]) {
        session.selectFrameIndex(frameIndex);
        expect(session.canCreateInstance, isFalse, reason: 'at $frameIndex');
      }
    });
  });

  group('the conte row\'s other buttons are lit, and each press lands', () {
    /// Presses [press] and says it landed on the row [id]: its timeline
    /// moved, in exactly one undo step.
    void expectLands(
      EditorSessionManager session,
      LayerId id,
      void Function() press,
    ) {
      final before = Map<int, TimelineExposure>.of(timelineOf(session, id));
      final steps = session.historyManager.undoCount;

      press();

      expect(timelineOf(session, id), isNot(equals(before)));
      expect(session.historyManager.undoCount, steps + 1);
    }

    test('mark', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(8);

      expect(session.layerMarks.canToggleMarkAtCurrentFrame, isTrue);
      expectLands(session, id, session.layerMarks.toggleMarkAtCurrentFrame);
    });

    test('cut', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(8);

      expect(session.clipboard.canCutRunAtCurrentFrame, isTrue);
      expectLands(session, id, session.clipboard.cutRunAtCurrentFrame);
    });

    test('delete', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(8);

      expect(session.cells.canDeleteCellAtCurrentFrame, isTrue);
      expectLands(session, id, session.cells.deleteCellAtCurrentFrame);
    });

    test('paste', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(2);
      session.copyFrameAtCurrentFrame();
      session.selectFrameIndex(8);

      expect(session.canPasteIndependentFrameAtCurrentFrame, isTrue);
      expectLands(session, id, session.pasteIndependentFrameAtCurrentFrame);
    });

    test('linked paste', () {
      final (session, id) = conteScene();
      session.selectFrameIndex(2);
      session.copyFrameAtCurrentFrame();
      session.selectFrameIndex(8);

      expect(session.canPasteLinkedFrameAtCurrentFrame, isTrue);
      expectLands(session, id, session.pasteLinkedFrameAtCurrentFrame);
    });
  });
}

Map<int, TimelineExposure> timelineOf(
  EditorSessionManager session,
  LayerId id,
) => session.layers.firstWhere((layer) => layer.id == id).timeline;

Map<int, int?> rowOf(EditorSessionManager session, LayerId id) =>
    timelineOf(session, id).map((key, value) => MapEntry(key, value.length));

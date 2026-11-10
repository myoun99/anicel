import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/pill_row_clipboard.dart';

/// 🗣️F-573 — A 겸용 CUT'S ROW CANNOT LEAVE ITS LINKS ALONE.
///
/// 유저 2026-11-08: 「겸용컷은 레이어의 링크해제 불가능하게. 지금 타임라인
/// 공용알약의 링크독립 작동가능해서 링크해제 되버림」. I-25 (유저 2026-09-14)
/// had said it of the link window — 「링크컷일경우엔 링크해제버튼 비활성화」 —
/// and the shared pill's rows rung never asked it. One law now, asked by
/// the verb both press ([LayerVerbs.unlinkLayers]); the cut still leaves
/// its links whole (`CutVerbs.unlinkCuts`).
///
/// The collaborator is held BY ITS OWN TYPE so the mutation runner names
/// this file as its witness (it picks witnesses by import).
void main() {
  LayerVerbs layersOf(EditorSessionManager s) => s.layerVerbs;

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  bool rowIsLinked(EditorSessionManager s) =>
      layersOf(s).groupIsLinked(s.activeLayer!, s.requireActiveCut);

  /// The active cut made 겸용 with a fresh sibling: both cuts, the source
  /// first.
  List<CutId> linkedPair(EditorSessionManager s) {
    final source = s.requireActiveCut.id;
    s.cutVerbs.createLinkedCutFromActiveCut();
    return [source, s.requireActiveCut.id];
  }

  test('in either cut of a 겸용 pair a selected row holds nothing on the '
      'pill\'s rows rung, and the press leaves it linked', () {
    final s = session();
    for (final cutId in linkedPair(s)) {
      s.selectCut(cutId);
      expect(layersOf(s).activeCutIsLinkedCut, isTrue, reason: '⛔전제');
      expect(rowIsLinked(s), isTrue, reason: '⛔전제: its row shares');
      s.rowSelectionVerbs.beginRowSelection(
        LayerRowAddress(s.activeLayerId!),
      );
      expect(s.unlinkSubject, isNot(PillSubject.layers), reason: '$cutId');

      TimelineToolbarPanelContext(s).unlink();

      expect(rowIsLinked(s), isTrue, reason: '「레이어의 링크해제 불가능하게」');
    }
  });

  test('the verb releases no row of a 겸용 cut, whoever presses it — the '
      'link window asks the same answer for its button', () {
    final s = session();
    linkedPair(s);
    final entries = s.historyManager.undoCount;

    layersOf(s).unlinkLayers([s.activeLayerId!]);

    expect(rowIsLinked(s), isTrue);
    expect(s.historyManager.undoCount, entries, reason: 'no step to undo');
    expect(layersOf(s).activeCutIsLinkedCut, isTrue);
  });

  test('⛔CONTROL — a linked row of a cut of its own still leaves: the law '
      'is the 겸용 cut\'s, not every link\'s', () {
    final s = session();
    linkDuplicateActiveRow(s);
    expect(layersOf(s).activeCutIsLinkedCut, isFalse, reason: '⛔전제');
    expect(rowIsLinked(s), isTrue, reason: '⛔전제');
    s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(s.activeLayerId!));
    expect(s.unlinkSubject, PillSubject.layers);

    TimelineToolbarPanelContext(s).unlink();

    expect(rowIsLinked(s), isFalse);
  });
}

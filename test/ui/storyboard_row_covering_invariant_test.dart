import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// The conte row TILES its cut, whatever verb just wrote it.
///
/// The drag verbs have their own tests. These drive the OTHER writers — the
/// ones that edit the row without going anywhere near the cut's length, and
/// which an investigation flagged as a second, independent way into a
/// stored hole: delete, the comma buttons, push/pull, paste. They were
/// listed as reachable and left open, because closing them one verb at a
/// time is how the pair came apart in the first place.
///
/// They are unreachable now, and not because each was fixed:
/// `cutWithCoveringStoryboardRow` runs on every repository write, so the
/// invariant holds for verbs nobody thought about — including the ones
/// added after this file. That is the dividend the write-time normalization
/// was bought for, and this is where it is collected.
void main() {
  EditorSessionManager threePanelCut() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.addLayerOfKind(LayerKind.storyboard);
    session.selectFrameIndex(8);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(16);
    session.createDrawingAtCurrentFrame();
    return session;
  }

  LayerId storyboardRowId(EditorSessionManager session) =>
      storyboardLayerForCut(session.requireActiveCut)!.id;

  /// Fails unless every stored block abuts the last, and the last ends on
  /// the cut — the two halves of "no frame belongs to nobody".
  void expectRowTilesItsCut(EditorSessionManager session, LayerId rowId) {
    final row = session.layers.firstWhere((layer) => layer.id == rowId);
    final duration = session.requireActiveCut.duration;
    var cursor = 0;
    for (final entry in row.timeline.entries) {
      expect(
        entry.key,
        cursor,
        reason: 'a stored hole opens before frame ${entry.key}',
      );
      cursor = entry.key + (entry.value.length ?? 1);
    }
    expect(cursor, duration, reason: 'the row must end where the cut does');
    // And the reading the strip draws agrees with the store, which is the
    // disagreement that made the damage invisible where it was made.
    final cells = storyboardCoverageCells(
      timeline: row.timeline,
      cutDuration: duration,
    );
    expect(cells.first.startIndex, 0);
    expect(cells.last.endIndexExclusive, duration);
  }

  test('the row is born tiling its cut', () {
    final session = threePanelCut();
    expectRowTilesItsCut(session, storyboardRowId(session));
  });

  test('deleting a MIDDLE panel leaves no hole — its frames go to the panel '
      'before it, which is what the coverage rule always said and only the '
      'reader used to do', () {
    final session = threePanelCut();
    final rowId = storyboardRowId(session);
    session.selectLayer(rowId);
    session.selectFrameIndex(8);

    session.deleteCellAtCurrentFrame();

    expectRowTilesItsCut(session, rowId);
    final row = session.layers.firstWhere((layer) => layer.id == rowId);
    expect(
      row.timeline.keys,
      [0, 16],
      reason: 'the division is gone, the two survivors keep theirs',
    );
  });

  test('deleting the LAST panel is the same rule at the row end', () {
    final session = threePanelCut();
    final rowId = storyboardRowId(session);
    session.selectLayer(rowId);
    session.selectFrameIndex(16);

    session.deleteCellAtCurrentFrame();

    expectRowTilesItsCut(session, rowId);
    expect(
      session.layers.firstWhere((layer) => layer.id == rowId).timeline.keys,
      [0, 8],
    );
  });

  test('and UNDO restores the tiling, not just the keys', () {
    final session = threePanelCut();
    final rowId = storyboardRowId(session);
    session.selectLayer(rowId);
    session.selectFrameIndex(8);
    session.deleteCellAtCurrentFrame();

    session.undo();

    expectRowTilesItsCut(session, rowId);
    expect(
      session.layers.firstWhere((layer) => layer.id == rowId).timeline.keys,
      [0, 8, 16],
    );
  });
}

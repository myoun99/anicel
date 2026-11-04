import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/draw_on_current_frame.dart';

/// 독립시키기 (`UnlinkLayerCommand`): the row unlinked and the rows it was
/// linked with go on apart, EACH with the pictures they showed — whichever
/// of them the shared cels were kept under — and the undo gives them the
/// one picture again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = CutId('cut-1');

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: conteTrackProject());
    addTearDown(s.dispose);
    return s;
  }

  Project projectOf(EditorSessionManager s) => s.repository.requireProject();

  Cut cutOf(EditorSessionManager s, CutId id) => projectOf(s)
      .tracksOfEveryTimeline
      .expand((track) => track.cuts)
      .singleWhere((cut) => cut.id == id);

  /// cut-1's first row drawn on, then a 겸용 of cut-1 pasted after it: the
  /// drawing is kept under cut-1's row, the first of the group. The rows by
  /// cut, and the cel drawn.
  ({CutId linked, Map<CutId, LayerId> rows, FrameId cel}) drawnAndLinked(
    EditorSessionManager s,
  ) {
    final row = cutOf(s, first).layers.first.id;
    s.selectGlobalFrame(1);
    s.selectLayer(row);
    drawOnCurrentFrame(s);
    s.selectTrackRow(conteTrackId);
    final before = {for (final cut in projectOf(s).tracks.single.cuts) cut.id};
    StoryboardToolbarPanelContext(s).copyFrame();
    StoryboardToolbarPanelContext(s).pasteLinkedFrame();
    final linked = projectOf(s).tracks.single.cuts
        .singleWhere((cut) => !before.contains(cut.id))
        .id;
    return (
      linked: linked,
      rows: {
        first: row,
        linked: projectOf(s).linkRegistry.counterpartIn(
          cutId: first,
          layerId: row,
          targetCutId: linked,
        )!,
      },
      cel: cutOf(s, first).layers.first.frames.last.id,
    );
  }

  BitmapSurface? pictureOf(
    EditorSessionManager s,
    CutId id, {
    required Map<CutId, LayerId> rows,
    required FrameId cel,
  }) => s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
    s.brushFrameKeyForCut(cutOf(s, id), rows[id]!, cel),
  );

  for (final (unlinked, which) in [
    (true, 'the cut the drawing is kept under'),
    (false, 'the cut linked to it later'),
  ]) {
    test('$which unlinked, both cuts go on showing the drawing — and the '
        'undo gives them the one picture again', () {
      final s = session();
      final (:linked, :rows, :cel) = drawnAndLinked(s);
      BitmapSurface? shown(CutId id) =>
          pictureOf(s, id, rows: rows, cel: cel);
      final picture = shown(first);
      expect(picture, isNotNull, reason: '⛔전제: a drawing');
      expect(shown(linked), same(picture), reason: '⛔전제: 겸용');

      final pressed = unlinked ? first : linked;
      s.cutCommandCoordinator.unlinkLayer(
        cutId: pressed,
        layerId: rows[pressed]!,
      );

      expect(
        projectOf(s).linkRegistry.groupOf(cutId: first, layerId: rows[first]!),
        isNull,
        reason: '⛔전제: unlinked',
      );
      expect(shown(first), same(picture));
      expect(shown(linked), same(picture));

      s.historyManager.undo();
      expect(shown(first), same(picture));
      expect(shown(linked), same(picture));
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R9 #1 and #9 — the rows that are not ordinary cel rows.
///
/// The user's rule for both is the same one: **a row is a row.** A folder
/// band is derived display, but that is no reason for a drag across it to
/// do nothing ("프레임셀이면 싹 다 모든게 작동해야함"), and it is equally
/// no reason to make it behave like the transform header and select every
/// member ("자꾸 트랜스폼헤더마냥 전체선택시키려들지마").
void main() {
  EditorSessionManager makeSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  group('#1 — a folder row selects', () {
    test('a drag on the folder band selects the FOLDER ROW, not its members',
        () {
      final session = makeSession();
      session.createDrawingAtCurrentFrame();
      final member = session.activeLayer!;
      session.groupActiveLayerIntoFolder();

      final folder = session.layers.firstWhere(
        (layer) => layer.kind == LayerKind.folder,
      );
      expect(
        session.layers.firstWhere((l) => l.id == member.id).folderId,
        folder.id,
        reason: 'the drawing really is inside the folder now',
      );

      session.updateFrameRangeSelectionDrag(
        layerId: folder.id,
        anchorIndex: 0,
        headIndex: 2,
      );

      final selection = session.frameRangeSelection.value;
      expect(
        selection,
        isNotNull,
        reason: 'the band shows frames, so a drag across it must select — '
            'this used to fall through to nothing',
      );
      expect(selection!.layerId, folder.id);
      expect(
        selection.spanLayerIds,
        [folder.id],
        reason: 'the folder row alone: a folder is not a select-everything '
            'header',
      );
    });

    test('the snap follows the band the row DRAWS — its members\' union', () {
      // The folder owns no timeline; what it shows is the merged exposures
      // of its subtree. Snapping to anything else would round the selection
      // to blocks the row does not display.
      const runs = [(start: 4, endExclusive: 9)];

      expect(aggregateRunBlockAt(runs, 3), isNull);
      final inside = aggregateRunBlockAt(runs, 6)!;
      expect(inside.startIndex, 4);
      expect(inside.endIndexExclusive, 9);
      expect(aggregateRunBlockAt(runs, 9), isNull, reason: 'end is exclusive');
    });

    test('an ordinary row is unaffected — no aggregate lane in play', () {
      final session = makeSession();
      session.createDrawingAtCurrentFrame();
      final drawing = session.activeLayer!;

      session.updateFrameRangeSelectionDrag(
        layerId: drawing.id,
        anchorIndex: 0,
        headIndex: 1,
      );

      final selection = session.frameRangeSelection.value!;
      expect(selection.layerId, drawing.id);
      expect(selection.spanLayerIds, [drawing.id]);
    });
  });

  group('#9 — a covering row refuses to be authored into', () {
    test('adding frames over a selection passes OVER an image row', () {
      final session = makeSession();
      session.createDrawingAtCurrentFrame();
      final drawing = session.activeLayer!;

      session.addLayerOfKind(LayerKind.image);
      final image = session.activeLayer!;
      expect(image.kind, LayerKind.image);
      expect(layerKindCoversWithoutGaps(image.kind), isTrue);
      final imageFramesBefore = image.frames.length;
      final imageTimelineBefore = Map.of(image.timeline);

      // A range that spans BOTH rows, then the add-frames verb.
      session.updateFrameRangeSelectionDrag(
        layerId: drawing.id,
        anchorIndex: 0,
        headIndex: 6,
        headLayerId: image.id,
      );
      expect(
        session.frameRangeSelection.value!.spanLayerIds,
        contains(image.id),
        reason: 'the premise: the image row really is inside the selection',
      );

      session.createInstancesForSelection();

      final imageAfter = session.layers.firstWhere((l) => l.id == image.id);
      expect(
        imageAfter.frames.length,
        imageFramesBefore,
        reason: 'one cel edge to edge — there is no "add a frame" here',
      );
      expect(imageAfter.timeline, imageTimelineBefore);
    });
  });
}

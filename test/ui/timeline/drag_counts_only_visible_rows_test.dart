import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import '../../helpers/library_source.dart';

/// **F-31 — a row drag counts the rows you can SEE.**
///
/// 유저 2026-08-24: 「레이어 드래그 시, 도중에 접힌것도 인식해버리는거같음 …
/// 그때부터 커서랑 가로선이랑 어긋남. **보이는것중에서만 이동하도록**」
///
/// 🚨The mechanism: travel is measured in rail ROWS and a drop slot indexes
/// the LAYER list, and those two lists part company in both directions — a
/// collapsed folder or attach group puts layers in the list with no rows on
/// screen, and a twirled-open layer puts rows on screen with no layers.
/// Adding rail-row travel to a layer index therefore ran the caret ahead of
/// the cursor, and past a folded group it named a gap that no visible row
/// draws, so the line went missing too.
///
/// These drive [LayerRowCaret] because that is what both grids call: the
/// rail and the x-sheet each used to do this arithmetic themselves, and one
/// of them being fixed alone is how the bug would come back.
void main() {
  Layer cel(String id) =>
      Layer(id: LayerId(id), name: id.toUpperCase(), frames: const []);

  TimelineDisplayRow layerRow(Layer layer, int layerIndex) =>
      TimelineDisplayRow.layer(layer, layerIndex: layerIndex);

  TimelineDisplayRow laneRow(Layer layer, String laneId, int layerIndex) =>
      TimelineDisplayRow.lane(
        layer,
        PropertyLaneRow(laneId: laneId, label: laneId, keyedFrames: const {}),
        layerIndex: layerIndex,
      );

  group('a folded group is layers with no rows', () {
    // Model order, and the display list the grid hands down. The folder's
    // members are in the stack and NOT on screen.
    final a = cel('a');
    final folder = createFolderLayer(id: const LayerId('f'), name: 'F');
    final m1 = cel('m1');
    final m2 = cel('m2');
    final m3 = cel('m3');
    final z = cel('z');
    final stack = [a, folder, m1, m2, m3, z];
    final rows = [layerRow(a, 0), layerRow(folder, 1), layerRow(z, 5)];

    test('one rail row of travel steps over the WHOLE folded group', () {
      final caret = LayerRowCaret.of(rows, a.id)!;

      expect(caret.slot, 0);
      expect(
        caret.layers.map((layer) => layer.id.value),
        ['a', 'f', 'z'],
        reason: 'the members have no row, so no caret can land between them',
      );
      expect(caret.slotFor(1), 2, reason: 'the gap past the folder row');
    });

    test('and the landing is AFTER the members, not among them', () {
      final caret = LayerRowCaret.of(rows, a.id)!;

      expect(
        modelInsertionForSlot(
          stack: stack,
          displayRows: caret.layers,
          slot: caret.slotFor(1),
        ),
        5,
        reason:
            'model index 5 is just before z — past m1, m2 and m3. '
            'Counted in the full layer list the same travel named slot 2, '
            'which is the gap between the folder and its first member: '
            'one row of travel would have dropped the row INSIDE the '
            'folded group.',
      );
    });

    test('the last row on screen is the last one a caret can follow', () {
      expect(LayerRowCaret.of(rows, z.id)!.isLastRow, isTrue);
      expect(
        LayerRowCaret.of(rows, folder.id)!.isLastRow,
        isFalse,
        reason: 'z has a row; the members between them do not',
      );
    });
  });

  group('open lanes are rows with no layers', () {
    final a = cel('a');
    final b = cel('b');
    final c = cel('c');
    final rows = [
      layerRow(a, 0),
      laneRow(a, 'position', 0),
      laneRow(a, 'scale', 0),
      layerRow(b, 1),
      layerRow(c, 2),
    ];

    test('travel INTO the lane block moves nothing', () {
      final caret = LayerRowCaret.of(rows, a.id)!;

      expect(
        caret.slotFor(1),
        0,
        reason:
            'one row down is a lane of this very layer — not a gap a '
            'layer can go in, so the caret stays on its own',
      );
    });

    test('travel PAST the lane block lands one layer on', () {
      final caret = LayerRowCaret.of(rows, a.id)!;

      expect(
        caret.slotFor(3),
        2,
        reason:
            'three rail rows clears both lanes and b; counted in the '
            'layer list it would have run off the end',
      );
    });

    test('the on-row band over a lane swallows nothing', () {
      final caret = LayerRowCaret.of(rows, a.id)!;

      expect(
        caret.onRowLayer(1),
        isNull,
        reason:
            'a lane holds no drop — the old arithmetic read one row '
            'down as one LAYER down and offered b',
      );
      expect(caret.onRowLayer(3)?.id, b.id);
      expect(caret.onRowLayer(null), isNull);
    });
  });

  group('with nothing hidden it is the plain list it always was', () {
    final a = cel('a');
    final b = cel('b');
    final c = cel('c');
    final rows = [layerRow(a, 0), layerRow(b, 1), layerRow(c, 2)];

    test('slots and travel match the layer indices one for one', () {
      final caret = LayerRowCaret.of(rows, b.id)!;

      expect(caret.slot, 1);
      expect(caret.layers.map((layer) => layer.id.value), ['a', 'b', 'c']);
      expect(caret.slotFor(0), 1);
      expect(caret.slotFor(1), 3);
      expect(caret.slotFor(-1), 0);
      expect(caret.onRowLayer(1)?.id, c.id);
      expect(caret.onRowLayer(-1)?.id, a.id);
    });

    test('a row with no place in the pass has no caret to offer', () {
      expect(LayerRowCaret.of(rows, const LayerId('ghost')), isNull);
    });
  });

  /// ⚠️Everything above pins the caret; nothing above can see a SURFACE
  /// going back to counting its own way, and both surfaces did exactly that
  /// until this round. The full layer list reaching the drop hooks IS the
  /// bug — it is the list with the hidden rows still in it — so that is
  /// what this refuses.
  test('neither grid hands the drop policy the full layer list', () {
    const grids = [
      'lib/src/ui/timeline/layer_timeline_grid.dart',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ];

    // Both grids resolve a row drag through ONE wrapper now (the audit's
    // clone scan, 2026-09-03), so the caret is asked there — of the rows
    // the grid DREW, handed in as a getter.
    final owner = librarySource('lib/src/ui/timeline/layer_row_drag.dart');
    expect(owner, contains('Widget layerRowDragWrapper('));
    final wrapper = owner.substring(
      owner.indexOf('Widget layerRowDragWrapper('),
    );
    expect(
      wrapper.contains('LayerRowCaret.of(dragRows()'),
      isTrue,
      reason: 'the wrapper asks the caret of the rows on screen',
    );
    expect(
      wrapper.contains('widget.layers'),
      isFalse,
      reason: 'the wrapper never sees the whole layer list',
    );

    for (final path in grids) {
      // The grid is a LIBRARY — the file plus the parts the audit's SRP
      // cuts (2026-09-02) put beside it — so the call is found where it sits.
      final source = librarySource(path);
      expect(
        source.contains('layerRowDragWrapper('),
        isTrue,
        reason: '$path resolves a row drag through the shared wrapper',
      );
      expect(
        source.contains('LayerRowCaret.of('),
        isFalse,
        reason: '$path asks no caret of its own — the wrapper does',
      );
      expect(
        RegExp(r'dragRows:\s*\(\)\s*=>\s*_state\._dragRows').hasMatch(source),
        isTrue,
        reason:
            '$path hands the wrapper the rows ON SCREEN, never the whole '
            'layer list — the difference is every folded group',
      );
      expect(
        RegExp(r'dragRows:\s*\(\)\s*=>\s*widget\.layers').hasMatch(source),
        isFalse,
        reason:
            '$path — the whole layer list is the list with the hidden rows '
            'still in it',
      );
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cut_verbs.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';

import '../../helpers/draw_on_current_frame.dart';

/// A copy that mints its cels afresh has to bring their pictures: a picture
/// lives in the store under its cel's key, so a new id with nothing moved
/// under it is a blank drawing. F-62 (유저: 「프레임 복사후 독립붙여넣기시,
/// 그림이 복제되지않음」) fixed that for frames; the layer and the cut were
/// measured doing the same on 2026-09-26 — every duplicated or pasted row
/// came out blank (card `duplicates-lose-their-pictures`).
///
/// The verbs these live in — named so `tool/mutation_run.dart` runs this
/// file for them.
LayerVerbs layerVerbsOf(EditorSessionManager session) => session.layerVerbs;
LayerClipboard layerBoardOf(EditorSessionManager session) =>
    session.layerClipboard;
CutVerbs cutVerbsOf(EditorSessionManager session) => session.cutVerbs;

void main() {
  late EditorSessionManager session;
  late Object picture;
  late LayerId drawnRow;

  Layer rowIn(Cut cut, LayerId id) =>
      cut.layers.firstWhere((layer) => layer.id == id);

  /// Every cel of [row] in [cut], by its picture (null for none).
  List<Object?> pictureOf(Cut cut, Layer row) => [
    for (final cel in row.frames)
      session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
        session.brushFrameKeyForCut(cut, row.id, cel.id),
      ),
  ];

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    drawOnCurrentFrame(session);
    drawnRow = session.activeLayer!.id;
    picture = pictureOf(
      session.requireActiveCut,
      rowIn(session.requireActiveCut, drawnRow),
    ).single!;
  });
  tearDown(() => session.dispose());

  Layer theNewRow(Set<LayerId> before) => session.requireActiveCut.layers
      .where((layer) => !before.contains(layer.id))
      .single;

  Set<LayerId> rowsNow() => {
    for (final layer in session.requireActiveCut.layers) layer.id,
  };

  test('a duplicated row shows the drawing it was duplicated from', () {
    final before = rowsNow();
    session.layerVerbs.duplicateActiveLayer();
    final copy = theNewRow(before);
    expect(
      copy.frames.single.id,
      isNot(rowIn(session.requireActiveCut, drawnRow).frames.single.id),
      reason: 'fixture premise: a cel of its own',
    );
    expect(pictureOf(session.requireActiveCut, copy), [same(picture)]);
  });

  test('selected rows duplicated at once — ⑨\'s one step — bring theirs', () {
    session.rowSelection.value = [LayerRowAddress(drawnRow)];
    expect(
      session.layerVerbs.duplicatableSelectedLayerIds(),
      [drawnRow],
      reason: 'fixture premise: the selected-rows arm answers',
    );
    final before = rowsNow();
    session.layerVerbs.duplicateSelectedLayers();
    expect(pictureOf(session.requireActiveCut, theNewRow(before)), [
      same(picture),
    ]);
  });

  test('a row copied and pasted shows the drawing it was copied from', () {
    session.layerClipboard.copyActiveLayer();
    final before = rowsNow();
    session.layerClipboard.pasteLayerFromClipboard();
    expect(pictureOf(session.requireActiveCut, theNewRow(before)), [
      same(picture),
    ]);
  });

  test('a duplicated cut shows every drawing of the cut it came from', () {
    final source = session.requireActiveCut;
    session.cutVerbs.duplicateActiveCut();
    final copy = session.requireActiveCut;
    expect(copy.id, isNot(source.id), reason: 'the copy is where you stand');
    final drawn = copy.layers.where((layer) => layer.frames.isNotEmpty);
    expect(drawn, hasLength(1), reason: 'fixture premise: one drawn row');
    expect(pictureOf(copy, drawn.single), [same(picture)]);
  });
}

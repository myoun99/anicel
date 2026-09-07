// A SYNCED ATTACH ROW IS NEVER AUTHORED INTO: THE BAND PASSES OVER IT.
//
// A survivor of the mutation campaign (2026-09-04, the cell-fills split):
// the stand-down for a synced mirror dropped, so a range that happens to
// span one would fill its gaps with blank cels of its own. A synced
// mirror's cels ride the base's timeline through the cell links — a cel
// authored on the mirror belongs to nobody, and undo cannot put back what
// the mirror then shadows.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  test('a band spanning a SYNCED mirror fills the base and authors nothing '
      'on the mirror', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    Layer layerOf(LayerId id) =>
        session.layers.firstWhere((layer) => layer.id == id);

    final base = session.activeLayer!;
    session.folders.addAttachedLayer(AttachedPlacement.above);
    final mirror = session.layers.firstWhere(
      (layer) => layer.attachedToLayerId == base.id,
    );
    expect(
      mirror.attachedMode,
      AttachedMode.synced,
      reason: 'the stand-down under test is the SYNCED one',
    );

    // A band over both rows, across frames the base has nothing on.
    session.selectLayer(base.id);
    session.updateFrameRangeSelectionDrag(
      layerId: base.id,
      anchorIndex: 0,
      headIndex: 6,
      headLayerId: mirror.id,
      spanRows: [LayerRowAddress(base.id), LayerRowAddress(mirror.id)],
    );
    session.cellInstances.createInstancesForSelection();

    expect(
      layerOf(base.id).timeline,
      isNotEmpty,
      reason:
          'the band did author the row that owns its own timing — without '
          'this the test would pass on a verb that did nothing at all',
    );
    // The mirror's row DOES gain entries — a synced mirror shows its
    // base's cels, under ids the attach machinery mints ('attach-mirror-…').
    // What it must never gain is a cel AUTHORED on it, which arrives with
    // an id minted from the mirror's own sequence.
    expect(
      layerOf(mirror.id).timeline.values.where(
        (entry) => !(entry.frameId?.value ?? '').startsWith('attach-mirror-'),
      ),
      isEmpty,
      reason:
          'a synced mirror follows its base; a blank cel authored on it '
          'belongs to nobody and undo cannot put back what it shadows',
    );
  });
}

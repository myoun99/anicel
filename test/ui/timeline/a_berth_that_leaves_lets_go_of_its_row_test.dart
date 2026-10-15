@Tags(['gc'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/row_berths.dart';

import '../../helpers/collect_garbage.dart';

/// 🚨I-57 ㉣ (10-13): three of the grids' four row memos were never let go
/// of — every layer of every cut a grid had shown stayed held, the widget
/// and the Layer it was built from. One keep holds them all now
/// ([KeptByBerth]), and what it keeps in a berth lives while the berth does.
void main() {
  // The berths ask the focus where the keyboard is.
  TestWidgetsFlutterBinding.ensureInitialized();

  TimelineDisplayRow row(String id, int index) => TimelineDisplayRow.layer(
    Layer(id: LayerId(id), name: id, frames: const []),
    layerIndex: index,
  );

  test('a berth that leaves lets go of the row kept in it — and one that '
      'stays holds its own', () async {
    final berths = RowBerths();
    final kept = KeptByBerth<String>();
    final stays = row('stays', 0);
    final leaves = row('leaves', 1);
    WeakReference<Widget> keep(RowBerthMap map, TimelineDisplayRow row) {
      final id = row.layer.id.value;
      return WeakReference(kept.keep(map, row, id, () => Text(id)));
    }

    final both = berths.berthsFor([stays, leaves], world: 'cut');
    final held = keep(both, stays);
    final gone = keep(both, leaves);

    kept.keep(
      berths.berthsFor([stays], world: 'cut'),
      stays,
      'stays',
      () => fail('the row that stays was built again'),
    );
    await collectGarbage();

    expect(held.target, isNotNull, reason: 'a berth holds its own row');
    expect(gone.target, isNull, reason: 'the berth that left let go');
  });
}

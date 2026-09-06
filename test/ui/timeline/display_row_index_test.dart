import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

Layer _layer(String id) =>
    Layer(id: LayerId(id), name: id, frames: const [], timeline: const {});

/// The one walk under the ↑/↓ nav, the flip HUD and the span resolvers:
/// "the index of the current row, else the active layer's cells row".
/// Three hand loops used to spell it (round 8).
void main() {
  final upper = _layer('upper');
  final lower = _layer('lower');
  const lane = PropertyLaneRow(
    laneId: 'position',
    label: 'Position',
    keyedFrames: {},
  );
  // Top to bottom: upper, upper/position, lower, lower/position.
  final rows = [
    TimelineDisplayRow.layer(upper, layerIndex: 0),
    TimelineDisplayRow.lane(upper, lane, layerIndex: 0),
    TimelineDisplayRow.layer(lower, layerIndex: 1),
    TimelineDisplayRow.lane(lower, lane, layerIndex: 1),
  ];

  group('indexOfLayerRow', () {
    test('is the layer\'s CELLS row, never one of its lanes', () {
      expect(indexOfLayerRow(rows, const LayerId('lower')), 2);
      expect(indexOfLayerRow(rows, const LayerId('upper')), 0);
    });

    test('a lane row of the layer is not its cells row, whatever order '
        'the list arrives in', () {
      expect(
        indexOfLayerRow([
          TimelineDisplayRow.lane(upper, lane, layerIndex: 0),
          TimelineDisplayRow.layer(upper, layerIndex: 0),
        ], const LayerId('upper')),
        1,
      );
    });

    test('-1 for a layer that is not drawn, and for no layer at all', () {
      expect(indexOfLayerRow(rows, const LayerId('ghost')), -1);
      expect(indexOfLayerRow(rows, null), -1);
      expect(indexOfLayerRow(const [], const LayerId('lower')), -1);
    });
  });

  group('indexOfDisplayRow', () {
    test('the current row when it is on screen — a lane row included', () {
      expect(
        indexOfDisplayRow(
          rows,
          current: const LaneRowAddress(LayerId('lower'), 'position'),
          activeLayerId: const LayerId('upper'),
        ),
        3,
      );
    });

    test('falls back to the ACTIVE layer\'s cells row when the current row '
        'is not drawn — a track row, a hidden row, no row at all', () {
      expect(
        indexOfDisplayRow(
          rows,
          current: const TrackRowAddress(TrackId('t')),
          activeLayerId: const LayerId('lower'),
        ),
        2,
      );
      expect(
        indexOfDisplayRow(
          rows,
          current: const LaneRowAddress(LayerId('ghost'), 'position'),
          activeLayerId: const LayerId('upper'),
        ),
        0,
      );
      expect(
        indexOfDisplayRow(
          rows,
          current: null,
          activeLayerId: const LayerId('lower'),
        ),
        2,
      );
    });

    test('-1 when neither is drawn', () {
      expect(
        indexOfDisplayRow(
          rows,
          current: const TrackRowAddress(TrackId('t')),
          activeLayerId: const LayerId('ghost'),
        ),
        -1,
      );
      expect(indexOfDisplayRow(rows, current: null, activeLayerId: null), -1);
    });
  });
}

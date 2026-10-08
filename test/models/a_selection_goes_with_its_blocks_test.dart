import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';

/// F-264: a selection carried with the blocks a shove moved is the SAME
/// selection some frames along — every row it named, on either axis — and
/// no frame of it goes before the axis' first.
void main() {
  const a = LayerId('a');
  const b = LayerId('b');

  test('a cut-local selection shifted keeps its rows and moves its cells', () {
    const selection = TimelineFrameRangeSelection(
      layerId: a,
      startIndex: 4,
      endIndexExclusive: 7,
      layerIds: [a, b],
      rows: [LayerRowAddress(a), LayerRowAddress(b)],
    );

    expect(
      selection.shiftedBy(3),
      const TimelineFrameRangeSelection(
        layerId: a,
        startIndex: 7,
        endIndexExclusive: 10,
        layerIds: [a, b],
        rows: [LayerRowAddress(a), LayerRowAddress(b)],
      ),
    );
    expect(selection.shiftedBy(-4).startIndex, 0);
    expect(selection.shiftedBy(-4).endIndexExclusive, 3);
  });

  test('…and its start stops at the first cell: a pull closes the empty '
      'cells a selection began on', () {
    final shifted = const TimelineFrameRangeSelection(
      layerId: a,
      startIndex: 1,
      endIndexExclusive: 3,
    ).shiftedBy(-2);

    expect((shifted.startIndex, shifted.endIndexExclusive), (0, 1));
  });

  test('a track selection shifted keeps its track and rows and moves its '
      'frames — and stops at the first, too', () {
    const track = TrackId('t');
    const selection = TrackFrameRangeSelection(
      trackId: track,
      anchorRow: TrackRowAddress(track),
      rows: [TrackRowAddress(track), LayerRowAddress(a)],
      startFrame: 8,
      endFrameExclusive: 14,
    );

    expect(
      selection.shiftedBy(3),
      const TrackFrameRangeSelection(
        trackId: track,
        anchorRow: TrackRowAddress(track),
        rows: [TrackRowAddress(track), LayerRowAddress(a)],
        startFrame: 11,
        endFrameExclusive: 17,
      ),
    );
    final pulled = selection.shiftedBy(-10);
    expect((pulled.startFrame, pulled.endFrameExclusive), (0, 4));
  });
}

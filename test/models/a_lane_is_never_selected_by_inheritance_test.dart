import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';

/// 🚨★★★H20 (유저 2026-08-23, **두 번째로 같은 말**):
///
/// > 「블록 선택하고 이동할때 **트랜스폼쪽이나 fx쪽이 선택범위ui 작동**해버리는데
/// > 대체 누가? 내가 저번에 그렇게 하지 말라고한거같은데 **또 멋대로
/// > 만들어냈거든?** fx랑 블록이랑 같이 움직이게할거면 **둘다 유저가 선택하게
/// > 할거니까** 멋대로 fx도 같이 움직여야 편하지않나? 같은 니멋대로의 판단좀
/// > 그만좀해라. **선택한 곳만 움직이게하라고**」
///
/// ⛔The invented rule lived in one line of [TimelineFrameRangeSelection
/// .coversRow]: with no row list, a LANE row answered `coversLayer(...)` —
/// "selecting a layer's cells selects all of its lanes too". Every range
/// MOVE publishes without a row list, so every block move fell into it and
/// lit the whole transform group.
///
/// ★A lane is covered when the drag swept it, and never by inheritance.
void main() {
  const layerId = LayerId('A');
  const other = LayerId('B');

  TimelineFrameRangeSelection anchorOnly() => const TimelineFrameRangeSelection(
    layerId: layerId,
    startIndex: 4,
    endIndexExclusive: 8,
  );

  test('an anchor-only selection covers its CELLS row and nothing below it', () {
    final selection = anchorOnly();
    expect(selection.coversRow(const LayerRowAddress(layerId)), isTrue);
    expect(
      selection.coversRow(const LaneRowAddress(layerId, 'position')),
      isFalse,
      reason: '⛔this is H20 — the transform lane was never swept',
    );
    expect(
      selection.coversRow(const LaneRowAddress(layerId, 'opacity')),
      isFalse,
    );
    expect(selection.coversRow(const LayerRowAddress(other)), isFalse);
  });

  test('a MULTI-LAYER selection covers those layers\' cells rows — still not '
      'their lanes', () {
    const selection = TimelineFrameRangeSelection(
      layerId: layerId,
      startIndex: 4,
      endIndexExclusive: 8,
      layerIds: [layerId, other],
    );
    expect(selection.coversRow(const LayerRowAddress(layerId)), isTrue);
    expect(selection.coversRow(const LayerRowAddress(other)), isTrue);
    expect(
      selection.coversRow(const LaneRowAddress(other, 'scale')),
      isFalse,
      reason: 'the move carries blocks between cells rows; a lane is a row '
          'of its own and the user selects it themselves',
    );
  });

  test('a lane the drag DID sweep is still covered — the row list is the '
      'authority whenever there is one', () {
    const selection = TimelineFrameRangeSelection(
      layerId: layerId,
      startIndex: 4,
      endIndexExclusive: 8,
      rows: [
        LayerRowAddress(layerId),
        LaneRowAddress(layerId, 'position'),
      ],
    );
    expect(selection.coversRow(const LayerRowAddress(layerId)), isTrue);
    expect(
      selection.coversRow(const LaneRowAddress(layerId, 'position')),
      isTrue,
      reason: 'swept, so selected — the fix removes INHERITANCE, not the '
          'ability to select a lane',
    );
    expect(
      selection.coversRow(const LaneRowAddress(layerId, 'opacity')),
      isFalse,
      reason: 'and the lane NEXT to it, which the drag stopped short of, '
          'stays out',
    );
  });
}

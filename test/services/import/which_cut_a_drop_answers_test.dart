import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportDestination;

/// 🚨★★★WHICH CUT A DROP ANSWERED (pool-drop-picks-layer-or-cut).
///
/// 유저 2026-09-12: 「풀에서 캔버스에 배치시 새 레이어 고정이아니라 새
/// 레이어/새 컷 고를수있게 … 액티브 컷이 없는 상태에서 캔버스 떨구면 새 컷
/// 고정이고, 있으면 새 레이어/새 컷 지정가능」. A place only the active cut
/// has answers the cut; the canvas's spot was a default from its first words
/// (「활성 레이어 바로 위를 기본값으로 채운 배치 창」) and answers nothing
/// about it.
void main() {
  test('the canvas answers no cut — its spot is a default, and the window '
      'asks', () {
    expect(const AboveActiveLayerSpot().answeredDestination, isNull);
  });

  test('a row\'s frames, an SE row\'s cell and a gap between rows answer the '
      'ACTIVE cut — each is a place only the active cut has', () {
    const spots = <ImportLayerSpot>[
      RowFramesSpot(layerId: LayerId('a'), frameIndex: 0),
      SeCellSpot(layerId: LayerId('s'), frameIndex: 0),
      LayerSlotSpot(1),
    ];
    for (final spot in spots) {
      expect(
        spot.answeredDestination,
        ImportDestination.activeCutLayer,
        reason: '${spot.runtimeType}',
      );
    }
  });

  test('a track\'s frames on the storyboard answer a NEW cut — the drop '
      'named where on the track it goes', () {
    expect(
      const NewCutSpot(index: 1, leadingGapFrames: 4).answeredDestination,
      ImportDestination.newCut,
    );
  });
}

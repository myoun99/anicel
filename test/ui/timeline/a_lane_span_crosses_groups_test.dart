import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';

/// 🚨★★★A LANE SPAN IS SLICED OUT OF WHAT THE RAIL DREW.
///
/// 절대명령 2 (유저, 반복): 「**선택범위는 레이어 불문 자유롭게.** 행의
/// 종류로 막지 않는다」.
///
/// The span used to be three per-family walks tried in a `??` chain —
/// `effectLaneSpan`, then `seNameTagLaneSpan`, then `transformLaneSpan`.
/// Each knew only its own order list, so a drag whose ends sat in DIFFERENT
/// groups matched none of them and collapsed to the anchor alone: the
/// selection stopped at a boundary the user never drew.
///
/// ⛔They were also the same code three times — get an order, index both
/// ends, slice ([[no-copy-to-share]]). One function reading the drawn rows
/// answers for every family and for families nobody has written yet.
void main() {
  const layer = LayerId('L');
  LaneRowAddress lane(String id) => LaneRowAddress(layer, id);

  /// A rail with three groups open at once: a transform group, an SE
  /// name-tag group, and an effect's lanes. The old chain could name a span
  /// inside any ONE of these and nothing across two.
  final drawn = <TimelineRowAddress?>[
    LayerRowAddress(layer),
    lane('transform-group'),
    lane('position'),
    lane('scale'),
    lane('se-name-tag-group'),
    lane('se-name-tag-text'),
    lane('effect:blur/group'),
    lane('effect:blur/radius'),
  ];

  test('🚨a drag ACROSS two groups keeps every lane between them', () {
    expect(
      laneSpanOverDrawnRows(
        rows: drawn,
        layerId: layer,
        laneId: 'scale',
        headLaneId: 'se-name-tag-text',
      ),
      ['scale', 'se-name-tag-group', 'se-name-tag-text'],
      reason:
          '유저: 「선택범위는 레이어 불문 자유롭게」 — the old chain returned '
          '[scale] alone here, because no single family order held both ends',
    );
  });

  test('and across all three, header rows included', () {
    expect(
      laneSpanOverDrawnRows(
        rows: drawn,
        layerId: layer,
        laneId: 'position',
        headLaneId: 'effect:blur/radius',
      ),
      [
        'position',
        'scale',
        'se-name-tag-group',
        'se-name-tag-text',
        'effect:blur/group',
        'effect:blur/radius',
      ],
      reason: 'a group HEADER is a row in the span like any other (R9 #20)',
    );
  });

  test('the drag reads the same either way round', () {
    expect(
      laneSpanOverDrawnRows(
        rows: drawn,
        layerId: layer,
        laneId: 'se-name-tag-text',
        headLaneId: 'scale',
      ),
      ['scale', 'se-name-tag-group', 'se-name-tag-text'],
      reason: 'dragging up names the same rows as dragging down',
    );
  });

  test('⛔a LAYER row inside the run is not a lane and is not collected', () {
    // The rail stacks kinds; only lanes belong to a LANE span. This is not
    // "blocked by row kind" — the layer row is a different subject with its
    // own selection, and putting its id here would be a lane id that does
    // not exist.
    expect(
      laneSpanOverDrawnRows(
        rows: drawn,
        layerId: layer,
        laneId: 'transform-group',
        headLaneId: 'position',
      ),
      ['transform-group', 'position'],
    );
  });

  test('⛔an endpoint that is not on screen keeps only the anchor', () {
    // A collapsed group draws no members, so a span across it cannot be
    // honestly named — the same answer the family walks gave for an id
    // missing from their order.
    expect(
      laneSpanOverDrawnRows(
        rows: drawn,
        layerId: layer,
        laneId: 'position',
        headLaneId: 'effect:glow/radius',
      ),
      ['position'],
    );
  });

  test('⛔another layer\'s lane of the same name is not this span', () {
    // The rows carry the owner, and a rail can draw two layers at once.
    final mixed = <TimelineRowAddress?>[
      lane('position'),
      LaneRowAddress(const LayerId('OTHER'), 'scale'),
      lane('scale'),
    ];
    expect(
      laneSpanOverDrawnRows(
        rows: mixed,
        layerId: layer,
        laneId: 'position',
        headLaneId: 'scale',
      ),
      ['position', 'scale'],
      reason:
          'the other layer\'s row sits between them and is stepped over, '
          'not adopted',
    );
  });
}

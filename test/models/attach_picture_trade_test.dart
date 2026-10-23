import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attach_picture_trade.dart';
import 'package:anicel/src/models/cel_rekey.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';

/// F-330 · I-98: a rows' hop on the same frames inside an attach group
/// trades their pictures — each row's cel for the base's cel, by the law a
/// move's landed-on blocks go back by.
void main() {
  const baseId = LayerId('base');
  final base = Layer(id: baseId, name: 'A', frames: const []);

  Layer synced(String id, {Map<String, String>? links}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    attachedToLayerId: baseId,
    baseFrameLinks: {
      for (final MapEntry(:key, :value)
          in (links ?? {'b1': '$id-1', 'b2': '$id-2'}).entries)
        FrameId(key): FrameId(value),
    },
  );

  final above = synced('above');
  final upper = synced('upper');

  /// The trade as `row:cel → row:cel` lines, for reading.
  List<String> read(List<CelPictureMove>? moves) => [
    for (final move in moves!)
      '${move.fromRow.value}:${move.fromCel.value} → '
          '${move.toRow.value}:${move.toCel.value}',
  ];

  test('a row carried one row on trades its picture with that row\'s, cel '
      'by cel', () {
    final moves = picturesTradedInAttachGroup(
      group: [above, base],
      sources: [above.id],
      rowDelta: 1,
      baseCels: const [FrameId('b1'), FrameId('b2')],
    );

    expect(read(moves), [
      'above:above-1 → base:b1',
      'base:b1 → above:above-1',
      'above:above-2 → base:b2',
      'base:b2 → above:above-2',
    ]);
  });

  test('two rows carried over a third: each picture goes one on, and the '
      'row passed over hands its own to the row left', () {
    final moves = picturesTradedInAttachGroup(
      group: [upper, above, base],
      sources: [upper.id, above.id],
      rowDelta: 1,
      baseCels: const [FrameId('b1')],
    );

    expect(read(moves), [
      'upper:upper-1 → above:above-1',
      'above:above-1 → base:b1',
      'base:b1 → upper:upper-1',
    ]);
  });

  test('carried up, the same law the other way', () {
    final moves = picturesTradedInAttachGroup(
      group: [upper, above, base],
      sources: [base.id],
      rowDelta: -2,
      baseCels: const [FrameId('b1')],
    );

    expect(read(moves), [
      'base:b1 → upper:upper-1',
      'upper:upper-1 → base:b1',
    ]);
  });

  test('a cel the selection names twice is traded once', () {
    final moves = picturesTradedInAttachGroup(
      group: [above, base],
      sources: [above.id],
      rowDelta: 1,
      baseCels: const [FrameId('b1'), FrameId('b1')],
    );

    expect(moves, hasLength(2));
  });

  test('no trade: carried off the group, a row not of it, no hop, nothing '
      'selected, or a row with no cel for one of the base\'s', () {
    List<CelPictureMove>? trade(
      List<LayerId> sources,
      int rowDelta, {
      List<Layer>? group,
    }) => picturesTradedInAttachGroup(
      group: group ?? [above, base],
      sources: sources,
      rowDelta: rowDelta,
      baseCels: const [FrameId('b1'), FrameId('b2')],
    );

    expect(trade([base.id], 1), isNull, reason: 'off the group');
    expect(trade([above.id], -1), isNull, reason: 'off the group');
    expect(trade([upper.id], 1), isNull, reason: 'a row not of the group');
    expect(trade([above.id], 0), isNull, reason: 'no hop');
    expect(trade([], 1), isNull, reason: 'nothing selected');
    expect(
      trade(
        [above.id],
        1,
        group: [
          synced('above', links: {'b1': 'above-1'}),
          base,
        ],
      ),
      isNull,
      reason: 'an orphan has nowhere to hang a picture',
    );
  });
}

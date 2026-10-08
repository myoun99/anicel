import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';

/// 🗣️I-73 (유저 2026-10-08): 「콘티레이어 권고한대로 머리만 한벌 ok」 ·
/// 「7. 맞음」 (the conte rows under the V row: +N · the base · −N). A cut's
/// conte is a GROUP — the base and the attach rows riding it — and a row's
/// SEAT is what names it the same way in every cut.
void main() {
  Layer row(
    String id, {
    LayerKind kind = LayerKind.storyboard,
    String? ridesOn,
    AttachedPlacement placement = AttachedPlacement.above,
    String? folder,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: const [],
    timeline: const {},
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: placement,
    folderId: folder == null ? null : LayerId(folder),
  );

  Cut cutOf(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  /// An attach row BELOW [base].
  Layer under(String id, String base) =>
      row(id, ridesOn: base, placement: AttachedPlacement.below);

  /// A group's rows as `(seat, id)`, top row first.
  List<(int, String)> seatsOf(Cut cut) => [
    for (final seat in conteGroupOf(cut)) (seat.seat, seat.row.id.value),
  ];

  /// The cut's list runs bottom-up: `[below…, base, above…]`.
  Cut full() => cutOf('full', [
    row('cel', kind: LayerKind.animation),
    under('conte-2', 'conte'),
    under('conte-1', 'conte'),
    row('conte'),
    row('conte+1', ridesOn: 'conte'),
    row('conte+2', ridesOn: 'conte'),
  ]);

  group('the cut\'s conte is its storyboard row that rides no other', () {
    test('🚨an attach row BELOW the conte is a storyboard row too, and '
        'stands before it in the list — it is not the cut\'s conte', () {
      // Measured 2026-10-08 on the app: 「the first storyboard row」 named
      // `conte-2` here.
      expect(storyboardLayerForCut(full())?.id, const LayerId('conte'));
      expect(
        [for (final layer in storyboardLayersOfCut(full())) layer.id.value],
        ['conte'],
        reason: 'one conte, whatever rides it',
      );
    });

    test('a cut with none has none — and its attach rows are not one', () {
      expect(
        storyboardLayerForCut(
          cutOf('bare', [row('cel', kind: LayerKind.animation)]),
        ),
        isNull,
      );
      final orphaned = cutOf('orphaned', [
        row('conte+1', ridesOn: 'gone'),
      ]);
      expect(storyboardLayerForCut(orphaned), isNull);
      expect(cutAcceptsAnotherStoryboardLayer(orphaned), isTrue);
    });

    test('a cut that has its conte takes no second one — but the conte '
        'itself may be asked again', () {
      expect(cutAcceptsAnotherStoryboardLayer(full()), isFalse);
      expect(
        cutAcceptsAnotherStoryboardLayer(
          full(),
          exceptLayerId: const LayerId('conte'),
        ),
        isTrue,
      );
      expect(
        cutAcceptsAnotherStoryboardLayer(
          full(),
          exceptLayerId: const LayerId('conte+1'),
        ),
        isFalse,
        reason: 'an attach row is not the conte it would be excepted as',
      );
    });

    test('a singleton kind is held by the row that stands by itself', () {
      expect(
        holdsSingletonOfKind(full().layers, LayerKind.storyboard),
        isTrue,
      );
      expect(
        holdsSingletonOfKind([
          row('conte+1', ridesOn: 'gone'),
        ], LayerKind.storyboard),
        isFalse,
        reason: 'a row riding another is not the cut\'s one',
      );
      expect(holdsSingletonOfKind(full().layers, LayerKind.camera), isFalse);
    });
  });

  group('the seats of a group', () {
    test('top row first: the rows above from the farthest, the base, the '
        'rows below from the nearest', () {
      expect(
        seatsOf(full()),
        [
          (2, 'conte+2'),
          (1, 'conte+1'),
          (0, 'conte'),
          (-1, 'conte-1'),
          (-2, 'conte-2'),
        ],
      );
    });

    test('a seat counts ROWS: an organizer folder among them is passed '
        'over, and the rows it files keep their place', () {
      final filed = cutOf('filed', [
        row('conte'),
        row('conte+1', ridesOn: 'conte', folder: 'process'),
        row('process', kind: LayerKind.folder),
        row('conte+2', ridesOn: 'conte'),
      ]);

      expect(
        seatsOf(filed),
        [(2, 'conte+2'), (1, 'conte+1'), (0, 'conte')],
      );
    });

    test('a row riding ANOTHER base is no seat of the conte', () {
      final mixed = cutOf('mixed', [
        row('cel', kind: LayerKind.animation),
        row('cel+1', kind: LayerKind.animation, ridesOn: 'cel'),
        row('conte'),
      ]);

      expect(
        [for (final seat in conteGroupOf(mixed)) seat.seat],
        [0],
      );
      expect(conteSeatOf(mixed, const LayerId('cel+1')), isNull);
    });

    test('a seat finds its row, and a row its seat', () {
      expect(conteSeatOf(full(), const LayerId('conte-2')), -2);
      expect(conteSeatOf(full(), const LayerId('conte')), 0);
      expect(conteSeatOf(full(), const LayerId('cel')), isNull);
      expect(conteRowAtSeat(full(), 1)?.id, const LayerId('conte+1'));
      expect(conteRowAtSeat(full(), 3), isNull);
    });

    test('a cut with no conte has no group', () {
      final bare = cutOf('bare', [row('cel', kind: LayerKind.animation)]);
      expect(conteGroupOf(bare), isEmpty);
      expect(conteSeatOf(bare, const LayerId('cel')), isNull);
      expect(conteRowAtSeat(bare, 0), isNull);
    });
  });

  group('the seats of a TRACK\'s cuts', () {
    Cut above(String id) => cutOf(id, [
      row('$id-conte'),
      row('$id-conte+1', ridesOn: '$id-conte'),
    ]);
    Cut below(String id) => cutOf(id, [
      under('$id-conte-2', '$id-conte'),
      under('$id-conte-1', '$id-conte'),
      row('$id-conte'),
    ]);
    Cut bare(String id) =>
        cutOf(id, [row('$id-cel', kind: LayerKind.animation)]);

    test('every seat any cut holds, top row first', () {
      expect(conteSeatsOf([above('a'), bare('b'), below('c')]), [1, 0, -1, -2]);
    });

    test('the base\'s seat is there before any cut has a conte', () {
      expect(conteSeatsOf([bare('a'), bare('b')]), [0]);
      expect(conteSeatsOf(const []), [0]);
    });

    test('the row that speaks for a seat is the first cut\'s that holds '
        'one', () {
      final cuts = [bare('a'), below('b'), above('c')];
      expect(conteHeadRowAt(cuts, 0)?.id, const LayerId('b-conte'));
      expect(conteHeadRowAt(cuts, 1)?.id, const LayerId('c-conte+1'));
      expect(conteHeadRowAt(cuts, -2)?.id, const LayerId('b-conte-2'));
      expect(conteHeadRowAt(cuts, 2), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';

/// 🚨A5-4 (유저 2026-08-22) — **THE CAMERA SECTION HAS AN ORDER.**
///
/// > 「위에서부터 **카메라/트랜지션/디렉션** 고정. 지금 **디렉션을 카메라 위로
/// > 옮길 수 있고 되돌릴 수 없다.** 카메라·트랜지션 = **드래그 불가**,
/// > 디렉션 = **디렉션끼리만**. 타임시트에도 이 위치관계 반영」
///
/// ⚠️The order was never written down. All three kinds share ONE section, so
/// the cross-section refusal never fired between them; what put them in the
/// right places was two unrelated insertion sites, and neither repairs a
/// list that has been disturbed.
///
/// 🎯THE IRREVERSIBILITY was an asymmetry, not a re-bucketing: the section
/// is read off the row BELOW a slot, so one gap answers differently
/// depending on which side is asked. A Direction row could climb past the
/// camera and then find the single gap that would undo it refused, because
/// that gap's `below` is a drawing row.
Layer _row(String id, {LayerKind kind = LayerKind.animation}) =>
    Layer(id: LayerId(id), name: id, frames: const [], kind: kind);

void main() {
  /// The default cut's shape: a drawing row, a Direction row, the camera.
  List<Layer> stack() => [
    _row('draw'),
    _row('dir', kind: LayerKind.instruction),
    _row('cam', kind: LayerKind.camera),
  ];

  group('the order is a rule, not an accident', () {
    test('a disturbed list is put back — camera on top, then transition, '
        'then directions', () {
      final disturbed = [
        _row('draw'),
        _row('cam', kind: LayerKind.camera),
        _row('trans', kind: LayerKind.transition),
        _row('dir', kind: LayerKind.instruction),
      ];
      expect(
        sectionedLayerOrder(disturbed).map((l) => l.id.value).toList(),
        ['draw', 'dir', 'trans', 'cam'],
        reason: 'raw order puts the top of the screen LAST — this is the '
            'repair for a project already saved with the rows swapped',
      );
    });

    test('and several directions keep their own order among themselves', () {
      final many = [
        _row('cam', kind: LayerKind.camera),
        _row('d2', kind: LayerKind.instruction),
        _row('d1', kind: LayerKind.instruction),
      ];
      expect(
        sectionedLayerOrder(many).map((l) => l.id.value).toList(),
        ['d2', 'd1', 'cam'],
        reason: 'the rank sort is STABLE, which is what leaves direction '
            'rows re-orderable — 「디렉션끼리만」 needs them to move at all',
      );
    });
  });

  group('a direction row cannot leave its own rank', () {
    test('★it cannot climb above the camera — the move the user could not '
        'undo', () {
      // Slot 3 is past the camera in raw order, which is above it on screen.
      expect(
        resolveLayerDrop(
          stack: stack(),
          movingId: const LayerId('dir'),
          insertAt: 3,
        ),
        isNull,
        reason: 'this landing used to be LEGAL, and the single gap that '
            'would have put the row back was refused — so the fix is to '
            'refuse the climb rather than to legalise the return',
      );
    });

    test('and it cannot drop into the drawing section either', () {
      expect(
        resolveLayerDrop(
          stack: stack(),
          movingId: const LayerId('dir'),
          insertAt: 0,
        ),
        isNull,
      );
    });

    test('but two direction rows still trade places', () {
      final two = [
        _row('draw'),
        _row('d1', kind: LayerKind.instruction),
        _row('d2', kind: LayerKind.instruction),
        _row('cam', kind: LayerKind.camera),
      ];
      final order = resolveLayerDrop(
        stack: two,
        movingId: const LayerId('d1'),
        insertAt: 3,
      );
      expect(order, isNotNull, reason: '「디렉션끼리만」 — but they DO move');
      expect(order!.order.map((id) => id.value).toList(), [
        'draw',
        'd2',
        'd1',
        'cam',
      ]);
    });
  });

  group('the kinds that hold their place say so', () {
    test('camera and transition do not re-order in a cut; everything else '
        'does', () {
      expect(layerKindReordersInCut(LayerKind.camera), isFalse);
      expect(layerKindReordersInCut(LayerKind.transition), isFalse);
      for (final kind in [
        LayerKind.animation,
        LayerKind.instruction,
        LayerKind.se,
        LayerKind.folder,
        LayerKind.image,
      ]) {
        expect(
          layerKindReordersInCut(kind),
          isTrue,
          reason: '$kind has no fixed seat',
        );
      }
    });

    test('and the camera itself is refused by the policy too — the grip is '
        'gone, but the rule does not depend on the grip', () {
      expect(
        resolveLayerDrop(
          stack: stack(),
          movingId: const LayerId('cam'),
          insertAt: 1,
        ),
        isNull,
      );
    });
  });
}

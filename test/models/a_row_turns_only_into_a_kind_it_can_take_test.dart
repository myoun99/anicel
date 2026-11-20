import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_kind_choices.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// 🗣️F-613 (유저 2026-11-19): 「레이어의 아이콘 누르면 변경가능한 대상 뜨고
/// 변경가능하게. 우선 액션란의 이미지-애니메이션-콘티 이 세가지 … 규칙은
/// 다른거 참고해서」 — which rows the type button turns, and into what, by
/// the rules the kinds already keep.
void main() {
  /// A row exposing [cels] one block each, in order — a cel named twice is
  /// ONE cel shown twice.
  Layer row(
    String id, {
    LayerKind kind = LayerKind.animation,
    List<String> cels = const [],
    String? ridesOn,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [
      for (final cel in cels.toSet())
        Frame(id: FrameId(cel), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final (at, cel) in cels.indexed)
        at * 2: TimelineExposure.drawing(FrameId(cel), length: 2),
    },
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
  );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  group('the action section\'s three picture kinds are the choices', () {
    test('image · animation · conte, in that order', () {
      expect(layerKindChoices, [
        LayerKind.image,
        LayerKind.animation,
        LayerKind.storyboard,
      ]);
    });

    test('a row of one of them turns; a row of any other kind does not', () {
      for (final kind in LayerKind.values) {
        expect(
          turnsBetweenKinds(row('r', kind: kind)),
          layerKindChoices.contains(kind),
          reason: '$kind',
        );
      }
    });

    test('⛔an attach row wears its base\'s kind — it does not turn', () {
      final rider = row('rider', ridesOn: 'base');
      expect(turnsBetweenKinds(rider), isFalse);
      final cut = cutOf([row('base'), rider]);
      for (final kind in layerKindChoices) {
        expect(canTurnInto(rider, kind, cut: cut), isFalse, reason: '$kind');
      }
    });

    test('⛔nothing turns into a kind outside them', () {
      final cel = row('cel', cels: ['a']);
      final cut = cutOf([cel]);
      for (final kind in LayerKind.values) {
        if (layerKindChoices.contains(kind)) continue;
        expect(canTurnInto(cel, kind, cut: cut), isFalse, reason: '$kind');
      }
      final folder = row('f', kind: LayerKind.folder);
      expect(
        canTurnInto(folder, LayerKind.animation, cut: cutOf([folder])),
        isFalse,
      );
    });
  });

  group('the rules the kinds already keep', () {
    test('a cut holds ONE conte — a second row is shown it and refused', () {
      final cel = row('cel', cels: ['a']);
      expect(
        canTurnInto(cel, LayerKind.storyboard, cut: cutOf([cel])),
        isTrue,
      );
      final conte = row('conte', kind: LayerKind.storyboard, cels: ['k']);
      expect(
        canTurnInto(cel, LayerKind.storyboard, cut: cutOf([cel, conte])),
        isFalse,
      );
    });

    test('a conte\'s attach row is not the conte a second one would make', () {
      final cel = row('cel', cels: ['a']);
      final rider = row('r', kind: LayerKind.storyboard, ridesOn: 'cel');
      expect(
        canTurnInto(cel, LayerKind.storyboard, cut: cutOf([cel, rider])),
        isTrue,
      );
    });

    test('an image holds one cel: 「셀이 여럿인 곳은 그 차이를 보여 주되 고를 '
        '수 없다」', () {
      final cut = cutOf(const []);
      bool turns(List<String> cels) =>
          canTurnInto(row('r', cels: cels), LayerKind.image, cut: cut);
      expect(turns(['a']), isTrue);
      expect(turns(['a', 'a']), isTrue, reason: 'one cel, shown twice');
      expect(turns(['a', 'b']), isFalse);
      expect(
        turns(const []),
        isTrue,
        reason: '🗣️F-613-Q1 「허용 — 빈 이미지 행이 된다」 — an image row of '
            'none (F-98)',
      );
    });

    test('a conte holding several cels turns into an image by the same '
        'law', () {
      final cut = cutOf(const []);
      expect(
        canTurnInto(
          row('k', kind: LayerKind.storyboard, cels: ['a', 'b']),
          LayerKind.image,
          cut: cut,
        ),
        isFalse,
      );
      expect(
        canTurnInto(
          row('k', kind: LayerKind.storyboard, cels: ['a']),
          LayerKind.image,
          cut: cut,
        ),
        isTrue,
      );
    });

    test('anything of the three turns into an animation', () {
      final cut = cutOf(const []);
      for (final kind in layerKindChoices) {
        expect(
          canTurnInto(
            row('r', kind: kind, cels: ['a', 'b']),
            LayerKind.animation,
            cut: cut,
          ),
          isTrue,
          reason: '$kind',
        );
      }
    });

    test('a row can always stay what it is — an empty image row (F-98) and '
        'the cut\'s own conte included', () {
      final empty = row('i', kind: LayerKind.image);
      expect(
        canTurnInto(empty, LayerKind.image, cut: cutOf([empty])),
        isTrue,
      );
      final conte = row('conte', kind: LayerKind.storyboard, cels: ['k']);
      final other = row('other', kind: LayerKind.storyboard, cels: ['o']);
      expect(
        canTurnInto(conte, LayerKind.storyboard, cut: cutOf([conte, other])),
        isTrue,
      );
    });
  });
}

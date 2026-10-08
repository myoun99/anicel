import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformPropertyLanes;

/// WHAT A ROW'S SCALE LANE HOLDS (`transform-fx-scale-x-y`, stage three).
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
/// 반전)」, of the option whose terms were 「카메라는 줌 하나 그대로」.
/// 🗣️F-256-Q2 (same day): 「연동 스위치(AE 의 사슬) — 켜면 한 칸을 바꿀 때
/// 다른 칸도 같은 비율로」 · 「이걸 트랜스폼등 fx에도 적용하고싶음」.
void main() {
  CanvasPoint scale(double x, double y) => CanvasPoint(x: x, y: y);

  Matcher near(double x, double y) => isA<CanvasPoint>()
      .having((point) => point.x, 'across', closeTo(x, 1e-9))
      .having((point) => point.y, 'down', closeTo(y, 1e-9));

  group('a row says which form its Scale takes', () {
    test('the camera one zoom, every other row two scales', () {
      for (final kind in LayerKind.values) {
        final row = Layer(
          id: LayerId('row-${kind.name}'),
          name: kind.name,
          frames: const [],
          kind: kind,
        );
        expect(
          scaleLaneFormOf(row),
          kind == LayerKind.camera ? isA<OneZoom>() : isA<TwoScales>(),
          reason: kind.name,
        );
      }
    });

    // 🗣️`transform-fx-scale-x-y-Q1` (유저 2026-10-07): 「Scale 행에 사슬 버튼
    // — 변형 도구의 「배율 연동」과 한 스위치」.
    test('🔗two scales can be linked and one zoom cannot — and on the rail '
        'the Scale lane alone says so', () {
      expect(const TwoScales().links, isTrue);
      expect(const OneZoom().links, isFalse);

      List<String> linkable(ScaleLaneForm form) => [
        for (final lane in transformPropertyLanes(
          TransformTrack.empty(),
          scaleForm: form,
          includeAnchorAndOpacity: true,
        ))
          if (lane.linkable) lane.laneId,
      ];
      expect(linkable(const TwoScales()), ['scale']);
      expect(linkable(const OneZoom()), isEmpty);
    });
  });

  group("a camera's one zoom", () {
    const form = OneZoom();

    CanvasPoint? typed(String input, {bool linked = false}) =>
        form.typed(input, current: uniformScale(1), linked: linked);

    test('prints as one percent', () {
      expect(form.label(uniformScale(1.5)), '150%');
      expect(form.label(uniformScale(4 / 3)), '133.3%');
    });

    test('reads one number, with or without its percent', () {
      expect(typed('150%'), uniformScale(1.5));
      expect(typed(' 150 '), uniformScale(1.5));
      expect(typed('150%', linked: true), uniformScale(1.5));
    });

    test('⛔a zoom is above zero, and one number', () {
      for (final input in ['0', '-50%', 'abc', '', 'NaN', 'Infinity']) {
        expect(typed(input), isNull, reason: '「$input」');
      }
      expect(typed('150, 80%'), isNull, reason: 'two numbers are not a zoom');
    });

    test('scrubs along the drag, half a percent a pixel', () {
      expect(form.scrubbed('150%', const Offset(40, 0)), '170%');
      expect(form.scrubbed('150%', const Offset(-40, 0)), '130%');
      expect(
        form.scrubbed('150%', const Offset(0, 40)),
        '150%',
        reason: 'one number has no second axis',
      );
      expect(form.scrubbed('garbage', const Offset(1, 0)), isNull);
    });
  });

  group("a layer's two scales", () {
    const form = TwoScales();

    test('print across, then down, the percent worn once', () {
      expect(form.label(scale(1.5, 0.8)), '150, 80%');
      expect(form.label(scale(-1, 1)), '-100, 100%', reason: 'flipped');
      expect(form.label(scale(0, 1)), '0, 100%', reason: 'shown as nothing');
      expect(form.label(scale(4 / 3, 0.5)), '133.3, 50%');
    });

    group('typed', () {
      CanvasPoint? unlinked(String input, {CanvasPoint? current}) => form.typed(
        input,
        current: current ?? uniformScale(1),
        linked: false,
      );

      CanvasPoint? linked(String input, CanvasPoint current) =>
          form.typed(input, current: current, linked: true);

      test('ONE number is both scales, chain or no chain', () {
        expect(unlinked('150'), uniformScale(1.5));
        expect(unlinked('150%'), uniformScale(1.5));
        expect(linked('150%', scale(2, 0.5)), uniformScale(1.5));
        expect(unlinked('-100'), uniformScale(-1));
        expect(unlinked('0'), uniformScale(0));
      });

      test('TWO are across and down — a minus flips, zero shows nothing', () {
        expect(unlinked('150, 80%'), scale(1.5, 0.8));
        expect(unlinked('-100, 100%'), scale(-1, 1));
        expect(unlinked('100, 0%'), scale(1, 0));
        expect(unlinked(' 150 ,80 '), scale(1.5, 0.8));
      });

      test('⛔what is not one or two finite numbers is not a scale', () {
        for (final input in [
          'abc',
          '',
          '150, abc%',
          '150,',
          '150, 80, 20%',
          'NaN, 100%',
          '100, Infinity%',
        ]) {
          expect(unlinked(input), isNull, reason: '「$input」');
          expect(linked(input, uniformScale(1)), isNull, reason: '「$input」');
        }
      });

      test('🔗the box left as it was shown follows the step of the other', () {
        // Across typed, down left: down goes by the same ratio.
        expect(linked('200, 50%', scale(1, 0.5)), near(2, 1));
        // Down typed, across left.
        expect(linked('100, 25%', scale(1, 0.5)), near(0.5, 0.25));
      });

      test('🔗unlinked, the same typing moves its own number alone', () {
        expect(
          unlinked('200, 50%', current: scale(1, 0.5)),
          scale(2, 0.5),
        );
        expect(
          unlinked('100, 25%', current: scale(1, 0.5)),
          scale(1, 0.25),
        );
      });

      test('🔗BOTH typed, or neither, is what was typed', () {
        expect(linked('200, 80%', scale(1, 0.5)), scale(2, 0.8));
        expect(linked('100, 50%', scale(1, 0.5)), scale(1, 0.5));
      });

      test('🔗the one carried keeps its own sign', () {
        // Across is flipped by the typing; down stays the way round it was.
        expect(linked('-200, -50%', scale(1, -0.5)), near(-2, -1));
        expect(linked('-200, 50%', scale(1, 0.5)), near(-2, 1));
      });

      test('🔗a scale standing on zero has no ratio: the other stays', () {
        expect(linked('50, 50%', scale(0, 0.5)), near(0.5, 0.5));
        expect(linked('100, 50%', scale(1, 0)), near(1, 0.5));
      });

      test('🔗「left as it was shown」 is asked of the PRINT, and the carry is '
          'taken from the scale itself', () {
        // The lane prints 133.3 for 1.3333…: the box hands 133.3 back
        // untouched, and that is not a typed across.
        const third = 4 / 3;
        expect(
          linked('133.3, 150%', scale(third, 0.75)),
          near(third * 2, 1.5),
          reason: 'across was left, and doubles from 1.3333…, not from 1.333',
        );
        // The same down the other way: 33.3 is what 0.3333… prints as.
        expect(
          linked('200, 33.3%', scale(1, 1 / 3)),
          near(2, 2 / 3),
          reason: 'down was left, and doubles from 0.3333…, not from 0.333',
        );
        // …while a number that prints differently IS typed.
        expect(
          linked('133.4, 75%', scale(third, 0.75)),
          near(1.334, 0.75 * (1.334 / third)),
        );
      });
    });

    group('scrubbed', () {
      test('ONE drag scrubs ONE number — the one it runs along more', () {
        expect(form.scrubbed('150, 80%', const Offset(40, 0)), '170, 80%');
        expect(form.scrubbed('150, 80%', const Offset(0, 40)), '150, 100%');
        expect(
          form.scrubbed('150, 80%', const Offset(40, 10)),
          '170, 80%',
          reason: 'a hand drifting off its line does not move both',
        );
        expect(form.scrubbed('150, 80%', const Offset(10, -40)), '150, 60%');
        expect(
          form.scrubbed('150, 80%', const Offset(20, 20)),
          '160, 80%',
          reason: 'even, it is across',
        );
      });

      test('a scrub runs through zero into a flip', () {
        expect(form.scrubbed('10, 100%', const Offset(-20, 0)), '0, 100%');
        expect(form.scrubbed('10, 100%', const Offset(-40, 0)), '-10, 100%');
      });

      test('⛔a label that is not two numbers is not scrubbed', () {
        for (final label in ['150%', 'garbage', '150, abc%', '1, 2, 3%']) {
          expect(
            form.scrubbed(label, const Offset(10, 0)),
            isNull,
            reason: '「$label」',
          );
        }
      });

      test('🔗what a scrub writes is what the chain reads: the other number '
          'is handed back as shown, so linked it follows', () {
        final current = scale(1.5, 0.75);
        final scrubbed = form.scrubbed(
          form.label(current),
          const Offset(300, 0),
        )!;
        expect(scrubbed, '300, 75%');
        expect(
          form.typed(scrubbed, current: current, linked: true),
          near(3, 1.5),
        );
        expect(
          form.typed(scrubbed, current: current, linked: false),
          scale(3, 0.75),
        );
      });
    });
  });
}

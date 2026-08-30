import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';

/// **R27 #16 — the direction row is a row you can draw on.**
///
/// 유저 확정 2026-08-25: 「일단 유효야. **카메라랑 트랜지션은 지금처럼
/// 못그리는데 디렉션레이어는 그림 그릴수있는 행으로**」.
///
/// 🚨The change that made it possible is a SPLIT, not a flag: "carries
/// instructions" had been answering two questions at once — *does this row
/// draw span overlays* and *does this row have a timeline of its own* — and
/// they had never disagreed because nothing was ever both. A direction row
/// is both now.
void main() {
  test('a direction row draws, and carries its instructions too', () {
    expect(layerKindIsDrawingCel(LayerKind.instruction), isTrue);
    expect(layerKindAcceptsBrushInput(LayerKind.instruction), isTrue);
    expect(
      layerKindCarriesInstructions(LayerKind.instruction),
      isTrue,
      reason: 'the spans are what the row is FOR — they did not go away',
    );
    expect(
      layerKindBandIsInstructionsOnly(LayerKind.instruction),
      isFalse,
      reason: 'its band is its own timeline now, with the spans over it',
    );
  });

  test('⛔and the camera and transition rows are untouched', () {
    for (final kind in [LayerKind.camera, LayerKind.transition]) {
      expect(layerKindIsDrawingCel(kind), isFalse, reason: '$kind');
      expect(layerKindAcceptsBrushInput(kind), isFalse, reason: '$kind');
    }
    expect(
      layerKindBandIsInstructionsOnly(LayerKind.transition),
      isTrue,
      reason:
          'the transition row is instructions-only and stays so — its '
          'placement in a cut is a projection, not a drawing',
    );
  });

  test('the band predicate answers for every kind, once', () {
    for (final kind in LayerKind.values) {
      expect(
        layerKindBandIsInstructionsOnly(kind),
        layerKindCarriesInstructions(kind) && !layerKindIsDrawingCel(kind),
        reason: '$kind — one derivation, so the two halves cannot drift',
      );
      if (layerKindBandIsInstructionsOnly(kind)) {
        expect(
          layerKindAcceptsBrushInput(kind),
          isFalse,
          reason: '$kind has no timeline to draw into',
        );
      }
    }
  });

  group('🚨a row you can draw on is a row you can give a cel', () {
    // 유저 2026-08-27: 「그림은 그려지지도않아. **프레임이 없다고 뜨거든**」.
    //
    // That notice means 「this layer takes a brush, but there is no cel at
    // this frame」 — so the brush gate was open and the CREATION gate was
    // shut. R27 #16 flipped `layerKindIsDrawingCel` and left
    // `layerKindHoldsDrawings`, which is what `canCreateDrawingAtCurrentFrame`
    // asks.
    test('a direction row takes an authored cel; camera and transition do '
        'not', () {
      expect(layerKindTakesAuthoredCels(LayerKind.instruction), isTrue);
      for (final kind in [
        LayerKind.camera,
        LayerKind.transition,
        LayerKind.folder,
        LayerKind.adjustment,
      ]) {
        expect(layerKindTakesAuthoredCels(kind), isFalse, reason: '$kind');
      }
    });

    test('⛔the SE row keeps it — it holds cels without being one', () {
      // The two predicates disagree on exactly two kinds, and this is the
      // other one. A split that quietly dropped SE would take frame
      // creation off the sound row.
      expect(layerKindIsDrawingCel(LayerKind.se), isFalse);
      expect(layerKindTakesAuthoredCels(LayerKind.se), isTrue);
    });

    test('the derivation is pinned, so the halves cannot drift again', () {
      for (final kind in LayerKind.values) {
        expect(
          layerKindTakesAuthoredCels(kind),
          layerKindHoldsDrawings(kind) || layerKindIsDrawingCel(kind),
          reason: '$kind — one derivation',
        );
      }
    });

    test('⛔THE FURNITURE DID NOT FOLLOW — that is the whole point of the '
        'split', () {
      // `layerKindHoldsDrawings` also gates the timesheet X in every empty
      // cell, the run labels over the blocks, the comma-drag grips and the
      // media drop target. A direction row wearing those is exactly the
      // kind of thing 「누가 멋대로 이상한짓하라했지」 was about.
      expect(
        layerKindHoldsDrawings(LayerKind.instruction),
        isFalse,
        reason: 'the direction row still wears no drawing-row furniture',
      );
    });
  });

  group('🚨the band shows BOTH — R27 #16 left it showing neither', () {
    // 유저 2026-08-27, on what shipped: 「지금 스샷보면 **블록의 배경색
    // 흰색이 사라졌는데?**」. Giving the row cels flipped
    // `layerKindBandIsInstructionsOnly` to false, so the band stopped
    // reading the span adapter and started reading cels the row did not
    // have. It drew nothing at all — the row did not gain a feature, it
    // lost its blocks.
    Layer direction({Map<int, InstructionEvent> spans = const {}}) => Layer(
      id: const LayerId('dir'),
      name: 'Direction 1',
      kind: LayerKind.instruction,
      frames: const [],
      instructions: spans,
    );

    TimelineCellExposureState noCels(Layer layer, int frameIndex) =>
        TimelineCellExposureState.uncovered;

    test('a span with no cel behind it still draws its block', () {
      final layer = direction(
        spans: {2: const InstructionEvent(instructionId: 'fi', length: 3)},
      );
      expect(
        bandExposureState(layer, 2, ownCels: noCels),
        TimelineCellExposureState.drawingStart,
      );
      expect(
        bandExposureState(layer, 3, ownCels: noCels),
        TimelineCellExposureState.held,
      );
      expect(
        bandExposureState(layer, 9, ownCels: noCels),
        TimelineCellExposureState.uncovered,
        reason: 'and nowhere else — the span is what defines the block',
      );
    });

    test("🚨the row's OWN cels win where it has them", () {
      final layer = direction(
        spans: {0: const InstructionEvent(instructionId: 'fi', length: 8)},
      );
      TimelineCellExposureState celAt4(Layer _, int frameIndex) =>
          frameIndex == 4
          ? TimelineCellExposureState.drawingStart
          : TimelineCellExposureState.uncovered;
      expect(
        bandExposureState(layer, 4, ownCels: celAt4),
        TimelineCellExposureState.drawingStart,
        reason: 'a drawing that starts mid-span really does start a block',
      );
      expect(
        bandExposureState(layer, 5, ownCels: celAt4),
        TimelineCellExposureState.held,
        reason: 'and the span carries the rest, as it always did',
      );
    });

    test('⛔a row that carries no instructions is untouched', () {
      final animation = Layer(
        id: const LayerId('a'),
        name: 'A',
        kind: LayerKind.animation,
        frames: const [],
      );
      TimelineCellExposureState covered(Layer _, int _) =>
          TimelineCellExposureState.held;
      expect(
        bandExposureState(animation, 0, ownCels: covered),
        TimelineCellExposureState.held,
      );
      expect(
        bandExposureState(animation, 0, ownCels: noCels),
        TimelineCellExposureState.uncovered,
        reason: 'no spans exist to fall back to, and none are invented',
      );
    });

    test('⛔a transition row is still spans and nothing else', () {
      final transition = Layer(
        id: const LayerId('t'),
        name: 'T',
        kind: LayerKind.transition,
        frames: const [],
        instructions: {
          0: const InstructionEvent(instructionId: 'ol', length: 2),
        },
      );
      // Even handed a covered answer, its band ignores it: the row has no
      // timeline of its own and never gained one.
      TimelineCellExposureState covered(Layer _, int _) =>
          TimelineCellExposureState.drawingStart;
      expect(
        bandExposureState(transition, 5, ownCels: covered),
        TimelineCellExposureState.uncovered,
      );
    });
  });
}

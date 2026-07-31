import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/clipboard/layer_copy_payload.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';

/// The four decisions the user made after R6 landed (2026-07-30):
/// copy carries everything, the adjustment shares across 겸용컷, each
/// effect has its own switch, and the eyedropper's "as seen" mode means it.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  LayerEffect brightness(double amount, {String id = 'fx'}) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.brightnessContrast,
    parameters: {'brightness': EffectParameter(value: amount)},
  );

  group('copy layer carries EVERYTHING (user: 합성포함해서 싹다)', () {
    test(
      'the payload takes the composite-time state, not just the artwork',
      () {
        final source = Layer(
          id: const LayerId('a'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: TimelineExposure.drawing(const FrameId('f1'), length: 2),
          },
          blendMode: LayerBlendMode.multiply,
          mark: LayerMark.red,
          onTimesheet: false,
          isFillReference: true,
          transformTrack: TransformTrack.empty().copyWith(
            rotation: PropertyTrack<double>().withKey(0, 30),
          ),
          effects: [brightness(25)],
          runBehaviors: const [
            TimelineRunBehavior(
              anchorFrameId: FrameId('f1'),
              side: TimelineRunEdgeSide.end,
              mode: TimelineRunEdgeMode.hold,
            ),
          ],
        );
        final payload = copyLayerToPayload(source);
        expect(payload.blendMode, LayerBlendMode.multiply);
        expect(payload.mark, LayerMark.red);
        expect(payload.onTimesheet, isFalse);
        expect(payload.isFillReference, isTrue);
        expect(payload.transformTrack.rotation.keyAt(0)!.value, 30);
        expect(payload.effects.single.parameterOf('brightness').value, 25);
        expect(payload.runBehaviors, hasLength(1));
      },
    );

    test('the paste plan applies it, and REMAPS run-behaviour anchors', () {
      final source = Layer(
        id: const LayerId('a'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
        ],
        timeline: {0: TimelineExposure.drawing(const FrameId('f1'), length: 2)},
        blendMode: LayerBlendMode.screen,
        effects: [brightness(25)],
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('f1'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.hold,
          ),
        ],
      );
      final cut = Cut(
        id: const CutId('cut'),
        name: 'Cut',
        layers: [source],
        duration: 12,
        canvasSize: canvasSize,
      );
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final plan = planPasteLayerCommandInput(
        project: session.repository.requireProject(),
        targetCut: cut,
        payload: copyLayerToPayload(source),
        insertionIndex: 1,
      );
      expect(plan.layer.blendMode, LayerBlendMode.screen);
      expect(plan.layer.effects.single.parameterOf('brightness').value, 25);
      expect(
        plan.layer.runBehaviors.single.anchorFrameId,
        plan.layer.frames.single.id,
        reason: 'the anchor names a block the COPY has',
      );
      expect(
        plan.layer.runBehaviors.single.anchorFrameId,
        isNot(const FrameId('f1')),
      );
    });
  });

  group('the adjustment shares across 겸용컷 (user: 액션란은 다 공유)', () {
    test('the link predicate takes the ACTION rows, storyboard excepted', () {
      expect(layerKindLinksIntoLinkedCut(LayerKind.adjustment), isTrue);
      expect(layerKindLinksIntoLinkedCut(LayerKind.animation), isTrue);
      expect(layerKindLinksIntoLinkedCut(LayerKind.folder), isTrue);
      // A cut holds one conte strip and it belongs to that cut.
      expect(layerKindLinksIntoLinkedCut(LayerKind.storyboard), isFalse);
      expect(layerKindLinksIntoLinkedCut(LayerKind.se), isFalse);
      expect(layerKindLinksIntoLinkedCut(LayerKind.camera), isFalse);
    });

    test('but 겸용 변경 does NOT relocate it — position is its meaning', () {
      // 겸용컷 생성 copies a stack wholesale, so every row keeps its place.
      // A CONVERT unions two different stacks and APPENDS what the other
      // side lacks, stripped of its folder — which for an adjustment means
      // grading the whole stack instead of the rows it was scoped to, in
      // one of the two "shared" cuts.
      expect(layerKindJoinsLinkedCutConvert(LayerKind.adjustment), isFalse);
      expect(layerKindLinksIntoLinkedCut(LayerKind.adjustment), isTrue);
      // Every other linking kind joins both paths.
      for (final kind in LayerKind.values) {
        if (kind == LayerKind.adjustment) {
          continue;
        }
        expect(
          layerKindJoinsLinkedCutConvert(kind),
          layerKindLinksIntoLinkedCut(kind),
          reason: kind.name,
        );
      }
    });

    test(
      'only the adjustment MIRRORS its chain — every other row stays local',
      () {
        for (final kind in LayerKind.values) {
          expect(
            layerKindMirrorsEffects(kind),
            kind == LayerKind.adjustment,
            reason: kind.name,
          );
        }
      },
    );

    test(
      'editing a linked adjustment\'s chain reaches every member, one undo',
      () {
        final session = EditorSessionManager(
          initialProject: createDefaultProject(),
        );
        addTearDown(session.dispose);
        session.createDrawingAtCurrentFrame();
        session.addLayerOfKind(LayerKind.adjustment);
        final row = session.activeLayer!;
        final sourceCutId = session.activeCutId!;
        session.createLinkedCutFromActiveCut();

        // The linked copy of the adjustment row, in the other cut.
        final project = session.repository.requireProject();
        final group = project.linkRegistry.groupOf(
          cutId: sourceCutId,
          layerId: row.id,
        );
        expect(
          group,
          isNotNull,
          reason: 'the adjustment row joined a link group at all',
        );
        expect(group!.members.length, greaterThan(1));

        // 겸용컷 생성 leaves the NEW cut active with its own first row
        // selected, so pick this cut's adjustment row before editing it.
        session.selectLayer(
          session.requireActiveCut.layers
              .firstWhere((layer) => layer.kind == LayerKind.adjustment)
              .id,
        );
        session.addEffectToActiveLayer(EffectKind.brightnessContrast);
        final withEffect = session.activeLayer!;
        session.updateLayerEffects(
          withEffect.id,
          effectsWithLaneValueEdited(
            withEffect.effects,
            laneId: effectLaneId(withEffect.effects.single.id, 'brightness'),
            frameIndex: 0,
            input: '35',
          )!,
        );

        List<Layer> membersNow() => [
          for (final member in group.members)
            for (final track in session.repository.requireProject().tracks)
              for (final cut in track.cuts)
                if (cut.id == member.cutId)
                  ...cut.layers.where((layer) => layer.id == member.layerId),
        ];

        expect(membersNow(), hasLength(group.members.length));
        for (final member in membersNow()) {
          // R9 #18: the edit is a key now; one key resolves to itself at
          // every frame, so the grade reads the same as before.
          expect(
            member.effects.single.parameterOf('brightness').resolveAt(0),
            35,
            reason: 'the grade is the same in every 겸용컷',
          );
        }
        session.undo();
        for (final member in membersNow()) {
          expect(
            member.effects.single.parameterOf('brightness').resolveAt(0),
            0,
            reason: 'one undo puts every member back',
          );
        }
      },
    );
  });

  group('per-effect switch (AE\'s eyeball)', () {
    test('the header row carries the switch; Transform\'s does not', () {
      final rows = effectPropertyLanes([
        brightness(20),
        brightness(10, id: 'fx2').copyWith(enabled: false),
      ], isExpanded: (_) => false);
      expect(rows, hasLength(2));
      expect(rows.first.groupEnabled, isTrue);
      expect(rows.last.groupEnabled, isFalse);
      // The label stays the effect's name — the glyph says on/off now.
      expect(rows.last.label, EffectKind.brightnessContrast.label);
    });

    test('toggling it is one undo step and stops the filter', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.addEffectToActiveLayer(EffectKind.brightnessContrast);
      final layer = session.activeLayer!;
      final effectId = layer.effects.single.id;
      session.updateLayerEffects(
        layer.id,
        effectsWithEnabledToggled(layer.effects, effectId)!,
      );
      expect(session.activeLayer!.effects.single.enabled, isFalse);
      expect(
        resolveLayerEffectsAt(
          effects: session.activeLayer!.effects,
          frameIndex: 0,
        ),
        isEmpty,
      );
      session.undo();
      expect(session.activeLayer!.effects.single.enabled, isTrue);
    });
  });

  group('the eyedropper\'s display mode means "as seen"', () {
    BitmapSurface flat(int argb) {
      final pixels = flatTilePixels(argb);
      return BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            coord: TileCoord(x: 0, y: 0),
            size: 8,
            pixels: pixels,
          ),
        },
      );
    }

    Layer drawing({List<LayerEffect> effects = const []}) => Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
      timeline: {0: TimelineExposure.drawing(const FrameId('f1'), length: 4)},
      effects: effects,
    );

    int sample(
      List<Layer> layers, {
      CanvasColorSampleSource source = CanvasColorSampleSource.display,
      int ink = 0xFF808080,
    }) => sampleCompositeColor(
      cut: Cut(
        id: const CutId('cut'),
        name: 'Cut',
        layers: layers,
        duration: 12,
        canvasSize: canvasSize,
      ),
      frameIndex: 0,
      surfaceResolver: (layer, frame) => flat(ink),
      point: CanvasPoint(x: 4, y: 4),
      activeLayerId: const LayerId('a'),
      source: source,
    );

    test('a layer\'s own colour effect changes what it picks', () {
      expect(sample([drawing()]) & 0xFF0000, 0x800000);
      // +20 of the slider = +51.
      expect(
        (sample([
                  drawing(effects: [brightness(20)]),
                ]) >>
                16) &
            0xFF,
        closeTo(0x80 + 51, 1),
      );
    });

    test('an ADJUSTMENT row above it grades the pick too', () {
      final adjustment = createAdjustmentLayer(
        id: const LayerId('fx'),
        name: 'FX1',
      ).copyWith(effects: [brightness(20)]);
      expect(
        (sample([drawing(), adjustment]) >> 16) & 0xFF,
        closeTo(0x80 + 51, 1),
      );
      // …at half mix, half the grade.
      expect(
        (sample([drawing(), adjustment.copyWith(opacity: 0.5)]) >> 16) & 0xFF,
        closeTo(0x80 + 26, 2),
      );
      // …and a hidden or bypassed row grades nothing.
      expect(
        (sample([drawing(), adjustment.copyWith(isVisible: false)]) >> 16) &
            0xFF,
        0x80,
      );
    });

    test('the grade lands on the STACK, never on the paper under it', () {
      // Every paint route computes filter(stack) over paper — the
      // adjustment's saveLayer wraps the scope and the background is drawn
      // outside it. Starting the accumulator AT the paper computed
      // filter(stack over paper) instead, which agrees only where the stack
      // is fully opaque.
      final darken = createAdjustmentLayer(
        id: const LayerId('fx'),
        name: 'FX1',
      ).copyWith(effects: [brightness(-40)]);

      // Nothing drawn at all: the pick is the paper, ungraded — which is
      // also exactly when the composite tree emits no adjustment node.
      final paper = sample([darken]);
      expect(
        (paper >> 16) & 0xFF,
        (canvasPaperColor >> 16) & 0xFF,
        reason: 'an adjustment over nothing grades nothing',
      );

      // Half-covered ink: the graded ink composites over the UNgraded
      // paper, so the answer sits between them — never below the ink's own
      // graded value.
      final half = sample([drawing(), darken], ink: 0x80808080);
      final gradedInk = 0x80 - 102 < 0 ? 0 : 0x80 - 102;
      final paperR = (canvasPaperColor >> 16) & 0xFF;
      final expected = (gradedInk * 0.5 + paperR * 0.5).round();
      expect((half >> 16) & 0xFF, closeTo(expected, 2));
    });

    test('a chain of [colour, blur] still reports its COLOUR part', () {
      final chained = drawing(
        effects: [
          brightness(20),
          LayerEffect(
            id: const EffectId('b'),
            kind: EffectKind.blur,
            parameters: {'blurX': EffectParameter(value: 4)},
          ),
        ],
      );
      expect(
        (sample([chained]) >> 16) & 0xFF,
        closeTo(0x80 + 51, 1),
        reason:
            'the blur is out of reach; dropping the brightness too is '
            'strictly worse',
      );
    });

    test('the LAYER mode reads the ink as drawn — no effects, no grade', () {
      final adjustment = createAdjustmentLayer(
        id: const LayerId('fx'),
        name: 'FX1',
      ).copyWith(effects: [brightness(20)]);
      expect(
        (sample([
                  drawing(effects: [brightness(20)]),
                  adjustment,
                ], source: CanvasColorSampleSource.layer) >>
                16) &
            0xFF,
        0x80,
        reason: 'the what-ink-is-this mode answers the ink',
      );
    });
  });
}

/// An 8×8 tile filled with one straight-alpha ARGB colour.
Uint8List flatTilePixels(int argb) {
  final bytes = Uint8List(8 * 8 * 4);
  for (var index = 0; index < 8 * 8; index += 1) {
    bytes[index * 4] = (argb >> 16) & 0xFF;
    bytes[index * 4 + 1] = (argb >> 8) & 0xFF;
    bytes[index * 4 + 2] = argb & 0xFF;
    bytes[index * 4 + 3] = (argb >> 24) & 0xFF;
  }
  return bytes;
}

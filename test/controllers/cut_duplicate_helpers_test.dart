import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/cut_duplicate_helpers.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

void main() {
  group('duplicateCutAsIndependentCopy', () {
    test('creates an independent duplicate using caller supplied IDs', () {
      final source = _sourceCut();

      final duplicate = duplicateCutAsIndependentCopy(
        source: source,
        newCutId: const CutId('cut-copy'),
        newName: 'Cut Copy',
        layerIdMap: {
          LayerId('layer-a'): LayerId('layer-copy-a'),
          LayerId('layer-b'): LayerId('layer-copy-b'),
        },
        frameIdMap: {
          FrameId('frame-a'): FrameId('frame-copy-a'),
          FrameId('frame-b'): FrameId('frame-copy-b'),
          FrameId('frame-c'): FrameId('frame-copy-c'),
        },
      );

      expect(duplicate.id, const CutId('cut-copy'));
      expect(duplicate.name, 'Cut Copy');
      expect(duplicate.duration, source.duration);
      expect(duplicate.canvasSize, source.canvasSize);
      expect(duplicate.metadata, source.metadata);

      expect(
        duplicate.layers.map((layer) => layer.id),
        orderedEquals([
          const LayerId('layer-copy-a'),
          const LayerId('layer-copy-b'),
        ]),
      );
      expect(duplicate.layers[0].name, 'Line');
      expect(duplicate.layers[0].isVisible, isFalse);
      expect(duplicate.layers[0].opacity, 0.5);
      expect(duplicate.layers[1].name, 'Color');
      expect(duplicate.layers[1].isVisible, isTrue);
      expect(duplicate.layers[1].opacity, 0.75);

      expect(
        duplicate.layers[0].frames.map((frame) => frame.id),
        orderedEquals([
          const FrameId('frame-copy-a'),
          const FrameId('frame-copy-b'),
        ]),
      );
      expect(duplicate.layers[0].frames[0].name, 'A');
      expect(duplicate.layers[0].frames[0].duration, 3);
      expect(duplicate.layers[0].frames[1].name, isNull);
      expect(duplicate.layers[0].frames[1].duration, 1);
      expect(
        duplicate.layers[1].frames.map((frame) => frame.id),
        orderedEquals([const FrameId('frame-copy-c')]),
      );
      expect(duplicate.layers[1].frames.single.name, 'C');
      expect(duplicate.layers[1].frames.single.duration, 2);

      expect(duplicate.layers[0].timeline.keys, orderedEquals([0, 5, 7]));
      expect(
        duplicate.layers[0].timeline[0],
        TimelineExposure.drawing(
          const FrameId('frame-copy-a'),
          length: 3,
          breakdownOffsets: const [1],
        ),
      );
      expect(
        duplicate.layers[0].timeline[5],
        TimelineExposure.drawing(const FrameId('frame-copy-b'), length: 2),
      );
      expect(
        duplicate.layers[0].timeline[7],
        TimelineExposure.drawing(const FrameId('frame-copy-a'), length: 1),
      );
      expect(duplicate.layers[1].timeline.keys, orderedEquals([2]));
      expect(
        duplicate.layers[1].timeline[2],
        TimelineExposure.drawing(
          const FrameId('frame-copy-c'),
          length: 1,
          // The block's memo is copied with it (see the memo test below).
          memo: const ExposureMemo(
            actionMemo: 'Character points at the horizon.',
            note: 'Use as conte panel note.',
          ),
        ),
      );
    });

    test('preserves source metadata', () {
      final source = _sourceCut().copyWith(
        metadata: const CutMetadata(note: 'FX-heavy cut.'),
      );

      final duplicate = duplicateCutAsIndependentCopy(
        source: source,
        newCutId: const CutId('cut-copy'),
        newName: 'Cut Copy',
        layerIdMap: {
          LayerId('layer-a'): LayerId('layer-copy-a'),
          LayerId('layer-b'): LayerId('layer-copy-b'),
        },
        frameIdMap: {
          FrameId('frame-a'): FrameId('frame-copy-a'),
          FrameId('frame-b'): FrameId('frame-copy-b'),
          FrameId('frame-c'): FrameId('frame-copy-c'),
        },
      );

      expect(duplicate.id, const CutId('cut-copy'));
      expect(duplicate.name, 'Cut Copy');
      expect(duplicate.metadata, source.metadata);
    });

    test('preserves source layer kinds', () {
      final source = _sourceCut();

      final duplicate = duplicateCutAsIndependentCopy(
        source: source,
        newCutId: const CutId('cut-copy'),
        newName: 'Cut Copy',
        layerIdMap: {
          LayerId('layer-a'): LayerId('layer-copy-a'),
          LayerId('layer-b'): LayerId('layer-copy-b'),
        },
        frameIdMap: {
          FrameId('frame-a'): FrameId('frame-copy-a'),
          FrameId('frame-b'): FrameId('frame-copy-b'),
          FrameId('frame-c'): FrameId('frame-copy-c'),
        },
      );

      expect(duplicate.layers[0].kind, LayerKind.animation);
      expect(duplicate.layers[1].kind, LayerKind.storyboard);
    });

    test('preserves source frame storyboard metadata', () {
      final source = _sourceCut();

      final duplicate = duplicateCutAsIndependentCopy(
        source: source,
        newCutId: const CutId('cut-copy'),
        newName: 'Cut Copy',
        layerIdMap: {
          LayerId('layer-a'): LayerId('layer-copy-a'),
          LayerId('layer-b'): LayerId('layer-copy-b'),
        },
        frameIdMap: {
          FrameId('frame-a'): FrameId('frame-copy-a'),
          FrameId('frame-b'): FrameId('frame-copy-b'),
          FrameId('frame-c'): FrameId('frame-copy-c'),
        },
      );

      expect(duplicate.layers[1].kind, LayerKind.storyboard);
      expect(
        duplicate.layers[1].frames.single.id,
        const FrameId('frame-copy-c'),
      );
      // The memo rides the EXPOSURE, so duplicating the cut carries it
      // without the frame copier knowing anything about memos.
      expect(
        duplicate.layers[1].timeline[2]!.memo,
        source.layers[1].timeline[2]!.memo,
      );
    });

    test(
      'does not mutate or share layer frame stroke lists with the source',
      () {
        final source = _sourceCut();

        final duplicate = duplicateCutAsIndependentCopy(
          source: source,
          newCutId: const CutId('cut-copy'),
          newName: 'Cut Copy',
          layerIdMap: {
            LayerId('layer-a'): LayerId('layer-copy-a'),
            LayerId('layer-b'): LayerId('layer-copy-b'),
          },
          frameIdMap: {
            FrameId('frame-a'): FrameId('frame-copy-a'),
            FrameId('frame-b'): FrameId('frame-copy-b'),
            FrameId('frame-c'): FrameId('frame-copy-c'),
          },
        );

        expect(source, _sourceCut());
        expect(identical(duplicate.layers, source.layers), isFalse);
        expect(identical(duplicate.layers[0], source.layers[0]), isFalse);
        expect(
          identical(duplicate.layers[0].frames, source.layers[0].frames),
          isFalse,
        );
        expect(
          identical(duplicate.layers[0].frames[0], source.layers[0].frames[0]),
          isFalse,
        );
        expect(
          identical(
            duplicate.layers[0].frames[0].strokes,
            source.layers[0].frames[0].strokes,
          ),
          isFalse,
        );
        expect(
          identical(
            duplicate.layers[0].frames[0].strokes.single,
            source.layers[0].frames[0].strokes.single,
          ),
          isFalse,
        );
        expect(
          identical(
            duplicate.layers[0].frames[0].strokes.single.points,
            source.layers[0].frames[0].strokes.single.points,
          ),
          isFalse,
        );
        expect(
          duplicate.layers[0].frames[0].strokes.single,
          source.layers[0].frames[0].strokes.single,
        );
      },
    );

    test('throws when a source layer id is not mapped', () {
      expect(
        () => duplicateCutAsIndependentCopy(
          source: _sourceCut(),
          newCutId: const CutId('cut-copy'),
          newName: 'Cut Copy',
          layerIdMap: {LayerId('layer-a'): LayerId('layer-copy-a')},
          frameIdMap: {
            FrameId('frame-a'): FrameId('frame-copy-a'),
            FrameId('frame-b'): FrameId('frame-copy-b'),
            FrameId('frame-c'): FrameId('frame-copy-c'),
          },
        ),
        throwsArgumentError,
      );
    });

    test('throws when a source frame id is not mapped', () {
      expect(
        () => duplicateCutAsIndependentCopy(
          source: _sourceCut(),
          newCutId: const CutId('cut-copy'),
          newName: 'Cut Copy',
          layerIdMap: {
            LayerId('layer-a'): LayerId('layer-copy-a'),
            LayerId('layer-b'): LayerId('layer-copy-b'),
          },
          frameIdMap: {
            FrameId('frame-a'): FrameId('frame-copy-a'),
            FrameId('frame-c'): FrameId('frame-copy-c'),
          },
        ),
        throwsArgumentError,
      );
    });

    test('throws when a drawing timeline exposure frame id is not mapped', () {
      final source = Cut(
        id: const CutId('cut-source'),
        name: 'Source',
        duration: 8,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
        layers: [
          Layer(
            id: const LayerId('layer-a'),
            name: 'Line',
            frames: [
              Frame(
                id: const FrameId('frame-a'),
                duration: 1,
                strokes: const [],
              ),
            ],
            timeline: {
              0: TimelineExposure.drawing(
                const FrameId('missing-frame'),
                length: 1,
              ),
            },
          ),
        ],
      );

      expect(
        () => duplicateCutAsIndependentCopy(
          source: source,
          newCutId: const CutId('cut-copy'),
          newName: 'Cut Copy',
          layerIdMap: {LayerId('layer-a'): LayerId('layer-copy-a')},
          frameIdMap: {FrameId('frame-a'): FrameId('frame-copy-a')},
        ),
        throwsArgumentError,
      );
    });
  });
}

Cut _sourceCut() {
  return Cut(
    id: const CutId('cut-source'),
    name: 'Source Cut',
    duration: 12,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [
      Layer(
        id: const LayerId('layer-a'),
        name: 'Line',
        frames: [
          Frame(
            id: const FrameId('frame-a'),
            name: 'A',
            duration: 3,
            strokes: [_stroke()],
          ),
          Frame(id: const FrameId('frame-b'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(
            const FrameId('frame-a'),
            length: 3,
            breakdownOffsets: const [1],
          ),
          5: TimelineExposure.drawing(const FrameId('frame-b'), length: 2),
          7: TimelineExposure.drawing(const FrameId('frame-a'), length: 1),
        },
        isVisible: false,
        opacity: 0.5,
      ),
      Layer(
        id: const LayerId('layer-b'),
        name: 'Color',
        frames: [
          Frame(
            id: const FrameId('frame-c'),
            name: 'C',
            duration: 2,
            strokes: const [],
          ),
        ],
        timeline: {
          2: TimelineExposure.drawing(
            const FrameId('frame-c'),
            length: 1,
            memo: const ExposureMemo(
              actionMemo: 'Character points at the horizon.',
              note: 'Use as conte panel note.',
            ),
          ),
        },
        isVisible: true,
        opacity: 0.75,
        kind: LayerKind.storyboard,
      ),
    ],
  );
}

Stroke _stroke() {
  return Stroke(
    id: const StrokeId('stroke-a'),
    points: const [StrokePoint(x: 1, y: 2), StrokePoint(x: 3, y: 4)],
    brushSettings: BrushSettings(color: 0xFF123456, size: 8, opacity: 0.4),
  );
}

import 'package:anicel/src/models/import/tvp_import_model.dart';
import 'package:anicel/src/models/import/tvpp_convert.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:flutter_test/flutter_test.dart';

TvppSlot _image() => const TvppSlot(
      kind: TvppSlotKind.image,
      chunkOffset: 0,
      chunkLength: 0,
      compressed: true,
    );

TvppSlot _hold() => const TvppSlot(
      kind: TvppSlotKind.hold,
      chunkOffset: 0,
      chunkLength: 0,
      compressed: true,
    );

TvppLayer _layer(
  String name, {
  TvppLayerKind kind = TvppLayerKind.raster,
  int layerId = 0,
  int parentId = 0,
  int start = 0,
  List<TvppSlot> slots = const [],
  List<TvppSlot> second = const [],
  Map<int, String> names = const {},
  int opacity = 255,
  TvpEdgeBehavior pre = TvpEdgeBehavior.none,
  TvpEdgeBehavior post = TvpEdgeBehavior.none,
}) =>
    TvppLayer(
      kind: kind,
      name: name,
      layerId: layerId,
      parentId: parentId,
      start: start,
      end: start + (slots.isEmpty ? 0 : slots.length - 1),
      opacity: opacity,
      preBehavior: pre,
      postBehavior: post,
      slots: slots,
      ctgSecondStream: second,
      instanceNames: names,
    );

TvppClip _clip({
  required List<TvppLayer> layers,
  List<TvppImageMark> marks = const [],
  List<TvppCameraPoint> camera = const [],
}) =>
    TvppClip(
      name: 'cut',
      width: 320,
      height: 180,
      frameRate: 24,
      pixelAspectRatio: 1,
      layers: layers,
      imageMarks: marks,
      cameraPoints: camera,
      cameraDataText: '',
    );

TvppCameraPoint _point({double x = 0, int instant = 0}) => TvppCameraPoint(
      x: x,
      y: 90,
      rotationDegrees: 0,
      zoomFactor: 1,
      sizeX: 320,
      sizeY: 180,
      instant: instant,
      bezierBeforeX: 0,
      bezierBeforeY: 0,
      bezierAfterX: 0,
      bezierAfterY: 0,
    );

void main() {
  group('convertTvppClip', () {
    test('slots become blocks: heads start, holds extend, offsets apply',
        () {
      final clip = _clip(
        layers: [
          _layer('cam', kind: TvppLayerKind.camera),
          _layer(
            'A',
            start: 3,
            slots: [_image(), _hold(), _hold(), _image(), _hold(), _image()],
            names: const {0: '1', 3: '2'},
          ),
        ],
        marks: [
          // layerIndex counts INTO clip.layers (camera included): 1 = A.
          const TvppImageMark(layerIndex: 1, frame: 4, colorIndex: 1),
          const TvppImageMark(layerIndex: 1, frame: 6, colorIndex: 2),
          const TvppImageMark(layerIndex: 1, frame: 8, colorIndex: 1),
        ],
      );
      final result = convertTvppClip(clip, clipIndex: 0).result;

      expect(result.layers, hasLength(1));
      final a = result.layers.single;
      expect(a.name, 'A');
      expect(a.blocks, hasLength(3));

      expect(a.blocks[0].start, 3);
      expect(a.blocks[0].length, 3);
      expect(a.blocks[0].name, '1');
      // frame 4 = offset 1 inside the first block.
      expect(a.blocks[0].breakdownOffsets, const [1]);

      expect(a.blocks[1].start, 6);
      expect(a.blocks[1].length, 2);
      expect(a.blocks[1].name, '2');
      // frame 6 = this block's HEAD: the workflow rule drops it.
      expect(a.blocks[1].breakdownOffsets, isEmpty);

      expect(a.blocks[2].start, 8);
      expect(a.blocks[2].length, 1);
      expect(a.blocks[2].name, '');
      // frame 8 = a head again.
      expect(a.blocks[2].breakdownOffsets, isEmpty);
    });

    test('a hold with no preceding image warns and drops', () {
      final clip = _clip(
        layers: [
          _layer('L', slots: [_hold(), _image()]),
        ],
      );
      final result = convertTvppClip(clip, clipIndex: 0).result;
      expect(result.warnings, hasLength(1));
      expect(result.layers.single.blocks.single.start, 1);
    });

    test('folders reverse to bottom-first with parents after members', () {
      // Stream (top-first): F(folder id=9), A(parent 9), B(parent 9), C.
      final clip = _clip(
        layers: [
          _layer('F', kind: TvppLayerKind.folder, layerId: 9),
          _layer('A', parentId: 9, slots: [_image()]),
          _layer('B', parentId: 9, slots: [_image()]),
          _layer('C', slots: [_image()]),
        ],
      );
      final layers = convertTvppClip(clip, clipIndex: 0).result.layers;
      expect(layers.map((l) => l.name).toList(), ['C', 'B', 'A', 'F']);
      expect(layers[3].isFolder, isTrue);
      expect(layers[1].parentIndex, 3); // B → F
      expect(layers[2].parentIndex, 3); // A → F
      expect(layers[0].parentIndex, -1); // C → root
    });

    test('a CTG layer becomes a folder holding its two source streams',
        () {
      final clip = _clip(
        layers: [
          _layer(
            'C(CTGlayer)',
            kind: TvppLayerKind.ctg,
            layerId: 7,
            slots: [_image(), _hold()],
            second: [_image(), _hold()],
          ),
        ],
      );
      final conversion = convertTvppClip(clip, clipIndex: 0);
      final layers = conversion.result.layers;
      expect(layers.map((l) => l.name).toList(), [
        'C(CTGlayer) (2)',
        'C(CTGlayer)',
        'C(CTGlayer)',
      ]);
      expect(layers[2].isFolder, isTrue);
      expect(layers[0].parentIndex, 2);
      expect(layers[1].parentIndex, 2);
      // Two streams, two distinct slot keys.
      expect(conversion.slotsByFile.keys, hasLength(2));
    });

    test('camera keys bake to per-frame poses', () {
      final layers = [
        _layer('L', slots: [for (var i = 0; i < 12; i++) _image()]),
      ];
      final still = convertTvppClip(
        _clip(layers: layers, camera: [_point(x: 160)]),
        clipIndex: 0,
      ).result;
      expect(still.camera.positions, hasLength(12));
      expect(still.camera.positions.first.x, 160);
      expect(still.camera.positions.last.x, 160);
      expect(still.camera.keyframes, hasLength(1));

      // A linear two-key pan (no easing profile): halfway in time is
      // halfway in space, and frames past the last key hold it.
      final moving = convertTvppClip(
        _clip(
          layers: layers,
          camera: [_point(x: 0), _point(x: 100, instant: 10)],
        ),
        clipIndex: 0,
      ).result;
      expect(moving.camera.positions, hasLength(12));
      expect(moving.camera.positions[0].x, 0);
      expect(moving.camera.positions[5].x, closeTo(50, 1e-6));
      expect(moving.camera.positions[10].x, 100);
      expect(moving.camera.positions[11].x, 100);
      expect(moving.warnings, isEmpty);
    });
  });
}

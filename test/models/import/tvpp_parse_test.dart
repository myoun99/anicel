import 'package:anicel/src/models/import/tvp_json_parse.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tvpp_test_builder.dart';

/// Structure parsing of TVPaint's .tvpp, against synthetic files built
/// from the measured spec (memory `tvpp-format-notes`). The builder is a
/// deliberate second implementation: encoder and parser must agree on
/// every layout rule — chunk padding, header fields, slot
/// classification — for these to pass.
void main() {
  group('parseTvppStructure', () {
    test('reads clips, layers, slots, names, marks and camera keys', () {
      final b = TvppBuilder();

      b.clipProperties('cut12');
      b.clipHeader(
        width: 320,
        height: 180,
        frameRate: 24,
        imageMarks: [(1, 2, 1), (1, 5, 2)],
      );

      // Layer 0: the camera layer every clip opens with.
      b.layerHead('카메라레이어', headerChunk: 'LRCA');
      b.layerExt(const {});

      // Layer 1: raster, frames 3..8 — image, hold, hold, image, hold,
      // image. Named instances on slots 0 and 3 only.
      b.layerHead(
        'A',
        start: 3,
        end: 8,
        count: 6,
        opacity: 200,
        pre: 3,
        post: 2,
        layerId: 977,
      );
      b.layerExt(const {0: '1', 3: '2'});
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));
      b.zchkHold();
      b.zchkHold();
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));
      b.zchkHold();
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));

      // Layer 2: a folder, and layer 3 its child via parentId.
      b.layerHead('F(folder)', headerChunk: 'LRFH', layerId: 950);
      b.layerExt(const {});
      b.layerHead('B', layerId: 949, parentId: 950, end: 0, count: 1);
      b.layerExt(const {});
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));

      // Layer 4: CTG — two image streams split by LRSR.
      b.layerHead('C(CTGlayer)', headerChunk: 'LRSH', end: 1, count: 2);
      b.layerExt(const {});
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));
      b.zchkHold();
      b.chunk('LRSR', const []);
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));
      b.zchkHold();

      b.clipConfig(
        cameraData: '''
mmotionblur=0.000000
mpoints-0-x=160.000000
mpoints-0-y=90.000000
mpoints-0-rotation=0.000000
mpoints-0-zoomfactor=1.000000
mpoints-0-camerasizex=320.000000
mpoints-0-camerasizey=180.000000
mpoints-0-instant=0
mpoints-0-bezierbeforex=0.000000
mpoints-0-bezierbeforey=0.000000
mpoints-0-bezierafterx=0.000000
mpoints-0-bezieraftery=0.000000
mpoints-1-x=200.000000
mpoints-1-y=90.000000
mpoints-1-rotation=-12.500000
mpoints-1-zoomfactor=1.560000
mpoints-1-camerasizex=320.000000
mpoints-1-camerasizey=180.000000
mpoints-1-instant=24
mpoints-1-bezierbeforex=0.000000
mpoints-1-bezierbeforey=0.000000
mpoints-1-bezierafterx=0.000000
mpoints-1-bezieraftery=0.000000
''',
      );

      // A second clip proves the DLOC split and per-clip naming.
      b.clipProperties('cut13');
      b.clipHeader(width: 320, height: 180);
      b.layerHead('카메라레이어', headerChunk: 'LRCA');
      b.layerExt(const {});
      b.layerHead('solo', end: 0, count: 1);
      b.layerExt(const {});
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));
      b.clipConfig();

      final result = parseTvppStructure(b.bytes);
      expect(result.warnings, isEmpty);
      expect(result.clips, hasLength(2));

      final clip = result.clips[0];
      expect(clip.name, 'cut12');
      expect(clip.width, 320);
      expect(clip.height, 180);
      expect(clip.frameRate, 24.0);
      expect(clip.pixelAspectRatio, 1.0);
      expect(clip.frameCount, 9); // layer A ends on frame 8.

      expect(clip.layers, hasLength(5));
      expect(clip.layers[0].kind, TvppLayerKind.camera);

      final a = clip.layers[1];
      expect(a.kind, TvppLayerKind.raster);
      expect(a.name, 'A');
      expect(a.start, 3);
      expect(a.end, 8);
      expect(a.frameCount, 6);
      expect(a.opacity, 200);
      expect(a.preBehavior, TvpEdgeBehavior.hold);
      expect(a.postBehavior, TvpEdgeBehavior.pingPong);
      expect(a.layerId, 977);
      expect(a.parentId, 0);
      expect(a.slots.map((s) => s.kind).toList(), const [
        TvppSlotKind.image,
        TvppSlotKind.hold,
        TvppSlotKind.hold,
        TvppSlotKind.image,
        TvppSlotKind.hold,
        TvppSlotKind.image,
      ]);
      expect(a.instanceNames, const {0: '1', 3: '2'});

      expect(clip.layers[2].kind, TvppLayerKind.folder);
      expect(clip.layers[3].parentId, 950);

      final ctg = clip.layers[4];
      expect(ctg.kind, TvppLayerKind.ctg);
      expect(ctg.slots, hasLength(2));
      expect(ctg.ctgSecondStream, hasLength(2));

      expect(
        clip.imageMarks
            .map((m) => (m.layerIndex, m.frame, m.colorIndex))
            .toList(),
        [(1, 2, 1), (1, 5, 2)],
      );

      expect(clip.cameraPoints, hasLength(2));
      expect(clip.cameraPoints[0].x, 160);
      expect(clip.cameraPoints[0].instant, 0);
      expect(clip.cameraPoints[1].rotationDegrees, -12.5);
      expect(clip.cameraPoints[1].zoomFactor, 1.56);
      expect(clip.cameraPoints[1].instant, 24);

      final clip13 = result.clips[1];
      expect(clip13.name, 'cut13');
      expect(clip13.cameraPoints, isEmpty);
      expect(clip13.layers, hasLength(2));
    });

    test('reads v11 files: bare SRAW/DBOD chunks, no folders', () {
      final b = TvppBuilder();
      b.clipProperties('284');
      b.clipHeader(width: 128, height: 64);
      b.layerHead('CUT', end: 2, count: 3);
      b.layerExt(const {});
      b.rawSlot(dbodRecord(List.filled(128 * 64, 0), 128, 64));
      b.rawSlot(holdRecord());
      b.rawSlot(srawRecord(List.filled(128 * 64, 0), 128, 64));
      b.clipConfig();

      final result = parseTvppStructure(b.bytes);
      expect(result.clips, hasLength(1));
      final layer = result.clips[0].layers.single;
      expect(layer.slots.map((s) => s.kind).toList(), const [
        TvppSlotKind.image,
        TvppSlotKind.hold,
        TvppSlotKind.image,
      ]);
      expect(layer.slots[0].compressed, isFalse);
      expect(layer.slots[0].v11WholeCanvas, isTrue);
      expect(layer.slots[2].v11WholeCanvas, isFalse);
    });

    test('rejects bytes with no clip header', () {
      expect(
        () => parseTvppStructure(TvppBuilder().bytes),
        throwsA(isA<TvppParseException>()),
      );
    });
  });
}

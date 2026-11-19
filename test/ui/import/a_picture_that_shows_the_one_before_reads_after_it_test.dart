import 'dart:typed_data';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/tvp_import_planner.dart';
import 'package:anicel/src/services/import/tvpp_raster_decoder.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart'
    show AnicelLaidCel, laidCelSurface;
import 'package:anicel/src/ui/session/tvpp_import_door.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/surface_rgba_in_place.dart';
import '../../models/import/tvpp_test_builder.dart';

/// 🗣️F-621 ② (유저 2026-11-19): a layer whose pictures show the tiles of
/// the picture before — `(0, 1, s)` — came in as its first picture alone.
/// The door reads every cel on its own first, and a cel that shows the one
/// before again after it, a stream's pictures in order
/// ([TvppImportDoor.decodeEach]).
void main() {
  const w = 130;
  const h = 70;
  const size = CanvasSize(width: w, height: h);

  // The 130 × 70 grid: tiles 0 1 2 over 3 4 5. The rows' first tiles stay
  // empty — the builder writes an empty tile as a copy of its row's first.
  int shade(int x, int y, int k) => premulBgra(
    (x * 3 + k * 40) & 0xff,
    (y * 5 + k * 70) & 0xff,
    60 + k * 40,
    255,
  );

  List<int> picture(Map<int, int> tiles) {
    final px = List<int>.filled(w * h, 0);
    tiles.forEach((t, k) {
      final x0 = (t % 3) * 64;
      final y0 = (t ~/ 3) * 64;
      for (var y = 0; y < (t ~/ 3 == 1 ? 6 : 64); y++) {
        for (var x = 0; x < (t % 3 == 2 ? 2 : 64); x++) {
          px[(y0 + y) * w + x0 + x] = shade(x, y, k);
        }
      }
    });
    return px;
  }

  final first = picture({1: 0, 2: 1, 4: 2});
  final second = picture({1: 0, 2: 0, 4: 3, 5: 2});
  final third = picture({1: 0, 2: 4, 4: 3});
  final alone = picture({1: 5, 4: 6});
  final records = [
    srawRecord(first, w, h),
    srawRecord(second, w, h, fromTheLast: {1: 1, 2: 1, 5: 4}),
    srawRecord(third, w, h, fromTheLast: {1: 1, 4: 4}),
  ];

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    layers: const [],
    duration: 3,
    canvasSize: size,
  );
  final plan = TvpImportPlan(cut: cut, bakes: const [], warnings: const []);
  const bake = PlannedCelBake(
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
    sourceFile: 's',
  );

  /// [layers] of records, one stream each, as a file and its slots.
  ({Uint8List file, List<TvppSlot> slots}) fileOf(
    List<List<Uint8List>> layers,
  ) {
    final b = TvppBuilder()
      ..clipProperties('t')
      ..clipHeader(width: w, height: h);
    for (final (index, laid) in layers.indexed) {
      b.layerHead('L$index', end: laid.length - 1, count: laid.length);
      for (final record in laid) {
        b.zchkSlot(record);
      }
    }
    b.clipConfig();
    final file = b.bytes;
    return (
      file: file,
      slots: [
        for (final layer in parseTvppStructure(file).clips.single.layers)
          ...layer.slots,
      ],
    );
  }

  Future<Uint8List> windowOf(Uint8List file, TvppSlot slot) async =>
      Uint8List.fromList(
        Uint8List.sublistView(
          file,
          slot.chunkOffset,
          slot.chunkOffset + slot.chunkLength,
        ),
      );

  /// [decoded] is a cel that shows [premul] — the format's own floor
  /// unpremultiply, worked out here.
  void expectCel(Object? decoded, List<int> premul, String which) {
    expect(decoded, isA<AnicelLaidCel>(), reason: '$which decodes');
    final cel = laidCelSurface(decoded! as AnicelLaidCel);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = premul[y * w + x];
        final a = v & 0xff;
        final straight = a == 0
            ? 0
            : (((v >> 8) & 0xff) * 255 ~/ a) << 24 |
                  (((v >> 16) & 0xff) * 255 ~/ a) << 16 |
                  (((v >> 24) & 0xff) * 255 ~/ a) << 8 |
                  a;
        if (surfaceRgbaInPlace(cel, x, y) != straight) {
          fail('$which pixel ($x, $y) is not the picture it shows');
        }
      }
    }
  }

  test('🚨every cel of a stream whose pictures show the one before lands '
      'as the picture it shows — beside a stream that stands alone', () async {
    final (:file, :slots) = fileOf([
      records,
      [srawRecord(alone, w, h)],
    ]);
    final decoded = <int, Object>{};
    await TvppImportDoor.decodeEach(
      [for (final slot in slots) (plan, cut, bake, slot)],
      atOnce: 4,
      windowOf: (slot) => windowOf(file, slot),
      landed: (index, lay, cel) async => decoded[index] = cel,
      stopped: () => false,
    );

    expect(decoded.keys, unorderedEquals([0, 1, 2, 3]));
    expectCel(decoded[0], first, 'the first');
    expectCel(decoded[1], second, 'the second');
    expectCel(decoded[2], third, 'the third, through the second');
    expectCel(decoded[3], alone, 'the other stream');
  });

  test('a stream whose first picture shows a picture before lands that it '
      'could not be read', () async {
    final (:file, :slots) = fileOf([
      [records[1]],
    ]);
    final decoded = <int, Object>{};
    await TvppImportDoor.decodeEach(
      [for (final slot in slots) (plan, cut, bake, slot)],
      atOnce: 2,
      windowOf: (slot) => windowOf(file, slot),
      landed: (index, lay, cel) async => decoded[index] = cel,
      stopped: () => false,
    );

    expect(decoded[0], isA<TvppNeedsThePictureBefore>());
  });

  test('🚨once a cel read in order hears the stop, no record more is '
      'read', () async {
    final (:file, :slots) = fileOf([
      [...records, srawRecord(third, w, h, fromTheLast: {1: 1, 2: 2, 4: 4})],
    ]);
    var read = 0;
    var landed = 0;
    await TvppImportDoor.decodeEach(
      [for (final slot in slots) (plan, cut, bake, slot)],
      atOnce: 1,
      windowOf: (slot) {
        read += 1;
        return windowOf(file, slot);
      },
      landed: (index, lay, cel) async => landed += 1,
      stopped: () => landed >= 2,
    );

    expect(landed, 2, reason: 'the first alone, the second in order');
    expect(
      read,
      4 + 2,
      reason: 'each tried alone, then the first again and the second',
    );
  });
}

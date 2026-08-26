// NOT part of the suite (no _test suffix): a local-only check that runs
// the PRODUCTION parser+decoder against the real reference projects and
// the oracle numbers measured from TVPaint's own PNG export. Run by hand:
//   flutter test test/services/import/tvpp_real_file_check.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/services/import/tvpp_raster_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const klm =
      'G:\\My Drive\\Creative\\Coding\\Anicel\\参考\\tvp_decode\\KLM_13_tvp12-1\\KLM.tvpp';

  test('KLM: structure + F_n slot pixel counts match the oracle', () {
    if (!File(klm).existsSync()) {
      markTestSkipped('참고 파일 없음 — 로컬 전용 검증');
      return;
    }
    final bytes = Uint8List.fromList(File(klm).readAsBytesSync());
    final parsed = parseTvppStructure(bytes);
    expect(parsed.clips, hasLength(2));

    final clip = parsed.clips[0];
    expect(clip.name, '12');
    expect(clip.width, 2150);
    expect(clip.height, 1518);
    expect(clip.frameRate, 24.0);
    expect(clip.frameCount, 42);
    expect(parsed.clips[1].name, '13');

    // Layer list: camera first, then the 30 the JSON export names.
    expect(clip.layers.first.kind, TvppLayerKind.camera);
    expect(clip.layers, hasLength(31));
    final names = clip.layers.skip(1).map((l) => l.name).toList();
    expect(names.first, 'TAP');
    expect(names.last, 'CON');
    expect(names, contains('F_n'));

    final fn = clip.layers.firstWhere((l) => l.name == 'F_n');
    expect(fn.start, 0);
    expect(fn.end, 13);
    expect(fn.slots, hasLength(14));
    expect(fn.instanceNames[0], '1');
    expect(fn.instanceNames[12], '7');

    final con = clip.layers.firstWhere((l) => l.name == 'CON');
    expect(con.start, 3);
    expect(con.opacity, 195);

    // Clip 13 carries the real production marks (68, every 3 frames).
    expect(parsed.clips[1].imageMarks, hasLength(68));

    // F_n's six SRAW drawings: opaque-pixel counts measured from the
    // PNG oracle during the format verification.
    const oracle = [1158, 1141, 1065, 1174, 1186, 994];
    final imageSlots =
        fn.slots.where((s) => s.kind == TvppSlotKind.image).toList();
    expect(imageSlots, hasLength(7)); // keyframe + 6
    for (var i = 0; i < 6; i++) {
      final rgba = decodeTvppSlotRgba(
        fileBytes: bytes,
        slot: imageSlots[i + 1],
        width: clip.width,
        height: clip.height,
      )!;
      var opaque = 0;
      for (var p = 3; p < rgba.length; p += 4) {
        if (rgba[p] != 0) {
          opaque++;
        }
      }
      expect(opaque, oracle[i], reason: 'F_n 그림 ${i + 1}');
    }
  });

  test('EMS (tvp11): uncompressed wrapper decodes', () {
    const ems =
        'G:\\My Drive\\Creative\\Coding\\Anicel\\参考\\tvp_decode\\EMS11_tvp11\\EMS11_284.tvpp';
    if (!File(ems).existsSync()) {
      markTestSkipped('참고 파일 없음 — 로컬 전용 검증');
      return;
    }
    final bytes = Uint8List.fromList(File(ems).readAsBytesSync());
    final parsed = parseTvppStructure(bytes);
    final clip = parsed.clips.first;
    expect(clip.width, 4671);
    expect(clip.height, 3304);
    final withImages = clip.layers
        .firstWhere((l) => l.slots.any((s) => s.kind == TvppSlotKind.image));
    final slot =
        withImages.slots.firstWhere((s) => s.kind == TvppSlotKind.image);
    final rgba = decodeTvppSlotRgba(
      fileBytes: bytes,
      slot: slot,
      width: clip.width,
      height: clip.height,
    )!;
    var opaque = 0;
    for (var p = 3; p < rgba.length; p += 4) {
      if (rgba[p] != 0) {
        opaque++;
      }
    }
    expect(opaque, greaterThan(0));
  });
}

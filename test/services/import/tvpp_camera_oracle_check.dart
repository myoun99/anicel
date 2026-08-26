// NOT part of the suite (no _test suffix): a local-only check that runs
// the PRODUCTION .tvpp camera bake against TVPaint's OWN bake — the
// `positions` array of a JSON export made from the same project. Run by
// hand:
//   flutter test test/services/import/tvpp_camera_oracle_check.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/import/tvpp_convert.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dir = r'G:\My Drive\Creative\Coding\Anicel\参考\tvp_decode\SKK_03_18-58';
  const tvpp = '$dir\\SKK_03_18_58.tvpp';
  const json = '$dir\\json\\SKK_03_18_58.json';

  test('SKK 18_58: the moving camera bakes what TVPaint baked', () {
    if (!File(tvpp).existsSync() || !File(json).existsSync()) {
      markTestSkipped('참고 파일 없음 — 로컬 전용 검증');
      return;
    }
    final bytes = Uint8List.fromList(File(tvpp).readAsBytesSync());
    final parsed = parseTvppStructure(bytes);
    final clip = parsed.clips.firstWhere((c) => c.name == '18_58');
    final converted = convertTvppClip(clip, clipIndex: 0).result;

    final oracle = (jsonDecode(File(json).readAsStringSync())
            as Map<String, dynamic>)['project']['clip']['camera']['positions']
        as List<dynamic>;
    expect(oracle, hasLength(48));
    expect(converted.camera.positions, hasLength(oracle.length),
        reason: 'one baked pose per frame');

    var worst = 0.0;
    var worstFrame = 0;
    final lines = <String>[];
    for (var i = 0; i < oracle.length; i++) {
      final o = oracle[i] as Map<String, dynamic>;
      final b = converted.camera.positions[i];
      final dy = ((o['y'] as num) - b.y).abs().toDouble();
      final dx = ((o['x'] as num) - b.x).abs().toDouble();
      final d = dx > dy ? dx : dy;
      if (d > worst) {
        worst = d;
        worstFrame = i + 1;
      }
      lines.add('f${i + 1}: oracle(${o['x']}, ${(o['y'] as num).toStringAsFixed(3)}) '
          'baked(${b.x.toStringAsFixed(3)}, ${b.y.toStringAsFixed(3)}) '
          'scale o=${o['scale']} b=${b.scale.toStringAsFixed(6)}');
      expect(b.angleDegrees, closeTo(o['angle'] as num, 1e-6));
      expect(b.scale, closeTo(o['scale'] as num, 1e-6));
    }
    // ignore: avoid_print
    lines.forEach(print);
    // ignore: avoid_print
    print('worst |Δ| = $worst at frame $worstFrame');
    // Measured 10.21px worst (1.0% of the 1036px pan, frame 7) with the
    // Δ-scaled destination-profile bezier — TVPaint's own evaluator
    // re-spaces the curve slightly and no reading of the stored handles
    // reproduced it below ~1% (the raw-offset reading was 141px out, the
    // source-profile reading 601px). Endpoints, the arrival frame and
    // the rest span are exact; this ceiling is the pin.
    expect(worst, lessThan(12),
        reason: "within ~1% of TVPaint's own bake on every frame");
    expect(converted.camera.positions.first.y, 694.0);
    for (var i = 25; i < 48; i++) {
      expect(converted.camera.positions[i].y, 1730.0,
          reason: 'at rest from one frame past the key instant');
    }
    expect(converted.camera.positions[24].y, lessThan(1730.0),
        reason: "still moving ON the key's own frame");
    for (var i = 1; i < 48; i++) {
      expect(
        converted.camera.positions[i].y,
        greaterThanOrEqualTo(converted.camera.positions[i - 1].y),
        reason: 'monotone pan',
      );
    }
  });
}

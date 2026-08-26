// NOT part of the suite (no _test suffix): a local-only check that runs
// the PRODUCTION .tvpp camera bake against TVPaint's OWN bakes — the
// `positions` arrays of JSON exports made from the same projects. Run by
// hand:
//   flutter test test/services/import/tvpp_camera_oracle_check.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/import/tvpp_convert.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const decode = r'G:\My Drive\Creative\Coding\Anicel\参考\tvp_decode';

  double check({
    required String tvpp,
    required String json,
    String? clipName,
  }) {
    final bytes = Uint8List.fromList(File(tvpp).readAsBytesSync());
    final parsed = parseTvppStructure(bytes);
    final clip = clipName == null
        ? parsed.clips.first
        : parsed.clips.firstWhere((c) => c.name == clipName);
    final converted = convertTvppClip(clip, clipIndex: 0).result;

    final oracle = (jsonDecode(File(json).readAsStringSync())
            as Map<String, dynamic>)['project']['clip']['camera']['positions']
        as List<dynamic>;
    expect(converted.camera.positions, hasLength(oracle.length),
        reason: 'one baked pose per frame');

    var worst = 0.0;
    for (var i = 0; i < oracle.length; i++) {
      final o = oracle[i] as Map<String, dynamic>;
      final b = converted.camera.positions[i];
      for (final (want, got) in [
        ((o['x'] as num).toDouble(), b.x),
        ((o['y'] as num).toDouble(), b.y),
        // Angle and zoom matter at the same visual order of magnitude
        // as a pixel here (a degree swings ~10px at these radii), so
        // one shared worst-case is honest enough.
        ((o['angle'] as num).toDouble(), b.angleDegrees),
        ((o['scale'] as num).toDouble(), b.scale),
      ]) {
        final d = (want - got).abs();
        if (d > worst) {
          worst = d;
        }
      }
    }
    return worst;
  }

  test('PROFILE_CAL: five differential exports, all channels', () {
    const base = '$decode\\PROFILE_CAL';
    if (!Directory(base).existsSync()) {
      markTestSkipped('참고 파일 없음 — 로컬 전용 검증');
      return;
    }
    for (final name in [
      '1_untouched',
      '2_point_added',
      '3_point_moved',
      '4_handle',
      '5_custom',
    ]) {
      final worst = check(
        tvpp: '$base\\$name\\$name.tvpp',
        json: '$base\\$name\\$name.json',
      );
      // ignore: avoid_print
      print('$name: worst |Δ| = $worst');
      // TVPaint's own solver quantizes at ~2^-16 of a segment (the
      // untouched bake sits a constant ~7.5e-6 of the span low), which
      // is the noise floor this ceiling allows for.
      expect(worst, lessThan(0.1), reason: '$name matches to solver noise');
    }
  });

  test('SKK 18_58: the mode=1 profile stays within its known ceiling',
      () {
    const dir = '$decode\\SKK_03_18-58';
    if (!Directory(dir).existsSync()) {
      markTestSkipped('참고 파일 없음 — 로컬 전용 검증');
      return;
    }
    final worst = check(
      tvpp: '$dir\\SKK_03_18_58.tvpp',
      json: '$dir\\json\\SKK_03_18_58.json',
      clipName: '18_58',
    );
    // ignore: avoid_print
    print('SKK 18_58: worst |Δ| = $worst');
    // This clip's authored profile says mode=1 where the calibration
    // files write mode=4, and its bake does not follow the mode-4
    // evaluator exactly — the residual (~1% of the 1036px pan) is a
    // DIFFERENT, unsolved evaluator, not noise. Pinned so a regression
    // past the known ceiling still fails.
    expect(worst, lessThan(12));
  });
}

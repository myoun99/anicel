// NOT part of the suite (no _test suffix): a local-only check that runs
// the PRODUCTION .tvpp camera bake against TVPaint's OWN bakes — the
// `positions` arrays of JSON exports made from the same projects — and
// the cut's camera the import keys from it (I-89 ⑦) against them too.
// Run by hand:
//   flutter test test/services/import/tvpp_camera_oracle_check.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/import/tvpp_convert.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';
import 'package:anicel/src/services/import/tvp_import_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Google Drive names its own folder in the system's language.
  final decode = [
    r'G:\My Drive\Creative\Coding\Anicel\参考\tvp_decode',
    r'G:\マイドライブ\Creative\Coding\Anicel\参考\tvp_decode',
  ].firstWhere((path) => Directory(path).existsSync(), orElse: () => '');

  /// The worst gap from TVPaint's own bake, of the import's bake and of the
  /// camera the import keys from it, played the way the app plays a camera.
  ({double bake, double keyed}) check({
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

    final decoded =
        jsonDecode(File(json).readAsStringSync()) as Map<String, dynamic>;
    final project = decoded['project'] as Map<String, dynamic>;
    final clipJson = project['clip'] as Map<String, dynamic>;
    final camera = clipJson['camera'] as Map<String, dynamic>;
    final oracle = camera['positions'] as List<dynamic>;
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

    final keyed = planTvpCamera(
      camera: converted.camera,
      frameCount: converted.frameCount,
    );
    var keyedWorst = 0.0;
    for (var i = 0; i < oracle.length; i++) {
      final o = oracle[i] as Map<String, dynamic>;
      final shown = resolveCameraPoseAt(
        camera: keyed,
        canvasSize: const CanvasSize(width: 1920, height: 1080),
        frameIndex: i,
      );
      for (final (want, got) in [
        ((o['x'] as num).toDouble(), shown.center.x),
        ((o['y'] as num).toDouble(), shown.center.y),
        // The two apps count the turn opposite ways, and the app's zoom
        // is TVPaint's scale turned over (`planTvpCamera`).
        ((o['angle'] as num).toDouble(), -shown.rotationDegrees),
        ((o['scale'] as num).toDouble(), 1 / shown.zoom),
      ]) {
        keyedWorst = math.max(keyedWorst, (want - got).abs());
      }
    }
    return (bake: worst, keyed: keyedWorst);
  }

  test('PROFILE_CAL: five differential exports, all channels', () {
    final base = '$decode\\PROFILE_CAL';
    if (!Directory(base).existsSync()) {
      markTestSkipped('참고 파일 없음 — 로컬 전용 검증');
      return;
    }
    for (final (name, ceiling) in [
      ('1_untouched', 0.1),
      ('2_point_added', 0.1),
      ('3_point_moved', 0.1),
      ('4_handle', 0.1),
      ('5_custom', 0.1),
      // The curve-type files share identical points AND identical
      // materialized auto-handles; only the type differs — 線形 writes
      // mode=1 (evaluated as a polyline, handles ignored; TVPaint's own
      // mode-1 solver is ~100× coarser, hence the looser ceiling),
      // スプライン writes mode=4 (the raw-handle bezier).
      ('6_multipoint_line', 2.0),
      ('7_multipoint_spline', 0.1),
    ]) {
      final worst = check(
        tvpp: '$base\\$name\\$name.tvpp',
        json: '$base\\$name\\$name.json',
      );
      // ignore: avoid_print
      print('$name: worst |Δ| = ${worst.bake}, keyed ${worst.keyed}');
      // TVPaint's own solver quantizes at ~2^-16 of a segment (the
      // untouched bake sits a constant ~7.5e-6 of the span low), which
      // is the noise floor the mode-4 ceiling allows for.
      expect(worst.bake, lessThan(ceiling),
          reason: '$name matches to solver noise');
      // The keys play the bake back within a pixel
      // (`cutCameraOfFramePoses`).
      expect(worst.keyed, lessThan(ceiling + 1),
          reason: '$name keyed plays as TVPaint does');
    }
  });

  test('SKK 18_58: the mode=1 profile stays within its known ceiling',
      () {
    final dir = '$decode\\SKK_03_18-58';
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
    print('SKK 18_58: worst |Δ| = ${worst.bake}, keyed ${worst.keyed}');
    // The one outlier: this 2026-05 file stores mode=1, which the
    // calibration pair proves means "polyline", yet its bake is SMOOTH
    // (it locally exceeds an interior point's value — impossible for a
    // polyline or any hull-bounded reading of its stored handles). Some
    // ingredient of the older file differs; the polyline reading lands
    // within ~1% of the pan and is pinned here so a regression past the
    // known ceiling still fails.
    expect(worst.bake, lessThan(12));
    expect(worst.keyed, lessThan(13));
  });
}

@Tags(['impeller'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/shaded_passes.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';

import '../../helpers/iris_truth.dart';

/// 🗣️I-132-Q15 a (유저 2026-10-28): 「모든 모양을 정확히 — 행 누적합」 — a
/// camera lens blur's iris covers exactly the pixel centres its shape
/// holds, row by row, as the GPU lays its table (`iris_table.frag`), at one
/// level or at each of a blur map's.
///
/// The truth is the shape asked point by point ([pastTheIris]). ⚠️A centre
/// within [band] of the edge may fall either way: the GPU works in floats,
/// and puts a centre a hair from the edge on it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(IrisBlurShader.load);

  const band = 0.02;

  IrisProperties iris(
    int sides, {
    double roundness = 0,
    double aspect = 1,
    double rotation = 0,
  }) => (
    sides: sides,
    roundness: roundness,
    aspect: aspect,
    rotation: rotation,
    fringe: 0,
  );

  void expectCovers(
    List<IrisRow> rows,
    double radius,
    IrisProperties shape, {
    String reason = '',
  }) {
    final reach = radius.floor();
    expect(rows, hasLength(2 * reach + 1), reason: reason);
    for (var dy = -reach; dy <= reach; dy += 1) {
      final row = rows[dy + reach];
      for (var dx = -reach - 1; dx <= reach + 1; dx += 1) {
        final past = pastTheIris(dx, dy, radius, shape);
        final covered = row.left <= dx && dx <= row.right;
        if (past.abs() < band) {
          continue;
        }
        expect(
          covered,
          past < 0,
          reason: '($dx, $dy) of $shape, r $radius $reason',
        );
      }
    }
  }

  testWidgets('every shape, rounded, squeezed and turned, covers exactly the '
      'centres it holds', (tester) async {
    final random = math.Random(132);
    for (var trial = 0; trial < 300; trial += 1) {
      final radius = 0.5 + random.nextDouble() * 30;
      final shape = iris(
        3 + random.nextInt(8),
        roundness: switch (trial % 3) {
          0 => 0,
          1 => 1,
          _ => random.nextDouble(),
        },
        aspect: math.pow(10, random.nextDouble() * 2 - 1).toDouble(),
        rotation: (random.nextDouble() * 2 - 1) * math.pi,
      );
      final pass = IrisGatherPass(
        radius: radius,
        iris: shape,
        paper: null,
        light: null,
      );
      final level = irisLevelOf(await irisTableOf(tester, pass), pass.reach);
      expect(level.reach, radius.floor());
      expectCovers(level.rows, radius, shape);
    }
  });

  testWidgets('its core is the iris drawn smaller, row for row', (
    tester,
  ) async {
    final shape = iris(6, roundness: 0.3, rotation: 0.4);
    final pass = IrisGatherPass(
      radius: 17,
      iris: shape,
      paper: null,
      light: null,
    );
    final table = await irisTableOf(tester, pass);
    final core = irisLevelOf(table, pass.reach, k: 1).rows;
    expect(core, hasLength(35));
    for (var dy = -17; dy <= 17; dy += 1) {
      final row = core[dy + 17];
      for (var dx = -18; dx <= 18; dx += 1) {
        final past = pastTheIris(dx, dy, 17 * irisCoreScale, shape);
        if (past.abs() < band) {
          continue;
        }
        expect(row.left <= dx && dx <= row.right, past < 0, reason: '$dx $dy');
      }
    }
  });

  testWidgets('each level\'s first row says what its outline and its core '
      'cover, all their rows — what a pixel\'s mean is over', (tester) async {
    final shape = iris(7, roundness: 0.3, aspect: 1.6, rotation: 0.9);
    for (final mapped in [false, true]) {
      final pass = IrisGatherPass(
        radius: 40.5,
        iris: shape,
        paper: null,
        light: null,
        map: mapped
            ? (channel: IrisMapChannel.luminance, focal: 30, inverts: false)
            : null,
      );
      final table = await irisTableOf(tester, pass);
      for (final level in mapped ? [0, 29, 30, 31, 128, 255] : [0]) {
        for (final k in [0, 1]) {
          final laid = irisLevelOf(table, pass.reach, level: level, k: k);
          expect(
            laid.covered,
            coveredBy(laid.rows),
            reason: 'level $level, k $k',
          );
        }
      }
      expect(
        irisLevelOf(table, pass.reach, level: mapped ? 255 : 0).covered,
        greaterThan(1000),
        reason: 'fixture: an iris that covers',
      );
    }
  });

  testWidgets('a triangle points up and lies flat along its bottom; a square '
      'stands square, an aspect of 2 is twice as wide as tall, and a quarter '
      'turn is clockwise', (tester) async {
    Future<List<IrisRow>> rowsOf(IrisProperties shape) async => irisLevelOf(
      await irisTableOf(
        tester,
        IrisGatherPass(radius: 20, iris: shape, paper: null, light: null),
      ),
      20,
    ).rows;

    final triangle = await rowsOf(iris(3));
    // Its bottom edge lies half its radius below the centre.
    expect(triangle[20 + 10].right - triangle[20 + 10].left, greaterThan(30));
    expect(triangle[20 + 11].left, greaterThan(triangle[20 + 11].right));
    expect(triangle[0].right - triangle[0].left, lessThanOrEqualTo(1));

    final half = (20 / math.sqrt2).floor();
    final square = await rowsOf(iris(4));
    for (var dy = -20; dy <= 20; dy += 1) {
      final row = square[dy + 20];
      expect(
        (row.left, row.right),
        dy.abs() <= half ? (-half, half) : (1, 0),
        reason: 'row $dy',
      );
    }
    final wide = await rowsOf(iris(4, aspect: 2));
    expect(wide[20], (left: -half, right: half), reason: 'as wide');
    expect(
      [
        for (var dy = -20; dy <= 20; dy += 1)
          if (wide[dy + 20].left <= wide[dy + 20].right) dy,
      ].first,
      -(20 / math.sqrt2 / 2).floor(),
      reason: 'half as tall',
    );

    final turned = await rowsOf(iris(3, rotation: math.pi / 2));
    // Its point, out right on the middle row; its flat side, upright, half
    // its radius left of the centre.
    expect(turned[20].right, 20);
    expect(turned[20].left, -10);
  });

  testWidgets('a blur map lays a level for each of its values: the radius '
      'times how far the value lies from the focal distance, over 255', (
    tester,
  ) async {
    final shape = iris(5, roundness: 0.5);
    // At 600 a level's 1201 rows take two lines.
    for (final (most, width) in [(24.0, 2 * 49), (600.0, 2048)]) {
      for (final inverts in [false, true]) {
        final pass = IrisGatherPass(
          radius: most,
          iris: shape,
          paper: null,
          light: null,
          map: (
            channel: IrisMapChannel.luminance,
            focal: 100.5,
            inverts: inverts,
          ),
        );
        final table = await irisTableOf(tester, pass);
        expect(table.width, width, reason: 'fixture');
        for (final level in [0, 60, 100, 101, 200, 255]) {
          final value = inverts ? 255 - level : level;
          final radius = most * (value - 100.5).abs() / 255;
          final laid = irisLevelOf(table, pass.reach, level: level);
          final reason = 'level $level of $most, inverts $inverts';
          expect(laid.reach, radius.floor(), reason: reason);
          expectCovers(laid.rows, radius, shape, reason: reason);
        }
      }
    }
  });

  testWidgets('an iris of more than 1024 rows lays them over lines', (
    tester,
  ) async {
    final shape = iris(8, roundness: 0.2);
    final pass = IrisGatherPass(
      radius: 700.5,
      iris: shape,
      paper: null,
      light: null,
    );
    final table = await irisTableOf(tester, pass);
    expect(table.width, 2048, reason: 'fixture: 1401 rows are two lines');
    final rows = irisLevelOf(table, pass.reach).rows;
    for (final dy in [-700, -400, 0, 323, 324, 699]) {
      final row = rows[dy + 700];
      for (final dx in [row.left - 1, row.left, row.right, row.right + 1]) {
        final past = pastTheIris(dx, dy, 700.5, shape);
        if (past.abs() < band) {
          continue;
        }
        expect(row.left <= dx && dx <= row.right, past < 0, reason: '$dx $dy');
      }
    }
  });
}

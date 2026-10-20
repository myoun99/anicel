import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/canvas/level_image.dart';

/// 🗣️유저 2026-10-18 (a-big-reference-picture-still-costs-when-zoomed-out-Q1):
/// 「엔진과 같은 바이트를 내는 CPU 반감을 찾는다」 · 「최대한 반감 한곳으로. 법
/// 통일하고싶음.」
///
/// The halving stays the engine's ([halvingPicture]): the CPU halves through
/// a table READ OFF the engine once ([measuredHalving]), and where the
/// engine's halving is not the sum's there is no table.
void main() {
  setUp(debugForgetMeasuredHalving);

  tearDown(() {
    debugEngineHalving = null;
    debugForgetMeasuredHalving();
  });

  /// [width] × [height] premultiplied texels at random — every value at most
  /// its alpha, the alpha whole where [opaque].
  Uint8List randomPremultiplied(
    int seed,
    int width,
    int height, {
    required bool opaque,
  }) {
    final random = math.Random(seed);
    final bytes = Uint8List(width * height * 4);
    for (var at = 0; at < bytes.length; at += 4) {
      final alpha = opaque ? 255 : random.nextInt(256);
      for (var channel = 0; channel < 3; channel += 1) {
        bytes[at + channel] = random.nextInt(alpha + 1);
      }
      bytes[at + 3] = alpha;
    }
    return bytes;
  }

  Uint8List cpuHalved(Uint8List table, Uint8List bytes, int width, int height) {
    final half = Uint8List(width * height);
    halveRgbaWords(
      table,
      bytes.buffer.asUint32List(),
      fromStart: 0,
      fromStride: width,
      width: width,
      height: height,
      into: half.buffer.asUint32List(),
      intoStart: 0,
      intoStride: width ~/ 2,
    );
    return half;
  }

  Future<Uint8List> engineHalved(Uint8List bytes, int width, int height) async {
    final image = await uploadRawRgba(bytes, width: width, height: height);
    final picture = halvingPicture([(image: image, at: ui.Offset.zero)]);
    final half = await picture.toImage(width ~/ 2, height ~/ 2);
    picture.dispose();
    image.dispose();
    final data = await half.toByteData(format: ui.ImageByteFormat.rawRgba);
    half.dispose();
    return data!.buffer.asUint8List();
  }

  /// [bytes] halved on the CPU by [rule], a value for the sum of a block's
  /// four at the block's place in the half ([x], [y]).
  Uint8List halvedBy(
    Uint8List bytes,
    int width,
    int height,
    int Function(int sum, int x, int y) rule,
  ) {
    final half = Uint8List(width * height);
    for (var y = 0; y < height ~/ 2; y += 1) {
      for (var x = 0; x < width ~/ 2; x += 1) {
        for (var channel = 0; channel < 4; channel += 1) {
          int at(int dx, int dy) =>
              bytes[((2 * y + dy) * width + 2 * x + dx) * 4 + channel];
          final sum = at(0, 0) + at(1, 0) + at(0, 1) + at(1, 1);
          half[(y * (width ~/ 2) + x) * 4 + channel] = rule(sum, x, y);
        }
      }
    }
    return half;
  }

  /// The Surface Pro 11's halving (Impeller GLES, 2026-10-21): the nearest
  /// value of the four's sum, a tie down but for 127.5, up.
  int deviceRule(int sum, int _, int _) =>
      sum % 4 == 2 && sum != 510 ? sum ~/ 4 : (sum + 2) ~/ 4;

  Uint8List tableOf(int Function(int sum, int x, int y) rule) =>
      Uint8List.fromList([
        for (var sum = 0; sum <= 1020; sum += 1) rule(sum, 0, 0),
      ]);

  testWidgets('🔬the test runner\'s engine halves a tie two ways — a block '
      'spread one way, packed the other — so it has NO table, and its every '
      'level is the engine\'s', (tester) async {
    await tester.runAsync(() async {
      // A sum of 490 four ways: 122.5 rounded down spread, up packed.
      final block = Uint8List.fromList([
        for (final value in [123, 123, 122, 122, 255, 235, 0, 0])
          ...List.filled(4, value),
      ]);
      final strip = Uint8List(4 * 2 * 4);
      for (var texel = 0; texel < 4; texel += 1) {
        for (final (way, x0) in [(0, 0), (1, 2)]) {
          final at = ((texel ~/ 2) * 4 + x0 + texel % 2) * 4;
          strip.setRange(at, at + 4, block, (way * 4 + texel) * 4);
        }
      }
      final halved = await engineHalved(strip, 4, 2);
      expect(
        {halved[0], halved[4]},
        hasLength(2),
        reason: '⛔전제: one sum, two values',
      );

      expect(measuredHalvingIfRead, isNull, reason: 'not read before asked');
      expect(await measuredHalving(), isNull);
      expect(measuredHalvingIfRead, isNull);
    });
  });

  test('the CPU halves through a table two channels a lane: every texel, '
      'translucent and opaque, the table\'s for its block\'s sum', () {
    final table = tableOf(deviceRule);
    for (final opaque in [false, true]) {
      final bytes = randomPremultiplied(opaque ? 2 : 1, 64, 48, opaque: opaque);
      expect(
        cpuHalved(table, bytes, 64, 48),
        halvedBy(bytes, 64, 48, deviceRule),
        reason: opaque ? 'opaque' : 'translucent',
      );
    }
  });

  test('…from a part of the rows into a part of others: the strides and '
      'the starts are each side\'s own', () {
    final table = tableOf(deviceRule);
    final from = randomPremultiplied(3, 12, 10, opaque: false);
    final into = Uint32List(9 * 6)..fillRange(0, 9 * 6, 0xDEADBEEF);
    // The 8×6 block at (2, 4) of the 12-wide source, into (3, 1) of a
    // 9-wide target.
    halveRgbaWords(
      table,
      from.buffer.asUint32List(),
      fromStart: 4 * 12 + 2,
      fromStride: 12,
      width: 8,
      height: 6,
      into: into,
      intoStart: 1 * 9 + 3,
      intoStride: 9,
    );
    final whole = halvedBy(from, 12, 10, deviceRule).buffer.asUint32List();
    for (var y = 0; y < 6; y += 1) {
      for (var x = 0; x < 9; x += 1) {
        final inside = x >= 3 && x < 7 && y >= 1 && y < 4;
        expect(
          into[y * 9 + x],
          inside ? whole[(y - 1 + 2) * 6 + (x - 3 + 1)] : 0xDEADBEEF,
          reason: '($x, $y)',
        );
      }
    }
  });

  testWidgets('a halving the sum says is read as it is — whatever its '
      'rounding — and read once', (tester) async {
    var strips = 0;
    debugEngineHalving = (bytes, width, height) async {
      strips += 1;
      return halvedBy(bytes, width, height, (sum, _, _) => (sum + 3) ~/ 4);
    };
    final table = await measuredHalving();
    expect(table, [for (var sum = 0; sum <= 1020; sum += 1) (sum + 3) ~/ 4]);
    expect(strips, 2, reason: 'a strip across and one down');
    expect(await measuredHalving(), same(table));
    expect(strips, 2, reason: 'and not again');
  });

  testWidgets('a halving the sum alone does not say has no table — four '
      'values of one sum apart, or one sum apart far along a strip, across '
      'or down', (tester) async {
    // A sum's four blocks lie side by side along a strip: rounded another
    // way far along one strip, the sum halves two ways across the two.
    int far(int sum, int along) =>
        along > 1000 && sum.isOdd ? sum ~/ 4 + 1 : sum ~/ 4;
    final rules = <String, int Function(int sum, int x, int y)>{
      'one sum two ways': (sum, _, _) => sum ~/ 4,
      'far across': (sum, x, _) => far(sum, x),
      'far down': (sum, _, y) => far(sum, y),
    };
    for (final MapEntry(key: name, value: rule) in rules.entries) {
      debugForgetMeasuredHalving();
      debugEngineHalving = (bytes, width, height) async {
        final half = halvedBy(bytes, width, height, rule);
        if (name == 'one sum two ways') {
          // The first block, of the sum 0, halves apart from its three.
          half[0] = 255;
        }
        return half;
      };
      expect(await measuredHalving(), isNull, reason: name);
    }
  });

  testWidgets('an engine that cannot make or hold a strip has no table', (
    tester,
  ) async {
    for (final (name, halving) in <(String, Future<Uint8List?> Function())>[
      ('held no strip', () async => null),
      ('threw', () async => throw StateError('lost context')),
    ]) {
      debugForgetMeasuredHalving();
      debugEngineHalving = (_, _, _) => halving();
      expect(await measuredHalving(), isNull, reason: name);
    }
  });
}

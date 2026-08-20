import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/layout/device_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arithmetic of the device-pixel grid, pinned on its own before it has
/// a single call site.
///
/// Everything here runs at FRACTIONAL ratios. At 1.0 / 2.0 / 3.0 the whole
/// mechanism is the identity on integer-logical input, so a pin written at
/// an integral ratio would pass with the quantizer deleted.
void main() {
  group('cumulative positions, not independent widths', () {
    test('three thirds of 800 land on the grid and still sum to 800', () {
      const grid = DeviceGrid(1.25);
      final run = grid.run();
      const third = 800.0 / 3;

      final widths = <double>[run.take(third), run.take(third), run.take(third)];

      // The boundaries are exactly on device pixels...
      expect(run.position * 1.25, closeTo(1000.0, 1e-9));
      // ...and nothing was lost or gained on the way: the run's own total
      // is exactly the parent's extent, so a Row built from these widths
      // neither overflows nor leaves a gap.
      expect(widths.reduce((a, b) => a + b), closeTo(800.0, 1e-9));

      var cumulative = 0.0;
      final devices = <double>[];
      for (final width in widths) {
        cumulative += width;
        devices.add(cumulative * 1.25);
      }
      expect(devices[0], closeTo(333.0, 1e-6));
      expect(devices[1], closeTo(666.0, 1e-6));
      expect(devices[2], closeTo(1000.0, 1e-6));
    });

    test('CONTROL: per-width snapping passes isOnGrid and still misses the '
        'parent by a whole device pixel', () {
      // ⚠️The first draft of this control was arithmetic on literals — it
      // survived deleting the entire library, which makes it decoration
      // rather than a control. It now builds the forbidden construction
      // out of the real class.
      const grid = DeviceGrid(1.25);
      const third = 800.0 / 3;

      final perWidth = List<double>.filled(3, grid.position(third));

      // Every width is INDIVIDUALLY on the grid. A per-value predicate
      // cannot tell the forbidden construction from the correct one —
      // only the sum can, which is exactly why the rule is about
      // cumulative positions and not about widths.
      for (final width in perWidth) {
        expect(grid.isOnGrid(width), isTrue);
      }
      expect(perWidth.reduce((a, b) => a + b) * 1.25, closeTo(999.0, 1e-6));

      // The run, given the same three extents, lands on 1000.
      final run = grid.run();
      final viaRun = <double>[run.take(third), run.take(third), run.take(third)];
      expect(viaRun.reduce((a, b) => a + b), closeTo(800.0, 1e-9));
      expect(run.position * 1.25, closeTo(1000.0, 1e-6));
    });

    test('a long run carries ONE rounding, not one per element', () {
      const grid = DeviceGrid(1.125);
      final run = grid.run();
      const extent = 7.3;
      for (var i = 0; i < 200; i++) {
        run.take(extent);
      }
      // 200 independent floors would lose up to 200 device pixels. The run
      // is allowed to lose less than one.
      final exact = extent * 200 * 1.125;
      expect(exact - run.position * 1.125, lessThan(1.0));
      expect(grid.isOnGrid(run.position), isTrue);
    });

    test('a run anchored at a snapped origin composes exactly', () {
      const grid = DeviceGrid(1.35);
      final origin = grid.position(97.4);
      final nested = grid.run(from: origin);
      nested.take(31.7);

      // floor(int + x) == int + floor(x): the nested chain adds no rounding
      // of its own, so the boundary matches the flat computation.
      final flat = grid.position(origin + 31.7);
      expect(nested.position, closeTo(flat, 1e-12));
    });
  });

  group('position', () {
    test('never overshoots its input', () {
      const grid = DeviceGrid(1.125);
      for (var i = 0; i < 500; i++) {
        final value = i * 0.37;
        expect(grid.position(value), lessThanOrEqualTo(value + 1e-9));
      }
    });

    test('leaves an already-on-grid constant exactly alone', () {
      // ⚠️These three are DYADIC — 48 * 1.25 is exactly 60.0 — so they
      // pass with the slack deleted entirely. They pin that the quantizer
      // does not MOVE a correct constant, which is a real but different
      // promise from rescuing one, and an earlier draft of this file cited
      // them as the slack's justification. They are not.
      expect(const DeviceGrid(1.25).position(48), closeTo(48.0, 1e-12));
      expect(const DeviceGrid(1.125).position(8), closeTo(8.0, 1e-12));
      expect(const DeviceGrid(2.625).position(16), closeTo(16.0, 1e-12));

      // THIS is what the slack is for: a 1× monitor at a 115% UI scale.
      // The ratio itself is inexact (1.1499999999999999), so a correct
      // constant lands a few ulps below a whole device pixel and a bare
      // floor drops it by a whole one.
      const product = 1.0 * 1.15;
      final grid = DeviceGrid(product);
      for (final logical in <double>[180, 200, 220, 360, 400]) {
        final device = logical * product;
        expect(
          device,
          lessThan(device.roundToDouble()),
          reason: 'the deficit at $logical must be real for this to pin',
        );
        expect(
          device.floorToDouble(),
          device.roundToDouble() - 1,
          reason: 'a bare floor loses a whole device pixel at $logical',
        );
        expect(grid.position(logical), closeTo(logical, 1e-12));
      }
    });

    test('floors NEGATIVE positions too — truncation would drift toward '
        'zero', () {
      // `truncateToDouble` is the most natural slip when rewriting this
      // line, and it is invisible on a positive-only sweep: at 1.25,
      // position(-0.001) would go from -0.8 to -0.0. Scroll offsets and
      // overscroll reach negatives, and PR8-10 quantizes those.
      for (final ratio in <double>[1.125, 1.25, 1.35, 1.5, 2.625, 1.5 * 0.7]) {
        final grid = DeviceGrid(ratio);
        for (var i = 1; i <= 2000; i++) {
          final value = -i * 0.37;
          expect(
            grid.position(value),
            lessThanOrEqualTo(value + 1e-10),
            reason: 'ratio $ratio overshot toward zero at $value',
          );
          expect(grid.isOnGrid(grid.position(value)), isTrue);
        }
      }
    });

    test('is idempotent at fractional ratios', () {
      for (final ratio in <double>[1.125, 1.25, 1.35, 1.5, 1.75, 2.625]) {
        final grid = DeviceGrid(ratio);
        for (var i = 0; i < 3000; i++) {
          final once = grid.position(i * 0.41);
          expect(
            grid.position(once),
            closeTo(once, 1e-12),
            reason: 'ratio $ratio, i=$i snapped twice and moved',
          );
        }
      }
    });

    test('lands on the grid it claims to', () {
      for (final ratio in <double>[1.125, 1.25, 1.35, 1.75, 1.5, 2.625]) {
        final grid = DeviceGrid(ratio);
        for (var i = 0; i < 200; i++) {
          expect(grid.isOnGrid(grid.position(i * 1.7)), isTrue);
        }
      }
    });

    test('isOnGrid says NO when it should', () {
      // ⚠️Without this, `isOnGrid => true` makes the two pins that delegate
      // to it vacuous — and PR2's audit gate has nothing else to hang on.
      for (final ratio in <double>[1.125, 1.25, 1.35, 1.5, 2.625, 1.5 * 0.7]) {
        final grid = DeviceGrid(ratio);
        expect(
          grid.isOnGrid(10.3),
          isFalse,
          reason: 'ratio $ratio called an off-grid anchor on-grid',
        );
        final on = grid.position(97.4);
        expect(grid.isOnGrid(on), isTrue);
        // A hundredth of a device pixel away is still off, so the
        // predicate is not a rubber stamp with a wide tolerance.
        expect(grid.isOnGrid(on + 0.01 / ratio), isFalse);
      }
    });

    test('passes values through unchanged when the ratio is unusable', () {
      // A degenerate ratio must not turn every coordinate into an infinity;
      // the grid simply stops claiming anything.
      for (final ratio in <double>[0, -1, double.nan, double.infinity]) {
        expect(DeviceGrid(ratio).position(37.3), 37.3);
        expect(DeviceGrid(ratio).isOnGrid(37.3), isTrue);
      }
      expect(const DeviceGrid(1.25).position(double.nan).isNaN, isTrue);
    });
  });

  group('the slack is relative, and both fixed alternatives were measured '
      'to fail', () {
    // Ratios that a real ladder × monitor matrix produces. These are
    // PRODUCTS, which is the whole point: an integer times a dyadic ratio
    // is exact, so the deficits this slack exists for only appear once a
    // UI scale multiplies the monitor's ratio.
    const productRatios = <double>[
      1.5 * 0.7,
      1.25 * 0.9,
      1.5 * 0.9,
      1.75 * 0.9,
      1.625 * 0.9,
      2.625 * 1.1,
      1.75 * 1.1,
    ];

    test('rescues a correct constant at a product ratio', () {
      // 1.5 * 0.7 lands on 1.0499999999999998, and 20 * that arrives as
      // 20.999999999999996. A bare floor would move a correct 20 by a
      // whole device pixel.
      const ratio = 1.5 * 0.7;
      expect(20 * ratio, lessThan(21.0), reason: 'the deficit is real');
      expect(DeviceGrid(ratio).position(20), closeTo(20.0, 1e-12));
    });

    /// Coordinates whose DEVICE position sits a hair BELOW a whole pixel —
    /// the only place an over-large slack can overshoot.
    ///
    /// ⚠️A uniform sweep cannot find these. A fixed 1e-6 slack overshoots
    /// only when the fractional part exceeds 1 - 1e-6, so a random sample
    /// hits it about once in a million; 44,000 samples of `i * 0.31` found
    /// nothing and the mutation survived. The boundary has to be built,
    /// not stumbled upon.
    Iterable<({double logical, double deficit})> nearMisses(double ratio) sync* {
      for (var k = 1; k <= 400; k++) {
        for (final deficit in <double>[1e-7, 5e-7, 9e-7]) {
          yield (logical: (k - deficit) / ratio, deficit: deficit);
        }
      }
    }

    test('never overshoots by more than Flutter calls an overflow', () {
      // RenderFlex reports an overflow above precisionErrorTolerance, so
      // an overshoot larger than that is not a rounding curiosity — it is
      // a red "overflowed by 3.20e-7 pixels" banner on a Row built from a
      // run, which is what the fixed 1e-6 device epsilon actually produced.
      const tolerance = 1e-10;
      for (final ratio in <double>[...productRatios, 1.125, 1.25, 1.35, 3.0]) {
        final grid = DeviceGrid(ratio);
        for (final near in nearMisses(ratio)) {
          expect(
            grid.position(near.logical) - near.logical,
            lessThanOrEqualTo(tolerance),
            reason:
                'ratio $ratio overshot at ${near.logical} '
                '(${near.deficit} device px below a whole pixel)',
          );
        }
      }
    });

    test('a run never hands out more than it was given', () {
      // The same property one level up, and this is the one a Row
      // overflows on. Each extent is built to land the run's cumulative
      // position just under a device pixel.
      for (final ratio in <double>[...productRatios, 1.25, 1.35]) {
        for (final near in nearMisses(ratio)) {
          final run = DeviceGrid(ratio).run();
          final handed = run.take(near.logical);
          expect(
            handed,
            lessThanOrEqualTo(near.logical + 1e-10),
            reason: 'ratio $ratio gave ${near.logical}, handed out $handed',
          );
        }
      }
    });

    test('stays idempotent at scroll-offset magnitudes', () {
      // A fixed epsilon small enough not to overshoot (1e-9) breaks HERE
      // instead, dropping a whole device pixel on the second snap.
      //
      // ⚠️The magnitudes are the test. The failures concentrate around
      // 1e7, where a coordinate's own ulp finally exceeds a 1e-9 constant;
      // a first draft that sampled 1e3 / 1e6 / 1e9 found NOTHING and the
      // mutation survived — 1e9 does not fail, because the doubles there
      // are already coarser than the grid. Measured with the constant:
      // 302 failures in 48,000, worst 0.35 logical at x=1.0000001e7,
      // ratio 2.8875.
      for (final ratio in productRatios) {
        final grid = DeviceGrid(ratio);
        for (final magnitude in <double>[1e3, 1e5, 1e6, 1e7, 1e8, 1e9]) {
          for (var i = 0; i < 400; i++) {
            final value = magnitude + i * 0.37;
            final once = grid.position(value);
            expect(
              grid.position(once),
              closeTo(once, 1e-9),
              reason: 'ratio $ratio at magnitude $magnitude, value $value',
            );
          }
        }
      }
    });
  });

  group('degenerate input cannot poison anything', () {
    test('a non-finite ratio is normalised, so == stays reflexive', () {
      // A stored NaN makes `a == a` false while the hash codes still
      // collide. This class is read in shouldRepaint / updateShouldNotify,
      // where "never equal to itself" pins *changed* for ever.
      for (final ratio in <double>[double.nan, double.infinity, -1, 0]) {
        final grid = DeviceGrid(ratio);
        expect(grid == grid, isTrue, reason: 'ratio $ratio');
        expect(grid.isActive, isFalse, reason: 'ratio $ratio');
        expect(grid.ratio.isNaN, isFalse, reason: 'ratio $ratio');
      }
      expect(DeviceGrid(double.nan), DeviceGrid(double.infinity));
    });

    test('isOnGrid is vacuously true on an inactive grid', () {
      // Which is why an audit has to ask isActive first, or it reports a
      // perfect grid on a broken ratio.
      final grid = DeviceGrid(0);
      expect(grid.isOnGrid(37.3), isTrue);
      expect(grid.isActive, isFalse);
    });

    test('a non-finite extent does not poison the rest of the run', () {
      // Measured on the first draft: [120, infinity, 40, 40] returned
      // [120, Infinity, NaN, NaN] and never recovered. take(maxWidth)
      // under an unbounded parent is an ordinary spelling.
      final run = DeviceGrid(1.25).run();
      expect(run.take(120), closeTo(120.0, 1e-9));
      expect(
        () => run.take(double.infinity),
        throwsA(isA<AssertionError>()),
        reason: 'debug builds must catch it at the call site',
      );
      // Release behaviour: refused, not accumulated — the run survives.
      expect(run.position, closeTo(120.0, 1e-9));
      expect(run.take(40), closeTo(40.0, 1e-9));
      expect(run.position.isFinite, isTrue);
    });

    test('finite extents that OVERFLOW when summed are refused too', () {
      // The case the assert cannot see, and the reason the guard sits on
      // the result rather than the argument: every extent here is finite,
      // so nothing trips in debug, and a guard on the argument would let
      // the run go to infinity and then to NaN for ever after.
      final run = DeviceGrid(1.25).run();
      expect(run.take(1e308), closeTo(1e308, 1e300));
      expect(run.take(1e308), 0.0, reason: 'the overflowing take gets no ground');
      // The property is that the run stays a NUMBER. It is saturated at an
      // absurd position and further extents are beneath the representable
      // spacing there, so they legitimately get nothing — but nothing is
      // ever Infinity or NaN, which is what would have leaked out into a
      // sibling's constraints.
      expect(run.position.isFinite, isTrue);
      expect(run.take(40).isNaN, isFalse);
      expect(run.position.isFinite, isTrue);
    });

    test('an off-grid anchor trips the invariant', () {
      // run(from: 10.3) at 1.25 reports 9.6 — the subtree shifted 0.875
      // device px — while the first take(48) still returns exactly 48.0.
      // Nothing downstream can notice, so the anchor is the only place it
      // can be caught.
      const grid = DeviceGrid(1.25);
      expect(() => grid.run(from: 10.3), throwsA(isA<AssertionError>()));
      // Everything a legitimate caller can produce passes.
      expect(() => grid.run(), returnsNormally);
      expect(() => grid.run(from: grid.position(10.3)), returnsNormally);
      final live = grid.run()..take(17.9);
      expect(() => grid.run(from: live.position), returnsNormally);
    });
  });

  test('a run telescopes: the extents it hands out sum to the ground it '
      'covered', () {
    // The property every caller depends on without stating it — a
    // Positioned laid out from these extents ends exactly where the run
    // says it does.
    for (final ratio in <double>[1.125, 1.35, 1.5 * 0.7, 2.625]) {
      final grid = DeviceGrid(ratio);
      final from = grid.position(96.0);
      final run = grid.run(from: from);
      var sum = 0.0;
      for (var i = 1; i <= 40; i++) {
        sum += run.take(i * 1.3);
      }
      expect(sum, closeTo(run.position - from, 1e-9), reason: 'ratio $ratio');
    }
  });

  testWidgets('DeviceGrid.of reads the EFFECTIVE ratio, not the hardware', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.25;
    tester.view.physicalSize = const Size(2000, 1250);
    addTearDown(tester.view.reset);

    late DeviceGrid grid;
    late double mediaQuery;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ),
        child: EffectiveDevicePixelRatioScope(
          uiScale: 0.9,
          child: Builder(
            builder: (context) {
              grid = DeviceGrid.of(context);
              mediaQuery = MediaQuery.devicePixelRatioOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(grid.ratio, closeTo(1.125, 1e-9));
    // The scope corrects MediaQuery to match, so a site that reaches for
    // it lands on the same grid. The HARDWARE ratio stays reachable from
    // the FlutterView, which nothing rewrites — that is the number a
    // form-factor question wants, and the grid never does.
    expect(mediaQuery, closeTo(1.125, 1e-9));
    expect(tester.view.devicePixelRatio, 1.25);
  });
}

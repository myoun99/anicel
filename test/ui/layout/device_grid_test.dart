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

    test(
      'CONTROL: rounding each width on its own drifts a whole device pixel',
      () {
        // The bug wearing the fix's clothes. If this ever matches the run
        // above, the run has stopped doing anything.
        const third = 800.0 / 3;
        final independent = (third * 1.25).floorToDouble() * 3;
        expect(independent, 999.0);
        expect(independent, isNot(closeTo(1000.0, 0.5)));
      },
    );

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
      // 48 * 1.25 arrives as 59.99999999999999. Without the epsilon this
      // floors to 59 and the quantizer MOVES a correct constant by a whole
      // device pixel — worse than not quantizing at all.
      expect(const DeviceGrid(1.25).position(48), closeTo(48.0, 1e-12));
      expect(const DeviceGrid(1.125).position(8), closeTo(8.0, 1e-12));
      expect(const DeviceGrid(2.625).position(16), closeTo(16.0, 1e-12));
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
      for (final ratio in <double>[1.125, 1.25, 1.35, 1.75]) {
        final grid = DeviceGrid(ratio);
        for (var i = 0; i < 200; i++) {
          expect(grid.isOnGrid(grid.position(i * 1.7)), isTrue);
        }
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

  testWidgets('DeviceGrid.of reads the EFFECTIVE ratio, not MediaQuery', (
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
    expect(mediaQuery, closeTo(1.25, 1e-9));
  });
}

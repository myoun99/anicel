import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/layout/device_grid_audit.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The quantization audit, landed BEFORE the quantization.
///
/// ⚠️Fractional ratio throughout, and BOTH `devicePixelRatio` and
/// `physicalSize` are set — changing the ratio alone silently moves the
/// logical viewport, and `setSurfaceSize` (which the repo's other editor
/// harnesses use) desynchronises MediaQuery from the render tree and
/// builds a letterbox scale into the root, which would make every phase
/// measured here meaningless.
void main() {
  setUp(DeviceGridAudit.debugReset);
  tearDown(DeviceGridAudit.debugReset);

  void useRatio(
    WidgetTester tester,
    double ratio, {
    Size logical = const Size(800, 600),
  }) {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(
      logical.width * ratio,
      logical.height * ratio,
    );
    addTearDown(tester.view.reset);
  }

  Widget surface({
    Key? key,
    required double left,
    String label = 'probe',
    Size size = const Size(100, 100),
    Widget Function(Widget)? wrap,
  }) {
    Widget raster = StaticRaster(
      key: key,
      debugLabel: label,
      child: const ColoredBox(color: Color(0xFF112233)),
    );
    if (wrap != null) {
      raster = wrap(raster);
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: left,
            top: 0,
            width: size.width,
            height: size.height,
            child: raster,
          ),
        ],
      ),
    );
  }

  group('the phase is a SIGNED DISTANCE to the nearest gridline', () {
    testWidgets('a surface just PAST a gridline reports a small negative', (
      tester,
    ) async {
      useRatio(tester, 1.25);
      // 10.3 × 1.25 = 12.875 device — an eighth of a pixel BEFORE 13, not
      // seven-eighths after 12.
      await tester.pumpWidget(surface(left: 10.3));
      await tester.pump();

      final report = DeviceGridAudit.sweep();
      expect(report.violations, hasLength(1));
      expect(report.violations.single.originPhase.dx, closeTo(-0.125, 1e-6));
      expect(report.violations.single.originPhase.dy, closeTo(0.0, 1e-6));
      expect(report.violations.single.worst, closeTo(0.125, 1e-6));
    });

    testWidgets('★the quantizer\'s OWN output is never a violation', (
      tester,
    ) async {
      // 🚨The first draft compared the raw fractional part against exact
      // zero, so a boundary the quantizer had just snapped came back at
      // 0.99999999999 and reported as the WORST possible violation —
      // measured, 300 of 4000 samples at ratio 1.7. The audit could never
      // have gone green, and the whole round rests on it being able to.
      useRatio(tester, 1.7);
      const ratio = 1.7;
      for (var i = 0; i < 12; i++) {
        // Exactly what DeviceGrid.position produces: floor(x·r)/r.
        final snapped = ((i * 17 + 3) * ratio).floorToDouble() / ratio;
        // ⚠️A fresh key each pass, so the element cannot be reused: a
        // reused surface does not repaint, and a probe that silently
        // measures a stale one proves nothing.
        await tester.pumpWidget(
          surface(
            key: ValueKey<int>(i),
            left: snapped,
            size: _onGrid(ratio),
          ),
        );
        await tester.pump();
        expect(
          DeviceGridAudit.sweep().violations,
          isEmpty,
          reason: 'a snapped origin of $snapped reported as off-grid',
        );
      }
    });

    testWidgets('★orders by REAL misalignment, worst at half a pixel', (
      tester,
    ) async {
      // 🚨The first draft sorted on the raw fraction, so 0.9 outranked
      // 0.5 — it put nearly-aligned surfaces at the top of a "worst first"
      // list and would have aimed the quantization work at them. Phase is
      // cyclic: misalignment peaks at half a pixel.
      useRatio(tester, 1.25);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              for (final entry in <(String, double)>[
                ('nearly-aligned', 0.9 / 1.25), // device 0.9 → −0.1
                ('worst', 0.5 / 1.25), // device 0.5 → +0.5
                ('middling', 0.2 / 1.25), // device 0.2 → +0.2
              ])
                Positioned(
                  left: entry.$2,
                  top: 0,
                  width: 100,
                  height: 100,
                  child: StaticRaster(
                    debugLabel: entry.$1,
                    child: const ColoredBox(color: Color(0xFF112233)),
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(
        DeviceGridAudit.sweep().violations.map((v) => v.label),
        <String>['worst', 'middling', 'nearly-aligned'],
      );
    });
  });

  group('SIZE is half the failure', () {
    testWidgets('an on-grid origin with an off-grid size is a violation', (
      tester,
    ) async {
      // 🚨The first draft measured origins only and would have called this
      // clean. `_gridFit`'s own doc says a panel whose extent is not a
      // whole number of device pixels gets its whole bottom row wrong, and
      // that it "happens to EVERY panel at the 125%, 150% and 175%
      // display scalings Windows ships".
      useRatio(tester, 1.25);
      // 10.4 × 1.25 = 13.0 (on grid). 100.3 × 1.25 = 125.375 (not).
      await tester.pumpWidget(
        surface(left: 10.4, size: const Size(100.3, 100.3)),
      );
      await tester.pump();

      final report = DeviceGridAudit.sweep();
      expect(report.violations, hasLength(1));
      expect(report.violations.single.originPhase, Offset.zero);
      expect(report.violations.single.sizePhase.dx, closeTo(0.375, 1e-6));
      expect(report.violations.single.sizePhase.dy, closeTo(0.375, 1e-6));
    });

    testWidgets('both edges on the grid is clean', (tester) async {
      useRatio(tester, 1.25);
      await tester.pumpWidget(surface(left: 10.4));
      await tester.pump();

      // ⚠️The control that stops this whole file from being vacuous: if
      // the audit reported every surface, every other pin here would pass
      // while measuring nothing.
      final report = DeviceGridAudit.sweep();
      expect(report.violations, isEmpty);
      expect(report.onGrid, 1);
      expect(report.unmeasurable, 0);
    });
  });

  group('what it cannot measure is never called clean', () {
    testWidgets('a rotation counts as UNMEASURABLE, not as on-grid', (
      tester,
    ) async {
      useRatio(tester, 1.25);
      await tester.pumpWidget(
        surface(
          left: 10.3,
          wrap: (child) => Transform.rotate(angle: 0.3, child: child),
        ),
      );
      await tester.pump();

      final report = DeviceGridAudit.sweep();
      expect(report.violations, isEmpty);
      expect(report.unmeasurable, 1);
      expect(report.isClean, isFalse, reason: 'unmeasurable is not clean');
    });

    testWidgets('★a degenerate ratio does not earn a perfect score', (
      tester,
    ) async {
      // 🚨The trap `DeviceGrid.isActive`'s own doc warns about, written one
      // commit before this file and then walked into: every phase reads as
      // aligned on a broken ratio, so the first draft reported ZERO
      // violations on a tree where every surface was off the grid.
      useRatio(tester, 1.25);
      await tester.pumpWidget(
        EffectiveDevicePixelRatio(
          ratio: 0,
          child: surface(left: 10.3),
        ),
      );
      await tester.pump();

      final report = DeviceGridAudit.sweep();
      expect(report.onGrid, 0, reason: 'nothing may be certified here');
      expect(report.unmeasurable, 1);
      expect(report.isClean, isFalse);
    });

    testWidgets('a surface that does not paint is skipped, not reported', (
      tester,
    ) async {
      // Offstage skips painting its subtree outright, so the surface puts
      // no pixels on screen — and its layout is not settled either, which
      // makes the "violation" unfixable. Under strict it would throw every
      // frame for something nobody can act on.
      useRatio(tester, 1.25);
      await tester.pumpWidget(
        surface(left: 10.3, wrap: (child) => Offstage(child: child)),
      );
      await tester.pump();

      final report = DeviceGridAudit.sweep();
      expect(report.violations, isEmpty);
      expect(report.notPainting, 1);
    });
  });

  testWidgets('a detached surface leaves the census', (tester) async {
    useRatio(tester, 1.25);
    await tester.pumpWidget(surface(left: 10.3));
    await tester.pump();
    expect(DeviceGridAudit.sweep().violations, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // The registry is maintained by attach/detach, which is what makes it
    // an invariant nobody has to remember to join.
    final report = DeviceGridAudit.sweep();
    expect(report.violations, isEmpty);
    expect(report.notPainting, 0);
  });

  testWidgets('LIVENESS GATE — the UNFIXED workspace is off the grid at 1.25', (
    tester,
  ) async {
    // 🎯★★★If this ever goes green on its own, the audit has stopped
    // measuring and every later reading is worthless.
    //
    // ⛔DO NOT "invert this to isEmpty when quantization lands". That
    // instruction was in the first draft and it is a measured trap: of the
    // violations reported here, most are positioned by padding, by an
    // `Align`, and by running sums of MEASURED TEXT WIDTHS inside their
    // own panels — half the population moves when the text scale moves.
    // Chrome-boundary quantization does not touch any of that, so the list
    // cannot reach zero in PRs 3-7 and a future author following such an
    // instruction would watch it fail and then delete the gate.
    //
    // The honest contract is MONOTONE: the count falls, and the named
    // chrome members below leave. Emptiness becomes available only over a
    // filtered population, after the leaf work in PRs 8-10.
    useRatio(tester, 1.25, logical: const Size(1600, 1000));

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final report = DeviceGridAudit.sweep();
    expect(
      report.violations,
      isNotEmpty,
      reason:
          'The workspace has no quantization yet, so panels must be landing '
          'off the device grid. An empty list here means the audit is '
          'looking at nothing — check that StaticRaster.census is populated '
          'and that debugDeviceGridPhase can locate the surfaces.',
    );
    expect(
      report.unmeasurable,
      0,
      reason: 'every surface in the shell should be locatable',
    );
  });

  testWidgets('install() is idempotent and inert while strict is false', (
    tester,
  ) async {
    useRatio(tester, 1.25);
    DeviceGridAudit.install();
    DeviceGridAudit.install();

    await tester.pumpWidget(surface(left: 10.3));
    await tester.pump();

    expect(DeviceGridAudit.sweep().violations, isNotEmpty);
    // The frame still completed, because the check is off. The per-frame
    // cost while off is one bool.
    expect(tester.takeException(), isNull);
  });
}

/// A size that lands on whole device pixels at [ratio].
Size _onGrid(double ratio) {
  final side = (100 * ratio).roundToDouble() / ratio;
  return Size(side, side);
}

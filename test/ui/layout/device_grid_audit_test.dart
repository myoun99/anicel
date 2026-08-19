import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/layout/device_grid_audit.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The quantization audit, landed BEFORE the quantization.
///
/// 🎯An audit written after the fix reports zero on its first run and
/// nobody can tell whether that is because the layout is correct or
/// because the audit is looking at nothing. The liveness gate at the
/// bottom is the whole reason this file exists first.
///
/// ⚠️Fractional ratio throughout, and BOTH `devicePixelRatio` and
/// `physicalSize` are set — changing the ratio alone silently moves the
/// logical viewport, and `setSurfaceSize` (which the repo's other editor
/// harnesses use) desynchronises MediaQuery from the render tree and
/// builds a letterbox scale into the root, which would make every phase
/// this file measures meaningless.
void main() {
  setUp(DeviceGridAudit.debugReset);
  tearDown(DeviceGridAudit.debugReset);

  /// A window whose PHYSICAL size is integral, as a real one is.
  void useRatio(WidgetTester tester, double ratio, {Size logical = const Size(800, 600)}) {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = Size(
      logical.width * ratio,
      logical.height * ratio,
    );
    addTearDown(tester.view.reset);
  }

  Widget surfaceAt(double left, {String label = 'probe'}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: <Widget>[
        Positioned(
          left: left,
          top: 0,
          width: 100,
          height: 100,
          child: StaticRaster(
            debugLabel: label,
            child: const ColoredBox(color: Color(0xFF112233)),
          ),
        ),
      ],
    ),
  );

  group('sweep', () {
    testWidgets('reports a surface that begins mid-pixel', (tester) async {
      useRatio(tester, 1.25);
      // 10.4 logical × 1.25 = 13.0 device — on grid.
      // 10.3 logical × 1.25 = 12.875 device — 0.875 into its pixel.
      await tester.pumpWidget(surfaceAt(10.3));
      await tester.pump();

      final violations = DeviceGridAudit.sweep();
      expect(violations, hasLength(1));
      expect(violations.single.label, 'probe');
      expect(violations.single.phase.dx, closeTo(0.875, 1e-6));
      expect(violations.single.phase.dy, closeTo(0.0, 1e-6));
      expect(violations.single.worst, closeTo(0.875, 1e-6));
    });

    testWidgets('stays silent for a surface that begins on the grid', (
      tester,
    ) async {
      useRatio(tester, 1.25);
      await tester.pumpWidget(surfaceAt(10.4));
      await tester.pump();

      // ⚠️The control that stops this whole file from being vacuous: if
      // the audit reported every surface, the liveness gate below would
      // pass while measuring nothing.
      expect(DeviceGridAudit.sweep(), isEmpty);
    });

    testWidgets('finds the offender at every fractional ratio', (tester) async {
      for (final ratio in <double>[1.125, 1.25, 1.35, 1.5]) {
        useRatio(tester, ratio);
        // Half a device pixel in, whatever the ratio.
        await tester.pumpWidget(surfaceAt(0.5 / ratio));
        await tester.pump();
        final violations = DeviceGridAudit.sweep();
        expect(violations, hasLength(1), reason: 'ratio $ratio');
        expect(
          violations.single.phase.dx,
          closeTo(0.5, 1e-6),
          reason: 'ratio $ratio',
        );
      }
    });

    testWidgets('sorts the worst offender first', (tester) async {
      useRatio(tester, 1.25);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              for (final entry in <(String, double)>[
                ('mild', 0.2 / 1.25),
                ('worst', 0.9 / 1.25),
                ('middling', 0.5 / 1.25),
              ])
                Positioned(
                  left: entry.$2,
                  top: 0,
                  width: 40,
                  height: 40,
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
        DeviceGridAudit.sweep().map((v) => v.label),
        <String>['worst', 'middling', 'mild'],
      );
    });

    testWidgets('a detached surface leaves the census', (tester) async {
      useRatio(tester, 1.25);
      await tester.pumpWidget(surfaceAt(10.3));
      await tester.pump();
      expect(DeviceGridAudit.sweep(), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // The registry is maintained by attach/detach, which is what makes
      // it an invariant nobody has to remember to join.
      expect(DeviceGridAudit.sweep(), isEmpty);
    });
  });

  testWidgets('LIVENESS GATE — the UNFIXED workspace is off the grid at 1.25', (
    tester,
  ) async {
    // 🎯★★★If this ever goes green on its own, the audit has stopped
    // measuring and every later "violations is empty" is worthless.
    //
    // It is asserted the wrong way round on purpose: right now the app
    // HAS no quantization, so a correct audit must find offenders. When
    // the quantization PRs land, this expectation flips to isEmpty and
    // the flip is the evidence that the round did something. ⛔Do not
    // delete it then — invert it, so the file keeps a record of what it
    // used to see.
    useRatio(tester, 1.25, logical: const Size(1600, 1000));

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final violations = DeviceGridAudit.sweep();
    expect(
      violations,
      isNotEmpty,
      reason:
          'The workspace has no quantization yet, so panels must be landing '
          'off the device grid. An empty list here means the audit is '
          'looking at nothing — check that StaticRaster.census is populated '
          'and that debugDeviceGridPhase can locate the surfaces.',
    );
  });

  testWidgets('install() is idempotent and inert while strict is false', (
    tester,
  ) async {
    useRatio(tester, 1.25);
    DeviceGridAudit.install();
    DeviceGridAudit.install();

    await tester.pumpWidget(surfaceAt(10.3));
    await tester.pump();

    // Violations exist...
    expect(DeviceGridAudit.sweep(), isNotEmpty);
    // ...and the frame still completed, because the check is off. The
    // per-frame cost while off is one bool, which is what the debug
    // performance bar and the old-tablet rule require.
    expect(tester.takeException(), isNull);
  });
}

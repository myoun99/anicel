import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../widgets/static_raster.dart';
import 'device_grid.dart';

/// One surface that does not sit on the device-pixel grid.
@immutable
class DeviceGridViolation {
  const DeviceGridViolation({
    required this.label,
    required this.origin,
    required this.size,
    required this.originPhase,
    required this.sizePhase,
  });

  /// The surface's debug label. ⚠️NOT unique — `command-group` appears six
  /// times in this app's census, two of them with an identical phase,
  /// which is why [origin] and [size] are carried too. A diagnostic that
  /// cannot name which of six is wrong sends the reader hunting.
  final String label;

  /// Global logical position and extent, for identifying which one.
  final Offset origin;
  final Size size;

  /// Signed distance from the nearest gridline, per axis, in DEVICE
  /// pixels — always in `[-0.5, 0.5]`, worst at ±0.5.
  final Offset originPhase;

  /// The same for the far edge. An on-grid origin with an off-grid size
  /// still resamples the whole bottom row.
  final Offset sizePhase;

  /// The largest single misalignment across both axes and both edges,
  /// which is what a reader wants to sort by.
  double get worst {
    var worst = 0.0;
    for (final value in <double>[
      originPhase.dx,
      originPhase.dy,
      sizePhase.dx,
      sizePhase.dy,
    ]) {
      if (value.abs() > worst) {
        worst = value.abs();
      }
    }
    return worst;
  }

  @override
  String toString() =>
      '$label at (${origin.dx.toStringAsFixed(1)}, '
      '${origin.dy.toStringAsFixed(1)}) '
      '${size.width.toStringAsFixed(1)}×${size.height.toStringAsFixed(1)} — '
      'origin off by (${originPhase.dx.toStringAsFixed(3)}, '
      '${originPhase.dy.toStringAsFixed(3)}), '
      'size off by (${sizePhase.dx.toStringAsFixed(3)}, '
      '${sizePhase.dy.toStringAsFixed(3)}) device px';
}

/// What one sweep saw.
@immutable
class DeviceGridReport {
  const DeviceGridReport({
    required this.violations,
    required this.onGrid,
    required this.unmeasurable,
    required this.notPainting,
  });

  /// Off-grid surfaces, worst first.
  final List<DeviceGridViolation> violations;

  /// Surfaces that were measured and found aligned.
  final int onGrid;

  /// 🚨Surfaces that could NOT be measured — detached, rotated, mirrored,
  /// per-axis scaled, or sitting under a degenerate ratio.
  ///
  /// Counted separately and never folded into "no violation". The first
  /// draft folded them, which meant a tree under a broken ratio reported
  /// **zero violations while every surface was off the grid** — the exact
  /// trap `DeviceGrid.isActive`'s own doc warns about, written one commit
  /// earlier and then walked into.
  final int unmeasurable;

  /// Surfaces in the census that did not paint, so were skipped.
  final int notPainting;

  bool get isClean => violations.isEmpty && unmeasurable == 0;

  @override
  String toString() =>
      '${violations.length} off grid, $onGrid on grid, '
      '$unmeasurable unmeasurable, $notPainting not painting';
}

/// Checks that panel surfaces sit on whole device pixels.
///
/// 🎯**This exists BEFORE the thing it checks.** An audit written after the
/// fix reports zero on its first run and nobody can tell whether that is
/// because the layout is correct or because the audit is looking at
/// nothing. Landing it first makes the question answerable.
///
/// The subject is [StaticRaster.census], a registry nobody has to remember
/// to join: `attach` adds every panel and `detach` removes it.
///
/// ⚠️**What it does NOT cover, measured.** The census is 15 surfaces in
/// this app, against 67 compositing boundaries in the workspace. And of
/// the 12 violations it reports at ratio 1.25, **nine survive a perfect
/// chrome quantization** — they are positioned by padding, by an `Align`,
/// and by running sums of measured text widths inside their own panels,
/// none of which the chrome chain touches. Half the population moves when
/// the text scale moves. ⛔So "the violation list is empty" is NOT
/// available as a success condition for the chrome PRs, and a gate
/// written that way is a trap. The honest contract is monotone: the count
/// falls, and named members leave.
///
/// ✅**The coupling this paragraph used to warn about is closed.** It read:
/// the phase is computed from `EffectiveDevicePixelRatio` (monitor × UI
/// scale) while the root matrix still uses the raw view ratio, "because no
/// `createViewConfigurationFor` override exists yet", so the two coincide
/// only at a scale of 1.0. `AnicelBinding` now multiplies the scale into
/// the root matrix, so the phase measured here IS the compositor's.
///
/// ⛔The warning behind it stands, which is why the paragraph is kept:
/// measured with the two deliberately mismatched, this audit reported a
/// violation of 0.70 on a genuinely on-grid surface and 0.5875 on one
/// whose true phase was 0.875 — **both numbers wrong**. Anything that
/// changes where the root matrix's ratio comes from has to move this
/// source with it, or the audit reports confident nonsense.
abstract final class DeviceGridAudit {
  /// Device pixels within which a surface counts as aligned. Same value
  /// [DeviceGrid.isOnGrid] uses — ⛔the two definitions of "on grid" must
  /// not drift apart, or the audit calls the quantizer's own output wrong.
  static const double tolerance = 1e-3;

  /// When true, a frame that ends with violations throws in debug builds.
  ///
  /// ⛔Stays false until quantization has landed. Turning it on while the
  /// tree is known to violate would make every debug session unusable and
  /// teach everyone to switch it off, which is worse than not having it.
  static bool strict = false;

  /// Measures every painting surface in the census.
  ///
  /// ⚠️Reads the CURRENT transforms, so it means nothing until layout has
  /// settled. Call it from a post-frame callback or a settled test.
  static DeviceGridReport sweep() {
    final violations = <DeviceGridViolation>[];
    var onGrid = 0;
    var unmeasurable = 0;
    var notPainting = 0;

    for (final raster in StaticRaster.census) {
      if (!raster.debugHasPainted || !raster.hasSize) {
        notPainting += 1;
        continue;
      }
      // isActive FIRST: on a degenerate ratio every phase would read as
      // aligned and the audit would hand out a perfect score.
      if (!DeviceGrid(raster.devicePixelRatio).isActive) {
        unmeasurable += 1;
        continue;
      }
      final originPhase = raster.debugDeviceGridPhase;
      final sizePhase = raster.debugDeviceGridSizePhase;
      if (originPhase == null || sizePhase == null) {
        unmeasurable += 1;
        continue;
      }
      final aligned =
          originPhase.dx.abs() < tolerance &&
          originPhase.dy.abs() < tolerance &&
          sizePhase.dx.abs() < tolerance &&
          sizePhase.dy.abs() < tolerance;
      if (aligned) {
        onGrid += 1;
        continue;
      }
      violations.add(
        DeviceGridViolation(
          label: raster.debugLabel,
          origin: raster.localToGlobal(Offset.zero),
          size: raster.size,
          originPhase: originPhase,
          sizePhase: sizePhase,
        ),
      );
    }

    violations.sort((a, b) => b.worst.compareTo(a.worst));
    return DeviceGridReport(
      violations: violations,
      onGrid: onGrid,
      unmeasurable: unmeasurable,
      notPainting: notPainting,
    );
  }

  static bool _installed = false;

  /// Arms the per-frame check. Idempotent, and inert until [strict].
  ///
  /// ⚠️The walk is skipped entirely while [strict] is false, so the cost
  /// on an ordinary debug session is one bool per frame — the debug
  /// performance bar and the old-tablet rule both forbid a census walk
  /// that runs unconditionally.
  static void install() {
    assert(() {
      if (_installed) {
        return true;
      }
      _installed = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (!strict) {
          return;
        }
        final report = sweep();
        if (report.isClean) {
          return;
        }
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Surfaces are off the device-pixel grid: $report'),
          ErrorDescription(
            'Every offset the app chooses must be an integral count of '
            'device pixels, or the surfaces below it inherit the '
            'fraction. Quantize the boundary that positions these.',
          ),
          ...report.violations.take(10).map((v) => ErrorHint('· $v')),
          if (report.violations.length > 10)
            ErrorHint('· …and ${report.violations.length - 10} more'),
          if (report.unmeasurable > 0)
            ErrorHint(
              '· ${report.unmeasurable} surface(s) could not be measured '
              'at all — a rotation, a per-axis scale, or a degenerate '
              'ratio. Those are not "clean".',
            ),
        ]);
      });
      return true;
    }());
  }

  /// Test-only: puts the flag back so one test cannot arm the next one.
  ///
  /// ⛔It deliberately does NOT clear `_installed`. A persistent frame
  /// callback cannot be removed, so re-installing would stack a second
  /// copy for the life of the process.
  @visibleForTesting
  static void debugReset() {
    strict = false;
  }
}

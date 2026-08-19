import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../widgets/static_raster.dart';

/// One surface whose origin does not begin on a whole device pixel.
@immutable
class DeviceGridViolation {
  const DeviceGridViolation({required this.label, required this.phase});

  /// The surface's debug label, or a placeholder when it has none.
  final String label;

  /// How far into its device pixel the surface begins, per axis, in
  /// DEVICE pixels. Never zero — a zero phase is not a violation.
  final Offset phase;

  /// The worse of the two axes, which is what a reader wants to sort by.
  double get worst =>
      phase.dx.abs() > phase.dy.abs() ? phase.dx.abs() : phase.dy.abs();

  @override
  String toString() =>
      '$label off the grid by '
      '(${phase.dx.toStringAsFixed(3)}, ${phase.dy.toStringAsFixed(3)}) '
      'device px';
}

/// Checks that panel surfaces begin on whole device pixels.
///
/// 🎯**This exists BEFORE the thing it checks.** An audit written after the
/// fix reports zero on its first run and nobody can tell whether that is
/// because the layout is correct or because the audit is looking at
/// nothing. Landing it first makes the question answerable: on the
/// unfixed tree at a fractional ratio it MUST report violations, and there
/// is a test that says so ([[device_grid_audit_test]]'s liveness gate).
/// When quantization lands, the same list going empty is evidence.
///
/// The subject is [StaticRaster.census], which is a registry nobody has to
/// remember to join: `RenderStaticRaster.attach` adds every panel and
/// `detach` removes it. So a panel added in six months is audited by
/// existing, which is the only kind of invariant that stays true.
abstract final class DeviceGridAudit {
  /// When true, a frame that ends with violations throws in debug builds.
  ///
  /// ⛔Stays false until quantization has actually landed. Turning it on
  /// while the tree is known to violate would make every debug session
  /// unusable and teach everyone to switch it off, which is worse than not
  /// having it.
  static bool strict = false;

  /// Every surface currently off the grid, worst first.
  ///
  /// ⚠️Reads the CURRENT transforms, so it means nothing until layout has
  /// settled. Call it from a post-frame callback or a settled test.
  static List<DeviceGridViolation> sweep() {
    final found = <DeviceGridViolation>[];
    for (final raster in StaticRaster.census) {
      final phase = raster.debugDeviceGridPhase;
      if (phase == null || (phase.dx == 0 && phase.dy == 0)) {
        continue;
      }
      found.add(
        DeviceGridViolation(label: raster.debugLabel, phase: phase),
      );
    }
    found.sort((a, b) => b.worst.compareTo(a.worst));
    return found;
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
        final violations = sweep();
        if (violations.isEmpty) {
          return;
        }
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            '${violations.length} surface(s) do not begin on a whole '
            'device pixel.',
          ),
          ErrorDescription(
            'Every offset the app chooses must be an integral count of '
            'device pixels, or the surfaces below it inherit the '
            'fraction. Quantize the boundary that positions these.',
          ),
          ...violations.take(10).map((v) => ErrorHint('· $v')),
          if (violations.length > 10)
            ErrorHint('· …and ${violations.length - 10} more'),
        ]);
      });
      return true;
    }());
  }

  /// Test-only: puts the flag back so one test cannot arm the next one.
  ///
  /// ⛔It deliberately does NOT clear `_installed`. A persistent frame
  /// callback cannot be removed, so re-installing would stack a second
  /// copy for the life of the process — the same duplicate-registration
  /// trap `FrameStats.install` documents at the top of `main`.
  @visibleForTesting
  static void debugReset() {
    strict = false;
  }
}

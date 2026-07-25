import 'package:flutter/foundation.dart';

/// The app's MEASUREMENT switches — the diagnosis overlays, in one place.
///
/// This is the second of them. The first is the pen program's
/// `InputInspector` (Edit ▸ Input Inspector), and they answer different
/// questions about the same session: the inspector says what the platform
/// DELIVERED, this says what the app did with the frame it had. Both are
/// static [ValueNotifier]s toggled from Edit, both inert until asked for.
abstract final class MeasurementMode {
  /// Flutter's frame-timing overlay (Edit ▸ Frame Timing Overlay): two
  /// graphs over the app, the UI thread (build/layout/paint — the Dart
  /// work) above the RASTER thread (turning the recorded picture into
  /// pixels). Each bar is a frame; the line across them is the display's
  /// frame budget, so bars crossing it are the jank.
  ///
  /// Read it while DOING the thing — Flutter renders on demand, so an
  /// idle app sitting at 0fps is not a finding. What it is for: the three
  /// canvas workloads want opposite things from the frame clock and only
  /// measurement separates them — a stroke wants the lowest latency at
  /// the display's full rate (120Hz on ProMotion, which
  /// `CADisableMinimumFrameDurationOnPhone` in ios/Runner/Info.plist
  /// unlocks), playback wants exactly the cel rate and nothing more, and
  /// a scrub wants no re-raster of cels it already holds.
  ///
  /// A TOGGLE and not just a build flag because flipping a `--dart-define`
  /// on a tablet costs a full rebuild and reinstall — useless for "watch
  /// this one stroke". The define below only seeds the starting value, so
  /// a run can still start with it on.
  ///
  /// Orthogonal to `--profile`: this decides what is DRAWN, the build mode
  /// decides what is MEASURED. In a debug build these are debug-build
  /// frame times, which is this project's performance bar; `flutter run
  /// --profile` gives near-release numbers and the DevTools timeline to
  /// take a bottleneck apart once the overlay says which thread lost.
  static final ValueNotifier<bool> frameTimingOverlay = ValueNotifier<bool>(
    startWithFrameTimingOverlay,
  );

  /// Seeds [frameTimingOverlay] so a measurement run can start with the
  /// graphs already up:
  ///
  /// ```
  /// flutter run --profile --dart-define=QA_PERF_OVERLAY=true
  /// ```
  ///
  /// False in every ordinary build, pinned by a test — an overlay left on
  /// ships two graphs across the user's canvas.
  static const bool startWithFrameTimingOverlay = bool.fromEnvironment(
    'QA_PERF_OVERLAY',
  );

  /// Test hygiene: back to the build's own defaults.
  @visibleForTesting
  static void reset() {
    frameTimingOverlay.value = startWithFrameTimingOverlay;
  }
}

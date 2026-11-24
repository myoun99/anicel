import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// The app's MEASUREMENT switches: the debug window, and the repaint tint
/// it carries in its head. Static [ValueNotifier]s toggled from the top
/// strip's SETTINGS popover, inert until asked for.
///
/// 🗣️유저 2026-11-24 (card one-debug-window-shows-everything Q2, 「결정은
/// 다 권고대로」): ONE switch — the input inspector, the frame statistics,
/// the engine's stages and the frame-timing graphs were four, and the user
/// had to know which to turn on, while a photo of one held a quarter of
/// what a question needed.
///
/// ⚠️These used to say "Edit ▸", and the Edit menu has not existed since
/// the seven-menu bar was replaced by the top strip — every command it
/// carried moved to the surface that shows its result. A stale path in a
/// doc comment is worse than none: it sent a reader looking for a menu
/// that is not there, which has already cost one round.
abstract final class MeasurementMode {
  /// The debug window (Settings ▸ Debug ▸ Debug Window): what the platform
  /// delivered, what the app did with each frame, what the engine took
  /// place by place, and what memory the app holds — on one screen, every
  /// sum with its parts and the rest. See `DebugWindow`.
  ///
  /// It is also the gate of what only it reads: the frame statistics'
  /// window, the strokes' steps, the pictures' writes, the repaint causes,
  /// the pointer's clock and the engine's timing all collect while it is
  /// up, and none of them costs a thing while it is down.
  ///
  /// ★Numbers, not graphs alone — three reasons the frame statistics stood
  /// beside Flutter's own graphs, and stand in their place now:
  ///
  ///  * **Percentiles.** A graph's max and average read the same for a
  ///    flat cost and a RISING one, which is the exact shape of "it gets
  ///    worse as I keep working"; a max is a single frame.
  ///  * **Latency.** `FrameTiming.totalSpan` is the whole pipeline for
  ///    one frame, and Flutter pipelines — build and raster can both sit
  ///    inside budget while the end-to-end span runs long, which is what
  ///    "smooth but the pen feels behind" is made of.
  ///  * **Retained raster.** `layerCacheCount`/`pictureCacheCount` are
  ///    the only way from Dart to see whether a repaint boundary bought
  ///    anything on the GPU.
  ///
  /// 🪦Flutter's frame-timing overlay was a switch of its own till
  /// 2026-11-24 (Q2: 「Flutter 그래프는 창 그래프가 대신」) — two full-width
  /// graphs redrawn every frame INSIDE the scene whose raster time they
  /// reported, part of their own measurement. The window's graph draws
  /// the same frames from their timings.
  ///
  /// 🪦So were the engine's stages (till 2026-11-24): a timed engine waits
  /// for nothing to be timed (rust/src/took.rs), so the frames the window
  /// reads are the same with them on — ↩️till 2026-11-23 it waited out
  /// each submit, which was the reason they had a switch apart.
  static final ValueNotifier<bool> debugWindow = ValueNotifier<bool>(
    startWithDebugWindow,
  );

  /// Tints a surface every time it is BAKED (Settings ▸ Show Repaints).
  ///
  /// The tint two mature apps decided they could not
  /// ship without: Krita carries `KisRepaintDebugger` in production and
  /// paints it at the end of `paintGL`; Blender tints every drawn region
  /// a random colour under `G.debug_value == 888`, commented "for
  /// debugging unneeded area redraws and partial redraw".
  ///
  /// The reason is the one this program keeps rediscovering: **a panel
  /// paying full price looks exactly like a free one.** The standing
  /// report says which panels bake; this says WHEN, while you work. A
  /// surface that flickers as you move the pen is re-baking on your
  /// pointer, and no amount of reading finds that as fast as seeing it.
  ///
  /// The tint cycles per bake, so a surface baking every frame strobes
  /// and one that baked once sits still.
  static final ValueNotifier<bool> showRepaints = ValueNotifier<bool>(
    startWithShowRepaints,
  );

  /// The tint a surface drawn from an image wears under [showRepaints],
  /// picked by how many images it has had — the cycle above.
  static Color repaintTint(int imagesTaken) =>
      _repaintTints[imagesTaken % _repaintTints.length];

  static const List<Color> _repaintTints = <Color>[
    Color(0x3300E5FF),
    Color(0x33FF4081),
    Color(0x33FFEA00),
    Color(0x3300E676),
  ];

  /// Seeds [showRepaints]:
  ///
  /// ```
  /// flutter run --dart-define=QA_SHOW_REPAINTS=true
  /// ```
  static const bool startWithShowRepaints = bool.fromEnvironment(
    'QA_SHOW_REPAINTS',
  );

  /// Seeds [debugWindow]:
  ///
  /// ```
  /// flutter run --dart-define=QA_DEBUG_WINDOW=true
  /// ```
  ///
  /// False in every ordinary build, pinned by a test — a window left on
  /// ships the instruments across the user's canvas.
  static const bool startWithDebugWindow = bool.fromEnvironment(
    'QA_DEBUG_WINDOW',
  );

  /// Test hygiene: back to the build's own defaults.
  @visibleForTesting
  static void reset() {
    debugWindow.value = startWithDebugWindow;
    showRepaints.value = startWithShowRepaints;
  }
}
